#!/usr/bin/perl
# One batch renderer for the first base-installer hook. Use perl-base modules
# only: neither full Perl, Python, CPAN nor a configured target APT is required.
use strict;
use warnings;
use bytes;
use Fcntl qw(O_RDONLY O_WRONLY O_CREAT O_EXCL O_NOFOLLOW O_NONBLOCK :mode);
use File::Temp qw(tempdir tempfile);
use IO::Handle ();

use constant FILE_LIMIT => 16 * 1024 * 1024;
use constant BYTE_LIMIT => 256 * 1024 * 1024;
use constant MEMBER_LIMIT => 10000;
use constant ENTRY_LIMIT => 20000;

sub fail { die "$_[0]\n"; }
sub relative {
    my ($path) = @_;
    defined($path) && length($path) <= 4096 && $path =~ m{\A[A-Za-z0-9_./\@+ -]+\z}
        && $path !~ m{\A/|(?:\A|/)(?:\.?\.?)(?:/|\z)}
        or fail('invalid relative source selector');
    return $path;
}
sub absolute {
    my ($path) = @_;
    defined($path) && $path =~ m{\A/[A-Za-z0-9_./\@+ -]*\z}
        && length($path) <= 4096 && ($path eq '/' || $path !~ m{/$})
        && $path !~ m{(?:\A|/)(?:\.|\.\.)(?:/|\z)|//}
        or fail('invalid absolute publication path');
    return $path;
}
sub parent_path { my ($path) = @_; $path =~ s{/[^/]+\z}{}; return length($path) ? $path : '/'; }
sub same_metadata {
    my ($left, $right) = @_;
    for my $index (0, 1, 2, 3, 4, 5, 7, 9, 10) {
        $left->[$index] == $right->[$index] or fail('input identity changed while reading');
    }
}
sub regular_metadata {
    my ($info, $maximum) = @_;
    @$info && S_ISREG($info->[2]) && $info->[3] == 1 && $info->[4] == $>
        && !($info->[2] & 0022) && $info->[7] >= 0 && $info->[7] <= $maximum
        or fail('unsafe or excessive regular input');
}
sub read_regular {
    my ($path, $maximum) = @_;
    $maximum //= FILE_LIMIT;
    sysopen(my $stream, $path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        or fail('cannot open regular render input');
    binmode($stream) or fail('cannot read render input as bytes');
    my @before = stat($stream);
    regular_metadata(\@before, $maximum);
    my $data = '';
    while (1) {
        my $count = sysread($stream, my $part, 65536);
        defined($count) or fail('cannot read render input');
        last unless $count;
        $data .= $part;
        length($data) <= $maximum or fail('render input exceeds byte limit');
    }
    my @after = stat($stream);
    same_metadata(\@before, \@after);
    length($data) == $before[7] or fail('render input changed length');
    close($stream) or fail('cannot close render input');
    return $data;
}
sub write_file {
    my ($path, $data, $replace, $mode, $policy) = @_;
    length($data) <= FILE_LIMIT or fail('render output exceeds byte limit');
    my @before;
    if ($replace) {
        @before = lstat($path);
        regular_metadata(\@before, FILE_LIMIT);
        $mode //= $before[2] & 0777;
    } else {
        !lstat($path) or fail('refusing to replace existing render output');
    }
    # A write failure or interruption must leave the previous candidate bytes
    # intact. Stage beside the destination, then recheck identities before the
    # single rename. New files use an exclusive link to avoid an overwrite race.
    my $parent = parent_path($path);
    directory($parent, 0, 0, $policy);
    my @parent_before = lstat($parent);
    my ($stream, $temporary) = tempfile('.render-XXXXXX', DIR => $parent, UNLINK => 0);
    my $error;
    eval {
        binmode($stream) or fail('cannot write render output as bytes');
        my $offset = 0;
        while ($offset < length($data)) {
            my $count = syswrite($stream, $data, length($data) - $offset, $offset);
            defined($count) && $count > 0 or fail('cannot write render output');
            $offset += $count;
        }
        if ($policy) {
            chown(0, 0, $temporary) == 1 or fail('cannot set publication ownership');
        }
        chmod($mode // 0600, $stream) == 1 or fail('cannot set render output mode');
        close($stream) or fail('cannot close render output');
        directory($parent, 0, 0, $policy);
        my @parent_after = lstat($parent);
        for my $index (0, 1, 2, 4, 5) {
            $parent_before[$index] == $parent_after[$index]
                or fail('render output parent identity changed');
        }
        if ($replace) {
            my @after = lstat($path);
            regular_metadata(\@after, FILE_LIMIT);
            same_metadata(\@before, \@after);
            rename($temporary, $path) or fail('cannot publish render output');
        } else {
            link($temporary, $path) or fail('cannot publish exclusive render output');
            unlink($temporary) == 1 or fail('cannot remove linked render output stage');
        }
        1;
    } or $error = $@ || "unknown output publication failure\n";
    if (defined($error)) {
        close($stream) if defined(fileno($stream));
        unlink($temporary) or fail('cannot remove failed render output stage') if -e $temporary;
        die $error;
    }
}
sub value_map {
    my ($path) = @_;
    my %values;
    for my $line (split /\n/, read_regular($path, 1024 * 1024)) {
        $line =~ /\A([A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*)=([^\0\r]*)\z/ or fail('malformed render-map row');
        my ($key, $value) = ($1, $2);
        !exists($values{$key}) or fail('duplicate render-map key');
        if ($key =~ /\APATH_(?:DIR_|FILE_)/) {
            length($value) && $value =~ m{\A/[A-Za-z0-9_./\@+ -]*\z}
                && ($value eq '/' || $value !~ m{/$})
                && $value !~ m{(?:\A|/)(?:\.|\.\.)(?:/|\z)|//}
                or fail('invalid normalized path render-map value');
        } elsif ($key =~ /\AAPPARMOR_PROFILE_/) {
            $value =~ /\A[A-Za-z0-9_.-]+\z/ or fail('invalid AppArmor profile render-map value');
        } elsif ($key eq 'GITBUILD_DISTRIBUTION') {
            $value =~ /\A[a-z][a-z0-9.-]*\z/ or fail('invalid distribution render-map value');
        }
        $values{$key} = $value;
    }
    return \%values;
}
sub mapped {
    my ($values, $key) = @_;
    exists($values->{$key}) or fail('missing render field: ' . $key);
    return $values->{$key};
}
sub path_bytes {
    my ($data, $values) = @_;
    # The canonical runtime map also owns suite policy. Resolve it in this
    # same pass, including files whose only token is the GitBuild suite.
    $data =~ s{__INSTALLER_(PATH_[A-Z0-9]+(?:_[A-Z0-9]+)*|APPARMOR_PROFILE_[A-Z0-9]+(?:_[A-Z0-9]+)*|GITBUILD_DISTRIBUTION)__}{mapped($values, $1)}eg;
    return $data;
}
sub scalar_bytes {
    my ($data, $values) = @_;
    $data =~ s{__INSTALLER_([A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*)__}{mapped($values, $1)}eg;
    return $data;
}
sub scalar_token_map {
    my ($values) = @_;
    my %tokens;
    for my $name (keys %$values) {
        for my $token ('__' . $name . '__', '__INSTALLER_' . $name . '__') {
            !exists($tokens{$token}) or fail('duplicate exact scalar token owner: ' . $token);
            $tokens{$token} = $values->{$name};
        }
    }
    return \%tokens;
}
sub snapshot_values {
    my ($path) = @_;
    my @lines = split /\n/, read_regular($path, 1024 * 1024), -1;
    pop @lines if @lines && $lines[-1] eq '';
    @lines && pop(@lines) eq '__INSTALLER_DATA_END__' && @lines % 2 == 0
        or fail('invalid prepared profile snapshot records');
    my (%values, %seen);
    while (@lines) {
        my ($key, $value) = splice(@lines, 0, 2);
        $key =~ /\A[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*\z/ && !$seen{$key}++
            or fail('invalid or duplicate prepared profile field');
        # Secrets and installer/repository authority never become generic
        # target configuration. Their explicit typed consumers retain ownership.
        next if $key =~ /(?:PASSWORD|PASSPHRASE|SECRET|TOKEN|PSK)/
            || $key =~ /\A(?:(?:DIR|FILE)_INSTALLER_|TARGET_ROOT\z|(?:DIR|FILE)_REPO_)/;
        $values{$key} = $value;
    }
    return \%values;
}
sub known_scalar_bytes {
    my ($data, $tokens) = @_;
    # Construct exact aliases once, including legacy fields whose own names
    # start INSTALLER_. Never infer a token name by stripping a prefix.
    $data =~ s{__[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*__}{
        exists($tokens->{$&}) ? $tokens->{$&} : $&
    }eg;
    return $data;
}
sub module_bytes {
    my ($data, $values) = @_;
    for my $name (qw(INITRAMFS_PLATFORM_MODULES GRAPHICS_INITRAMFS_MODULES VFIO_INITRAMFS_MODULES VIRT_HOST_INITRAMFS_MODULES)) {
        next unless exists($values->{$name});
        my (%seen, @modules);
        for my $module (split /\s+/, $values->{$name} // '') {
            next unless length($module);
            $module =~ /\A[A-Za-z0-9_][A-Za-z0-9_-]*\z/ or fail('invalid module name in ' . $name);
            push @modules, $module unless $seen{$module}++;
        }
        my $block = join('', map { "$_\n" } @modules);
        $data =~ s{^[\t ]*__(?:INSTALLER_)?\Q$name\E__[\t ]*(?:\n|\z)}{$block}mg;
    }
    return $data;
}
sub module_map {
    my ($path) = @_;
    my (%values, $active);
    for my $line (split /\n/, read_regular($path, 65536)) {
        if ($line =~ /\A([A-Z][A-Z0-9_]*)=(.*)\z/) {
            my ($name, $value) = ($1, $2);
            $name =~ /\A(?:INITRAMFS_PLATFORM|GRAPHICS_INITRAMFS|VFIO_INITRAMFS|VIRT_HOST_INITRAMFS)_MODULES\z/
                && !exists($values{$name}) or fail('unknown or duplicate module block');
            $active = $name;
            $values{$name} = $value;
        } else {
            defined($active) && $line =~ /\A[A-Za-z0-9_\t -]*\z/
                or fail('malformed module block continuation');
            $values{$active} .= "\n" . $line;
        }
    }
    return \%values;
}
sub fstab_bytes {
    my ($data, $records) = @_;
    my (@rows, %widths);
    my ($section, $count) = (0, 0);
    for my $line (split /\n/, $records) {
        next if $line =~ /\A\s*\z/;
        @rows < 4096 && length($line) <= 16384 && index($line, "\0") < 0
            or fail('excessive or invalid filesystem record');
        if ($line =~ /\A\s*#/) {
            push @rows, [$line];
            ++$section;
            next;
        }
        my @fields = split ' ', $line;
        @fields == 6 && $fields[4] =~ /\A[01]\z/ && $fields[5] =~ /\A[012]\z/
            or fail('filesystem records require six valid fields');
        for my $index (0 .. 4) {
            $widths{$section}[$index] = length($fields[$index])
                if length($fields[$index]) > ($widths{$section}[$index] // 0);
        }
        push @rows, [$section, \@fields];
        ++$count;
    }
    $count or fail('empty filesystem table');
    my $block = '';
    for my $row (@rows) {
        if (@$row == 1) { $block .= $row->[0] . "\n"; next; }
        my ($group, $fields) = @$row;
        $block .= sprintf('%-' . $widths{$group}[$_] . 's  ', $fields->[$_]) for 0 .. 4;
        $block .= $fields->[5] . "\n";
    }
    my $replacements = ($data =~ s{^__INSTALLER_FSTAB_RECORDS__(?:\n|\z)}{$block}mg);
    $replacements == 1 or fail('fstab requires exactly one declared record block');
    return $data;
}
sub apparmor_modes_bytes {
    my ($data, $values) = @_;
    keys(%$values) == 1 or fail('AppArmor mode policy requires one state owner');
    my $selected = mapped($values, 'DESKTOP_APPARMOR_STATE');
    $selected =~ /\A(?:enforce|complain)\z/ or fail('invalid desktop AppArmor state');
    my (%seen, $rows, $hardware, $incus, $veth, $result);
    ($rows, $hardware, $incus, $veth, $result) = (0, 0, 0, 0, '');
    for my $line (split /(?<=\n)/, $data) {
        if ($line =~ /\A\s*(?:#|\z)/) {
            $line =~ s/__DESKTOP_APPARMOR_STATE__/$selected/g;
            $result .= $line;
            next;
        }
        my @fields = split ' ', $line;
        @fields == 4 or fail('AppArmor mode policy requires four fields');
        my ($state, $requirement, $profile, $executable) = @fields;
        $requirement =~ /\A(?:required|optional|if-executable)\z/
            && $profile =~ /\A[A-Za-z0-9._+-]+\z/
            && ($requirement eq 'if-executable' ? $executable =~ m{\A/} : $executable eq '-')
            && !$seen{$profile}++ or fail('invalid or duplicate AppArmor mode record');
        if ($profile eq 'hardware-tuning' || $profile eq 'incus-host' || $profile eq 'incus-desktop-ui') {
            $state eq 'enforce' && $requirement eq 'optional' && $executable eq '-'
                or fail('fixed AppArmor profile must remain enforced');
            $profile eq 'hardware-tuning' ? ++$hardware : ++$incus;
        } elsif ($profile eq 'app-veth') {
            $state eq 'enforce' && $requirement eq 'required' && $executable eq '-'
                or fail('app-veth AppArmor profile must remain enforced');
            ++$veth;
        } else {
            $state eq '__DESKTOP_APPARMOR_STATE__' or fail('unowned desktop AppArmor state');
            $fields[0] = $selected;
        }
        $result .= join(' ', @fields) . "\n";
        ++$rows;
    }
    $rows && $hardware == 1 && $incus == 2 && $veth == 1
        or fail('AppArmor mode policy lacks its fixed profile records');
    return $result;
}
sub render_file {
    my ($root, $kind) = @_;
    directory($root, 0, 1);
    my $data = read_regular("$root/input");
    my $result;
    if ($kind eq 'literal' || $kind eq 'line' || $kind eq 'line-optional') {
        my $token = read_regular("$root/map", 4096);
        $token =~ /\A__[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*__\z/
            or fail('invalid literal render token');
        my $value = read_regular("$root/value");
        if ($kind eq 'line' || $kind eq 'line-optional') {
            my $block = length($value) ? $value . ($value =~ /\n\z/ ? '' : "\n") : '';
            my $count = ($data =~ s{^\Q$token\E(?:\n|\z)}{$block}mg);
            $count || index($data, $token) < 0 or fail('declared block token must occupy its own line');
            ($count == 1 || $kind eq 'line-optional' && $count == 0)
                or fail('declared line block must occur exactly once');
            $result = $data;
        } else {
            $result = join($value, split(/\Q$token\E/, $data, -1));
        }
    } elsif ($kind eq 'apparmor-modes') {
        $result = apparmor_modes_bytes($data, value_map("$root/map"));
    } elsif ($kind eq 'fstab') {
        $result = fstab_bytes($data, read_regular("$root/map"));
    } elsif ($kind eq 'theme' || $kind eq 'appearance') {
        my $values = value_map("$root/map");
        my $target = relative(read_regular("$root/target", 4096));
        $result = theme_bytes($data, $values, $target, $kind eq 'appearance');
    } elsif ($kind eq 'scalar' || $kind eq 'resources' || $kind eq 'modules') {
        my $values = $kind eq 'modules' ? module_map("$root/map") : value_map("$root/map");
        $result = $kind eq 'modules' ? module_bytes($data, $values)
            : known_scalar_bytes($data, scalar_token_map($values));
        if ($kind eq 'resources') {
            for my $controller (qw(IO CPU)) {
                my $enabled = mapped($values, 'SYSTEMD_' . $controller . 'WEIGHT_ENABLE');
                $enabled =~ /\A(?:true|false)\z/ or fail('invalid resource controller switch');
                $result =~ s{^[\t ]*(?:Startup)?\Q$controller\EWeight[\t ]*=[^\n]*(?:\n|\z)}{}mg
                    if $enabled eq 'false';
            }
        }
    } else {
        fail('unsupported file render kind');
    }
    if ($result =~ /__INSTALLER_(?:PATH_|APPARMOR_PROFILE_|GITBUILD_DISTRIBUTION__)/) {
        my $paths = value_map(parent_path($0) . '/inputs/paths.map');
        $result = path_bytes($result, $paths);
    }
    write_file("$root/output", $result, 0, 0600);
}
sub theme_value {
    my ($key, $values, $target) = @_;
    if ($key =~ /\ATARGET_PATH_(.+)\z/) {
        my $value = mapped($values, $1);
        index($value, "$target/") == 0 or fail('theme path escapes target source tree');
        return '/' . relative(substr($value, length($target) + 1));
    }
    return mapped($values, $key);
}
sub theme_bytes {
    my ($data, $values, $target, $defaults_only) = @_;
    if ($defaults_only) {
        my ($field, $count, $result) = ('', 0, '');
        for my $line (split /(?<=\n)/, $data) {
            $field = $1 if $line =~ /\A\s*"key": "([A-Z][A-Z0-9_]*)",\s*\z/;
            if ($line =~ /\A\s*"default"\s*:/) {
                $line =~ /\A\s*"default": "([^"\r\n]*)",\s*\z/
                    or fail('invalid appearance default template');
                my $current = $1;
                my $expected = theme_value($field, $values, $target);
                ($current eq '__THEME_' . $field . '__' || $current eq $expected)
                    or fail('appearance default differs from its declared theme field');
                $line =~ s{__THEME_([A-Z0-9]+(?:_[A-Z0-9]+)*)__}{theme_value($1, $values, $target)}eg;
                ++$count <= 1024 or fail('excessive appearance default count');
            }
            $result .= $line;
        }
        $count > 0 or fail('empty appearance default count');
        return $result;
    }
    $data =~ s{__THEME_([A-Z0-9]+(?:_[A-Z0-9]+)*)__}{theme_value($1, $values, $target)}eg;
    index($data, '__THEME_') < 0 or fail('malformed or unresolved theme token');
    return $data;
}
sub directory {
    my ($path, $create, $private, $policy) = @_;
    absolute($path);
    my $current = '';
    for my $leaf ('', grep { length } split m{/}, $path) {
        $current = $leaf eq '' ? '/' : ($current eq '/' ? "/$leaf" : "$current/$leaf");
        my @info = lstat($current);
        return if !@info && $create < 0; # Preflight stops at the first absent parent.
        if (!@info && $create) {
            my $mode = $policy && ($current eq $policy->{defaults}
                || index($current, "$policy->{defaults}/") == 0
                || grep { $current eq $_ } @{$policy->{skeletons}}) ? 0700 : 0755;
            mkdir($current, $mode) or fail('cannot create publication directory');
            chmod($mode, $current) == 1 or fail('cannot set publication directory mode');
            @info = lstat($current);
        }
        my $shared_temporary = $policy && $current eq $policy->{temporary}
            && @info && ($info[2] & 07777) == 01777;
        @info && S_ISDIR($info[2]) && $info[4] == $> && (!($info[2] & 0022) || $shared_temporary)
            or fail('unsafe publication ancestry');
    }
    if ($private) {
        my @info = lstat($path);
        ($info[2] & 0777) == 0700 or fail('workspace must be private and owned');
    }
}
sub tree_inventory {
    my ($root, $extra) = @_;
    my (@files, @directories);
    my @pending = ([$root, 0]);
    my $entries = 0;
    while (@pending) {
        my ($parent, $depth) = @{pop @pending};
        $depth <= 64 or fail('tree exceeds depth limit');
        opendir(my $stream, $parent) or fail('cannot inspect private tree');
        my @children;
        while (defined(my $leaf = readdir($stream))) {
            next if $leaf eq '.' || $leaf eq '..';
            ++$entries <= ENTRY_LIMIT + $extra or fail('tree exceeds entry limit');
            relative($leaf);
            push @children, $leaf;
        }
        closedir($stream) or fail('cannot close private tree');
        for my $leaf (sort @children) {
            my $path = "$parent/$leaf";
            my @info = lstat($path);
            @info && $info[4] == $> && !($info[2] & 0022) or fail('unsafe tree member metadata');
            if (S_ISDIR($info[2])) {
                push @directories, $path;
                push @pending, [$path, $depth + 1];
            } else {
                regular_metadata(\@info, FILE_LIMIT);
                push @files, $path;
            }
        }
    }
    return (\@files, \@directories);
}
sub manifest_records {
    my ($path) = @_;
    my @lines = split /\n/, read_regular($path, 4 * 1024 * 1024);
    shift(@lines) eq 'format=3' or fail('invalid payload manifest format');
    my (%records, $total);
    $total = 0;
    for my $line (@lines) {
        $line =~ /\A([0-9]+)\t([a-f0-9]{64})\t(.+)\z/ or fail('invalid payload manifest row');
        my ($size, $digest, $member) = (0 + $1, $2, relative($3));
        !exists($records{$member}) && keys(%records) < MEMBER_LIMIT && $size <= FILE_LIMIT
            && ($total += $size) <= BYTE_LIMIT or fail('excessive or duplicate manifest member');
        $records{$member} = [$size, $digest];
    }
    return \%records;
}
sub has_prefix {
    my ($member, @prefixes) = @_;
    for my $prefix (@prefixes) { return 1 if index($member, "$prefix/") == 0; }
    return 0;
}
sub render_tree {
    my ($root, $options) = @_;
    directory($root, 0, 1);
    my $source = "$root/source";
    directory($source, 0, 0);
    my $expected = manifest_records("$root/inputs/payload.manifest");
    my $paths = value_map("$root/inputs/paths.map");
    my $logging = value_map("$root/inputs/logging.map");
    my $themes = value_map("$root/inputs/themes.map");
    my $templates = value_map("$root/inputs/templates.map");
    my $resources = value_map("$root/inputs/resources.map");
    my $modules = module_map("$root/inputs/modules.map");
    my (%profile_assets, %profile_values);
    for my $line (split /\n/, read_regular("$source/$options->{'profile-assets'}", 1024 * 1024)) {
        my @fields = split /\t/, $line, -1;
        @fields == 2 && $fields[1] eq 'profile' && !exists($profile_assets{$fields[0]})
            && exists($expected->{$fields[0]}) or fail('invalid prepared profile asset inventory');
        $profile_assets{relative($fields[0])} = 1;
    }
    for my $snapshot (qw(host layout account)) {
        my $values = snapshot_values("$root/inputs/$snapshot.records");
        @profile_values{keys %$values} = values %$values;
    }
    for my $key (keys %$templates) {
        if (exists($paths->{$key})) {
            $templates->{$key} eq $paths->{$key} or fail('template map redefines canonical path');
            delete $templates->{$key};
        }
    }
    for my $key (keys %$resources) {
        !exists($templates->{$key}) or fail('duplicate system-template/resource owner');
        $templates->{$key} = $resources->{$key};
    }
    # Only declared profile publishers share raw profile scalar semantics.
    # Other typed consumers may quote values or produce separate primary and
    # future-account inputs. Preserve their grammar until that consumer runs.
    my $resource_tokens = scalar_token_map($resources);
    @profile_values{keys %$templates} = values %$templates;
    # These values are produced after hardware/driver selection or GRUB's
    # final root/initramfs calculation. Missing is deferred, never an empty
    # module list or a frozen pre-selection boot flag.
    delete $profile_values{$_} for grep {
        /\A(?:GRUB_.*FLAGS|CPU_CRC32C_MODULE|(?:INITRAMFS_PLATFORM|GRAPHICS_INITRAMFS|VFIO_INITRAMFS|VIRT_HOST_INITRAMFS)_MODULES)\z/
    } keys %profile_values;
    my $profile_tokens = scalar_token_map(\%profile_values);
    # The extraction manifest is the work list, including dotfiles. Render each
    # listed member once; do not discover or checksum the tree again.
    my ($total, $rendered_count, $rendered_bytes) = (0, 0, 0);
    for my $member (sort keys %$expected) {
        my $path = "$source/$member";
        directory(parent_path($path), 0, 0);
        my $data = read_regular($path);
        ($total += length($data)) <= BYTE_LIMIT or fail('render input exceeds byte limit');
        my $result = $data;
        if (has_prefix($member, @{$options}{qw(scripts target installer)})
                && $member !~ /\.(?:png|jpg|jpeg|webp|gif|ico|ttf|otf|woff|woff2|gz|xz|bz2|zip|deb)\z/
                && index($data, "\0") < 0) {
            if (has_prefix($member, $options->{target})
                    && $member ne $options->{'appearance-registry'}
                    && !has_prefix($member, $options->{'appearance-python'})) {
                $result = module_bytes($result, $modules);
                $result = known_scalar_bytes($result,
                    $profile_assets{$member} ? $profile_tokens : $resource_tokens);
            }
            $result = path_bytes($result, $paths);
            if (has_prefix($member, @{$options}{qw(target late desktop firstboot)})) {
                $result =~ s{__INSTALLER_(LOG_[A-Z0-9]+(?:_[A-Z0-9]+)*)__}{mapped($logging, $1)}eg;
            }
            if (($result =~ /__THEME_[A-Z0-9]+(?:_[A-Z0-9]+)*__/
                    || has_prefix($member, $options->{target}) && index($result, '__THEME_') >= 0)
                    && has_prefix($member, @{$options}{qw(target desktop firstboot)})
                    && !(has_prefix($member, $options->{'appearance-python'}) && $member =~ /\.py\z/)) {
                $result = theme_bytes($result, $themes, $options->{target}, $member eq $options->{'appearance-registry'});
            }
            length($result) <= FILE_LIMIT && ($rendered_bytes += length($result)) <= BYTE_LIMIT
                or fail('render output exceeds byte limit');
            if ($result ne $data) {
                write_file($path, $result, 1);
                ++$rendered_count;
            }
        }
    }
    write_file("$root/inputs/prepared-members", join('', map { "$_\n" } sort keys %$expected), 0, 0600);
    return {format => 2, members => scalar(keys %$expected), input_bytes => $total,
            rendered_files => $rendered_count, rendered_bytes => $rendered_bytes};
}
sub publish_perl {
    my ($root, $options) = @_;
    my $values = value_map("$root/inputs/perl.map");
    my (%assets, @publications);
    my $total = 0;
    for my $line (split /\n/, read_regular("$root/source/$options->{'perl-assets'}", 1024 * 1024)) {
        my @fields = split /\t/, $line, -1;
        @fields == 3 && $fields[2] =~ /\A(?:common|desktop|server)\z/ or fail('invalid shared Perl inventory');
        my ($source, $target, $owner) = (relative($fields[0]), relative($fields[1]), $fields[2]);
        next if $owner ne 'common' && $owner ne $options->{family};
        next if $options->{snapshots} eq 'false' && index($target, 'timeshift/') == 0;
        $target =~ m{/.*\.pm\z} && !exists($assets{$target}) or fail('invalid or duplicate Perl namespace member');
        my $data = scalar_bytes(read_regular("$root/source/$source"), $values);
        length($data) <= FILE_LIMIT && ($total += length($data)) <= BYTE_LIMIT && keys(%assets) < MEMBER_LIMIT
            or fail('shared Perl publication exceeds limits');
        $assets{$target} = $data;
        push @publications, [$source, $target];
    }
    keys(%assets) or fail('empty selected shared Perl inventory');
    my $destination = $options->{'perl-root'};
    directory($destination, 1, 0);
    my %namespaces = map { (split m{/}, $_, 2)[0] => 1 } keys %assets;
    for my $name (keys %namespaces) {
        !lstat("$destination/$name") or fail('refusing to replace existing Perl namespace');
    }
    my $temporary = tempdir('.installer-perl-XXXXXX', DIR => $destination, CLEANUP => 0);
    for my $target (sort keys %assets) {
        directory(parent_path("$temporary/$target"), 1, 0);
        write_file("$temporary/$target", $assets{$target}, 0, 0644);
        chmod(0644, "$temporary/$target") == 1 or fail('cannot set Perl module mode');
    }
    my $rows = join '', map { $_->[0] . "\t$destination/" . $_->[1] . "\t0644\n" } @publications;
    for my $name (sort keys %namespaces) {
        rename("$temporary/$name", "$destination/$name") or fail('cannot publish complete Perl namespace');
    }
    rmdir($temporary) or fail('cannot remove empty Perl publication directory');
    write_file("$root/inputs/published-assets.tsv", $rows, 0, 0600);
    return scalar(@publications);
}
sub receipt {
    my ($report) = @_;
    my $receipt = '{' . join(',', map { '"' . $_ . '":' . $report->{$_} }
        qw(format members input_bytes rendered_files rendered_bytes published_perl_files));
    if (defined($report->{source_archive_sha256})) {
        $receipt .= ',"source_archive_sha256":"' . $report->{source_archive_sha256}
            . '","source_manifest_sha256":"' . $report->{source_manifest_sha256}
            . '","source_identity":"' . $report->{source_identity} . '"';
    }
    return $receipt . "}\n";
}

sub source_provenance {
    my ($root, $report) = @_;
    return unless lstat("$root/identity");
    my $identity = read_regular("$root/identity", 8192);
    $identity =~ /\Averified-v1 ([a-f0-9]{64}) ([a-f0-9]{64}) ([A-Za-z0-9:\/._+?%#@ -]+)\n\z/
        or fail('prepared payload identity is malformed');
    $report->{source_archive_sha256} = $1;
    $report->{source_manifest_sha256} = $2;
    $report->{source_identity} = $3;
}
sub cleanup_workspace {
    my ($root) = @_;
    directory($root, 0, 1);
    opendir(my $stream, $root) or fail('cannot inspect cleanup root');
    my @children = sort grep { $_ ne '.' && $_ ne '..' } readdir($stream);
    closedir($stream) or fail('cannot close cleanup root');
    join('|', @children) eq 'identity|inputs|receipt.json|render.pl|source'
        or fail('cleanup workspace inventory differs');
    # This private receipt has one exact producer and a fixed numeric schema;
    # do not pull JSON::PP (not in perl-base) into the early installer runtime.
    my $data = read_regular("$root/receipt.json", 65536);
    $data =~ /\A\{"format":2,"members\":[1-9][0-9]{0,4},"input_bytes\":[0-9]{1,9},"rendered_files\":[0-9]{1,5},"rendered_bytes\":[0-9]{1,9},"published_perl_files\":[1-9][0-9]{0,4}(?:,"source_archive_sha256":"[a-f0-9]{64}","source_manifest_sha256":"[a-f0-9]{64}","source_identity":"[A-Za-z0-9:\/._+?%#@ -]+")?\}\n\z/
        or fail('cleanup requires a completed render receipt');
    read_regular("$root/identity", 65536);
    my ($files, $directories) = tree_inventory($root, 64);
    unlink($_) == 1 or fail('cannot remove owned workspace file') for @$files;
    rmdir($_) or fail('cannot remove owned workspace directory')
        for sort { length($b) <=> length($a) } @$directories;
    rmdir($root) or fail('cannot remove completed workspace');
}

# A publication plan is private, bounded data. Its length-prefixed fields carry
# line blocks without quoting or a shell-evaluated configuration language.
# The shell owns role selection and dependency barriers; this process owns the
# selected immutable source snapshot, rendering and each atomic destination.
sub publication_plan {
    my ($path) = @_;
    my $data = read_regular($path, FILE_LIMIT);
    $data =~ s/\Apublication-plan-v1\n// or fail('unsupported publication plan');
    my (@rows, $offset, $fields_total);
    ($offset, $fields_total) = (0, 0);
    while ($offset < length($data)) {
        pos($data) = $offset;
        $data =~ /\G([1-9][0-9]{0,3})\n/gc or fail('malformed publication field count');
        my $count = 0 + $1;
        $count >= 9 && $count <= 1033 && ($count - 9) % 2 == 0
            && @rows < MEMBER_LIMIT && ($fields_total += $count) <= 100000
            or fail('excessive publication plan');
        $offset = pos($data);
        my @fields;
        for (1 .. $count) {
            pos($data) = $offset;
            $data =~ /\G(0|[1-9][0-9]{0,6}):/gc or fail('malformed publication field length');
            my $length = 0 + $1;
            $offset = pos($data);
            $length <= 1024 * 1024 && $offset + $length < length($data)
                && substr($data, $offset + $length, 1) eq ','
                or fail('truncated or excessive publication field');
            my $value = substr($data, $offset, $length);
            index($value, "\0") < 0 && index($value, "\r") < 0
                or fail('invalid publication field bytes');
            push @fields, $value;
            $offset += $length + 1;
        }
        push @rows, \@fields;
    }
    return \@rows;
}
sub publication_markers {
    my ($data, $kind, $source) = @_;
    return if index($data, "\0") >= 0; # Preserve binary assets byte for byte.
    if ($kind eq 'template-input') {
        $data !~ /__INSTALLER_(?:PATH_|APPARMOR_PROFILE_|GITBUILD_DISTRIBUTION)/
            or fail("unresolved canonical template-input field: $source");
        return;
    }
    if ($kind eq 'appearance-registry') {
        $data =~ s/__INSTALLER_LABWC_WAYBAR_((INTERNAL|EXTERNAL)_(ACTIVE|PANEL)|SHARED_MENU(_HOVER)?)_SHADOW__//g;
    }
    $data !~ /__INSTALLER_[A-Za-z0-9_]/ or fail("unresolved target installer field: $source");
}
sub publication_render {
    my ($data, $kind, $values, $blocks, $paths) = @_;
    return $data if index($data, "\0") >= 0;
    $data = known_scalar_bytes($data, scalar_token_map($values))
        if $kind eq 'scalar' || $kind eq 'scalar-blocks' || $kind eq 'resources';
    for my $name (sort keys %$blocks) {
        my $token = '__INSTALLER_' . $name . '__';
        my $value = $blocks->{$name};
        $value .= "\n" if length($value) && $value !~ /\n\z/;
        my $count = ($data =~ s{^\Q$token\E(?:\n|\z)}{$value}mg);
        $count == 1 or fail('declared publication line block must occur exactly once: ' . $name);
    }
    if ($kind eq 'resources') {
        for my $controller (qw(IO CPU)) {
            my $enabled = mapped($values, 'SYSTEMD_' . $controller . 'WEIGHT_ENABLE');
            $enabled =~ /\A(?:true|false)\z/ or fail('invalid resource controller switch');
            $data =~ s{^[\t ]*(?:Startup)?\Q$controller\EWeight[\t ]*=[^\n]*(?:\n|\z)}{}mg
                if $enabled eq 'false';
        }
    }
    return path_bytes($data, $paths);
}
sub publication_destination {
    my ($path, $policy, $create) = @_;
    absolute($path);
    $path ne '/' or fail('publication destination is the target root');
    # The target Perl is already chrooted. No mounted-target prefix is ever
    # accepted here, and all filesystem checks remain relative to this root.
    $path =~ m{\A/(?:bin|boot|dev|etc|home|lib|lib64|opt|proc|root|run|sbin|srv|sys|tmp|usr|var|pool|data)/}
        or fail('publication destination is outside the target namespace');
    directory(parent_path($path), $create, 0, $policy);
    my @info = lstat($path);
    regular_metadata(\@info, FILE_LIMIT) if @info;
    return \@info;
}
# Durability belongs to the batch commit, not to transient render candidates.
# Keep one sync per written file and one per distinct directory; no data is read
# or hashed again and no process is launched to flush the target filesystem.
sub publication_sync {
    my ($path, $is_directory, $policy) = @_;
    directory($is_directory ? $path : parent_path($path), 0, 0, $policy);
    sysopen(my $stream, $path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        or fail('cannot open publication for synchronization');
    my @before = stat($stream);
    if ($is_directory) {
        @before && S_ISDIR($before[2]) && $before[4] == $>
            or fail('unsafe publication directory during synchronization');
    } else {
        regular_metadata(\@before, FILE_LIMIT);
    }
    $stream->sync or fail('cannot synchronize published target state');
    my @after = lstat($path);
    same_metadata(\@before, \@after);
    close($stream) or fail('cannot close publication synchronization handle');
}

# Source family directories are acquisition interfaces, not installed paths.
# The shell passes their existing shared root owners once. Logical leaf names
# use a small fixed interface table; all selection is exact-key in memory.
sub publication_source {
    my ($requested, $members, $context, $families) = @_;
    relative($requested);
    my @choices;
    my $physical = index($requested, "$context->{SOURCE_TARGET_ROOT}/") == 0
        || $requested =~ m{\A(?:scripts|hosts|catalog|frontends)/};
    if ($physical) {
        # A fixed physical filename has an explicit owner. Preserve source_fetch
        # suffix handling only when that exact member is absent.
        @choices = ($members->{$requested} ? $requested : "${requested}.tmpl");
    } else {
        for my $entry (@$families) {
            my ($logical, $root) = @$entry;
            next unless index($requested, "$logical/") == 0;
            my $leaf = substr($requested, length($logical) + 1);
            @choices = $leaf =~ m{\A(?:common|desktop|server)/}
                ? ("$root/$leaf") : ("$root/common/$leaf", "$root/$context->{FAMILY}/$leaf");
            last;
        }
        if (!@choices && $requested =~ m{\Aetc/systemd/([^/]+)/(.*)\z}) {
            my ($scope, $leaf) = ($1, $2);
            $scope =~ /\A(?:system|user|system\.conf\.d|user\.conf\.d|journald\.conf\.d|coredump\.conf\.d|resolved\.conf\.d|logind\.conf\.d)\z/
                or fail('invalid logical systemd asset scope');
            @choices = ("$context->{SOURCE_SYSTEMD_COMMON}/$scope/$leaf",
                        $context->{'SOURCE_SYSTEMD_' . uc($context->{FAMILY})} . "/$scope/$leaf");
        }
        if (!@choices && $requested =~ m{\Aetc/apt/(.*)\z}) {
            my $leaf = $1;
            @choices = ($context->{'SOURCE_APT_' . uc($context->{FAMILY})} . "/$leaf");
            unshift @choices, "$context->{SOURCE_APT_ROOT}/$leaf" if index($leaf, 'apt.conf.d/') == 0;
        }
        @choices = ("$context->{SOURCE_TARGET_ROOT}/$requested") unless @choices;
        @choices = map { ($_, "${_}.tmpl") } @choices;
    }
    my %seen;
    my @selected = grep { !$seen{$_}++ && $members->{$_} } @choices;
    @selected == 1 or fail("missing or ambiguous publication source owner: $requested");
    my $source = $selected[0];
    for my $entry (@$families) {
        my $root = $entry->[1];
        next unless index($source, "$root/") == 0;
        my $leaf = substr($source, length($root) + 1);
        $leaf =~ m{\A(?:common|\Q$context->{FAMILY}\E)/}
            or fail('publication source belongs to an incompatible or missing role family');
    }
    if (index($source, "$context->{SOURCE_SYSTEMD_ROOT}/") == 0) {
        (index($source, "$context->{SOURCE_SYSTEMD_COMMON}/") == 0
            || index($source, $context->{'SOURCE_SYSTEMD_' . uc($context->{FAMILY})} . '/') == 0)
            or fail('publication source belongs to an incompatible systemd role');
    }
    if ($source =~ m{\Afrontends/}) {
        index($source, "$context->{SOURCE_FRONTEND_ROOT}/") == 0
            or fail('publication source belongs to another suite');
    }
    for my $family (qw(desktop server)) {
        next if $family eq $context->{FAMILY};
        (index($source, $context->{'SOURCE_APT_' . uc($family)} . '/') != 0
            && index($source, "$context->{SOURCE_TARGET_ROOT}/etc/skel-$family/") != 0)
            or fail('publication source belongs to an incompatible target role');
    }
    $source !~ m{\A(?:repo\.env|hosts/installer/runtime\.env|hooks/installer/di\.env)\z}
        or fail('installer authority cannot be published as target configuration');
    return $source;
}

sub publish_assets {
    my ($work, $root) = @_;
    my $started = time;
    directory($root, 0, 1);
    directory($work, 0, 1);
    index($work, "$root/inputs/publish.") == 0 && parent_path($work) eq "$root/inputs"
        or fail('publication work is outside the prepared input owner');
    my $context = value_map("$work/context");
    my @source_keys = qw(SOURCE_TARGET_ROOT SOURCE_AA_ROOT SOURCE_APPARMOR_ROOT SOURCE_TMPFILES_ROOT
                         SOURCE_SYSCTL_ROOT SOURCE_BIN_ROOT SOURCE_SBIN_ROOT SOURCE_LIBEXEC_ROOT
                         SOURCE_LIB_ROOT SOURCE_SHARE_ROOT SOURCE_SYSTEMD_ROOT SOURCE_SYSTEMD_COMMON
                         SOURCE_SYSTEMD_DESKTOP SOURCE_SYSTEMD_SERVER SOURCE_APT_ROOT SOURCE_APT_DESKTOP
                         SOURCE_APT_SERVER SOURCE_FRONTEND_ROOT);
    my @context_keys = (qw(FORMAT SUITE FAMILY PHASE GROUP DEFAULTS_ROOT TEMP_ROOT SKELETON_BASE
                           SKELETON_DESKTOP SKELETON_SERVER ACCOUNT_HOME SOURCE_ARCHIVE_SHA256), @source_keys);
    keys(%$context) == @context_keys or fail('publication context has unsupported fields');
    mapped($context, $_) for @context_keys;
    $context->{FORMAT} eq '1' && $context->{FAMILY} =~ /\A(?:desktop|server)\z/
        && $context->{SUITE} =~ /\A(?:forky|trixie)\z/
        && $context->{PHASE} =~ m{\A[-A-Za-z0-9_.\x2f\x40+:]+\z}
        && $context->{GROUP} =~ /\A[a-z][a-z0-9-]{0,63}\z/
        && $context->{SOURCE_ARCHIVE_SHA256} =~ /\A[a-f0-9]{64}\z/
        or fail('invalid selected publication context');
    my %provenance;
    source_provenance($root, \%provenance);
    ($provenance{source_archive_sha256} // '') eq $context->{SOURCE_ARCHIVE_SHA256}
        or fail('publication plan belongs to another prepared payload');
    my $policy = {defaults => absolute($context->{DEFAULTS_ROOT}),
                  temporary => absolute($context->{TEMP_ROOT}),
                  skeletons => [map { absolute($context->{$_}) } qw(SKELETON_BASE SKELETON_DESKTOP SKELETON_SERVER)]};
    absolute($context->{ACCOUNT_HOME});
    relative($context->{$_}) for @source_keys;
    my @family_interfaces = (
        ['etc/apparmor.d', $context->{SOURCE_AA_ROOT}], ['etc/apparmor', $context->{SOURCE_APPARMOR_ROOT}],
        ['etc/tmpfiles.d', $context->{SOURCE_TMPFILES_ROOT}], ['etc/sysctl.d', $context->{SOURCE_SYSCTL_ROOT}],
        ['usr/local/bin', $context->{SOURCE_BIN_ROOT}], ['usr/local/sbin', $context->{SOURCE_SBIN_ROOT}],
        ['usr/local/libexec', $context->{SOURCE_LIBEXEC_ROOT}], ['usr/local/lib', $context->{SOURCE_LIB_ROOT}],
        ['usr/local/share', $context->{SOURCE_SHARE_ROOT}]);
    my $paths = value_map("$root/inputs/paths.map");
    my %members;
    for my $member (split /\n/, read_regular("$root/inputs/prepared-members", 4 * 1024 * 1024)) {
        relative($member);
        !$members{$member}++ && keys(%members) <= MEMBER_LIMIT
            or fail('invalid prepared source membership');
    }
    my %published;
    for my $line (split /\n/, read_regular("$root/inputs/published-assets.tsv", 4 * 1024 * 1024)) {
        my @fields = split /\t/, $line, -1;
        @fields == 3 && $fields[2] eq '0644' && !exists($published{$fields[1]})
            or fail('invalid prepared publication inventory');
        relative($fields[0]); absolute($fields[1]);
        $published{$fields[1]} = $fields[0];
    }
    my (%sources, %candidates, %candidate_sources, %primary, %ownership, $resources);
    my ($input_bytes, $output_bytes, $source_reads, $rows) = (0, 0, 0, 0);
    for my $row (@{publication_plan("$work/plan")}) {
        my ($kind, $source, $target, $mode, $owner, $family, $suite, $phase, $dependency, @pairs) = @$row;
        ++$rows;
        $kind =~ /\A(?:plain|scalar|scalar-blocks|stdin|template-input|appearance-registry|resources)\z/
            && $mode =~ /\A0?[0-7]{3}\z/ && $owner eq '0:0'
            && $family eq $context->{FAMILY} && $suite eq $context->{SUITE}
            && $phase eq $context->{PHASE} && $dependency eq $context->{GROUP}
            or fail('invalid publication operation or dependency context');
        $target = absolute(path_bytes($target, $paths));
        if ($kind ne 'stdin') {
            $source = publication_source($source, \%members, $context, \@family_interfaces);
        }
        if ($kind eq 'template-input') {
            $target =~ m{\A\Q$policy->{temporary}\E/installer-[A-Za-z0-9.-]+/}
                or fail('template input is outside a private target consumer workspace');
        }
        my (%values, %blocks);
        while (@pairs) {
            my ($key, $value) = splice(@pairs, 0, 2);
            $key =~ /\A[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*\z/
                && !exists($values{$key}) && !exists($blocks{$key})
                or fail('invalid or duplicate publication scalar field');
            if ($key =~ /\ABLOCK_(LABWC_WORKSPACE_NAME_LINES|LABWC_WORKSPACE_KEYBIND_LINES|LABWC_RECORDING_KEYBIND_LINES)\z/) {
                $kind eq 'scalar-blocks' && !exists($blocks{$1})
                    or fail('unexpected or duplicate deferred publication block');
                $blocks{$1} = $value;
            } else {
                index($value, "\n") < 0 or fail('publication scalar field must be one line');
                $values{$key} = $value;
            }
        }
        if ($kind eq 'scalar-blocks') {
            keys(%blocks) == 3 && $source =~ m{/etc/skel-desktop/\.config/labwc/rc\.xml\.tmpl\z}
                or fail('publication blocks require the declared Labwc template');
        }
        my $data;
        if ($kind eq 'stdin') {
            keys(%values) == 1 && $values{INPUT_FILE} =~ /\Ainput\.[A-Za-z0-9]+\z/
                or fail('generated publication requires one private input');
            $data = read_regular("$work/$values{INPUT_FILE}");
            $input_bytes += length($data);
            ++$source_reads;
            $source eq '-' || $members{$source} or fail('unknown generated publication source');
            %values = ();
        } else {
            relative($source);
            $members{$source} or fail("publication source is absent from the prepared payload: $source");
            if (!exists($sources{$source})) {
                directory(parent_path("$root/source/$source"), 0, 0);
                $sources{$source} = read_regular("$root/source/$source");
                $input_bytes += length($sources{$source});
                ++$source_reads;
            }
            $data = $sources{$source};
        }
        $input_bytes <= BYTE_LIMIT or fail('publication source bytes exceed batch limit');
        if ($kind eq 'resources') {
            !keys(%values) or fail('resource publication cannot override its owner');
            $resources //= value_map("$root/inputs/resources.map");
            %values = %$resources;
        }
        my $result = publication_render($data, $kind, \%values, \%blocks, $paths);
        publication_markers($result, $kind, $source);
        length($result) <= FILE_LIMIT && ($output_bytes += length($result)) <= BYTE_LIMIT
            or fail('publication outputs exceed batch limit');
        my $primary_path;
        for my $family_name (qw(desktop server)) {
            my $skeleton = $context->{'SKELETON_' . uc($family_name)};
            next unless index($target, "$skeleton/") == 0;
            $primary_path = "$policy->{defaults}/$family_name/" . substr($target, length($skeleton) + 1);
        }
        if (defined($primary_path) && ($kind ne 'stdin' || $source eq '-')) {
            $primary{$primary_path} = [$result, oct($mode)];
            if ($kind eq 'scalar' || $kind eq 'scalar-blocks') {
                my %future = %values;
                $future{ACCOUNT_HOME} = '$HOME' if exists($future{ACCOUNT_HOME});
                $future{ACCOUNT_USERNAME} = '$USER' if exists($future{ACCOUNT_USERNAME});
                for my $key (grep { /\ADIR_HOME_/ } keys %future) {
                    index($future{$key}, "$context->{ACCOUNT_HOME}/") == 0
                        or fail('future-account directory escapes the primary account HOME');
                    $future{$key} = '$HOME/' . relative(substr($future{$key}, length($context->{ACCOUNT_HOME}) + 1));
                }
                $result = publication_render($data, $kind, \%future, \%blocks, $paths);
                publication_markers($result, $kind, $source);
            }
        }
        $candidates{$target} = [$result, oct($mode)];
        $candidate_sources{$target} = $source;
        my $owned_kind = $kind;
        $owned_kind = 'template-input' if $target =~ m{\A\Q$policy->{temporary}\E/(?:installer-[^/]+|install-[^/]+/)};
        $source = 'generated' if $source eq '-';
        $ownership{$target} = join("\t", $target, $source, $owned_kind, $phase, sprintf('%04o', oct($mode))) . "\n";
    }
    $rows or fail('empty publication plan');
    my $candidate_bytes = 0;
    for my $candidate (values %primary, values %candidates) {
        length($candidate->[0]) <= FILE_LIMIT && ($candidate_bytes += length($candidate->[0])) <= BYTE_LIMIT
            or fail('primary and future publication outputs exceed batch limit');
    }
    # Validate every candidate before any mutation, then keep the plan and
    # proposed ownership on failure. Atomicity is per file; a failed batch is
    # never reported as rolled back or eligible for automatic replay.
    for my $path (keys %primary, keys %candidates) {
        my $before = publication_destination($path, $policy, -1);
        if (exists($published{$path}) && @$before
                && ($candidate_sources{$path} // '') eq $published{$path}) {
            ($before->[2] & 07777) == 0644 && $before->[4] == 0 && $before->[5] == 0
                or fail('published prepared Perl member metadata changed');
        }
    }
    write_file("$work/ownership.pending", join('', @ownership{sort keys %ownership}), 0, 0600);
    publication_sync("$work/$_", 0, $policy) for qw(plan context ownership.pending);
    publication_sync($work, 1, $policy);
    my (%written, %changed_parents);
    my ($written_files, $written_bytes, $reused_files, $destination_reads, $destination_bytes) = (0, 0, 0, 0, 0);
    for my $path ((sort keys %primary), (sort keys %candidates)) {
        my $candidate = exists($primary{$path}) ? $primary{$path} : $candidates{$path};
        my $before = publication_destination($path, $policy, 1);
        for my $skeleton (@{$policy->{skeletons}}) {
            next unless index($path, "$skeleton/") == 0;
            chmod(0700, $skeleton) == 1 or fail('cannot preserve private account template root');
        }
        # Debian systemd's configuration roots are public directories; private
        # credentials below other roots retain their existing modes.
        my $systemd = $paths->{PATH_DIR_SYSTEMD_ETC} // '';
        if (length($systemd) && $path =~ m{\A\Q$systemd\E/(?:system|user)/}) {
            chmod(0755, $systemd) == 1 or fail('cannot normalize systemd configuration root');
            my ($scope) = $path =~ m{\A\Q$systemd\E/(system|user)/};
            chmod(0755, "$systemd/$scope") == 1 or fail('cannot normalize systemd configuration scope');
        }
        my $perl_root = $paths->{PATH_DIR_PERL5_SITE_PERL} // '';
        if (length($perl_root) && index($path, "$perl_root/") == 0) {
            my $parent = parent_path($path);
            my $base = parent_path($perl_root);
            while (1) {
                chmod(0755, $parent) == 1 or fail('cannot normalize managed Perl directory mode');
                last if $parent eq $base;
                $parent = parent_path($parent);
            }
        }
        # Base-stage already published complete Perl namespaces. Preserve that
        # optimization, but compare current bytes with the protected candidate
        # when a later publication encounters a mutable installed destination.
        if (exists($published{$path}) && @$before
                && ($candidate_sources{$path} // '') eq $published{$path}
                && $candidate->[1] == 0644) {
            ($before->[2] & 07777) == 0644 && $before->[4] == 0 && $before->[5] == 0
                or fail('published prepared Perl member metadata changed');
            my $current = read_regular($path);
            ++$destination_reads;
            $destination_bytes += length($current);
            if ($current eq $candidate->[0]) {
                ++$reused_files;
                next;
            }
        }
        write_file($path, $candidate->[0], scalar(@$before) ? 1 : 0, $candidate->[1], $policy);
        ++$written_files;
        $written_bytes += length($candidate->[0]);
        $written{$path} = 1;
        my $changed_parent = parent_path($path);
        while (1) {
            $changed_parents{$changed_parent} = 1;
            last if $changed_parent eq '/';
            $changed_parent = parent_path($changed_parent);
        }
    }
    publication_sync($_, 0, $policy) for sort keys %written;
    publication_sync($_, 1, $policy)
        for sort { length($b) <=> length($a) || $a cmp $b } keys %changed_parents;
    rename("$work/ownership.pending", "$work/ownership.tsv") or fail('cannot complete publication ownership');
    publication_sync($work, 1, $policy);
    my $elapsed = time - $started;
    $elapsed = 0 if $elapsed < 0;
    write_file("$work/report", "format=1\noperations=$rows\nfiles=" . scalar(keys %candidates)
        . "\nsource_reads=$source_reads\ninput_bytes=$input_bytes\noutput_bytes=$written_bytes\nwritten_files=$written_files\nreused_files=$reused_files\ndestination_reads=$destination_reads\ndestination_bytes=$destination_bytes\nperl_launches=1\nelapsed_seconds=$elapsed\n", 0, 0600);
    print STDERR "asset_batch phase=$context->{PHASE} barrier=$context->{GROUP} records=$rows files=", scalar(keys %candidates),
        " source_reads=$source_reads unique_input_bytes=$input_bytes written_bytes=$written_bytes reused_files=$reused_files destination_bytes=$destination_bytes elapsed_seconds=$elapsed\n"
        or fail('cannot report publication batch');
}

sub main {
    umask 0077;
    if (@ARGV && $ARGV[0] eq '--publish') {
        shift @ARGV;
        @ARGV == 2 or fail('publication requires a private plan and prepared root');
        publish_assets(absolute($ARGV[0]), absolute($ARGV[1]));
        return;
    }
    if (@ARGV && $ARGV[0] eq '--file') {
        shift @ARGV;
        @ARGV == 2 or fail('file rendering requires a private workspace and kind');
        render_file(absolute($ARGV[0]), $ARGV[1]);
        return;
    }
    my $root = absolute(shift(@ARGV));
    my %options;
    while (@ARGV) {
        my $key = shift @ARGV;
        if ($key eq '--cleanup') { !@ARGV && !%options or fail('invalid cleanup arguments'); cleanup_workspace($root); print "completed target rendering workspace removed\n"; return; }
        $key =~ /\A--(scripts|target|installer|late|desktop|firstboot|appearance-python|appearance-registry|perl-assets|profile-assets|perl-root|family|snapshots)\z/
            or fail('unsupported renderer option');
        my $name = $1;
        !exists($options{$name}) && @ARGV or fail('missing or duplicate renderer option');
        $options{$name} = shift @ARGV;
    }
    keys(%options) == 13 or fail('all explicit renderer selectors are required');
    relative($options{$_}) for qw(scripts target installer late desktop firstboot appearance-python appearance-registry perl-assets profile-assets);
    absolute($options{'perl-root'});
    $options{family} =~ /\A(?:desktop|server)\z/ && $options{snapshots} =~ /\A(?:true|false)\z/ or fail('invalid selected target policy');
    my %provenance;
    source_provenance($root, \%provenance);
    my $report = render_tree($root, \%options);
    @{$report}{keys %provenance} = values %provenance;
    $report->{published_perl_files} = publish_perl($root, \%options);
    write_file("$root/receipt.json", receipt($report), 0, 0600);
    print 'prepared target payload: members=', $report->{members}, ' rendered_files=',
        $report->{rendered_files}, "\n"
        or fail('cannot report target preparation');
}
eval { main(); 1 } or do { my $cause = $@ || "unknown rendering failure\n"; print STDERR 'target payload rendering failed: ', $cause; exit 1; };

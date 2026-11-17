#!/usr/bin/perl
# One batch renderer for the first base-installer hook. Use perl-base modules
# only: neither full Perl, Python, CPAN nor a configured target APT is required.
use strict;
use warnings;
use bytes;
use Fcntl qw(O_RDONLY O_WRONLY O_CREAT O_EXCL O_NOFOLLOW O_NONBLOCK :mode);
use File::Temp qw(tempdir tempfile);

use constant FILE_LIMIT => 16 * 1024 * 1024;
use constant BYTE_LIMIT => 256 * 1024 * 1024;
use constant MEMBER_LIMIT => 10000;
use constant ENTRY_LIMIT => 20000;

sub fail { die "$_[0]\n"; }
sub relative {
    my ($path) = @_;
    defined($path) && length($path) <= 4096 && $path =~ m{\A[A-Za-z0-9_./@+ -]+\z}
        && $path !~ m{\A/|(?:\A|/)(?:\.?\.?)(?:/|\z)}
        or fail('invalid relative source selector');
    return $path;
}
sub absolute {
    my ($path) = @_;
    defined($path) && $path =~ m{\A/[A-Za-z0-9_./@+ -]*\z}
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
    my ($path, $data, $replace, $mode) = @_;
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
    directory($parent, 0, 0);
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
        chmod($mode // 0600, $stream) == 1 or fail('cannot set render output mode');
        close($stream) or fail('cannot close render output');
        directory($parent, 0, 0);
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
            length($value) && $value =~ m{\A/[A-Za-z0-9_./@+ -]*\z}
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
    my ($path, $create, $private) = @_;
    absolute($path);
    my $current = '';
    for my $leaf ('', grep { length } split m{/}, $path) {
        $current = $leaf eq '' ? '/' : ($current eq '/' ? "/$leaf" : "$current/$leaf");
        my @info = lstat($current);
        if (!@info && $create) {
            mkdir($current, 0755) or fail('cannot create publication directory');
            chmod(0755, $current) == 1 or fail('cannot set publication directory mode');
            @info = lstat($current);
        }
        @info && S_ISDIR($info[2]) && $info[4] == $> && !($info[2] & 0022)
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
    $identity =~ /\A([a-f0-9]{64}) ([a-f0-9]{64}) ([A-Za-z0-9:\/._+?%#@ -]+)\n\z/
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
sub main {
    umask 0077;
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

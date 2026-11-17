#!/usr/bin/perl
# One batch renderer for the first base-installer hook. Use perl-base modules
# only: neither full Perl, Python, CPAN nor a configured target APT is required.
use strict;
use warnings;
use bytes;
use Fcntl qw(O_RDONLY O_WRONLY O_CREAT O_EXCL O_TRUNC O_NOFOLLOW O_NONBLOCK :mode);
use File::Temp qw(tempdir);
use IPC::Open2 qw(open2);
use Cwd qw(getcwd);

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
    if ($replace) {
        my @info = lstat($path);
        regular_metadata(\@info, FILE_LIMIT);
    }
    my $flags = O_WRONLY | O_NOFOLLOW | ($replace ? O_TRUNC : O_CREAT | O_EXCL);
    sysopen(my $stream, $path, $flags, $mode // 0600) or fail('cannot open render output');
    binmode($stream) or fail('cannot write render output as bytes');
    print {$stream} $data or fail('cannot write render output');
    close($stream) or fail('cannot close render output');
}
sub value_map {
    my ($path) = @_;
    my %values;
    for my $line (split /\n/, read_regular($path, 1024 * 1024)) {
        $line =~ /\A([A-Z][A-Z0-9_]*)=([^\0\r]*)\z/ or fail('malformed render-map row');
        my ($key, $value) = ($1, $2);
        !exists($values{$key}) or fail('duplicate render-map key');
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
                $line =~ /\A\s*"default": "__THEME_([A-Z0-9_]+)__",\s*\z/ && $1 eq $field
                    or fail('invalid appearance default template');
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
    my ($files) = tree_inventory($source, 0);
    @$files == keys(%$expected) or fail('copied payload has missing or extra members');
    my ($total, $checksums) = (0, '');
    for my $path (sort @$files) {
        my $member = relative(substr($path, length($source) + 1));
        my @info = lstat($path);
        exists($expected->{$member}) && $info[7] == $expected->{$member}[0]
            && ($total += $info[7]) <= BYTE_LIMIT or fail('copied payload differs from manifest');
        $checksums .= $expected->{$member}[1] . "  $member\n";
    }
    # One packaged coreutils process verifies the entire private copy, replacing
    # thousands of subprocesses or a dependency on non-base Digest::SHA.
    write_file("$root/inputs/checksums", $checksums, 0, 0600);
    my $previous = getcwd();
    chdir($source) or fail('cannot enter copied source directory');
    my $verified = system { $options->{'sha256'} } $options->{'sha256'}, '--check', '--status', '--strict', "$root/inputs/checksums";
    chdir($previous) or fail('cannot leave copied source directory');
    $verified == 0 or fail('copied source differs from authenticated manifest');
    my $paths = value_map("$root/inputs/paths.map");
    my $logging = value_map("$root/inputs/logging.map");
    my $themes = value_map("$root/inputs/themes.map");
    # Hash the bytes as they pass through the one rendering walk. No second
    # recursive read of the rendered output is needed for its receipt.
    my $hash_pid = open2(my $hash_out, my $hash_in, $options->{'sha256'}, '--binary');
    binmode($hash_in) && binmode($hash_out) or fail('cannot open fingerprint stream');
    my ($rendered_count, $rendered_bytes) = (0, 0);
    my $render_error;
    eval {
      for my $path (sort @$files) {
        my $member = substr($path, length($source) + 1);
        my $data = read_regular($path);
        my $result = $data;
        if (has_prefix($member, @{$options}{qw(scripts target installer)})
                && $member !~ /\.(?:png|jpg|jpeg|webp|gif|ico|ttf|otf|woff|woff2|gz|xz|bz2|zip|deb)\z/
                && index($data, "\0") < 0) {
            $result = path_bytes($data, $paths);
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
        print {$hash_in} $member, "\0", length($result), "\0", $result
            or fail('cannot write render fingerprint stream');
      }
      1;
    } or $render_error = $@ || "unknown rendering failure\n";
    # Close and reap the owned hasher even when a token or output fails. The
    # enclosing installer deadline also bounds these final pipe/wait steps.
    my $input_closed = close($hash_in);
    my $digest_line = <$hash_out> // '';
    my $output_closed = close($hash_out);
    my $hash_waited = waitpid($hash_pid, 0);
    my $hash_status = $?;
    die $render_error if defined($render_error);
    $input_closed && $output_closed && $hash_waited == $hash_pid && $hash_status == 0
        or fail('render fingerprint command failed');
    $digest_line =~ /\A([a-f0-9]{64}) [ *]-\n\z/ or fail('invalid render fingerprint');
    return {format => 1, members => scalar(@$files), input_bytes => $total,
            rendered_files => $rendered_count, rendered_bytes => $rendered_bytes, rendered_sha256 => $1};
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
    for my $name (sort keys %namespaces) {
        rename("$temporary/$name", "$destination/$name") or fail('cannot publish complete Perl namespace');
    }
    rmdir($temporary) or fail('cannot remove empty Perl publication directory');
    my $rows = join '', map { $_->[0] . "\t$destination/" . $_->[1] . "\t0644\n" } @publications;
    write_file("$root/inputs/published-assets.tsv", $rows, 0, 0600);
    return scalar(@publications);
}
sub receipt {
    my ($report) = @_;
    return '{' . join(',', map { '"' . $_ . '":' . $report->{$_} }
        qw(format members input_bytes rendered_files rendered_bytes published_perl_files))
        . ',"rendered_sha256":"' . $report->{rendered_sha256} . '"}' . "\n";
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
    $data =~ /\A\{"format":1,"members":[1-9][0-9]{0,4},"input_bytes":[0-9]{1,9},"rendered_files":[0-9]{1,5},"rendered_bytes":[0-9]{1,9},"published_perl_files":[1-9][0-9]{0,4},"rendered_sha256":"[a-f0-9]{64}"\}\n\z/
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
    my $root = absolute(shift(@ARGV));
    my %options;
    while (@ARGV) {
        my $key = shift @ARGV;
        if ($key eq '--cleanup') { !@ARGV && !%options or fail('invalid cleanup arguments'); cleanup_workspace($root); print "completed target rendering workspace removed\n"; return; }
        $key =~ /\A--(scripts|target|installer|late|desktop|firstboot|appearance-python|appearance-registry|perl-assets|perl-root|family|snapshots|sha256)\z/
            or fail('unsupported renderer option');
        my $name = $1;
        !exists($options{$name}) && @ARGV or fail('missing or duplicate renderer option');
        $options{$name} = shift @ARGV;
    }
    keys(%options) == 13 or fail('all explicit renderer selectors are required');
    relative($options{$_}) for qw(scripts target installer late desktop firstboot appearance-python appearance-registry perl-assets);
    absolute($options{$_}) for qw(perl-root sha256);
    $options{family} =~ /\A(?:desktop|server)\z/ && $options{snapshots} =~ /\A(?:true|false)\z/ or fail('invalid selected target policy');
    my $report = render_tree($root, \%options);
    $report->{published_perl_files} = publish_perl($root, \%options);
    write_file("$root/receipt.json", receipt($report), 0, 0600);
    print 'prepared target payload: ', receipt($report) or fail('cannot report target preparation');
}
eval { main(); 1 } or do { my $cause = $@ || "unknown rendering failure\n"; print STDERR 'target payload rendering failed: ', $cause; exit 1; };

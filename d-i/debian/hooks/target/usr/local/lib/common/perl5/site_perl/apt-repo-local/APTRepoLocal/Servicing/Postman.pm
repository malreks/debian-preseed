package APTRepoLocal::Servicing::Postman;

use strict;
use warnings;

use lib '__INSTALLER_PATH_DIR_PERL5_SITE_PERL__/runtime';
use Managed::Process qw(capture_command);

use Moo;
use MooX::StrictConstructor;

use Digest::SHA;
use JSON::PP qw(decode_json);

has http  => (is => 'ro', required => 1);
has event => (is => 'ro', required => 1);
has state => (is => 'ro', required => 1);
has release_policy => (is => 'ro', required => 1);

sub _limit {
    my ($self, $name) = @_;
    my $value = $self->release_policy()->{postman}{$name};
    defined $value && !ref $value && $value =~ /\A[1-9][0-9]*\z/
        or die "Postman release policy limit is unavailable: $name\n";
    return 0 + $value;
}

sub _capture_limited {
    my ($self, $limit, @command) = @_;
    @command or return;
    my $result = capture_command(argv => \@command, timeout => 120, limit => $limit);
    if ($result->{status} != 0) { die "Postman archive inspection failed\n"; }
    return $result->{stdout};
}

sub _sha256 {
    my ($self, $path) = @_;
    -f $path && !-l $path
        or die "Postman archive is not a regular file\n";
    open my $fh, '<:raw', $path
        or die "cannot read Postman archive: $!\n";
    my $digest = Digest::SHA->new(256);
    $digest->addfile($fh);
    close $fh
        or die "cannot close Postman archive: $!\n";
    return $digest->hexdigest();
}

sub _entries {
    my ($self, $archive) = @_;
    my $listing = $self->_capture_limited(
        2 * 1024 * 1024,
        '__INSTALLER_PATH_DIR_USR__/bin/tar',
        '--list',
        '--gzip',
        '--file',
        $archive,
    );
    $listing =~ /\n\z/
        or die "Postman archive listing is malformed\n";
    my @entries = split /\n/, $listing, -1;
    pop @entries;
    @entries && @entries <= $self->_limit('maximum_members')
        or die "Postman archive has an unsafe member count\n";
    my %seen;
    for my $entry (@entries) {
        length($entry) && length($entry) <= 512
            && $entry !~ /[[:space:]\\]/
            && $entry !~ m{\A/}
            && $entry !~ m{(?:\A|/)\.\.(?:/|\z)}
            && $entry =~ m{\APostman(?:/|\z)}
            && !$seen{$entry}++
            or die "Postman archive contains an unsafe member path\n";
    }
    for my $required (
        qw(
            Postman/Postman
            Postman/app/Postman
            Postman/app/chrome-sandbox
            Postman/app/libffmpeg.so
            Postman/app/resources/app/assets/icon.png
            Postman/app/resources/app/package.json
        )
    ) {
        $seen{$required}
            or die "Postman archive is missing $required\n";
    }
    return \@entries;
}

sub _release {
    my ($self, $archive) = @_;
    my $json = $self->_capture_limited(
        $self->_limit('metadata_maximum_bytes'),
        '__INSTALLER_PATH_DIR_USR__/bin/tar',
        '--extract',
        '--gzip',
        '--to-stdout',
        '--file',
        $archive,
        'Postman/app/resources/app/package.json',
    );
    my $package = eval { decode_json($json) };
    !$@ && ref $package eq 'HASH'
        or die "Postman release metadata is invalid\n";
    my $version = $package->{version};
    defined $version && $version =~ /\A[0-9]+(?:\.[0-9]+)+\z/ && length($version) <= 64
        or die "Postman release version is invalid\n";
    return $version;
}

sub validate {
    my ($self, $archive) = @_;
    -f $archive && !-l $archive
        or die "Postman archive is not a regular file\n";
    my $size = -s $archive;
    defined $size && $size >= $self->_limit('minimum_bytes') && $size <= $self->_limit('maximum_bytes')
        or die "Postman archive size is outside approved bounds\n";
    $self->_entries($archive);
    return {
        version => $self->_release($archive),
        sha256  => $self->_sha256($archive),
        size    => $size,
    };
}

sub _installed {
    my ($self) = @_;
    my $raw = $self->state()->read_state('postman.installed', 256);
    return undef if !defined $raw;
    my ($version, $sha256) = $raw =~ /\A([0-9]+(?:\.[0-9]+)+)\|([0-9a-f]{64})\n\z/
        or die "stored Postman installation state is invalid\n";
    return { version => $version, sha256 => $sha256 };
}

sub _pending {
    my ($self) = @_;
    my $raw = $self->state()->read_state('postman.pending', 256);
    return undef if !defined $raw;
    my ($version, $sha256, $name) = $raw =~ /\A([0-9]+(?:\.[0-9]+)+)\|([0-9a-f]{64})\|(postman-[0-9]+(?:\.[0-9]+)+-linux-amd64\.tar\.gz)\n\z/
        or die "stored Postman pending state is invalid\n";
    return { version => $version, sha256 => $sha256, name => $name };
}

sub _version_compare {
    my ($self, $left, $operator, $right) = @_;
    my $result = system('__INSTALLER_PATH_DIR_USR__/bin/dpkg', '--compare-versions', $left, $operator, $right);
    return 1 if $result == 0;
    return 0 if $result == 256;
    die "Postman version comparison failed\n";
}

sub fetch {
    my ($self, $work, $for_repository) = @_;
    defined $for_repository && $for_repository == 1
        or die "Postman acquisition requires the native repository publisher\n";
    my $archive = "$work/postman-linux64.tar.gz";
    eval {
        $self->http()->download(
            label => 'Postman',
            url => $self->release_policy()->{service_urls}{postman},
            destination => $archive,
            minimum => $self->_limit('minimum_bytes'),
            maximum => $self->_limit('maximum_bytes'),
            content_policy => 'artifact',
        );
        1;
    } or return (1, 'download');
    my $release = eval { $self->validate($archive) };
    return (1, 'archive') if !$release;
    my $installed = $self->_installed();
    if ($installed) {
        return (1, 'downgrade') if $self->_version_compare($release->{version}, 'lt', $installed->{version});
        return (2, 'current') if $release->{version} eq $installed->{version}
            && $release->{sha256} eq $installed->{sha256};
        return (1, 'validation') if $release->{version} eq $installed->{version};
    }
    my $name = "postman-$release->{version}-linux-amd64.tar.gz";
    my ($stored, $created) = eval {
        $self->state()->retain_artifact('postman', $archive, $name);
    };
    return (1, 'publish') if !$stored;
    $self->state()->write_state(
        'postman.pending',
        join('|', $release->{version}, $release->{sha256}, $name) . "\n",
    );
    $self->event()->emit(
        'downloaded',
        'postman',
        $installed ? $installed->{version} : 'unknown',
        $release->{version},
    ) if $created;
    return (0, 'downloaded');
}

1;

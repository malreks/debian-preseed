package APTRepoLocal::Servicing::Ledger;

use strict;
use warnings;

use lib '__INSTALLER_PATH_DIR_PERL5_SITE_PERL__/runtime';
use Managed::Process qw(capture_command);

use Moo;
use MooX::StrictConstructor;

use Digest::SHA qw(sha256_hex);
use Digest::SHA;
use MIME::Base64 qw(encode_base64);
use APTRepoLocal::Servicing::Atomic;

has http  => (is => 'ro', required => 1);
has event => (is => 'ro', required => 1);
has state => (is => 'ro', required => 1);
has release_policy => (is => 'ro', required => 1);

sub _capture_bytes {
    my ($self, @command) = @_;
    @command or return;
    my $result = capture_command(argv => \@command, timeout => 120, limit => 1_048_576);
    if ($result->{status} != 0) { return; }
    return $result->{stdout};
}

sub _digest {
    my ($self, $path, $algorithm) = @_;
    -f $path && !-l $path
        or die "Ledger AppImage is not a regular file\n";
    open my $fh, '<:raw', $path
        or die "cannot read Ledger AppImage: $!\n";
    my $digest = Digest::SHA->new($algorithm);
    $digest->addfile($fh);
    close $fh
        or die "cannot close Ledger AppImage: $!\n";
    return $digest->hexdigest();
}

sub _is_elf {
    my ($self, $path) = @_;
    open my $fh, '<:raw', $path
        or die "cannot inspect Ledger AppImage: $!\n";
    my $header = q{};
    read $fh, $header, 4;
    close $fh
        or die "cannot close Ledger AppImage inspection: $!\n";
    return $header eq "\x7fELF";
}

sub _parse_metadata {
    my ($self, $path) = @_;
    my $policy = $self->release_policy();
    my $raw = APTRepoLocal::Servicing::Atomic->read_limited($path, 65_536);
    my %fields;
    for my $field (qw(version path sha512 size)) {
        my @values = $field eq 'size'
            ? $raw =~ /^ {4}size:\s*(.+?)\s*$/mg
            : $raw =~ /^\Q$field\E:\s*(.+?)\s*$/mg;
        @values == 1
            or die "Ledger release metadata must have one $field field\n";
        $fields{$field} = $values[0];
    }
    $fields{version} =~ /\A[0-9]+(?:\.[0-9]+)+\z/ && length($fields{version}) <= 32
        or die "Ledger release version is invalid\n";
    $fields{path} eq "ledger-live-desktop-$fields{version}-linux-x86_64.AppImage"
        or die "Ledger release filename is invalid\n";
    $fields{sha512} =~ /\A[A-Za-z0-9+\/]{86}==\z/
        or die "Ledger release SHA-512 metadata is invalid\n";
    $fields{size} =~ /\A[0-9]+\z/
        or die "Ledger release size metadata is invalid\n";
    return \%fields;
}

sub _manifest_digest {
    my ($self, $path, $filename) = @_;
    my $raw = APTRepoLocal::Servicing::Atomic->read_limited($path, 65_536);
    my @matches = $raw =~ /^\s*([0-9a-f]{128})\s+\Q$filename\E\s*$/mg;
    @matches == 1
        or die "Ledger signed manifest lacks a unique AppImage digest\n";
    return $matches[0];
}

sub _assert_key {
    my ($self, $key) = @_;
    -r $key && !-l $key
        or die "Ledger public key is unavailable\n";
    system('__INSTALLER_PATH_DIR_USR__/bin/openssl', 'pkey', '-pubin', '-in', $key, '-noout') == 0
        or die "Ledger public key is invalid\n";
    my $der = $self->_capture_bytes('__INSTALLER_PATH_DIR_USR__/bin/openssl', 'pkey', '-pubin', '-in', $key, '-outform', 'DER');
    defined $der && sha256_hex($der) eq $self->release_policy()->{public_key_sha256}
        or die "Ledger public key fingerprint does not match its pinned key\n";
}

sub _installed_hash {
    my ($self) = @_;
    my $raw = $self->state()->read_state('ledger.installed.sha512', 256);
    return q{} if !defined $raw;
    $raw =~ /\A([0-9a-f]{128})\n\z/
        or die "stored Ledger installation hash is invalid\n";
    return $1;
}

sub _installed_version {
    my ($self) = @_;
    my $raw = $self->state()->read_state('ledger.installed.version', 128);
    return q{} if !defined $raw;
    $raw =~ /\A([0-9]+(?:\.[0-9]+)+)\n\z/
        or die "stored Ledger installation version is invalid\n";
    return $1;
}

sub _version_compare {
    my ($self, $left, $operator, $right) = @_;
    my $result = system('__INSTALLER_PATH_DIR_USR__/bin/dpkg', '--compare-versions', $left, $operator, $right);
    return 1 if $result == 0;
    return 0 if $result == 256;
    die "Ledger version comparison failed\n";
}

sub fetch {
    my ($self, $work, $for_repository) = @_;
    my $policy = $self->release_policy();
    defined($for_repository) && $for_repository == 1
        or die "Ledger acquisition requires the native repository publisher\n";

    my $key = '__INSTALLER_PATH_DIR_USR_LOCAL_SHARE__/software/ledger/ledgerlive.pem';
    my ($metadata, $manifest, $signature, $image) = map { "$work/$_" } qw(
        ledger-latest-linux.yml ledger-live.sha512sum ledger-live.sha512sum.sig ledger-live-linux-x86_64.AppImage
    );
    my $release;
    eval {
        $self->_assert_key($key);
        $self->http()->download(
            label => 'Ledger release metadata',
            url => $policy->{metadata_url},
            destination => $metadata,
            content_policy => 'metadata',
        );
        $release = $self->_parse_metadata($metadata);
        my $base = $policy->{checksums_base_url}
            . "$release->{version}.sha512sum";
        $self->http()->download(
            label => 'Ledger checksum manifest',
            url => $base,
            destination => $manifest,
            content_policy => 'metadata',
        );
        $self->http()->download(
            label => 'Ledger checksum signature',
            url => "$base.sig",
            destination => $signature,
            content_policy => 'artifact',
        );
        system('__INSTALLER_PATH_DIR_USR__/bin/openssl', 'dgst', '-sha256', '-verify', $key, '-signature', $signature, $manifest) == 0
            or die "Ledger checksum signature verification failed\n";
        $self->http()->download(
            label => 'Ledger Live AppImage',
            url => $policy->{requested_latest_url},
            destination => $image,
            content_policy => 'artifact',
        );
        1;
    } or return (1, $@ =~ /signature|fingerprint/i ? 'signature' : 'download');

    -s $image == $release->{size}
        or return (1, 'validation');
    my $sha512 = eval { $self->_digest($image, 512) };
    return (1, 'validation') if !$sha512 || !$self->_is_elf($image);
    $sha512 eq $self->_manifest_digest($manifest, $release->{path})
        && encode_base64(pack('H*', $sha512), q{}) eq $release->{sha512}
        or return (1, 'signature');

    my $old_hash = $self->_installed_hash();
    my $old_version = $self->_installed_version();
    if ($old_version ne q{} && $self->_version_compare($release->{version}, 'lt', $old_version)) {
        return (1, 'downgrade');
    }
    return (2, 'current') if $old_hash eq $sha512;

    my ($stored, $created) = eval {
        $self->state()->retain_artifact('ledger', $image, $release->{path});
    };
    return (1, 'publish') if !$stored;
    $self->state()->write_state(
        'ledger.pending',
        join('|', $release->{version}, $sha512, $release->{path}) . "\n",
    );
    $self->event()->emit('downloaded', 'ledger', $old_version || 'unknown', $release->{version})
        if $created;
    return (0, 'downloaded');
}

1;

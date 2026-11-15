package APTRepoLocal::Servicing::Tuta;

use strict;
use warnings;

use Moo;
use MooX::StrictConstructor;

use Digest::SHA;

has http  => (is => 'ro', required => 1);
has event => (is => 'ro', required => 1);
has state => (is => 'ro', required => 1);
has release_policy => (is => 'ro', required => 1);


sub _sha256 {
    my ($self, $path) = @_;
    -f $path && !-l $path
        or die "Tuta AppImage is not a regular file\n";
    open my $fh, '<:raw', $path
        or die "cannot read Tuta AppImage: $!\n";
    my $digest = Digest::SHA->new(256);
    $digest->addfile($fh);
    close $fh
        or die "cannot close Tuta AppImage: $!\n";
    return $digest->hexdigest();
}

sub _is_elf {
    my ($self, $path) = @_;
    open my $fh, '<:raw', $path
        or die "cannot inspect Tuta AppImage: $!\n";
    my $header = q{};
    read $fh, $header, 4;
    close $fh
        or die "cannot close Tuta AppImage inspection: $!\n";
    return $header eq "\x7fELF";
}

sub _installed_hash {
    my ($self) = @_;
    my $raw = $self->state()->read_state('tuta.installed.sha256', 128);
    return q{} if !defined $raw;
    $raw =~ /\A([0-9a-f]{64})\n\z/
        or die "stored Tuta installation state is invalid\n";
    return $1;
}

sub _pending {
    my ($self) = @_;
    my $raw = $self->state()->read_state('tuta.pending', 256);
    return undef if !defined $raw;
    my ($hash, $name) = $raw =~ /\A([0-9a-f]{64})\|(tuta-[0-9a-f]{64}\.AppImage)\n\z/
        or die "stored Tuta pending state is invalid\n";
    return { hash => $hash, name => $name };
}

sub _event_hash {
    my ($self, $hash) = @_;
    return $hash =~ /\A[0-9a-f]{64}\z/
        ? 'sha256:' . substr($hash, 0, 12)
        : 'unknown';
}

sub fetch {
    my ($self, $work, $for_repository) = @_;
    defined $for_repository && $for_repository == 1
        or die "Tuta acquisition requires the native repository publisher\n";
    my $key = '__INSTALLER_PATH_DIR_USR_LOCAL_SHARE__/software/tuta/tutao-pub.pem';
    return (1, 'signature') if !-r $key || -l $key;

    my $image = "$work/tutanota-desktop-linux.AppImage";
    my $signature = "$work/tutanota-linux-sig.bin";
    eval {
        $self->http()->download(
            label => 'Tuta Mail AppImage',
            url => $self->release_policy()->{service_urls}{tuta_appimage},
            destination => $image,
            content_policy => 'artifact',
        );
        $self->http()->download(
            label => 'Tuta Mail signature',
            url => $self->release_policy()->{service_urls}{tuta_signature},
            destination => $signature,
            content_policy => 'artifact',
        );
        system('__INSTALLER_PATH_DIR_USR__/bin/openssl', 'dgst', '-sha512', '-verify', $key, '-signature', $signature, $image) == 0
            or die "Tuta signature verification failed\n";
        $self->_is_elf($image)
            or die "Tuta AppImage is not an ELF binary\n";
        1;
    } or return (1, $@ =~ /signature/i ? 'signature' : 'download');

    my $hash = eval { $self->_sha256($image) };
    return (1, 'validation') if !$hash;
    my $installed = $self->_installed_hash();
    return (2, 'current') if $installed eq $hash;

    my $name = "tuta-${hash}.AppImage";
    my $previous_pending = $self->_pending();
    my ($stored, $created) = eval {
        $self->state()->retain_artifact('tuta', $image, $name);
    };
    return (1, 'publish') if !$stored;
    $self->state()->write_state('tuta.pending', "$hash|$name\n");
    $self->event()->emit(
        'downloaded',
        'tuta',
        $self->_event_hash($installed),
        $self->_event_hash($hash),
    ) if $created || !defined $previous_pending
        || $previous_pending->{hash} ne $hash;
    return (0, 'downloaded');
}

1;

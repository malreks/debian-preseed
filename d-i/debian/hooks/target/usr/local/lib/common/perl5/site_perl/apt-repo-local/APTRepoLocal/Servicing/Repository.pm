package APTRepoLocal::Servicing::Repository;

use strict;
use warnings;

use lib '__INSTALLER_PATH_DIR_PERL5_SITE_PERL__/runtime';
use Managed::Process qw(capture_command);
use Moo;
use MooX::StrictConstructor;
use MooX::Types::MooseLike::Base qw(Str);
use JSON::PP qw(decode_json);
use APTRepoLocal::Servicing::Process;

# Compatibility boundary for explicit installer/bootstrap and offline repair.
# Runtime publication belongs exclusively to apt-repo-local; it never
# installs packages or invokes APT from an APT update hook.
has directory => (is => 'ro', isa => Str, default => sub { '__INSTALLER_PATH_DIR_VAR_LIB_SOFTWARE__/repo' });
use constant HELPER => '__INSTALLER_PATH_DIR_USR_LOCAL_LIBEXEC__/apt-repo-local';

sub _capture {
    my ($self, @command) = @_;
    @command or return;
    delete $self->{capture_failure_detail};
    # The package import handoff itself may process a large external archive
    # indefinitely. Catalogue and metadata queries retain their short command
    # timeout because they are not transfers or installs.
    my $timeout = $command[0] eq HELPER && ($command[1] // q{}) eq 'import'
        ? 7200 : 120;
    my $result = capture_command(argv => \@command, timeout => $timeout, limit => 4_194_304);
    if ($result->{status} != 0) {
        # Keep the shared capture status raw. Decode once for this public
        # diagnostic; never mistake a timeout, signal, or ordinary exit for
        # success.
        my $status = $result->{status};
        my $detail = ($result->{error} // q{}) eq 'timeout'
            ? (defined($timeout)
                ? "deadline exceeded after ${timeout}s; operation outcome may be unknown"
                : 'operation returned an unexpected timeout status; outcome may be unknown')
            : ($status & 127) ? 'signal ' . ($status & 127)
            : 'exit ' . ($status >> 8);
        # The importer emits a bounded managed diagnostic. Do not expose raw
        # subprocess output or URL credentials/query strings from child errors.
        my ($managed) = ($result->{stderr} // q{}) =~ /^apt-repo-local: ([^\r\n]*)/m;
        if (defined $managed) {
            $managed =~ s{https?://\S+}{[redacted-url]}gi;
            $managed =~ s/[\x00-\x1f\x7f]/?/g;
            $detail .= ': ' . substr($managed, 0, 512);
        }
        $self->{capture_failure_detail} = $detail;
        return;
    }
    return $result->{stdout};
}

sub refresh {
    my ($self) = @_;
    system(HELPER, 'rebuild') == 0
        or die "managed repository publication failed\n";
    return 1;
}

sub rebuild { return $_[0]->refresh(); }
sub write_source {
    system(HELPER, 'init') == 0
        or die "managed repository initialization failed\n";
    return 1;
}

sub retain {
    my ($self, $source, $metadata) = @_;
    my $path = $self->_capture(HELPER, 'import', '--', $source);
    defined $path or die 'managed repository import failed ('
        . ($self->{capture_failure_detail} // 'no importer result') . ")\n";
    chomp $path;
    my $directory = $self->directory();
    $path =~ m{\A\Q$directory\E/pool/[a-z0-9][a-z0-9+.-]+/[0-9a-f]{64}/[A-Za-z0-9_.+:~-]+\.deb\z}
        or die "managed repository returned an unsafe package path\n";
    return wantarray ? ($path, 1) : $path;
}

sub latest {
    my ($self, $deb, $spec) = @_;
    my $raw = $self->_capture(HELPER, 'list');
    defined $raw or die "managed repository catalogue is unavailable\n";
    my $catalog = decode_json($raw);
    ref $catalog eq 'HASH' && ref $catalog->{packages} eq 'HASH'
        or die "managed repository catalogue is invalid\n";
    my %wanted = map { $_ => 1 } @{$spec->{packages}};
    my $candidate;
    for my $record (values %{$catalog->{packages}}) {
        next if !$wanted{$record->{package}};
        my $relative = $record->{filename};
        $relative =~ m{\Apool/[a-z0-9][a-z0-9+.-]+/[0-9a-f]{64}/[A-Za-z0-9_.+:~-]+\.deb\z}
            or die "managed repository catalogue path is invalid\n";
        my $path = $self->directory() . "/$relative";
        my $metadata = $deb->validate_spec($path, $spec, "$spec->{label} retained archive");
        next if !$metadata;
        if (!$candidate || system('__INSTALLER_PATH_DIR_USR__/bin/dpkg', '--compare-versions', $metadata->{version},
                                  'gt', $candidate->{metadata}->{version}) == 0) {
            $candidate = { path => $path, metadata => $metadata };
        }
    }
    return $candidate;
}

sub repair {
    my ($self, $deb, $spec) = @_;
    my @packages = @{$spec->{packages}};
    for my $package (@packages) {
        my $status = $self->_capture('__INSTALLER_PATH_DIR_USR__/bin/dpkg-query', '-W', '-f=${Status}', $package) // q{};
        next if $status eq q{} || $status eq 'unknown ok not-installed'
            || $status eq 'deinstall ok config-files' || $status eq 'purge ok not-installed';
        if ($status eq 'install ok installed' && $deb->installed_payload_valid($spec)) {
            return 1;
        }
        my @executables = (
            $spec->{executable},
            @{$spec->{in_use_executables} // []},
        );
        return 0 if APTRepoLocal::Servicing::Process->application_running(
            executables => \@executables,
            roots       => $spec->{in_use_roots} // [],
        );
        my $version = $self->_capture('__INSTALLER_PATH_DIR_USR__/bin/dpkg-query', '-W', '-f=${Version}', $package) // q{};
        chomp $version;
        my $candidate = eval { $self->latest($deb, $spec) };
        my $archive = $candidate ? $candidate->{path} : undef;
        if (defined $archive && -f $archive && !-l $archive) {
            my $metadata = eval {
                $deb->validate_spec(
                    $archive,
                    $spec,
                    "$spec->{label} retained archive",
                );
            };
            my $repaired = $metadata && eval {
                $self->refresh();
                $deb->install($archive, 1);
                $deb->installed_payload_valid($spec);
            };
            if ($repaired) {
                return 1;
            }
        }
        if ($status ne 'install ok installed') {
            system('__INSTALLER_PATH_DIR_USR__/bin/dpkg', '--remove', '--force-remove-reinstreq', $package) == 0
                || system('__INSTALLER_PATH_DIR_USR__/bin/dpkg', '--purge', '--force-all', $package) == 0
                or die "$spec->{label} could not be removed from unrecoverable dpkg state\n";
        }
        return 0;
    }
    return 1;
}

1;

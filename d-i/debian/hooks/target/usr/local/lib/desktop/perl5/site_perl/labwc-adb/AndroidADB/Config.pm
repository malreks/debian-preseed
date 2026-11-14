package AndroidADB::Config;

use strict;
use warnings;

use Cwd qw(abs_path);
use Fcntl qw(S_ISDIR);
use File::Spec;
use Moo;
use MooX::StrictConstructor;
use MooX::TypeTiny;
use Types::Standard qw(HashRef Int Str);

use AndroidADB::Validation qw(fail require_value);

my %TOOL_CANDIDATES = (
    ffprobe => ['__INSTALLER_PATH_DIR_USR__/bin/ffprobe'],
    adb => [
        '__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/adb',
        '__INSTALLER_PATH_DIR_USR__/bin/adb',
        '/bin/adb',
    ],
    df => [
        '__INSTALLER_PATH_DIR_USR__/bin/df',
        '/bin/df',
    ],
    fastboot => [
        '__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/fastboot',
        '__INSTALLER_PATH_DIR_USR__/bin/fastboot',
        '/bin/fastboot',
    ],
    notify_send => [
        '__INSTALLER_PATH_DIR_USR__/bin/notify-send',
        '/bin/notify-send',
    ],
    samloader => [
        '__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/samloader',
        '__INSTALLER_PATH_DIR_USR__/bin/samloader',
        '/bin/samloader',
    ],
    scrcpy => [
        '__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/scrcpy',
        '__INSTALLER_PATH_DIR_USR__/bin/scrcpy',
        '/bin/scrcpy',
    ],
    systemctl => [
        '__INSTALLER_PATH_DIR_USR__/bin/systemctl',
        '/bin/systemctl',
    ],
    samsung_extractor => [
        '__INSTALLER_PATH_DIR_USR_LOCAL_LIBEXEC__/labwc-samsung-firmware-extract',
    ],
    ss => [
        '__INSTALLER_PATH_DIR_USR__/bin/ss',
        '/bin/ss',
    ],
    terminal => [
        '__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/labwc-terminal',
    ],
    wayland_app => [
        '__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/labwc-wayland-app',
    ],
    timeout => [
        '__INSTALLER_PATH_DIR_USR__/bin/timeout',
        '/bin/timeout',
    ],
);

has runtime_dir => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has home => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has server_marker => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has tool_paths => (
    is       => 'ro',
    isa      => HashRef,
    required => 1,
);

has adb_server_port => (
    is      => 'ro',
    isa     => Int,
    default => sub { 5037 },
);

has adb_probe_seconds => (
    is      => 'ro',
    isa     => Int,
    default => sub { 6 },
);

has adb_start_seconds => (
    is      => 'ro',
    isa     => Int,
    default => sub { 20 },
);

has adb_command_seconds => (
    is      => 'ro',
    isa     => Int,
    default => sub { 120 },
);

has adb_wait_seconds => (
    is      => 'ro',
    isa     => Int,
    default => sub { 60 },
);

has adb_transfer_seconds => (
    is      => 'ro',
    isa     => Int,
    default => sub { 900 },
);

has adb_backup_seconds => (
    is      => 'ro',
    isa     => Int,
    default => sub { 14_400 },
);

has adb_backup_headroom_kib => (
    is      => 'ro',
    isa     => Int,
    default => sub { 1_048_576 },
);

has samsung_download_seconds => (
    is      => 'ro',
    isa     => Int,
    default => sub { 21_600 },
);

has samsung_flash_seconds => (
    is      => 'ro',
    isa     => Int,
    default => sub { 14_400 },
);

has samsung_download_wait_seconds => (
    is      => 'ro',
    isa     => Int,
    default => sub { 90 },
);

has samsung_download_minimum_free_kib => (
    is      => 'ro',
    isa     => Int,
    default => sub { 16_777_216 },
);

has samsung_firmware_minimum_archive_bytes => (
    is      => 'ro',
    isa     => Int,
    default => sub { 104_857_600 },
);

has samsung_firmware_maximum_archive_bytes => (
    is      => 'ro',
    isa     => Int,
    default => sub { 25_769_803_776 },
);

has samsung_firmware_format => (
    is      => 'ro',
    isa     => Str,
    default => sub { 'samsung-firmware-v1' },
);

sub from_environment {
    my ($class) = @_;

    require_value($> != 0, 'labwc-adb-action must run as the logged-in desktop user');

    for my $override (qw(ADB_SERVER_SOCKET ANDROID_ADB_SERVER_PORT)) {
        require_value(
            !defined($ENV{$override}) || $ENV{$override} eq q{},
            "$override overrides are not supported by the managed launcher",
        );
    }

    my @account = getpwuid($<);
    require_value(scalar(@account), "desktop account is unavailable for UID $<");
    my ($account_uid, $account_home) = @account[2, 7];
    require_value(
        defined($account_uid) && $account_uid == $<,
        "desktop account does not match UID $<",
    );
    my $runtime_dir = File::Spec->catdir('__INSTALLER_PATH_DIR_RUN_USER__', $<);
    _validate_runtime_dir($runtime_dir, $<);
    my $bus_path = File::Spec->catfile($runtime_dir, 'bus');
    my @bus_metadata = lstat($bus_path);
    require_value(
        @bus_metadata
            && (($bus_metadata[2] & 0170000) == 0140000)
            && $bus_metadata[4] == $<
            && $bus_metadata[3] == 1,
        'ADB user bus socket is unavailable or unsafe',
    );
    _validate_home($account_home, $<);

    my %tool_paths;
    for my $tool (qw(adb df ss timeout)) {
        $tool_paths{$tool} = _resolve_tool($tool, 1);
    }
    for my $tool (qw(fastboot notify_send samloader scrcpy samsung_extractor systemctl terminal wayland_app)) {
        $tool_paths{$tool} = _resolve_tool($tool, 0);
    }

    return $class->new(
        runtime_dir   => $runtime_dir,
        home          => $account_home,
        server_marker => File::Spec->catfile($runtime_dir, 'labwc-adb-server.managed'),
        tool_paths    => \%tool_paths,
    );
}

sub tool {
    my ($self, $name) = @_;
    return $self->tool_paths->{$name};
}

sub require_tool {
    my ($self, $name, $message) = @_;
    my $path = $self->tool($name);
    return $path if defined($path) && $path ne q{};
    fail($message // "required Android Debug Bridge command is not installed: $name");
}

sub output_root {
    my ($self) = @_;
    return File::Spec->catdir($self->home, 'Android', 'adb');
}

sub _validate_runtime_dir {
    my ($runtime_dir, $uid) = @_;
    require_value(
        (
            defined($runtime_dir)
                && !ref($runtime_dir)
                && !!($runtime_dir =~ m{\A/})
        ),
        'ADB runtime directory must be an absolute path',
    );
    my @metadata = lstat($runtime_dir);
    require_value(
        (
            @metadata
                && S_ISDIR($metadata[2])
                && $metadata[4] == $uid
                && !-l $runtime_dir
                && ($metadata[2] & 0o077) == 0
                && -w $runtime_dir
        ),
        "ADB runtime directory is unavailable: $runtime_dir",
    );
    return 1;
}

sub _validate_home {
    my ($home, $uid) = @_;
    require_value(
        (defined($home) && !ref($home) && !!($home =~ m{\A/})),
        'HOME must be an absolute path',
    );
    require_value(
        (
            !!($home !~ /[\r\n]/)
                && index($home, '..') < 0
                && index($home, '//') < 0
        ),
        'HOME contains unsupported path syntax',
    );
    my @metadata = lstat($home);
    require_value(
        (
            @metadata
                && S_ISDIR($metadata[2])
                && $metadata[4] == $uid
                && !-l $home
        ),
        "desktop HOME is unavailable or does not belong to the current user: $home",
    );
    return 1;
}

sub _resolve_tool {
    my ($name, $required) = @_;
    my $candidates = $TOOL_CANDIDATES{$name};
    defined($candidates) or fail("unknown managed Android tool: $name");

    for my $candidate (@{$candidates}) {
        next if !-e $candidate || !-x $candidate;
        my $resolved = abs_path($candidate);
        next if !defined($resolved) || !-f $resolved || !-x $resolved;
        return $candidate;
    }

    fail("required Android Debug Bridge command is not installed: $name") if $required;
    return undef;
}

1;

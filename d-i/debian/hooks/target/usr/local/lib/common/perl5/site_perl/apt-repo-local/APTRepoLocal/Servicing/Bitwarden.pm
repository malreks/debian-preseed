package APTRepoLocal::Servicing::Bitwarden;

use strict;
use warnings;

use Moo;
use MooX::StrictConstructor;

use Fcntl qw(S_ISREG);
use APTRepoLocal::Servicing::Atomic;

sub _trusted_text {
    my ($self, $path, $limit) = @_;
    my @st = lstat $path;
    return undef if !@st
        || !S_ISREG($st[2])
        || $st[4] != 0
        || ($st[2] & 0022);
    my $text = eval {
        APTRepoLocal::Servicing::Atomic->read_limited($path, $limit);
    };
    return undef if $@;
    return $text;
}

sub _contains_all {
    my ($self, $text, $fragments) = @_;
    for my $fragment (@{$fragments}) {
        return 0 if index($text, $fragment) < 0;
    }
    return 1;
}

sub policy_valid {
    my ($self) = @_;
    my @requirements = (
        [
            '__INSTALLER_PATH_DIR_PYTHON3_SITE_PACKAGES__/labwc_managed_app/profiles.py',
            [
                '"bitwarden": {',
                '"exec": "__INSTALLER_PATH_DIR_OPT__/Bitwarden/bitwarden"',
                '"ELECTRON_OZONE_PLATFORM_HINT": "wayland"',
                '"args": electron_args("bitwarden", "launch")',
            ],
        ],
        [
            '__INSTALLER_PATH_DIR_PYTHON3_SITE_PACKAGES__/labwc_managed_app/electron.py',
            [
                'ELECTRON_PASSWORD_STORE = "--password-store=gnome-libsecret"',
                'features = ("UseOzonePlatform", *profile["features"])',
                'args.append(electron_password_store_arg(app_name))',
            ],
        ],
        [
            '__INSTALLER_PATH_DIR_PYTHON3_SITE_PACKAGES__/labwc_managed_app/session.py',
            [
                'def bitwarden_session_unit_argv(',
                '"--property=After=labwc-session.target labwc-kwallet-portal.service"',
                '"--property=Requisite=labwc-session.target labwc-kwallet-portal.service"',
                '"--property=PartOf=labwc-session.target labwc-kwallet-portal.service"',
            ],
        ],
        [
            '__INSTALLER_PATH_DIR_ETC_SKEL_DESKTOP__/.config/systemd/user/labwc-kwallet-portal.service',
            [
                'Type=dbus',
                'BusName=org.freedesktop.secrets',
                'Environment=QT_QPA_PLATFORM=wayland',
                'ExecStart=__INSTALLER_PATH_DIR_USR__/bin/ksecretd',
                'ExecStartPost=__INSTALLER_PATH_DIR_USR_LOCAL_LIBEXEC__/labwc-session-check kwallet-ready',
            ],
        ],
        [
            '__INSTALLER_PATH_DIR_ETC_SKEL_DESKTOP__/.local/share/dbus-1/services/org.freedesktop.secrets.service',
            [
                'Name=org.freedesktop.secrets',
                'QT_QPA_PLATFORM=wayland',
                'SystemdService=labwc-kwallet-portal.service',
            ],
        ],
        [
            '__INSTALLER_PATH_DIR_ETC_SKEL_DESKTOP__/.config/kwalletrc',
            [
                '[org.freedesktop.secrets]',
                'apiEnabled=true',
            ],
        ],
        [
            '__INSTALLER_PATH_DIR_APPARMOR__/opt.Bitwarden.bitwarden',
            [
                'profile bitwarden __INSTALLER_PATH_DIR_OPT__/Bitwarden/bitwarden',
                '#include <abstractions/electron-application>',
                'owner @{HOME}/.config/Bitwarden/** rwkl,',
                'owner @{HOME}/.local/share/Bitwarden/** rwkl,',
            ],
        ],
        [
            '__INSTALLER_PATH_DIR_APPARMOR__/abstractions/electron-application',
            ['#include <abstractions/electron-runtime>'],
        ],
        [
            '__INSTALLER_PATH_DIR_APPARMOR__/abstractions/electron-runtime',
            ['#include <abstractions/desktop-runtime>'],
        ],
        [
            '__INSTALLER_PATH_DIR_APPARMOR__/abstractions/desktop-runtime',
            [
                'include if exists <abstractions/dbus-session>',
                'owner __INSTALLER_PATH_DIR_RUN_USER__/[0-9]*/wayland-[0-9]* rw,',
            ],
        ],
        [
            '__INSTALLER_PATH_DIR_APPARMOR__/labwc-session',
            [
                'profile ksecretd __INSTALLER_PATH_DIR_USR__/bin/ksecretd flags=(attach_disconnected, mediate_deleted)',
                'owner @{HOME}/.config/{kwallet*,ksecret*,kdeglobals}* rwkl,',
                'owner link "@{HOME}/.config/kwalletrc.*" -> "@{HOME}/.config/#[0-9]*",',
                'owner @{HOME}/.local/share/{kwalletd,ksecretd}/** rwklm,',
                'owner link "@{HOME}/.local/share/kwalletd/*.{kwl,json}.*" -> "@{HOME}/.local/share/kwalletd/#[0-9]*",',
            ],
        ],
    );

    for my $requirement (@requirements) {
        my ($path, $fragments) = @{$requirement};
        my $text = $self->_trusted_text($path, 1_048_576);
        return 0 if !defined $text || !$self->_contains_all($text, $fragments);
    }
    return 1;
}

1;

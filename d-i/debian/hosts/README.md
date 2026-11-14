# Host profiles and installed policy

Concrete profiles live in `profiles/desktop/` and `profiles/server/`, with one
shared environment in each family and common defaults in `profiles/shared.env`.
Both suites use those same authored profiles;
there are no per-suite or per-tier copies. The corresponding physical suite
classes live under `classes/class-profile/{desktop,server}/`.

The restricted data compiler resolves suite runtime data and canonical runtime
directories, family defaults, the concrete profile, then missing common and
identity defaults. Common defaults never overwrite a family or host field.
They own the shared DevOps, non-GUI firmware, NFS and hosting policy. The former
separate hosting environment has been removed. The compiler resolves runtime
files and filesystem policy afterward.
Suite identity cannot be overridden by a profile. Each compiled environment has
field-level provenance. Profile data is never sourced as shell code.

Journal retention defaults belong to each family shared environment; concrete
hosts have no copied journal block and may add a same-name assignment only when
a deliberate host override is required. Server shared policy also owns the
rootless Podman identities, workload budgets and persistent provider paths under
`/pool/podman`; shipped concrete server profiles do not repeat those defaults.

`shared-de.env` owns the common desktop domain, hostname prefix and optional
`SYSTEM_NAMESERVERS_TLS_SAN_CUSTOM`; `shared-srv.env` owns the corresponding
server values. Concrete hosts can override them. The custom SAN defaults to
empty: each resolver retains its configured authenticated TLS hostname.
A nonempty override applies only with custom CA mode enabled. The private CA
still comes from the actual initrd and never disables certificate validation.

Every concrete profile declares independent root/home encryption, Wi-Fi, IPv6,
primary-interface, SSH, sharing and hardware policy. Btrfs profiles own Timeshift
schedules and retention. F2FS requires explicit `snapshots=none`; the installer
does not change the filesystem. Duo/dualboot profiles are quarantined before
partitioning because preservation has not been qualified.

Private account and AP credentials come from `/preseed.env` in the actual
Debian Installer initrd. This is unrelated to the checkout or served-tree root.
Public profile data must contain no passwords, tokens or private keys.

## Primary operator, DevOps and runner identities

Every server host profile declares `CODEX_ONLY_ENABLE`. With another server
role, true installs the verified Codex release, clones codex-home and configures
the primary operator's headless runtime. False omits that optional setup.
Selecting `role/server/devops` always installs Codex and the full non-GUI
DevOps tools, regardless of this boolean. The frozen plan owns one Codex stage
and one full toolchain stage even when several server roles are selected.

`PRESEED_PRIMARY_USERNAME` selects the human account. Its passwd entry supplies
the home for Codex, Bash fragments, Bazel, compiler state and rootless Podman.
The installer creates the shared `devops` group if needed and adds this account;
it does not substitute a runner's `HOME`. The server DevOps role installs
`71-devops-srv.sh`; selected Codex installs `99-codex-srv.sh`. Both fragments
only configure the login environment. Setup and cloning happen during the
unattended installation. Shared build/cache/database paths remain pool-backed.

GitHub and GitLab retain distinct locked `ci-github` and `ci-gitlab` identities,
UIDs 2101 and 2102, with `nologin`, private homes, subordinate IDs, Podman
stores and sockets. They receive no primary-account Git key, password, SSH
authorized key, `devops`, KVM or Incus membership. Their native enrollment uses
only their matching `PRESEED_CI_GITHUB_TOKEN` or `PRESEED_CI_GITLAB_TOKEN` from
the actual initrd credential file. These tokens are independent of Codex's
private Git clone input. The locked `srv-devops` account owns optional local
BuildBuddy service data; the human account owns interactive DevOps tools.

All required private clones consume the encrypted `/git_ed25519` pair and
`PRESEED_GIT_SSH_PASSPHRASE` from the actual initrd through the shared private
stdin/memfd/temporary-agent path. Every desktop tier, including base, installs
Obsidian and clones both the Obsidian vault and Netscape exports. Desktop
repository policy stays in `shared-de.env`; a server Codex install does not
require either desktop repository. Missing required Git credentials fail
clearly without using an ambient account or SSH agent. API login remains an
operator action after Codex installation.

## Desktop session and appearance

Every desktop profile explicitly declares `LABWC_WORKSPACE_COUNT_INTERNAL` and
`LABWC_WORKSPACE_COUNT_EXTERNAL`. Labwc workspaces span all outputs. An
internal-only topology uses the internal count; a topology with an enabled
external output uses the external count. The existing output watcher reconciles
this policy at startup and settled topology changes. A DPMS-off interval does
not become a new topology. Publication uses the existing output lock and keeps
the previous XML on an uncertain compositor reload; it does not start another
watcher. Counts do not imply independent per-monitor workspaces. This follows
the compositor's [native workspace model](https://labwc.github.io/labwc-config.5.html#workspaces).

All three desktop tiers stage the same Labwc, Waybar, menus, appearance editor
and native desktop services. Base includes the everyday desktop applications;
medium and full add their own application and specialist workloads. Native
Debian Python and systemd packages follow the newest eligible candidates of
the selected suite, without fixed minor-version paths or package versions.

Desktop Appearance manages the existing desktop controls, icon/pointer themes
and toolkit appearance. Its field registry contains Fuzzel, Waybar, Taskview,
Waycal, Crystal Dock, GtkGreet, terminal appearance, Swaylock and Mako. It has
no L3afpad, KeePass or other application-preference pages. Field defaults are
rendered once; source-line/token mappings remain available for validated runtime
edits. The same per-account lock and recovery journal cover native file updates.
Only the authenticated greeter helper can change its fixed system files.

Theme acquisition, bounded extraction and initial default capture live under
the desktop installer sources. Private setup code is staged temporarily,
checked for root ownership and removed after each operation. Installed runtime
assets contain the editor, captured non-secret defaults, mapping registry and
greeter recovery helper, without installation-only entrypoints.

## OpenSSH server policy

All thirteen concrete profiles declare `SSH_SERVER_ENABLE` as literal `true`
or `false`. Desktop defaults are false; server defaults are true. Every profile
also declares its five-digit `SSH_SERVER_PORT` in 30000..40000 and explicit
user/source-network policy. Server role class files include `openssh-server`
and `openssh-sftp-server` directly. On desktops, a true boolean incorporates the
suite-owned `fragments/ssh.cfg` package answers into the frozen plan before
pkgsel. There is no optional SSH class.

A true value configures public-key-only SSH for the primary user. The installer
first checks `/lan_ed25519.pub` at the actual initrd root, beside `/preseed.env`.
Only when absent does it check the authenticated payload's `ssh/lan_ed25519.pub`
member, authored at `d-i/debian/ssh/lan_ed25519.pub`. It never fetches an unpinned
moving fallback. Missing keys are nonfatal: installation and SSH configuration
continue, and authorization is reported as pending. No default or generated
login key substitutes for the missing input.

The existing SSH installer shell code validates the public key with the target
OpenSSH tool, then adds it to the primary user's `.ssh/authorized_keys`. It
preserves other entries and does not append an identical key twice. The user
owns the directory and file, with modes 0700 and 0600 respectively. This runs
during offline installation; no authorization wrapper is installed.

False disables and masks SSH activation, omits desktop server packages and
prevents an SSH firewall opening. Server packages remain available without
activation. Desktop socket activation uses explicit paired Ethernet/Wi-Fi
addresses and FreeBind; server access remains limited by the profile ACL and
both managed interface names. Fail2ban and CrowdSec SSH detection follow the
same boolean. Tailscale SSH retains its separate explicit policy.

These contracts have source/static evidence only. No target authentication,
service start, firewall load, boot or network acceptance is claimed.

## Sharing mount storage

The public sharing root remains empty during installation. Its backing tree is
`<parent>/.<sharing-name>-store/root` (normally `/data/.sharing-store/root`). The
backing parent is root-owned mode `0700`, so ordinary accounts cannot bypass the
public mount's restrictions through its source path. At boot it is bound to
`/data/sharing` with the existing shared propagation and safety options; the
recursive slave mount at `~/Sharing` receives later NFS mounts.

NFS and Filen installation populate the backing tree offline. An existing
nonempty public destination or an unowned backing tree is refused and preserved.
This layout is for fresh installs; it does not migrate an installed system's
existing sharing data.

## Native client rendering and panel status

Intel and NVIDIA actions resolve the requested vendor from kernel PCI, driver
and render-node identity. On the reported P15s these are Intel `0000:00:02.0`
at `renderD128` and NVIDIA `0000:2d:00.0` at `renderD129`; enumeration numbers
are discovered at each launch. Native managed sandboxes expose only the selected
render node and its required NVIDIA graphics devices. EGL vendor, Firefox and
Chromium selectors use that same identity. Missing or ambiguous explicit GPU
selection fails before client startup. Existing Vulkan restrictions remain.
An unspecified `launch` with no supported PCI GPU retains the software-capable
native launch path; that does not satisfy an explicit Intel/NVIDIA request.
An application's already-running process keeps its original renderer until it
exits; a new environment cannot migrate that process to another GPU.

Waybar uses native Bluetooth and backlight modules. Battery, notification mode
and recording state use continuous readers with cached JSON output, bounded
event handling and reconciliation without subprocesses. Keyboard status runs
at startup and on its existing change signal. Menus and control actions remain
available. The display watcher reconciles at startup and on settled DRM events
instead of invoking output policy on an unconditional 30-second timer.
The SNI tray module is enabled in every host profile. Each profile defines the
same `LABWC_WAYBAR_TRAY_ENABLE` variable with `true` as its value. The
renderer retains a boolean compatibility switch for explicit callers, while
the profile contract keeps the tray present. Managed application D-Bus proxy
permissions and application launchers are unchanged.

Audit execution telemetry remains enabled. These source changes remove the
recurring status command chains; they do not establish a measured reduction
in CPU, audit volume, CrowdSec load or power consumption.

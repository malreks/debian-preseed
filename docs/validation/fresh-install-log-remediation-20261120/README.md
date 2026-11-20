# Fresh-install corrections, 2026-11-20

This work targets newly formatted installations. It adds no migration, existing
account updater, installed-host repair workflow or deployment. The corrections
listed below are implemented, but full installation, enforcing-policy, logged-in-session and
physical-hardware acceptance remain incomplete. The generated support matrix must
retain its qualification limits.

## Installer and firstboot ownership

The installer keeps class selection and the frozen plan in its own execution
environment. It no longer publishes `classes.tsv`, its target-path key or a
runtime class reader. The existing scalar/path renderer publishes component
settings before reboot:

- Firstboot receives concrete release, suite and desktop tier expectations.
- CrowdSec receives its optional desktop collection switch and SSH policy.
- Server provisioning and its controller receive the selected server roles.

Firstboot checks the running target and collects diagnostics. It does not render
the desktop configuration again or repair its ownership. The desktop defaults
metadata check is read-only. Firstboot no longer executes awk, mawk, gawk or nawk
to read class selection. Replacing the receipt parser with another interpreter
would retain an unnecessary target dependency; that parser was removed.

Settled boot evidence is separate from the installation plan. Its atomic receipt
records boot ID, rendered release, starting/pending/timeout/failed/verified state
and failures. Successful completion and cleanup require matching verified
evidence. The nonblocking `Type=exec` service boundary is retained. This does not
establish acceptance of an installed boot or an actual user session.

The final collector checks the complete enabled-unit inventory and its required
static dependency closure in bounded batches. It uses systemd's installed
enablement and [unit metadata interface](https://www.freedesktop.org/software/systemd/man/latest/org.freedesktop.systemd1.html),
including canonical aliases and exact installed template instances, instead of
reading installer class data. A single 45-second deadline covers all queries;
each query and the aggregate capture have explicit byte limits. Successful
one-shots, checked inapplicable conditions, armed event services and completion
gated cleanup are distinct from missing execution, failed, pending, timed out or
unknown cleanup outcomes. A changing inventory remains pending. Later pending
work cannot relabel an earlier hard failure.

## Complete log coverage and correlation

[log-coverage.tsv](log-coverage.tsv) records all 104 regular files recursively
below `todo/`, including 31 empty files, their sizes, line counts and SHA-256
digests. The read covered 48,417,714 bytes and 206,781 newline records. Empty files
are recorded as absence of execution evidence. Empty locks also do not establish
that an associated operation completed.

[audit-correlation.json](audit-correlation.json) correlates audit epoch/serial,
record type and body across all three rotations and the AppArmor mirror. Enriched
audit ASCII group separators remain within their newline record. The supplied
authoritative files contain 190,361 distinct records. All 532 AppArmor records
match the mirror exactly, with no mirror duplicates or missing supplied records.
The 66 denials form five distinct caller/path classes. Mirrored records are not
counted twice. This bounded capture does not establish rotation reliability.

The logged release matched both checked-in suite receipts before editing:
`25a9a1db6f428c75e2e57387e2765b21c22eca265dc1ed77e8d7d7cab50b173c`.
The initial worktree was clean. The failures were not attributed to a stale
deployment. Service evidence is correlated within the supplied boot by unit,
process and timestamp. The full disposition and source-owner record is
[issues.json](issues.json). It includes subsequently discovered implementation
and fixture failures; fixed source defects do not qualify unrelated runtime gates.

## Implemented shared contracts

The source changes include fixed literal btop config operands at the actual shell
boundary; native Waybar menu ownership and installation-time canonical leaf/action
validation; removal of displaced popup helpers and fabricated popup activity;
normal external status font weight; profile-local Python site-directory access;
exact keyboard-home and logging-socket directory grants; one private physical
network lock directory; verified PARTUUID swap configuration; compatible signed
polkit dependency guards; unified KWallet activation aliases and actual provider
readiness; reminder serialization; and requested/effective AI capability fields.

The firstboot profile's writable installer-state access is limited to its own log
subtree. It does not receive class-receipt access or additional executable
wildcards. Mandatory managed profiles remain enforcing in source policy. No host
policy was loaded, no public Xwayland was installed, and the existing private
Zoom/Discord eligibility was preserved.

The signed KWallet package's `org.freedesktop.impl.portal.desktop.kwallet` and
`org.kde.secretservicecompat` aliases both launch `ksecretd`. Fresh account overrides
route these and Secret Service through one managed unit. `kwalletd6` retains its
separate vendor activation. A running unrelated daemon no longer satisfies the
managed Bitwarden prerequisite merely by existing. Interface readiness does not
claim that a wallet is unlocked.

Notifier work combines repeated metadata probes without caching trust, avoids
unchanged state publications and chmod operations, and explicitly propagates
state-reader failures. Failure injection found that conditional shell callers
could ignore a rejected state read. The corrected code reports the failure while
continuing independent security-signal checks. No execution-audit policy was
disabled to obtain a reported improvement.

## Evidence boundary

All native helper execution occurred in private networkless QEMU guests with no
host directory mounts, service sockets, credentials or device passthrough. Kernel
and initramfs identities, source hashes, package metadata, exact commands, serial
captures and deadlines are retained under the disk-backed private directory
`.build/validation/log-remediation-20261120/`. `TMPDIR`, `TMP` and `TEMP` point there
for host commands. The guests use their own private runtime filesystems.

The image uses the identified Debian installer kernel `6.12.107+deb13-amd64` and
authenticated Forky package data. This is an extracted-package fixture, not a
completed Debian installation or the logged operator kernel. Actual packages
include labwc `0.20.3-1`, Waybar `0.15.0-1+b1`, Python interpreter `3.14.10-1`,
rsyslog `8.2610.0-3`, AppArmor `4.1.8-3+b1`, hyprpolkitagent `0.2.0-1` and
KWallet `6.30.0-1`. No package maintainer script ran on the development host.

The native fixture's interpreter aliases, image-loader and MIME caches must be
complete before GUI results count. Failed fixture runs are retained as failures.
An init-script failure that booted guest systemd, a fixture syntax error and
missing image-loader/cache setup are not product passes. QEMU's exit code alone
does not establish fixture success; the recorded `GUEST_RESULT` is authoritative.

Completed bounded checks so far:

- Actual Dash shell and fixed normalizer preserved both literal btop operands
  for home names with spaces and punctuation and rejected extra/injected argv.
- The actual shell serializer, Perl renderer and strict reminder reader agreed
  on all eight fields, disabled transports and booleans. Malformed quoting,
  duplicate keys and invalid controls were rejected; no notification was sent.
- Six desktop suite/tier render cases and selected single/combined server-role
  cases worked without an installed class receipt. The actual firstboot wrapper
  preserved failure evidence, retried, published matching completion, skipped a
  repeated successful invocation and reran after stale boot evidence.
- Actual GtkBuilder loading under native Wayland validated 13 menu contracts.
  The installation validator rejected missing, unknown, wrong-type, duplicate,
  competing-event and injected action data. The standalone popup's failure to
  map was reproduced, establishing the condition for native in-process ownership.
- Fully rendered firstboot, labwc-session, desktop-wrappers,
  desktop-system-wrappers and waybar-menus profiles compiled offline against private package
  support with explicit configuration, ABI/features, `-Q -K`, one compile job and
  a 120-second per-file deadline. No policy loaded and the private cache stayed
  empty. Run 43 includes the current narrowed firstboot and local Python rules.
- Actual keyboard, Waybar trampoline, state reader and logging-socket helpers
  succeeded under observed intended enforcing attachments. The logging socket
  had UID/GID 1000:1001 and mode 0660. Negative checks denied arbitrary ownership
  changes, recursive home/local-package access, receipt writes and forbidden
  execution. Run 46 remains a failed run because its forbidden-execution observer
  entered the wrong boundary; supplemental run 48 entered through the approved
  interpreter and completed that case. See [apparmor-enforcement.json](apparmor-enforcement.json).
- Run 66 exercised the actual Waybar trampoline-to-state-helper chain with no
  new audit denials. Valid bounded markers worked; mismatched identity/schema,
  unsafe mode, symlinks, hardlinks, FIFO, oversized content and raced replacement
  were rejected. Cleanup removed only a valid exact marker. The replacement
  injection was a separate ordinary-user case, not an enforcing-profile claim.
- Run 68 exercised actual physical-network helper locking under its observed
  enforcing profile. Boot/manual calls shared one inode and waited; dispatcher
  calls deferred without backend work. Exact mode, unsafe links/FIFO, inode
  replacement, the production 45-second timeout, bounded reads and child reap
  passed. NetworkManager/radio/backend outcomes were simulated; actual network
  priority, saved-profile authentication and hardware recovery remain open.
- Runs 55/67 exercised both actual swap configuration producers, the shell
  serializer, Perl renderer and whole consumer. Missing/wrong identity, size,
  conflicting mapping and failed-probe-with-valid-output cases failed before
  publication or destructive calls; valid and already-active paths were
  repeatable. Block, cryptsetup, mkswap and swapon commands were mocked.
- Native systemd-tmpfiles 262.2 preserved the signed vendor X11 rules and created
  all four socket directories root-owned at mode 1777 through repeated combined
  remove/create operations, with exactly one X11 directory rule.
- Matching rsyslog delivered all 199 numbered records exactly once across
  rename/create, consecutive rotations, restart, interrupted checkpoint restart
  and final partial batches. Hostile denial-looking EXECVE data produced no
  mirror record or alert. Exactly the two real anchored denials produced signals.
  The logged watch-descriptor warning was not reproduced; its cause remains open.
- The final audited notifier measurement reduced unchanged-cycle median CPU from
  1.702 to 1.008 seconds, elapsed time from 2.148 to 1.252 seconds, executable
  calls from 140 to 80, process creation from 195 to 122, writes from 90 to 72
  and audit bytes from 253,425 to 150,370. Three unchanged cycles, event delivery
  and unsafe-state failures were checked. Audit execution rules remained active,
  lost records were zero and auditd shut down successfully with the actual
  rendered ENRICHED configuration. These are TCG fixture measurements, not
  physical desktop performance. Per-child tree high-water memory was unchanged
  at 22,172 KiB, including the fixed launcher/timeout. Context-switch counts do
  not measure timer wakeups. See [notifier-performance.json](notifier-performance.json).
- Native screenshots at scales 1, 1.25, 1.5 and 2 show the normal external status
  font weight using actual production CSS. Each layer surface had attached and
  committed a real buffer before capture. All eight images were inspected. The
  status-only fixture had identical before/after visible pixel heights at
  each scale (48, 60, 73 and 96 pixels). Those bounds are not a direct GTK logical
  allocation measurement. Keyboard/network glyph variants, internal output,
  hover and drawer geometry remain separate gates. See [visual-evidence.json](visual-evidence.json),
  [before at scale 1](screenshots/external-before-scale-1.png) and
  [after at scale 1](screenshots/external-after-scale-1.png).

Native run 72 completed with `GUEST_RESULT=0` and QEMU exit 0. All seven
available menu modules (Tomat, Wayscriber, notifications, power, clock, battery
and audio) opened one mapped, grabbed popup, avoided opening click-through,
dismissed on outside click, reopened once, and selected exactly one canonical
leaf through the real fixed normalizer. Tomat's submenu was included, and its
healthy popup remained open beyond 15 seconds. Backend actions were captured by
a private sink: no power command or external service action was performed.

The active-button replay was run separately against the signed Waybar 0.15.0
package in the private networkless guest. The launcher marker and Apps drawer
remain supported lifetime owners. For Tomat, the measured normal-color pixel
set was unchanged while the native popup was mapped; the fixture then stopped
at an unrelated already-known btop theme-view assertion (`GUEST_RESULT=1`), so
this is partial evidence rather than a passing full GUI run. It confirms the
package/API gap recorded in [native-active-color.json](native-active-color.json)
and establishes the accepted native-package behavior: Tomat/Wayscriber retain
their timer/daemon classes while the popup is open; no popup-active color is
required without a supported lifecycle signal. The custom-module FD5/FD6 hypothesis was checked
against the signed source: the continuous reader receives only Waybar's
close-on-exec stdout pipe, and click commands are separate children; no stable
FD5/FD6 lifecycle interface exists.

Actual CPU and memory btop processes ran as UID 1000 on PTYs with their intended
config paths and published titles. A final suite audit then found Trixie's native
btop 1.3.2 does not implement `--config`; its native XDG configuration interface is
supported by both package versions. See the [Trixie manual](https://manpages.debian.org/trixie/btop/btop.1.en.html)
and [upstream 1.3.2 config reader](https://github.com/aristocratos/btop/blob/v1.3.2/src/btop_config.cpp).

The final terminal wrapper keeps the exact quoted selector API and fixed
allowlist, consumes its two supported selectors and launches a fixed `env
XDG_CONFIG_HOME=<HOME>/.config/btop/profiles/<cpu|memory> btop` child inside the
terminal. Installation creates relative config views onto the existing authored
files. Packaged/builtin theme lookup and ordinary native theme directories remain.
No version probe, config rendering or copy happens at launch, and no APT policy or
confinement permission was widened. Run 78 passed both signed btop binaries under
native Foot, with actual wrapper argv, PTY/process/title evidence and file-open
traces proving selection of each config. It used the identified fixture libraries,
so it is not a full Trixie OS installation result.

The primary account receives independent published defaults rather than a copy
of the skeleton. Its explicit installer-only view operation validates the
account/home, permanently drops groups/GID/UID, then creates links through the
pinned HOME descriptor. Run 80 passed account ownership, stable repeat inode,
exact targets, conflict retention, parent-symlink/hardlink rejection and retry
convergence. Future-account config links target regular files; no generic trusted
link policy was broadened. Run 85 passed the current skeleton writer and actual
future-account snapshot as well. Its syscall trace confirms that the root-only
source descriptor closes before the permanent groups/GID/UID drop, with no root
restoration. See [btop-portability.json](btop-portability.json).

Run 88 completed with `GUEST_RESULT=0` and QEMU exit 0 using the current firstboot
source. The actual rendered metadata gate prevented execution of a harmless
marker in defaults with unsafe owner/mode, symlink, hardlink, oversized content,
unsafe skeleton metadata or missing selected-desktop configuration, while later
independent diagnostics continued. Server absence remained expected.

The same run exercised the actual unit collector across 23 response scenarios,
including 100-unit batches, aliases, required static dependencies, a missed boot
job, late failure, successful one-shot, armed trigger/event state, checked versus
unchecked conditions, template instances, unsafe instance paths, changing or
malformed inventory and oversized output. The production 45-second timeout ran
and its actual child was reaped. Six receipt-priority cases passed. The
unprovable-reap adapter was separately injected with a mock; no unkillable child
was created. Systemd manager responses were simulated: this is collector and
subprocess evidence, not a full boot or firstboot enforcement result. See
[unit-acceptance.json](unit-acceptance.json).

The earlier native exit matrix remains separate evidence:  Both window closes returned Foot status 1
with slave HUP; normal child exit was 0, child error was 7, failed exec and
compositor disconnect were 230. The current source accepts status 1 only for the
existing default forms or an exact CPU/memory Foot argv bound to matching
button, action ID, title and HOME config leaf. Added options, traversal, changed
executables and unrelated commands do not receive that exception.

Focused run 74 completed with `GUEST_RESULT=0` and QEMU exit 0 after rendering
all package `.py` and `.py.tmpl` members. Run 78 repeated the constructor checks
for the final portable child argv. The real transient constructor accepted
the exact CPU/memory case, retained marker start/cleanup on the terminal unit,
and rejected modified executable, traversal, arbitrary config, extra arguments,
wrong HOME/title/action identity and unrelated shell commands. This is argv
construction evidence, not execution of a systemd service or a real cgroup.

A standalone native GTK input probe received GDK Escape (keyval 65307, hardware
keycode 9). That does not establish Escape dismissal/navigation in Waybar menus:
those earlier gates failed and remain open. Earlier runs 70/71 and run 73's
incomplete package-import fixture remain failed records. Early black visual
captures were rejected and are not appearance evidence.

The guarded repository unittest suite has not been run on the host, and its
isolation guard has not been bypassed. Updated unittest definitions are distinct
from the separately executed native fixtures. Fresh OS installation and full
logged-in-session checks remain unexecuted. Static/build results and later native
results must be recorded separately before any expanded support claim.

## Outstanding acceptance gates

The ledger identifies the smallest next verification for each open item. Material
remaining gates include native keyboard Escape/navigation and the complete menu
lifecycle matrix; managed application/PTY/cgroup cleanup; the remaining full-boot
and service-specific enforcement matrix; physical backlight identity and DDC/CI
capability/mapping; icon variants, internal/hover/drawer appearance; real block
swap execution; actual NetworkManager/radio priority and authentication; a real
registered polkit agent and authorization dialog; one durable wallet provider in
the logged-in session; complete settled-boot/user-session acceptance; security
timer/scanner execution; and fresh installations of both suites and filesystems.

The enabled-unit/required-dependency collector is implemented and its installed
boot acceptance remains open. The separate actual-user-session receipt is
incomplete implementation work. The physical brightness/DDC backend and icon
alignment changes are also not implemented. These are open gates, not skipped
passing checks or support-qualified features.

Brightness remains unresolved. The supplied journal proves the native module was
included and `intel_backlight` had a successful systemd restore. It does not supply
the required brightness/actual/max/power inventory or a connector/EDID/serial to
DDC bus mapping. No first-display guess, arbitrary I2C permission, gamma substitute
or fabricated percentage was added. Icon optical alignment also remains open
without the necessary measured rendering evidence.

The existing installer-only CUDA legacy archive compatibility workaround is
intentionally retained at the user's explicit request. Authentication hardening
of that archive is outside this correction set. This does not change the normal
APT/TLS policy for other repositories or claim publisher authentication for the
legacy exception. No CUDA installation or driver change was performed.

CrowdSec console approval, Tailscale enrollment and an operator-locked Obsidian
identity are separate operator states. They do not justify account or credential
resets. ACPI/MMIO/SMT, GPU topology, EFI/Secure Boot/MOK and other hardware-specific
claims require target evidence; no speculative global workarounds were applied.

## Fresh-install verification handoff

Review the changed source and the regenerated suite receipt, manifest, archive,
source helper, support matrix and preseed as one product set. The pure serializer
does not run native installation tests. Use only an approved disposable target for
installation acceptance. Confirm the chosen fresh disk layout and profile, then
retain installation, settled-boot and actual user-session evidence separately.

Verify UI and user services from the logged-in labwc account. Do not manufacture
session variables from root. Test nondestructive menu opening, selection and
cancellation before any separately authorized power action. Preserve external
approval and wallet unlock as operator decisions. No existing-host apply,
rollback, credential, partition or firmware workflow is part of this work.

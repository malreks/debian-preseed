# Installer operation, maintenance and rollback

This checkout creates reviewable source publications only. Implementation work
has not booted an installer, solved packages, changed storage, loaded policy,
started services, enrolled runners or DNS, or switched a served pointer.
`tools/release_pointer.py` is a manual operator tool and has not been executed,
including its preview mode. The static-only boundary remains in force.

## Review the source plan

Each suite has its own physical `common.cfg`, `fragments/`, `classes/`, family
APT trees and generated `preseed.cfg`. Shared implementation and target assets
are in `d-i/debian/`. No suite frontend is a directory symlink. Select one
registered desktop tier, or one or more registered server roles of the same
family; see [class selection](class-selection.md). The build records 22 amd64,
Btrfs, fresh-install role combinations and fourteen individual suite/role plans.
These are source plans, not acceptance of native installations.

Concrete profiles own storage policy, NFS/Filen switches, hardware tuning,
crypto, Wi-Fi and IPv6 choices. Role selection does not override those choices.
Runtime paths have one owner in `hosts/installer/runtime.env`; source selectors
are in `repo.env`; installer destinations are in `hooks/installer/di.env`.
Profile data is parsed and expanded by the restricted data compiler. It is
never an arbitrary shell program. Shared NFS defaults and identity defaults
fill missing values without replacing a concrete profile value.

Family shared profiles own the common site identity. Their optional custom TLS
SAN defaults to empty, preserving each resolver's authenticated hostname; an
override applies only with the explicitly supplied custom CA. Both workspace
counts live in every desktop profile. See the [host policy contract](../../d-i/debian/hosts/README.md)
for topology semantics and the desktop-only appearance editor's scope.

Desktop Appearance keeps its existing nine desktop field components and global
toolkit/icon/pointer choices. The color editor and theme selector share the
account ownership lock. A mixed user/greeter edit retains both journals until
the authenticated greeter decision finishes; interrupted dock edits also retain
prior liveness until restart is confirmed. Do not delete an appearance journal
to bypass a conflict or failed authentication. The recorded
[offline policy compilation evidence](../validation/desktop-appearance-static-20261112.json)
uses private public-package support data and does not establish GUI or loaded
policy acceptance. Application-specific preference pages are outside this app.

The [desktop resource policy](desktop-resources.md) separates session
infrastructure, applications and compilation, carries memory protection through
the ancestor hierarchy and bounds each zram emergency pass. Review its profile
knobs and rollout limits together with the complete release.

`CRYPTO_LUKS2_ROOT` and `CRYPTO_LUKS2_HOME` are independent opt-ins. They are
separate from the existing explicit Secure Boot signing-state storage policy.
Review `SECURE_BOOT_STATE_MODE` and its private signing credentials as well;
disabling root/home encryption does not change that profile field. Encryption,
TPM policy, recovery slots and boot-console prompting remain unverified natively.
Duo/dualboot preservation profiles fail before disk mutation; no preservation
claim is made. F2FS profiles explicitly declare snapshots=none. A role never
changes the filesystem or silently selects a proprietary GPU driver.

Crypto staging and later enrollment use the same permanent initramfs verifier.
It inspects regular root-owned images, excludes detached `.sig` files, and
rejects private enrollment state in any image. Root encryption additionally
requires the TPM hook, its configuration, native recovery fallback, token plugin
and each native TSS/OpenSSL library loader name. The build hook copies package
SONAME links and their targets through Debian's `copy_exec` contract. Forky uses
the [systemd 262 PIN-hardening contract](https://github.com/systemd/systemd/blob/v262/man/systemd-cryptenroll.xml):
its [Argon2id implementation uses OpenSSL](https://github.com/systemd/systemd/blob/v262/src/shared/crypto-util.c).
Native Debian packages remain on selected-suite candidates without version pins.

The inspection allows at most 64 images and 4,096 boot-directory entries,
16 MiB output per archive reader and 32 MiB aggregate listings. Each command
has at most 120 seconds within a 300-second shared inspection deadline; native
child cleanup keeps its separate bounded budget. Metadata checks reject a
changed image or boot directory while ignoring ordinary access-time updates.
Names are read incrementally with a 4 KiB encoded line limit, 100,000 entries
per image and 200,000 entries in aggregate; control-bearing names are rejected.
These are optimistic change checks on trusted target paths, not a filesystem
snapshot or proof against a malicious root writer.

Firstboot cleanup publishes a durable pending marker before removing health
hooks. It retains that marker through rebuild, archive inspection and the boot
stamp, including failure paths. Final TPM enrollment refuses pending cleanup
and requires a separate boot after the rebuilt-image stamp. Keep recovery
credentials available across kernel/initrd or measured-boot policy updates;
boot the intended image, explicitly reenroll, then confirm after another boot.
Reenrollment without a bootstrap credential asks for the existing recovery
passphrase. Uncertain keyslot operations return 76 and retain their mutation
record and private workspace for explicit recovery. No archive inspection,
TPM enrollment, recovery boot or PIN entry has been executed in this checkout.

Initial temporary TPM enrollment now uses an installation-only program staged
under the existing private setup directory and removed on success or failure.
It receives the random key and selected devices through inherited handles,
checks the physical disk fingerprint recorded before partman changes, and
checks each partition's disk generation, parent, slot and LUKS UUID. Read-only
native descriptor probes must succeed before enrollment; there is no pathname
fallback. Its 600-second common native-operation budget and 32 MiB aggregate
output budget reuse the permanent helper's pidfd, streaming and cleanup owner.
The short initial UUID queries use target tools with a 30-second deadline and
five-second forced-cleanup allowance. No extra interpreter is assumed in d-i.

`FILE_INSTALLER_SELECTED_DISK_IDENTITY` in `hooks/installer/di.env` owns the
partman identity receipt. `FILE_CRYPTO_BOOTSTRAP_TRANSACTION` in the target path
contract owns a private, durable transaction record. That record contains
device identities and before/after LUKS metadata, never the random plaintext
key. Its writer and both readers enforce a 1 MiB bound. The same enrollment
lock protects installation and permanent maintenance.
The temporary token must use SHA-256 PCR 7, preserve the bootstrap slot, and
unlock through the target TPM token plugin without a passphrase fallback.
Automatic public-key/PCR-lock additions are disabled for this temporary policy.
The final separately booted PIN/recovery procedure remains authoritative.
Permanent maintenance reads the same verified transaction and requires exactly
the configured root/home UUID set before configuration export, enrollment or
release. A missing, partial or unsafe handoff returns 76. The shell adapters
preserve that result, including failures of the configuration data producer.

On bootstrap status 76, keep the installer key, sealed credential, transaction
and any sealing candidate. Stop automatic retries. A verified record can be
rechecked on the same boot without changing keyslots; any unverified, malformed,
previous-boot or changed-device record requires an operator decision. During a
separately authorized recovery, hold the enrollment lock, preserve a private
copy of the evidence, confirm the physical disk and each recorded LUKS UUID,
inspect current metadata, and prove the applicable bootstrap/recovery and TPM
unlock paths before deciding whether to resume the installation or restore a
known prior header from an operator-owned backup. No automatic header restore,
keyslot wipe or journal deletion is provided. If child termination remains
uncertain, retain the lock-owning process evidence and avoid further mutation.
These procedures and the full inherited-handle bridge remain unexecuted here.

Installation uses physical Ethernet. Target routing follows
`MANAGED_NETWORK_PRIMARY_IFACE`; paired Wi-Fi addresses use Ethernet +1 within
the same configured subnet. `WIFI_ENABLE` controls private AP preconfiguration,
and `IPV6_ENABLE=false` suppresses both physical IPv6 addresses. A desktop saved
AP can still become a fallback when preconfiguration was disabled. DHCP lease
churn has not been qualified: reserve the paired address space and review the
rendered plan rather than assuming an installer-time address pair tracks later
DHCP changes. No host network was queried to verify this behavior.

Private account, AP and enabled Filen credentials come from `/preseed.env` in
the actual booted Debian Installer initrd. That immutable installer interface
is unrelated to the checkout or served document root. Never put enrollment
secrets, passwords or private keys into the public profiles or payload.
Missing runner enrollment is installed-but-pending. An enabled Filen account
requires its private email, password and TOTP seed before installation completes;
its sync service is not automatically started.

Runner service URLs are public profile policy in `server/shared-srv.env`.
`CI_GITHUB_URL` is `https://github.com/mjcramerz`; `CI_GITLAB_URL` selects the
GitLab instance. Only `PRESEED_CI_GITHUB_TOKEN` and `PRESEED_CI_GITLAB_TOKEN`
belong in the initrd credential file. The installer consumes each selected
provider's private input once. It passes the GitHub token through the native
masked input environment, and GitLab's authentication token through its
mode-0600 native configuration, never command arguments or diagnostics.
The persistent maintenance controller cannot enroll or install runners.
GitLab's native configuration uses `FILE_SERVER_GITLAB_CONFIG`, inside its
private runner-owned config directory; native `.runner_system_id` and token
rotation can be written there without granting write access to root-owned
installation receipts. The pinned native CLI's exit status alone is not proof
of credential acceptance: the installer also requires a bounded authenticated
200 JSON acknowledgement from GitLab's
[runner verification API](https://docs.gitlab.com/api/runners/#verify-authentication-for-a-registered-runner),
bound to that native manager identity. The token travels only in private stdin
and the HTTPS request body; redirects are refused. Interrupted verification
retains enrollment uncertainty instead of enabling a falsely enrolled runner.

Runner hosts contain the verified native runtime and rootless container engine.
Each workflow selects its own slim/custom images and supplies its own CI
toolchains and remote-cache credentials. GitLab defaults to a pinned selected-
suite slim image and `if-not-present`; custom and multiple images are allowed.
Its native helper uses the matching runner version and supported Debian-derived
Ubuntu flavor, with its explicit image reference in the public shared profile.
This follows GitLab's supported
[helper flavor contract](https://docs.gitlab.com/runner/configuration/advanced-configuration/#helper-image)
and the pinned runner's
[tag construction](https://gitlab.com/gitlab-org/gitlab-runner/-/blob/v19.5.3/helpers/container/helperimage/linux_info.go).
Custom job/helper images must also be Debian-derived; the operator owns the
contents of those images. No Alpine image or fallback is configured. GitHub's native runner
owns its container pull behavior and does not expose the GitLab setting; the
implementation does not invent an equivalent environment option. Workflows on
this dedicated trusted host must use job containers; native host jobs are not
a qualified cache/toolchain path.

Provider identities, rootless sockets, build roots and caches are distinct.
All backing data stays on `/pool`. GitLab mounts only its own build/cache
directories and the public Bazel configuration into job images. GitHub's native
pre-job hook publishes cache environment values through `GITHUB_ENV` and
places `.bazelrc` in the native container HOME. Bazel disk/repository/output
caches, Cargo, Go, pip/uv, sccache/ccache and temporary files use each provider's
own cache tree. Optional `CI_BAZEL_REMOTE_CACHE_URL`,
`CI_BUILDBUDDY_BES_BACKEND` and `CI_BUILDBUDDY_RESULTS_URL` are public endpoints;
API keys stay in workflow secrets. Missing enrollment leaves the verified
installation pending. A possibly completed native registration retains an
uncertainty marker and refuses automatic re-registration. No source receipt
claims that a runner is online.

Server DevOps targets the human account selected by `PRESEED_PRIMARY_USERNAME`,
with the same shared non-GUI tool policy used by desktop medium/full. Its
Codex installation is unconditional: `CODEX_ONLY_ENABLE=false` does not remove
Codex from this role. On another server role, the host boolean enables Codex
without the full toolchain, firmware or virtualization stages. Codex and
codex-home use `DEVOPS_CODEX_ROOT` and `DEVOPS_CODEX_USER_ROOT` from the shared
profile, while compiler/cache/database stores use the canonical pool paths.
The complete Bazel cache configuration has one installer owner and is copied
to the primary account; it never uses the GitHub or GitLab service home.

The primary account receives `devops` membership and its own rootless Podman
configuration. Locked runner accounts keep their own homes, IDs, sockets and
stores, and receive only the matching private provider token during installation.
Their passwords remain locked and they have no interactive shell or operator
group access. A colliding existing identity is preserved and rejected. The
separate locked `srv-devops` account owns the optional local BuildBuddy service;
it is not the human DevOps login. Login fragments configure the environment
only and never install, clone, start an engine or enroll a runner.

For required Git clones, supply the encrypted `/git_ed25519` and
`/git_ed25519.pub` in the initrd and `PRESEED_GIT_SSH_PASSPHRASE` in its root
`/preseed.env`. The same private helper authenticates codex-home and both
desktop repositories. Obsidian and Netscape are installed/cloned in every
desktop tier, including base; their policy and synchronization remain desktop
owned. Servers validate only the selected Codex repository. No clone uses
an inherited runner home or an ambient SSH agent. Missing required clone
credentials fail clearly. Status 76 retains private recovery staging and
prohibits automatic retry or cleanup until the recorded outcome is reconciled.

Headless Codex uses a separate launcher and backend user unit. It requires
non-root Bubblewrap and pool storage, without desktop services or a runner
management socket. A bounded sealed resolver snapshot keeps Debian's native
resolver symlink usable while the namespace has private runtime directories.
This uses Bubblewrap's documented
[read-only file-descriptor binding](https://github.com/containers/bubblewrap/blob/main/bwrap.xml)
and systemd's
[per-unit credential interface](https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html#Credentials).
The source-only review does not establish namespace, AppArmor, DNS or service
acceptance on an installed target.

Timeshift has no class selector. Each concrete host profile declares
`TIMESHIFT_ENABLE`. True requires qualified amd64/Btrfs and owns the suite's
Timeshift package fragment, managed modules, configuration, AppArmor policy,
snapshot timers and GRUB-Btrfs refresh integration. False excludes all of
those publications and leaves the filesystem unchanged. Retention and calendar
values remain host policy. Server defaults disable daily snapshots and retain
two weekly and one monthly snapshot; desktops retain their more frequent
policy. F2FS keeps `TIMESHIFT_ENABLE=false` and requires explicit
`snapshots=none` on the command line. The maintenance menu hides unavailable
snapshots, and manual snapshots use the same bounded lock/supervisor as timers.

## Shared profile services

SSH activation is explicit in every concrete profile. Server classes always
include OpenSSH packages; desktop pkgsel adds the suite SSH fragment when
`SSH_SERVER_ENABLE=true`. False leaves the services masked offline. True
installs the profile access policy and authorizes the primary human account.
The installer shell reads `/lan_ed25519.pub` in the actual initrd first and,
only when absent, uses authenticated payload selector `FILE_SSH_LAN_ED25519_PUB`.
A missing or unusable key leaves authorization pending without failing the
installation. A safe existing `authorized_keys` file is preserved and the key
is appended once. No Python authorizer or installer authorization wrapper is
installed into the target.

NFS, Filen and hardware tuning use shared implementations and common systemd
units on both families. NFS and Filen run through `os.sharing` once. The desktop
hardware caller and `server.hardware` both invoke the same profile-gated tuning
backend. No tuning operation is performed by the installer stage. Selected
hardware must also satisfy the actual vendor and optional driver gates.

Servers receive the CLI/backend and system units. Desktop menus, GTK bookmarks,
Waybar edits and per-application user scope leases remain desktop-only. The
server skeleton contains Bash startup files and numbered profile fragments;
`71-devops-srv.sh` is installed only by `role/server/devops`, and login does not
start an engine. No Zsh or Starship configuration is installed into that skeleton.

Hardware broker configuration is format 2. Its `role_family` is validated,
root-owned installed policy, never a request parameter. Desktop manual control
requires an active local seat. Headless control admits only the exact configured
human UID or root through the existing Unix-socket credential check. Runner and
service UIDs remain separate. Intel policy handover still requires explicit
confirmation; device identity, recovery journals and bounded worker lifetimes
retain their existing owners. Status continues to report actual local-seat
presence on servers, even though their configured operator needs no desktop seat.

The CLI currently uses its established `labwc-hardware-tuning` entry point for
both families. `status`, `report`, and fixed `manual VENDOR PROFILE` operations
are terminal interfaces; `menu` requires the desktop picker. Do not infer that
a service is enabled merely because its CLI package or support module exists.

`nfsmnt` and `filenmnt` use `network-sharing`; the desktop menu uses the separate
`labwc-network-sharing` wrapper. See the [NFS contract](../network-sharing.md)
and [Filen contract](../sharing-filen.md) for native authentication, exact export
policy, mount lifecycle and failure limits. Neither CLI grants arbitrary unit
management or blanket sudo. Native services load policy only on the installed
machine, never during checkout validation.

## Suite and package maintenance

Medium/full desktops and the server DevOps class use one common QEMU/Incus
installation stage. Only the explicit human operator receives `kvm`, `incus`
and `devops` group access; CI identities receive none of them and no
`incus-admin` access. Servers use native private client configuration in the
operator's HOME. `INCUS_WEB_UI_ENABLE` defaults to false for servers and true
for desktops. Incus remains local to its native Unix sockets; the managed NAT
bridge uses the active host route rather than attaching to a physical Wi-Fi
or Ethernet bridge. No service is started by this installer stage.

An interrupted Incus mutation retains its private transaction at the target
`FILE_INCUS_BOOTSTRAP_JOURNAL` path from the runtime contract. Do not remove
that file or reset a store to retry. Inspect the transaction and native Incus
objects. After completing any necessary operator repair, run the installed
`incus-host --recover-uncertain` entrypoint: it verifies the configured storage,
network, local-only API and unprivileged default profile without modifying
Incus objects, then acknowledges that exact retained record. For an interrupted
storage preparation it verifies only the owned directory identities. A policy
change or incomplete/conflicting state refuses acknowledgement. The service
has no automatic restart after failure. This operator procedure has not been
executed in this coding task.

The Trixie frontend selects Trixie for the base, udebs, target repositories,
updates and security. Forky selects Forky. Both use the configured GLES mirror.
Sid and Experimental are acquisition-only Debian sources at negative priority;
they are not hidden base or solver fallbacks. Trixie base, security and updates
have equal priority so a newer security/update candidate is not suppressed by
base-suite priority. Explicit backports/vendor package pins name their package
identities. Vendor channel labels such as stable, any or unstable are reviewed
independently of Debian suite names; no mechanical suite replacement is used.
See [vendor repository review](vendor-repositories.md) for actual published
Forky channels, narrow exceptions and Cramerz's normal-priority availability.

On amd64 both suites select fixed **XanMod EDGE 7.3.1-xanmod1** image/header
pairs through CPU-qualified `kernel/x64v2` or `kernel/x64v3` class files.
There is no floating kernel meta-package or stock fallback. The shared kernel
stage verifies the exact installed image, headers and initrd, and selects the
paired upstream regulatory database from Debian's native package. Server boot
also uses the shared signing backend and its explicit signing-state profile.
Review the public MOK certificate and complete firmware enrollment separately
when Secure Boot requires it; the server stage does not reset firmware keys.
Boot, signatures, DKMS and hardware behavior remain unverified. Review exact
vendor package availability before any rollout, and retain the prior bootable
kernel/certificate and recovery media when updating the fixed pair.

The unattended-upgrade core blacklist is deliberately broad: kernel/boot,
systemd/udev, APT/dpkg, foundational account/shell libraries and other controlled
components require operator maintenance. Server policy therefore does not mean
comprehensive automatic security patching. The server operator owns review of
held security candidates, the full upgrade window, service compatibility,
reboot coordination, private runner enrollment and credential rotation. Verified
artifact pins in `shared-srv.env` require a reviewed source change and rebuild;
no moving latest download is an update policy. DNS backup/restore and resolver
ownership need private operator configuration before any activation.

A preserved profile value or a generated plan does not prove that a native
package exists or that its dependency set is compatible with all exclusions.
Record upstream blockers explicitly, without selecting a foreign Debian suite,
weakening the fixed Zoom/Discord private-Xwayland scope or building from source.

## Generation and static review

The [backup desktop review](backup-desktop-review.md) records the complete
reference-tree fingerprint, package/application ownership and deliberate
interface changes. It is human review evidence, never installed policy.

The only generation command is `make build`. It captures non-secret regular
source files and overwrites `payload.tar.gz`, `payload.manifest`, `source.sh`,
`receipt.json`, `support-matrix.json` and `preseed.cfg` directly in each suite
directory. There are no release/publication output directories, and these
flat products remain visible to Git. The build holds one nonblocking ownership
lock on the existing suite parent directory inode and creates no lock file.
It writes both preseeds after the payload products. It does not invoke
inventory, tests, installers, shell snippets, services or policy loaders.
Source capture binds the bootstrap, member manifest, payload and both frontend
views to one content identity. An interrupted multi-file build must be rebuilt
and audited before serving; its flat files are not a transactional serving root.

File replacement walks each destination ancestor with no-follow directory opens and
performs member creation, replacement, inspection and synchronization through
the pinned parent descriptors. Existing candidates must have the exact file
and directory set, owner, modes and bytes. Content reads promote only a checked
single-link regular inode through Linux's own descriptor interface; FIFOs,
devices and links are rejected before opening content. A second metadata pass
checks the complete inspected identities. This is optimistic change detection,
not a filesystem snapshot or protection against a malicious account controlling
the entire checkout.

The separate manual served-tree tool validates its complete product mapping
before external output creation: at most
10,000 files, 20,000 file/directory entries, 256 MiB total, 64 MiB per file,
512-character member paths and 64 components. Invalid names, environment-file
outputs and file/directory prefix collisions are refused. Existing unexpected
entries are rejected as they are enumerated. Published directories are 0755
and files are 0644 regardless of the ordinary restrictive creation mask.
Staging starts private and incomplete staging is retained privately on failure.
Older malformed or inaccessible candidates are refused rather than repaired
in place.

Cooperating generators take a nonblocking lock on the pinned suite-parent
directory. A busy result requires a later explicit invocation after the other
writer finishes; it does not launch a competing writer or perform cleanup.
Each flat output is atomically replaced and checked. The separate operator
tool verifies and reuses an identical complete external candidate. A failure after a
rename has a distinct outcome-unknown result if synchronization or final
verification cannot prove its durable state; the exception preserves its cause.
The direct Python generation and manual operator CLIs return 75 for that state
and 1 for ordinary failure; Make reports a failed recipe with its own nonzero
status, so retain its diagnostic rather than interpreting only Make's status.
Keep current generated files and external transaction evidence for review. Do not infer restoration
from an error, auto-retry an uncertain publication or delete another writer's
temporary name. The two checkout preseeds are convenience views: an interrupted
update may leave them mismatched and the static audit will refuse that state.
The manual served-tree capture refuses a mismatched pair as well.

Obsolete shared release/publication directories have been removed. Their old
paths remain ignored to prevent accidental reintroduction, while the suite's
flat products are never ignored. Retention applies only to the operator's
external served trees. The changed-file audit compares the current flat
products with current authored source and with each other.
Physical suite classes/fragments and family APT trees remain tracked inputs.
Suite runtime assignments come from each suite's `runtime.env`; a small shared
installer TSV owns native qualification blockers. There is no suite JSON
installation input and no runtime dependency on these documentation files.

All managed Podman/Incus stores, image staging, compilation outputs and build
caches use the mounted `/pool` partition. XFS is the normal backing filesystem
for the Btrfs host layouts. An absent pool is an error; no engine initializes
a replacement store on `/`. Runner providers have separate stores and sockets.
The server DevOps primary account has private build/cache/database roots,
rootless Podman/Buildah configuration and Bazel output policy there. Desktop
Gitbuild keeps repository inputs under the user's workspace but snapshots,
jobs, logs, rootless build roots and artifacts under its private pool roots.
Existing stores and previous outputs are never reset or silently migrated.
Both Incus backends also bind native image, backup and instance-log archive
storage to owned custom volumes in their pool. Native Incus owns that storage
operation, with ETag checks and retained uncertainty handling. A competing
configuration or volume is refused. Its small daemon database and management
socket keep their native package paths. These server options were checked
against the [Incus 6.0 configuration source](https://raw.githubusercontent.com/lxc/incus/stable-6.0/internal/server/node/config.go);
no daemon API was contacted during this work.

After payload inputs change, the required check is
`python3 -B tools/post_change_check.py`. It parses changed source as data,
performs permitted shell/syntax/structured-data checks and compares current
source, generated members, manifest, receipt and preseed pins. It also checks
plain class files, role plans, absent activation and real runtime placeholder
producers. It does not execute fixture code or managed module imports.
No `make check`, test discovery, native integration, host repair, policy load,
VM, container, chroot or inventory command is authorized by this procedure.

Read the immutable receipt and the current [checkpoint](CHECKPOINT.md) for exact
release hashes, command results and outstanding work. A static pass establishes
serialization consistency and checked source contracts; it does not establish
boot, disk preservation, GUI, service, firewall or hardware acceptance.

## Operator publication and rollback

Publication is a separate, explicitly authorized operator action. First review
both frontend preseeds, the complete local candidate, its receipt and any
qualification blockers. The HTTP document root must select the complete served
tree. Do not copy or switch one frontend independently of its shared release.

After separate rollout authorization, the manual tool's argument contract is:

```text
python3 -B tools/release_pointer.py activate SERVED_PARENT RELEASE_SHA256
python3 -B tools/release_pointer.py activate SERVED_PARENT RELEASE_SHA256 --apply
```

The first form previews. Both forms are outside this coding task and neither
has been run. `SERVED_PARENT` must be an operator-chosen canonical trusted
absolute directory. The helper captures the receipt's exact flat suite products
and frontend inputs, retains prior complete trees, takes one publication
lock, verifies both frontend identities and complete product membership, writes
and synchronizes a private transaction journal, then atomically switches one
`current` pointer to the complete served tree. It verifies the pointer after
the switch. Complete trees live in the operator's external `trees/` store;
generation never creates that store in this checkout. A tree identity binds
the complete served member set, while the source identity binds its inputs.

Rollback uses the previous complete tree identity recorded in that journal:

```text
python3 -B tools/release_pointer.py rollback SERVED_PARENT PREVIOUS_TREE_SHA256
python3 -B tools/release_pointer.py rollback SERVED_PARENT PREVIOUS_TREE_SHA256 --apply
```

Finish or stop all active installers before switching the served pointer.
The public URLs are flat, so an installer that has not finished acquisition
cannot retrieve old bytes through those URLs after a switch. Its trusted
preseed pins reject mixed bytes; restart it from the selected trusted preseed
if necessary. Retain previous complete external trees and transaction evidence
for operator rollback. A prepared or outcome-unknown journal
blocks a second mutation. Its exact journal filename is required for the
manual `reconcile` operation; reconciliation verifies the current pointer and
retained bytes before accepting either previous or selected state. A failed
return alone does not prove restoration. Preserve the journal and candidate
when the outcome cannot be established. Never auto-retry an uncertain switch.

A served-pointer rollback affects future source acquisition. It does not undo
partitioning, packages, runner registration, TPM enrollment or installed DNS
configuration on a target. Those need their own operator-approved recovery
using retained credentials, service stores and backups. No such live recovery
has been attempted from this checkout.

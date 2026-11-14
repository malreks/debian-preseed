# Backup reference and desktop ownership review

The current checkout is the implementation authority. The sibling
`debian-preseed-de.bak` tree was read as reference data only. No implementation
was copied from it. No backup script, module, helper, fixture, installer or
inventory utility was executed or imported.

All 2,893 regular backup files were hashed and classified, including hidden
desktop configuration. Their sorted file-hash/path fingerprint is
`ed3ab98607cc41df8ff7f5da9f294d5042cfbd07ac24737653cc60ab7e477305`, exactly
the supplied extracted audit tree. All 2,892 files in the earlier Git baseline
have the same bytes in this backup; the additional file is historical
`todo/journalctl`. Every file has a disposition in the human
[ownership ledger](ownership-ledger.json). Historical reports, diagnostic logs
and retired publications are evidence, never installed desktop inputs. The
ledger is not read by the installer, builder or changed-file checker.

The package review covered all 734 original `pkgsel/include` tokens across
desktop, application, optional, hardware and common APT classes/fragments.
Native `gh` and `thunar` follow the selected suite, without their old `/trixie`
and `/forky` qualifiers. Native `7zip` replaces `p7zip`. The four fixed XanMod
image/header identities are retained under explicit CPU-qualified kernel
classes, independently of disk selection. This is the requested **EDGE
7.3.1-xanmod1** release, with both x64v2 and x64v3 pairs. No kernel version was
inferred from a native Debian package candidate.

The source review traced the following application groups through physical
classes, package or artifact installation, shared renderers, target staging,
installed launchers, configuration, AppArmor, services and verification:

| Ownership | Applications and configuration | Current installation and activation owners |
| --- | --- | --- |
| Every desktop | Labwc/session, greetd, native Waybar modules/menus, Fuzzel, Mako, PipeWire/WirePlumber, dock, terminals, file manager, viewing/archive tools, accessibility, localization, appearance | Physical base/medium/full class packages; `desktop.storage`, `desktop.software`, `desktop.session`; shared desktop component renderers/staging and `verify.sh.tmpl` |
| Every desktop | Vivaldi, Bitwarden, Tuta, Sleek, Tomat, Ledger Live, Obsidian, Spotify, L3afpad, Calendar/Calix/Agenda/Waycal, credentials, Secret Service/KWallet, schemas, workers and menu actions | Physical role packages/repositories and common selected application workers; shared launchers, account configuration, managed-app integrity, network confinement and AppArmor; no required Whisper or Fruux enrollment for local calendar use |
| Medium/full | Zoom, Discord, Filen Desktop | Explicit `software_run_selected_app` class sets, component servicing, launchers, configuration and policy; private Xwayland eligibility remains Zoom/Discord only |
| Medium/full | Telegram, qBittorrent, RetroArch, Edge, Mullvad Browser/VPN | Physical role packages/repositories and corresponding desktop runtime wrappers/configuration |
| Full | QoreDB, Postman, Tor Browser; VS Code, PowerShell and broader database/development software | Explicit full-only artifact workers or full class package records; shared acquisition/servicing interfaces retained |
| Medium/full and server DevOps | Firmware/CH341A, DevOps, Podman/Buildah, QEMU/Incus and Whisper/AI | Physical role content and shared installer stages; desktop UI/session activation separated from headless backend/account setup |
| Every role with profile policy | CrowdSec, Timeshift on qualified Btrfs, zram, NFS/Filen, hardware tuning, crypto, SSH and paired uplinks | Shared implementation and canonical runtime paths; explicit profile switches, scheduling/retention and private credentials; no public feature/capability selectors |

The original desktop shell inventory has 301 function names. Eight old names
were replaced by current shared owners: Filen installation is in common
`filen.sh`/`filen-install.py`; hardware tuning and CPU detection are in common
`hardware-tuning.sh`; SCX validation/installation is in common `scx-scheds.sh`;
boot logging belongs to common `system-services.sh`; and the Whisper predicate
is now `desktop_whisper_class_selected`. The other names remain in the
redesigned source. Name retention is an inspection aid, not runtime proof.

The review also covered Bash/Zsh family boundaries, `.profile.d`, browser and
application policies, native menu XML/action maps, application module integrity,
firstboot/first-login callers, appearance source mappings, common versus
desktop systemd policy, shared networking and native service drop-ins. The
existing full support libraries remain available when required by integrity or
sibling consumers. Base activation guards exclude specialist entrypoints,
shell fragments and user services even when support modules are shared.

All desktop tiers install the same Labwc session, Waybar modules, Tomat popup
owner and Apps drawer, including Tuta and Sleek. The account copier requires
their configuration and Tuta launcher in base as well as medium/full. Base
excludes tier-owned Cargo/Mise and specialist application directories, while
retaining failures for missing core skeleton assets. Every tier installs
Obsidian, copies its configuration and clones the configured Obsidian vault
and Netscape exports using the actual initrd Git key/passphrase. The independent
Obsidian auto-sync boolean controls its timer. Metadata verification checks
private checkout ownership and the configured origin/tracking branch without
executing Git configuration. Ledger, Tuta, Obsidian and Spotify retain their
explicit application network confinement in every
desktop tier; Sleek and Tomat keep their local-only operation.
Calendar programs and local reminders remain usable without remote credentials;
Fruux and Telegram stay pending until their complete private pairs are supplied.
The credential unit is conditioned on the private bootstrap file and remote
reminders on the account identity, preserving explicit keyring retry ownership.

Firstboot now validates the published format-2 class receipt as bounded data,
requiring one matching desktop role/class and family with root-owned regular
file metadata. Base checks that its excluded AI, Android, container-menu and
benchmark assets and commands are absent, including account-local service
files. Medium/full retain required-presence checks for those assets. Common
desktop/session checks still apply to all tiers. Whisper session activation is
checked against the staged skeleton enablement link, so an installed service
file alone does not claim or require persistent activation.

The active Ledger installer now uses the existing dedicated-identity packaged
extractor, after vendor signature and digest verification, instead of executing
the AppImage runtime. Ledger and Tuta retain a private workspace when parser
termination cannot be proved; the shared extraction lock has a 30-second wait
budget. Native servicing callers retain their existing publisher transactions.
Unused Tuta/Postman direct-install methods were removed after reviewing their
callers. These verifiers now require the native repository publisher, as Ledger
does. The active Discord repair/bootstrap boundary retains its separate owner;
this change does not expand private Xwayland eligibility.
Python follows the selected suite current unversioned `python3` candidate and
packaged extension-module ABI. No Python minor version or native Debian package
version is fixed by the desktop implementation.

Managed desktop/server build outputs, toolchain caches, rootless Podman state,
Incus container volumes and native image/backup/log stores use the mounted
data pool. Gitbuild source repositories may remain in the user's workspace;
their snapshots, per-repository job roots, temporary build roots, artifacts and
logs use private pool directories. Its worker, tarball identity and sbuild
policy now consume the rendered native suite instead of a Forky constant.
The corresponding path authorization and AppArmor rules follow these owners.
Missing mounts, conflicting storage/configuration and existing mismatched
identities are refused rather than reset.

Common DevOps, non-GUI firmware, NFS and hosting defaults now belong to the
single shared profile environment. Server DevOps reuses the shared non-GUI
tool installer for the explicit primary account, including Codex/codex-home,
firmware tools, Bazel and rootless Podman. Other server roles can select only
Codex through their host boolean. Provider identities and private enrollment
tokens remain separate from primary-account tools and Git credentials.
Ordinary `labwc-build` invocations now apply pool-backed compiler scratch and
Cargo output policy before either a new scope or the existing-scope fast path;
the primary account's private scratch directory is provisioned during installation.
Arbitrary Makefile output paths still require an explicit pool workspace or
the build system's supported output setting, as described in
[desktop resource policy](desktop-resources.md).

Fixed XanMod kernel packages now have one shared `os.kernel` verification and
regulatory-data stage on desktops and servers. Server boot setup uses the
shared signing backend and the existing explicit profile signing-state mode;
MOK firmware enrollment remains an operator action. Merely installing a kernel
package does not prove its boot, module, signing or hardware compatibility.

This is static source and ownership evidence. It establishes neither successful
package solving nor application launch, GUI behavior, networking, disk
preservation, boot or hardware acceptance. The native Trixie Labwc dependency
on excluded system Xwayland still blocks all three Trixie desktop installations
before partitioning. The current source keeps that blocker explicit and does
not borrow a foreign-suite Labwc implementation.

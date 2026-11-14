# Shared installer implementation checkpoint

This is work in progress. No installation, test runner, enrollment, publication,
deployment, package operation, service operation or native policy check has run.
The checkout started clean at `88a341c9d4b8864db5a63f79357eeaebbe92a821`.
The recorded source inventory and product hashes are in `shared-baseline.json`
and `baseline-publications/`. The supplied ZIP is an independent audit snapshot;
its hashes are not claimed as the identity of this Git checkout.

## 2026-11-12 typed-loader, suite, and credential transport remediation

The current source correction keeps shell module loading restricted to `.sh`
assets and resolves `scripts/common/credential-data.awk` through a separate
authenticated parser resolver. The resolver requires authenticated payload
state, manifest membership, digest and size closure, regular single-link files,
private ownership/modes, safe relative paths, and a private staging directory;
the parser is passed only to `awk -f`.

Installer media identity is deliberately independent of the target suite. Any
d-i image may run either frontend; `INSTALLER_SUITE`, authenticated payload
qualification, suite policy, and the early target
`/etc/apt/apt.conf.d/00suite-default-release` drop-in select Forky or Trixie.
Trixie desktop remains blocked and all support-matrix runtime acceptance remains
unverified.

Password/passphrase kernel arguments, including the named d-i Wi-Fi passphrase
aliases, are accepted by the embedded bootstrap and runtime readers as an
explicit installation override; the protected `/preseed.env` value remains
the preferred unattended channel. Token, access-key, bearer-secret, generic
PSK and private-key arguments are rejected before parsing. Passwords remain
absent from generated process arguments and URLs, while kernel-command-line
exposure is an accepted installation trade-off.
Seed `url=`/`preseed/url=` accepts HTTP, HTTPS, and local `file=` sources. The
installer delegates HTTP/HTTPS certificate, authority, downgrade, and redirect
behavior to d-i `wget`, with HTTPS certificate checking disabled. Authenticated
payload, manifest, release, and suite checks remain mandatory.
The Wi-Fi helper removes the prepared keyfile after successful native profile
publication and refuses mismatched duplicates. Runtime-root validation is
self-contained for standalone seed resolution and persistence, and the
bounded lifecycle reaps deadline zombies before reporting timeout.

This checkpoint is static source evidence only. The generated Forky/Trixie
products were rebuilt and audited, and the native installer/systemd 262,
AppArmor, labwc/Waybar, app-veth, firmware, NVIDIA/CUDA, Perl, Python and
credential-leak acceptance matrix remains deferred.

## Accepted layout and role changes

The user's later corrections supersede the plan's three-entry frontend layout.
Each suite owns physical `classes/`, `fragments/`, `hooks/target/etc/apt/`,
`common.cfg` and generated `preseed.cfg`. The shared implementation lives under
`d-i/debian/`. The retired `d-i/trixie-server/` implementation and its bridge and
builders have been removed. The older sibling server repository supplies no
trusted implementation or artifact identity.

The latest user instruction replaces the capability design in the original plan.
Physical suite class files are authored plain preseed inputs and own package,
repository and debconf answers. Their comments have no behavioral meaning.
The later correction removes all 154 `Installer-*` directives and their parser;
constraints and phase helpers now belong to the separate shared installer
`hooks/installer/class-dispatch.tsv` table. There is no capability catalog,
capability predicate or capability receipt. Shared receipts record classes.

Public roles are desktop base/medium/full and server github-actions/gitlab-cicd/
technitium/devops. Public feature classes are removed. Optional selections live
under `class-select/optional/`; dualboot, SSH, NVIDIA/CUDA and their explicitly
named legacy driver variants stay independent. Crypto and Wi-Fi have no class:
every concrete profile owns `CRYPTO_LUKS2_ROOT`, `CRYPTO_LUKS2_HOME`, `WIFI_ENABLE`
and `MANAGED_NETWORK_PRIMARY_IFACE`. Common APT owns the crypto package baseline.
There are no old selector aliases. Profile classes live under physical
`class-profile/desktop/` and `class-profile/server/` directories in each suite.
Medium owns CH341A, CrowdSec, DevOps, Podman, QEMU/Incus, Tailscale, Timeshift and
Whisper. Full inherits these and adds the broader software collection. CrowdSec belongs to every
role. SSH belongs to every server role. Every Btrfs profile owns its Timeshift
schedule and retention; F2FS requires an explicit `snapshots=none` boot policy.
Server policies retain fewer snapshots at less frequent intervals. Zram and the
Perl support implementation are shared across role families; profiles own sizing.

The latest selection correction permits exactly one desktop role or any
nonempty combination of server roles, with mixed families rejected before
partitioning. Format-2 frozen plans/receipts retain each selected role; there
is no scalar first-server-role fallback. Identical shared stage declarations
coalesce, conflicting providers fail, and helpers remain unique per phase.
Generation includes all 36 suite/role-combination plans (14 individual-role
plans plus 22 combined-server plans). See `class-selection.md` and the
unexecuted `tests/fixtures/class-selection-cases.json` source cases.

Profile `.env` files use ordinary variable references, never asset template
tokens. Canonical runtime directories load before family/host profile data;
profile-dependent runtime file paths load afterwards. The compiler rejects
template tokens and attempts to override invariant roots/selectors/suite keys
from a profile. The CUDA pre-pkgsel path now consumes the validated composite
profile instead of sourcing a raw desktop `.env` file.

## Generation and static evidence so far

- `make build` initially failed on an undefined server profile parent. The
  restricted data parser correctly refused that input; the reference was repaired.
- A subsequent generation completed with release
  `89f1a2538a8cd81a8cfbc8ce851b421cd814993a91c2db40a4e0183de8a584dd`,
  2,179 members. This is a retained intermediate candidate and is now stale.
- Data-only Python AST inspection parsed 397 sources without importing them.
- `python3 -B tools/post_change_check.py` failed: a JPEG asset had a misleading
  `.svg` suffix, and the checker lacked the validated suite input for `repo.env`.
  The asset extension/references and suite input have been corrected. A new audit
  is required after generation; this checkpoint does not claim that it passes.
- Independent agents failed before reading source due to encrypted-context
  hydration errors. No delegated review or passing test is claimed.
- `make build` later completed with release
  `52efbc32cbdc9d0021bf9d8d1e384d7e2fa7ad3a8aa1dd083c6cfa9ac2616395`,
  2,271 members and 36 generated role selections. The complete local candidate
  was created without switching a served pointer.
- `python3 -B tools/post_change_check.py` passed for that candidate:
  3,595 changed files, 498 Python AST inputs, 357 shell/unbound-variable inputs,
  104 AppArmor structural inputs, 672 appearance mappings, 36 role plans,
  2,141 current source/member comparisons, 178 frontend comparisons and six
  trusted product pins. `payload_members=2179` in the general archive counter
  describes a retained earlier archive; `current_release_members=2271` is the
  authoritative current-candidate comparison count.
- Source edits after that audit make the candidate stale again: shared Codex
  redirect acquisition, removal of unreachable direct Ledger publication,
  base network-authorization gating, CrowdSec receipt/family checks, SSH
  allow-list ownership, suite-native ICU packages, optional crypto data
  loading, and runner socket/client policy need a new build and audit.
- The server DevOps fragment and all active source callers now use
  `71-devops-srv.sh`. All fourteen role files explicitly retain CrowdSec's local
  API answers and defer central enrollment. The class-comment parser has been
  removed. These changes are also unbuilt and unaudited at this checkpoint.

## Outstanding acceptance work

## 2026-11-11 15:34 UTC checkpoint

- `make build` exited 0 for
  `53c1d8a8b1bb38fee1bbea2bcdea58b8ea274ba80756c38b0734165cc1570f01`,
  2,278 members. The complete local candidate was staged; no served pointer changed.
- `python3 -B tools/post_change_check.py` exited 0: 3,971 changed files,
  499 Python AST inputs, 362 shell/unbound-variable inputs, 104 AppArmor structural
  inputs, 76 plain preseed class files, 36 role-selection plans, 14 minimum tuple
  plans, 2,142 current source/member comparisons, 174 frontend comparisons and six
  trusted product pins. This is static and serialization evidence only.
- The frozen plan now carries non-package answers and compacted source-local APT
  records; preseed formatting consumes those records. Thirty-two duplicated or
  empty answer/parser helpers were retired. Profile classes are registered in
  the graph and resolve by their family-qualified names.
- Authored `catalog/server-artifacts.json` was removed. Download/source URLs,
  digests, versions, redirect hosts and extraction limits live in `shared-srv.env`.
  The compiler emits a separate target artifact-policy view for each server
  profile, with no moving `latest` download or index fallback.
- Crypto root/home partition recipes, mapper resolution, Timeshift selection,
  config and first-boot enrollment now use independent profile booleans.
  A boot-console unit is staged. The installer bootstrap secret is sealed with
  TPM2 directly from installer input; no plaintext copy is written to the target.
  These source changes still need the remaining crypto identity/recovery review
  and unexecuted failure fixtures; the static pass is not encryption acceptance.
- Every concrete profile has explicit crypto, Wi-Fi and primary-interface values.
  Network priority, Wi-Fi preconfiguration and headless service/firewall consumers
  are the next implementation slice. They are not yet complete.
- A further independent read-only crypto review attempt failed before source
  access with `invalid_encrypted_content`. No sidecar review was obtained.

## Remaining work after this checkpoint

Complete the role-family asset and activation ownership ledger, all frozen-plan
phase consumers, server support and recovery, suite package availability review,
profile rendering and precedence review, source/member/manifest/preseed equality,
active documentation migration, failure-injection fixtures (unexecuted), and the
required changed-file static audit. Trixie's packaged Waybar and Crystal Dock
availability needs an explicit compatibility decision with primary evidence;
foreign-suite core fallbacks are forbidden. Boot, disks, preservation, package
solving, GUI, services, firewall and hardware acceptance remain unverified.

## 2026-11-11 16:53 UTC checkpoint

- `make build` exited 0 for `48b802b7864a2f096a5555a12855d6e6d1531f820bd658fff11b1a0a83c8e5b8`, 2,283 members. No served pointer changed.
- `python3 -B tools/post_change_check.py` exited 0: 4,365 changed regular files, 516 Python AST inputs, 369 shell/unbound-variable inputs, 104 AppArmor structural inputs, 36 role-combination plans, 14 minimum suite/role plans, 2,147 current-source comparisons, 176 frontend comparisons, six trusted product pins, 113 canonical systemd drop-in directories and 266 real runtime placeholder producers.
- The source-selector coverage check now rejects missing FILE owners; the duplicate DIR_SUITES assignment was repaired before this successful build. All fixed system/user unit drop-in directories now derive from runtime.env and the actual publication map. The nftables staging caller uses DIR_SYSTEMD_SYSTEM_NFTABLES_DROPIN. Dynamic read-only per-UID rejection checks retain their validated systemd instance identity.
- Both inventory utilities, their Make target and obsolete inventory documentation/fixture were removed at the user’s explicit request; existing inventory products were preserved and no inventory utility was executed.
- Network, crypto, server identity/store, resolver handover and role-firewall edits are included in this serialization/static snapshot. They have no boot, package-solver, service, firewall, encryption or hardware acceptance evidence.
- New steering extends NFS, Filen/nfsmnt and profile-gated hardware tuning to every host family. Their sharing/lifecycle stages still require implementation below this checkpoint.
- The independent drop-in review agent failed before source access with invalid_encrypted_content. No delegated review is claimed.

## 2026-11-11 17:18 UTC checkpoint

- `make build` exited 0 for `81e31daacffa330adc2c45123426cea0953c090d479fc0958b65ce21fbaf9147`, 2,289 members. The complete local candidate is staged; no served pointer changed.
- `python3 -B tools/post_change_check.py` exited 0: 4,747 changed files, 517 Python AST sources, 376 shell/unbound-variable sources, 105 AppArmor structural sources, 114 canonical system/user drop-in directories, 268 actual runtime placeholder producers, 36 role combinations, 14 minimum suite/role plans, 2,153 source comparisons, 176 frontend comparisons and six trusted product pins.
- NFS, Filen and hardware backend units moved to common/system. The NFS stage is selected for every family, uses the correct family firewall guard and server-owned NFS ACL, and derives policy from all concrete profiles. Shared NFS and identity defaults no longer overwrite selected profile fields.
- `nfsmnt` and `filenmnt` use a common CLI; the desktop menu is a separate wrapper. Mutating systemctl calls preserve a controlling TTY for Trixie’s native authentication agent. Trixie polkit 126’s native helper and Forky’s socket helper have explicit policy paths. Native authentication remains unexecuted.
- The hardware backend is shared, with no desktop assets rendered by its server branch. Config format 2 has a required role_family; server control remains bound to the configured human/root peer UID, while desktop seat restrictions are preserved. Root policy/worker paths consume the same validated config.
- AppArmor mode-writer confinement was extracted into one shared policy. The unit’s desktop recovery dependency lives in a desktop-only drop-in. No policy was loaded into the development host.
- Shared-profile failure fixtures and a source-move ledger were authored as data, never executed. Active sharing docs and operator rollout/rollback/maintenance instructions were updated; historical reports were retained.
- Original task acceptance work remains: full path/component ownership, minimum tuple package qualification and precise Trixie desktop upstream conflicts, crypto device identity/bounded mutation/uncertain recovery review, server artifact/lifecycle recovery review, remaining environment/renderer consumers, and final generation/current-source evidence. The checkpoint is not completion of the full implementation request.

## 2026-11-11 18:29 UTC checkpoint

- `make build` exited 0 for `8e19ac04ce31b8a3830273201a6329bb4991b8bcb2955560f5f0dfe4b55a7c73`, 2,286 members. The local candidate contains both complete suite frontends; no serving pointer changed.
- `python3 -B tools/post_change_check.py` exited 0: 5,486 changed regular files, 517 Python AST sources, 385 shell/unbound-variable sources, 105 AppArmor structural sources, 72 plain class files, 36 role-combination plans, 14 minimum tuple plans, 2,149 source comparisons, 172 frontend comparisons and six trusted product pins. These are static and serialization checks, not executed tests.
- The standard/enhanced security classes and group were removed from both suites at the user's instruction. Both APT fragments retain the universal auditd/AppArmor/nftables/Fail2ban package baseline. The common system-services phase owns one audit configuration and expanded integrity rule set; each desktop role separately includes its graphical AppArmor notification package. Active class examples and source fixtures were migrated.
- Common systemd policy now includes boot profiles, journal retention/sealing/forwarding, native package logging, resource controls, pre-clean/tmpfiles policy and operator-armed diagnostics. Graphical seat/session and desktop resolver policy remain physically separate. Shared SCX implementation follows host-profile policy on both families.
- The artifact transport is shared by software and server artifact acquisition, with per-hop redirect validation and one total transfer deadline. NFS/Filen and server child cleanup retain private recovery state and service-policy backups on uncertain completion. Their failure cases were authored and inspected as source data only.
- The ownership ledger remains human documentation. It is neither compared by the static checker nor consumed by the builder or installed system. An independent package review agent failed before source access with `invalid_encrypted_content`; no sidecar findings are claimed.
- Remaining work still includes common virtualization activation for server DevOps, crypto device identity/recovery, server subordinate-ID and cgroup preflight, complete artifact/application ownership, final documentation and source/release evidence. Trixie desktop has a precise upstream blocker: native Labwc depends on Xwayland, which the required package exclusion forbids. No foreign-suite fallback was added.

## 2026-11-11 19:24 UTC checkpoint

- `make build` exited 0 for `036c014c3f109423311bc5b294ae464d3732be9b2ac9d97a66be2ea717a87c71`, 2,291 members. Source fingerprint: `3c03c3fd4edd6364e705c726ccc7c5fe4849d81238eee3dce53819b5f3aa4d55`. No served pointer changed.
- `python3 -B tools/post_change_check.py` exited 0: 5,857 changed regular files, 520 Python AST sources, 388 shell/unbound-variable sources, 108 AppArmor structural sources, 72 plain class files, 36 role combinations, 14 minimum tuple plans, 2,154 current-source comparisons, 172 frontend comparisons and six trusted product pins.
- Physical common/desktop/server partitions now own AppArmor policy/configuration, tmpfiles, sysctl and local bin/sbin/libexec/lib/share source assets. The in-memory FILE catalogue resolves one owner and rejects cross-family or ambiguous staging. Installed FHS command paths stay stable. A shared data-only native Python site entry selects unversioned project module paths; native systemd/Python packages follow suite candidates.
- Data-only comparison with preceding release `acb0253484e4d3c3b9870d5fa6ea01bd2aa73891753e9050fa13bb66d15dbdbc` found all 1,669 target source assets present at their current owners: 1,652 identical bytes and 17 reviewed edits. All 113 desktop systemd source files retained identical non-comment directive lists. Forky is the desktop target; no desktop service features were removed to accommodate Trixie.
- Crypto native operations bind inherited root/home device descriptors and disk generations; bounded child cleanup, mutation intent, explicit recovery and outcome-unknown propagation are authored with unexecuted failure fixtures. No enrollment or native crypto operation was executed.
- Payload SHA-256: `4795339b01d9a75c0656904aa99d68c59bc6a7415545f35a87004a969b7c38b6`; manifest: `91542631832f47d33c11f03baf48bbeca59bd65bc50e17871d978568829e2ba9`; bootstrap: `9d5d1dc6e465a059b21f33e548a4384b38e566fd0579a1cc6e5533903ad54bb8`.
- Incus host bootstrap and direct-QEMU integration are shared by selected medium/full desktops and server DevOps. Further source changes after this checkpoint separate desktop-only Incus UI checks/login integration into `desktop.virtualization`; the common backend policy loses its UI-file permission and explicitly retains mandatory confinement. Those later changes require regeneration and a new static result.
- Native runtime acceptance, package solving, boot, GUI, services, firewall, disks and hardware remain unverified. The Trixie desktop upstream Xwayland dependency conflict remains a reported incomplete requirement, without foreign-suite fallback. Remaining independent implementation includes firmware/server DevOps ownership, server preflight/resource policy, inactive developer-tool callers, profile precedence, documentation and final evidence.

## 2026-11-11 19:55 UTC checkpoint

- `make build` exited 0 for `dfa6c569d797d8cd0176f7023356897521a3e86470f88d29e7e71e1cb26fbf99`, 2,301 members, source fingerprint `131580aa761d7e3bdbef2bb881bcb482d6ff507bb3d658ba3e20d96ee34d4b4c`. Both complete suite frontends remain a local publication candidate; no served pointer changed.
- `python3 -B tools/post_change_check.py` exited 0: 6,415 changed regular files, 522 Python AST sources, 396 shell/unbound-variable sources, 109 AppArmor structural sources, 795 partitioned target source files, 117 canonical systemd drop-in directories, 275 actual runtime placeholder producers, 36 role combinations, 14 minimum tuple plans, 2,164 current-source comparisons, 172 frontend comparisons and six trusted product pins.
- The preceding `8a5be718eac73c33b3fc8a17ea4f487781a008fe5503249335ac6de6acb87c48` audit failed because a remaining runtime UI call was still in the common Incus backend. That call and its function were moved into a separately confined desktop UI readiness helper/service and a desktop-only restricted-broker dependency. The common helper, configuration and AppArmor profile now contain no UI dependency. The corrected candidate above passed the same check. Its backend service explicitly requires its AppArmor profile; desktop mode policy keeps the backend and UI probe enforced independently of ordinary application mode.
- Shared firmware installation now owns CH341A/UART CLI presence, the primary operator's workspace and USB groups, udev data and verified SNANDer releases. Desktop login/GUI integration is a separate stage; server DevOps never fetches a desktop account environment or validates graphical entrypoints. The SNANDer path uses the shared redirect-aware HTTP transport, pinned source/binary digests, bounded streaming tar/PAX metadata/member/expanded-byte handling, regular-file/directory-only member policy, amd64 ELF validation and complete source/license/metadata retention. No archive program, programmer or device operation ran. Uncertain acquisition retains private evidence and requires explicit recovery after reboot.
- All selected subordinate-ID ranges are checked against both native databases and existing UIDs/GIDs before any service identity/store mutation. Runner services and reserved service user-manager instances share an aggregate workload slice, including rootless engine jobs. These contracts have unexecuted source/failure fixtures; no account, manager, service, job, package or container operation was run.
- Explicit profile boot values now precede common boot defaults. Native package candidate/version assumptions were not restored. Forky desktop features remain the desktop target; Trixie server compatibility does not remove or lower those features.
- Payload SHA-256 `54d7017f7e7b99e07361ffbe94c2f6aa300edf551d127e6458b76fba62b40173`; manifest `fc38e0a038cf1a0979f360f77dfe3a46bbe4d81617cc6dc07ae47e8d2607db0c`; bootstrap `9d5d1dc6e465a059b21f33e548a4384b38e566fd0579a1cc6e5533903ad54bb8`; receipt `2ddf3dd5ae58acd125a149a711c9280159312d1056fc06a6bd473a4827a93021`.
- Work remains incomplete: migrate every remaining account-data shell load to restricted data, finish developer-tool callers/profile ownership and unused server policy/artifact fields, review the firmware device-mode authority, complete the human ownership/operations documentation, and regenerate/finalize evidence after those changes. The native Trixie desktop Xwayland dependency blocker remains explicit. No native boot, package solving, disk preservation, GUI, service, firewall, encryption or hardware acceptance is claimed.

## 2026-11-11 20:06 UTC checkpoint

- `make build` exited 0 for `aa3b9bca0299f1d6b9fe222664f15f0bd98804cbbc0ba56514d369dcf15b2cc5`, 2,327 members; source fingerprint `50a4cdfa3131486f3b52ce7833c5450986c096c21e08e91c6e14aa5679879b10`. No served pointer changed.
- `python3 -B tools/post_change_check.py` exited 0: 6,598 changed regular files, 522 Python AST sources, 398 shell/unbound-variable sources, 109 AppArmor structural sources, 795 partitioned target sources, 117 canonical systemd drop-in directories, 275 runtime placeholder producers, 36 role combinations, 14 minimum tuple plans, 2,164 current-source comparisons, 172 frontend comparisons and six trusted product pins.
- The same restricted AWK grammar now decodes initrd credentials and compiled/effective account snapshots, with distinct permitted-name/size contracts. Snapshot decoding validates the complete input before assignment, rejects process environment overrides, preserves literal dollar/backtick/apostrophe/empty data and disables shell tracing. Eleven early/partman/finish/late account callers were migrated from sourcing data to the loader. AWK was inspected as source, never executed; its behavior fixtures remain unexecuted.
- Each suite/profile has a separate non-secret account-policy view. A data-only archive read using Python standard-library tarfile/shlex parsed all 26 views: 20 desktop views with `audio cdrom video sudo`, six server views with `sudo`; no primary identity/password or calendar credentials were present. This check imported no repository code and did not run the AWK parser or fixtures.
- Payload SHA-256 `dc2670018e1ddea4542fc9012d274e6f87cc9c65d120d26877c4f38800fe5957`; manifest `90aeaf5e63fc0aabcbf61147615dcf43de1bdec7b06f257f26b1a691a3ac30bb`; bootstrap `9d5d1dc6e465a059b21f33e548a4384b38e566fd0579a1cc6e5533903ad54bb8`.
- Outstanding independent work remains as above: developer-tool caller migration, remaining server policy/artifact ownership, firmware device-mode authority, active human documentation/ledger updates, native-package acquisition assumptions and final regenerated evidence. Runtime/boot acceptance remains unverified and native Trixie desktops remain blocked by the documented Labwc/Xwayland dependency conflict.

## 2026-11-12 continuation checkpoint

The current source is commit `ec5ef46d01c7bb96efb52129592a154c81a6a637`
plus the preserved, uncommitted implementation. The initial tracked source
fingerprint at that commit was
`5ff8e0e676ea327fa6e9ffe67a7b9a77c3c0670d5714645a9aedefa3d9374c68`.
The supplied audit archive was treated as an older reference, without inventing
Git history. Current ownership and callers were reassessed against this checkout.

The everyday desktop now stages Bitwarden, Tuta, Sleek, Tomat, Ledger Live,
Vivaldi, Spotify, L3afpad and calendar support in all three tiers. Base omits
extra browsers and specialist development/virtualization/firmware/AI activation.
All tiers retain the same Labwc/Waybar session and everyday menu controls.
CH341A CLI/USB/firmware support belongs to medium/full and server DevOps;
graphical programmer/login integration remains desktop-only. Firmware device
mode still refuses an identity-unsafe mutation rather than pretending success.

Every desktop profile declares internal and external workspace counts. The
existing output watcher applies the native global workspace count according
to the active topology, with its existing lock, identity checks, atomic XML,
bounded reload and retained previous-state evidence. No second watcher was
introduced. Labwc workspaces cover all outputs, as documented by the
[upstream configuration reference](https://labwc.github.io/labwc-config.5.html#workspaces).

All 36 authored environment files were grouped into larger sections. The
formatting retained assignment bytes and order. The intentional policy changes
move domain/prefix into each family's shared environment, make the custom TLS
SAN optional and add explicit outer theme archive limits. Thirteen concrete
profiles no longer duplicate the shared identity. Empty custom SAN preserves
each resolver's configured authenticated name, including custom-CA mode.
Native Python/systemd packages and native module ABIs follow suite candidates;
the special XanMod EDGE image/header pairs remain explicitly fixed by policy.

Desktop Appearance remains limited to its existing desktop, toolkit and
icon/pointer controls. No application-preference pages were added. The registry
retains nine field components, 567 fields and 672 current source mappings.
Exact owner permissions now cover Waybar module/style/icon and Swaylock atomic
siblings. Fifteen runtime modules remain installed. Initial capture, outer
release extraction and four theme-installation modules moved to temporary,
root-private installer staging; both installation-only target entrypoints
were removed. Bounded outer extraction verifies digest and file identity,
rejects unsafe members and never executes an archive program. Runtime field
and theme writers retain their shared lock and recovery journals.

The active Ledger installer uses the dedicated-identity packaged extractor;
Ledger/Tuta unknown extraction outcomes retain their private workspace. The
shared extractor's lock acquisition is bounded. Unused Tuta/Postman direct
publication methods were removed after caller review. Their verifiers require
the native publisher. Discord's active repair/bootstrap authority remains
separate, and private Xwayland eligibility remains exactly Zoom/Discord.

All managed container stores, image/backup/log volumes, compilation outputs
and build caches require the mounted pool. Incus daemon metadata/sockets retain
native package locations. Technitium uses the newly implemented unprivileged
Incus/veth service, private management and pinned DNS/.NET artifacts; it cannot
be combined with current runner roles. Missing enrollment stays pending.
SSH, network sharing and hardware policy retain common implementation with
family-specific UI/activation, rather than copying desktop credentials or
login setup into servers. Installation-only network, firmware and server setup
programs also remain outside persistent target assets.

The human ownership ledger accounts for all 2,893 baseline paths and names
existing regular files for every current implementation owner. Historical
`todo/journalctl` is explicitly reference-only because it is absent from this
checkout. This documentation is neither installed nor consumed by generation
or the static checker. Independent review delegation was attempted again but
failed before source access with `invalid_encrypted_content`; no sidecar
findings or successful independent review are claimed.

### Current immutable local candidate

`make build` exited 0 for release
`fd9ebad5acd828790c3b51f3f4a75a61d3c79ebcc9aba483027f0fc8b8f24098`,
with 2,315 members. It staged both complete frontend trees and their shared
release locally; it did not switch a served pointer. Source/compiler fingerprint:
`8b283fe178e18b036ffbacafde40f0923312d5a0d3394a6795eee6ff2cbff2f8`.

| Product | SHA-256 |
|---|---|
| Payload | `cde36b4f85cf8d3fa31451c5d9209e62f92f45e7a1614529b5717135ff2b1cac` |
| Manifest | `4bf015b21d7a2d45519ef8a4bf4e7f6e7b6b434cd547ab8dcbd44bf8522600fa` |
| Bootstrap | `9d5d1dc6e465a059b21f33e548a4384b38e566fd0579a1cc6e5533903ad54bb8` |
| Receipt | `29911f2399174602d576f8d837bf2d12737c71d7f61bd1f276211a7d30780e09` |
| Support matrix | `ff0b2a12aec48418f02ad6dc591db5463826187eb4ac1fa836a1f70f05ab782a` |
| Forky preseed | `0af5e6e982b1478b6ae01dad930a82ec2abe5ec0260aa0abc1af85be532c54ef` |
| Trixie preseed | `d07f7bad7882962bdf49ca6ac500d22fbe8211ea11fe00f787eb9539d379c04e` |

Both generated roots are ignored. `git ls-files -- d-i/debian/releases
d-i/debian/publications` produced no paths. The authorized index cleanup stages
4,474 generated-file removals; ignored local copies remain available for review
and rollback. Authored classes, fragments and family APT policy remain inputs.

### Static evidence and limits

- `python3 -B tools/post_change_check.py` exited 0 for this release before this
  checkpoint was appended: 197 changed regular files, 37 Python AST sources,
  78 shell/ShellCheck/unbound-variable sources, five AppArmor structural sources,
  118 canonical systemd drop-in directories and 297 runtime placeholder producers.
  It checked 2,180 current source/member identities, 178 frontend identities,
  six trusted product pins, 22 role combinations and 14 individual minimum plans.
  Appearance checks covered 567 rendered defaults, 672 source/mapping/capture
  records, 726 native token occurrences, 15 runtime modules and exact atomic
  permissions for 79 native desktop files. This command is repeated after the
  final documentation update.
- `git diff --check` exited 0. A bounded source search of active tools, installer
  and profile inputs found no inventory target/tool, old owner map or retired
  repository/server-artifact JSON catalog reference.
- Standalone `python3 -I -B -` standard-library data inspection read all 1,680
  target regular files and 52 desktop installer files. It parsed 247 target and
  17 desktop Python sources and 84 non-template target JSON documents. The 25
  JSON templates remain source templates and belong to rendering checks. An
  initial attempt to parse raw JSON templates stopped on an unresolved numeric
  template token; correcting that classification completed the data inspection.
  No repository module was imported. This is structural coverage with focused
  semantic review, not proof of every line or a passing runtime test.
- Combined target/desktop fingerprint (sorted SHA-256, two spaces, relative
  path, LF): `1ae765a2a2184fb66d4fd24714ece9ae508cc4358c5a6ab415d3a70fc7e864dc`.
  The seven new JSON fixture sources have fingerprint
  `0438487c8efe62b6d198cc96ae8721445fd6c3b81cad1b697de2757ec386943d`.
  Their cases, the updated Stubby cases and all other behavioral/failure fixtures
  remain unexecuted.
- Source-check Python is 3.14.10; Dash, BusyBox and ShellCheck are available.
  No native target image/package execution evidence exists. The offline AppArmor
  parser binary is available, but private package support/ABI inputs were not
  staged and compilation was not performed. Perl compilation/BEGIN execution,
  tests, discovery, managed imports, package operations, services, GUI, policy
  loading and disposable environments were not run.

### Incomplete upstream requirement and operator boundary

All fourteen individual plans and twenty-two permitted role combinations have
source implementations. Three Trixie desktop plans remain blocked before
partitioning: native Trixie Labwc depends on system Xwayland, which the requested
package policy prohibits. Debian's [current package dependency record](https://packages.debian.org/trixie/labwc)
was rechecked. No foreign-suite fallback or source build was substituted. Thus
the original twelve-tuple native requirement remains incomplete for those
three tuples. The other eleven individual plans, including server DevOps in
each suite, are source candidates with native acceptance unverified. Arm64,
dualboot preservation and identity-unsafe programmer mode are not qualified.
F2FS retains explicit snapshots=none; no filesystem is silently changed.

Review both frontend preseeds, the ignored complete candidate, receipt, package
pins, profile policy and this blocker before any separately authorized rollout.
Use the single complete-tree pointer procedure and retained previous identity
documented in [operations](operations.md); rollback selects that previous whole
tree, never one frontend or payload file. Neither pointer tool, including its
preview, was executed. There was no push, merge, publication, deployment,
enrollment, workflow execution or repartitioning. Boot, disk preservation,
package solving, GUI, services, firewall, encryption and hardware acceptance
remain unverified.

## 2026-11-12 appearance recovery and offline policy checkpoint

This continuation preserves the current checkout and the preceding implementation.
Desktop Appearance still exposes the same nine desktop field components:
Fuzzel, Waybar, Taskview, Waycal, Crystal Dock, GtkGreet, Terminal, Swaylock and
Mako, together with its existing desktop toolkit/icon/pointer choices. The
registry remains 567 fields and 672 mappings. No application-preference page or
application-owned configuration path was added.

Source review found that color editing stopped Crystal Dock before acquiring
the account lock or persisting liveness. The color coordinator now owns stop,
QSettings recapture, file publication, restart and recovery under the existing
lock. It writes liveness before stopping, preserves legitimate shutdown writes
and retains the journal until the exact dock unit is active again. Theme and
field recovery check committed native bytes before finalizing root evidence.

Mixed account/greeter color edits now use the same authenticated commit/rollback
protocol as theme edits. Root stores the initiating UID, token and operation
kind in its existing private journal; it never reads an account journal as root
authority. Retained alternate greeter evidence is a read-only refusal condition
before new edits or wallpaper recovery; it is never replayed or rewritten by the
new protocol. A failed or lost reply restores account bytes where provable and
retains evidence until greeter recovery succeeds. The GTK entrypoint, component
catalog and desktop-only path allow-list remain the same. The shared static audit
now checks lock placement, dispatch argument shapes and commit-check ordering as
source AST, without executing these operations.

The source fixture has eighteen unexecuted cases, including stop interruption,
authentication cancellation, lost root replies, committed file replacement and
a restart request that never becomes active. Its SHA-256 is
`a102b7e772ede0f30c87e3233eb5aa0dc57da6bdf7ceb265150d375acef36e3d`.
The fifteen runtime module sources have fingerprint
`4c50f9e00f6efd00efc6affb90f56f2eb79bcec436d51152d2aa6b228f749f32`
(sorted SHA-256, two spaces, repository-relative path, LF). Five human ownership
entries were updated to describe the changed source, without making the ledger
an installation or checker input.

### Explicit offline AppArmor exception

Twelve compiler invocations exited 0: `labwc-appearance`, `labwc-session`,
`waybar-menus`, `calendars`, `labwc-network-sharing` and `desktop-wrappers`, each
with the corresponding Forky or Trixie public package support tree. Exact argv,
package URLs, lengths, SHA-256 values and input identities are recorded in
[desktop-appearance-static-20261112.json](../validation/desktop-appearance-static-20261112.json).
The policy/rendering input fingerprint is
`aa235e2fe918b5b94e75c6556f5af3fc32d48b9d52ab3d80abb3d6cc06dffd96`.

The installed parser reported 4.1.8. Support data came from Debian apparmor
4.1.8-3+b1 for Forky and 4.1.0-1 for Trixie; the Trixie parser binary was not
executed. Package bytes matched Debian's public download-page sizes and hashes;
no Release signature-chain verification is claimed for this data acquisition.
Only regular policy support members were staged, with no package installation,
maintainer-script or downloaded-executable execution.

Each invocation used `-Q -K -j 1 --max-jobs 1`, an explicit empty private parser
configuration, private base/include/cache paths and both feature inputs from the
declared package. Deadlines were 15 or 30 seconds. Forty-three absolute package
ABI lookups were relocated only in each private copy. Account-specific rules
used the synthetic name `static-review`; the lockscreen path came from the
authored source-image theme value. The first staging attempt stopped on an
unrelated unresolved policy value. The first wrapper closure/copy also lacked
its ordinary account/theme substitutions; completing that private rendering
resolved the initial compiler errors without a source policy change.

No host policy, parser configuration, cache or kernel feature input was used.
Nothing was loaded into the kernel. These results prove offline compilation of
the recorded policy inputs, not runtime file access, loaded modes or a successful
desktop session. All behavioral/failure fixtures, GUI/service/network/installer
checks and other native tests remain unexecuted.

### Regenerated local candidate and static evidence

`timeout 60s make build` exited 0 and created release
`11eef25994980c769e9e0dfa4b96b434683cc9deb5bea93f1aa71ddf376675d8`,
with 2,315 members. Source/compiler fingerprint:
`a14e9f398a07a8b77e5c7f4ea848c9d8adae70242c5ff8f066facaf76d653e4a`.

| Product | SHA-256 |
|---|---|
| Payload | `0a194f04dec751d71196ff99565520912a3ccb3d46adf6ffe7a9b450d147548e` |
| Manifest | `53ff5eceb18575e531f806e3a6312b53d2c58d9f0c9ad1a8010525651712cca2` |
| Bootstrap | `9d5d1dc6e465a059b21f33e548a4384b38e566fd0579a1cc6e5533903ad54bb8` |
| Receipt | `184df4b46ce413f0caa6a0ff650b61589fe6c8ea81f813f5d22cf0b023bd93b3` |
| Support matrix | `ff0b2a12aec48418f02ad6dc591db5463826187eb4ac1fa836a1f70f05ab782a` |
| Forky preseed | `37fd802ab7475ef6c71bbd3c3336009e9b1d5384f0b67fda731c76b13072028a` |
| Trixie preseed | `7538ed1585d5117955c79598188ca8b4879e197b939bf376332bffff9fbef70a` |

`timeout 120s python3 -B tools/post_change_check.py` exited 0 before this final
documentation addition: 204 changed regular files, 41 Python AST sources,
78 shell/ShellCheck/unbound-variable sources, two appearance recovery protocols,
567 rendered field defaults, 672 mappings, 726 native token occurrences,
79 exact native file permissions, 2,180 current source/member identities,
178 frontend identities and six trusted product pins. The same audit is repeated
after the final documentation update. `git diff --check` exited 0.

Both generated roots remain ignored, previous candidates remain available and
no served pointer changed. The recorded installer failure was also traced again:
software now loads the common bootstrap, repository selectors and validated
installer `di.env` before deriving `DIR_INSTALLER_LATE_ENV`. That is a source
repair of the recorded fatal path, not a claim that an installer boot completed.

The three native Trixie desktop plans remain incomplete because their Labwc
package requires prohibited system Xwayland. No suite fallback was introduced.
The existing complete-tree rollout/rollback procedure in
[operations](operations.md#operator-publication-and-rollback) still applies only
after separate operator authorization. No publication, deployment, enrollment,
workflow, repartitioning or host repair occurred in this continuation.

## 2026-11-12 desktop resource isolation and source-capture checkpoint

Source revision remains `ec5ef46d01c7bb96efb52129592a154c81a6a637` with the
existing working changes preserved. Desktop resource design now uses upstream
systemd 262 as its minimum baseline for Forky; native packages remain unpinned.
The reviewed upstream resource, scope and stop-property references are linked
in [desktop resources](desktop-resources.md). Installed package versions and
effective controller behavior were not measured.

Session infrastructure, managed applications and compilation have separate
session/application/build slices. Waybar, Crystal Dock, Mako and audio overrides
join the compositor's session slice. Soft memory protection extends through
three system ancestors and the account's session/application slices. The
profile-owned build policy defaults to CPU/I/O weight 20, memory high/max
60%/75%, swap max 20% and 8,192 tasks; existing weight switches still apply.
Canonical runtime drop-in roots and repository selectors own all new paths.
The plan compiler rejects malformed/reversed resource values before publication,
and target rendering validates them again.

The DevOps shell and ordinary interactive build/compiler aliases use one
synchronous user scope through the installed user-facing `labwc-build` command.
Nested compilers inherit the existing scope. Argv expansion is disabled, the
terminal/environment/cwd are retained, missing ownership/policy fails without
an unconfined fallback, and the scope owns its fifteen-second stop budget.
Explicit absolute compiler calls outside that shell and IDE/external workers
still need a reviewed build owner; no universal interception claim is made.

All ten desktop profiles have moderately later available-memory and emergency
PSI gates, smaller writeback batches and a ninety-second emergency cooldown.
One 8,192-page emergency envelope and a 16,384-page pressure envelope cover
all recompression tiers plus selected writeback; half remains available for
disk relief when available. Pressure/emergency compaction is deferred to normal
maintenance. The controller remembers the last emergency completion independently,
so state oscillation cannot bypass cooldown. Zram, PSI, OR triggers and normal
maintenance remain enabled. Servers share the same implementation with
32,768/16,384-page pressure/emergency defaults. Other server profile thresholds
and scheduling remain unchanged.

The builder's shared, frontend and compiler captures now use pinned Linux
file descriptors, single-link regular-file checks, bounded enumeration/reads
and a complete membership/identity recheck. The Linux `/proc/self/fd` interface
is used only to promote the builder's own checked source inode; no host policy,
service, package, network or device state is read. Serialization consumes the
captured bytes. Removed dead payload-file/template lookup and mutable-source
preseed fallbacks; affected source fixtures now use the actual immutable API.
This is optimistic source-change detection, not a filesystem snapshot or a
claim of safety against a malicious account controlling the entire checkout.

Permitted commands/results in this continuation:

- Standalone standard-library `ast.parse` and JSON data parsing succeeded;
  no managed module was imported by these checks.
- `timeout 60s make build` exited 0 four times. The first two generations
  produced `aaccf1edfc7a3c552a94dad7e7ac19d7c921913dc56f9895adb75cae4ef97a94`
  identically. After adding publication-time profile guards and the bounded pressure policy,
  the final generation produced the release below. Old ignored candidates were retained.
- `timeout 120s python3 -B tools/post_change_check.py` exited 0 after each
  generation stage. The final source audit reports 228 changed regular files,
  44 Python ASTs, 80 shell/ShellCheck/unbound-variable sources, 120 canonical
  drop-in roots, 299 runtime placeholder producers, three slice contracts and
  three memory-protection ancestors. Both pressure and emergency envelopes
  have source contract checks. It verified 2,185 source identities,
  178 frontend identities, all 2,320 members and six preseed product pins.
- `git diff --check` and `git diff --cached --check` exited 0. Generated
  release/publication trees have no tracked members and remain ignored.

Final release and SHA-256 identities:

```text
release           dc429ae3441842b2deb2533b40705656d91017df403cf30c5476762cfbb89d86
source/compiler   db6a409871a8b9100a1278730f4ddc2d312dbe3bcb28c733fd99d89f16da02d3
payload.tar.gz    40a5410cca2054fea7834bd47853cc25b9de98e3ccbc22cd89809b4634b2d9a9
payload.manifest  3ff1af66fa13f85a2c58b88cc3a819a20f94600cf662f12b71110885cb0da8ba
source.sh         9d5d1dc6e465a059b21f33e548a4384b38e566fd0579a1cc6e5533903ad54bb8
receipt.json      46c42a82ce929807228aea9de0b1d1aafd7871777266bd42cf9d8ce8e82509fc
support-matrix    ff0b2a12aec48418f02ad6dc591db5463826187eb4ac1fa836a1f70f05ab782a
Forky preseed     763aa6b24228e2ede4faa46b61b395edce9c4c362163a6f4d60a57f2f87bc9fc
Trixie preseed    afb4fed90bee45ac5c34ec7ebb34936ba7aa37a253fa7ee12e9847f2eb8d4846
```

## 2026-11-12 suite repository and runner boundary checkpoint

The installer log failure was traced to `prepare-context`: the kernel command
line used the documented semicolon-separated class list
`prod;full;static;btrfs-de-p15s;nvidia-legacy;cuda-legacy`, but the previous
shell bracket expression rejected a literal separator under the installer
shell. `class-selection.sh` now validates printable input and each separator-
stripped token with a BusyBox-compatible whitelist; the exact failure input is
retained in the unexecuted class-parser fixture.

Forky no longer adds a positive Trixie source. Forky desktop classes use the
native Forky Hyprpolkitagent and Incus packages; Zabbly and Trixie Backports
entries were removed. Microsoft PowerShell and Oracle MySQL Shell remain
Trixie-full-only because their publishers do not expose a Forky/Testing
archive; Forky full omits those packages instead of using a foreign-suite
fallback. Forky keeps the requested normal-priority Cramerz archive and its
published Tailscale Forky channel.

GitHub/GitLab runner administration remains server-only. The desktop skeleton
has no runner profile or runner selector; only `72-ci-runners-srv.sh.tmpl`, the
server control command, and server unit staging remain. Server Podman runtime
directories and sockets are now profile-owned, rendered into the runner units,
and the compiled GitLab policy selects architecture-specific Ubuntu helper
images (`amd64` and `arm64`) rather than one x86-only tag.

The regenerated products are identified by source identity
`fef50448f12717cbcd1e3be7d9e50a3b7fadcfb1aff15da5ed633d62f5a20e41` and 2,341
payload members. Both suites share the following payload products:

```text
payload.tar.gz  2b1324663eb53142dd64add6638fc00d471103179205ef48d40bd16abaa7f7c3
payload.manifest ea0e4031e2b8d9abb9bcf35fa81c6f068bb794b4969dc9b632c93717dc2f5bae
source.sh b789131ba59b74e266b9a1e4317b17b7efde58930b10ffac54c1595b3a5736e9
receipt.json aecad8cbd29ca0f5a37f6b61c8039612cfe89695365a1e709abfaaa8c0abb80c
support-matrix.json ff0b2a12aec48418f02ad6dc591db5463826187eb4ac1fa836a1f70f05ab782a
Forky preseed 4035d1253b2baaae8da02e48833c9b271039f7aba45a250bf78917402121628c
Trixie preseed 4440b58a91f5d324229d3c79b0f75cd7f886cce00b79344a22f009963ef26377
```

`timeout 120s make build`, `timeout 120s python3 -B
tools/post_change_check.py`, and `git diff --check` completed successfully.
The audit reported 130 changed files, 2,341 current release members, 2,206
source-equality comparisons, 35 server Podman policy fields, and two
server-only runner-enrollment contracts. Native installer boot, package
solving, service startup, container execution, helper-image acquisition, and
runner enrollment remain unexecuted under the repository's static-only limit.

## 2026-11-12 runner scheduler correction

The preceding scheduler checkpoint is superseded for runner activation. The
server runner units no longer call `scx-workload-handoff` from
`ExecStartPre`/`ExecStopPost`; that helper and its repository selector were
removed. The old arrangement changed the global scheduler for the entire
runner daemon lifetime rather than for an individual job, and its peer-service
mapping was reversed. Desktop runner administration remains absent: neither
desktop skeleton staging nor either flat payload contains a desktop runner
profile.

Job-aware scheduler switching remains an explicit incomplete requirement. GitHub
does expose synchronous `ACTIONS_RUNNER_HOOK_JOB_STARTED` and
`ACTIONS_RUNNER_HOOK_JOB_COMPLETED` hooks, but this checkout does not yet have a
reviewed root-authorized lease broker for them. GitLab's documented
`pre_build_script` runs in the Docker job container, so it cannot safely control
the host scheduler without exposing a privileged host channel. No daemon-lifetime
fallback was retained; a broker/lease design must be reviewed before the
profile-selected performance worker is enabled for individual runner jobs.

The corrected pure build produced source identity
`d264aa1afbe14548fbc4d394225232a0ce88573ee361b8f9df81df0cdf316f63` and 2,341
payload members. Forky and Trixie flat products are byte-identical for this
snapshot: `payload.tar.gz`
`9922755a30b21992cd6d50c9e0e31d1e9712743796e8f63ecf9a948f9f583c32`,
`payload.manifest`
`a814e933e73d9281edc3e4ae143953ca4de0c46a92cb1bc64cfe6feb8b128891`,
`source.sh`
`b789131ba59b74e266b9a1e4317b17b7efde58930b10ffac54c1595b3a5736e9`,
`receipt.json`
`ee13d2d9f32e0923cc78e2426dfe75454b4143c305b85694c9a7e4c7e4632367`, and
`support-matrix.json`
`ff0b2a12aec48418f02ad6dc591db5463826187eb4ac1fa836a1f70f05ab782a`.

`timeout 120s make build` and
`timeout 120s python3 -B tools/post_change_check.py` both completed
successfully. The audit reported 118 changed files, 2,341 current release
members, 2,206 source-equality comparisons and 56 shell/static inputs. Data-only
archive inspection found no obsolete handoff member, no desktop runner profile,
and the expected server runner assets in both suites. No installer, test
runner, service, package, host policy, runner enrollment or native scheduler
operation was executed.

The nineteen resource failure cases remain unexecuted; fixture SHA-256 is
`fee3f3dfba9075c6faad5a52766e3345c073a93dc3563249ff95b25eabb75c3e`.
The updated installer-module fixture SHA-256 is
`e9ddb7d406cba7bf6086c8f3bca68b469eccb0cddd14e2fb2bee830c7d15ecdf`;
the I/O-PSI fixture is
`115319b2fdf8efad195fa1e20773f3436599f4da5b2fb7a787fced08e0322ba4`.
Independent sidecar requests failed before source access with encrypted-content
hydration errors and supplied no findings. No fixture, Perl BEGIN/import,
native validator, live helper or service was executed. The existing offline
AppArmor record remains historical; no parser was invoked in this continuation.

The human ownership ledger records the affected source owners, and is neither
an installed-system input nor a publication/checker authority. Desktop
Appearance remains at nine desktop components with 567 fields and 672 mappings;
no application-preference controls were added.

Review the complete candidate and policy using [operations](operations.md).
No served pointer was switched. Rollback must select the recorded previous
complete served-tree identity, which is distinct from a local source release ID.
The original three Trixie desktop requirements remain incomplete because native
Labwc requires prohibited system Xwayland. No foreign-suite fallback, package
solver, boot/disk, GUI, OOM/load, firewall, service or hardware acceptance is
claimed. No push, merge, deployment, enrollment, workflow or repartitioning ran.

## 2026-11-12 immutable publication integrity checkpoint

The previous goal turn made implementation progress on desktop resources and
source capture. This continuation preserves that work and revision
`ec5ef46d01c7bb96efb52129592a154c81a6a637`, and closes confirmed local publication
defects. The original ZIP identity remains independent historical evidence;
the current source/compiler fingerprint below describes this working tree.

Reviewed the full pure build path, its publication library, both generated
frontend callers, the guarded source fixtures, the manual operator caller and
the active operations/rollback contract. Parent creation formerly followed
symlinks before validation, existing-tree reads/enumeration were insufficiently
bounded, restrictive creation masks could leave served children private, and
concurrent generation did not have an explicit writer/reuse contract. The
publication library now pins destination directory descriptors and uses
no-follow relative opens, creation, metadata, rename and synchronization. It
validates product grammar, prefix collisions and aggregate bounds before output
creation, checks exact file/directory sets and owner/mode/content, and performs
a second complete metadata capture. Regular file content is read only from a
checked pinned inode through Linux's own descriptor interface. Published
directories are explicitly 0755 and members 0644.

Cooperating writers take a nonblocking lock on the pinned output parent and
reuse an identical completed tree. Incomplete staging remains private with its
exact retained path reported. Cleanup only names the writer's own temporary
inode; cleanup/synchronization failures preserve the primary error and evidence.
Post-rename uncertainty has a separate exception and direct Python CLI result
75; ordinary failure returns 1. Make reports its own failed-recipe status.
The operator tool's source adapter preserves the same distinction and retained
transaction journal. It was not executed, including preview. Descriptor I/O and
optimistic identity checks do not claim a filesystem snapshot or protection
against a malicious owner controlling the whole checkout.

The mandatory checker now inspects these publication contracts and both result
adapters as source AST, in addition to the existing source-capture, pure-build,
role, asset, appearance and current-source/member/pin checks. The human ownership
ledger records changed tool owners; no installer or checker uses that ledger as
policy. No installed-system helper or target asset was added by this continuation.

Permitted commands/results:

- Standalone standard-library `ast.parse` checks succeeded for the publication,
  builder, operator, checker and guarded fixture sources. JSON parsing found
  23 unique publication fixture cases. These commands imported no repository
  implementation or fixture.
- `timeout 60s make build` exited 0 five times. The first two generations
  reproduced `62b4966c5c6e5aaf08ab2fa53ae1cdfa02ddc7abcc0bc9457711320b9d69fa21`.
  After the caller-result repair, the intermediate release was
  `67307d5226c1c8dbf753cfde81f12d821c89f165348ac03264d06e4757393e4a`.
  After the retained-evidence diagnostic update, both final generations
  reproduced `08b1aa52970e614a07f45e4b2185eb5546080bcdf166c97705559f98b26d1ca6`.
  Generation wrote only authorized local products and checkout preseed views.
- `timeout 120s python3 -B tools/post_change_check.py` passed for the current
  release. Its source scope includes 231 changed regular files, 46 Python ASTs,
  80 shell/ShellCheck/unbound-variable sources and 67 structured files. It
  verified 2,185 source identities, 178 frontend identities, 2,320 payload
  members, six trusted product pins, 22 role-combination plans and 14 individual
  role plans. New publication descriptor/recovery checks and two uncertain-result
  adapters passed their static contract checks. Desktop Appearance remains at
  nine desktop components, 567 fields and 672 mappings.
- `git diff --check` and `git diff --cached --check` exited 0. `git ls-files --
  d-i/debian/releases d-i/debian/publications` returned no paths; `git check-ignore`
  confirmed both current product roots remain ignored.

Current release and SHA-256 identities:

```text
release           08b1aa52970e614a07f45e4b2185eb5546080bcdf166c97705559f98b26d1ca6
source/compiler   a6505ca17e4191d868435a96fc5aeadd1d802e5dd16dd0747fc7cb9e43e232db
payload.tar.gz    10fff79bedd2c2dcc9a7e8be694c6befbb5cd5930ed19c37d76c4600438401e1
payload.manifest  d90c790e5ca2aded3e576a3d1286df0300f3d54a833f76c042c6cfce5f40afa0
source.sh         9d5d1dc6e465a059b21f33e548a4384b38e566fd0579a1cc6e5533903ad54bb8
receipt.json      1c8a0d77063f226796aa2f79c338620d6789fe7c9643b5855c2dadbeb22099b4
support-matrix    ff0b2a12aec48418f02ad6dc591db5463826187eb4ac1fa836a1f70f05ab782a
Forky preseed     d910bd971cbafa65933a1550a34f679b61f49f47ca4d32f2f30cdc149db61db4
Trixie preseed    270ddea190118f126824067592ad7d16c86084df003fe715c8b471898749fb5d
```

The seventeen guarded `PublicationContracts` methods and 23 JSON cases remain
unexecuted. Current source/fixture SHA-256 identities are:

```text
tools/publication.py                       7925d867b8efdfeafd4f76f28a4516ce0a956e14bf4a4d5dbf3cbbe7c225e07c
tools/release_pointer.py                   9cbb4dfb2603f206222506a4b2c2a8ef6286119263f76a055369e88ff7b4d4b5
tools/tests/test_installer_modules.py      7c9e07cd51d3fd949f3247be7bd1dc85616ba48e7861d2b66d8b223f3a6d238e
tests/fixtures/immutable-publication.json  846ebd8236534c5237b0d8ee21835c3e44a4d8841c54ed76e9e348036adfcd52
```

The JSON fixture path above is relative to the shared installer subtree. Both
independent sidecar requests failed before source access with encrypted-content
hydration errors; neither supplied review findings. No required static parser
was unavailable for the changed contracts. No fixtures, native validators,
offline AppArmor parser, services, package operations or installed helpers ran.

The original three Trixie desktop requirements remain incomplete. The accessible
[Debian Trixie Labwc listing](https://packages.debian.org/trixie/labwc), checked
2026-11-12, still lists version 0.8.3-1 with a required system `xwayland`
dependency. The [Forky listing](https://packages.debian.org/forky/labwc) lists
0.20.2-1 with `xwayland` suggested instead. Those are observed package metadata,
not installed versions or new native pins. Direct backports lookups and an
all-suites search page were inaccessible through the research tool; no qualified
Trixie backport was established and lookup failures are not proof of absence.
No foreign-suite fallback, source build or policy weakening was introduced.
Boot, disk preservation, solver, GUI, resource-pressure behavior, services,
firewall and hardware acceptance remain unverified.

The [operator publication/rollback procedure](operations.md#operator-publication-and-rollback)
still requires a separately authorized action. Review both generated frontends,
the complete local candidate, receipt, qualification gates and retained previous
tree first. Switch only the whole served-tree pointer and roll back to the
recorded previous complete tree identity; preserve immutable URLs needed by
in-flight installers and uncertain recovery journals. No pointer, deployment,
external enrollment, workflow, push, merge or disk state was changed here.

## 2026-11-12 crypto initramfs and cleanup handoff checkpoint

Continued from revision `ec5ef46d01c7bb96efb52129592a154c81a6a637` and the
previous local release `08b1aa52970e614a07f45e4b2185eb5546080bcdf166c97705559f98b26d1ca6`.
Preserved the staged removals, unrelated source work and desktop resource
implementation. The earlier ZIP/tree fingerprints remain historical audit
identities; the source/compiler fingerprint below identifies this working tree.

Reviewed independent root/home profile policy, the runtime/partman layout,
late crypto staging, initramfs build/unlock hooks, permanent enrollment helper,
selected-device native operation/recovery paths, console enrollment unit,
firstboot/secondboot cleanup, exact AppArmor consumers, source selectors,
canonical target paths, shared renderer and affected source fixtures.

Confirmed and repaired these source defects:

- Crypto image enumeration included detached `initrd.img-*.sig` signatures.
  Late installation now calls the permanent `tpm2-policy-check --initramfs`
  verifier, which excludes those signatures. Installation and reenrollment
  share one root/home-aware archive check rather than divergent implementations.
- The initrd hook accepted any one TSS library instead of requiring every
  family, and regular-file-only discovery could omit SONAME links. The hook
  independently requires ESYS, MU, RC, device TCTI and OpenSSL, passing package
  links and their regular targets to Debian's existing `copy_exec`. The archive
  verifier requires each loader name as well as the token plugin, root hook,
  configuration and native recovery fallback when root encryption is selected.
- Boot evidence ignored the durable cleanup-pending marker. It now checks that
  marker and the health hook before and after measured-boot reads. Cleanup keeps
  pending evidence through rebuild, verification and the durable boot stamp;
  enrollment requires another boot after that stamp. Metadata/access errors,
  dangling links and malformed stamp identities fail closed.
- Reenrollment without a bootstrap credential described the required existing
  recovery passphrase as new. The prompt now follows the actual recovery path,
  and a bootstrap symlink is rejected before requesting a secret. Boot-evidence
  and initramfs shell adapters preserve uncertain child result 76.

The shared verifier bounds discovery at 4,096 entries and 64 real images,
individual command output at 16 MiB, aggregate listing bytes at 32 MiB, encoded
member lines at 4 KiB, members at 100,000 per image and 200,000 aggregate.
It admits names incrementally rather than constructing an unbounded split list.
The 300-second common deadline covers command admission, parsing and final
metadata verification; individual native commands receive at most 120 seconds
and their remaining common budget, with separate bounded child cleanup. It
checks image and boot-directory metadata without treating read-induced atime
changes as writes. This is optimistic change detection on trusted target paths,
not a filesystem snapshot or protection against a malicious root writer.

Added canonical target files `FILE_FIRSTBOOT_INITRAMFS_CLEANUP_PENDING`,
`FILE_CRYPTO_BOOT_ARTIFACTS_CLEANED` and `FILE_TPM2_CRYPTROOT_CONFIG` to
`hosts/installer/runtime.env`, wired their existing shared publication-map
producers, and updated all affected target, installer and exact AppArmor
consumers. No second renderer or installed installer-only helper was added.
The human ownership ledger records ten source owners and is not used as
installer/checker policy. The obsolete shell-function archive fixture now
targets the actual permanent verifier with synthetic metadata and commands.
The related TPM fixtures use the current physical source, the required
inherited-device descriptor interface, and bounded private state instead of
creating completion-fixture state under the root account's home. Those fixture
authority and native-evidence interfaces remain explicitly mocked.

Upstream review used Forky-oriented interfaces, including
[systemd v262 TPM code](https://github.com/systemd/systemd/blob/v262/src/shared/tpm2-util.c),
[v262 PIN enrollment documentation](https://github.com/systemd/systemd/blob/v262/man/systemd-cryptenroll.xml),
and its [OpenSSL Argon2id implementation](https://github.com/systemd/systemd/blob/v262/src/shared/crypto-util.c).
The native [initramfs-tools 0.151 copy interface](https://sources.debian.org/src/initramfs-tools/0.151/hook-functions/)
and [archive-listing entrypoint](https://sources.debian.org/src/initramfs-tools/0.151/lsinitramfs/)
were inspected as primary source. Debian Sources labels that version Forky/Sid;
this is observed source metadata, not a target installed version or a new pin.
No Trixie systemd resource baseline replaced the Forky desktop contract, and
native Debian systemd/Python/package versions remain selected-suite candidates.

Commands and actual results:

- Standalone `python3 -I -B` scripts using only standard-library `ast.parse`,
  JSON parsing and hashes parsed the changed Python sources, checked 39 unique
  crypto fixture IDs and confirmed all four pure-generation compiler inputs
  remained identical to the previously reviewed release. No repository module
  or fixture was imported or executed by these source checks.
- `timeout 60s make build` exited 0 six times. The first two runs reproduced
  `0ca3eaf7c1d3b49e5fbd7e3947d36bbf051dcc017254e87b32ec87e83664e552`.
  The first mandatory static audit then exited 1 because the three new path
  tokens lacked real publication-map producers. That candidate is rejected
  for rollout. After wiring the shared map, generation produced
  `57699fe67f30290db153b9676b0346d05f50e2f28d24d3d52c2a2c7850bf259e`
  and its mandatory audit passed. The streaming-name bounds produced intermediate
  `7f446b264882b583cf59247af91f1a4b17e845cd8659a77606fc8b9c56bbd91a`.
  Both final runs reproduced the current `603871fcd01c8af03a4564ca8276be3107e9051ca2c992fb05270cb8075eabdc`.
- `timeout 120s python3 -B tools/post_change_check.py` passed for the final
  release: 241 changed regular files, 48 Python ASTs, 85 shell/ShellCheck and
  unbound-variable sources, 68 structured files, six changed AppArmor sources,
  2,185 current source identities, 178 frontend identities, 2,320 payload
  members, 302 actual path-placeholder producers and six trusted product pins.
  The new source checks cover one shared crypto verifier, five dynamic library
  families, the cleanup handoff and two uncertain-result adapters. Existing
  checks still cover 22 role combinations, fourteen individual suite/role plans,
  120 systemd drop-in roots, all desktop tiers, resource ownership, appearance,
  X11 exclusions, private Xwayland scope and package/asset ownership. These are
  static source/data checks, not executed behavioral cases.
- `git diff --check` and `git diff --cached --check` exited 0.
  `git ls-files -- d-i/debian/releases d-i/debian/publications` returned no
  tracked paths. `git check-ignore` confirmed both current generated roots.

Current SHA-256 identities:

```text
release           603871fcd01c8af03a4564ca8276be3107e9051ca2c992fb05270cb8075eabdc
source/compiler   5b40966b169b4d6bdd7d69d370b3425a732ae1776b174c0b01e93e6a6c6852ae
payload.tar.gz    da765f78db2377967bf9014c5869794777c7850360e02859f30173ee4daa58a4
payload.manifest  1f595ab2a9c1f14e8552eb8088acae01ecf65d811fbaff967e636dcc53acb37b
source.sh         9d5d1dc6e465a059b21f33e548a4384b38e566fd0579a1cc6e5533903ad54bb8
receipt.json      dc1d058525be4cf8af3442dc3be0f67e9108359eb37363094c4d8714f92abf5b
support-matrix    ff0b2a12aec48418f02ad6dc591db5463826187eb4ac1fa836a1f70f05ab782a
Forky preseed     66b14e0b607a2f9acfd092f6022bc7940bcea72bb453365d8b61c5386473b995
Trixie preseed    5b81c2397dcf84cdbd5a098fc97ed73151495498c9089b2338bff00e78056bff
```

Unexecuted source/fixture SHA-256 identities (paths relative to `d-i/debian/`):

```text
tests/fixtures/crypto-boot-contract.json               d7624d46cbac6cac8b0abba5cc2ee1903788544c99533ced90cf83eba5669c5e
tests/test_security_hardening_20260924.py               23d2cca5f48b1b38874fb8956aaca1e71390bd02b31938433bcdb966d614c499
hooks/target/usr/local/libexec/common/tpm2-policy-check  7b05beb8ea97ed01ad85f3b0146d7a834ce38f5388440dd010aa2f2e6728684b
```

The 39 failure-injection cases and guarded behavioral fixture remain
unexecuted. No required static tool was missing. Independent bounded crypto
sidecar requests failed before source access with encrypted-content hydration
errors and supplied no findings. The root agent performed source integration.
No offline AppArmor compiler, native validator, package operation, boot, TPM,
PIN, recovery, disk, service, GUI, network, policy loader or installed helper ran.

This checkpoint does not finish the overall implementation goal. Remaining
installer-phase identity/recovery and server artifact/lifecycle review must not
be inferred from the permanent verifier changes. The original three Trixie
desktop requirements still have the recorded native Labwc/system-Xwayland
dependency blocker; source plans do not turn them into qualified installations.
No foreign-suite fallback, package pin, source build or policy weakening was
introduced. The [operator procedure](operations.md#operator-publication-and-rollback)
still requires separately authorized whole-tree publication, retaining the
actual previously served tree identity and immutable URLs for in-flight installs.
Rollback uses that recorded complete tree, not a partial frontend or release
pointer. No publication, deployment, enrollment, workflow, push, merge or
repartitioning action was performed.

## 2026-11-12 Forky resource baseline and installer crypto identity checkpoint

Continued from revision `ec5ef46d01c7bb96efb52129592a154c81a6a637` and local
release `603871fcd01c8af03a4564ca8276be3107e9051ca2c992fb05270cb8075eabdc`.
Preserved existing staged removals and unrelated redesign work. The original
ZIP/tree fingerprints remain historical audit identities; the source/compiler
fingerprint below identifies the current installer inputs and serializer.

Rechecked the desktop resource design against upstream systemd **v262**:
[memory protection and limits](https://raw.githubusercontent.com/systemd/systemd/v262/man/systemd.resource-control.xml),
[scope invocation and argument expansion](https://raw.githubusercontent.com/systemd/systemd/v262/man/systemd-run.xml)
and [scope stop/kill property dispatch](https://raw.githubusercontent.com/systemd/systemd/v262/src/core/dbus-scope.c).
Forky remains the desktop design baseline. Session infrastructure, applications
and compilation retain separate session/app/build slices, ancestor memory
protection and bounded pressure/emergency zram work. No Trixie systemd resource
baseline or native package version pin was introduced. These source checks do
not establish actual cgroup placement, controller delegation or desktop latency.

Confirmed and repaired a remaining installer crypto boundary: temporary TPM
enrollment passed raw partition names after the initial storage identity checks.
The late stage now holds the private key and selected disk/partitions open,
rechecks the partman disk receipt and delegates native enrollment once to
`scripts/late/crypto-bootstrap.py.tmpl`. The existing private setup staging owner
removes that program on success and failure; it is never installed under the
persistent target asset tree. The target program checks block-device generation,
physical parent, partition slot, selected UUID and bootstrap unlock authority.
Native descriptor/LUKS2 probes run read-only before mutation and have no pathname
fallback. Descriptor rejection returns unavailable status 69.

The temporary program captures the existing root-owned maintenance helper as
trusted code bytes and reuses its native command, pidfd, bounded cleanup, secret
input, state-publication and enrollment-lock primitives. Native work has a
600-second common deadline, 32 MiB aggregate output budget and per-command bounds.
The initial read-only UUID queries use target coreutils with a 30-second timeout
and five-second forced-cleanup allowance. No additional late d-i interpreter or
GNU tool availability is assumed. The inherited-handle bridge and target native
interfaces remain unexecuted; read-only compatibility probes are an installation
gate, not acceptance evidence from this checkout.

Before sealing or keyslot changes, a durable private transaction records the
selected devices and original metadata. Sealed-credential publication refuses
another owner. Each temporary token must be the sole SHA-256 PCR-7 token, keep
the original bootstrap slot, unlock without a passphrase fallback and preserve
the original random-key unlock. Automatic public-key/PCR-lock additions are
disabled for this temporary policy. Only a same-boot verified receipt with exact
device/metadata matches can resume through read-only verification. Interrupted,
malformed, changed-device or unverified state returns 76 and retains recovery
evidence without automatic retry. Writer and readers enforce a 1 MiB transaction
bound. No plaintext key is written into the target filesystem.

The permanent enrollment helper consumes the verified exact-volume transaction
before configuration export, maintenance or release. Its existing AppArmor
consumers receive exact read rules for that file. The shell adapter preserves
uncertain status for configuration, generation and release operations; the
configuration producer is now captured before its here-document is consumed,
so substitution cannot hide a failed producer. This readiness gate does not
replace the later native metadata, PIN, recovery, measured-boot and separate-boot
confirmation gates.

`FILE_INSTALLER_SELECTED_DISK_IDENTITY` in `hooks/installer/di.env` now owns the
disk receipt. Updated its bootstrap requirement, original producer, both partman
consumers and late crypto caller. `FILE_CRYPTO_BOOTSTRAP_TRANSACTION` in the target
path contract owns persistent crypto recovery evidence and has a real shared
placeholder-map producer. `repo.env` owns the temporary program selector. The
human ownership ledger records sixteen reviewed source owners; it is not used
as installer/checker policy. Added 37 unexecuted failure-injection source cases
and two mocked permanent-handoff fixture methods. No fixture was executed.

Primary source review also covered the
[cryptsetup 2.8.8 device-path backend](https://gitlab.com/cryptsetup/cryptsetup/-/raw/v2.8.8/lib/utils_device.c),
[systemd v262 enrollment entrypoint](https://raw.githubusercontent.com/systemd/systemd/v262/src/cryptenroll/cryptenroll.c),
[v262 lexical path argument handling](https://raw.githubusercontent.com/systemd/systemd/v262/src/shared/parse-argument.c),
and Debian Installer's
[in-target](https://sources.debian.org/src/debian-installer-utils/1.155/in-target/),
[chroot setup](https://sources.debian.org/src/debian-installer-utils/1.155/chroot-setup.sh)
and [logging bridge](https://sources.debian.org/src/debian-installer-utils/1.155/log-output.c/).
These are reviewed source versions, not installed target versions or pins.
Salsa raw URLs and the libdebian-installer exec implementation were inaccessible
through the research tool; no claim of complete native bridge acceptance follows.
The independent resource sidecar failed before source access with an encrypted
content hydration error and supplied no findings. Integration remained local.

Commands and actual results:

- Standard-library-only `python3 -I -B` stdin scripts parsed the affected Python
  ASTs, JSON and source-case identifiers, calculated SHA-256 identities, and
  confirmed all four generation compiler inputs still match the previously
  reviewed sources. They imported or executed no repository module or fixture.
- `timeout 60s make build` exited 0 five times. Intermediate candidates were
  `fc564e4b84bf79ac94fb8b09741a88656fc8a4846aaea371b6c29ac0f62f0c4e`,
  `845410df2e8d69a749d0214a2dfb1cb80ea40a1ceef254ae7b7fbe6a0460f051`
  and `c65af9524bbe54c479c9f8f710ebb5b09071cdab4d94eb4750dde27e60bdf517`.
  Both final unchanged-input runs reproduced
  `5530b46fa703c4944369f0d274c6f94d066e443c28c057a64a3132c91c6dc3a7`.
  The complete candidates remain local and ignored.
- `timeout 120s python3 -B tools/post_change_check.py` passed for the first
  candidate and the final release. The final audit covers 247 changed regular
  files, 49 Python ASTs, 89 shell/ShellCheck and unbound-variable inputs, 69
  structured files, six changed AppArmor sources, 2,186 current source identities,
  178 frontend identities, 2,321 archive members, 303 actual path-placeholder
  producers, twelve installation-only source programs and six trusted pins.
  New source checks cover three installer device bindings, the bootstrap
  transaction and its permanent handoff. Existing checks still cover 22 role
  combinations, fourteen individual suite/role plans, 120 systemd drop-in roots,
  all desktop tiers, three slice contracts, three memory ancestors, pressure
  envelopes, nine appearance components, 567 appearance fields and 672 mappings.
  These counts describe static contracts and source plans, not passing native
  installations or executed behavioral cases.
- `git diff --check` and `git diff --cached --check` exited 0.
  `git ls-files -- d-i/debian/releases d-i/debian/publications` returned no paths.
  `git check-ignore --` with both final generated roots confirmed that each is
  ignored. Revision remained unchanged.

Current SHA-256 identities:

```text
release           5530b46fa703c4944369f0d274c6f94d066e443c28c057a64a3132c91c6dc3a7
source/compiler   677c57184172a5c603a250ad6be690235a2fdce355fc71023a1a02ab3ce740e3
payload.tar.gz    8557041153495dcc06bb714133e6ab57ec8e722da1ced4e4c3caa1d887d8a8ff
payload.manifest  cd0f3babebb1169d38ea386ec60f3b0aeb376862d17b2a89181039432f40d45b
source.sh         9d5d1dc6e465a059b21f33e548a4384b38e566fd0579a1cc6e5533903ad54bb8
receipt.json      59df575ba13ae5ace5554fd0d37693f9c262eb6435bfda10843d721fe4d2302a
support-matrix    ff0b2a12aec48418f02ad6dc591db5463826187eb4ac1fa836a1f70f05ab782a
Forky preseed     47b92c29a01dea1ce10a4ec868dd4ce677ddcb0f45b5b17526f128053ae64380
Trixie preseed    82ac3eb4262efa305defd44f201d57fd2ed325cb4d6f2dac99f3bf220dd83c09
```

Source/fixture identities (relative to the shared installer subtree):

```text
scripts/late/crypto-bootstrap.py.tmpl                   1eb6a522d526c348395d0a4d9e3444bd5ae3a790be2e1a3a58af413cc4a566ae
hooks/target/usr/local/libexec/common/tpm2-policy-check  d3a5fb58916aaea0d6e9d7c38723ffefda332b7379f237a69a4aefff86a0d605
tests/fixtures/crypto-bootstrap-contract.json          9b094d3045ccc5b50f65719baa0b5957af4bf5cded7095cceb39e38694bb7092
tests/test_security_hardening_20260924.py               9d3162e4669c99f9d2b582b5448ef1b53021928f566942e338851d6fce1d7261
```

No required static parser was unavailable. No tests, managed imports, native
validators, offline AppArmor compiler, package operations, services, TPM/PIN,
disk mutation, installer, GUI, networking, policy loader or installed management
helper ran. The resource, crypto, archive and service contracts therefore retain
their native verification limits.

The broader implementation goal remains incomplete. Further storage/installer
identity and server artifact/lifecycle review must not be inferred from this
late-stage handoff. Three original Trixie desktop requirements still have the
native Labwc dependency blocker: on this check Debian lists
[Trixie Labwc 0.8.3-1](https://packages.debian.org/trixie/labwc) with required
system `xwayland`; [Forky Labwc 0.20.3-1](https://packages.debian.org/forky/labwc)
does not have that required dependency. These are observed package metadata,
not pins or solver results. No qualified Trixie alternative has been established.
No foreign-suite fallback, source build or weakened X11 policy was introduced.

The [operator procedure](operations.md#operator-publication-and-rollback) still
requires separate authorization. Review the complete local candidate, both
matching frontends, receipt and qualification gates first. Record the actual
previously served complete tree and switch only one complete pointer. Retain
that tree, its immutable URLs and recovery journal for rollback and in-flight
installers. No pointer tool, publication, deployment, enrollment, workflow,
push, merge or repartitioning action was performed.


## 2026-11-12 13:17 UTC — fatal class selection, flat products and private service setup

This checkpoint supersedes the earlier local release/publication layout. The
current source revision is `ec5ef46d01c7bb96efb52129592a154c81a6a637`, with
existing staged and unstaged work preserved. The captured source/compiler
fingerprint below identifies the current dirty implementation, not an invented
archive revision. It differs from the original audited tree; changes were
traced through the current owning source and callers.

The supplied installation stopped in `prepare-context`, before partitioning or
package selection. Its fatal diagnostic was `class selection has forbidden
characters`. The raw alphabet omitted the hyphen required by registered names,
including `btrfs-de-p15s`, `nvidia-legacy` and `cuda-legacy`. The incoming boot
value also used unique bare filenames. The ingress now permits the hyphen and
resolves a bare filename only against captured registered class records; no
input-derived filename probing or retired-class alias table is used. Internal
and persisted references are canonical. Unknown/ambiguous names, duplicates,
empty selectors, traversal and excessive input still fail. Hardware-detection,
normalization, context and cache-publication failures propagate before later
work. Unused implicit-class and bare-predicate bridges were removed.

The boot input's non-secret class value maps to:

```text
site/prod;role/desktop/full;network/static;profile/desktop/btrfs-de-p15s;optional/nvidia-legacy;optional/cuda-legacy
```

The log inputs remained unchanged through final review:

```text
todo/syslog         f2dff7f014dcdf2a91a16e28e2de324ce212be5e66a0fca52d746310823f47df
todo/installer.log  9dad8b3304fa6d67bf99b0f0989b9ff7d5d169191d0ad012f588280ed2e220bf
```

The code defect is repaired and regenerated. No installer replay was permitted
or attempted, so successful boot or completion of the installation is not
claimed. The later USB FAT warning is not the recorded preflight failure; no
host filesystem repair was attempted.

Current ownership and behavior:

- `TIMESHIFT_ENABLE` in each of thirteen concrete host profiles is the sole
  Timeshift switch. There is no Timeshift class. The conditional suite package
  fragment owns the package and one shared stage. False omits its modules,
  configuration, policies, helpers, timers and GRUB-Btrfs integration. True
  retains the selected amd64/Btrfs identity checks and host retention/calendar
  policy. Server defaults retain two weekly and one monthly snapshot, with no
  daily timer. Manual desktop snapshots use the existing managed lock/command
  owner; the unavailable action is hidden when disabled. The notification shim
  is common to both families, with the source selectors and human ledger fixed.
- Initial runner artifacts, accounts and private configuration belong to
  `scripts/server/setup.py.tmpl`, staged temporarily by the installer. The
  persistent controller cannot install or enroll runners. Tokens come only from
  the actual initrd `/preseed.env`; public provider URLs and image/cache policy
  belong to `server/shared-srv.env`. GitHub scope is
  `https://github.com/mjcramerz`. Missing enrollment stays pending. Native
  registration uncertainty is retained without retry or an online claim.
- Runner job toolchains belong to workflow-selected Debian-derived images.
  Default GitLab jobs use the selected suite's pinned Debian slim reference and
  `if-not-present`. The explicit version-matched helper uses GitLab's supported
  Debian-derived Ubuntu flavor, never Alpine. Its public image reference and
  flavor live in the shared profile. Desktop Podman examples now use Debian
  slim as well. GitHub retains its native container-pull semantics; no invented
  equivalent of GitLab's setting is claimed. Custom images own their dependency
  and UID/cache compatibility requirements.
- Provider build/cache/tmp data and rootless stores remain separate on `/pool`.
  Bazel/BuildBuddy endpoints are public profile policy; workflow secrets own
  job API credentials. GitHub's native job hook publishes container cache
  environment and its HOME Bazel configuration. GitLab receives only its own
  mounts. Its native configuration now uses `FILE_SERVER_GITLAB_CONFIG` inside
  its private writable config directory, allowing the native manager-ID and
  token-rotation writes while root-owned receipts remain outside that directory.
  Enrollment additionally requires bounded authenticated 200 JSON acknowledgement
  bound to the native manager ID; CLI exit zero alone is insufficient. Private
  token bodies use stdin/HTTPS, never argv, query strings, redirects or logs.
- All six requested Technitium private fields are consumed from the initrd.
  The designated locked nologin service identity is distinct from the primary
  SSH account. Optional OS hashing uses private native stdin; web, TLS and backup
  credentials remain distinct. Private authenticated native web setup has an
  uncertainty journal and root-private Unix proxy, with no host TCP management
  listener. Missing web credentials or certificate material stays explicit.
  Format-3 backup archives use fixed Scrypt/AES-256-GCM, authenticate before tar
  parsing/restoration, exclude the backup key/socket and retain the current key
  across credential-directory replacement. Incus/pool snapshots retain the
  filesystem's separate encryption policy. None of these operations ran here.
- `make build` overwrites exactly the five flat products plus `preseed.cfg` in
  each suite, under one nonblocking existing-directory ownership lock. It creates
  no release/publication directories or lock file. Suite products are visible
  to Git. Obsolete shared generated output was removed only after validating
  its receipt-selected membership, regular-file types, ownership and inode
  identities: 11,024 files, 1,415,204,381 bytes and 4,074 directories. Two old
  manifests differed from their old receipts (four copies across old roots);
  those obsolete outputs were discarded with the rest. No authored input or
  external served tree was deleted. Retired shared output roots remain ignored
  solely to prevent accidental reintroduction.
- The manual pointer tool captures the exact flat product/frontend set and
  retains complete external served trees for rollback. It is never run by the
  build, installer or static audit, and was not executed here, including preview.
  The ownership ledger remains human documentation, without installer/checker
  policy authority. Active docs, source fixtures and build allowances now follow
  the flat output contract; historical checkpoints retain their recorded history.

Actual permitted verification:

- `timeout 120s make build` exited 0 for all five generation runs in this
  continuation. Intermediate source identities were
  `6e850d760f0a3a13f4839ceba64bf80b8dc540fb221a1bd8833c0913f51879f4`,
  `2485f234e6821e1459f4133526d6bc0954836abbf9f6db9bae80c94439a960a1`,
  `2901027bdd9ad0b2094f1b6f7e33d7d0d17b8b5aa68360da0834d686ed3e25f1`
  and `0337efe7f1f87dfcb5ecce6a1ad40c220fa012e7971b7bc0f507124c32476d67`.
  Only the final source identity below is current.
- `timeout 120s python3 -B tools/post_change_check.py` passed after each
  generation. The final implementation audit covered 283 changed regular files,
  53 Python ASTs, 99 shell/ShellCheck/unbound-variable inputs, 78 structured files,
  six changed AppArmor structures, 316 actual path-placeholder producers, 2,189
  current source identities, 180 frontend identities, 2,324 payload members and
  six trusted preseed product pins. It also checked thirteen Timeshift booleans,
  both conditional package fragments, two installer-only runner providers and
  protected capture equivalence across five shared server functions. A final
  documentation-inclusive audit uses the same required command.
- Standard-library-only `python3 -B` stdin checks parsed eight Python sources,
  reviewed three server symbol tables without unbound global candidates, checked
  JSON/unique fixture IDs, compared the five generated products byte-for-byte
  across suites, hashed the products/fixtures/logs, and inspected archive registry
  data. All six expected references from the logged class input exist in that
  registry. These are source/data comparisons, not parser fixture execution.
- `git diff --check` and `git diff --cached --check` exited 0.
  `git check-ignore -- d-i/forky/payload.tar.gz d-i/trixie/payload.tar.gz
  d-i/forky/receipt.json d-i/trixie/receipt.json` returned 1 without output,
  confirming these products are not ignored. Both retired shared roots, both
  suite release directories and `d-i/trixie-server` are absent.

Current SHA-256 identities (the five products are identical in both suites):

```text
source identity   4b7a77197ab17f941f2ea72bd891f84dd1fbf372bb6872d1bb4df7f11fbc52a9
source/compiler   d42c2b98943fc4f6b9ca1b86f4ba80c6eba2efdf5e626489429356841ab09436
payload.tar.gz    68ba3bc38680b884c5d0ea5118229365a72d148f287f289c591d59737ddcd0a0
payload.manifest  6e9f7ba52dd3d04ebd6e13aeb10209fe07d0532f7ab34cce809596624d0692ea
source.sh         7efc6b68235d7a0108030a7b75ed6a77bd30c1624c620ae4841577375d748efe
receipt.json      1b9a0ff0e74f8b5ce7f972d7c013d4880a62778c9e34b1b500559c57b3510a70
support-matrix    ff0b2a12aec48418f02ad6dc591db5463826187eb4ac1fa836a1f70f05ab782a
Forky preseed     45f628a9b87fe147f7453121590762d38395a7ffb0ad812591a5214bf449132d
Trixie preseed    2c040b06b31b4fd5be4c5d444673e59ad2c81e081c617bffc91bb2094cbceddf
```

Unexecuted source/failure-injection fixtures (114 cases in these five files):

```text
class-parser-failures.json       14  60090f229e0616639c177b774d4a8921778a719fef29f55d3033c564e003dfa8
timeshift-profile-policy.json    12  f09ca875dadc0caaa04e7621e76a65223844c20665f32f30fc40140de93eb7ed
runner-installation-policy.json  18  9bdeece466f128c39583f9bb00bc00bbc838c369512c1d128dbbef8e305b97ea
technitium-incus-contract.json   43  2ae1bc69b434dc7306152a69677f987d0ac6f30cb8e4f9d7bea569c98f24cef7
immutable-publication.json       27  2f32233458462649cdfd4e27df64da3d250cadf564e5f8240c74e1165322f571
```

No required static parser was unavailable. Independent sidecars repeatedly
failed encrypted-context hydration before source access; they supplied no
findings or independent approval. Integration/review remained with the root
owner. No tests, fixtures, managed imports, Perl BEGIN blocks, offline AppArmor
compiler, native policy loader, package operation, service, container, VM,
chroot, host networking/storage, enrollment, workflow, deployment, push, merge
or repartitioning operation was executed. Container image references were not
pulled or booted; no target package/service versions are claimed as installed.

The broader original requirement is still incomplete for three Trixie desktop
roles: current Debian metadata lists
[Trixie Labwc 0.8.3-1](https://packages.debian.org/trixie/labwc) with a required
system `xwayland` dependency; the required X11 exclusion conflicts with it.
[Forky Labwc 0.20.3-1](https://packages.debian.org/forky/labwc) does not require
that package. These metadata were rechecked on 2026-11-12; they are observations,
not native package pins or solver results. The generated matrix contains all
22 compatible role-selection source plans and fourteen individual suite/role
plans, including explicit qualification blockers. No foreign-suite fallback,
source build, replacement polkit agent or weakened X11 policy was introduced.
Additional architecture/dualboot/hardware tuples remain deliberately unqualified.

Operator rollout must finish/stop active acquisition before a flat served-tree
switch. Review both suite preseeds, products, receipts and qualification gates;
then follow the separate manual procedure in [operations](operations.md).
Retain the previous complete external served tree and transaction journal for
rollback. Old in-flight preseed pins reject new mixed bytes; a complete local
snapshot keeps using its bound bytes. A pointer rollback changes future
acquisition only and cannot undo target disk, account, package or provider state.
No manual pointer command, including preview, was run in this coding task.

## 2026-11-12 13:45 UTC — desktop firstboot ownership and ordinary build storage

Continued in the actual `mcr/main` checkout at
`ec5ef46d01c7bb96efb52129592a154c81a6a637`, preserving the pre-existing
staged/unstaged redesign. Re-read the attached objective, current guidance,
isolation boundary and relevant plan/desktop/installer callers. The previous
goal turn made concrete progress on the fatal class parser, flat serialization
and private service setup; this continuation adds the desktop repairs below.
Two read-only sidecar reviews were attempted with no inherited conversation.
Both failed encrypted-context hydration before reading source, supplied no
findings and made no changes. Integration and source review remained here.

### Implemented contracts and ownership

- `labwc-build` already separated builds from desktop/app slices, but ordinary
  aliases did not apply the pool scratch policy until a DevOps shell was
  activated. It now resolves the native non-root account instead of trusting
  `USER`, requires a mounted pool and direct installed directories, checks the
  account root/private scratch ownership and modes, and publishes canonical
  `TMPDIR`, `TMP`, `TEMP`, `GOTMPDIR` and Cargo target output before either the
  new-scope or nested-scope path. It creates no replacement store and performs
  no chmod/chown repair. Argv, cwd, terminal and toolchain selection remain
  with the invoking build. Arbitrary Makefile output still requires a pool
  workspace or its explicit supported output option; the launcher does not
  silently move a checkout or promise to rewrite arbitrary build semantics.
- The desktop pool tmpfiles policy provisions the primary account's build
  scratch directory as mode 0700. Its existing directory normalizer applies
  the declaration during installation. The all-tier offline desktop metadata
  gate now checks build storage, the launcher, build slice and memory ancestry
  files before activation. This is authored target verification, not an
  invocation of that gate in this coding task.
- PipeWire greeter-exclusion staging now uses the existing registered unit
  map. Offline and firstboot verification use the same four canonical runtime
  drop-in placeholders. Negative audio-session checks also use those
  placeholders. There is no new target path renderer or installed wrapper.
- Firstboot's broad desktop inventory still required files that base's
  installer deliberately omits: AI, Android, container-menu, benchmark and
  related account service assets. Firstboot now parses the format-2 class
  receipt as bounded data, requiring one matching desktop role/class and
  family, exact root-owned regular-file metadata, a 256 KiB file bound,
  4,096-record bound and 4,096-character record bound. Missing, malformed,
  mixed, duplicate or mismatched class identity records a failure rather than
  inferring a role from file presence.
- For base, the corresponding 16 authored specialist path patterns are checked
  for absence, including dangling links; excluded command presence is a
  failure. Medium/full retain required-presence checks. Common session,
  calendar, appearance and Waybar files remain required for every desktop.
  The ownership remains physical desktop classes, their shared installer
  staging, and the published class receipt; class comments are not inputs.
- Firstboot no longer assumes that an installed Whisper service file means
  the profile enabled a persistent server. It requires the copied account
  enablement only when the root-owned skeleton stages that link, rejects
  dangling/missing copies, and otherwise requires the account link absent.
- The changed-file audit now detects dynamic global unit-directory
  reconstruction as well as fixed spellings. Its only native-instance
  allowance is four exact negative assertions for numeric-UID systemd
  instance names in firstboot. Assignments, staging calls, other paths or
  commands do not match that allowance. These assertions install nothing.
  The human desktop ownership review and resource documentation were updated;
  neither is an installed-system policy input.

The firstboot AppArmor profile already covers the installer-state receipt and
the native readers used here; no policy permission was broadened. The shared
desktop/session, application network confinement, managed module inventory,
native Waybar types and exact private Zoom/Discord boundary were retained.

### Current flat products

`timeout 120s make build` ran twice, both exit 0. The first intermediate source
identity was `fb2db872f1a763cf144b3fb12e0cc6a22ca6ef68ff6f980f8f197018e8e8b270`.
The second incorporates the additional firstboot repairs and is current:

```text
source identity    b84ff3ab461daf1fff5cc870c2d51eec6d8b08ec615ae57bf9c2864fcca2f027
source fingerprint 5104102dc55c4323e83144fc9ccbaa67c6e2c5af710c83797d1d882470a5df18
payload.tar.gz     d0e6bfca833a7ff01d8c1fe2114d18e7ae32bfa49e4b4d718702e92a3ab3dfd7
payload.manifest   d2c7b479ca2edb4217882928a36efd6fbc0fe7f300c06df38dc33eed86241716
source.sh          7efc6b68235d7a0108030a7b75ed6a77bd30c1624c620ae4841577375d748efe
receipt.json       68945eaf2d01f1c734796ae160d3e3a4c5fd248cf52d1bb53ccc3b5545f6f63d
support-matrix     ff0b2a12aec48418f02ad6dc591db5463826187eb4ac1fa836a1f70f05ab782a
Forky preseed      1c22a2760d3732a94d354c206bcefb4263008837ec5fcdbc8c99b00b1bbd50d3
Trixie preseed     960c5af8d90e99976ec2108fed0e6a26dba5c6ad7d03a629fc56dbd6103a46a1
```

The five payload products are byte-identical in both suite roots; the preseeds
retain distinct suite identities and pins. All products are regular files,
with 2,324 payload members, 2,189 current source inputs and 180 frontend
identities. A data-only existence check reconfirmed that both retired shared
generated roots, both suite release directories and `trixie-server` are absent.
The flat product ignore check below returned 1 with no output, as expected.

### Actual static evidence

- `timeout 120s python3 -B tools/post_change_check.py`: first run exited 1
  because the expanded dynamic drop-in guard found the additional firstboot
  consumers. They were repaired, with the exact negative native-instance
  assertions retained as described above. After rebuilding, the command
  exited 0 and reported **PASS**.
- That successful audit inspected 286 changed existing regular files,
  parsed 53 Python sources, checked 101 shell sources with syntax/ShellCheck
  and unbound-variable checks, and parsed 78 structured files. It also checked
  six changed AppArmor structures, 316 runtime placeholder producers, 120
  canonical drop-in directories, 16 firstboot absence patterns and the
  selected-class receipt/build-pool contracts. No required parser was reported
  unavailable.
- Current source/member equality: 2,189; frontend equality: 180; archive
  membership: 2,324; trusted preseed product pins: six. Matrix checks covered
  22 role-combination source plans and fourteen individual suite/role plans,
  including explicit qualification blockers. These are not native acceptance
  results.
- Appearance checks remained at 567 fields and 672 mappings across nine
  desktop components. Timeshift remained profile-only with thirteen concrete
  booleans and two conditional suite fragments. Runner installation-only
  ownership and all six Technitium private-field contracts remained covered.
- `git diff --check`: exit 0. `git diff --cached --check`: exit 0.
- `git check-ignore -- d-i/forky/payload.tar.gz d-i/trixie/payload.tar.gz
  d-i/forky/receipt.json d-i/trixie/receipt.json`: exit 1, no output;
  the required flat products are not ignored.
- Additional `python3 -I -B -` stdin programs used standard-library AST,
  symbol-table, JSON, source-pattern and SHA-256 processing only. They parsed
  the changed audit source and embedded desktop metadata Python, inspected
  its new bindings, checked fixture ID uniqueness and collected the exact
  receipt/product/fixture identities. No managed module was imported.

The two updated behavioral fixture documents contain 48 cases, all
**unexecuted**:

```text
desktop-resource-isolation.json  25 cases
2d64f444907c7b2391ebcb4acdd25e2fbb5c7ff35de314c31cc4ac40c7f50c7e
desktop-tier-installation.json   23 cases
5c4d41cd1b42bd433029e7b697cdb9e7b2e71b8408a79ba4ecbded61d2b9af71
```

No tests, fixtures, installer hooks, firstboot programs, build launcher,
package solver, service, user manager, firewall, hardware, container, VM,
chroot, policy loader or installed management helper was executed. No offline
AppArmor compilation was needed for this continuation. There was no push,
merge, deployment, external enrollment, workflow, manual pointer operation or
disk operation.

### Remaining limits and operator boundary

The broad goal remains active and native acceptance remains unverified.
The three required native Trixie desktop installations remain incomplete:
the official [Trixie Labwc metadata](https://packages.debian.org/trixie/labwc)
still lists 0.8.3-1 with a required system `xwayland` dependency, while
[Forky Labwc](https://packages.debian.org/forky/labwc) lists 0.20.3-1 without
that required package. Both pages were rechecked on 2026-11-12 during this
continuation. Those observations are not native package version pins. No
foreign-suite package, source build, alternate polkit agent or weakened X11
exclusion was introduced.

Operator rollout and rollback remain the manual procedure in
[operations](operations.md). Review both suite preseeds and receipts together,
finish/drain active acquisition before a complete external served-tree switch,
and retain the previous complete external tree plus journal. Old preseed pins
reject mixed flat-product bytes. Pointer rollback changes future acquisition;
it cannot undo target storage, account, package or provider state. No rollout
command was run here.
## 2026-11-12 scheduler, runner policy, and shared-profile checkpoint

The concrete desktop and server profiles now own
`HARDWARE_CPU_SCHEDULER_SCX_ENABLE`, `HARDWARE_CPU_SCHEDULER_SCX_MODE`,
`HARDWARE_CPU_SCHEDULER_SCX_WORKER_NORMAL`, and
`HARDWARE_CPU_SCHEDULER_SCX_WORKER_PERFORMANCE`. The family shared files no
longer define those selections. Shared policy owns only the pinned sched_ext
artifact hosts, bounds, URLs, and digests. The common profile file now owns
the network-sharing defaults and Fangfrisch defaults. Server profiles own
explicit `ci-github`, `ci-gitlab`, and `srv-devops` Podman identities and a
high-throughput runner budget (`CPUWeight=1000`, `IOWeight=1000`,
`TasksMax=65536`, `MemoryHigh=90%`, `MemoryMax=98%`).

The installer renders the profile-selected normal worker into the installed
SCX defaults and loader configuration. Desktop DevOps entry switches to the
profile-selected performance worker. Runner service start/stop stages use the
runtime handoff helper to request the performance/normal worker transition;
the helper is best-effort and never prevents a runner from starting when the
SCX loader is unavailable. No scheduler service, D-Bus manager, package state,
or host policy was contacted during this work.

Static evidence for this checkpoint:

```text
timeout 120s make build
  built source identity ea3adc17ac763f9b2e94e6a50877e1d73154fee1fb76c8b263237a46168fe693 members=2343
  suite products: d-i/{forky,trixie}/{payload.tar.gz,payload.manifest,source.sh,receipt.json,support-matrix.json}
  flat product hashes:
    payload.tar.gz 1c355e4e7eed0adbb6c37d789c9a0e1fff6ee31c8f1b61a6b0a7ebc03bfd75c7 (both suites)
    payload.manifest 10d32c0eb3cae74d0ec78619bcac537a8fd790f9f0e465a3d013c113b52d83b5 (both suites)
    source.sh b789131ba59b74e266b9a1e4317b17b7efde58930b10ffac54c1595b3a5736e9 (both suites)
    receipt.json 20bdd92f8214e7394c09ed2888738da6f65cfa94ff5160561f3cba44ee0a0e44 (both suites)
    support-matrix.json ff0b2a12aec48418f02ad6dc591db5463826187eb4ac1fa836a1f70f05ab782a (both suites)
    Forky preseed e471b3c05efd60a57c12aaf8757ee7b4171053c62db275e579c530ef5c2f7207
    Trixie preseed 66ab48639a03792959fb66120a939a3fbdff50f9a550b9f64feb29616321b790

timeout 120s python3 -B tools/post_change_check.py
  post-change static audit: PASS
  changed_files=118, current_release_members=2343,
  current_release_source_equality=2208, current_release_frontend_equality=186,
  shell_sources=58, python_ast=12, structured_files=28

python3 -B stdin AST/data check
  tools/class_compiler.py, tools/source_layout.py,
  tools/post_change_check.py, and d-i/debian/scripts/server/setup.py.tmpl: AST OK
  all 14 concrete profiles: four explicit SCX selection variables present
  shared-de.env/shared-srv.env: zero SCX selection variables
  three concrete server profiles: explicit Podman identities and runner budgets present

/usr/bin/git diff --check
  exit 0
```

The first build attempt stopped before serialization because the newly moved
network-sharing default was below NFS variables that referenced it; the shared
file was reordered and the successful build above was then generated. No test
runner, fixture, installer hook, firstboot program, package solver, service,
container, VM, chroot, AppArmor loader, hardware path, or native management
helper was executed. The generated products remain flat under each suite root;
no release or publication directories were created.

## 2026-11-12 shared journal, server Podman, and runner-scope checkpoint

The nine `SYSTEMD_JOURNAL_*` defaults are now authored once in each family
shared environment (`desktop/shared-de.env` and `server/shared-srv.env`). The
thirteen shipped concrete profiles contain no copied journal assignments; a
future operator may add a same-name assignment as an explicit override.

The complete server Podman policy is authored in `server/shared-srv.env`,
including the locked `ci-github`, `ci-gitlab`, and `srv-devops` identities,
runner budgets, provider storage drivers, and graphroots/image-transfer scratch
under `/pool/podman`. Concrete server profiles contain none of those policy
assignments. Runner service `User`/`Group`, `RequiresMountsFor`, and
`ReadWritePaths` are rendered from the shared profile values. The server
DevOps operator configuration and shell fragment use `/pool/podman` for
persistent container configuration and stores; compilation remains under the
separate `/pool/build` tree. The desktop Podman provisioner is skipped for
headless server roles.

GitHub/GitLab runner administration is server-only. The desktop skeleton no
longer stages a runner control profile or runner scheduler helper; the server
skeleton retains `72-ci-runners-srv.sh`, and the server foundation stages the
bounded `ci-runners` command and its private primary-UID policy.

Static evidence for this checkpoint:

```text
git rev-parse HEAD
  1bae5011559928e73028fbe238d9ed1d41c3ef8e

timeout 120s make build
  built source identity 1e467c6c533a54e3ab88db73f37989bb7cd5f655255d9ad9f15b1db49faaac1
  members=2342
  suite products: d-i/{forky,trixie}/{payload.tar.gz,payload.manifest,source.sh,receipt.json,support-matrix.json}
  payload.tar.gz 3334b7ecaa30a15c702131d80794f94b208da9d9d61ea2c44e1ee4162e27ebd0 (both suites)
  payload.manifest 5c46fa474546dbf022bcf2b669e16baa209ac8b4760b7e8ebfab0bd45e905a3a (both suites)
  source.sh b789131ba59b74e266b9a1e4317b17b7efde58930b10ffac54c1595b3a5736e9 (both suites)
  receipt.json 4ab3c7d0998d57a06d6dc74e9ff2cd9aafc718ae19fa39764e89aa864914976b (both suites)
  support-matrix.json ff0b2a12aec48418f02ad6dc591db5463826187eb4ac1fa836a1f70f05ab782a (both suites)
  Forky/Trixie preseed products were regenerated by the same build.

timeout 120s python3 -B tools/post_change_check.py
  post-change static audit: PASS
  changed_files=119, current_release_members=2342,
  current_release_source_equality=2207, current_release_frontend_equality=186,
  server_podman_shared_policy=31, shell_sources=57, python_ast=14,
  structured_files=28

Static archive inspection
  both payloads contain server/72-ci-runners-srv.sh and
  usr/local/bin/server/ci-runners
  assets; neither contains a desktop 72-ci-runners.sh profile.

Unexecuted limits
  No test runner, fixture, installer hook, package solver, service, user
  manager, firewall, hardware path, container, VM, chroot, AppArmor loader,
  native management helper, or external runner enrollment was executed.
```

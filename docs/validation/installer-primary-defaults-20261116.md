# Private future-account templates and primary HOME publication

Recorded 2026-11-16. Base revision: `344bfdb78ce57cf2441e2fb3f4062bce43a074c2`.
The working tree contains the changes described here; no commit or deployment
was made. The generated receipt binds the payload inputs separately from this
validation record and the source fixtures.

## Reported failure and accepted behavior

The reported DevOps stage tried to run `install` as the primary account with
the installed desktop skeleton's yt-dlp configuration as its input. The Codex
staging code had already made the skeleton's configuration directory private
to root. The account therefore could not traverse that input pathname. Bazel
had the same unprivileged source-access dependency; Packer also copied its
primary configuration from the installed skeleton.

Both role skeleton roots must be root:root, mode 0700. They are reusable
templates for privileged creation of future accounts. Primary-account defaults
come from authenticated, rendered payload inputs. Installed applications,
wrappers, Python modules and Perl modules must not reference either private
skeleton. Primary HOME and its published contents belong to the account's
actual target UID and primary GID.

No installation log files were present at the supplied todo paths during this
task. The diagnosis above is established from the reported error and its source
call chain; it is not a replay of a logged installation.

## Publication and ownership

- The three shared publication boundaries retain an independent, root-private
  rendered payload input when publishing a future-account default. The d-i
  environment owns this temporary staging location. No repository selectors or
  staging paths are installed as runtime application configuration.
- The installation-only primary publisher uses descriptor-relative I/O. It
  checks the passwd identity and canonical HOME, rejects indirect or unsafe
  source/destination entries, and assigns each candidate file its account UID,
  GID and private mode before atomic publication. Executable defaults receive
  mode 0700; other files receive mode 0600. HOME receives mode 0700.
- DevOps configuration handoff opens a root-owned payload snapshot inside the
  target, then passes only its read descriptor to the unprivileged writer.
  Account execution retains the explicit clean environment. The writer uses
  private account directories, no-follow descriptors, exclusive candidates,
  synchronized writes and atomic no-replace publication. A different existing
  account configuration is preserved and reported.
- Desktop shell/session defaults, server Bash/operator defaults, GPG input,
  firmware login fragments, Incus login fragments, generated sharing bookmarks,
  hardware battery actions and appearance capture use independent payload
  inputs. Bookmarks and battery adjustments are calculated independently for
  primary inputs and future-account defaults.
- After every selected late stage succeeds, the installation-only publisher
  removes its private rendered inputs. A failed stage retains those inputs.
  Publication is atomic per file; there is no whole-HOME rollback transaction.

The active KWallet unit, Secret Service activation file and KWallet
configuration still belong in the account's corresponding configuration/data
locations. Additional root-owned public reference copies are published beneath
the canonical local share root for Bitwarden servicing policy validation. They
contain non-secret defaults, are not active unit search paths, and are not
substitutes for the account copies. Tuta's public launcher and KeePassXC's
non-secret fallback defaults likewise have their own public publication and
matching AppArmor read rules.

## Future-account and runtime contracts

The autostart/shutdown AppArmor attachment and read/execute patterns use the
canonical HOME root followed by `*`. They therefore continue to cover each new
account directly beneath that root. The privileged account-creation tool must
select the appropriate role skeleton and assign the new HOME its account
ownership. The later account-type follow-up below adds the explicit
administrative `account-create` CLI. Debian's own default skeleton selection
remains separate. Templates are copied for account creation; session hooks
execute from the resulting HOME.

The source and payload scans cover every regular file under all installed local
binary, administrative, library-execution and library source trees, without an
extension filter. This includes all 79 desktop Python files and 161 Perl tree
files/entrypoints. The installed application set reviewed through those shared
owners includes Bitwarden, QoreDB, Obsidian, Tomat, Sleek, Postman, Discord, Tuta,
Ledger, ChatGPT/Codex, KeePassXC, Whisper and Llama. Waypaper and subsequent
installer child-shell inputs are included in the existing shared static scope
checks. Appearance registry source-line labels are repository provenance data
under the share tree; they are not installed skeleton file access.

The two-app private Xwayland policy was not changed.

## Changed owners

Paths below are relative to `d-i/debian/` unless otherwise stated.

- Environment and selector owners: `hooks/installer/di.env`, `repo.env`.
- Installed runtime and policy owners:
  `hooks/target/etc/apparmor.d/desktop/desktop-wrappers.tmpl`,
  `hooks/target/usr/local/bin/desktop/labwc-sync-application-launchers.tmpl`,
  `hooks/target/usr/local/lib/common/perl5/site_perl/apt-repo-local/APTRepoLocal/Servicing/Bitwarden.pm`,
  `hooks/target/usr/local/lib/desktop/python3/dist-packages/labwc_managed_app/profiles.py.tmpl`.
- Shared publication: `scripts/common/modules/target-publication.sh`,
  `scripts/common/primary-defaults.py`, `scripts/late/target-assets.sh`.
- Related generated defaults: `scripts/common/filen-install.py`,
  `scripts/common/filen.sh`, `scripts/common/hardware-tuning-config.py`,
  `scripts/common/hardware-tuning.sh`, `scripts/late/network-sharing.py`,
  `scripts/late/network-sharing.sh`.
- Desktop publication: `scripts/desktop/appearance-setup.py`,
  `scripts/desktop/appearance_setup/defaults.py`,
  `scripts/desktop/components/appearance.sh`,
  `scripts/desktop/components/devices-network.sh`,
  `scripts/desktop/components/gpg-bootstrap.sh`,
  `scripts/desktop/components/rendering-access.sh`,
  `scripts/desktop/components/target-assets.sh`,
  `scripts/desktop/components/user-config.sh`,
  `scripts/desktop/components/user-session.sh`,
  `scripts/desktop/verify.sh.tmpl`, `scripts/desktop/virtualization.sh`.
- Late/server publication: `scripts/late/account.sh`, `scripts/late/ch341a.sh`,
  `scripts/late/devops/account-execution.sh`,
  `scripts/late/devops/codex-appserver.sh`,
  `scripts/late/devops/publication-layout.sh`,
  `scripts/late/devops/tool-configs.sh`, `scripts/late/dispatch.sh`,
  `scripts/late/software.sh.tmpl`, `scripts/server/setup.py.tmpl`,
  `scripts/firstboot/04-validation.sh.tmpl`.
- Static audit owner: repository-root `tools/post_change_check.py`.
- Source fixtures: `tests/test_desktop_sandbox.py`,
  `tests/test_filen_sync_20261017.py`, `tests/test_hardware_tuning_20260916.py`,
  `tests/test_hardware_tuning_handover_20260917.py`,
  `tests/test_hardware_tuning_refactor_20260917.py`,
  `tests/test_late_target_install_contracts.py`, `tests/test_network_sharing.py`,
  `tests/test_primary_payload_defaults.py`.
- Generated products: both suites' `payload.tar.gz`, `payload.manifest`,
  `receipt.json` and `preseed.cfg`. The pure build also serialized the declared
  `source.sh` and `support-matrix.json` products; their bytes did not change.

## Earlier validation evidence and limits

The checks and hashes in this section precede the destination follow-up below.
They establish that earlier working-tree snapshot only. The later source
changes have not been run through that validation command.

- `timeout 120s make build`: passed. Source release identity
  `08450f5c355e2551b175c25289636e3243ff888ee588ba75dfc38734b3a96c05`;
  source fingerprint
  `77518ac55dfaaf762fb55c4e30625c65ccc80c260ea40270df8dab9adbe5d76f`.
- `timeout 180s python3 -B tools/post_change_check.py`: passed after generation.
  It parses source as data, invokes shell syntax/ShellCheck checks, and verifies
  generated products. The recorded pass included 127 installer child shells,
  57 target-install functions, two target-install scopes, 672 appearance mapping
  checks, and 2,422 current payload members. That pass included this record's
  earlier content and the then-current fixture sources.
- An independent, bounded standard-library archive/data check verified every
  member size and SHA-256 against the manifest, 2,249 source-member comparisons,
  the compiler-generated repository selector suffix, matching suite payload and
  manifest bytes, and zero forbidden references in all 528 installed library
  and wrapper files. The first version of that additional check incorrectly
  required the generated repository environment to equal the authored prefix;
  the corrected check accounts for the documented compiler selector suffix.
- `git diff --check`: passed.
- New guarded failure fixtures cover candidate publication failure, symlink and
  hardlink refusal, changed source identity, deadline failure, account UID/GID
  and modes, and cleanup link refusal. These fixtures were authored and parsed
  only. No unittest discovery, fixture import/execution, installer, VM, chroot,
  container, live service, native application launch or host repair was run.
- Perl was inspected as source. No managed Perl import or BEGIN block was
  executed. AppArmor structure was checked as data; policy compilation/loading
  and target session transitions remain unverified.
- No offline bundle generation was run. No target image/package versions or
  successful end-to-end installation are established by this static record.

Earlier artifact SHA-256 values, superseded by the follow-up build:

| Product | SHA-256 |
| --- | --- |
| Both suite payload archives | `005cd8ef4d2c77ca6172c03c315a3185e4ebc4dcc448e97cb789f15a9b75cae8` |
| Both suite manifests | `d1bd85bf9dd8ba1026dd3dde4ddf375da8c956df45b7400780a7972bbe15d220` |
| Forky preseed | `90d7cdd34b6d84e995a0db07d05a6741c24e678c40709514db93f45715a242da` |
| Trixie preseed | `c10bd598d53a4de014a615660f055f96f07fa5554d9c98b74d30852b5dea5485` |
| Both suite bootstrap source files | `4b79e30d528aa1e24f872574cda2b25fb198ae5028a49bedc907feb43002e944` |

## Destination follow-up

The user requested another payload-to-both-destinations audit. Direct source
inspection confirmed that `source_prepare_payload` authenticates and extracts
the archive, and `source_fetch` copies regular members from that protected
snapshot. Once the payload-ready marker exists, it refuses a missing member
instead of fetching a moving remote replacement. Existing renderers consume
those copied inputs before publication.

The payload source inventory contains 259 desktop skeleton files and eight
server skeleton files, including hidden files. Role/package gates and existing
explicit exclusions still govern selection; this is not an unrendered bulk
copy of every optional or inactive source asset. The copied paths shown in the
inventory were checkout template names, not paths inspected in the installed
host's HOME or Syncthing directories.

The follow-up found and corrected two omissions:

1. `scripts/server/foundation.sh` now calls the shared primary-default publisher
   after the existing server-account validation/publication step. All selected
   rendered defaults are copied recursively, including the optional
   Whisper/Llama login fragment and CI fragment. Later DevOps and Codex stages
   continue to publish their respective fragments independently from payload
   inputs. The shared publisher also establishes HOME's account UID/GID and
   mode 0700.
2. `scripts/desktop/waypaper.sh` now renders the same payload launcher to both
   destinations. `waypaper_launcher_dir` is derived from ACCOUNT_HOME's local
   applications directory, and `waypaper_launcher` appends `waypaper.desktop`.
   Its HOME copy receives mode 0600 and account UID/GID; the future-user
   template copy receives mode 0644 under the root-private skeleton.

`tools/post_change_check.py` and
`tests/test_late_target_install_contracts.py` gained source guards and mutation
fixtures for those destination pairs, server publication ordering, recursive
hidden-file coverage, the primary launcher's exact account-relative directory,
and HOME ownership/privacy. The added fixtures have not been executed.

After the user prohibited further ad hoc Python scans and checks on the host,
work continued with direct checkout source/diff reads and generation only.
`timeout 120s make build` completed successfully, serializing 2,422 members for
both suites. No validation runner, native test, installed helper or installer
was executed for this follow-up. The required changed-file audit was not rerun
under that latest restriction; earlier PASS results must not be presented as
validation of these additional changes.

The destination follow-up's generated receipts reported:

- Release: `59aa14d6ed8f7e98c3b21b577f4321629010597f750ef3036310f2821904db75`.
- Source fingerprint: `60c6abc3250e1f71ff3294114d3b79a3ecf36fae2faa591d27a3481557e5fb98`.
- Payload archive SHA-256: `ebb45a3a1cad663be2dd17781bb5ab0c03d54aeed75a9fb5362d8f67ff9b5ec4`.
- Manifest SHA-256: `127ee5861cca5477e9b46131bc4a036a4fcced371748db28de31f6a28683316c`.

These historical hashes are generation receipt data. The independent archive check
listed earlier was not rerun against this follow-up build. Native installation
and loaded-policy acceptance remain unverified.

## Explicit account types and reusable defaults

The primary account is still created by Debian Installer. Every selected
desktop role publishes its rendered desktop defaults directly from the
authenticated payload snapshot into that account's HOME; every selected server
role does the same for its server defaults. The shared publisher sets the
account UID/GID and HOME mode 0700. It never invokes the future-account creation
CLI or copies the already installed skeleton into the primary HOME.

The `--no-create-home` addition to `foundation_identity()` in
`scripts/server/setup.py.tmpl` belongs only to fixed system service identities.
Those accounts use `--system` and a non-login shell, and their separate service
state directories are prepared explicitly. `account_skeleton()` and the server
foundation's primary-default publisher still initialize the human operator's
HOME.

The new installed administrative command is selected through
`FILE_ACCOUNT_CREATE` in the canonical runtime contract. On the installed
target, an administrator can run:

```sh
sudo account-create --type desktop USERNAME
sudo account-create --type server USERNAME
sudo account-create --type base USERNAME
```

Omitting `--type` selects base. Desktop and server types require their own
installed defaults and cannot silently fall back to another type. Base has
four minimal private Bash/login defaults, without desktop or server tooling.
The command creates a new human account with a HOME and login shell, a locked
password, and no inherited supplementary group grants. Password setup and
additional administrative or workspace authorization are separate explicit
operator decisions. It refuses existing account/group/HOME adoption. Service
identities and non-login accounts are outside this command's human-defaults
contract.

The root-private base, desktop and server template roots are owned by the
canonical `DIR_ETC_SKEL_*` runtime variables. All three roots remain mode 0700.
Only this explicit root account-provisioning entrypoint reads installed
templates; the application Python and Perl trees and ordinary runtime wrappers
remain forbidden from referencing them. The initializer drops to the new
account's UID/GID before writing account-relative application configuration and
does not read the template roots. Creation uses an exclusive state lock, a
checked private snapshot, no-follow descriptor traversal, and a durable result
record. Failure after account mutation retains operation evidence instead of
deleting an uncertain account or retrying automatically.

The desktop renderer captures the primary account's concrete configured input
before rendering the future-account copy from the same payload input using the
same shared renderer. Sleek's complete active task-file configuration and all
four Xournal++ Documents/Pictures properties remain populated. Future-account
initialization resolves those typed HOME fields for the new user. Xarchiver
gets concrete temporary/extraction directories in each actual HOME copy; a new
desktop account without existing authorized pool storage uses its own private
cache directory. Generated GTK bookmarks and Bazel defaults likewise avoid
freezing the primary username. Firmware login functions derive and validate
the current account identity when they run.

The build failure reported as `FILE_TARGET_SKEL_BASE_` was caused by a staging
loop that constructed FILE selector names dynamically. It has been replaced by
four explicit registered FILE selector calls. The compiler's missing-selector
check is retained. The pure build then succeeded with 2,427 payload members.

Additional source-only guards cover the three account types, privileged entry
gate, direct primary publication, lock/identity/recovery contracts, the four
explicit base selectors, and the new canonical path-map producers. The runtime
placeholder check now checks both defined values and actual producers in the
shared installer renderer. Guarded mutation fixtures were authored as source;
they have not been imported or executed.

Validation of the final snapshot is recorded below after final serialization.
The first audit in this follow-up stopped at the release-equality check because
the renderer source had changed after generation. It is a detected stale
product, not a passing final audit. No VM, native installer, account creation,
service, installed helper, package operation, or application launch was run.

## Account-type follow-up verification

- `timeout 120s make build`: passed after the explicit-selector repair and
  final payload-source changes, serializing 2,427 members for both suites.
- `timeout 180s python3 -B tools/post_change_check.py`: passed after that
  serialization. Its data-only runtime-path audit covered 134 script assets
  and 852 target assets and confirmed every referenced path is defined and
  actually published by the shared renderer. It checked 31 pre-profile
  dependencies and five path-loading entrypoint contracts. It compared 2,254
  captured source members and all 2,427 release members with current products.
- The same audit inspected 528 installed application/library source files for
  forbidden private-skeleton references. The sole root administrative account
  creator is checked separately for its privileged provisioning contract.
- Source checks cover three private skeleton roots, three future-account
  types, all four minimal base login defaults, and both role-to-primary
  destination pairs. Extensionless `.profile`, `.bashrc`, `.bash_profile` and
  `.bash_logout` sources are included in changed-file shell syntax/SC2154
  checking, alongside the existing shell scripts and nested child-shell scope
  checks.
- `git diff --check`: passed. Guarded mutation fixtures remain authored and
  parsed as source only; they were not imported, discovered or executed.
- There was no VM, container, chroot, live account creation, installer run,
  installed management helper execution, service operation, package operation,
  Perl import/BEGIN execution, AppArmor load, or offline generation. No native
  target image/package versions or completed-install result is claimed.

Final generated identities (receipt data and independent `sha256sum` of the
two archives/manifests):

| Value | SHA-256 |
| --- | --- |
| Release | `f2468fcdabdf84dd7995a1f91f70cd2425fa13d936ecf0c3df63324d36014a33` |
| Source fingerprint | `84f6c792e01582a0eb4f59b0cfc0b904ff9927eb0ae044f48ca005af0becbb10` |
| Both payload archives | `4ea401dc0a3115bb70b766e83f7cba65afc5d00dff7dd29cd99bc4fc8d29c6b4` |
| Both payload manifests | `73181ca4f2a28d140d5ab4572836b491bf7311fe521d362dd855c1259ae028b4` |

These results establish serialization consistency and static source contracts.
Native account creation, installation, target policy transitions and application
behavior remain unverified under the user's no-native-run restriction.

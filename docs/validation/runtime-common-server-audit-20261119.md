# Common and server runtime review — 2026-11-19

## Outcome and limits

This second review pass made four bounded observation improvements to installed
runtime helpers and corrected one shared hardware command's source ownership.
It removes repeated observations inside the same operation and keeps the
service, account and hardware gates at their existing call sites. The changes
have source-level syntax evidence only. No native test, repository
import, service command, hardware probe, installer replay, Perl compile or
isolation-capability probe was executed on the development host.

The counts below are derived from the source call paths. They are not elapsed
time measurements and do not prove service readiness, SSH authentication, boot
success or hardware health. Each later operation still obtains fresh evidence.

| Operation | Previous work | Current work | Scope of the reduction |
|---|---:|---:|---|
| NVMe endpoint link evidence | 10 attribute reads | 7 attribute reads | Each matching `15b7:5006`, class `010802` endpoint in one report; three compatibility fields reuse the nested evidence |
| NVMe kernel device root resolution | One per PCI entry | One when the listing is nonempty | Each report; every PCI entry still resolves separately and must remain inside the kernel device tree |
| Server maintenance stopped-state decision | 2 `systemctl show` processes | 1 `systemctl show` process | The path that reaches both the `ActiveState` and `MainPID` gates; an active-state rejection already used only one process |
| SSH context directory metadata | 14 `find` processes | 7 `find` processes | Seven directories, with owner and mode obtained together for each directory |
| SSH context metadata including three identity files | 17 `find` processes | 10 `find` processes | The same successful context check; file owner/link-count/mode checks remain separate and unchanged |
| Hardware report count/display values | Up to 5 reads per control | At most 1 read per control | Four profile comparisons plus the displayed current value; planning safety reads are additional and remain fresh |

## Coverage and ownership

The original assigned inventory contains 159 physical files and 1,311,013
expanded source bytes at the start of this pass. These figures exclude the
package agent's `apt-repo-local.tmpl` and `perl5/site_perl/apt-repo-local/**`
trees. File counts and hashes were collected as data; they do not mean that
every branch of every inventoried file received the same depth of review.

| Physical root below `d-i/debian/hooks/target/usr/local/` | Files | Initial source bytes | Review coverage |
|---|---:|---:|---|
| `bin/common` | 12 | 140,762 | Entry-point inventory and relevant runtime consumers; `git-ssh` context contract traced |
| `bin/server` | 2 | 14,470 | Entry-point inventory; maintained server role wiring inspected |
| `sbin` | 10 | 198,840 | Full inventory; NVMe reporter read/containment checks and direct staging consumer reviewed in detail |
| `libexec/common`, excluding local APT importer | 49 | 458,758 | Full inventory; SSH, diagnostics, storage and selected daemon boundaries inspected |
| `libexec/server` | 4 | 80,127 | Full inventory; server maintenance command gate and all five owning call sites traced |
| `lib/common/perl5`, excluding local APT servicing | 82 | 418,056 | Module inventory and selected Zram/Filen/managed-process call paths; shared status-decoder consolidation belongs to the integration owner |
| `lib/server/perl5` | 0 | 0 | No physical files in this checkout |

The machine-readable companion records the initial inventory and exact changed
files. The review was subsequently extended to 32 files in common Python,
common hardware tuning and `usr/libexec/install-tools`; findings from that
additional review are recorded separately below rather than being implied by
the original totals. The neutral CLI moved into `bin/common` adds one file to
that ownership scope; its original desktop source file is removed.

No `Managed::Process` or adapter edits belong to this subtask. The integration
owner is separately reviewing/consolidating raw wait-status decoding. The
desktop owner retains appearance/session Python and Perl changes. The package
owner retains local APT importer and servicing code. No
`managed_workflows.Tree.read` or `Tree.write` interface was changed.

## Changed runtime paths and real consumers

### NVMe evidence

Changed source:
`d-i/debian/hooks/target/usr/local/sbin/common/nvme-pcie-status`.

`scripts/late/storage-maintenance.sh` stages this physical member as the
canonical target `nvme-pcie-status` command for both storage families.
`hooks/target/usr/local/libexec/common/debugsys.py.tmpl` invokes that installed
command from its storage probes. The command also remains an operator-facing,
read-only diagnostic.

`snapshot()` now obtains the endpoint's seven link-evidence attributes once.
The top-level `aer_correctable`, `current_link_speed` and `current_link_width`
compatibility fields use those exact values, including `None` when an
attribute is unavailable. Previously those three values were read again after
the nested dictionary was collected, which could both repeat I/O and disagree
within the same report when counters or link state changed.

The kernel device root is resolved lazily once per nonempty report. Device
entry resolution, PCI-address validation, containment and matching name,
vendor/device/class selection, root ownership, no-follow attribute opens,
ASCII decoding, 8,192-byte attribute bounds, control-value validation and the
controller-directory checks remain in place. Upstream bridge, firmware,
correctable-error logging, runtime-PM and APST observations remain separate.
The helper still never reads serials or namespace contents, writes PCI/sysfs
state, runs NVMe commands, or declares hardware health verified.

Reusing an attribute value within this report is not an atomic hardware
snapshot. Different attributes may still change between their individual
reads, and a later report must reread them.

### Server maintenance gate

Changed source:
`d-i/debian/hooks/target/usr/local/libexec/server/installer-serverctl.py.tmpl`.

`scripts/server/foundation.sh` installs the template at `FILE_SERVER_CONTROL`.
The existing `require_stopped()` gate is called by DNS configuration, backup,
update, rollback and recovery acknowledgement. Those callers remain at their
original operation boundaries.

One fixed `systemctl show` invocation now requests named `ActiveState` and
`MainPID` properties. The parser accepts either property order, requires both
properties exactly once, and rejects unknown or malformed lines. Only
`inactive` or `failed` with an exact zero PID can pass. Nonzero or unknown PID
values retain the `OutcomeUnknown` outcome, and command failure propagates.
The Technitium guest's independent `dns_workload().stopped()` check still runs
after the host service gate; a stopped host wrapper does not by itself prove
that the guest workload is stopped.

The existing command helper retains its clean environment, deadline, bounded
output, pinned child identity and termination handling. No result is cached
between maintenance operations. The standard named multi-property interface is
documented by [systemctl's `--property` option](https://www.freedesktop.org/software/systemd/man/latest/systemctl.html#-p).

### Managed SSH context

Changed source:
`d-i/debian/hooks/target/usr/local/libexec/common/ssh-checks`.

`scripts/desktop/components/target-assets.sh` installs the helper at the
canonical target libexec path. Four real consumers source it:

- `usr/local/bin/common/git-ssh` uses it for explicit unlock/status checks.
- `usr/local/libexec/desktop/obsidian-git-sync` checks the selected identity
  before automatic synchronization.
- `usr/local/libexec/desktop/labwc-ssh-key-load` checks context and socket before
  loading and proving the identity.
- `usr/local/libexec/desktop/labwc-ssh-gpg-askpass` checks context before
  decrypting the passphrase blob.

Each of the seven directory checks now asks `find -P` for `%U:%m` once. The
complete response must exactly match the current UID and an allowed mode;
private SSH/GnuPG directories still require mode 0700. A failed metadata
command explicitly fails the context check, even if it printed a plausible
response before failing.

The NSS/home comparison, non-root UID requirement, home-root containment,
directory/non-symlink checks, private-file no-symlink checks, exact link count,
private/public file modes, canonical user runtime directory, socket type,
socket ownership and mode remain in place. The exported/private variables
consumed by existing callers retain their names and values. There is no
cross-invocation cache and no agent, key or credential access during this
source review.

## Fixtures and static verification

`d-i/debian/tests/test_runtime_observation_20261119.py` adds 14 guarded test
methods: seven for service observations, five for SSH context observations and
two for the hardware command's family ownership.
The server command is mocked. The SSH fixture uses a private tree, a recording
metadata adapter and a modeled identity; it never queries real NSS or an SSH
agent. Its cases cover exact command counts, property order, missing and
duplicate data, invalid/still-running state, command failure, independent guest
failure, metadata owner/mode failures, ambiguous output, symlinks, hardlinks,
and fresh permission observations. The family cases source the actual
repository family guard in the isolated fixture: both desktop and server must
accept the common hardware CLI, while server must continue rejecting the
desktop-only management CLI.

`d-i/debian/tests/test_nvme_link_idle_20260927.py` adds two guarded test methods
for one-read compatibility fields, unavailable values and fresh subsequent
snapshots. A private fixture changes its attributes after a read to make an
accidental second observation visible. Existing containment, metadata, size,
unavailable-control and read-only cases remain. The test's stale physical
source path and source-staging adapter are updated to the current layout, and
its publication-failure check now covers all four initial assets.

`d-i/debian/tests/test_hardware_report_observation_20261119.py` adds seven
guarded cases using in-memory controls. They cover a shared count/display
observation, a fresh next report, a cached unavailable observation, an
unqueryable control, fresh planning bounds and ownership checks, fresh health
evidence, the existing standalone `Knob.report` interface, and preservation of
a fatal `ValueError`. A changing paired bound deliberately invalidates one
profile despite the report's shared display evidence. No native driver is
constructed by these cases.

The affected direct-load fixtures in `test_hardware_tuning_20260916.py` and
`test_management_hardware_visibility.py` now name the real common hardware
module directory and desktop management entry point. Their isolation guards
remain intact. The old flat import directories do not exist and were not
remapped by `payload_fixture`.

Completed checks were limited to:

- Standard-library `ast.parse` of every changed Python source and fixture,
  without importing repository modules. The 28 common Python/hardware modules
  were also parsed as data while resolving their static internal imports.
- AST parsing of the private metadata adapter embedded in the new fixture.
- `/bin/sh -n` of `ssh-checks` and the hardware staging adapter, without sourcing
  or running either.
- Source search for all direct consumers and each `require_stopped()` call.
- Byte/hash comparison of the moved CLI and matching ownership/member entries
  in the JSON/TSV registries and fixture path map.

All completed syntax checks passed. The NVMe fixture file now contains 24
test definitions; the new general observation fixture contains 14 and the
new hardware report fixture contains seven. In total, 23 new test methods
were authored in this subtask. These are authored cases, not executed passing
tests. Native command semantics, rendering,
installed permissions, AppArmor mediation and integration in an actual target
remain subject to the separate isolated validation gate. The integration
owner performs the required changed-file audit and pure artifact build.

All host scratch for this pass is under the private
`.build/validation/round2/evidence` tree on the checked `overlayfs` workspace.
The source-check and inventory-writing commands set explicit `TMPDIR`, `TMP`
and `TEMP` there. No host temporary filesystem, mount, service or device was
used as a fixture.

## Additional common Python, hardware and install-tools review

| Additional physical root below `hooks/target/usr/` | Files | Source bytes when this extension was inventoried | Review result |
|---|---:|---:|---|
| `local/lib/common/python3` | 19 | 234,642 | Static local imports resolve; existing private-file, publication and process boundaries retained |
| `local/lib/common/hardware_tuning` | 9 | 203,247 | Shared CLI ownership defect fixed; report-only duplicate observations removed |
| `libexec/install-tools` | 4 | 60,123 | All four installed entry points and selected verification/boot call paths traced; no code change |

### Hardware report observations

Only `Engine.report()` and `Knob.report()` changed in the hardware modules.
The former keeps an operation-local map of current-value results or errors.
Both `planned_changes` and the controls display use that map. A control
requested in all four profiles previously contributed four count reads plus
one display read; those five observations become one. A control not requested
by a profile is still read for display if queryable. Non-restorable controls
are never read merely to invent a current value.

No `knob.read` callable is replaced or wrapped globally. `Engine.plan()` still
performs its own fresh pair-bound, governor/EPP and policy-owner checks for
each profile. `apply`, `reset`, `health`, write/readback, recovery ordering,
thermal interlocks and device identity checks are unchanged. The separate
recovery-journal reads around backend setup are deliberately retained. A
standalone `Knob.report()` call still uses its fresh reader by default.

An unavailable report observation remains an error for that report, including
its affected profile counts; it never becomes zero, a default value or an
apparently verified state. `OSError` and `TuningError` retain the existing
display-error behavior. A `ValueError` that previously escaped the final
control report remains fatal. The observation map is discarded when the
report returns or raises.

### Reachable server source-family failure and correction

`scripts/server/hardware.sh` invokes the shared
`install_profile_hardware_tuning()` implementation. The authored server
profiles `btrfs-srv-flex.env`, `btrfs-srv-flex-duo.env` and
`btrfs-srv-flex-trio.env` enable Intel tuning and autostart. When their Intel
hardware gate succeeds, the shared installer stages the hardware CLI.

Before this change the requested physical member was
`hooks/target/usr/local/bin/desktop/labwc-hardware-tuning`.
`installer_repo_file_value()` applies `installer_repo_assert_asset_family()`,
which correctly rejects a desktop member under a server role. This was a
source-level reachable failure, not a failed live installation observed during
this pass.

The neutral wrapper now belongs to
`hooks/target/usr/local/bin/common/labwc-hardware-tuning`. Its content is
unchanged, with SHA-256
`610e69be7375d01953547027eb3870fe1c234aaa0be245860c7c2a219c2fb73f`.
It still imports the common hardware client and installs at the same
`/usr/local/bin/labwc-hardware-tuning` interface with mode 0755. No new AppArmor
permissions, authentication route, service enablement or hardware policy was
introduced. Both role families may consume common members through the existing
family guard; the guard itself is unchanged.

The staging caller and fixture path map now select the common physical member.
Four token source-member lists were updated in each placeholder registry
format, retaining their ordering and other ownership data. This registry
format has no per-occurrence source-line fields for the moved member. The
global source fingerprint is left for the integration owner's final pure
metadata refresh after concurrent edits have settled. Historical reports and
archives were not rewritten.

### Common Python and install-tools observations retained

The static module graph for all 19 common Python files and nine hardware files
resolves 44 internal import references to physical members, including the
`gitbuild/worker.py.tmpl` source that installs as `worker.py`. No unresolved
static internal import was found. This does not execute imports or establish
availability of native libraries, D-Bus services, drivers or Python package
dependencies on an installed target.

The actual common Python staging/consumer paths inspected include:

- Key manager: the common CLI, eight `key_manager` modules and shared
  `managed_workflows.fs`, staged by `desktop_stage_key_manager()`.
- Gitbuild: common CLI/worker/publisher/importer wrappers, seven `gitbuild`
  modules and the three shared workflow modules, staged by
  `devops_stage_gitbuild()` with its concrete worker-template render.
- Network sharing: the common Python module staged by
  `scripts/common/profile-services.sh` and invoked through the common sharing
  entry points.
- Hardware tuning: the nine available common modules, with vendor modules
  selected by the existing host/hardware/class gates and used by the fixed
  broker, worker, policy-owner, power-profiles and client entry points.

Repeated file checks around privileged Gitbuild copies, key publication,
transaction planning and rollback are separate trust/identity boundaries and
were retained. Key-manager terminal and secret-handling commands were not
merged into the generic process helper. Network mount/service observations
before and after mutations remain fresh.

`system-log.sh` is staged by common system services and sourced by APT refresh
and swap fallback helpers; its logger lookup already has a per-process cache.
`bootprofile-apply` is staged by the common/late boot flow and invoked by its
system service. `secure-boot-tool` is staged by the GRUB provider and called by
kernel/header/removal hooks, the APT MOK prehook and LUKS MOK wrappers. Its
`verify-module-signature.py` dependency is staged beside it, and the source
contains the expected fixed decompression and cryptographic-verification calls.

The module verifier's protected snapshots, input/output bounds, explicit
certificate handling and failure outcomes were inspected. Verification before
signing and verification after signing operate on different contents and were
not deduplicated. Likewise, fresh mount readiness and publication durability
checks were retained. This source review makes no claim that signatures,
firmware enrollment, initramfs regeneration, mounts or boot were exercised.

## Exact files changed by this subtask

Runtime/source changes:

- `d-i/debian/hooks/target/usr/local/sbin/common/nvme-pcie-status`
- `d-i/debian/hooks/target/usr/local/libexec/server/installer-serverctl.py.tmpl`
- `d-i/debian/hooks/target/usr/local/libexec/common/ssh-checks`
- `d-i/debian/hooks/target/usr/local/lib/common/hardware_tuning/common.py`
- `d-i/debian/hooks/target/usr/local/lib/common/hardware_tuning/engine.py`
- `d-i/debian/hooks/target/usr/local/bin/common/labwc-hardware-tuning`, moved
  byte-for-byte from `usr/local/bin/desktop/labwc-hardware-tuning`
- `d-i/debian/scripts/common/hardware-tuning.sh`

Fixture and registry changes:

- `d-i/debian/tests/test_nvme_link_idle_20260927.py`
- `d-i/debian/tests/test_runtime_observation_20261119.py`
- `d-i/debian/tests/test_hardware_report_observation_20261119.py`
- `d-i/debian/tests/test_hardware_tuning_20260916.py`
- `d-i/debian/tests/test_management_hardware_visibility.py`
- `d-i/debian/tests/fixtures/contracts/source-paths.json`
- `d-i/debian/catalog/placeholder-registry.json`
- `d-i/debian/catalog/placeholder-registry.tsv`

Evidence files:

- `docs/validation/runtime-common-server-audit-20261119.md`
- `docs/validation/runtime-common-server-audit-20261119.json`

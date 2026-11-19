# Installer performance and readiness evidence — 2026-11-19

## What this evidence establishes

The supplied failed installation took **6,463 seconds (107 minutes 43 seconds)**
from the first timestamped `prepare-context` event to the fatal late-command
event. Late dispatch accounts for **4,131 seconds (68 minutes 51 seconds)**.
The main package-selection interval, vendor-software preparation, desktop
publication/configuration, and storage/security setup all matter. The evidence
does not support attributing the entire delay to environment parsing, hashes,
or shell process creation.

These are observations from the supplied logs, not a successful baseline run of
the edited source. No full installer, service, package manager, managed helper,
Perl import, native test discovery, or benchmark was executed on the development
host. No comparable successful before/after installation is available. No final
installation time or percentage speedup is claimed.

The companion [machine-readable evidence](installer-performance-evidence-20261119.json)
records input hashes, shipped receipt identities, exact UTC boundaries, physical
log line numbers, stage outcomes, and bounded event counts. Log parsing preserves
carriage-return progress records instead of treating each carriage return as an
extra physical line. Identifiers, addresses, credentials, and device serials
from the input logs are not reproduced in this report.

## Revision reconciliation and the Labwc failure

The input contains several different revisions:

| Evidence | Recorded identity or digest | Meaning |
| --- | --- | --- |
| `todo/installer.log` | release `a66ecd9a0e79c128300604b8f422faf6e8759fe64c5ad49b2e3d246f73ccc745` | Revision used by the failed installation |
| Both supplied suite receipts | release `d02800c982e0fbde087f19dbfb21fa7bc00e1e03c7e19575e1af228b5692621b` | Shipped generated products, before this work |
| Both supplied suite payload archives | SHA-256 `fad99459aead4da7d81617e717a79e46431272cf53ae6bd9bdbe436ffcc6f31f` | Identical shared payload, 2,433 members |
| `offline/payload.tar.gz` | SHA-256 `73c68e5bbb7ddb665cd3e5614acb957f3523b91bd325b05eb44428f0facd7416` | Older flat-tree offline bundle |
| Receipts inside that offline bundle | release `043109310d674ea55bdd30298d83aa537ae999434b2d8743277b766075a2d7c0` | Also different from the failed-run release |

The failed-run log reports a base render of 2,434 members and 1,122 rendered
files. The current source and both supplied suite payloads have no
`scripts/desktop/verify.sh.tmpl`; the log names that file. The archive contains
no Git history, and no supplied receipt or publication matches the failed-run
release. The exact historical revision therefore cannot be reconstructed from
the supplied material.

There is nevertheless direct source evidence of the ordering defect in the
older offline bundle. Its `scripts/desktop/labwc.sh` calls
`desktop_verify_target_staging` and `desktop_verify_role_installation` **before**
`desktop_enable_target_services`. Its verifier requires both
`multi-user.target.wants/labwc-system-desktop-overrides.*` links. The failed log
records that the unit files were staged, followed by a failure on the missing
service enablement link; it contains no intervening service-enablement success.
This is a source-level reproduction of the ordering problem in an available
historical revision, not proof of a byte-identical revision or executed replay.

The supplied current orchestrator had already removed the large verifier and
retained service enablement at the end. That removes the historical pre-enable
assertion, but the two project-owned units still used the optional-unit helper,
which accepts an unavailable unit with a warning. Final readiness checked owned
regular files and boot/package state, but did not check these enablement links.

The correction in this change restores the essential assertion at its owner:

* `scripts/desktop/components/services.sh` requires each project-owned unit to
  be a readable regular file with root ownership, mode 0644, and one link;
  validates destination ancestry; invokes the existing offline systemd link
  writer; then checks the exact installed-system symlink target and ownership.
  Optional package units retain their existing optional behavior.
* `hooks/installer/finish-install.d/94zz-99-validate-target` rechecks both links
  inside the existing target chroot before publishing readiness. It verifies
  non-symlink parent directories, regular unit files, metadata, exact link
  destinations, and readability in the **target** namespace. It does not start
  a service or contact a running systemd manager.
* The final role gate is presence of either project-owned unit. The independent
  ownership scan rejects deletion of published unit files, including deletion
  of both units, so removing a file cannot turn a desktop failure into a server
  skip.

An absolute systemd link such as `/etc/systemd/system/example.service` is
resolved in the installed system. Testing that link for readability through an
installer-prefixed path can accidentally resolve it in the installer root.
The mutation check compares the exact link text; final readability is checked
inside the target chroot. This distinction is covered by the focused fixture.

## Ranked wall-time evidence

The following rows are disjoint intervals. They sum to the observed 6,463
seconds; the table does not add child durations to parent stages.

| Rank | Interval | Seconds | Time | What is known |
| --- | --- | ---: | ---: | --- |
| 1 | `pkgsel` menu selection → `finish-install` selection | 1,883 | 31:23 | Base upgrade, pre-pkgsel hooks, package download/unpack/configuration, DKMS and triggers |
| 2 | `desktop.software` | 1,469 | 24:29 | Vendor downloads, inspections, repackaging, local repository work, package installation |
| 3 | `desktop.session` until failure | 962 | 16:02 | Desktop tools, asset publication, rendering, themes, fonts, account configuration; does not complete |
| 4 | `desktop.storage` | 779 | 12:59 | Storage/account/network/security/boot foundation; not merely formatting |
| 5 | Other selected late stages combined | 600 | 10:00 | Fifteen smaller selected stages; detailed intervals in JSON |
| 6 | `desktop.devops` | 297 | 4:57 | Pinned development tools/runtimes and configuration |
| 7 | `bootstrap-base` selection → `pkgsel` selection | 273 | 4:33 | Debootstrap/base rendering/base package and APT setup |
| 8 | First timestamped context event → `bootstrap-base` selection | 170 | 2:50 | Context, class selection, early hooks, partman/layout |
| 9 | Initial late dispatcher work | 24 | 0:24 | Before the first selected late stage starts |
| 10 | `finish-install` selection → late dispatcher start | 6 | 0:06 | d-i handoff |

The full selected late-stage total is 4,107 seconds, plus the initial 24-second
dispatch interval. The 775-second storage child log is nested within the
779-second selected stage. The 959-second desktop child log is nested within
the 962-second failed selected stage. Neither child duration is added again.

### Package, DKMS, and trigger costs

The syslog explicitly records **10.3 GB fetched in 2 minutes 41 seconds** at a
reported 64.1 MB/s during the main package transaction. Additional package
installation starts at 23:29:00 and `pkgsel` reports finishing up at 23:54:29,
a 1,529-second enclosing interval. Download duration is only one part of it.

NVIDIA DKMS reports `Building module(s)` at 23:45:57, followed by the first
module-signing record at 23:53:15: **438 seconds (7:18)** between those events.
The earlier `Building initial module` line is at 23:45:56. These boundaries
show a substantial build-related interval but do not separate CPU time,
compiler subprocess time, disk stalls, or scheduler contention. Five module
signing records follow. The recorded target kernel is
`7.3.1-x64v3-xanmod1`, with NVIDIA `580.142`.

There are three explicit `update-initramfs: Generating` records, at 23:44:26,
23:44:36, and 23:53:59, plus eight deferral records and 41 package-trigger
processing records. The first two generations are ten seconds apart, but the
logs do not give three complete start/end pairs. It would be incorrect to
invent an initramfs total from the gaps or count a deferral as a generation.
The current source also contains a temporary legacy-NVIDIA guard and final
signature/initrd repair; these existing mechanisms must be reviewed together
before changing trigger policy. This work does not suppress required package
triggers or signing to claim a speedup.

The raw syslog contains 2,569 `Unpacking` and 2,569 `Setting up` records,
47 `Fetched` summaries, 16 `Need to get` summaries, and 57 `Reading package
lists` records. These are log events, not an independently verified count of
unique packages, downloads, or APT processes. The two logs overlap, and target
output can be replayed into more than one channel; adding their counts would
double-count work.

### Vendor software and desktop work

The managed ChatGPT/Codex bootstrap reports a 309-second wrapped operation
inside `desktop.software`. Downloaded `.deb` preparation then runs sequentially
for the selected applications. The complete-distribution adoption path already
batches Discord, Ledger, Postman, and Tuta into one local APT installation;
this is an existing optimization and must survive.

Tuta finishes at 00:27:17. Local APT service enablement starts at 00:34:55,
**458 seconds** later. The intervening output contains local repository
publication, a four-package local installation (reported 692 MB of archives
and 2,028 MB of installed data), update-baseline handling, and index refresh.
There is no reliable internal timing split. It is a high-priority measurement
gap, not evidence that any single hash, repository rebuild, or APT call consumed
458 seconds.

The desktop log contains 1,176 `staged_asset` records, many emitted once to the
desktop category and once to the late category. Deduplicating identical
timestamp/message pairs gives 592 records. This is a conservative event count,
not a unique-file or syscall count: some duplicated messages can straddle a
second, and a file can legitimately be republished. The visible per-asset
orchestration and repeated metadata/context checks justify batching, but these
logs alone do not quantify the subprocess reduction.

Base-stage rendering already uses one target Perl invocation. The supplied log
shows the complete hook taking 39 seconds, with the render announcement at
23:20:38 and completion at 23:20:48. That ten-second interval includes the
remainder of rendering and post-render work; it is not a pure CPU benchmark.
Preserve this architecture rather than recreating a per-file renderer.

The log contains 375 completed `run_in_target` wrapper records with 1,148
reported seconds in aggregate. These establish partial instrumentation
coverage only. They exclude direct shell commands and many package processes,
and some belong to enclosing stages described above. They must not be presented
as the total process count or added to the installation total.

## Implemented source-level work reductions

These counts describe the selected code paths and authored fixtures. They are
not timings or observed native process counts. No speedup is extrapolated from
the historical 458-second software interval or the 592 deduplicated asset log
records.

For the seven compatible original `.deb` inputs selected by the full desktop
role, callers now describe expected identity, required members and pinned hashes
in one private plan. The importer copies and hashes its protected snapshots,
inspects each original archive once, publishes one signed repository generation,
then returns the exact archive paths for one serialized APT transaction. One
installed-package readiness query precedes application-specific post-install
callbacks. Base and medium roles select four and six of these inputs; the two
SCX packages have their own earlier dependency barrier. The existing transformed
Discord/Ledger/Postman/Tuta batch and ChatGPT/Codex bootstrap stay separate.

| Original-archive validation / compatible full-desktop batch | Before | After |
| --- | ---: | ---: |
| `dpkg-deb --contents` listings across caller and importer | 24 | 7 |
| `dpkg-deb --field` metadata calls | 28 | 7 |
| Redundant `dpkg-deb --info` calls | 7 | 0 |
| Import publication boundaries | 7 | 1 |
| Forced immediate rebuilds after those imports | 7 | 0 |
| Selected local APT index refreshes | 7 | 1 |
| Compatible `.deb` installation transactions | 7 | 1 |

This accounting excludes required inspection of newly rewritten/signed objects,
existing published state, and the separately pinned Tomat downloader boundary.
Those objects or trust boundaries cannot reuse an unrelated original-archive
result. Ledger's unchanged downloaded archive now has one full SHA-512 scan
instead of two; the computed bytes must still agree with the independently
verified expected digest values. Failure retains the active batch marker.
Source review also found that `.signed-*.deb` intermediate files could be
picked up by an inbox watcher after interruption; these are now non-watchable
`.part` files, with an authored abrupt-exit fixture for that boundary.

Each nonempty asset dependency flush uses one bounded target Perl process.
The path map and prepared-member/publication indexes are read once for that
flush, and distinct resolved source bytes are cached in that process. The three
Labwc line blocks are rendered in the same pass. All candidates are rendered
and preflighted before the first mutation; publication remains atomic per file,
with exact ownership records imported once into the private journal. Ownership
keys no longer require destination-path hashes. Mutable destination ancestry
and essential readiness checks remain at their mutation/use boundaries.

The new `asset_batch` log line reports phase, barrier, records, files,
`source_reads`, `unique_input_bytes`, `written_bytes`, `reused_files`,
`destination_bytes` and `elapsed_seconds`. The authored 250-destination,
single-source publication fixture expects one source read and one Perl launch.
It has not been executed. Real flush counts, bytes, time and failure cleanup
must be collected in a controlled installer replay.

## Installation graph and runtime boundaries

Paths in this table are relative to `d-i/debian/` unless qualified. Literal
leaf names denote fixed interfaces; source roots, d-i state, and installed
paths remain separate contracts.

| Phase / owner | Inputs | Outputs / dependency for next phase | Interpreter and boundary |
| --- | --- | --- | --- |
| Build: `tools/build.py`, class compiler, publication | Authored shared sources, both suite frontends, selection/dispatch policy, environment contracts | Deterministic suite payload/manifest, source helper, preseed, receipts and support matrix | Development Python serialization only; never executes installer/target code |
| Generated preseed include + `scripts/common/source.sh` | Operator-selected seed, trusted preseed pins, local/HTTP/offline transport | Private authenticated payload snapshot and bootstrap implementation | d-i `/bin/sh`, BusyBox-compatible tools; target Perl is unavailable |
| `scripts/preseed/dispatch.sh` and apply/context helpers | Frozen suite/architecture/class/profile/site selection, credential channel, minimal roots | Validated class plan, debconf/preseed answers, bounded runtime context | d-i shell and data-only AWK; no installed-system environment publication |
| `scripts/early/dispatch.sh` → family d-i early hook | Prepared source and frozen class plan | Hook staging, selected disk identity, account/crypto/partman input fragments | d-i shell; target root not yet a complete operating system |
| `scripts/partman/dispatch.sh` → family layout/finish hook | Validated disk identity, selected recipe, sizing/configuration | Mounted target, fstab, frozen layout/runtime values, storage completion | d-i shell + partitioner tools against selected installation disk; never a development-host action |
| Debian `bootstrap-base` / debootstrap | Selected suite/architecture and mounted target | Base operating system including perl-base | d-i orchestration; package extraction/configuration in target |
| `hooks/installer/base-stage.d/00rendertarget` | Authenticated snapshot, selected host/account/layout data, renderer maps and plans | Private rendered source tree, target asset publications, ownership entries, render receipt/ready identity | Shell adapter; one bounded `chroot TARGET /usr/bin/perl -f render.pl`; no extra Perl package transaction |
| Remaining base hooks and apt-setup | Prepared target, suite/family APT policy | Package-manager configuration and usable suite metadata | d-i shell; package operations delegated to target |
| Pre-pkgsel dispatcher | Frozen dependencies, prepared implementation, selected firmware/DKMS/CUDA policy | Required package/signing/temporary-installer policies before main package transaction | d-i shell adapters with serialized target package actions |
| Debian `pkgsel` | Selected package set, verified repository metadata, pre-pkgsel completion | Installed/configured packages, package triggers, selected kernel/modules/initrds | d-i → target APT/dpkg; heavy package/maintainer work belongs here |
| `scripts/late/dispatch.sh` | Ready rendered tree, frozen class graph, account/environment context | Dependency-ordered per-stage completion; `late.done` only after all selected providers succeed | d-i shell; shell/Perl/Python target helpers at explicit chroot/in-target boundaries |
| Desktop storage/software/devops/session | Prior provider completion, prepared assets, downloaded artifacts and selected policy | Final boot/security/network/account/application/desktop configuration and offline unit links | Keep package writers serialized; batch only independent preparation/publication within explicit barriers |
| `finish-install.d/99-normalize-finish` (staged earlier as `94zz-10`) and `95-normalize-apt` | Completed late stages, temporary diversions and target state | Restored package helpers, normalized writable backing/APT paths | d-i shell and target-specific commands; no live target service activation |
| `finish-install.d/94zz-99-validate-target` | Late success, no fatal record, owned-file inventory, final boot/package/service state | `TARGET_VALIDATED`; this is not yet installation success | d-i shell plus one existing target chroot readiness check and owned-publication scan |
| Guarded finish/reboot sentinel | Validated target and successfully completed finish hooks | Installation success and reboot permission | d-i lifecycle owner |
| Installed firstboot service | Concrete installed configuration, booted kernel/systemd/device/network state | Collection, network/service/package/boot validation, completion only on successful stages | Installed `/bin/sh`/target tools under bounded stage deadlines and one ownership lock |

Firstboot runs `01-early.sh`, `02-collect.sh`, `03-network.sh`, and
`04-validation.sh`; only successful diagnostics permit `05-cleanup.sh` to
publish completion. Subsequent cleanup uses its existing service. Runtime
activation and observations that require a booted target remain here. No
installation workload has been moved to firstboot by the changes described
in this report. CrowdSec/Tailscale enrollment remains pending until separately
authorized; pending enrollment in the supplied log is not an installer fault.

The graph uses `hooks/installer/class-dispatch.tsv` and the compiled selected
plan for dependency ownership. Per-stage `.done` state is neither an integrity
check nor permission to accept changed artifacts. A failed desktop session
cannot satisfy final readiness or installation success.

## Integrity checks are not an optimization target

Static inspection found a current-source defect beyond the historical log:
`source_prepare_payload` accepted `expected_archive` and `expected_manifest`,
checked their string syntax, transferred the files, and immediately parsed and
extracted the archive. It wrote those expected strings to `payload.ready`
without comparing the actual file bytes. `source_state_key` was a path/key
hash helper, not evidence that payload content had been authenticated. Two
existing tests explicitly expected incorrect digest arguments to be accepted.

The corrected ownership is a real archive and manifest SHA-256 comparison
against trusted preseed pins before any archive parsing. This adds necessary
work. Once the whole archive bytes are authenticated and the private snapshot
is protected, separately hashing every unchanged member is unnecessary for
transport integrity. Archive traversal, link/type, duplicate-member, byte/count
limits, and exact manifest membership checks remain different properties and
must stay. Old unverified marker text must be invalidated by an explicit schema.

The flat offline adapter has a separate byte-identity boundary. Its old source
referenced an unavailable `source_hash` helper and produced a checksum list
without comparing the copied member bytes. It now uses the defined SHA-256
helpers and validates each copied member against the authenticated manifest
before publishing its verified receipt. Same-size changes must fail; a size
check alone is insufficient. These necessary integrity scans are additional
work, not an optimization removed from the accounting. The old supplied
offline archive was inspected as historical evidence and was not regenerated.

The generated bootstrap also must verify the downloaded source helper before
dot-sourcing it; later payload checks cannot retroactively protect executed
helper code. A checksum fetched alongside untrusted content is not a trust
anchor. These pins establish byte consistency with a trusted preseed; they do
not by themselves authenticate an operator-supplied preseed fetched over an
untrusted channel. Preserve this distinction in deployment documentation.

Requested HTTPS now requires certificate-verifying GNU wget and configured
CA trust. The unconditional `--no-check-certificate` option has been removed;
if wget lacks the GNU `--no-config` capability, bootstrap rejects the HTTPS
request before transfer. BusyBox remains available for explicit HTTP seeds,
and local-file seeds remain supported. The [Debian BusyBox wget source](https://sources.debian.org/src/busybox/1:1.37.0-10.1/networking/wget.c/)
documents that its internal TLS does not authenticate peers and that its
OpenSSL path can select internal TLS if OpenSSL cannot be executed. Merely
providing a TLS-capable BusyBox build is therefore insufficient.

HTTPS installation media must explicitly supply GNU wget and appropriate CA
trust, such as `ca-certificates-udeb` in a prepared d-i image. Bootstrap does not
silently install a downloader or trust package, or retry insecurely. Local/HTTP
seeds retain their operator-controlled deployment model. The first preseed
remains the trust anchor, and existing downloader redirect behavior is not
claimed to provide a new authority/downgrade policy. This compatibility change
requires an isolated installer-image check, not a host TLS probe.

Focused tests now reject mismatching archive and manifest pins with an archive
parser sentinel, reject a legacy receipt accompanying changed bytes, count
one archive and one manifest hash for a protected snapshot/reuse operation,
and ensure a corrupted bootstrap helper never executes its sentinel. TLS
fixtures require GNU wget, reject an untrusted certificate even with legacy
bypass flags, and accept the fixture endpoint only when its private CA is
explicitly supplied. A private mock BusyBox client also covers HTTPS refusal
before any transfer, HTTP snapshot acceptance with correct trusted pins, and
rejection of wrong archive/manifest pins before parsing. The generic mocked
downloader-error fixture uses HTTP so it tests error propagation independently
of the HTTPS client capability gate. These fixtures are authored for the
isolated test environment and are not reported as executed.

## Check ownership and invalidation decisions

| Check / owner | Decision | Why / invalidation |
| --- | --- | --- |
| Trusted whole payload and manifest bytes, source acquisition | Retain/restore actual comparison before parser use | Expected text in a marker is not evidence; new artifact identity or verification schema invalidates reuse |
| Bootstrap helper pin, generated preseed | Check before dot-source | Executable bytes cross the first trust boundary; changed helper must match the embedded pin |
| Archive type/path/link/count/size/member inventory | Retain safety validation | Content identity and safe extraction establish different facts; do not collapse by unchecked extraction |
| Prepared-tree rendering | Retain existing single Perl batch; reuse prepared snapshot | Selected profile/account/layout, payload identity, renderer schema and late hardware values define validity |
| Destination/root ancestry | Retain at publication and mutation/use boundaries | Target ancestry is mutable even when source bytes are stable; a cached source check cannot authorize a replaced parent |
| Required Labwc source metadata | Consolidate in required-unit activation adapter | Exact owned files must exist with correct metadata before link mutation |
| Required Labwc enablement | Check after creation and at final readiness | First check owns the mutation; second catches changes by later stages before boot; compare exact installed-system path |
| Optional packaged services | Retain optional availability semantics | A missing optional package is different from a missing project-owned required unit |
| Profile membership | One registry plus exact owned env/class members | Creation/deletion no longer modifies thousands of source selectors; compile the full candidate before publication |
| Profile deletion references/recovery | Retain exact-member reference and transaction checks | Changed source/identity, failed writes or uncertain rollback invalidate acceptance; keep private recovery material |
| Final owned files, package audit, signed boot chain and initrds | Retain essential final checks | They occur after package/asset mutations and establish readiness, not merely source consistency |

The old `repo.env` contains 253,948 bytes and 2,855 assignments. Per-shell
caches already exist. It is incorrect to claim every lookup reloads the file.
The useful work to remove is redundant inventory-as-configuration, independent
loader initialization in new shells, and repeated linear lookup/orchestration,
while keeping operator policy and genuine configurable roots explicit.
The migrated file is 6,103 bytes and 113 assignments: four repository defaults
and 109 shared directory roots, with no per-file inventory. A mechanical
comparison found no changed value among all 113 retained keys after parent
expansion. Fixed source members belong to their callers; the compiler owns
`source-members.tsv` and the smaller APT selection table. The
[configuration ownership matrix](../implementation/installer-configuration-20261119.md)
records parser grammar, consumers, target/installer separation and the unchanged
profile/default precedence.

## Placeholder metadata disposition

The complete consumer search covered build capture, class compilation,
online/offline manifests and receipts, runtime hooks and scanner, Makefile
validation, developer validators, tests and changed-source audit coverage.
`catalog/placeholder-registry.json` has two developer reader groups:
`tools/validate_placeholder_registry.py` and the full-checkout tests
`test_placeholder_registry_contract.py` / `test_target_owned_scan.py`. None of
these requires the JSON to be a runtime payload member. The validator still
reads the authored JSON and checks that the TSV matches it.

`tools/build.py:SourceCapture` now excludes exactly that JSON member from shared
runtime capture. The audit's changed-source coverage uses the same exact
exception. `tools/offline.py:OfflineCapture` inherits the capture rule before
building the flat runtime snapshot; its compiled member set and manifest are
derived from that snapshot and have no independent JSON dependency. No offline
archive was regenerated for this change. Other catalog JSON and same-named
files at different physical members are unaffected.

The full 2,249,615-byte TSV remains in runtime capture. The base render hook
copies it to protected installer bootstrap state, and the finish hook passes
it to `scripts/common/target-owned-scan.awk`. Those consumers need exact token,
owner, source and source-scoped literal information, joined to the publication
record's phase. Removing columns
or substituting a smaller index without preserving those semantics is not
supported by this review. Source receipts, manifest authentication and compiled
membership continue to bind the retained runtime TSV.

Data-only comparison with the supplied source archive found both authored
files unchanged:

| Member | Bytes | SHA-256 | Runtime disposition |
| --- | ---: | --- | --- |
| `catalog/placeholder-registry.json` | 4,152,041 | `a14d1ffab8894c80c8c6bdb4800184e706395379a543b631cb0833f8482b52dc` | Excluded from runtime capture; retained in the full source tree and developer validation |
| `catalog/placeholder-registry.tsv` | 2,249,615 | `d84feaecf6f8d978629f94326c5a82503edd66d3104e62a5805317c4a445f388` | Retained completely as authenticated installer diagnostic data |

The direct reduction is 4,152,041 expanded source bytes. No elapsed-time or
compressed-size saving is claimed. Guarded capture fixtures now assert the
exact exclusion, retained TSV and other JSON members, unchanged authored
bytes, and manifest/receipt membership. They were authored and AST-parsed only;
native fixture execution remains deferred.

## Validation performed and remaining acceptance work

Performed for this report and its owned changes:

* Read repository instructions, isolation implementation, relevant source
  callers, supplied logs, receipts, and archive members as data.
* Parsed timestamps and counted bounded log events using Python standard
  library data operations; stored hashes and exact observations in the JSON.
* Inspected only tool availability: QEMU system executables, Podman, Docker,
  and proot were not available on `PATH`; `bwrap`, `unshare`, `chroot`, and
  `timeout` were available. No namespace/mount/capability probe or native
  isolation attempt was run as part of this evidence subtask.
* Parsed changed Python sources with `ast.parse`, without imports or execution:
  the profile manager, source-layout/build/module checkers, member-index fixtures,
  payload/diagnostic/APT/late-profile fixtures, and focused transport,
  configuration and desktop-enablement tests. An AST data scan found no fixed
  source path still used as a selector/configuration dictionary key outside
  separately owned asset/package fixtures.
* Compared all six changed `AGENTS.md` isolation preambles with the supplied
  archive: preserved. The authorized edits replace design rules for file
  aliases and stable local constants, not isolation or security boundaries.
* Ran `/bin/sh -n` on the changed desktop services source and finish readiness
  hook. This is syntax evidence only.

All analysis scratch was confined to private disk-backed
`.build/validation/evidence/` with `TMPDIR`, `TMP`, and `TEMP` directed there.
The initial scratch filesystem was verified as overlayfs. No host `/tmp`,
memory-backed scratch, package state, service manager, network configuration,
device, credential store, or user data was used for tests.

The existing isolation guard is stricter than merely starting a process with
`chroot` or a temporary directory. It requires an identified disposable
rootless image, private namespace ownership, no mapped outer root UID, dropped
capabilities, no host mounts, a read-only overlay image root, private guest
filesystems, private procfs, a loopback-only private network, and the dedicated
test init. No compatible target image is attached. Tool availability alone is
not proof that this boundary can be established. The guard has not been
disabled or bypassed, and no host fallback is acceptable.

Full build and changed-file-audit results belong to the integration delivery
record, because other agents edit their inputs. The report does not infer a
passing build, native test, installation, or first boot from source syntax.

### Comparable measurement plan and budgets

For a valid before/after comparison, preserve the exact suite, architecture,
package versions/set, selected role/profile, storage layout, kernel/NVIDIA
variant, Secure Boot policy, memory/vCPU/disk resources, and network/cache
conditions. Preserve the historical full desktop plus legacy GPU/CUDA scenario
as one scenario, but establish its matching baseline source first. Keep a
server, desktop-base, and supported architecture/profile path in coverage;
unsupported combinations must fail explicitly rather than silently change the
selected software.

Run cold and warm conditions separately. A warm filesystem/package cache
result is not comparable to a cold installer. Capture exclusive stage starts,
ends and status, package import/index/APT barrier timings, DKMS and initramfs
events, aggregate child-process counts, and bytes downloaded/read/written or
hashed where an isolated fixture can observe them. Use stage-level counters and
coarse resource samples, not per-asset diagnostic subprocesses. Do not put
download URLs with credentials, environment dumps, or secrets in the timing
record.

No new wall-time target is assigned without those runs. Existing hard timeouts
remain safety limits, not promised budgets. Initial regression budgets should
be structural: one unchanged `.deb` inspection per owning batch; one index and
APT update per compatible imported batch; bounded interpreter launches per
asset batch; no extra whole-source scans; retained final boot/service/package
checks. After repeated controlled runs, set wall-time budgets from observed
distributions and include variability. DKMS, package unpack/configuration,
network variability, optional tool bootstrap and final firstboot readiness
remain material costs even after redundant installer orchestration is removed.

# Installed-target `usr` implementation and validation report

Date: 2026-11-19

Scope: continued optimization, deduplication and wiring review of
`d-i/debian/hooks/target/usr/**`, integrated with the first-round installer work.

Current generated release:
`4ee3bda3b1fad62258b6b791a5ff90c7e4f8a4366913d22c18673a1a2c733150`

## Result and acceptance status

The second round reduces repeated metadata commands, file reads, package
inspection and hashing; binds Appearance candidates to the bytes used to
prepare them; fixes shared hardware CLI ownership for server installation;
consolidates compatible Perl status decoding; and removes an identical login
background source. The existing feature selections and first-round installer
work remain in the checkout.

**Both reviewed `make build` runs succeeded, and all 12 suite products were
byte-identical across the two builds. The required overall static audit remains
FAIL because BusyBox and ShellCheck are unavailable. Native tests and runtime
acceptance remain unverified.** Missing checkers are not counted as passing.
Final audit counts and command output are recorded in
[target-usr-delivery-validation-20261119.json](docs/validation/target-usr-delivery-validation-20261119.json)
and [target-usr-delivery-commands-20261119.txt](docs/validation/target-usr-delivery-commands-20261119.txt).

The earlier [IMPLEMENTATION_20261119.md](IMPLEMENTATION_20261119.md) remains the
historical first-round report. Its measurements, baseline identities and
limitations are preserved. This report identifies the newer release and the
additional changes, rather than retroactively treating earlier products or
logs as evidence for it.

The supplied `offline/payload.tar.gz` remains an unchanged historical artifact.
**It is not the current rebuilt installer.** Use the regenerated
`d-i/forky/` or `d-i/trixie/` suite products when validating this release. The
existing offline acquisition adapter changes are retained, but the separate
offline archive has not been regenerated.

## Measured source and payload sizes

These figures come from file/archive inspection and build comparison. They
measure bytes and membership, not installation or application execution time.
The payload figures describe one shared payload, not the sum of both suite
copies.

| Snapshot | Compressed payload bytes | Expanded payload bytes | Members |
|---|---:|---:|---:|
| Original supplied normal payload | 11,923,852 | 40,306,051 | 2,433 |
| First-round regenerated payload | 11,788,150 | 36,150,412 | 2,434 |
| Current second-round payload | 10,267,881 | 34,621,032 | 2,433 |

Compared with round one, the current payload is **1,520,269 compressed bytes
smaller (12.897%)** and **1,529,380 expanded bytes smaller (4.231%)**. Compared
with the original normal payload, the reductions are **1,655,971 compressed
bytes (13.888%)** and **5,685,019 expanded bytes (14.105%)**. Membership totals
alone do not describe which files changed; the generated manifest and release
identity remain authoritative.

Current payload SHA-256:
`bb9f1fe4c9c2d38e235bdb789a034fbc39c9b4a487408a43aa7cdfdfe2eae617`

| Authored `hooks/target/usr` source inventory | Files | Source bytes |
|---|---:|---:|
| Start of this round | 671 | 12,799,276 |
| Current | 670 | 11,269,053 |
| Net reduction | 1 | 1,530,223 |

The source-byte reduction is 11.956%. The initial exact-duplicate inventory
found the same 1,545,015-byte JPEG at
`usr/share/backgrounds/login/lock-6000x4000.jpeg` and
`usr/share/backgrounds/login/welcome-6000x4000.jpeg`. The retained lock image
now supplies both the lock-screen and login-screen source selections in
`hosts/themes/base.env`. The image bytes did not need transformation. The
current `usr` inventory has **no remaining byte-identical file pairs**.
Additional implementation changes mean the net source-byte reduction is
smaller than that one removed image's size. The lock-screen and login-screen
selectors remain independent, so either can still select a different image.

Installer wallpaper staging now publishes each distinct `(source, destination)`
pair once. A different source or destination remains a separate publication;
the helper does not collapse independent custom selections.

The delivered validation JSON preserves the source/payload measurements,
baseline identities and reproducibility hashes. The generated suite receipt
contains the complete captured runtime membership.

## Whole-tree static coverage

The inventory and declared wiring checks span the full current authored `usr`
tree, including common, desktop and server source families. Role-selected
source membership is distinct from the set actually installed for one profile.

| Static check | Coverage/result | What it establishes |
|---|---|---|
| Physical `usr` inventory | 670 files | Current file membership and byte totals |
| Exact duplicate content | No remaining file pairs | No complete byte-identical source-file duplicates in that inventory |
| Python module ownership | 98 modules, 261 managed import references | Declared local imports resolve to their source owners; ten references resolve through package exports |
| Python ambiguity/parse checks | No unresolved imports, duplicate owners or parse errors in the recorded graph | Static module and exported-name resolution for the recorded inputs |
| Perl package ownership | 160 packages, 339 managed import references | Declared managed imports resolve; no unresolved references in the recorded graph |
| Logical destination map | 670 destinations, no collisions | Default path expansion and role-directory flattening have no recorded conflicting destinations |
| Explicit desktop/D-Bus launcher references | 31 references | Thirty have source-owned executable producers; one has an identified vendor release producer |

The vendor-produced launcher is
`/usr/local/bin/com.github.dahenson.agenda`. Its desktop entry is bound to
`install_agenda_release` in `scripts/desktop/calendar-install.py`, including
the existing `INSTALL_BINARY` publication contract and profile pin. It was not
silently treated as an unresolved source file or assumed to be supplied by an
unrelated package.

These are static declarations and default-path checks. They do not execute
imports, resolve every possible dynamic dispatch, validate external Python or
Perl dependencies on a target, prove native ABI availability, or establish
that every service and launcher runs. The inventory does not mean every branch
of every file received equally deep review. Detailed review concentrated on
the changed paths, their actual consumers and the adjacent trust/lifecycle
boundaries. The graph results are included under `managed_module_wiring` and
`entrypoint_wiring` in the delivered validation JSON.

## Desktop Appearance: fewer reads and stronger preparation checks

Five existing modules under
`usr/local/lib/desktop/python3/dist-packages/labwc_appearance/` changed:
`fields.py`, `transaction.py`, `engine.py`, `greeter.py` and `wallpaper.py`.
Their entry points, installed module set, account/root split and AppArmor
permissions remain the same.

The authored registry has 567 fields and 672 mappings. Of these, 573 user
mappings refer to 36 user paths; 99 mappings refer to greeter files. The
following counts are derived from the source paths and authored registry:

| Appearance operation | Previous path | Current path |
|---|---:|---:|
| Read current values when first-choice mappings are readable and fit the cache | 567 reads/decodes | 38 unique reads/decodes |
| Prepare all user field values | 1,719 variant probes plus a reread of each present grouped file | 108 unique variant reads, reused for rendering |
| User-only field apply: user-process registry loads | 3 | 1 |
| Apply including greeter request: user-process registry loads | 4 | 1 |
| Apply including greeter and dock shutdown: user-process registry loads | 5 | 1 |
| Authenticated root field helper: root registry loads | 1 | 1 |

The current-values cache lasts for one invocation. It uses a bounded LRU with
an 8,388,608-unit accounting budget; an entry is charged for its input bytes
and decoded line overhead. That accounting is not a measurement of Python
heap allocation. Missing/error inputs are local misses, and eviction or an
oversized working set leads to fresh reads. The authored first-choice files
fit the budget, but user customizations and fallback mappings can change the
actual counts.

The reliability fix is separate from that reuse. Previously a renderer could
prepare from one version of a file while `transaction.plan` later accepted a
different version as its rollback baseline. All seven runtime planner calls
now pass exact expected input bytes, including expected absence and no-op
candidates. A fresh guarded read must agree before the journal and candidate
configuration publication proceed. Candidate and expected key sets must match.

The dock stop remains a distinct lifecycle boundary. After QSettings shutdown,
the affected inputs are read and rendered again so legitimate layout saves are
preserved in candidate and rollback images. Apply, rollback and committed
verification still obtain fresh evidence. The authenticated root helper loads
its own trusted registry; a user-process cache never becomes root authority.
Wallpaper's immutable image preparation still precedes the CSS transaction,
so the CSS preparation check is not described as an image-staging rollback.

The existing event-driven output, session-state and Waybar helpers were also
reviewed. Their coalescing and session-close behavior did not justify another
lifecycle change in this pass. The full source counts, call graph and authored
fixture cases are in
[desktop-appearance-inputs-20261119.md](docs/validation/desktop-appearance-inputs-20261119.md).

## Package servicing and publication

This round changes two installed owners:

- `usr/local/lib/common/perl5/site_perl/apt-repo-local/APTRepoLocal/Servicing/Deb.pm`
- `usr/local/libexec/common/apt-repo-local.tmpl`

The first-round seven-package desktop transaction, separate SCX transaction
and existing four-vendor adopted transaction remain. Package selections,
dependency policy, configured package ceilings, package-manager options,
signing format and repository index format are unchanged.

| Servicing operation | Previous round-one path | Current path |
|---|---:|---:|
| Fresh Perl package validation including payload | 5 `dpkg-deb` calls | 2: one control read and one payload listing |
| Perl metadata-only validation | 4 `dpkg-deb` calls | 1 |
| Required-member lookups | A listing split/scan for each lookup | One scan, retaining requested-member records only |
| Installed status/version queries | 2 | 1 |
| Python refresh or interactive-add inspection of unchanged protected input | Two control reads, two listings, two Debian-version validations | One of each |
| Separate interactive-add upstream SHA-256 read | 1 | 0; digest comes from the protected staging copy |
| Separate signed-output SHA-256 reread | 1 complete signed archive | 0 |
| Separate transformed-input SHA-256 reread | 1 complete transformed archive | 0 |

If `S` is the complete signed archive size and `T` is the transformed unsigned
archive size, signing removes `S` bytes of separate SHA-256 reads for an
unchanged input, or `S + T` when rewriting was required. The mandatory copy
updates one digest state; its pre-signature state identifies the unsigned
prefix and its final state includes the appended ar header, clear signature
and any odd-length padding. Required copies, dpkg-sig member hashing, GPG,
transformed-output inspection, existing pool-object checks and retained
upstream-object checks remain.

The named Perl control parser rejects malformed, duplicate case-insensitive,
NUL/CR-bearing and oversized metadata. Required-member uniqueness, executable
checks, supported symlinks and CLI-only desktop handling are preserved.
Hardlink declarations cannot satisfy required-member checks. The old
cross-call listing cache based on pathname and second-resolution timestamps
was removed; independent validations intentionally obtain fresh inventory.

Python reuse is confined to protected snapshots copied by the current
repository process. It binds device, inode, size, nanosecond mtime/ctime and
the exact required-member tuple, and checks identity before and after
inspection. Independent deliveries and transformed outputs receive fresh
inspection. Returned dictionaries cannot mutate the stored inspection result.

Refresh prepares and validates an inactive `.part` before activation. A
controlled rename must preserve the expected identity before cached evidence
can follow it. Failure after activation revokes that evidence and isolates the
ready object and sidecar under a non-watchable failure name. Failure to isolate
is `OutcomeUnknown`, with retained paths, rather than an ordinary upstream
error that permits continuing. Original, transformed and signed identities
remain distinct; source replacement, mutation and short/failed writes are
checked at the corresponding boundaries.

The three affected fixture files contain 67 guarded test methods in the
recorded related classes, with 22 methods newly authored in round two. None
were executed. See the complete package handoff in
[runtime-package-servicing-20261119.md](docs/validation/runtime-package-servicing-20261119.md).

## Common/server observations and hardware wiring

The common/server pass initially inventoried 159 files and then reviewed 32
additional common Python, hardware and install-tools files. Its counts are
specific to the operations below; they are not totals for every installer or
target process.

| Runtime observation | Previous work | Current work |
|---|---:|---:|
| Matching NVMe endpoint link evidence | 10 attribute reads | 7 |
| Fixed kernel device-root resolution | Once per PCI entry | Once per nonempty report |
| Successful server stopped-state host gate | 2 `systemctl show` processes | 1 named-property query |
| SSH context directory metadata | 14 `find` processes | 7 |
| SSH context metadata including three identity files | 17 `find` processes | 10 |
| Hardware report current values for four comparisons plus display | Up to 5 reads/control/report | At most 1 display/count read/control/report |

The NVMe reporter reuses the same observed values for nested evidence and its
three compatibility fields, including unavailable values. It retains PCI
selection, containment, root ownership, no-follow and size checks. It does not
write hardware state or declare health verified.

The server maintenance gate requests `ActiveState` and `MainPID` together,
accepts either named-property order, and rejects incomplete, duplicate or
unknown properties. Only the existing stopped states with a zero main PID
pass. Technitium's independent guest-stopped check remains after the host
gate. An active-state rejection previously needed only one query and still
does; the table's reduction applies to the path that reaches both properties.

SSH directory owner and mode come from one strict observation per directory.
The account/home relationship, private modes, file link counts, runtime
directory and agent socket checks remain. Failed or ambiguous metadata cannot
authorize the context.

Hardware display/count observations are local to `Engine.report()`. Planning
continues using fresh paired bounds, governor/EPP and ownership checks.
Apply/reset/health, write/readback, thermal checks and recovery-journal reads
are unchanged. Unavailable report values remain errors; no numeric defaults
are invented. A new report obtains new evidence.

The server wiring correction is reachable in the three authored
`btrfs-srv-flex`, `btrfs-srv-flex-duo` and `btrfs-srv-flex-trio` profiles, which
enable Intel tuning. Their shared installer selected a CLI physically owned
by the desktop family. The family guard rejected that source under server.
The neutral wrapper now resides in `usr/local/bin/common/` and keeps the same
installed `labwc-hardware-tuning` name, content and mode. The staging caller,
fixture map and registry membership were updated. The family guard and
AppArmor permissions were not widened.

The common/server work adds 23 guarded test methods, all unexecuted. Its
report includes exact changed paths and preservation of the separate
install-tools signature, decompression, mount and boot boundaries:
[runtime-common-server-audit-20261119.md](docs/validation/runtime-common-server-audit-20261119.md).

## Shared Perl status decoding and its confinement exception

`Managed::Process::status_from_wait` is now the shared exit-code decoder used
by seven existing adapters: Android ADB, network control, network scan,
security commands, scanner logging, Timeshift commands and Zram mapper setup.
The shared capture API continues returning raw wait status. Adapters decode
only at their public exit-code boundary, retaining their result shapes and
compatibility entry points. Failed/missing waits remain failures and signal
termination remains distinguishable from successful exit.

The standalone ChatGPT log runner deliberately keeps its three-line decoder.
Its narrowly confined AppArmor domain does not grant the shared runtime module
read permission. Importing the shared module solely to remove those lines
would require widening that domain. The local equivalent is therefore
retained, with no policy change. Eliminating complete duplicate source files
does not require eliminating every small intentional code repetition across
distinct confinement boundaries.

## First-round work retained

The continued runtime review does not replace the earlier installer design.
The current products retain:

- The seven-package desktop batch, separate SCX barrier, protected copy and
  publication ordering, post-install readiness, and retained uncertain-state
  markers.
- The single existing Perl renderer's bounded publication batches, dependency
  flushes, source reuse and exact-key ownership journal, with direct target
  consumers still behind publication barriers.
- Restricted `repo.env` assignment-data parsing and shared directory/default
  ownership, without restoring the removed per-file selector inventory.
  Build membership checks and the small compiled APT asset table remain.
- Trusted bootstrap-source, payload archive and manifest SHA-256 verification,
  versioned verification receipts, and the corresponding local/offline copy
  integrity checks.
- Certificate-verifying GNU wget plus configured CA trust for requested
  HTTPS; BusyBox HTTPS remains rejected. Explicit HTTP/local acquisition is
  still protected by trusted artifact pins. Trust in the initial preseed
  remains an operator/deployment responsibility.
- Required service readiness at the owning post-enable/final boundaries,
  including the corrected Labwc verification ordering and exact link targets.
- Exclusion of the developer-only placeholder-registry JSON from runtime
  payload capture, while retaining the authored JSON, developer validation and
  full runtime TSV ownership data.

The original failed-install logs remain historical evidence. No timing in
those logs is relabeled as a measurement of this release, and nested stage
durations are not added to parent durations. The detailed earlier evidence is
preserved in
[installer-performance-evidence-20261119.md](docs/validation/installer-performance-evidence-20261119.md),
[asset-publication-20261119.md](docs/validation/asset-publication-20261119.md) and
[installer-configuration-20261119.md](docs/implementation/installer-configuration-20261119.md).

## Executed validation and remaining limits

| Evidence | Recorded result |
|---|---|
| Reviewed pure build, first run | Succeeded for forky and trixie at the release identity above |
| Reviewed pure build, second run | Succeeded at the same identity |
| Reproducibility comparison | All 12 products byte-identical; no changed product |
| Placeholder ownership refresh | 3,634 production tokens and registry entries; 734 canonical render fields; no missing or unowned production tokens |
| Generated payload/source checks | 2,433 runtime members, 2,257 source-equality comparisons and 208 frontend-equality comparisons |
| Prepared-input consistency | Seven prepared-input checks in the integration record |
| Changed-file checks | 60 changed surviving files; 25 Python AST parses, five direct shell syntax parses and ten structured files; no findings in available checks |
| Embedded and generated shell syntax | 117 embedded installer-shell parses and 16 generated preseed-shell parses with the available interpreter |
| Required overall audit | **FAIL**: four unavailable BusyBox/ShellCheck gates remain blocking |
| Native tests, imports, Perl loading/compilation, service or installer execution | **Not executed** |
| Runtime, boot, security-policy and performance acceptance | **Unverified** |

The 12 compared products are each suite's `payload.tar.gz`,
`payload.manifest`, `source.sh`, `receipt.json`, `support-matrix.json` and
`preseed.cfg`. Repeat serialization demonstrates reproducible products for
these inputs; it does not prove target installation success.

Two stale `.pyc` files inherited byte-for-byte from the original ZIP were
removed during integration cleanup. They were not produced by importing or
executing repository code in this pass. Native execution remains subject to
[docs/test-isolation.md](docs/test-isolation.md), with no development-host
fallback and no weakened guard. All host scratch and evidence were kept in
the private, disk-backed checkout validation trees.

Future acceptance requires the separately reviewed disposable environment:
execute the guarded fixtures, exercise service and publication failures,
validate the installed confinement and launcher paths, and run an installer
and firstboot trial for the supported profile. Any timing comparison must
identify the exact release, image, workload and hardware and use comparable
stage boundaries. Until that evidence exists, the report claims the measured
artifact reductions and the explicit source-derived work reductions above,
without claiming a measured runtime speedup or a fully validated installation.

## Delivery contents and comparison baselines

The complete source ZIP contains the current authored tree, both regenerated
suite product sets, the historical first-round evidence and this round's
validation reports. Private transfer/build scratch and interpreter caches are
excluded. The separate authored patch compares against the originally supplied
ZIP and includes authored additions, edits and deletions, including the removed
JPEG. The twelve generated suite products are supplied in the ZIP and excluded
from the authored patch; rebuild them through the existing pure serializer.

The delivered cumulative manifest is
[changed-paths-round2-20261119.tsv](docs/validation/changed-paths-round2-20261119.tsv).
The incremental manifest against the immutable first-round delivery is
[target-usr-changed-paths-20261119.tsv](docs/validation/target-usr-changed-paths-20261119.tsv).
Both record regular-file additions, modifications and deletions, with private
scratch and generated interpreter caches excluded. The original first-round
manifest remains a historical record rather than a current tree description.

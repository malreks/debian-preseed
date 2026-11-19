# Installer implementation and validation report

Date: 2026-11-19

> Historical first-round record. The continued target-runtime review and newer
> generated release are documented in
> [IMPLEMENTATION_TARGET_USR_20261119.md](IMPLEMENTATION_TARGET_USR_20261119.md).
> The evidence, identities and limitations below are preserved for that earlier
> implementation round.

Input: the attached debian-preseed.zip, extracted as debian-preseed.bak.

Authority: current authored sources; historical logs are evidence, not acceptance of this revision.

## Result

Implemented package batching, shared Perl asset publication, restricted repository configuration, actual preseed/payload integrity verification, and required desktop service readiness. Both suite products are regenerated through the reviewed make build serializer. This delivery is an implementation with partial validation, not a successful-installation acceptance record.

The complete codebase retains its original directory name. The delivery includes an exact changed-path manifest and a focused authored-source patch. Generated payloads are supplied in the archive and must be regenerated, rather than patched manually.

The final generated identities, size comparisons, reproducibility result, and executed audit outcome are recorded in [delivery-validation-20261119.json](docs/validation/delivery-validation-20261119.json). The final command output is in [delivery-commands-20261119.txt](docs/validation/delivery-commands-20261119.txt).

## Important validation and compatibility limits

The required audit remains a failure when BusyBox or ShellCheck is missing. Available Python AST, shell syntax, decoded preseed, structured-data and cross-component checks still run and report their own results; no missing checker is treated as passing. Native tests, Perl compile/import, package operations, installer replay and full installation were not executed because no approved disposable image/runtime was available. The repository's existing isolation guard and prohibitions are retained.

The supplied offline/payload.tar.gz is an older historical product and remains unchanged. **Do not use that file as the rebuilt installer.** Its release differs from both the supplied normal products and this implementation. The offline generator and authenticated flat-tree adapter are updated, but the standalone bundle was not regenerated: producing its download catalogs requires a usable repository metadata snapshot/acquisition environment. Use the regenerated d-i/forky or d-i/trixie products for validation of this change. Local file-based acquisition of those normal payloads remains supported.

HTTPS requires certificate-verifying GNU wget and appropriate CA trust in the installer image. BusyBox's internal TLS implementation is not accepted for a requested HTTPS transfer. Local files and explicitly selected HTTP sources remain supported, with executable source, archive and manifest bytes checked against trusted preseed pins. Trust in the first preseed is still an operator/deployment responsibility. No automatic trust-package installation or insecure retry was added.

The existing support matrix and explicit unsupported combinations remain the authority. Source generation for a tuple is not evidence of runtime acceptance. No package, profile, software feature, Secure Boot rule, confinement policy or required firstboot task was intentionally removed.

## Actual baseline and remaining expensive work

The supplied failed run spans 6,463 seconds (107m43s); late dispatch spans 4,131 seconds (68m51s). These are historical observations, not measurements of the edited source. The exact failed-run release is absent from the supplied archive/history. An older offline snapshot demonstrates the same pre-enablement verification ordering problem, but is not byte-identical to the failed-run release.

| Supplied-log interval | Observed duration | Interpretation |
| --- | ---: | --- |
| Complete failed run | 107m43s | Includes failure and all preceding work |
| Late dispatch | 68m51s | Parent interval; do not add its children again |
| Main pkgsel menu interval | 31m23s | Heavy package configuration and triggers |
| Vendor software late stage | 24m29s | Download, inspection, local repository and application work |
| Desktop session late stage | 16m02s | Asset publication/configuration; ends in failure |
| Desktop storage late stage | 12m59s | Storage/security/boot-related work |
| DevOps late stage | 4m57s | Required tooling/configuration |

The supplied syslog also contains a 161-second, roughly 10.3 GB download, approximately 438 seconds of NVIDIA module build before signing, three initramfs generation announcements, eight deferral records and 41 trigger records. These events overlap enclosing stages. They are not independent additions to the total.

Package configuration, DKMS/kernel signing, storage/security initialization and network acquisition remain substantial. Existing trigger deferrals and final readiness are retained. There is no new maintainer-script bypass, unvalidated prebuilt-module shortcut, blanket initramfs suppression or transfer of required work to firstboot.

See [the evidence report](docs/validation/installer-performance-evidence-20261119.md) and its JSON companion for the full phase/dependency/interpreter/target-boundary table, timestamps, source hashes, revision reconciliation and measurement protocol.

## Package architecture and source-derived work counts

Seven compatible downloaded desktop packages now form one private plan: Bitwarden, QoreDB, Obsidian, Tomat, Sleek, Zoom and Filen. Their preparation remains serialized. The importer validates every package, then publishes one repository generation; one APT update and one APT install follow. Application-specific finish checks run after that installation barrier. SCX scheduler/loader have a separate two-package barrier. ChatGPT bootstrap and the existing adopted-vendor transaction retain their distinct dependencies.

The importer records the input digest during its protected snapshot copy. Its reuse is process-local and tied to device/inode/size/mtime/ctime. Package content and required members are inspected once, from the same validated input. Signed/repackaged/published bytes have separate identities and verification. Retained pool objects are verified by content, and signing-key changes cause actual re-signing.

| Work for the seven-package group | Supplied source | Implemented source |
| --- | ---: | ---: |
| dpkg-deb contents listings | 24 | 7 |
| dpkg-deb metadata invocations | 28 | 7 |
| dpkg-deb info invocations | 7 | 0 |
| Importer index publications | 7 | 1 |
| Immediate forced extra rebuilds | 7 | 0 |
| Local APT updates | 7 | 1 |
| APT install transactions | 7 | 1 |
| Installed status/version queries | 7 status + 3 version | 1 combined query |
| Extra complete upstream SHA-256 reads, beyond required snapshot copies | 17 | 0 |

The eliminated extra upstream read volume is twice the sum of the seven input sizes, plus the QoreDB, Obsidian and Sleek sizes. The required seven snapshot copies still read the inputs once and now hash during those copies. These are source-derived operation counts, not observed elapsed time or a global count of all installer processes.

Ledger's hex and base64 SHA-512 representations come from one digest stream. Upstream and transformed artifact evidence remains distinct.

An active batch marker is claimed before repository mutation. Preparation and signed scratch use non-watchable .part objects. Ordinary pre-publication failures clean only owned staging; uncertain publication, APT or readiness failures retain the plan, receipt, marker and evidence. Automatic replay is refused after an uncertain side effect. The marker is cleared only after installed-state readiness succeeds.

## Asset architecture and shell-to-Perl migration

The existing scripts/common/render.pl remains the one renderer. Its publication mode accepts a bounded, length-prefixed declarative plan containing source, destination, operation, mode, ownership, role, suite, phase and dependency group. Thin shell adapters collect records and flush at the points where target commands or direct file readers require the results.

Each nonempty flush launches target Perl once, loads the existing prepared-member inventory and canonical path map once, reads each distinct selected source once, prepares every candidate, then publishes files atomically. The code uses perl-base modules; it adds neither full Perl nor a CPAN/bootstrap transaction. Early d-i, preseed and partman stay in their shell/AWK runtime.

The shared target_exec boundary flushes before ordinary, quiet, captured, tested, interactive and direct target commands. Explicit barriers also precede direct shell normalization/readers. Hardware-dependent rendering stays behind its existing typed boundary until its inputs are known.

Destination ancestry, direct-file metadata, symlink/hardlink defenses, modes and ownership are revalidated at publication. Candidate files, affected directories and recovery plans have an explicit durability boundary. A batch is atomic per destination, not a filesystem transaction; partial mutation retains evidence and is not described as rollback.

Primary-account values are captured before conversion to future-account HOME/USER templates. Waypaper uses the existing primary-default publisher with an exact relative-file selection for its user-owned launcher. User-owned helper documentation keeps its dedicated, constrained publication path. These cases do not relax the root-owned shared batch policy.

Per-destination hashed ownership filenames are replaced by an exact-key journal and bounded last-write-wins snapshot. The old hash identified a pathname; it was not a content-integrity check. The final mutable-target validation remains.

See [the asset publication record](docs/validation/asset-publication-20261119.md) for the exact changed owners, schema/bounds, barriers, failure handling and numeric telemetry. Counts include records, unique source reads/bytes, written/reused files, destination comparison bytes and elapsed whole seconds per batch. They contain no configuration values or secret material.

## Repository configuration and consumers

repo.env shrank from 253,948 bytes and 2,855 assignments to 6,103 bytes and 113 assignments: four repository defaults and 109 shared directory roots. All retained values were compared with the supplied source and remain unchanged after expansion. This is a 97.6% source-byte reduction; the old implementation already had per-shell caches, so it is not a claim that every old lookup reread the whole file.

One restricted data loader replaces separate repository loaders. It accepts the exact supported vocabulary, parent-first references and safe relative roots, and rejects duplicate, missing, unknown or executable forms before assigning values. The build uses a matching restricted grammar. Repository configuration is never shell-evaluated or installed as a target runtime dependency.

| Contract | Owner and current consumers | Publication |
| --- | --- | --- |
| repo.env | Repository defaults/shared source roots; early loaders, compiler, profile and offline tools | Authenticated installer input only |
| hooks/installer/di.env | d-i mount, phase state, temporary paths and log locations | Private installer context |
| hosts/installer/runtime.env | Concrete installed-system paths and runtime policy | Rendered into selected installed assets |
| Host profiles/themes | Selection, supported overrides, policy and appearance | Selected prepared inputs and concrete target assets |
| Fixed source member names | Owning callers and phase dispatch | Root-relative literal interfaces; build checks membership |
| source-members.tsv | Compiler-generated family/suite membership metadata, static audits and inspection | Generated payload metadata; runtime publication reuses prepared-members |
| apt-assets.tsv | Compiler-selected suite/family/kind/leaf/member table | Small runtime APT selection input |
| Credentials | Existing protected secret-input channel | Only the necessary protected consumer; never public catalogs |

The profile manager creates/deletes actual owned profile/class/registry records and no longer rewrites repository FILE aliases. Build, offline tooling, diagnostics, validators and affected fixtures are migrated. The six applicable AGENTS design sections permit stable local interfaces while preserving isolation, credentials, ownership and target-boundary rules.

The 4,152,041-byte placeholder-registry.json remains unchanged in the full checkout for developer validation, but is excluded from the runtime payload by exact member path. The 2,249,615-byte TSV remains fully present for base/final runtime diagnostics. No registry coverage was discarded.

The full [consumer matrix and configuration rationale](docs/implementation/installer-configuration-20261119.md) documents creators, readers, validators, exporters/renderers, publication boundaries and invalidation.

## Verification ownership decisions

| Check and former callers | Decision and cost removed | Owning boundary / invalidation |
| --- | --- | --- |
| Repository loading in preseed/bootstrap/common adapters | Consolidate parser; remove large FILE inventory and parallel validators | Whole small data input; new shell or changed selected configuration reloads it |
| Fixed source existence/catalog coverage | Move exhaustive coverage to compiler/static audit; use prepared member keys in batches | Changed captured source or compiler identity requires rebuild |
| Logical role/suite source lookup for asset wrappers | Resolve once in memory per batch; reject ambiguity | New role, suite, batch context or source identity requires new resolution |
| Repeated source reads and scalar/block rendering per asset | One distinct-source read and in-process rendering per flush | Flush ends reuse; hardware-dependent values remain deferred |
| Destination ancestry/metadata in wrappers and publisher | Consolidate in owning publisher; retain mutation-time rechecks | A mutable destination/ancestor cannot reuse source validation |
| Ownership record path hash and per-file temporary record | Exact-key journal plus one snapshot/import | Incomplete/malformed journal or failed import invalidates completion |
| Bootstrap source expected digest | Restore actual comparison before execution | Changed helper/release requires matching trusted pin |
| Archive/manifest expected digests | Restore actual byte comparison before parser use | Changed artifact or verified-v1 schema invalidates receipt reuse |
| Archive names/types/limits/extraction | Retain three existing tar/decompression passes | These establish safe extraction; early BusyBox parity for fewer passes is unverified |
| Flat offline source copies | Verify each protected copy against authenticated manifest | Flat trees have no whole authenticated archive; size alone is insufficient |
| Package repeated listings/metadata/wrapper hashes | Consolidate one contents/metadata inspection and hash during required copy | Input inode/size/timestamps or expected identity changes invalidate process-local reuse |
| Signed/repackaged bytes and retained pool objects | Retain distinct content checks | Transformation or signing-key change requires new evidence |
| Per-package repo refresh and APT transaction | One compatible plan, generation and serialized installation barrier | Changed repository generation refreshes indexes; side effects/uncertainty prevent replay |
| Final installed package and required executable checks | One combined installed query, retained application readiness | Runs after APT mutation; exact published version/arch/status required |
| Required Labwc units | Mandatory metadata before enablement, links after enablement and final readiness | Later target mutation warrants the separate final check |
| Full placeholder JSON at runtime | Exclude unused developer metadata only | Authored JSON and its validator remain; runtime TSV diagnostics retained |
| Boot/kernel/signing/initramfs/account/confinement readiness | Retain essential checks | Source identity is not evidence of final mutable-system readiness |

## Commands and evidence classifications

The executed generation command is make build, with a hard 120-second timeout and TMPDIR, TMP and TEMP set to a private disk-backed directory under .build/validation. It only serializes the authorized flat suite products. It does not execute installer hooks or tests.

The executed required static command is:

    timeout 180 python3 -B tools/post_change_check.py --baseline-zip /path/to/original/debian-preseed.zip

The new baseline option compares the immutable supplied ZIP with existing regular checkout files, because the archive has no Git metadata. It performs real git diff --no-index --check on changed text in private scratch. It does not create a synthetic commit. Without this option, the existing Git working-tree mode remains.

No make test, make check, make validate, unittest discovery, repository test import, Perl -c/import, dpkg/APT operation, service control or installer entrypoint was run on the host. Focused guarded fixtures were authored and updated for the changed behavior and failure boundaries. They remain **unexecuted** until an approved environment is supplied.

For reproducibility, compare all twelve suite product byte hashes across consecutive builds with unchanged captured inputs. The final JSON record reports that comparison separately from runtime acceptance. The final audit log reports its exact exit status and any remaining findings; do not infer PASS from the build result.

## Next acceptance work

Use a disposable identified image with the repository's isolation guard, private disk scratch and bounded cleanup. Run the focused renderer/root-boundary, package-batch, repository-configuration/transport, bootstrap-portability, diagnostics, late-install and profile tests. Exercise both suites, applicable amd64/arm64 and desktop/server contexts, local/HTTP/verified-HTTPS and newly generated offline media.

Before/after performance runs must use the same machine/VM resources, selected profile, package/kernel set and network/cache state. Keep cold and warm runs separate. Record successful install completion and firstboot readiness before comparing totals. Use batch counters and stage-level wall/CPU/I/O/transaction/DKMS/initramfs observations; do not add nested stages. Set stage budgets only after comparable successful runs. No final installation duration or percentage speedup is asserted here.

## External implementation references

- Debian Trixie perl-base file list: https://packages.debian.org/trixie/amd64/perl-base/filelist
- Debian Forky perl-base file list: https://packages.debian.org/forky/amd64/perl-base/filelist
- Debian BusyBox wget source (internal TLS and OpenSSL fallback): https://sources.debian.org/src/busybox/1:1.37.0-10.1/networking/wget.c

These establish package/module or implementation facts. They do not establish which image/runtime was booted in this workspace.

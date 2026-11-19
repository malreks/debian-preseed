# Pre-pkgsel stage-record repair, 2026-11-19

The reported `50-class-plan.sh:10 ... invalid pre-pkgsel stage record` failure
comes from a format mismatch. The compiler and frozen plan carry physical source
members, while the dispatcher still applied an old environment-selector character
allow-list to the entire record. Every ordinary provider path contains `/`, which
that check rejected before the first provider could start. The original dispatcher
was reproduced failing with that exact message inside a disposable Debian guest.

For example, this is a valid current record:

```text
stage	installer.firmware|pre-pkgsel|hooks/installer/pre-pkgsel.d/49nvidia-opt-in-firmware.sh
```

The TSV has two columns; the second column has three pipe-separated fields. The
stage ID, phase, and repository member have different grammars. They must not be
validated as one shell identifier.

The repair introduces one shared `installer_plan_stage_records` reader. It checks
the complete stage set before dispatch, validates each field, accepts canonical
repository paths, and rejects malformed columns, extra fields, unsafe paths,
unresolved installer tokens, duplicate IDs/providers, and excessive stage counts.
It scans once per consuming phase and uses `LC_ALL=C` with a portable AWK literal.
Both pre-pkgsel and late dispatch consume it. Late validation precedes the receipt
and account publication operations.

The compiler now distinguishes stage IDs from slash-containing class identifiers.
It rejects IDs and dependency references that cannot be used as phase filenames,
and rejects provider spellings incompatible with the runtime contract. The static
AWK portability gate also inspects the new reader, alongside its existing
ownership and CrowdSec owners.

| Changed owner | Purpose |
| --- | --- |
| `d-i/debian/hooks/installer/pre-pkgsel.d/50-class-plan.sh` | Consume validated physical-member records; remove the obsolete combined allow-list. |
| `d-i/debian/scripts/common/modules/installation-plan.sh` | Own the shared bounded record reader. |
| `d-i/debian/scripts/late/dispatch.sh` | Use the same reader before target receipt/account publication. |
| `tools/class_compiler.py` | Align stage and provider validation with the runtime. |
| `d-i/debian/tests/fixtures/contracts/pre-pkgsel-plan.sh` | Replace obsolete `FILE_*` fixture selectors and checksum-era state with the current prepared-payload and readiness contracts; exercise failures and ownership. |
| `d-i/debian/tests/test_plan_stage_dispatch_20261119.py` | Register dispatcher and compiler regressions for the guarded test image. |
| `tools/post_change_check.py` | Add the reader to the existing AWK delimiter audit. |
| `tools/tests/test_awk_literal_portability_20261119.py` | Cover the third checked owner and its historical raw-slash failure. |

Shared-contract inspection covered the compiler, AWK resolver, immutable plan,
phase ownership, both stage consumers, early hook registration, prepared-payload
acquisition, and the managed-software consumer of the namespace stage. The six
pre-pkgsel provider interfaces are firmware, os-prober, namespace, DKMS, legacy
CUDA, and legacy NVIDIA. Late provider addresses were compared against all 22
generated reference plans: three desktop tiers, the composable GitHub Actions,
GitLab CI/CD and DevOps server roles, and standalone Technitium, for both suites.
The managed-software inventory includes Bitwarden, QoreDB, Obsidian, Tomat, Sleek,
Postman, Discord, Tuta, Ledger and ChatGPT/Codex. Their stage ownership and source
membership were inspected; their application launch/policy behavior was not
executed by these fixtures.

The source HEAD is `55abef8015812e76ad385aebf77c15942c984f67`, with existing
uncommitted work retained. The generated release is
`894ea7d26345a4d257c45e85844747ab9b78af0bc45dca38f60656272a80013c`.
Both suite directories were regenerated through the inspected pure `make build`
path, with 2,433 payload members. Each contains `preseed.cfg`, `payload.tar.gz`,
`payload.manifest`, `source.sh`, `receipt.json`, and `support-matrix.json`.
The [machine-readable evidence](pre-pkgsel-stage-records-20261119.json) records all
twelve product hashes, changed-owner hashes, the captured source fingerprint,
fixture identities, exact QEMU argument arrays, results, and retained failures.

| Completed isolated check | Result |
| --- | --- |
| Original dispatcher with a physical-member plan | Reported failure reproduced as an expected negative control. |
| 27 dispatcher cases × Dash/installer ash × BusyBox AWK/mawk | 108 passed. |
| Real AWK resolver and stage reader against all 22 generated plans × two AWK engines | 44 passed; ordered stage records and source-member presence matched. |
| Compiler rejection/acceptance inputs | 7 passed. |
| Static AWK guard, including reintroduction of the raw slash | 2 passed. |

These are fixture cases and comparisons, not a count of full installer runs or
Python unittest methods. The dispatcher fixtures use the real reader, restricted
policy parser, child wait-status propagation, and phase ownership/release stamps.
Bootstrap module selection, transport, logging and provider bodies are fixtures.
Success, completed-stage skipping, child failures, transfer failure, invalid
policy, release mismatch, missing readiness/preparation, interrupted ownership,
wrong/symlink completion stamps and malformed records are covered. In malformed
record cases, no first-stage claim or child execution is allowed.

The disposable boundary uses QEMU 11.1.2 with TCG, one vCPU, 768 MiB, a private
initramfs, no network device, no host mounts and no device passthrough. Its Debian
Installer kernel is `6.12.107+deb13-amd64`; BusyBox is `1.37.0` from Debian
`1:1.37.0-6+b9`. Dash is `0.5.12-12`, mawk is `1.3.4.20250131-1`, and the compiler
fixture uses Python `3.13.5-2+deb13u5`. The kernel and base initrd were checked
against the Debian HTTPS-published checksum manifest. Additional packages were
extracted as data after verifying signed repository metadata and package hashes;
no package scripts were executed. Guest `/proc`, `/dev` and writable RAM belong
to that guest. Every host image, capture and scratch file is under the verified
disk-backed `.build/validation/class-plan-20261119/` tree.

The full guest has a 180-second deadline; the compiler guest has a 120-second
deadline, each with a separate five-second kill grace. Both final runs reported
guest status 0, powered down, and returned QEMU status 0; their direct processes
were reaped. Images and serial captures remain available for inspection.

Earlier guest attempts exposed an unescaped AWK slash in the new reader and three
fixture setup omissions: unavailable `diff`, missing guest devtmpfs for Python's
random input, and a missing repository-relative asset layout for the static
checker. These were corrected. Failed-run images and logs are retained, and those
runs are not counted as passes. The final full matrix was repeated with the
corrected guest device setup.

Source checks run for this repair are `make build`,
`python3 -B tools/post_change_check.py`, Python AST parsing, `sh -n`, ShellCheck
error checks, and `git diff --check`. Generation and the static audit passed;
the audit includes the existing user changes and compares current sources,
manifest entries, receipts and preseed pins as data. The named historical
`debian-preseed-de-audit.md` file is absent from this checkout, so it supplies no
acceptance evidence for this repair.

A complete unattended installation, target package installation, complete
`late_command`, first boot, Secure Boot, NVIDIA/CUDA operation, loaded AppArmor,
services and hardware behavior remain unverified. The full guarded Python test
suite was not run; its new wrappers were syntax-checked and their core contracts
were exercised by the standalone guest fixtures. All four compiled suite/family
qualification rows remain `source-candidate` with native acceptance unverified.
No remote publication or serving-service change was performed. A deployment must
use all six matching suite products together and start from the rebuilt preseed;
an existing installation's frozen runtime snapshot is not repaired by changing
checkout files.

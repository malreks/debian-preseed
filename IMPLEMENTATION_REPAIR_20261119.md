# Installer preparation and publication repair report

Date: 2026-11-19.

**Repairs incorporated and both normal suites rebuilt.** All 12 generated products reproduce byte for byte, and the compiled source/data contracts pass for the repaired release. The required static audit remains **FAIL** because BusyBox and ShellCheck are unavailable. No successful native installation is claimed.

Use the regenerated products in `d-i/forky/` or `d-i/trixie/` as a matching set. The separate `offline/payload.tar.gz` is a historical build that does not contain these repairs. The source archive includes the entire checkout, cumulative optimizations, both normal suite builds, regression sources and the evidence linked below.

## Reported failure and what the evidence establishes

The reported installer dialog identified `hook-base-00rendertarget`, displayed `Component: unavailable`, and used the broad operation label `prepare_target_payload`. The report did not supply the selected profile, source transport, release identity, exit status or private failure record. That label covers many operations, so it does not establish which inner operation failed on the user's machine.

This pass found and repaired a definite server-family preparation defect, a failure-component reporting mismatch, a malformed lifecycle call, and three queued-publication ordering defects. The server defect is a concrete failing source path when a server profile is selected. It is not sufficient evidence that the user's particular attempt selected a server profile or failed for that reason.

| Finding | Source evidence | Resulting change |
| --- | --- | --- |
| Server preparation rejected desktop classifier metadata | The hook resolved the appearance registry through the installed-asset family guard before launching the renderer | Pass its canonical captured-source address to the classifier; retain family checks for installed assets |
| Failure component became `unavailable` | The failure producer stored a prose log context; the frontend accepts bounded structured identifiers | Select a valid supplied identifier, then log tag, then phase, without widening the frontend filter |
| Missing installer environment lost its intended component/detail split | One `installer_lifecycle_abort` call passed the human reason as its second argument and omitted the third | Pass status, `guard-hook-path`, and private detail in the correct positions |
| Tmpfiles consumer read before publication | Its readability check could run while the required policy remained in the batch queue | Flush successfully before the direct read |
| Logging foundation inspected unpublished files | Five staged forwarding files were checked before their batch was committed | Flush before the metadata and placeholder loop |
| Desktop assertion inspected unpublished XML | Deferred rendering queued the replacement, then an installer-side assertion read the destination | Flush before inspecting the rendered candidate |

The earlier [implementation report](IMPLEMENTATION_20261119.md) and [target `usr` report](IMPLEMENTATION_TARGET_USR_20261119.md) remain historical records of their own snapshots. Their release identities, measurements and validation limits must not be treated as acceptance evidence for this repair release.

## Preparation boundary and diagnostics

### Captured classifier metadata versus installed-family selection

The preparation hook is [base-stage.d/00rendertarget](d-i/debian/hooks/installer/base-stage.d/00rendertarget). It copies the captured source tree and prepares the maps required by the base-system Perl renderer before later base hooks, kernel/DKMS work, package selection and late dispatch.

The old appearance argument invoked `installer_repo_file_value` for `hooks/target/usr/local/share/desktop/labwc-appearance/fields.json.tmpl`. The helper deliberately rejects desktop-owned installed assets when `INSTALLER_HOST_VARIANT=server`. That was the wrong boundary for this argument: the renderer needs the registry to distinguish appearance marker definitions while classifying the complete captured tree, which includes both families.

The hook now supplies `$DIR_TARGET_SHARE_LABWC_APPEARANCE/fields.json.tmpl`. This remains a repository-relative path derived from the restricted `repo.env` contract. The renderer still validates its option as a relative address. Actual asset publication continues using the family guard, and server Perl publication continues excluding desktop modules. No `render.pl` implementation change or policy relaxation was required for this repair.

The hook now records **21 distinct operation contexts**, covering phase validation, profile/account/storage inputs, workspace preparation, each map producer, renderer launch, receipt validation, ownership import and ready-marker publication. A source check confirmed that every recorded line number matches the corresponding `prepare_context` call. The existing context helper sets advisory structured fields and performs no fetch. It does not change the operation's status or introduce another validation dependency.

See the [base-render boundary evidence](docs/validation/base-render-boundary-20261119.md) and [machine-readable companion](docs/validation/base-render-boundary-20261119.json).

### Structured failure components and private detail

The canonical [lifecycle library](d-i/debian/scripts/common/lifecycle.sh) now chooses a component using this order: a valid supplied identifier, a valid `INSTALLER_LOG_TAG`, then a valid `INSTALLER_PHASE`. Empty, unknown, unavailable, URL-shaped, unsupported-character and overlength candidates are rejected. If no candidate is usable, the field remains `unknown`.

The allowed characters and 240-character limit agree with the existing frontend filter. Raw detail is still private diagnostic content. The change preserves the original failure status and atomic first-writer-wins record, so a later cleanup failure cannot replace the primary failure. The embedded lifecycle block in [source.sh](d-i/debian/scripts/common/source.sh) was synchronized with the canonical library; independent byte comparison found an exact match.

The missing-`di.env` branch in [guard-hook.sh](d-i/debian/scripts/preseed/guard-hook.sh) now calls `installer_lifecycle_abort` with all three intended arguments. A source-only review of the other literal prose call sites found no additional instance of the same argument-position error.

These changes improve diagnosis across profiles. They do not turn a failed operation into success or permit the installer to continue after a fatal state.

## Publication order and retained batching

The existing publisher queues assets until a dependency boundary. A target-command wrapper already flushes before target execution, but an installer-shell reader can run before reaching that wrapper. On a fresh target it sees no file; on an existing target it can inspect stale bytes.

Three direct readers now establish their own dependency barriers:

| Source owner | Reader | Barrier placement |
| --- | --- | --- |
| [storage-maintenance.sh](d-i/debian/scripts/late/storage-maintenance.sh) | `normalize_target_tmpfiles_directory_policy` | After path validation, before the readability check and target setup request |
| [late/target-assets.sh](d-i/debian/scripts/late/target-assets.sh) | `stage_target_logging_foundation` | After queuing the first five forwarding assets, before checking their type, owner, mode, link count and placeholders |
| [devices-network.sh](d-i/debian/scripts/desktop/components/devices-network.sh) | `desktop_assert_role_target_template_resolved` | Before reading the deferred rendered target candidate |

Each barrier returns immediately with the publisher's nonzero status if publication fails. The subsequent reader cannot silently use stale data. A flush does not close a batch or modify nesting depth; the owning begin/finish sequence remains intact. The reviewed flush call chain does not overwrite the consumers' path variables.

Batching, the single renderer, ownership import, source-integrity checks and retained failure evidence remain the same owners. The additional work occurs at a required read dependency. No per-file fallback renderer, duplicate publication implementation or unconditional target execution was introduced. No wall-clock speedup or installation-time improvement was measured during this repair pass.

## Cross-component coverage

The parallel review covered four connected areas: bootstrap/build/configuration, rendering/preparation, installed runtime and installer consumers, and the relevant regression sources. Inventory and source/data coverage are distinguished from runtime acceptance.

| Area | Coverage and finding |
| --- | --- |
| Repository and installer authority | Restricted `repo.env` grammar, `di.env`, canonical `runtime.env`, all three bootstrap loading routes, profile/theme ownership and source resolution were traced. No second configuration authority was introduced. |
| Compiler and publication contracts | Both suites, all 19 profile selections per suite, generated profile/source/APT/Perl table shapes, archive manifests, suite receipts, source frontend equality and preseed pins were inspected as data. |
| Profile and renderer input closure | All 38 compiled suite/profile views contain the 734 canonical runtime fields. All 313 used canonical placeholder names have producers. No `KEY`/`INSTALLER_KEY` scalar alias collision was found. |
| Early template inputs | Of 193 required direct inputs, 189 are present in every compiled profile; four are produced by the inspected GRUB/Btrfs/F2FS paths before use. All seven resource loop groups, five boolean controls and storage-mode domains were checked across the 38 views, with no invalid value found. |
| Shared Perl inputs | All 160 catalog rows were reviewed. Only `ACCOUNT_USERNAME` and `SOFTWARE_APT_REPO_LOCAL_DEB_MAXIMUM_BYTES` remain deferred outside canonical/logging maps, and the hook supplies both. |
| Target tree | The runtime agent inventoried 1,699 target files totaling 13,318,842 bytes. All 249 Python sources passed AST parsing; 114 shell entrypoints passed parser-only checks. |
| Authored Python imports | 293 local import edges across 98 authored dist-packages modules resolved to captured source modules. Native module loading and third-party package availability were not inferred from this result. |
| Third-party package declarations | Fourteen selected suite/role checks found the required relevant package names in the generated common APT and selected role declarations. This is declaration presence, not package availability or installation. |
| Shared late consumers | Desktop-only storage/logind/NVIDIA/dbus-broker publication paths and Tailscale role gates were traced. Three additional direct-reader barriers were repaired. |
| Managed software and servicing | Dispatch, policy consumers, initial publication order, package metadata boundaries and launcher/module sources were reviewed for Bitwarden, QoreDB, Obsidian, Tomat, Sleek, Zoom, Filen, Postman, Discord, Tuta, Ledger, ChatGPT, Codex, SCX and Tor Browser. No additional concrete defect was established. |
| Independent peer review | Lifecycle/frontend grammar, embedded-copy equality, guard-hook argument arity, classifier addressing, all 21 context lines, flush status propagation and batch depth were checked without executing the implementations. No new concrete regression was found in those reviewed changes. |

The [runtime publication repair report](docs/validation/runtime-publication-repair-20261119.md) records the inspected consumers, software families, package-declaration checks and source-level limitations. Vendor signatures, remote archive layouts, package maintainer behavior, graphical launch, services and AppArmor acceptance were not executed or inferred from source wiring.

The data-only source-contract checker was rerun successfully against the repaired release `b4de1b60b6be8c7bae263af79a19f931c1d63eb7673eef35540b5c7feb1f3e42`. Per shared payload, it verified 2,433 manifest members, all 38 compiled suite/profile views, 182 profile-asset rows, 88 APT rows and 160 Perl rows, with unique selected destinations. Desktop selects 160 Perl modules and server selects 102. Both suite receipts, source helpers and preseed payload pins agree with the rebuilt bytes. The complete result is included in the [delivery validation record](docs/validation/repair-delivery-validation-20261119.json).

The tools and installer-script source pass also parsed 40 Python files under `tools` and 39 under `d-i/debian/scripts`, with no syntax errors. Parsing source does not execute tests or prove behavioral correctness.

## Regression coverage authored in this pass

| Fixture source | Added coverage | Execution classification |
| --- | --- | --- |
| [test_debconf_protocol.py](d-i/debian/tests/test_debconf_protocol.py) | Structured component selection for prose, valid identifiers, URL input, overlength input and fallback; original status, private-detail exclusion and first-failure retention | Source reviewed; native execution not performed |
| [test_base_render_boundary_20261119.py](d-i/debian/tests/test_base_render_boundary_20261119.py) | Four cases for both-family classifier arguments, preserved server rejection of desktop publication, desktop acceptance and all 21 exact stage lines | AST/source review and extracted shell parser checks; native execution not performed |
| [test_target_render_20261116.py](d-i/debian/tests/test_target_render_20261116.py) | One additional server renderer case preserves appearance marker definitions and excludes desktop Perl publication | AST/source reviewed; Perl renderer not executed |
| [test_publication_consumer_barriers_20261119.py](d-i/debian/tests/test_publication_consumer_barriers_20261119.py) | Six cases for fresh tmpfiles policies, stale-file preservation on failure, logging publication before reads, logging failure propagation, deferred XML reads and XML publication failure | AST and parser-only shell checks; native execution not performed |

The two base-render fixture files now use the explicitly owned guest `/workspace` for all 17 temporary-directory roots. These paths address the renderer's strict ancestry checks and the fixture design's read-only guest root. The fixture isolation guard remains mandatory before discovery; changing the fixture paths does not itself establish an available or successfully executed guest.

## Offline bundle: separate and still historical

The complete checkout contains `offline/payload.tar.gz`. **That existing archive has not received this repair.** Its recorded release is `043109310d674ea55bdd30298d83aa537ae999434b2d8743277b766075a2d7c0`.

The read-only assessment of [tools/offline.py](tools/offline.py) found that a metadata-only rebuild still needs the original repository inputs: each declaration's scoped public keys, signed `InRelease` or `Release` plus detached signature, and the advertised binary, installer and source indexes. It verifies index byte counts and SHA-256 values from the signed release before ingesting them. `--metadata-dir` requires an explicit complete local snapshot and has no network fallback.

The historical archive retains 53 metadata evidence files: 20 keyrings, 32 release records and one detached signature. Its catalogs refer to **264 original indexes totaling 149,100,132 bytes**: 161 binary, 60 installer and 43 source indexes. None of those raw indexes is included, and no compatible metadata snapshot was found in the available workspace. Filtered catalog JSON cannot reconstruct the original signed index bytes. The offline recipe was not run, and no package or metadata acquisition was attempted for this assessment.

Normal suite products are selected separately. [source_prepare_payload](d-i/debian/scripts/common/source.sh) obtains `payload.manifest` and `payload.tar.gz` adjacent to the selected suite base and checks the suite preseed's trusted digests. `make build` regenerates the normal `d-i/forky` and `d-i/trixie` products; the independent `make offline` recipe does not run as part of that build. The regenerated normal suite products, with the final release recorded below, are the repair candidate. Extracting the historical offline archive would select its older flat-tree source and preseeds instead.

## Final release and validation accounting

The [machine-readable validation record](docs/validation/repair-delivery-validation-20261119.json) contains all 12 product hashes, the compiled source/data results, runtime and preparation review evidence, exact static audit errors and performance limits. The [command record](docs/validation/repair-delivery-commands-20261119.txt) preserves build and audit output. [Repair-only changed paths](docs/validation/repair-changed-paths-20261119.tsv) are relative to the previous delivered ZIP; [cumulative changed paths](docs/validation/changed-paths-round3-20261119.tsv) are relative to the original attachment.

| Final evidence | Recorded result |
| --- | --- |
| Delivered release | `b4de1b60b6be8c7bae263af79a19f931c1d63eb7673eef35540b5c7feb1f3e42` |
| Source fingerprint | `04f9294c5dae0fa38069f43284675bb34e3f902ed3f724b78ff791514a8c8ae9` |
| Forky and Trixie product hashes | All six products per suite recorded and checked; both payload archives are identical |
| Consecutive-build byte reproducibility | PASS: all 12 product hashes unchanged, with no differences |
| Final compiled contract-data audit | PASS: both suites, all 38 compiled views, manifests, catalogs, source helpers and preseed pins |
| Changed paths and whitespace | Exact byte/mode manifests supplied; real `git diff --no-index --check` completed against both delivered and original baselines |
| Required static audits | FAIL: four errors caused by unavailable BusyBox/ShellCheck checks; no additional errors from the available checks |
| Complete source archive | `debian-preseed-optimized-20261119.zip`; archive checksum accompanies the download |
| Native installer/target acceptance | Not performed; an approved disposable target image is unavailable |

The required audit failures are preserved verbatim:

```text
required static shell checker is unavailable: busybox, shellcheck
embedded shell checker requires shellcheck, dash and busybox
preseed syntax requires dash and busybox; no silent skips
preseed syntax requires dash and busybox; no silent skips
```

The last two lines are separate suite checks. Available source checks continued after these failures; no checker or acceptance gate was disabled. The cumulative audit also revisited the earlier optimizations against the original attachment, including Appearance mappings, generation/publication contracts, role policy and shell/Python source checks.

## Optimizations retained and measured artifact sizes

This repair retains the earlier single-owner configuration and rendering design, package batching, managed Python observation reuse, shared Perl status handling, common hardware wrapper ownership and wallpaper deduplication. The new flushes occur where a consumer must observe committed bytes; other batching continues.

| Shared runtime payload | Original attachment | Previous delivery | Repaired delivery |
| --- | ---: | ---: | ---: |
| Compressed bytes | 11,923,852 | 10,267,881 | 10,268,910 |
| Expanded file bytes | 40,306,051 | 34,621,032 | 34,624,274 |
| Regular members | 2,433 | 2,433 | 2,433 |

The repaired payload is 1,654,942 compressed bytes and 5,681,777 expanded bytes smaller than the original attachment. Compared with the immediately preceding delivery, explicit diagnostics and correctness barriers add 1,029 compressed bytes and 3,242 expanded bytes. These are artifact-size measurements, not runtime speed benchmarks.

The complete `d-i/debian/hooks/target/usr/` tree remains 670 regular files totaling 11,269,053 bytes. A fresh SHA-256 grouping found no byte-identical file groups. This does not imply that every semantically similar operation should be merged: bootstrap embedding and independently confined executables retain their existing ownership boundaries.

## Selecting the repaired products

Publish the complete extracted project through the existing deployment process, or publish all regenerated products for the selected suite together: `preseed.cfg`, `source.sh`, `payload.tar.gz`, `payload.manifest`, `receipt.json` and `support-matrix.json`. Start from that suite's regenerated preseed. It pins the source helper, payload and manifest; mixing it with an older helper or payload is expected to fail integrity validation.

Both receipts must identify the release shown above. The shared payload SHA-256 is `5f48e43a8adc877fe79f4a82ad9e913f61b1b6057db25598eb58bc4d0de8e8e3`. Existing suite/role policy and candidate/unverified support statuses remain authoritative; compiling a profile does not promote it to native support.

For another failure in this release, preserve the selected profile, suite, release identity, exit status and the new precise operation/source-line fields with the preceding private diagnostic. The earlier broad dialog alone cannot distinguish account, storage, workspace, map-generation and renderer failures. No secrets need to be placed in the public component field.

Official Debian package file lists show that both supported suites' `perl-base` includes the Perl interpreter and the `File::Temp`, `IO::Handle` and `Fcntl` dependencies used by preparation. This rules out an assumed missing package-core module as an established source defect; it does not prove that the user's target has a complete or working installation. Sources: [Trixie perl-base file list](https://packages.debian.org/trixie/amd64/perl-base/filelist) and [Forky perl-base file list](https://packages.debian.org/forky/amd64/perl-base/filelist).

No identified approved disposable target image or native fixture was available. QEMU, Docker, Podman, proot, BusyBox and ShellCheck were unavailable in the inspected tool inventory. `bwrap` and `chroot` binaries alone are not an identified target environment. Repository tests, installer hooks, Perl imports/compilation, managed services, package managers and hardware programs were not executed on the development host.

All source/data inspection and private scratch stayed within the checkout's disk-backed validation tree with explicit temporary-directory settings. The [test-isolation contract](docs/test-isolation.md), target authority checks and required acceptance gates remain in force. A native installation claim requires separate recorded evidence from the corrected release in the approved isolated or explicitly selected target environment.

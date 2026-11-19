# Runtime publication consumer repair — 2026-11-19

## Result and limits

This review found and repaired three downstream consumers that read target files before a queued publication batch had made those files visible. These defects can stop a fresh desktop installation or inspect old target contents. They are separate from the earlier `hook-base-00rendertarget` / `prepare_target_payload` failure investigated in the base-render report.

The fixes retain batched publication and add an explicit dependency barrier only at the affected installer-side read. A failed flush returns its original status before any subsequent read or setup command. No vendor package, service, AppArmor policy, role selection, private Xwayland eligibility, or target runtime implementation was changed by this part of the repair.

Validation in this workspace was limited to source inspection, data inventory, Python AST parsing and shell parsing with `-n`. The new guarded fixtures were authored and parsed, but were **not executed**. Native installation, package import, boot, desktop session, AppArmor and service acceptance remain unverified here. There is no measured performance claim.

## Repaired consumers

| Production source | Consumer and defect | Repair |
| --- | --- | --- |
| `d-i/debian/scripts/late/storage-maintenance.sh` | `normalize_target_tmpfiles_directory_policy()` tested readability before the later target setup call could flush queued assets. Desktop staging queues the pool, network, cache and man-db policies before calling this helper. A fresh target therefore lacked the file at the first read. | Flush after validating the destination path and before the readability test. The setup helper sees the current published policy. |
| `d-i/debian/scripts/late/target-assets.sh` | `stage_target_logging_foundation()` started a batch, queued five forwarding assets, then immediately checked their type, ownership, mode, link count and unresolved tokens. No intervening target command published them. | Flush the first five assets before the metadata/content loop. The remaining five logging assets still publish through the batch's normal finish. |
| `d-i/debian/scripts/desktop/components/devices-network.sh` | `desktop_assert_role_target_template_resolved()` inspected `rc.xml` immediately after the deferred Labwc renderer queued it. The first installation could fail on a missing file; an existing file could make the assertion inspect obsolete contents. | Flush before resolving and inspecting the target candidate. |

The shared `target_exec()` path already flushes pending publication before running a command in the target. That barrier cannot protect an earlier shell `test`, metadata query, `grep`, `cat`, copy, glob or command substitution. The added barriers express those earlier dependencies without turning every asset operation into a separate publication process.

## Guarded regression source

`d-i/debian/tests/test_publication_consumer_barriers_20261119.py` contains six test methods. Its isolation guard runs before discovery. Inside an approved isolated guest, the fixture requires guest root ownership, creates one exclusive private workspace under `/var/lib`, and supplies private publication and target-setup adapters. It extracts the reviewed shell functions as source instead of loading the full installer.

| Fixture method | Intended regression coverage |
| --- | --- |
| `test_fresh_tmpfiles_consumers_publish_before_their_readability_check` | Four fresh target policies: `75-desktop-pool-storage.conf`, `40-network-profiles.conf`, `50-desktop-var-cache.conf`, and `man-db.conf`; expected event order is queue, flush, setup. |
| `test_failed_tmpfiles_publication_does_not_use_an_existing_stale_policy` | A publication error returns status 71, leaves the previous file intact and prevents setup. |
| `test_logging_foundation_publishes_before_metadata_and_token_checks` | All five initial logging candidates exist before their five inspections, and the remaining five publish at batch finish. |
| `test_logging_publication_failure_stops_before_any_validation` | A failed initial flush stops before metadata/content inspection. |
| `test_deferred_desktop_assertion_checks_the_new_candidate` | Deferred `rc.xml` publication precedes the assertion. |
| `test_deferred_desktop_assertion_propagates_publication_failure` | A failed deferred publication prevents inspection and preserves the failure status. |

The fixture source AST parses. Its composed shell prelude and extracted production functions pass `dash -n`. Each of the three edited production shell files also passes `dash -n`. These checks establish source syntax, not fixture outcomes.

## Target source coverage

The inventory traversed the entire `d-i/debian/hooks/target` source tree, including `usr`, systemd, AppArmor, desktop entries, skeleton defaults, shared assets and data. It recorded hashes and source grouping for 1,699 regular files totaling 13,318,842 bytes. Those counts describe this review snapshot; the target tree was not modified by the three barrier repairs.

| Check | Observed source result | Scope limitation |
| --- | --- | --- |
| Python parsing | 249 Python sources parsed, including Python templates and extensionless Python entrypoints; zero parse errors. | No imports or module-level code executed. |
| Authored Python module resolution | 98 modules under authored `dist-packages`; 293 import edges into that namespace; no missing referenced module. | Symbol exports, dynamic imports, installed `sys.path`, interpreter versions and native dependencies still require runtime validation. |
| Shell parsing | 114 shebang-identified target shell sources passed the matching Dash or Bash parser with `-n`. | No shell body, embedded program or target helper executed. |
| Third-party package names | Required package names were present in the generated common APT fragment plus the corresponding selected role file for 14 suite/role combinations. | This is package declaration presence, not repository availability, package installation or import success. |

The third-party review covers PyGObject, defusedxml, icalendar, tinycss2 and YAML for desktop consumers; keyring for selected DevOps publishing tools; and cryptography for the DNS backup implementation. The DNS cipher imports cryptography inside its backup helper. The private hardware-tuning imports (`broker`, `client`, `common`, `engine`, `policy_owner`, `power_profiles`, and `system_state`) resolve to the dedicated hardware-tuning source directory and are staged together by `install_profile_hardware_tuning()` when its gates are satisfied. Waypaper is installed through its separate managed environment.

## Additional direct-reader and family review

The other reachable consumers reviewed did not require another production change:

- Public desktop, proxy, background, appearance, Help and compz directory checks create their own parents explicitly before reading or changing directory metadata.
- The user-session asset helper already flushes queued custom units and drop-ins before its shell globs and mode changes. Its earlier package-unit probes inspect vendor-installed units. User-unit enablement and user-resource policy run after desktop asset publication finishes.
- Wallpaper extraction and target-side validators pass through target execution before reading their output. The managed application module tree uses a separate private staging directory, verifies that tree, and publishes it together; it does not read a queued target candidate.
- Vivaldi, Wayscriber, KWallet and other package presence probes read package-installed files, not assets awaiting this batch.
- `desktop_replace_block_placeholder_in_target()` has no current runtime callsite in `d-i/debian`. The active Labwc `rc.xml` renderer uses scalar/block publication followed by the repaired assertion. The unused helper was left unchanged.
- Shared late scripts that mention desktop logind, NVIDIA tmpfiles, dbus-broker user units and storage roots are reached through the desktop storage dispatch path. The Tailscale integration gates its desktop helpers on medium/full desktop roles. The software provisioning script rejects non-desktop families before selecting desktop policy sources.

These are source call-order and selection checks. They do not establish every possible runtime state of the installed target.

## Managed software and library wiring reviewed

The package/runtime review traced the software dispatch gates, initial publication order, release-policy consumers, package metadata handling and corresponding launcher/module sources. Existing source contracts were retained.

| Software or shared path | Integration examined |
| --- | --- |
| Bitwarden, QoreDB, Obsidian, Tomat, Sleek | Role-gated preparation, shared DEB queue/flush, installed-file post-install consumers, retained package specifications and release-policy selection. |
| Zoom, Filen | Medium/full desktop preparation and package specifications; Filen sandbox repair; Zoom's separate compatibility entrypoint. |
| Postman, Discord, Tuta, Ledger | Dedicated archive/extractor helpers, published launchers and keys/policies, release metadata consumers, and post-extraction reads. |
| ChatGPT | Medium/full role gate, shared repository/package policy, preparation/finalization/abort handling and installed payload checks. |
| Codex | Separate class-owned provisioning and runtime consumers; desktop staging preserves the rendered class-owned units instead of replacing them with source templates. |
| SCX | Profile-controlled package and backend selection, required installed package assets, and shared scheduler configuration. |
| Tor Browser | Full desktop selection gate and its separate installer helper. |
| Shared servicing libraries | Bounded DEB metadata inspection, named control-field parsing, process result handling, repository handoff, source snapshot identity, and the separation of upstream/transformed/signed artifact identities. |
| Managed application Python package | Explicit module manifest, private staged tree validation, whole-package publication and entrypoint/module source resolution. |

No additional concrete defect was established in these reviewed paths. This review does not assert that every vendor release, archive layout, signature, package maintainer script, graphical launch or service transition succeeds. Those boundaries need the repository's approved isolated native validation environment and actual installer acceptance runs.

## Evidence locations

Private reproducible evidence is stored under `.build/validation/round3/runtime_sweep/`:

- `coverage.json`: consolidated scoped review and validation inventory.
- `target-inventory.json`: file counts, hashes, groups and parsed Python source list.
- `python-import-review.json`: authored import edges and other import names.
- `target-shell-syntax.json`: all 114 shell parser results.
- `third-party-package-presence.json`: role/suite package-name checks.
- `consumer-validation.json`: new fixture AST and three production/composed-shell parse results.

Build refresh, signed metadata/index regeneration, complete archive auditing and final downloadable delivery are owned by the integrating repair work. This report does not substitute for those gates.

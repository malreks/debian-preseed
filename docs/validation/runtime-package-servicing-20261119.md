# Round two: package publication and servicing

## Delivered source changes

This pass changes these two installed source owners:

- `d-i/debian/hooks/target/usr/local/libexec/common/apt-repo-local.tmpl`
- `d-i/debian/hooks/target/usr/local/lib/common/perl5/site_perl/apt-repo-local/APTRepoLocal/Servicing/Deb.pm`

Directly related fixture updates are in:

- `d-i/debian/tests/test_installer_package_batch_20261119.py`
- `d-i/debian/tests/test_retained_package_bounds.py`
- `d-i/debian/tests/test_management_refresh_20261026.py`

No installer package selection, shared policy ceiling, package dependency policy, package-manager options, AppArmor rules, source selector, repository index format, or signing format changed. The first-round seven-package desktop batch, separate SCX batch, and existing four-vendor adopted batch remain in place.

## Source-derived reductions

These counts describe code paths, not measured wall-clock improvement.

| Operation | Previous round-one path | Round-two path |
|---|---:|---:|
| Fresh Perl validation with payload checking: `dpkg-deb` invocations | 5: `--info`, three `-f`, one `-c` | 2: one full `-f`, one `-c` |
| Perl metadata-only validation | 4 | 1 |
| Perl required-member listing scans | One full split/scan per required lookup | One split/scan, bounded records for requested paths only |
| Perl installed status/version queries | 2 | 1 |
| Python refresh inspection before an import of unchanged protected bytes | 2 control reads, 2 data listings, 2 Debian version validations | 1 of each |
| Python interactive add inspection | 2 of each | 1 of each |
| Python interactive add's separate upstream SHA-256 read | 1 | 0; uses the checked staging-copy digest |
| Separate signed-output SHA-256 reread per newly signed import | 1 full signed archive | 0 |
| Separate transformed-input SHA-256 reread per rewritten import | 1 full transformed archive | 0 |

If `S` is the complete signed archive size and `T` is the transformed unsigned archive size, signing removes `S` bytes of separate full-file SHA-256 reads for an unchanged input and `S + T` for a transformed input. The mandatory signing copy feeds a single SHA-256 state. Its digest before signature append identifies the exact unsigned prefix; the final digest includes the appended ar header, clear signature, and odd-length padding in write order. No file content is inferred from a filename or size alone.

The existing dpkg-sig member SHA-1/MD5 pass, GPG operation, required archive copies, transformed-output inspection, existing pool-object hash checks, and retained upstream-object hash checks remain. The Debian version validator also remains. The previous cross-call Perl listing cache was removed because it used pathname and second-resolution timestamps; a later validation deliberately obtains fresh contents rather than claiming those cached bytes still apply.

## Authority and invalidation

The Perl control parser consumes named fields, independent of their order. It rejects malformed, duplicate case-insensitive, NUL-bearing, CR-bearing, and over-limit control data; Package, Version, and Architecture are still required by their actual consumers. Its listing table preserves exact required-member uniqueness, symlink support, executable checks, CLI-only empty desktop handling, and rejection of hardlink declarations as required members.

Python inspection reuse is process-local and restricted to snapshots copied by this repository process into its protected inbox. The key binds dev/inode/size/mtime_ns/ctime_ns and the exact required-member tuple. The parser checks identity before and after inspection. Returned field dictionaries cannot mutate the cached result. Independent inbox deliveries and newly transformed outputs receive fresh inspection; no sidecar, persisted receipt, or public object authorizes reuse.

Refresh now copies and inspects an inactive `.part`, checks the remote release/version constraints, and only then activates it. Activation verifies that rename preserved dev/inode/size/mtime before carrying the digest and inspection with the new ctime. An exception after rename revokes both caches and moves the exact ready file and sidecar to a non-watchable `.activation-failed-*.part` path. If isolation fails, the result is `OutcomeUnknown` with explicit retained paths. Refresh propagates that result instead of reporting an ordinary upstream failure and continuing.

The original upstream identity is distinct from the transformed identity. It is checked after metadata/hash inspection, immediately before and after rewriting, and before/during/after original-byte retention. Transformed output is separately inspected and bound to signing. Signing holds a checked input descriptor across member hashing, GPG and copy, rejects replacement/mutation, bounds the complete signed output, handles short or failed writes, and binds final output identity and size. Retained/pool copy metadata opens use the checked no-follow file boundary.

## Consumer coverage

The shared Perl interfaces were traced through CLI specifications, download adapters, retained candidate selection, repair, application installation, and post-install checks for Bitwarden, QoreDB, Obsidian, Tomat, Sleek, Zoom, Filen, and ChatGPT/Codex. The named metadata result remains unchanged for the Obsidian/Sleek/Tomat release adapters, including their independent vendor digest and version comparisons.

The Python publisher's common path also covers Discord, Postman, Tuta, Ledger, SCX and its loader, and explicit local Debian-package imports. Vendor verification and binary-package assembly continue before the protected stage/import boundary. No vendor signature or publisher-signing claim was substituted for another.

## Fixture and validation record

There are **67 guarded test methods** in the three affected fixture files, counted by parsing their Python AST as source data:

- `InstallerPackageBatchTests`: 22.
- `SignedArchiveCopyTests`: 5.
- `RetainedPackageBoundsTests`: 26.
- `ServicingInspectionTests`: 6.
- `ManagementRefreshFixtures`: 8.

Of these, **22 focused methods are new in round two**. They cover inspection/read counts, changed requirements, independent inbox inputs, mutation during inspection, controlled-rename replacement and mutation, post-rename synchronization failure, failed isolation, original-input mutation during transformation/retention, exact signature padding and digests, short/failed writes, output size bounds, named control parsing, duplicate/hardlink members, single installed-version queries, and outcome-unknown propagation.

The retained-package harness was updated to physical source owners and rendered fixture imports, the consolidated control method, a private bounded subprocess environment, and the currently shared configured package ceiling. No production limit changed. Management-refresh fixtures now use the same guarded rendered publisher source and explicitly distinguish inactive staging from activation.

**Performed checks for these paths:** source/consumer inspection and AST parsing of the publisher and all three changed Python fixture files. All four parse successfully. Temporary environment variables were explicitly directed to `.build/validation/round2/packages/tmp` on the previously verified checkout filesystem.

**Not performed as part of this source review:** test discovery, test execution, repository module import, Perl compilation/loading, package-manager or service commands, native integration, network operations, build, or the shared audit runner. The 67 methods are authored/inspected fixture source, not passing test results. The independent pure-build, generated-product, and final static-audit evidence is recorded in `target-usr-delivery-validation-20261119.json` and the consolidated `IMPLEMENTATION_TARGET_USR_20261119.md` report. No numerical elapsed-time or end-to-end speedup claim is made.

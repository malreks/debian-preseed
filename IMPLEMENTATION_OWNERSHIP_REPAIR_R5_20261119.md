# Debian preseed R5: ownership-stage regex repair and complete source delivery

Date: 2026-11-19. Release: `a8b81c64382235d5af48d0d86b0958b4415c17738a7698f3601e1c901d0a1d35`.

## Outcome

This revision corrects a second delimiter defect at `commit_target_ownership`,
retains and strengthens the `render.pl` PHASE fix, rebuilds both normal suite
products, and extends the maintained validation through the previously missed
renderer-to-ownership handoff. Three independent agents covered the renderer
and integration, installer ownership/provenance, and whole-source syntax and
portability. The complete code tree contains 3,060 regular files;
the exact cumulative change manifest lists 295 paths against the
original supplied ZIP.

The isolated run passed **113 regression methods** and all four normal-suite
desktop/server preparation, publication, ownership-import and snapshot scenarios.
The release is **not certified as a complete booted installer installation**.
BusyBox/ShellCheck availability and full noncore Perl dependency coverage remain
explicit failed gates, described below. No successful result is substituted for
an unavailable checker or a missing module.

## Why the ownership stage failed

The renderer writes three tab-separated fields: physical source member, absolute
destination and mode. The base hook converts them into destination, source,
`plain`, phase and mode. Those producer/consumer schemas agree, and the batch is
protected as a root-owned, single-link `0600` regular file.

The importer and snapshot each contained four unescaped slash characters in
slash-delimited AWK character classes. For example, the original class
`[A-Za-z0-9_./@+:-]` is now `[A-Za-z0-9_.\/@+:-]`. BusyBox's `next_token`
scanner ends a regexp at the first unescaped slash; a character class does not
exempt that delimiter. The current Debian implementation documents this behavior
in [BusyBox awk.c](https://sources.debian.org/src/busybox/1:1.37.0-10.1/editors/awk.c).
The diagnosis here is primary-source analysis and exact historical-code checking,
not a fabricated native BusyBox reproduction.

Earlier Mawk-only syntax acceptance did not establish BusyBox compatibility,
and earlier complete preparation stopped before the actual ownership import.
Both gaps are addressed in the maintained validation. The complete source sweep
found one additional occurrence in CrowdSec logging-overlay validation. Exact
retained R4 bodies contain nine faulty slash positions in total; the expanded
current production census finds none.

## Production changes

| Owner | Change and resulting behavior |
|---|---|
| `d-i/debian/scripts/common/modules/target-publication.sh` | One `installer_target_ownership_filter` owns both import and snapshot grammar. Literal slash delimiters are escaped. Import keeps one streaming AWK pass and does not allocate row arrays. Snapshot retains last-record-wins and deletion handling. |
| `d-i/debian/scripts/late/crowdsec.sh` | The same delimiter correction in the logging-overlay value validator, preserving its accepted alphabet. |
| `d-i/debian/scripts/common/render.pl` | PHASE uses paired Perl delimiters and explicit slash/at-sign bytes. The accepted alphabet remains exactly 69 ASCII bytes. |
| `d-i/debian/hooks/installer/base-stage.d/00rendertarget` | An advisory log records the validated release, copied archive/manifest identities and actual copied renderer hash. It hashes once, exposes no origin URL/account/map data, and cannot replace the renderer's status. Operation-context anchors match the actual source lines. |

Metadata and ancestry checks, the five-column contract, the 16 KiB row limit,
20,000-row limit, private journal and 16 MiB snapshot bound remain in place.
Validation-rejected batches leave an existing journal unchanged. The
normal render/receipt/import/ready ordering is unchanged, and a failed ownership
commit cannot publish the ready marker.

The actual base-hook TSV conversion remains byte-for-byte unchanged. Of 2,433
members in each final payload, 2,428 are byte-and-metadata identical to R4. The
five changed members are the release catalog and the four production owners
listed above. No target `/usr` member changed in R5.

## Regression and integration evidence

The maintained `tools/prepare_syntax_fixture.py` now checks the captured
renderer, lifecycle support, ownership module and base hook against authored
bytes before producers run. It executes the exact 272-byte AWK conversion and
chmod block from the captured base hook, then the real ownership importer and
snapshot with the actual metadata/ancestry helpers. Every published row must
survive unchanged in the batch and journal, and the snapshot must contain the
same complete record set. Source identities are rechecked after rendering.

Its default runtime is BusyBox and it fails before creating output if that
runtime is absent. Explicit `--ownership-runtime posix` selects fixed Dash/AWK
paths and records `busybox_validation=false`; it is reduced-dialect evidence,
not an installer-runtime fallback. All four runs below used this explicit mode.

| Final payload scenario | Rendered files | Published modules | Imported/snapshotted records | Result |
|---|---:|---:|---:|---|
| forky / desktop | 1121 | 160 | 160 | Passed in explicit POSIX fixture |
| forky / server | 1117 | 102 | 102 | Passed in explicit POSIX fixture |
| trixie / desktop | 1121 | 160 | 160 | Passed in explicit POSIX fixture |
| trixie / server | 1117 | 102 | 102 | Passed in explicit POSIX fixture |

These four scenarios committed **524 total records**. The separately selected
regression groups passed 77 renderer/publication/ownership/provenance/service
methods and 36 tooling/isolation/preparation methods. Coverage includes malformed
rows, traversal, unsafe metadata, symlinks/hardlinks, count/size bounds, empty or
corrupt journals, deletion/update semantics, retained prior bytes after failed
publication, bounded child status, advisory diagnostic failures, and a 250-file
publication batch. The exact old full renderer fails compilation with its
unmatched-bracket diagnostic; the final authored renderer and both exact archived
copies compile successfully. Phase validation checks 256 individual bytes,
256 embedded bytes and 18 multi-byte/boundary cases.

Actual typed producers were rerun with the final payload in all four scenarios.
Desktop scenarios validate 13 outputs each, and selected server scenarios 2 each,
using strict JSON, TOML and INI checks. The four Zsh startup files also passed
native `zsh -f -n` parsing in the private image.

The runtime boundary was a disposable rootless private image with read-only
copied source/runtime bytes, private PID/mount/network/IPC/UTS/cgroup namespaces,
no host binds, host devices, package state or service sockets, dropped
capabilities, no-new-privileges, bounded process sessions and a 360-second outer
deadline. A private 32 MiB `/var/lib` mount contains the publication tests. The
private `/dev/null` is an ordinary empty file, a documented fixture limitation.
Every stage completed without timeout/cancellation, direct children were reaped,
and the outer namespace ended. The overall exit is 1 because required dependency
and BusyBox gates correctly remain failed.

- Image manifest SHA-256: `5c514aa557f4f21e44c39e74916cf14dbcbc56e7710b40f036c0253c34dab3c8`
- Complete captured native log SHA-256: `20a78faa1b068171f59b5a4c833e34b7a40aa8d35549800f0866eafaf8f5c1e7`

## Whole-source and target `/usr` audit

The broad source sweep examined 3,039 regular files before delivery-evidence
serialization, including 1,699 target files. Documentation/evidence additions
account for the final packaged count. Source checks are distinct from target
execution or complete language/runtime acceptance.

| Check | Final source coverage | Outcome |
|---|---:|---|
| Python AST | 591 files plus 22 embedded programs| Passed |
| Shell syntax | 341 direct scripts: 334 Dash and 7 Bash| Passed |
| Embedded shell/preseed | 149 occurrences / 148 unique, plus 5 changed complete drivers| Passed |
| AWK | 302 occurrences / 156 unique; 271 production occurrences / 151 unique| Mawk compiler-only parse passed; raw-slash portability scan clear |
| JavaScript | 11 programs| Node parser passed |
| Structured data | 236 JSON, 46 YAML, 24 XML, 10 raw TOML, 41 INI| Passed |
| Retained auxiliary evidence | 10 Lua, 2 C, 31 CSS, 28 desktop entries| Exact source hashes unchanged from accepted earlier checks |
| Exact suite archive equality | 348 audited source members per suite, containing 201 AWK occurrences each| Matches authored bytes and manifest |

The target `d-i/debian/hooks/target/usr/**` inventory contains 670 regular files
and 11,269,069 bytes, with 670 unique contents, zero exact duplicate groups, no
missing source owners, no archive/source byte mismatch and no normalized
destination collision for either selected family. Shared Perl publication has
102 common modules and 58 desktop modules; server selection publishes 102 and
desktop selection 160. All 182 profile publishers reference existing unique
sources. These are exact-byte and ownership checks; they do not claim that all
possible semantic similarities can safely be merged.

The two full changed-source contract audits also checked current source/manifest
equality, all 22 role-combination plans, 734 render fields, 13 managed application
owners, suite selection, publication barriers and the earlier optimization
contracts. Their only reported errors are missing required BusyBox/ShellCheck
tools, and their nonzero status is preserved.

## Performance and reliability

The ownership grammar now has one owner. Each import remains a single streaming
AWK pass; snapshot retains its single bounded last-record/deletion pass. No
per-file interpreter loop or new runtime package dependency was added. The
existing batched publication, prepared Perl reuse, common/family ownership and
runtime-source deduplication remain intact and are covered by the current
regressions and exact archive comparison.

The normal compressed payload is 10,269,768 bytes,
compared with 11,923,852 bytes in the original
supplied archive: **13.87% smaller**. Expanded payload bytes
are 34,627,450, compared with
40,306,051: **14.09% smaller**.
These are measured artifact sizes. Installer elapsed-time or hardware performance
was not benchmarked, so no speedup percentage is claimed.

## Verification gaps that remain

1. **Native BusyBox and ShellCheck were unavailable.** The mandatory BusyBox
   ownership method fails explicitly for the missing binary, and the default
   preparer refuses to proceed. The source repair is supported by the BusyBox
   lexer and exact negative controls; native handoff execution here used
   Dash/Mawk. The complete static gates also retain their missing-tool failures.
2. **The private image lacks noncore Perl dependencies.** The complete inventory
   attempted 190 standalone programs and 10 production embedded programs: 30
   passed, 170 stopped at missing imports, predominantly `Moo`. The separate
   canonical 190-file gate passed 29 and blocked 161; it is overlapping coverage,
   not 190 additional programs. Imports were neither stripped nor stubbed for
   either complete compiler gate. Both suite package owners and all 22 compiled
   package plans remain byte-identical to previously reviewed declarations;
   this is not package-installation proof.
3. **A complete Debian Installer boot/install, first boot, services, AppArmor
   loading, networking activation and real hardware acceptance were not run.**
   HCL and some consumer-specific checks also lack a suitable native parser.
   No unconditional “zero issues anywhere” or complete-install success is claimed.
4. **`offline/` remains the supplied separate historical snapshot.** It is
   preserved in the complete source tree and was not rebuilt as the R5 normal
   preseed release. Do not substitute its payload for the normal suite files.

## Deploy the matching normal-suite files

Extract `debian-preseed-complete-r5-20261119.zip` into a fresh directory. The ZIP
retains the original `debian-preseed.bak/` root, POSIX file/directory modes and
empty directories. For the selected normal suite, publish the matching complete
set below from this extraction and boot its matching preseed. The rendered
payload is authenticated by these generated files; replacing only the loose
`render.pl` source does not update an already generated or fetched payload.

```text
d-i/<forky-or-trixie>/preseed.cfg
d-i/<forky-or-trixie>/source.sh
d-i/<forky-or-trixie>/payload.tar.gz
d-i/<forky-or-trixie>/payload.manifest
d-i/<forky-or-trixie>/receipt.json
d-i/<forky-or-trixie>/support-matrix.json
```

| Identity | Expected value |
|---|---|
| Release | `a8b81c64382235d5af48d0d86b0958b4415c17738a7698f3601e1c901d0a1d35` |
| Source fingerprint | `cc579b2be6680092eb4c1a1b0bbd843dbf3b63d894c15c43b09f7a7ca0a2b540` |
| Payload, either suite | `91735463de4fb13a58f56f4c371e745ea20927d2217e170b937253c93e4423b9` |
| Manifest, either suite | `0159f53cb792c87733187984a982f013b29de454a81f7cbd1f0a893e4a8fdeb8` |
| Actual copied renderer | `e2402d0c03e4b3cf1323b925fce74409670f6ace170f20dbe4b9aaed9ecbffe3` |

The advisory `target renderer provenance` log records the release and these
archive/manifest/renderer hashes immediately before rendering. This makes the
selected bytes identifiable on an installer run. No deployment, remote publish,
repository push or target-machine operation was performed by this repair.

`make build` was run twice using the unchanged reviewed pure generator. It
wrote only allowed flat suite products; the second run changed no file, and all
12 product hashes matched. Eight products changed against R4; the transport
and support matrix remained byte-identical. Exact archive membership, every
manifest size/hash, source-owner references and frontend payload pins passed.

The accompanying authored patch is cumulative against the original supplied
`upload/debian-preseed.zip`; it excludes exactly the 12 reproducible generated
products and private/cache directories. The full ZIP includes those products.
The delivery packager verifies every ZIP member's CRC, bytes and POSIX mode,
then actually applies the patch to a private sparse original tree and compares
all resulting authored bytes and Git executable modes. Artifact SHA-256 values
are provided with the downloadable delivery after final packaging, avoiding a
self-referential archive checksum inside the archive itself.

## Included evidence

The complete source includes `docs/validation/ownership-repair-r5-20261119.json`
and the exact `changed-paths-round5-20261119.tsv` manifest. The same directory
contains current native stage/test diagnostics, four ownership preparations,
typed producer reports, both complete Perl reports, AWK/source/archive audits,
the complete target `/usr` ownership inventory, package-plan provenance and
reproducible-build hashes. The separate `nonperl-syntax-r5-20261119.md` explains
parser scope and corrected earlier Mawk portability assumptions. Historical
reports retain their dated scope and are not relabeled as execution of R5.

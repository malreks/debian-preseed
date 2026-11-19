# Round 5 non-Perl syntax and AWK portability review

Date: 2026-11-19. Release:
`a8b81c64382235d5af48d0d86b0958b4415c17738a7698f3601e1c901d0a1d35`.

This report records the source and data checks for the ownership handoff repair.
It supersedes the **AWK portability conclusion** in the historical round 4
report. That report correctly recorded Mawk compiler acceptance, but Mawk
acceptance did not establish compatibility with the BusyBox AWK interpreter
used by the installer. The previous full-payload preparation also stopped
before the actual ownership-journal importer. The current maintained preparation
includes that handoff; its native results belong to the combined round 5 record.

The final source inventory contained 3,039 regular files, including all 1,699
files under `d-i/debian/hooks/target/`. These counts were captured before this
report was added. No repository tests, installer entrypoints, services, package
managers, hardware helpers or managed target commands ran during this source
review. Native fixture execution is recorded separately by the private-image
supervisor.

## Confirmed AWK delimiter defect and shared repair

The Debian-packaged BusyBox 1.37.0 AWK
[lexer implementation](https://sources.debian.org/src/busybox/1:1.37.0-10.1/editors/awk.c)
ends a regular-expression token at its first unescaped slash. Its token scanner
does not exempt bracket expressions. Thus `/[A-Za-z0-9_./]/` does not deliver the
intended complete character class to that interpreter. The
[GNU Awk escape-sequence documentation](https://www.gnu.org/software/gawk/manual/html_node/Escape-Sequences.html)
also specifies escaping a slash that belongs to a slash-delimited expression.

The complete decoded-literal census identified nine historical occurrences:

| Owner in the preceding release | Raw slash occurrences | Corrected owner |
| --- | ---: | --- |
| Ownership import validation in `scripts/common/modules/target-publication.sh` | 4 | `installer_target_ownership_filter validate` |
| Ownership snapshot validation in the same module | 4 | `installer_target_ownership_filter snapshot` |
| `crowdsec_stage_logging_overlay` in `scripts/late/crowdsec.sh` | 1 | The same overlay validator, with its literal slash escaped |

The ownership module now has one AWK grammar for both operations. Each slash
inside the four shared classes is written `\/`. The existing accepted alphabet,
absolute-path normalization, field count, row-length limit, row-count limit and
mode grammar remain intact. The shared program records invalid input in `bad`
and checks it in `END`, so an early rejection cannot become a successful final
status. Its import-validation mode does not retain rows or allocate the snapshot
arrays. Snapshot mode retains the existing last-record and deletion behavior.

The CrowdSec change adds one escape byte to its existing value expression:
`/^[A-Za-z0-9_.\/:-]+$/`. It preserves the permitted characters and the existing
overlay preservation decisions.

The source census also checked absolute-path AWK invocations that the preceding
private extractor omitted, including the GRUB helper, the swaylock wrapper and
the failed-unit notification path. It decoded literal shell programs contained
in Python source, including the offline acquisition adapter. No further raw
slash in a regexp bracket expression was found in the current production
literals.

### Regression checks

`tools/post_change_check.py` now has a dedicated lexical delimiter check for the
actual shared ownership-filter and CrowdSec program bodies. It decodes their
literal shell arguments as data and checks that both ownership callers route to
the single filter. The checker distinguishes AWK strings, comments, division
operators and regexp tokens. This focused check does not claim to be a complete
AWK parser or a replacement for interpreter-specific behavior validation.

The guarded fixture `tools/tests/test_awk_literal_portability_20261119.py`
contains four methods covering the actual current owners, the historical raw
class spellings, string/comment/division distinctions, and missing or dynamic
program arguments. Their private-image execution results are recorded in the
combined round 5 validation record; they were not run on the development host.

The independent source census used the exact three retained round 4 AWK program
bodies as negative controls. It found four offending slash bytes in the old
importer, four in the old snapshot program and one in CrowdSec. The current
census found zero. Those historical negatives are data-only lexical checks,
not a claim that BusyBox was executed during this source review.

## Final parser coverage

| Source class | Coverage | Result and boundary |
| --- | ---: | --- |
| Python sources, templates and extensionless entrypoints | 591 | AST parsing passed; no repository imports |
| Direct shell sources and templates | 341 | 334 Dash and seven Bash parser-only checks passed |
| Literal child-shell and preseed command bodies | 149 occurrences / 148 unique | Parser-only checks passed after literal quoting and continuation decoding |
| Complete changed preparer and regression-fixture shell drivers | 5 | AST-extracted literal data passed Dash parser-only checks |
| Literal Python command/heredoc bodies | 22 unique | AST parsing passed |
| AWK source/literal occurrences | 302 / 156 unique | Mawk compiler-only checks passed; this is Mawk-specific evidence |
| Production subset of AWK literals | 271 occurrences / 151 unique | No unescaped slash inside the identified regexp classes |
| Polkit JavaScript sources and templates | 11 | Node parser-only checks passed |
| Strict JSON source/data files | 236 | Parsed with duplicate keys and nonfinite values rejected |
| YAML source/data files | 46 | Safe YAML parsing passed |
| XML, SVG and XML policy files | 24 | XML parsing passed without external-entity resolution |
| Raw TOML source/data files | 10 | Parsing passed |
| INI, desktop and NetworkManager files | 41 | Strict raw INI parsing passed |
| Lua and Nmap NSE sources | 10 | Source hashes unchanged from the accepted text-only compilation |
| C fixture sources | 2 | Source hashes unchanged from the accepted syntax-only compilation |
| CSS sources and templates | 31 | Source hashes unchanged from lexical-balance and 22 local-import checks |
| Desktop-entry sources | 28 | Source hashes unchanged: 26 generic-validator passes, two consumer-specific extensions |

There were no unexpected source parser failures. The sixteen preseed command
strings consist of eight current suite launch strings and eight historical
baseline reference strings. The five separately parsed shell drivers are the
maintained map producer, maintained ownership handoff, ownership regression,
renderer-provenance regression and service-name regression. These are parser
occurrences, not executed behavioral cases.

Twelve typed structured templates intentionally do not parse in their raw source
form. All twelve retain the exact source hashes from the prior actual-producer
and renderer validation: Wi-Fi configuration; application, proxy and Tailscale
network JSON; three hardware-policy JSON files; software release policy; greeter
TOML; and the Code, Sleek and Wayscriber appearance files. This source refresh
does not relabel those raw inputs as successful final-format parses. Their
actual rendered-output evidence and role selections are explained in the
historical report, with any repeated native run reported separately.

One AWK expression in `scripts/desktop/detect.sh.tmpl` is constructed from a
validated decimal value and fixed numeric bounds. It has no regexp bracket
expression and does not contain this delimiter defect. Literal-only parser
counts exclude its eventual runtime expression. File-based AWK calls resolve
to the seven separately inventoried `.awk` source files. Other unmatched AWK
mentions were reviewed availability checks, diagnostic strings, command lists,
or fixture/parser-selection adapters that forward an existing program.

## Exact generated-product checks

Both normal suite archives contain the same corrected source bytes. Each
archive was read as data without extraction or execution. For each suite, 348
audited source members match both the current authored file and their manifest
size/hash. Those members contain 201 decoded AWK program occurrences. The
comparison explicitly requires the shared ownership module, CrowdSec owner,
shared Perl renderer and `00rendertarget` base hook to be present and equal.

| Product identity | SHA-256 |
| --- | --- |
| Forky and Trixie normal payload archives | `91735463de4fb13a58f56f4c371e745ea20927d2217e170b937253c93e4423b9` |
| Both normal payload manifests | `0159f53cb792c87733187984a982f013b29de454a81f7cbd1f0a893e4a8fdeb8` |
| Captured source fingerprint | `cc579b2be6680092eb4c1a1b0bbd843dbf3b63d894c15c43b09f7a7ca0a2b540` |
| Shared ownership source module | `821d8a4191c1334add3b9696055fb219b436fca1f2f5631b772b46eb541fc92e` |
| CrowdSec source owner | `af982b434a46c3c81dc5f916365ef1f26c08584196e8c942dc6ef22f0c46cf79` |

The final generated `source.sh` and preseed products were included in the direct
and decoded-shell source checks. This establishes agreement between the local
authored source, captured archives, manifests and generated launch products.
It cannot establish which bytes a separately booted installer fetched from an
external deployment.

## Renderer provenance review

The base hook now logs the release identifier and the archive, manifest and
copied-renderer SHA-256 values immediately before invoking the renderer. The
helper accepts only bounded-format hexadecimal identifiers for output. It does
not print the identity's origin URL, account data or map values. It hashes the
copied `render.pl` through the existing SHA-256 helper on standard input once.
Missing, indirect or malformed identity data and hashing errors produce
`unavailable` fields. Its guarded call and explicit successful return preserve
the renderer's normal status owner, including under `set -e`.

Independent review traced the complete helper, hasher and four-method guarded
fixture. The fixture uses private files, a sanitized environment, an empty
search path, a fixed SHA-256 executable and the bounded shared stage supervisor.
Cleanup uncertainty preserves its private evidence. Neither the diagnostic nor
the fixture needs a network request or an installer command replay.

## Verification limits

Mawk compilation and the source-derived BusyBox delimiter check are distinct
results. Direct BusyBox execution is not claimed by this report. Missing
BusyBox/ShellCheck tools must remain explicitly unavailable in the aggregate
checker; a successful independent parser does not satisfy those gates.

The current Lua, C, CSS and desktop-entry inputs were hash-verified against
their earlier results instead of rerunning unchanged inputs. The four accepted
Zsh parser results remain private-image evidence; no Zsh startup file was run
on the host. CSS lexical checks do not establish acceptance of every property
by its runtime consumer. The Packer HCL template still lacks an available HCL
parser in this environment. The two desktop-entry extensions retain their
session/Xfce owning-consumer boundary.

This review establishes source parsing, specific delimiter portability,
shared-call wiring and exact local archive identity. Boot, a complete physical
installation, active services, networking, application launches and hardware
performance require corresponding runtime evidence and are not inferred from
these checks.

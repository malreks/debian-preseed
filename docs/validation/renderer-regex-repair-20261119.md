# Shared renderer regex repair and phase grammar hardening

Date: 2026-11-19.

## Failure established by the supplied logs

The `installer.log` supplied for the initial repair identifies the delivered release
`b4de1b60b6be8c7bae263af79a19f931c1d63eb7673eef35540b5c7feb1f3e42`,
Forky, the desktop/full role, and `profile/desktop/btrfs-de-p15s`. Its final
preparation attempt reaches `render_target_source_snapshot` and records the
Perl compiler diagnostic:

```text
Unmatched [ in regex; marked by <-- HERE in m/\A[ <-- HERE A-Za-z0-9_./ at .../render.pl line 828.
```

The renderer exits with status 255 before its `main` routine can execute. The
reported line belongs to publication-context validation, but Perl compiles
the whole file before selecting any entrypoint. The fault therefore also
blocks the initial base-stage preparation. It is not a server-only failure.

## Repair and shared contract

The `PHASE` expression in
[`render.pl`](../../d-i/debian/scripts/common/render.pl) used `/.../` delimiters
while its character class contained an unescaped `/`. The expression now uses
paired `m{...}` delimiters. The intended phase alphabet remains ASCII letters,
digits, underscore, dot, slash, at sign, plus, colon and hyphen.

The initial repair also spelled the at sign explicitly as `\@` in the
relative-selector, absolute-path, canonical-path-map and phase expressions.
This preserved their literal
character alphabets. Perl's regex parsing rules already exempt `@+` and `@-`
from interpolation, so the previous `@+` spelling is not evidence of a second
renderer defect. See the [official perlop regex parsing rules](https://perldoc.perl.org/perlop).

The changes retain the existing path normalization, source-family checks,
private ancestry checks, ownership checks, bounded inputs, publication
journaling, single shared renderer and batching. No extra production process,
interpreter, source scan or runtime lookup was added.

All four entrypoint owners were traced:

| Entry point | Calling owner | Effect of the repair |
| --- | --- | --- |
| Full prepared source snapshot | `hooks/installer/base-stage.d/00rendertarget` | The complete program can compile before early tree rendering and shared Perl publication |
| Deferred `--file` rendering | `scripts/common/modules/files-logging.sh` | Uses the same corrected program and literal path grammar |
| Batched `--publish` operations | `scripts/common/modules/target-publication.sh` | Phase validation uses the intended literal alphabet and retains context/plan agreement |
| Final `--cleanup` | `scripts/late/dispatch.sh` | Uses the same corrected program without changing cleanup ownership or receipt validation |

The shell publication context and ownership adapters already describe the
same intended phase alphabet; their grammars were not widened.

## Regression source added

Four initial guarded methods cover the repaired boundary:

1. Compile the complete renderer with `perl -f -c` before supplying runtime
   inputs, and assert that no rendering output is created.
2. Render a real prepared source fixture with literal `@` and `+` in its
   workspace, source member, canonical path-map value and shared Perl
   destination.
3. Pass ordinary and punctuation-bearing phase identifiers through the real
   publication parser, reaching the deliberate empty-plan rejection.
4. Reject empty phases and phases containing spaces, semicolons, dollar signs
   or brackets before plan validation.

The phase cases allocate only their private `/workspace` fixture. Their empty
plan ensures no target destination can be published, while retaining the
production parser and all context checks. The fixture helper's new optional
`phase` argument defaults to the previous `late-command` value and supplies
both the context and operation records consistently.

Sources:

- [`test_target_render_20261116.py`](../../d-i/debian/tests/test_target_render_20261116.py)
- [`test_publication_batch_20261119.py`](../../d-i/debian/tests/test_publication_batch_20261119.py)
- [`fixture_publication.py`](../../d-i/debian/tests/fixture_publication.py)

## Source review and execution classification

This focused review inspected all 1,084 lines of the renderer, its four
entrypoint owners, the relevant context producers and the edited fixtures.
The three Python fixture sources passed AST parsing; all four edited files
passed UTF-8 and whitespace checks. The four changed regex sites are recorded
in the companion evidence. No other definite renderer defect was established
by this source review.

Source inspection and AST parsing do not prove Perl compilation or installed
behavior. This focused review did not itself execute Perl, test discovery,
installer hooks, package managers, services or host management programs.
Any isolated compiler or behavioral runs performed for the final delivery are
recorded separately in that delivery's validation record. The isolation guards
and production path restrictions remain unchanged.

## Follow-up phase spelling hardening

After the same line-828 failure was reported again, the available current
source, both normal suite payloads and the delivered ZIP were re-inspected as
data. Their pre-hardening renderer was the already-correct paired-delimiter
version with SHA-256
`04baa6387169c0d0fbedcbb4a8360504eaae8b53361931a5d0d57c2c93fb6898`.
Its line 828 used:

```perl
$context->{PHASE} =~ m{\A[A-Za-z0-9_./\@+:-]+\z}
```

That expression is valid. The retained earlier renderer with SHA-256
`2cdb1db8733bb3bde5e71b34314dd670598f8440cb5b8a5494300eaff18eb2c3`
contains the original slash-delimited expression at the same line. Those are
different byte identities. Source comparison does not establish which bytes
the user's repeated failure executed; the selected payload and copied renderer
identity must establish that separately.

The phase expression now spells the slash and at sign with explicit byte
escapes and places the literal hyphen first:

```perl
$context->{PHASE} =~ m{\A[-A-Za-z0-9_.\x2f\x40+:]+\z}
```

This is a spelling hardening of the valid expression, not a second diagnosed
syntax repair. It keeps the paired delimiters, full-string anchors and
one-or-more requirement. An independent source-level character-class decoder
found exactly the same **69 ASCII bytes** in both alphabets: 26 uppercase
letters, 26 lowercase letters, 10 digits and the seven punctuation bytes
`_ . / @ + : -`. Empty values and any other byte remain invalid. The other
three path expressions were not changed.

The hardened renderer remains 1,084 lines and is 54,926 bytes, with SHA-256
`e2402d0c03e4b3cf1323b925fce74409670f6ace170f20dbe4b9aaed9ecbffe3`.
Only the phase predicate changed, adding five source bytes without adding a
runtime lookup, another regex pass or an interpreter process.

Three additional methods in the existing guarded
`PublicationPhaseValidationTests` cover this boundary:

1. Exercise all 256 byte values individually and embedded between valid
   prefixes/suffixes, for 512 cases against the exact production predicate.
2. Check 18 explicit empty, multicharacter, boundary, control-byte and UTF-8
   cases, including full-string rejection of leading/trailing NUL and newline.
3. Compile the complete authored renderer and exact renderer members from both
   current suite archives. Each archive member must first equal the authored
   bytes and its manifest record. These checks cannot silently compile only a
   repaired source file while shipping a different renderer.

The selected phase class now contains five methods; its existing two methods
still exercise full publication-context validation with an empty plan. All
state is private beneath the guest's `/workspace`. Native subprocesses use
explicit interpreter paths, sanitized environments and bounded timeouts.
This review parsed fixture source and compared bytes only; the release owner
records the separately executed isolated results after regenerating the suite
products.

## Follow-up ownership handoff coverage

The subsequent failure reports `commit_target_ownership`, after renderer
completion. The renderer's three-column publication schema agrees with the
base hook and ownership importer:

| Boundary | Fields in order |
| --- | --- |
| Renderer `published-assets.tsv` | Physical source member, absolute target, mode |
| Base-hook conversion | Absolute target, physical source member, `plain`, installer phase, mode |
| Ownership journal and snapshot | The same five fields |

The earlier full-payload preparation fixtures exercised the real renderer and
Perl module publication, but stopped before this shell-side ownership import.
That was a concrete integration coverage gap. The maintained
`tools/prepare_syntax_fixture.py` now continues through the exact captured
base-hook AWK conversion, real ownership import and real journal snapshot.
It sources the actual lifecycle metadata and ancestry checks. Only the fatal
error transport is fixture-local, so a rejected input returns failure instead
of entering the installer's interactive hold loop.

The captured lifecycle, publication module and base hook must equal their
current authored source before any map producer runs. Their hashes are checked
again after rendering. The completed handoff must preserve every publication
row in the converted batch and journal, and every row in the snapshot
regardless of AWK array iteration order. The report binds the three source
owners, exact conversion bytes, renderer receipt, input rows, journal and
canonical snapshot digest. All new files remain within the guarded private
scenario, and the handoff inherits the shared bounded process/session owner,
resource limits and capped diagnostics.

Ownership validation defaults to BusyBox and fails if that runtime is absent.
An explicit `--ownership-runtime posix` option runs fixed Dash and AWK paths
for reduced-dialect evidence; its report records
`ownership.busybox_validation=false` and executable hashes. It never silently
substitutes this mode for BusyBox. The canonical auditor's ordinary call keeps
the strict default. A POSIX-mode pass is not BusyBox execution evidence.

Two additional guarded preparer methods cover a complete real desktop payload
through ownership commit and rejection of an internally consistent archive
containing a stale publication owner. The preparer test file now contains nine
methods. The ownership module's separate dialect and malformed-input fixtures
belong to its repair review. Native execution of this extension is recorded by
the release owner after the current suite products are rebuilt; this focused
source review does not claim those executions have passed.

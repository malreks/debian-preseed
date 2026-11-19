# Desktop Appearance operation inputs — 2026-11-19

## Scope and evidence boundary

This change reuses registry and file inputs within one Desktop Appearance
operation and binds prepared output to the bytes from which it was rendered.
It changes five existing modules in
`d-i/debian/hooks/target/usr/local/lib/desktop/python3/dist-packages/labwc_appearance/`:
`fields.py`, `transaction.py`, `engine.py`, `greeter.py`, and `wallpaper.py`.
It adds no installed module, entrypoint, configuration key, service, polling
loop, package dependency, or AppArmor permission.

The checks recorded here parse source as data. No project module or fixture
was imported, no native test or desktop command was run, and no timing result
was measured. Native fixture execution remains deferred to the approved
disposable image boundary in `docs/test-isolation.md`. Host scratch remained
in the private `.build/validation/round2/assets/` tree, with `TMPDIR`, `TMP`,
and `TEMP` explicitly set to its `tmp` child for checks.

## Installed call graph reviewed

The public `labwc-desktop-appearance` wrapper still enters
`labwc_appearance.cli`. Its GTK editor reads `fields.current_values(registry)`
and saves through `fields.apply(selected)`; theme selections enter
`engine.apply_choice`. The authenticated `labwc-appearance-greeter` wrapper
still enters `greeter.main`, dispatching theme, field, and wallpaper requests
to their existing owners. All seven runtime calls of `transaction.plan` were
inspected: two in `engine.py`, three in `fields.py`, one in `greeter.py`, and
one in `wallpaper.py`.

The shared `managed_workflows.fs.Tree` reader and writer were inspected but
not changed. Its descriptor-relative ancestry, regular-file, single-link,
ownership, permission, bounded-read, and read-identity checks remain the
file-access boundary. The installer module list in
`scripts/desktop/components/appearance.sh`, wrapper import roots, and exact
Appearance AppArmor domains still cover the same modules and paths.

The desktop session/event review also covered `labwc-waybar-events.tmpl`,
`labwc-output-watch`, and `labwc-session-state.tmpl`. Their event-driven
readers, coalescing, reconciliation, and bounded session-close checks did not
justify an additional lifecycle rewrite. Native Waybar module identity and
the Zoom/Discord eligibility boundary are unaffected.

## Input reuse and source-derived work counts

`fields.current_values` keeps decoded file lines in a local LRU for that
invocation only. Missing, unreadable, and undecodable paths are local misses
in the same cache. A new refresh builds a new cache and reads new content.
The cache charges `128 + 4 * input_bytes + 96 * line_count` per decoded file,
with an 8,388,608-unit budget. The charge covers input size and line overhead;
it is an accounting bound, not a measurement of Python heap allocation.
Eviction or an individually oversized cache entry causes ordinary fresh
reads, so a larger working set is not rejected merely for exceeding the
reuse budget. Native grammar and ambiguous-mapping rejection are unchanged.

`_prepare_user_updates` now groups mappings by each candidate physical path
before reading it. Each existing file is rendered from that one read. The
coordinator passes one validated registry through its user-side helpers,
including greeter request preparation and a possible dock shutdown pass.
The authenticated root field helper still loads and validates its own
root-owned registry; user data does not become privileged authority.

The authored registry contains 567 fields and 672 mappings: 573 user mappings
refer to 36 user paths, and the other 99 mappings refer to greeter files.
The following counts derive from the previous and changed call graphs:

| Operation | Before | After |
| --- | --- | --- |
| Current values, every first-choice mapping readable and working set fitting the cache | 567 file reads and decodes | 38 unique file reads and decodes |
| Prepare all user field values | 573 × 3 = 1,719 variant probes, followed by one reread for each present grouped file | 36 × 3 = 108 unique variant reads, used directly for rendering |
| User-only field apply, registry loads | 3 | 1 |
| Field apply including a greeter request, registry loads in the user process | 4 | 1 |
| Field apply including greeter and dock shutdown, registry loads in the user process | 5 | 1 |
| Authenticated greeter field preparation, registry loads in the root process | 1 | 1 |

The 38 first-choice authored source files total 120,047 bytes and have a
combined cache charge of 738,780, below the per-operation budget. These are
source-template sizes, not installed byte counts or runtime measurements.
User customizations, fallback mappings, and cache eviction can change actual
reads. No wall-time estimate follows from these counts. Fresh security reads
at transaction planning, application, rollback, and committed verification
are deliberately retained.

## Prepared-byte transaction binding

Previously a coordinator could read a file, render from those bytes, and
then let `transaction.plan` capture different bytes as its rollback image.
An independent edit in that interval could therefore be overwritten by a
candidate rendered from an older version.

Every runtime renderer now supplies `expected=` images to `transaction.plan`.
The planner requires exactly the candidate key set and compares a fresh
guarded read with the corresponding prepared bytes, including expected
absence and candidates that would otherwise be no-ops. A mismatch fails
before the journal or prepared configuration files are published. Wallpaper's
immutable image staging still precedes its CSS transaction, as before; this
check binds the CSS input and does not claim to roll back image staging.
Theme state JSON is
bound in the same way as native configuration. The journal schema and
aggregate recovery limits are unchanged.

The dock still stops under its existing account lock. Fields are prepared
again after shutdown, and the theme coordinator rereads and rerenders its
dock file, retaining QSettings layout saves in both candidate and rollback
images. Snapshots are not reused over this barrier. Application and recovery
continue to reread files and reject an unrelated writer's changed content.
Root greeter and wallpaper callers have the same preparation check. Existing
atomic writes, ownership/modes, durable decisions, root commit/rollback,
retained-evidence errors, and service restart ownership remain in place.

## Fixtures and checks

Authored, unexecuted fixtures:

- `d-i/debian/tests/test_appearance_snapshot_20261119.py`: one read/decode for
  many fields; fresh next refresh; missing/error/invalid-UTF-8 fallback reuse;
  LRU eviction; one variant read per preparation; CRLF preservation; one user
  registry load; greeter request registry reuse; fresh dock shutdown inputs;
  rejection before journal/refresh; all seven caller bindings and independent
  root registry ownership.
- `d-i/debian/tests/test_gitbuild_appearance_20260928.py`: concurrent native
  bytes and expected absence; no-op candidate checks; incomplete snapshot
  rejection; existing apply/rollback checks with supplied snapshots; theme
  state created between rendering and planning.
- `d-i/debian/tests/test_appearance_picker_contract_20261027.py`: corrected
  source locations to include the physical `lib/desktop` family and changed
  its greeter source assertion to the canonical installer placeholder.

Python AST parsing succeeded for all five changed runtime modules and all
three affected fixtures. A separate AST inventory confirmed all seven
runtime planner calls include `expected=`. Registry JSON and source files
were read as data to derive the counts above. The parent integration owns
pure payload generation and the complete changed-file audit; their result
must be reported separately. These static checks do not establish a passing
native fixture, GUI, Polkit, AppArmor, service, or target integration result.

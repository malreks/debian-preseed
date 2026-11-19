# Shared target asset publication, 2026-11-19

## Result and evidence boundary

The existing `d-i/debian/scripts/common/render.pl` now also owns bounded target
asset publication. Desktop and logging staging submit a private declarative
plan and flush it at dependency barriers. A nonempty flush launches the target
Perl interpreter once, binds the prepared source inventory and canonical path
map once, reads each distinct source once, renders and preflights the complete
batch, then publishes each destination atomically. No second renderer or
target package installation was introduced.

This record describes implemented source and source-level checks. It does not
claim that Perl compilation, a native fixture, a complete installer run, or a
wall-time benchmark passed. No approved disposable image/runtime was available
in this workspace. The repository isolation guard therefore prevented native
execution; there was no host fallback. The coordinating change report records
the separate pure build and whole-checkout audit results.

## Producer, consumer and ownership changes

| Owner | Implemented responsibility |
| --- | --- |
| `d-i/debian/scripts/common/render.pl` | Existing scalar/path renderer, bounded length-prefixed publication plan loader, prepared member resolution, candidate preflight, atomic publication, durability, primary/future defaults, and redacted batch counters. |
| `d-i/debian/scripts/common/modules/target-publication.sh` | Begin/add/flush/finish adapters; one restricted context per batch; one interpreter per nonempty flush; retained failure evidence; exact-key ownership journal and bounded snapshot. |
| `d-i/debian/scripts/late/target-assets.sh` | Thin queued adapters for plain, resource, template-input, appearance-registry and generated assets; logging batch; explicit barrier before legacy typed publication and shell readers. |
| `d-i/debian/scripts/desktop/components/rendering-access.sh` | Scalar and declared Labwc block records; the shared Perl owner handles primary and future-account values. |
| `d-i/debian/scripts/desktop/components/stage-assets.sh` | Role gating followed by the shared publication adapter, without a per-asset source inventory probe. |
| `d-i/debian/scripts/desktop/components/target-assets.sh` | Desktop publication batch and barriers before direct shell mutations. |
| `d-i/debian/scripts/common/target.sh` | Flush at the shared `target_exec` boundary before normal, quiet, captured, tested, interactive or direct target commands. |
| `d-i/debian/scripts/common/primary-defaults.py` | Existing account-aware atomic HOME publisher, extended with one exact relative-file selection so a late asset does not replay other defaults. |
| `d-i/debian/scripts/desktop/waypaper.sh` | Publish the future template through the batch and only the independent primary launcher through the existing user-owned HOME boundary. |
| `d-i/debian/scripts/desktop/components/user-session.sh` | Flush queued user-unit drop-ins before shell globbing and private directory-mode normalization. |
| `d-i/debian/scripts/common/modules/files-logging.sh` | Flush before the retained legacy single-file typed renderer. |
| `d-i/debian/hooks/installer/base-stage.d/00rendertarget` | One import of already-published Perl ownership records. |
| `d-i/debian/hooks/installer/finish-install.d/94zz-99-validate-target` | One exact-key ownership snapshot, followed by retained final mutable-target checks. |

The required Labwc enablement/readiness correction in the services component
and the earlier finish-install readiness block was handled separately. The
publication changes preserve that block.

The public repository configuration contains shared roots, not per-file
selectors. Fixed staging sources are physical root-relative members, including
quoted filenames containing spaces. Dynamic logical family, systemd and APT
leaves are resolved against the prepared member hash inside Perl. Resolution
rejects missing or ambiguous ownership, an incompatible role, another suite,
and installer authority files. Diagnostics and ownership records carry the
resolved physical member.

## Plan and context contract

The private plan begins with `publication-plan-v1` and a newline. Each operation
has a decimal field count followed by length-prefixed byte fields of the form
`length:value,`. The fixed nine fields are kind, source member, target path,
mode, owner, family, suite, phase and dependency group. Optional trailing fields
are scalar-name/value pairs, including three explicitly declared Labwc line
blocks. Neither configuration nor plan values are evaluated as shell or Perl
code. Byte lengths are produced under `LC_ALL=C`.

The loader bounds the plan to 16 MiB, 10,000 records, 1,033 fields per record,
100,000 aggregate fields and 1 MiB per field. Input and candidate byte budgets
remain enforced. Binary assets containing NUL retain their original bytes.

The context has 30 exact fields: 12 format, selection, phase, destination and
archive-identity fields, plus 18 existing repository roots for source
resolution. Those roots come from the existing restricted configuration owner;
they are not a new configuration authority. The source archive must match the
prepared `verified-v1 ARCHIVE_SHA MANIFEST_SHA BASE` identity. Old unverified
identity spellings are rejected.

## Security and behavior retained

Target containment remains in the existing mounted-target shell boundary and
the chrooted Perl publication boundary. Perl validates normalized absolute
target paths and every existing ancestor. It rejects symlinks, dangling links,
non-directory ancestors, multiply linked regular files, unsafe writeable
ancestors and unsafe file metadata. The one permitted shared ancestor is the
exact configured temporary root with root ownership and sticky mode 1777.
Private workspaces and reusable account template roots retain mode 0700.

Every candidate is rendered and validated before any target mutation. Files
are written to private temporaries beside their destination, receive requested
modes and root ownership before publication, and are published using the
existing atomic rename/exclusive-link logic with identity rechecks. Atomicity
is per destination. A failed batch is not represented as rolled back.

The plan, context and proposed ownership are synchronized before mutation.
Written files are synchronized once each, and affected ancestor directories
once each, before the successful ownership batch is published. Failure keeps
the private plan and available recovery evidence; adapters mark the batch as
failed and reject automatic replay. Ownership import or cleanup failure also
retains a failed batch. No shell source values are printed as diagnostics.

Already-published Perl modules retain the existing no-rewrite optimization.
When a later batch touches one, it validates current mutable metadata and
compares current bytes with the protected candidate. Identical bytes retain
the inode; changed or absent bytes are restored atomically. This destination
comparison is deliberately retained and separately counted.

Primary-account payload defaults are captured from the concrete rendered
result before reusable account templates are produced. Future-account values
use `$HOME` and `$USER`; derived home directories must remain below the
validated primary home before conversion. The existing account publisher still
owns actual user identity, UID/GID, private HOME publication and recovery.

Waypaper's late primary launcher uses an exact `.local/share/applications/waypaper.desktop`
selection in that existing account publisher. It cannot use the root-only
batch writer directly below a user-owned HOME. The selection rejects absent
files, directory selections, traversal and indirect ancestors, retains the
same descriptor-relative atomic writer, and leaves other primary defaults
untouched. The future template remains mode 0644; the primary launcher receives
the account UID/GID and mode 0600.

The helper-document tree is also owned by the primary account after runtime
storage normalization. Only prepared `DIR_TARGET_DOCS` sources targeting
`DIR_DATA_DOCS` at mode 0644 use the retained typed atomic handoff. Existing
target containment, ancestry, symlink and hardlink checks and the explicit
primary UID/GID assignment remain in that dedicated path. Source bytes already
passed base-stage rendering; the handoff validates unresolved markers and adds
no separate renderer. These caller corrections preserve the root-only ancestry
policy of the shared batch writer.

The ownership journal replaces a hashed filename per destination with one
bounded, exact-key last-write-wins snapshot. Deletes are explicit tombstones.
Malformed or incomplete rows fail verification. Finish-install continues to
check current installed files, containment, link count, byte bounds and
unresolved placeholders. The journal is not a substitute for checking mutable
target state.

Hardware/profile rendering whose values are discovered later remains behind
the existing typed boundary. That path flushes the batch first. Moving those
operations into an earlier batch would violate their dependency order.

## Source-level work counts and observability

| Work | Implemented bound or change |
| --- | --- |
| Interpreter startup | One target Perl invocation per nonempty flush, rather than one per rendered asset or Labwc block. Singleton callers still use one bounded batch. |
| Prepared inventory/path binding | One prepared-member read and one canonical path-map load per flush. |
| Source content reads | One per distinct resolved source per flush, held in an in-process cache. |
| Three Labwc deferred blocks | One in-memory rendering pass per primary/future candidate using the existing scalar/path functions. |
| Destination-path hashes for ownership | Zero. Exact target paths are journal keys. |
| Ownership publication | One import after each successful batch; one snapshot at final verification. |
| Mutable destinations | Required metadata checks remain; previously published Perl bytes are compared when that optimization applies. |
| Durability | One synchronization per written file and per distinct affected directory, after required preflight and before successful ownership commit. |

Each successful target batch emits one redacted stderr line with `phase`,
`barrier`, `records`, `files`, `source_reads`, `unique_input_bytes`,
`written_bytes`, `reused_files`, `destination_bytes`, and coarse
`elapsed_seconds`. These are actual counters from that future target run;
this source-review session did not generate installer timing evidence.

The new guarded 250-destination fixture expects one source read, one interpreter
launch and 250 published outputs. Those numbers describe an authored assertion,
not an executed benchmark or a claim of a 250-fold elapsed-time improvement.

## Checks performed and deferred

Parser-check commands used private checkout scratch under
`.build/validation/assets/tmp` with `TMPDIR`, `TMP` and `TEMP` set. No host
management helpers, services, package managers or installer entrypoints were
executed.

Performed checks:

- `/bin/sh -n` accepted the eleven changed shell owners listed above. This was a
  parser check; the scripts were not sourced or executed.
- Standard-library `ast.parse` accepted `tools/post_change_check.py`,
  `scripts/common/primary-defaults.py` and the eight changed publication/account
  fixture sources. Repository modules were neither
  imported nor executed.
- The source review traced plain, scalar, deferred-block, resource,
  template-input, appearance-registry and generated publication callers,
  dynamic family/systemd/APT source lookup, the base-stage import, primary
  defaults, target command barriers and final owned-file validation.
- A separate reviewer inspected the bounded plan, renderer, metadata checks,
  atomic writer, flush adapters and ownership commit as source. That review
  found no additional concrete defect; it is not a runtime proof.
- `git diff --check` could not run in this extracted archive tree because it
  has no Git metadata. The coordinating audit uses the attached archive as the
  baseline and records its own results.

Authored or migrated guest-only fixtures:

- `d-i/debian/tests/fixture_publication.py`: private prepared source, exact plan
  encoding and sanitized real-Perl invocation with no executable search path.
- `d-i/debian/tests/test_publication_batch_20261119.py`: shared-source counts,
  account split, three deferred blocks, binary suite/family parity, dynamic
  family/systemd/APT ownership, ambiguous or wrong-scope rejection, unsafe
  target/source cases, mutated Perl restoration, malformed plans, old identity
  rejection and interrupted-write evidence.
- `d-i/debian/tests/test_target_render_20261116.py`: existing rendering and
  typed-consumer cases adapted to the real batch boundary and direct members.
- `d-i/debian/tests/test_target_owned_scan.py`: exact-key updates, tombstones,
  spaced source names and malformed journal rejection.
- `d-i/debian/tests/test_placeholder_registry_contract.py`: deferred-block
  ownership moved to the shared renderer.
- `FutureAccountContracts` in
  `d-i/debian/tests/test_late_target_install_contracts.py`: mutate the actual
  Perl primary/future owner and the thin desktop adapter.
- `d-i/debian/tests/test_target_debconf_boundary.py`: all six noninteractive
  target command entrypoints require one successful publication barrier;
  failed publication prevents the command and protocol setup.
- `d-i/debian/tests/test_primary_payload_defaults.py`: selected user-owned HOME
  publication preserves sibling defaults and rejects missing/directory inputs
  and indirect user directories using the existing atomic writer.

None of those native fixtures was executed. Before claiming target compatibility
or end-to-end improvement, run them in the reviewed disposable Debian fixture
with its image identity, timeout and cleanup recorded, then perform the
supported installer scenarios and compare emitted batch counters and timings.

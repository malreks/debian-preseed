# Installer configuration ownership and source membership

Date: 2026-11-19. This document describes the current source migration. Runtime
acceptance remains subject to the isolated validation described in
[the performance evidence report](../validation/installer-performance-evidence-20261119.md)
and [the repository isolation contract](../test-isolation.md).

## Decision and measured source change

`d-i/debian/repo.env` now describes four repository defaults and 109 shared
repository directory roots. Fixed source filenames are root-relative interfaces
at their callers. Source membership is build-generated data. The configuration
file is no longer a manually maintained variable for every payload member.

| Property | Supplied source | Migrated source |
| --- | ---: | ---: |
| Authored `repo.env` bytes | 253,948 | 6,103 |
| Assignments | 2,855 | 113 |
| Repository defaults retained | 4 | 4 |
| Retained shared directory roots | — | 109 |
| Retained values changed after parent expansion | — | 0 |
| `FILE_*` inventory in repository configuration | Present | Absent |

The byte reduction is 247,845 bytes, approximately 97.6%. These are source-data
measurements, not an installer wall-time result. The old adapters already had
per-shell caches. A lookup did not necessarily reload the old environment.
The changes remove its large authored inventory, several independent parsing
implementations, obsolete file-variable resolution and inventory-based APT
selection. New shells still need their small validated context.

The four retained defaults are unchanged:

| Key | Value | Owner and use |
| --- | --- | --- |
| `REPOSITORY_FAMILIES` | `desktop server` | Supported repository family vocabulary |
| `REPOSITORY_NAME` | `debian-preseed-de` | Public repository identity |
| `DEBIAN_APT_PREFERENCES` | Empty string | Explicit repository preference default |
| `DEBIAN_DEFAULT_CLASSES` | `site/prod;network/dhcp` | Default selection inputs |

All 113 retained values were compared mechanically as data against the provided
original map, including suite-dependent paths. No retained value changed. The
new fixture embeds those original values, so future parity checks do not depend
on a development scratch directory or an external copy of the checkout. The
configuration bytes at this comparison had SHA-256
`07493586d53926ede6aa18a8a6ba5f3190db9913a3443c938c54d6fc752fc030`.

The retained directories cover shared boundaries used by acquisition, module
loading, suite/family APT policy, profile management, offline capture and target
asset groups. This is a reduction with preserved root values; it is not a claim
that every one of the 109 roots must exist forever. Removing another root needs
an audited migration of its actual consumers. Creating another root needs a
shared configuration or ownership reason, rather than a new fixed filename.

## Consumer and ownership matrix

Paths below are relative to `d-i/debian/` unless prefixed with `tools/`.
“Publish” distinguishes copying an installer input into the authenticated
payload from installing configuration on the target operating system.

| Value class / authored owner | Creates or changes | Reads | Validation owner | Exports or renders | Publication boundary |
| --- | --- | --- | --- | --- | --- |
| Repository defaults and shared relative roots: `repo.env` | Repository maintainers; profile creation/deletion no longer edits it | Preseed, bootstrap and common acquisition adapters; build/compiler, profile and offline tools | `source_load_repo_env` for d-i data grammar; pure build checks schema vocabulary, required roots and physical source references | Loader assigns supported shell variables; selected suite is carried explicitly; the complete member inventory is never exported | Captured unchanged in the authenticated source payload; never an installed target environment |
| Fixed source member addresses | Owning installer caller, dispatcher or selection catalog | Source loader, renderer, stage consumer, profile manager | Safe relative-path grammar, captured membership and direct-source checks at the owning boundary; build checks fixed call references | Passed as concrete root-relative member names, including physical `.tmpl` suffixes | Selected source is copied/rendered through the existing target publication boundary |
| Source membership: `catalog/compiled/source-members.tsv` | `tools/class_compiler.py` from one captured source set plus compiled outputs | `tools/check_build.py`, changed-product audit and source inspection | Compiler rejects unsafe or absent members; audits check complete membership and family/suite metadata against the payload | Static index rows only; no environment assignments or new per-file runtime lookup | Generated inside the payload; no separate authored configuration authority |
| Prepared runtime members: `inputs/prepared-members` | Base-stage renderer from the authenticated payload manifest | `render.pl:publish_assets`, once per dependency flush | Same protected prepared-source identity; exact membership and selected source-family/suite checks | In-memory member lookup for the batch | Private prepared workspace; not an authored configuration file or a second read of `source-members.tsv` |
| Selected APT members: `catalog/compiled/apt-assets.tsv` | Same compiler from suite/family APT source paths | `scripts/common/modules/repository-apt.sh` | Compiler extracts canonical suite/family/kind/leaf/member rows; consumer selects exact tuple | Small selected file list | APT policy staging before dependent package operations |
| Installed paths and target state: `hosts/installer/runtime.env` | Target runtime contract maintainers | Profile compiler, selected prepared-input renderer, installed-asset template producers | Restricted profile/configuration compilation, canonical root ownership, placeholder and publication validation | Compiled into selected profile inputs; one path renderer produces concrete target values | Installed units, wrappers, policies and configuration; the authored environment is not a target runtime dependency |
| d-i mount, temporary state, hooks and logs: `hooks/installer/di.env` | Installer contract maintainers | Preseed/bootstrap adapters and standalone base, partman, apt-setup and finish hooks | Authenticated acquisition, restricted source/path validation and required-key checks in bootstrap | Installer-only values; mounted target prefix is applied only outside the target | Private installer context and phase hooks; never target runtime configuration |
| Host policy and supported overrides: `hosts/profiles/`, suite runtime inputs | Operator/profile maintainer and profile manager | Class/profile compiler, prepared selected host/account/layout inputs | Existing profile schema and ownership checks; profile data cannot redefine invariant path/suite/repository owners | Existing precedence/default rules preserved; selected data goes to renderer | Concrete installed configuration and protected installer state as appropriate |
| Theme values and field metadata: `hosts/themes/` | Theme maintainer | Appearance compiler/renderers and selected target assets | Existing theme grammar, allowlists, field mappings and placeholder ownership checks | Appearance substitution after canonical target-path rendering | Concrete appearance assets; no filesystem-root or secret ownership |
| Credentials and sensitive identity input | Operator through dedicated protected input | Existing credential/account preparation boundary | Existing restrictive parser, file permissions and secret handling | Only the necessary protected recipient context | Never `repo.env`, source membership tables, public catalogs or public payload defaults |

### What each stage actually needs

The generated preseed has a selected suite and trusted source/payload pins. Its
early shell transport does not need the source inventory as shell variables or
a target Perl interpreter. After authentication, the preseed adapter loads the
small repository context and d-i destinations, freezes the selected context,
and stages the phase dispatcher.

Partman consumes the selected storage/account policy and d-i paths. It freezes
device/layout results before target rendering. After debootstrap, the existing
base hook invokes target Perl for one selected preparation batch. That batch
uses selected host/account/layout values, source members and the canonical
target path map; it does not infer target paths from repository source roots.

Later stages reuse the prepared source and selected inputs. Source roots are
needed for acquisition/publication. Target runtime values are needed to render
or address installed files. d-i state is needed to supervise the installer and
name its mounted target. Passing all three contracts indiscriminately to an
installed helper would confuse their authority and is unnecessary.

Installed programs receive concrete configuration. Neither `repo.env` nor
`di.env` is an installed configuration API. After entering the target, use its
absolute runtime values directly; do not prepend the installer mount again.

## One early data parser

`scripts/common/source.sh:source_load_repo_env` is the d-i parser shared by:

* `scripts/preseed/bootstrap-entry.sh:ensure_repo_env`;
* `scripts/common/bootstrap.sh:bootstrap_ensure_repo_env`;
* `scripts/common/modules/repository-apt.sh:installer_ensure_repo_env`; and
* the source/preseed include preparation path that loads the captured context.

The adapters keep their phase/context duties and per-shell readiness state.
They no longer maintain independent repository configuration parsers. Loading
does not source or evaluate configuration as shell code. One AWK invocation
validates the complete input before shell `read` assigns any configuration
value. The input must be a direct readable file and the external suite must be
`forky` or `trixie`.

The grammar is deliberately small: one supported uppercase key and one
double-quoted value per assignment; blank lines and whole-line comments are
allowed. Plain `${NAME}` references resolve only to earlier validated values,
plus the explicit suite. Duplicate, unknown or missing keys fail. Shell
substitution, backticks, backslash escapes, control characters, unsupported
parameter operators and inherited undeclared parents fail. Directory roots
must be nonempty canonical relative paths; absolute paths, traversal,
ambiguous separators and dot components fail. The sole root sentinel `.` is
allowed only for `DIR_REPO_ROOT`. Family/name/default value grammar is also
checked. Inputs are bounded to 512 lines, 4,096 bytes per line and 4,096 bytes per
expanded value. The pure `repository_data` build validator applies the same
grammar and supported-key vocabulary before serialization.

These restrictions apply specifically to repository configuration. They do not
silently redefine the richer existing profile data grammar or its default and
override precedence. `di.env` remains its separate authenticated installer
contract with its own restricted source/required-path checks; this migration
does not claim that every historical environment file has the same parser.

## Fixed members, generated indexes and diagnostics

The compiler owns physical membership because it already captures the source
bytes and generated outputs. It emits deterministic sorted rows, including
family/suite classification, rather than adding `FILE_COMPILED_*` variables to
the environment. The source membership header is `format` / `1`; each following
row names a physical member, family and suite. APT rows name suite, family,
policy kind, relative leaf and physical source member. Both tables belong to
the same captured payload identity as their consumers.

`source-members.tsv` supplies family/suite metadata for build checks, the
changed-product audit and inspection. Runtime Perl publication uses the
existing `inputs/prepared-members` list produced at base rendering from the
authenticated manifest, loading it once for each dependency flush. It does not
add a read of `source-members.tsv` per flush or a new per-file runtime lookup.

Examples of stable member interfaces are `scripts/common/credential-data.awk`,
`catalog/selection.json` and `hooks/installer/di.env`. They do not have supported
per-host alternate filenames. Their callers can name those interfaces
directly. Dynamic host-profile choices remain under the shared family roots
and selection registry. Source-to-target mappings, role selection and
placeholder ownership remain explicit compiled/catalog data rather than
thousands of replacement constants in Perl.

The distinction between a source name and a target name remains essential.
`hooks/target/usr/local/libexec/...` is an acquisition member; the installed
helper path comes from the canonical target contract. A source template retains
its `.tmpl` suffix in the membership table even when its installed destination
does not. A real source member with a space remains an exact physical member;
it must not be split by shell word expansion.

Diagnostics should report a resolved physical member and source line. Their
lookup is advisory: an unavailable source label cannot fetch new content,
change valid staging into failure or attribute an operation to another file.
Boundary checks for unsafe ancestry, indirect files, ownership, permissions,
unresolved placeholders and mutable destination state remain mandatory.

`tools/profile.py` now updates only exact profile environments, both suite
classes and `catalog/selection.json`. It derives family/template directories
from the retained roots, compiles the complete candidate before publication,
and preserves rollback/recovery handling. Deletion validates exact ownership,
dependent Duo/Trio variants and references to the deleted physical members.
It neither creates nor removes repository file aliases.

The placeholder ownership contract has two representations with distinct
consumers. `catalog/placeholder-registry.json` remains an authored, 4,152,041-byte
developer input in the full repository. `tools/validate_placeholder_registry.py`
and the checkout contract tests still read it and require its TSV projection to
match. The exact JSON member is excluded from runtime source capture; other
catalog JSON is unchanged. The changed-source audit mirrors that exact rule.
Normal payloads and the independent offline flat-tree exporter share the same
capture rule, so neither needs to transport this developer-only representation.

The complete 2,249,615-byte `catalog/placeholder-registry.tsv` remains runtime
input. Base-stage rendering copies it from the authenticated snapshot into
protected installer bootstrap state; finish-install's owned-file scanner joins
its exact token, owner, source and literal-allowance fields with each publication
record's phase. It remains
covered by the payload manifest, source receipt and compiled membership index.
No equivalent smaller ownership index has been demonstrated, so the TSV is not
trimmed. Both authored files remain byte-identical to the supplied archive.
The JSON exclusion removes 4,152,041 expanded input bytes; it establishes no
measured compressed-size or elapsed-time improvement. Selected publication
records and the TSV continue to drive final actionable readiness diagnostics.

## Bootstrap integrity and HTTPS compatibility

The trusted generated preseed pins the source helper, archive and manifest.
The downloaded source helper must match its embedded SHA-256 before execution;
archive and manifest bytes must match their pins before archive parsing. The
private ready receipt now identifies the verification schema as `verified-v1`.
An old receipt that merely recorded expected hashes cannot authorize reuse.
Whole-archive authentication and safe extraction/member validation establish
different properties and are both retained. An unchanged private snapshot
does not need a second independent content hash for every member.

Requested HTTPS now requires certificate-verifying GNU wget. The bootstrap
checks for its `--no-config` capability and rejects an HTTPS request before
transfer if that capability is absent. There is no `--no-check-certificate`
option or insecure retry. BusyBox wget remains supported for explicit HTTP
seed URLs, together with trusted helper/archive/manifest pins; local-file
seeds remain supported independently of wget.

This restriction follows the [Debian BusyBox wget source](https://sources.debian.org/src/busybox/1:1.37.0-10.1/networking/wget.c/):
the internal TLS implementation does not authenticate the peer, and the
OpenSSL path can use internal TLS if OpenSSL cannot be executed. A TLS-capable
BusyBox build therefore is not sufficient evidence of certificate verification.
An HTTPS installer image must explicitly contain GNU wget and CA trust for
its endpoint. The relevant d-i CA package is `ca-certificates-udeb`; provide
trust during image construction. Bootstrap does not silently install a
downloader or an additional udeb after a failed transfer. A private CA must
be explicitly trusted by that private image.

Local-file and HTTP seeds remain supported for their operator-controlled
deployment models. Artifact pins establish consistency with a trusted preseed;
they cannot make a preseed acquired through an untrusted initial channel
authentic. The operator-provided first preseed remains the trust anchor.
The existing bounded redirect/retry path remains a separate transport concern;
this change does not claim a new authority or scheme-downgrade policy beyond
the downloader's behavior. External vendor data retains its separate HTTPS
and policy/signature/hash verification boundaries.

## Verification status and remaining work

Performed here: source and consumer inspection, data-only byte/key counting,
comparison of all retained values with the supplied original map, and Python
AST parsing of authored fixture sources. No repository test was imported or
executed on the development host. Build and changed-file-audit results belong
to the overall integration record, since those inputs were edited concurrently.

`tests/test_repository_configuration_20261119.py` covers both suites, every
retained original value, empty defaults, malicious input, duplicate/unknown/
missing keys, unsupported suite/family/name, absolute and traversal paths,
undeclared or forward parents, indirect input and parser size limits. It also
checks that rejection does not partially assign configuration and includes a
BusyBox-shell portability case. Transport fixtures cover mismatched trusted
pins, unverified old receipts, a corrupt helper, self-signed TLS rejection even
with legacy bypass flags, and successful TLS only with GNU wget and explicit
private fixture trust. A mock BusyBox client must be rejected before transfer
for HTTPS, while HTTP can prepare a verified snapshot and must still reject
wrong archive or manifest pins before parsing. These are authored isolated
cases, not reported passing runtime tests.

Native execution requires the unchanged reviewed disposable-image boundary,
identified image/fixture, private namespaces, no host binds/services/data,
bounded timeouts and recorded cleanup. Available commands alone do not prove
that boundary is available. Neither a temporary directory nor a plain chroot
authorizes execution, and there is no host fallback. Final installer,
firstboot, TLS-media compatibility and wall-time acceptance remain unverified
until those controlled runs are available.

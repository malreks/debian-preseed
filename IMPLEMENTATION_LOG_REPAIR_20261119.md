# Installer log repair and complete source delivery

Date: 2026-11-19. This is the fourth repair/optimization snapshot of the supplied
codebase. It supersedes the previous delivery for the normal Forky and Trixie
installation products. Earlier implementation reports remain historical records.

## Result and scope

The new logs identified a definite compile-time defect in the shared Perl
renderer. That defect is fixed. The complete previous renderer reproduced the
reported failure under Perl 5.40.1 in a private image; the repaired complete
program compiled successfully. Real payload preparation then passed for Forky
and Trixie, each with desktop and server profiles.

The delivery includes the entire source tree, all current suite products,
regression fixtures, documentation and validation evidence. It preserves the
previous configuration, batching, publication and ownership optimizations.
The new checks remain outside the production installation and pure build paths.

This is not a claim that every installed application, kernel, service or hardware
combination has passed an installation. The complete Perl sweep has dependency
blocks, and required BusyBox/ShellCheck checks remain unavailable. Those results
are reported as incomplete/nonzero, not as successful checks.

## Exact failure and repair

The attached `installer.log` identifies previous release
`b4de1b60b6be8c7bae263af79a19f931c1d63eb7673eef35540b5c7feb1f3e42`.
At line 353 it reports:

```text
Unmatched [ in regex ... at .../render.pl line 828.
```

The next records identify status 255, component `target-render`, the
`00rendertarget` hook and operation `render_target_source_snapshot`. This is
more specific than the earlier generic `prepare_target_payload` symptom.

The publication-phase expression used slash delimiters while its character
class contained an unescaped slash. Perl compiles the complete program before
selecting an entrypoint, so this expression blocked initial source preparation
as well as publication. The corrected expression uses paired delimiters:

```perl
$context->{PHASE} =~ m{\A[A-Za-z0-9_./\@+:-]+\z}
```

The intended allowed characters and all validation surrounding the expression
are preserved. Literal at-sign spelling is also explicit in the related path
classes. This adds no runtime subprocess, scan or dependency.

The review traced all four shared modes and their callers: initial preparation,
`--file`, `--publish` and `--cleanup`. It retained the source-family boundaries,
private ancestry and ownership checks, limits, publication journal, atomic
replacement and receipt checks. The failure is corrected at the shared owner.

The second definite production defect was in
`LabwcSecurityAction::_validate_service_name`: the unescaped `@_` sequence inside
its character class interpolated Perl's argument array. The literal at sign is
now escaped. The pure production validator passed accepted service-instance
names and rejected slash, whitespace, newline, traversal, punctuation and an
incorrect unit suffix. Its fixed argv dispatch and authorization checks remain.

The shared caller review also found missing option separators in three dynamic
service-name paths. The security inspector now passes
`systemd-analyze security --no-pager -- <unit>`; the system inspector passes
`systemctl status --no-pager --full -- <unit>`; clipboard cleanup passes
`systemctl --user --no-pager stop -- <unit>`. A valid name beginning with `-`
now remains an operand throughout those paths. The validators and authorization
rules retain their existing behavior. Neighboring callers were traced to their
option separators, closed sets or fixed non-hyphen prefixes.
That inventory covers all 83 files under `target/usr` mentioning `systemctl`,
`systemd-analyze` or `journalctl`, including 15 documentation/help files, and
follows generic wrappers and persisted-state unit names back to their owners.

The final private run exercised the actual Perl validator/dispatcher, the full
rendered shell helper and the actual clipboard cleanup/command-construction
functions with strict argv-recording sinks. Leading-hyphen and ordinary names,
invalid input, inactive-service journal continuation and clipboard cleanup
ordering passed. No service manager or clipboard command was contacted by those
fixtures. The fixes add no subprocess, scan or dependency.

## Why the old audit missed the error

The canonical codebase auditor still selected the former Forky source layout.
It did not cover the shared implementations now owned by `d-i/debian`. The audit
now includes the shared target, installer, scripts and host trees, both suite
overlays, the complete shared renderer and the physical role-owned Perl roots.
Missing or empty required scopes cannot produce an empty successful audit.

The maintained `tools/prepare_syntax_fixture.py` prepares exact shipped inputs
inside the existing isolation boundary. It verifies the archive and manifest,
uses the real repository-data parser, profile snapshots and map producers,
runs the unchanged renderer, and supplies the actual published Perl modules.
The auditor verifies provenance, original source hashes, both renderer copies,
completed receipt and all 160 module publications. It stages selected bytes
unchanged and gives `.pm.tmpl` files their importable `.pm` filenames.

The compiler uses the actual local modules and imports. It does not strip
imports, replace missing packages with stubs or substitute arbitrary template
values. Taint-mode shebangs are preserved. Each native parser has explicit
process ownership, a deadline and an output limit. The preparer also bounds
CPU, memory, descriptors and output files. Unsafe outputs, FIFO inputs,
symlinks, stale source and corrupt payloads fail before downstream compilation.

The prepared gate is wired into `make check-perl`, `make check`, the private
image test-init check stage and the aggregate validator. The aggregate report
now hashes the twelve flat suite products rather than looking in a removed
release directory. `make build` remains the same pure serialization path.

Inside a reviewed disposable image, the maintained compiler gate is:

```sh
python3 -I -B d-i/debian/tests/audit_codebase.py \
  --perl-only --prepare-suite forky --prepare-family desktop \
  --output .build/validation/perl-syntax.json
```

Use `--prepare-suite trixie` for Trixie. Explicit prepared-input paths are also
supported. `make audit` uses `--source-only` as a strict source diagnostic;
unrendered types and unavailable dependencies remain incomplete/nonzero.
These commands must not be run by bypassing the repository's isolation guard.

## Executed isolated evidence

The validation used identified, privately copied interpreter/runtime bytes,
with Perl 5.40.1, a read-only private root, separate user/mount/PID/network/IPC/
UTS/cgroup namespaces, private guest scratch space, no host mounts or devices,
no host service sockets, no privileges and bounded process cleanup. Host-side
images and logs stayed in private disk-backed checkout storage. Image manifests,
source hashes, commands, timeouts, results and cleanup evidence are recorded in
[the validation record](docs/validation/log-repair-delivery-validation-20261119.json).

The guard observes the strict private procfs network inventory without opening
a socket. It validates the opened file's filesystem identity, rejects procfs
submounts and requires exactly the loopback interface. All other image, mount,
namespace, capability and PID 1 checks remain mandatory. No host fallback or
network permission was introduced.

| Check | Observed result |
| --- | --- |
| Previous complete renderer | Reported `Unmatched [` failure reproduced; status 255 |
| Repaired complete renderer | `perl -f -c` passed |
| Renderer/bootstrap/reuse/selector/phase/service grammar methods | 52 passed |
| Private-network isolation methods | 5 passed |
| Auditor, policy-classification and preparation methods | 25 passed |
| Additional service-operand regression methods | 3 passed; the final run also repeated the two existing Perl grammar methods |
| Zsh startup files | All four parsed successfully in the clean image |
| Forky and Trixie desktop preparation | Both passed; 2,433 captured members; 1,121 rendered files; 160 published Perl modules each |
| Forky and Trixie server preparation | Both passed; 2,433 captured members; 1,117 rendered files; 102 published Perl modules each |
| Deferred desktop structured configuration | All 12 source templates covered; 13 outputs per suite passed |
| Selected server hardware configuration | Both selected outputs per suite passed; ten desktop/disabled consumers explicitly not selected |
| Complete production Perl inventory | 200 attempted: 30 passed, 170 dependency-blocked; status 1 |
| Maintained standalone Perl gate | 190 attempted: 29 passed, 161 dependency-blocked; status 1 |

The 85 distinct passing regression methods are separate from compiler-file counts and
configuration-output counts. Failed intermediate fixture/image attempts are
retained in private evidence; they are not counted as passes.

The four final preparation scenarios use `desktop/btrfs-de-p15s` and
`server/btrfs-srv-flex` for each suite. This is execution evidence for those
selections; the wider compiled profile inventory is checked as data.

The structured checks use real producers for app-veth, proxy, greetd, software
release policy, Tailscale and Wi-Fi, plus the actual offline hardware-policy
installer. JSON rejects duplicate keys and nonfinite values; TOML and INI use
strict parsers. Synthetic account, device identifiers, package activation data
and network adapters are explicitly declared. No hardware backend was created,
no service was started, and no network configuration was activated.

The first missing compiler dependency was `Moo.pm` in the validation image.
The early renderer uses core Perl dependencies and completed full preparation;
the blocked checks concern later target programs and modules that import Moo.
Both suite APT baselines declare the ten direct provider packages needed for
Moo/MooX, Types and XML. All 22 compiled package plans include each direct
provider once. `Path::Tiny` is a mandatory dependency of the explicitly selected
`libtypes-path-tiny-perl`, as confirmed by its
[Debian control file](https://sources.debian.org/src/libtypes-path-tiny-perl/0.006-2/debian/control/).
This verifies package declarations; it does not turn blocked native compilations
into passes or prove package installation on a booted target.

## Whole-source syntax and wiring sweep

Three parallel specialist reviews covered the renderer and its callers, all
Perl programs and imports, and the remaining languages/configuration formats.
The root review covered integration, isolation, generated-product identity,
packaging and the previous optimization contracts.

The detailed non-Perl inventory and exact parser counts are in
[the non-Perl report](docs/validation/nonperl-syntax-20261119.md). It includes
Python ASTs, Dash/Bash sources, literal child shells, generated preseed command
boundaries, AWK compilation, Lua parsing without execution, C syntax checks,
Node parsing of Polkit rules, strict structured data and desktop-entry checks.
CSS checks establish structure and local-import resolution, not native toolkit
property acceptance. Two desktop-entry variants use their consumers' extension
keys; generic-validator errors for those variants are retained explicitly.

The stale firstboot fixture index was corrected to include `DIR_REPO_SCRIPTS`
as well as target assets. The five actual firstboot members were present and
matched both suite manifests; the runtime staging path was not changed to
accommodate a broken test.

Static regression contracts now also guard the phase delimiter, literal
service-name grammar and all three prepared validation entrypoints. The required
changed-file audit runs against both the previous delivery and the original
uploaded source archive. Missing BusyBox and ShellCheck remain fatal audit
errors. Available static checks continue, so these missing tools do not hide
other reported failures. Exact errors and counts are retained in the validation
record and command record.

## Optimizations preserved

The previous shared repository-data parser and small parent-derived `repo.env`
remain the configuration owners. The removed `FILE_*` catalog is not restored.
Target paths still come from one contract and one publication renderer.

Package operations retain their reviewed batches, with separate policy-specific
operations where ordering requires them. Publication keeps one bounded Perl
interpreter per nonempty batch, one set of membership/maps per invocation,
complete preflight before mutation, atomic writes and ownership commit. The
three direct-reader barriers flush queued assets before installer-side reads.

Runtime changes retained from the earlier snapshots include operation-local
appearance snapshots, shared wait-status decoding, fewer repeated package/hash
queries, reuse of selected hardware/SSH/server observations, corrected shared
hardware-wrapper ownership and removal of the redundant JPEG asset. Independent
installed defaults retain their required ownership and lifecycle.

The final target `usr` inventory contains 670 regular files and 11,269,069 bytes,
with zero byte-identical duplicate groups, missing source owners or conflicting
logical destinations within either selected family. All source bytes and owners
match the final payload and manifest; the details are recorded in the validation JSON. Exact duplicate-file elimination is not a promise that every
similar routine should be merged: different roles, privilege boundaries and
independent state owners remain explicit. The compressed payload is 10,268,942 bytes, down from 11,923,852 bytes in the
original upload (13.9% smaller). Expanded content is 34,624,295 bytes, down from
40,306,051 bytes (14.1% smaller). No installation-speed or hardware performance
benchmark was performed, so no measured speedup is claimed.

## Current products and deployment identity

Current release:

```text
f3438948657b580ffdd65ce04c15707e81be6f77566fb4bcee2ed69a41fa39c8
```

Shared payload SHA-256:

```text
82a73d838a165690f537d29a6b3170553f0a0cca2c3cb4d23ddc7acc71444141
```

Shared manifest SHA-256:

```text
7f8b701a7533f04fa07a46601faf4f5b1ef9c55d3c8f4900a07762728a8baf7a
```

Deploy the selected suite's complete matching set from this archive:

- `preseed.cfg`
- `source.sh`
- `payload.tar.gz`
- `payload.manifest`
- `receipt.json`
- `support-matrix.json`

Both suites' products were rebuilt twice. All twelve products were byte-identical
on the second build; only the authorized flat products changed during generation.
Every payload member, source index, selected Perl destination, compiled profile,
APT selection, receipt product hash and preseed payload pin was checked as data.
The retained comparison chain covers the initial successful native payload,
the intervening build and the final archive. The final change affects exactly
four members: `catalog/compiled/release.tsv` and the three service-command
owners. The other 2,429 members are byte- and metadata-identical. All twelve
typed structured templates and their owning producers/support inputs remain
unchanged across that chain. Final-artifact preparation, the complete 200-entry
Perl sweep and the maintained compiler gate are recorded against current source
bytes and the final archive/manifest hashes.

Use the normal `d-i/forky/` or `d-i/trixie/` products. The preserved
`offline/payload.tar.gz` is a historical artifact with different release identity.
Its original authenticated package-index inputs are absent from the supplied
source, so it was not regenerated or relabeled as current. The original logs
and private validation images, caches and transfer state are excluded from the
source download.

The full ZIP preserves exact source bytes, POSIX file/directory modes and empty
directories. The cumulative authored patch is checked by actual Git application
against private copies of the original uploaded bytes. It excludes exactly the
twelve generated suite products; those are included in the ZIP. The path manifest
records cumulative additions, modifications and deletions.

## Remaining acceptance limits

The reported renderer failure is reproduced and repaired, and no further
nonblocked syntax failure was found by the recorded checks. Complete Perl
compilation still requires the missing real dependency packages in the test
image. BusyBox and ShellCheck checks, native HCL/CSS/consumer acceptance,
AppArmor loading, booted installation, package installation, first boot,
network activation, application launches, Secure Boot and hardware behavior
are not established by this evidence. The aggregate validator was not executed
through its entire unrelated test suite.

The current report and validation data retain these limits explicitly. They do
not certify an unobserved installation or an absolute absence of defects.

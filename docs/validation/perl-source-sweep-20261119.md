# Perl source and embedded-program sweep

Date: 2026-11-19. This record describes the source inventory, repair and maintained
Perl gate. The native results below were captured by the release owner inside
the reviewed private image, then inspected as data by the Perl sweep. Initial
regression results and the final exact-archive compiler replay are identified
separately below. The final delivery report owns the complete generated-product
identity and the combined validation record.

## Confirmed service-name defect

`d-i/debian/hooks/target/usr/local/lib/desktop/perl5/site_perl/labwc-security-action/LabwcSecurityAction/Root.pm.tmpl`
used the character class `[A-Za-z0-9@_.:-]` in `_validate_service_name`.
The unescaped `@_` is a Perl argument-array interpolation, so the pattern could
derive its allowed characters from the arguments being validated. The predicate
now uses `[A-Za-z0-9\@_.:-]`, preserving the intended fixed alphabet and the
existing traversal and `.service` suffix checks.

The caller is `Root::_dispatch`'s `inspect-service` branch. It validates exactly
one service name before passing that name as an argument to
`systemd-analyze security --no-pager --`. The command adapter, privilege boundary,
service operation, AppArmor policy and class ownership are unchanged.

The regression source is `d-i/debian/tests/test_perl_service_name_20261119.py`.
Its first two guarded methods execute the actual extracted pure validator without
loading the privileged module. Three accepted examples cover ordinary names,
literal `@`, underscore, hyphen and colon. Seven rejected examples cover slash,
space, punctuation, newline, traversal, an incorrect suffix and an empty name.
The caller argument deliberately contains disallowed characters to verify that
it cannot alter the validator's alphabet. The fixture retains the mandatory
isolation guard and uses only a private guest `/workspace` directory.

Perl's documented interpolation behavior is described in
[perlop](https://perldoc.perl.org/perlop). Its regex-parsing section explicitly
exempts `@+` and `@-`; the renderer's use of `@+` was therefore not classified
as this argument-array defect. The renderer's separately reported slash
delimiter syntax error remains a distinct confirmed failure.

### Service argument boundary

A final source review found that the preserved service-name alphabet also
accepts leading hyphens, including `-Hhost.service`. The maintenance menu's
free-text selection accepts this value, the client checks only its argument
count, and the root dispatcher, `_exec` and `Command::exec` previously forwarded
it unchanged without an option terminator. The
[systemd-analyze option contract](https://www.freedesktop.org/software/systemd/man/latest/systemd-analyze.html)
assigns `-H` to remote-host selection. A unit-shaped argument could therefore
be parsed as an option at that command boundary.

The smallest compatible correction inserts a literal `--` after `--no-pager`
and before the validated unit in the `inspect-service` branch. The validator
still accepts its existing alphabet, while that single argument remains a unit
operand. Other callers of the general command adapter retain their existing
argument contracts.

A third guarded fixture method extracts the actual `_validate_service_name`,
`_dispatch` and `_exec` functions together. A private command sink records the
resulting argv instead of running `systemd-analyze`; four examples verify the
exact option boundary for a leading-hyphen name and ordinary service names.
This fixture does not import the privileged module or contact any service.
Its source was AST-parsed only by the reviewing agent; the release owner's
isolated validation record owns native execution results. This additional
source correction postdates the initial archive identities recorded below.

The sibling shell system-inspection owner,
`hooks/target/usr/local/libexec/desktop/labwc-system-action-root`, had the same
ambiguity in `systemctl status --no-pager --full "$service_name"`. It now inserts
`--` before that operand. Its journal query retains `--unit "$service_name"`,
which already binds the value to the required option argument. Its existing
behavior continues to show the journal when `systemctl status` reports an
inactive service.

The new guarded `test_system_service_name_20261119.py` method passes the complete
shell owner through the unchanged shared renderer with private fixture paths,
then exercises its real startup, validation and `inspect-service` dispatch.
The non-login shell driver supplies exact-argv shell-function sinks for every
external command reached by that branch: `id`, `getent`, `systemctl` and
`journalctl`. No installed identity or service command executes. Four accepted
names include the leading-hyphen case; nine rejected name/request shapes must
make no service-command calls. The sink returns the ordinary inactive-service
status from `systemctl` to check that the subsequent journal call remains.

Neighboring service callers were inspected before changing their shared
operand contract. The frontend status actions select fixed unit literals;
AppArmor's dynamic worker already passes `--`; the admin worker constructs a
unit with its fixed `labwc-admin-action@` prefix and validated request fields;
and both Mullvad callers select the fixed `mullvad-daemon.service` literal.
Those owners do not expose the same leading-hyphen operand ambiguity and were
left unchanged. This is a focused source review and argv fixture, not a live
service or authorization test.

## Inventory and cross-component scope

The source scan identified:

- **190 standalone Perl programs/modules**, including `.pl`, `.pm`, template
  variants and extensionless programs identified by their Perl shebangs;
- **10 production embedded Perl programs**, extracted exactly from their
  owning shell literal or heredoc, with source owner, source line, code hash,
  import names and command-line `-M` imports recorded;
- **17 shell owners** containing Perl references, inspected to distinguish
  execution from module catalogs, package declarations and comments;
- **116 Perl-like literal fragments in the initial Python regression inventory**, kept
  explicitly separate because some are concatenated with other literals or
  extracted functions and are not independently compilable programs.

After adding the maintained audit fixtures and service-dispatch coverage, the
refreshed source inventory contains **129** such Python literal fragments.
The standalone and production embedded-program counts remain 190 and 10.

The ten production embedded programs are the Android ADB, Digital Assets and
AI Copilots launchers; the AI llama-server and privileged model-installer
launchers; pinned Tomat and Codex acquisition; two firstboot module-import
checks; and the NVIDIA compatibility heredoc. No production Perl `-e` command
was found in the inspected target unit/configuration owners.

The standalone inventory covers the common runtime, AppArmor modes,
APTRepoLocal servicing, Filen, managed networking, Timeshift, Whisper and Zram
modules, plus desktop Android ADB, AI Copilots, Digital Assets, Compz and
security/network action modules and their entrypoints. It also includes the
installer renderer and network generator. The source hashes and extracted
program ownership are retained in the run's private compile inventory for the
release owner's isolated parser workflow.

The import inventory includes the local module providers and the relevant
external families: Moo, MooX, Types, Path::Tiny and XML::LibXML, as well as core
Perl modules and pragmas. Static import names are dependency evidence; they do
not establish that a target interpreter has successfully loaded those modules.

## Canonical audit coverage repair

The existing `d-i/debian/tests/audit_codebase.py` selected the former Forky
implementation roots. The shared installer renderer and the managed target
programs now live under `d-i/debian`, so that selection omitted the very source
that failed in the installer. Its exit condition also accepted runs containing
only missing tools, dependencies or template context.

The auditor now requires the shared target, installer, scripts and hosts
scopes, includes both suites' target overlays and any further relevant suite
overlays, and refuses missing or empty expected scopes. Perl lookup paths use
the actual component directories beneath the `common`, `desktop` and `server`
role roots. Its `--perl-only` preflight selects complete Perl programs,
including the full shared renderer. Missing compiler/dependency/template
context now makes the result nonzero. An unrelated placeholder no longer
hides a true parser error elsewhere in a program.

Native parsing retains the isolation guard, uses the image's explicit Perl
interpreter, preserves the existing taint flag, disables implicit site startup,
and passes the sanitized fixture environment. Every parser has a ten-second
execution limit, bounded output and the shared child-session cleanup owner.
The thirteen guarded cases in `tools/tests/test_perl_audit_20261119.py` cover
scope selection; missing scopes/compiler/dependencies; the full-program regex
failure with an unrelated placeholder; taint mode; FIFO rejection; real module
imports from byte-preserving published sources; strict unrendered-source
failure; stale source/renderer rejection; unresolved rendered-token rejection;
and missing-dependency failure in rendered mode. The existing policy
classification fixture now supplies all required source scopes.

Source preflight alone does not replace canonical template rendering. The
maintained auditor calls `tools/prepare_syntax_fixture.py` for actual production
map generation, source rendering and shared module publication. Its prepared
mode validates the format-3 manifest, current suite archive identity, completed
render receipt, original Perl source hashes and both copies of the renderer.
It requires publication of all 160 inventoried modules, copies their selected
bytes unchanged and removes only the physical `.tmpl` filename suffix when a
Perl module must be found as `.pm`. No import is removed or dependency stub
created. Original and selected hashes are recorded for every program.

Inside the prepared disposable image, the canonical complete-program command
is:

```sh
/usr/bin/python3 -I -B d-i/debian/tests/audit_codebase.py \
  --perl-only --prepare-suite forky --prepare-family desktop \
  --output .build/validation/perl.json
```

The existing-preparation form accepts `--rendered-root`, `--published-assets`
and `--source-manifest`. The separate `--source-only` mode is an explicit strict
diagnostic and continues to fail when source templates require rendering or
imports are unavailable. A missing package is a blocked check, never a syntax
pass. The installer build remains a separate serialization operation.

Every selected rendered Perl program must be free of installer placeholders.
Only the exact unchanged `scripts/common/render.pl` owner may retain its two
literal input-grammar markers, `__INSTALLER_DATA_END__` and
`__INSTALLER_FSTAB_RECORDS__`.

## Captured isolated native results

The initial native runs described in this section used payload SHA-256
`39fe4e4d5c918fd4f739ca75eee8dac3222bfa4ca260e910030da0508fb4b778`
and manifest SHA-256
`8deb1f388c680791b01293286d976aa2f481c5c42a80a71df42f21fbfa38abe1`.
An intermediate generated-product refresh produced release
`afdc643351dd32416c29dcb7ba38a7010c3717aaacfa6ec28751c54d1412a7e2`
and payload SHA-256
`72065a4119fe0e299d3ce08090ea23d306ac1e251c3aa576a4f6dafa4e0f4e5c`.
That refresh incorporated the maintained gate's build provenance while its
runtime production source remained frozen. The subsequent service-operand
corrections produced release
`f3438948657b580ffdd65ce04c15707e81be6f77566fb4bcee2ed69a41fa39c8`,
payload SHA-256
`82a73d838a165690f537d29a6b3170553f0a0cca2c3cb4d23ddc7acc71444141`
and manifest SHA-256
`7f8b701a7533f04fa07a46601faf4f5b1ef9c55d3c8f4900a07762728a8baf7a`.

The retained data-only comparison establishes that the initial-to-intermediate
archive step changed only `catalog/compiled/release.tsv`. The final step changed
that identity member plus the security root, system-action root and session-state
operand owners; the other 2,429 members remained byte- and metadata-identical.
The session-state correction is covered by its separate source review and
guarded fixture. Explicit hashes for all twelve typed structured templates,
their owning producers and their support inputs remain unchanged across this
comparison chain. Final-archive preparation and complete-program compiler
reruns are recorded separately by the release owner; earlier native results
are not relabeled as execution of the new archive.

The release owner's final private image has fixture-manifest SHA-256
`d37e72c8861d14022c5b75b94cfad274bb3e0543801c10b2ddfcca60599bd0aa`.
Its focused service run passed all three Perl service-name/dispatch methods,
the shell service-operand method and the separate clipboard-unit method, with
stage status zero and no timeout or cancellation. The two original Perl
validator methods were rerun; the third Perl method, shell method and clipboard
method add three distinct methods to the prior 82-method evidence, for **85
distinct regression methods** across the combined record. This count is
behavioral regression evidence, not a claim that all Perl programs compiled.

The initial maintained fixture run passed all **25 regression methods**: thirteen Perl
audit cases, five existing policy classification cases and seven preparation
contract cases. The captured test runner reported 4.115 seconds, status 0, no
timeout or cancellation, and completed owned child-session cleanup.

Final exact-archive source preparation and Perl publication passed for all four
suite/family combinations: Forky desktop, Forky server, Trixie desktop and
Trixie server. The representative desktop profile was `btrfs-de-p15s`; server
used `btrfs-srv-flex`. Desktop published all 160 repository modules. Server
published its 102 common modules; it did not claim to publish or compile the
58 desktop-only modules. These are preparation/publication checks, not installer
boot or hardware results.

The following compiler results were replayed against the final source inventory
and final payload identified above. They preserve the dependency limitation of
the identified private image:

| Native check | Attempted | Passed compilation | Blocked by missing dependency | Other compiler failures | Exit/result |
| --- | ---: | ---: | ---: | ---: | --- |
| Final maintained prepared gate, complete standalone programs | 190 | 29 | 161 | 0 | Status 1; incomplete |
| Final private complete inventory, standalone plus embedded programs | 200 | 30 | 170 | 0 | Status 1; incomplete |

The final 200-program compiler stage took 50.981 seconds. Neither compiler stage
timed out or was cancelled; owned child sessions were cleaned up and direct
children were reaped. Their incomplete status is caused by missing dependencies.
The initial compiler runs produced the same counts, but remain separate evidence
for their earlier source and archive identities.

The first missing dependency was `Moo.pm`. A failed import can stop the Perl
compiler before it reaches later source, so the blocked programs have **not**
passed full syntax validation. The gate deliberately reports failure in that
case. These results do not establish that every Perl program is error-free.

The repaired renderer itself passed full-program compilation, with identical
original and selected SHA-256:
`04baa6387169c0d0fbedcbb4a8360504eaae8b53361931a5d0d57c2c93fb6898`.

Initial native evidence is retained in
`.build/validation/round4/canonical-perl-gate-initial.json`,
`.build/validation/round4/perl-compile-native-initial.json` and
`.build/validation/round4/native-maintained-initial.log`. The source-only review
of the maintained gate and thirteen-case fixture is recorded in
`.build/validation/round4/perl_sweep/prepared-gate-source-review.json`.

Final native evidence is retained in
`.build/validation/round4/perl-compile-native-final.json` (SHA-256
`68c85ec7fdf327ce71fd9061ff44549b2cda60cbf4225e56a17a54aade9d5a59`),
`.build/validation/round4/canonical-perl-gate-final.json` (SHA-256
`aa29c5728abc443f3c70b60c4c27161081005921d74cbad62017aed6b4570872`)
and `.build/validation/round4/native-final.log` (SHA-256
`e8b40491a9c05cb9151d1a19589f28bbe79b1560a1257caed0f6328fb7036220`).
The public `log-repair-delivery-validation-20261119.json` preserves the exact
per-program source/selected hashes, statuses, preparation identities and
cleanup results from those final records.

## Target package and import closure

Both suites' base APT fragments declare the package providers used by the
inventoried non-core Perl imports. The owning declarations are
`d-i/forky/fragments/apt.cfg` and `d-i/trixie/fragments/apt.cfg`; they apply to the
shared package baseline across desktop and server plans.

| Imported module | Debian provider |
| --- | --- |
| `Moo` | `libmoo-perl` |
| `MooX::HandlesVia` | `libmoox-handlesvia-perl` |
| `MooX::Options` | `libmoox-options-perl` |
| `MooX::StrictConstructor` | `libmoox-strictconstructor-perl` |
| `MooX::TypeTiny` | `libmoox-typetiny-perl` |
| `MooX::Types::MooseLike::Base` | `libmoox-types-mooselike-perl` |
| `MooX::Types::MooseLike::Numeric` | `libmoox-types-mooselike-numeric-perl` |
| `Types::Standard` | `libtype-tiny-perl` |
| `Types::Path::Tiny` | `libtypes-path-tiny-perl` |
| `Path::Tiny` | `libpath-tiny-perl`, required by `libtypes-path-tiny-perl` |
| `XML::LibXML` | `libxml-libxml-perl` |

All ten explicitly selected provider packages are present once in each of all
22 compiled package plans read from the final payload identified above:
eleven per suite, six desktop plans and
sixteen server plans overall. `libpath-tiny-perl` is a mandatory dependency of
the explicitly selected `libtypes-path-tiny-perl`, as confirmed in Debian's
[package control source](https://sources.debian.org/src/libtypes-path-tiny-perl/0.006-2/debian/control).
The [source package catalog](https://sources.debian.org/src/libtypes-path-tiny-perl/)
lists that source version for both Forky and Trixie. No target package
declaration gap was found for these imports.

Dynamic `require` sites were also reviewed. They name local module providers,
core `Encode`/`Time::HiRes`, the already declared `XML::LibXML`, or the fixed
Discord/Postman/Tuta/Ledger servicing-module map. They did not introduce another
non-core package family. Per-plan package membership, module/provider mapping,
source hashes and the captured archive identity are retained in
`.build/validation/round4/perl_sweep/noncore-perl-package-coverage.json`.

This declaration review read source and captured JSON as data. It did not
install packages, contact host package state or establish that the private
parser image contains the declared target packages. The missing-Moo native
checks therefore remain blocked despite the complete target declarations.

## Source checks and limits

The delimiter scan found the reported `render.pl` expression and no second
confirmed standalone Perl instance of that slash-in-character-class error.
It also surfaced analogous AWK expressions in the publication shell owner;
those were handed to the shell/AWK review rather than misclassified as Perl.
The literal-array scan found the service-name issue described above. Both
scans are conservative source heuristics, not substitutes for a Perl compiler.

The new fixture was AST-parsed without discovery or importing its isolation
guard. All source inspection and extraction operated as data, with scratch
under `.build/validation/round4/perl_sweep` on the disk-backed workspace and
explicit temporary-directory settings. No Perl interpreter, managed module,
installer, package manager, service, policy loader or hardware program was
executed by this source-sweep agent on the development host.

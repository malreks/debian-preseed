# Whisper target scope and remaining installer scripts, 2026-11-16

## Revision and execution boundary

Base commit: `c39fe1bcf6e62e118399c448d2cd788a653af87b`. The worktree contains
the changes listed below. No VM, native installer replay, test discovery,
managed Perl import, service operation, package transaction or offline catalog
generation ran in this pass. Source was read as data; shell parsers used `-n`,
Python used `ast.parse`, and ShellCheck analyzed source without execution.

The previously referenced `debian-preseed-de-audit.md` is absent from this
checkout. Earlier validation reports describe earlier snapshots and are not
used as acceptance evidence for this worktree.

## Reproduced defect and correction

The reported Whisper failure was a target environment boundary defect. Both
`whisper_target_install_entrypoints` and `whisper_target_verify_runtime` read
`DIR_USR_LOCAL_LIBEXEC` inside target-install mode. The private target policy
serializes Whisper policy fields; it does not export installer path variables.
The parent function's environment therefore could not establish this value.

Before the fix, the new static target-scope projection reproduced:

```text
scripts/late/whisper.sh:762: target-install ShellCheck SC2154:
DIR_USR_LOCAL_LIBEXEC is referenced but not assigned.
```

The shared path renderer now supplies the desktop CLI wrapper path directly.
The parent passes the selected desktop/server family as an explicit argument,
and target-install mode validates it before mutation. Both publication and
verification call the same CLI path selector. Server installation selects the
native CLI because the default-model wrapper and its desktop dependencies are
staged only on the desktop branch. Existing ownership, mode, symlink and release
verification remains in place.

## Remaining installation sequence and sibling coverage

Reviewed the class stage registry and late dispatcher, then the desktop
entrypoint, its complete ordered module list and `run_desktop_late_command`.
The desktop session depends on Whisper and managed software. It covers device
authorization, conditional private Xwayland and specialist tools, Satty,
Kanshi, target assets, appearance/default rendering, hardware tuning/scx,
desktop launcher wrapping, resource policy, account configuration, fonts,
Waypaper, conditional Codex setup, verification and offline service enablement.
The Llama fragment has its own server stage and was checked independently of
whether the reported desktop selection includes it.

Llama review includes its target-install function closure, actual serialized
configuration fields, archive helper, launcher and configuration staging,
release/model publication and verification. No additional missing child input
was found in that scope.

Waypaper review includes wheel download and hash checking, transient pipx
account preparation/removal, explicit `env -i` inputs, nested symlink validation
shell, wrapper publication before runtime sealing, desktop entry, appearance
delegate and configuration staging. Its outer and nested shell scopes pass
independent unbound-variable checks. No Waypaper source edit was required.

The shared managed-software contracts include Bitwarden, QoreDB, Obsidian,
Tomat, Sleek, Postman, Discord, Tuta, Ledger, ChatGPT/Codex, Filen, Zoom and Tor
Browser, plus the scx download path. The persistent audit checks 13 managed
application owners and ten managed-software child shells. No application
policy, download size restriction, private Zoom/Discord Xwayland configuration
or enrollment policy changed in this pass.

## Persistent checks added

`tools/post_change_check.py` now checks self-reentering target-install programs
separately from installer-only code. It reads the actual private configuration
writer, projects the reachable function closure, checks missing policy fields
even when guarded by `${NAME:?}`, and runs shell syntax and SC2154 checks with
uppercase-variable analysis. Diagnostics retain original source line numbers.
It does not declare arbitrary parent globals as target inputs.

Embedded child-shell checks cover all installer script families. Nested `-c`
arguments are decoded at their own quoting layer. A policy explicitly sourced
by a child contributes only fields authored by that policy. Profile loading
must precede helper rendering in the Tailscale, DevOps, desktop, Whisper and
Llama entrypoints.

The guarded fixture `tests/test_late_target_install_contracts.py` contains
negative cases for the exact Whisper error, missing serialized Whisper/Llama
policy fields, a missing variable in Waypaper's nested shell and the boundary
between sourced policy fields and installer path variables. The fixture was
inspected and AST-parsed; it was not imported or executed.

## Observed static results

A bounded, data-only Python inventory read every regular source in the three
trees below. Python programs/templates were parsed using `ast.parse`. Shell
sources and assignment-only `.env` inputs were checked with Dash and BusyBox
`-n` (Bash `-n` for Bash sources), then ShellCheck `--norc --severity=error`.
Each subprocess had a 20-second timeout and a clean PATH/locale environment;
the whole inventory had a 180-second timeout and two workers. Result: exit 0,
no diagnostics. An AppArmor policy whose filename ends in `.sh` was classified
as policy data rather than shell code.

| Source tree | Shell sources/data | Python AST parses |
| --- | ---: | ---: |
| `scripts` | 170 | 37 |
| `hooks/target` | 124 | 248 |
| `hooks/installer` | 29 | 0 |
| Total | 323 | 285 |

`timeout 180s python3 -B tools/post_change_check.py` passed with:

- 130 embedded child-shell programs and two separate target-install scopes;
- 57 reachable target-install functions and 56 serialized input fields;
- 134 script assets and 850 target assets with known, resolvable path tokens;
- 31 bootstrap dependencies checked before profile rendering;
- five entrypoint loading-order contracts;
- 2,248 payload source equality checks and 208 frontend equality checks.

Tool versions observed: Python 3.14.10, ShellCheck 0.11.0, BusyBox 1.38.0
(`1:1.38.0-3+b1`), Bash 5.3.15. Dash was used in syntax-only mode; no Dash
package version or target package version was inferred from these checks.

## Generated products and fingerprint

The permitted `timeout 120s make build` serializer passed after the Whisper
source correction. Subsequent edits affect only the checker, guarded fixture
and this report. Both suite archives contain the corrected Whisper source and
the audited Llama, Waypaper, desktop entrypoint, component loader, Labwc driver,
verification template and Waypaper adapter byte-for-byte. Each has 2,421 members.

- Release: `e0a7aae200255bfcab831a73a8f67146bfbffb98f356b512c039a37de6ef24f1`
- Source fingerprint: `8297b21e2423b815593394ac07e70097a2f6e32cac1e9fc10af4c8e1fd83c33d`

| Product | SHA-256 |
| --- | --- |
| Both suite `payload.tar.gz` files | `c8bd31c4484ca4c216dd21949da147056900d1d0289037288114d86ab06e819c` |
| Both suite `payload.manifest` files | `27cea132d6950bbcf45886b88e7a287697a625cd998c2486d8fe9467933a8d5e` |
| Forky `preseed.cfg` | `6b90fa657c57fb2510bc7396eff284cc36f5b4b8b2256ac12e8495e03fa237c0` |
| Trixie `preseed.cfg` | `c53c1976a63da90d244e69b6e6d2bc91d84a940bd5e79d194d0a3d2442eb509b` |
| Both suite `receipt.json` files | `f32680b15035f9cbf08b9aa97ee372f5bad42607ec6ca493d083db462eb29d06` |
| `scripts/late/whisper.sh` | `07eb3d083318184f98da69cbceb5617558b6394dabd229a72c639825afda0cc3` |
| `tools/post_change_check.py` | `aa48c6b38652120b5367b293ce24caa71bebb7fd013788375789421f6dda088f` |
| Guarded regression fixture | `320e367699f854a3fc1358fd1c89211337b40c017523d0107d2accc4b114218a` |

Changed authored owners are `scripts/late/whisper.sh`,
`tools/post_change_check.py`, the guarded regression fixture and this report.
Changed generated products are each suite's payload, manifest, preseed and
receipt. The shared source bootstrap and support matrix serialize identically.

## Verification limits

These results establish source syntax, the inspected environment and rendering
contracts, and current archive/source consistency. They do not establish a
completed installation, a successful network download, target Perl imports,
GUI launch, loaded AppArmor policy, hardware behavior or external deployment.
No target image or native fixture was run, so there is no native cleanup state
or target package-version result. The generated products must be served together
for the next installation to consume this revision.

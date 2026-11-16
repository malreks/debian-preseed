# Tailscale and shared script path publication

This repair addresses unresolved runtime path placeholders when Tailscale
loads the D-Bus helper, and the same contract in sibling script loaders.
Evidence is source inspection, data-only rendering and pure serialization.
No native installer, target service, package transaction or desktop application
was executed. The supplied `todo` log snapshots predate the reported Tailscale
failure; the diagnosis below is established by the current source ordering.

## Causes and changes

- `scripts/late/tailscale.sh` fetched `FILE_LATE_DBUS_BROKER` before loading
  its compiled host environment. The child shell did not inherit the
  dispatcher's unexported canonical target paths. The shared renderer therefore
  lacked the values needed by the D-Bus template. Tailscale now validates and
  loads that environment before helper acquisition, and reacquires the D-Bus
  helper instead of accepting a readable file retained by an older failed
  renderer.
- `scripts/common/fetch.sh` previously fetched to the final destination before
  rendering paths. A failed render could leave a raw template at that path.
  `installer_fetch_seed_path` in `scripts/common/modules/repository-apt.sh` now
  fetches, renders with the existing scalar renderer, rejects unresolved path
  tokens and sets the requested mode inside one private sibling directory.
  Only a complete candidate replaces the destination. The path covers every
  script family through `DIR_REPO_SCRIPTS`, plus target assets through
  `DIR_HOOKS_TARGET`. Ordinary non-script data remains literal.
- `scripts/common/bootstrap.sh` delegates to that publisher only after its
  source-library dependency is initialized. The earlier bootstrap fallback
  stages privately and validates path rendering before publication. Common
  and runtime modules no longer bypass the shared path by calling the raw
  transport directly. Both paths reject rendering into the authenticated
  source snapshot. Source templates and their manifest digests remain intact.
- `scripts/late/devops.sh.tmpl` now loads the selected compiled profile before
  loading its implementation modules. Previously that happened only inside
  `devops_main`, after the modules already needed rendering. The redundant
  later profile load was removed from `devops/main-orchestration.sh`.

Authored templates retain their canonical placeholders. Installer-side loaded
scripts and published target files require concrete paths. No second renderer,
path owner or hard-coded target path was introduced.

## Shared inspection and static evidence

- The data-only path audit covers 134 script assets and 850 target assets.
  Every concrete path token in that set has a value in the canonical runtime
  contract. Bootstrap dependency checks also enforce that the scripts needed
  before profile loading contain no concrete runtime path tokens.
- Archive inspection verifies all six changed script owners against current
  checkout bytes in both payloads. All 19 compiled host profiles in each suite
  provide the 280 path variables referenced by scripts. Account-only snapshots
  are separate data and are not treated as complete host environments.
- The shared target asset inventory includes Bitwarden, QoreDB, Obsidian,
  Tomat, Sleek, Postman, Discord, Tuta, Ledger, ChatGPT/Codex, Zoom and Filen,
  alongside other desktop, server, firstboot and common helpers. Their existing
  target publication consumers remain under the same renderer. Servicing
  constructors, download policy, application eligibility and private Xwayland
  configuration were not changed.
- `tools/post_change_check.py` adds persistent checks for the complete path
  token inventory, bootstrap module routing, publication order and the two
  entrypoint environment-loading orders.
- The isolated fixture source in `test_installer_contracts_20261115.py` was
  extended to cover all seven source families, initialized/fallback/partially
  initialized loaders, missing profile values, unknown tokens, failed fetches
  and rendering, stale cached content, original destination bytes/modes and
  unchanged source bytes. These native fixture cases were **not executed**.
  Their shell driver was extracted as AST data and parsed by `dash -n`,
  `busybox sh -n` and ShellCheck with error severity only.

The authorized validation commands are `timeout 120s make build`,
`timeout 180s python3 -B tools/post_change_check.py`, and `git diff --check`.
Generation is pure serialization. The changed-file audit uses source parsers,
ShellCheck, data-only contract checks, archive comparisons and frontend pins;
it does not execute the fixture or installer. Tool versions observed for this
record: Python 3.14.10 and ShellCheck 0.11.0.

## Artifact identity and limits

Base commit: `87a9904dc387ce90fd25f091cbe16d9fc042b874`.

Both suite receipts identify release
`caa6ec65037554a5d7ab2e6633afc63dbee918f8d27599a3702244e1e8c64cda`
and captured source fingerprint
`873348845ed6f7b8cd153213cd9a0deb4afaf880e94a7779dfc0ef84c16d1ff2`.
The two payloads have SHA-256
`4ad6b7ffe1fe7e366984de538cb2082b9a4a2b9c490f4dca342d10da830fe698`;
their manifests have SHA-256
`5c2cbbab1e89430e258d6f45257e66c15ef9e47e4d97b116d323c9123722e238`.

Native installation and target launch/boot behavior remain unverified. No VM,
container, chroot, offline catalog generation, host policy/service operation,
commit, push or deployment was performed. Enrollment-pending records remain
informational, as required by the existing installer contract.

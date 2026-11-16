# Installer hook instructions

## Host scratch storage prohibition

This restriction applies to the development host only. The Debian Installer,
installed target, and approved isolated guests may use their own `/tmp`, tmpfs,
and other configured memory-backed filesystems.

Never use the real host's `/tmp`, `/var/tmp`, `/dev/shm`, or any tmpfs or
RAM-backed host directory for work, downloads, staging, caches, temporary files,
build scratch space, parser support, or validation artifacts. Never create or
mount a host tmpfs. Use private, owned storage under `.build/validation/` on the
checkout's verified disk-backed filesystem, and set `TMPDIR`, `TMP`, and `TEMP`
explicitly for commands and subprocesses. Stop or correct helpers that ignore
these settings; do not fall back to host temporary directories. Delegated work
follows the same rule. Approved VM guest filesystems are separate; all host
images, captures, scratch files, and outputs remain on disk.

The repository-root `AGENTS.md` and `d-i/debian/AGENTS.md` remain authoritative.
This directory owns installer-phase hooks and the installer-only environment
contract.

- `di.env` is the sole source for the mounted target, installer temporary
  locations, phase hook directories, partman interfaces, and installer log.
  It is fetched from the authenticated seed using its repository selector,
  validated, and sourced before installer phase dispatch.
- Installer hook source files must not hard-code repository, target, temporary,
  hook, or generated-state paths. Resolve source labels and operation contexts
  through `repo.env` selectors, and resolve installer destinations from
  `di.env`; retain a literal only for an immutable Debian partman/package
  interface and document that interface beside the use.
- `repo.env` owns only checkout-relative `DIR_*`/`FILE_*` selectors and is never
  sourced on the installed target. `hosts/installer/runtime.env` owns target
  filesystem paths and target policy/state; `di.env` owns d-i-only paths. Do
  not publish `di.env` values into target runtime configuration or introduce
  aliases that repeat a root.
- If a target asset is staged from an installer hook, preserve its
  `__INSTALLER_PATH_*__` placeholder until the shared publication renderer
  resolves it once. Reject unresolved tokens and do not substitute paths
  locally in an individual hook.
- Keep repository selectors in `repo.env` and installed-system target roots in
  `hosts/installer/runtime.env`. Do not duplicate a root across these
  contracts or add variable-only aliases.
- Installer hooks may use target roots only through the mounted-target value
  and the canonical runtime contract. Hooks must not publish the installer
  environment or installer state into the installed target.
- Standalone base-stage, apt-setup, partman and finish-install hooks must load
  the cached bootstrap/`di.env` contract before deriving installer destinations;
  exact Debian partman interface paths may remain literal only when the
  package contract requires that spelling.
- Preserve phase boundaries and the static-only validation boundary. Do not
  execute hooks, package scripts, services, D-Bus, hardware, or host helpers.

## Source selector naming and staging

- Every published source directory and file has a `DIR_*` or `FILE_*` entry
  in `repo.env`. Use concise role/component names such as
  `DIR_TARGET_SKEL_PROFILE`, `FILE_TARGET_SKEL_DIRCOLORS`,
  `FILE_TARGET_SKEL_PROFILE_71_DEVOPS_DE`, and `FILE_LATE_CORE`; do not encode
  the entire filesystem hierarchy or duplicate extensions in a selector name.
- File entries name physical payload members, including `.tmpl` when present,
  and derive from their nearest directory selector. Fixed installer callers
  resolve `FILE_*` through `installer_repo_file_value`,
  `bootstrap_repo_file_value`, or the preseed entrypoint equivalent. Dynamic
  source choices use `installer_repo_asset_path` and the cached FILE catalog;
  directory operations use DIR selectors. Do not reconstruct a fixed source
  filename or a static directory prefix at a staging call site.
- Repository selectors remain installer acquisition data. Installed paths and
  target policy stay in `hosts/installer/runtime.env`; d-i destinations and
  state stay in `hooks/installer/di.env`. Profiles and themes retain their
  policy/appearance ownership. Installed programs must not source any of these
  installer input files or receive repository selectors as runtime settings.
- Keep FILE and DIR diagnostic interfaces distinct: FILE context calls pass
  selector, source line, and operation; DIR context calls additionally pass a
  relative leaf. Diagnostic lookup is advisory and must never trigger a fetch,
  fail a valid operation, or report a line belonging to a different source.
- A selector change requires an audit of fixed and dynamic callers, source
  labels, loader/template suffix handling, fixtures, and generated products.
  Preserve Dash/BusyBox compatibility; do not add `stat`, Bash features,
  environment-size limits, or a second path renderer to the installer.

# Installed target asset instructions

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

The repository-root and `d-i/debian/AGENTS.md` instructions apply here.

- Files in this directory are installed-system assets. Project-owned absolute
  paths must use the shared installer placeholder namespace and be rendered
  once by the d-i publication path. Installed files must contain concrete
  target paths and must never source the runtime environment at runtime.
- Do not hard-code repository checkout paths, d-i temporary paths, installer
  hook paths, or duplicate target roots in target assets. Repository source
  selectors belong to `repo.env`, installer-only paths belong to
  `hooks/installer/di.env`, and installed target paths belong to
  `hosts/installer/runtime.env`; use the shared placeholder renderer when a
  target path is needed in source. A literal is permitted only for a documented
  immutable Debian/FHS/package/AppArmor/systemd interface.
- Render each `__INSTALLER_PATH_*__` token once at the publication boundary,
  reject unresolved or traversal-bearing values, and keep the installed file
  independent of the runtime environment file. Theme/profile data may select
  policy or appearance values but never owns filesystem roots or repository
  selectors.
- Keep `/usr/bin` versus `/usr/local/bin`, `/usr/local/libexec`, Perl and
  Python module roots, systemd roots, AppArmor roots, and firstboot state tied
  to the canonical runtime contract. Do not introduce duplicate roots or
  variable-only aliases.
- AppArmor profiles must retain exact least-privilege paths, child domains,
  modes, and intentional denials. Never add broad wildcards or capabilities,
  switch to complain mode, or load policy into the host kernel.
- Waybar and GTK assets must preserve native module/menu contracts, canonical
  XML IDs and action maps, the existing Apps drawer protocol, and the private
  popup owner boundary. Do not convert native modules to `custom/*`.
- Keep target files idempotent, atomic where published, correctly owned and
  mode-checked. Validate unresolved placeholders, symlinks, traversal and
  generated ownership at the existing staging boundary.

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

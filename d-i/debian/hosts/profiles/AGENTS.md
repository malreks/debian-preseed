# Host profile instructions

The repository-root, `d-i/debian/AGENTS.md`, and the shared profile schema are
authoritative.

- Profile files are validated data contracts, not executable shell programs.
  Preserve assignment grammar, class/profile names, inheritance and sibling
  consumers. Do not add command substitution, `eval`, unbounded expansion or
  secrets.
- Profile variables own policy, feature, package, hardware, storage, network,
  security, software, and firstboot data. They do not own repository selectors,
  installer destinations, mounted-target paths, or installed-system roots.
  Never hard-code those paths in a profile; use the owning `repo.env`,
  `hooks/installer/di.env`, or `hosts/installer/runtime.env` contract through
  the existing renderer and preserve the profile's override ownership.
- Repository `DIR_*`/`FILE_*` selectors are relative and parent-derived in
  `repo.env`; installer-only state is in `di.env`; concrete target paths are in
  `runtime.env`. Do not source repository or installer environments from an
  installed target, duplicate roots, or add variable-only aliases.
- Profile `.env` files use ordinary `${VARIABLE}` references to earlier
  validated assignments, including canonical directories from `runtime.env`.
  They must not contain template placeholders. The restricted data parser
  resolves these references without sourcing shell code. Template placeholders
  belong only to target asset templates, whose publication uses the shared
  renderer. Keep installer-relative selectors in `repo.env` and do not add
  installer-only path or state keys to the installed-system contract.
- Keep profile overrides compatible across desktop, hardware, storage, network,
  security, software and firstboot callers. A changed key requires a search of
  every renderer, hook, service, AppArmor rule and generated payload consumer.
- Preserve optional/unavailable outcomes and all security, thermal, private
  XWayland, Waybar-native and systemd lifecycle boundaries. Do not turn an
  informational firmware or enrollment record into a source change.
- Use only static parsing, deterministic rendering, pure `make build`, and the
  changed-file audit. Do not execute profile code or run installer/native tests.

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

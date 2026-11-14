# Theme and appearance contract instructions

The repository-root, `d-i/debian/AGENTS.md`, and the Waybar/theme contract are
authoritative.

- Theme files are catalog data. Preserve the `__THEME_*__` marker grammar,
  schema allowlists, field IDs, source-line mappings and defaults-only
  appearance rendering. Do not duplicate a theme key or action table.
- Theme variables own appearance data only. They do not own repository
  selectors, installer destinations, mounted-target paths, or installed-system
  roots. Do not hard-code those paths in a theme; use `repo.env` for relative
  source selectors, `hooks/installer/di.env` for d-i-only paths, and
  `hosts/installer/runtime.env` through the shared target placeholder renderer
  for installed paths.
- Preserve `__INSTALLER_PATH_*__` tokens until the single publication renderer
  resolves them, then reject unresolved tokens. Never add ad-hoc substitutions,
  restore a literal project path to satisfy a checker, or source an environment
  file from an installed theme asset. Repository selectors remain parent-derived
  `DIR_*`/`FILE_*` values in `repo.env`.
- Project-owned installed paths must use the shared installer placeholder
  renderer before theme substitution. Repository source selectors use the
  grouped hierarchy in `repo.env`; do not restore literals when a placeholder
  or selector is required.
- Keep native Waybar `clock`, audio, battery, brightness/backlight, disk, CPU,
  memory and other built-in modules native. Preserve the existing launcher
  marker and Apps drawer prelight/expanded protocol. Only the authorized
  Tomat, Wayscriber, notifications and power popup owner may use the bounded
  transient GTK lifecycle path.
- Preserve GTK XML IDs, menu-actions, CSS class sources, AppArmor policy,
  renderer/staging cases, firstboot provisioning and appearance registry
  mappings as one shared contract. Do not claim popup state from `:active`, a
  timer or a click-only marker.
- Validate theme data and rendering statically only. Do not launch GTK, Waybar,
  Labwc, D-Bus or a systemd manager; report those verification limits.

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

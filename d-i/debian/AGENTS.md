# Shared Debian installer subtree instructions

The repository-root `AGENTS.md` is authoritative. These additional rules apply
to every file below `d-i/debian/`:

- Keep source inspection and pure serialization as the default. Native tests,
  installer hooks, package scripts, systemd, D-Bus, network and hardware
  validation may run only inside the controlled isolated-validation boundary
  defined by the repository-root `AGENTS.md`; never run them on the host or
  with host mounts, sockets, credentials, devices or namespaces. Chroot,
  container and VM validation must use the same private, bounded boundary. The
  only generation command is `make build`; it may overwrite only the flat suite
  products and generated preseeds declared in root `AGENTS.md`. It must not
  create release or publication directories.
- Keep `hosts/installer/runtime.env` limited to installed-system target paths
  and target state. Keep repository-relative selectors in `repo.env`. Keep
  installer-only destinations and state exclusively in
  `hooks/installer/di.env`. Do not create aliases that repeat a root or whose
  complete value is another variable.
- No new source, documentation, template, or generated input may hard-code a
  project, checkout, installer, target, or generated-state path. Use the
  owning environment contract and its existing selector/renderer; retain a
  literal only for an immutable Debian/FHS or package interface and document
  the reason beside the consumer.
- `repo.env` is the only owner of repository-relative `DIR_*`/`FILE_*`
  selectors. Assign parent-first, resolve selectors through the cached
  bootstrap/entrypoint join helpers, and never source repository selectors on
  the installed target. `hosts/installer/runtime.env` owns concrete target
  paths and target policy/state; `hooks/installer/di.env` owns d-i-only target
  mount, temporary, hook, partman, and log paths. Do not cross-publish values
  between those contracts or add variable-only aliases.
- Target source assets use `__INSTALLER_PATH_*__` placeholders until the shared
  publication renderer materializes them. Render once, reject unresolved
  tokens, and never perform caller-specific substitutions. Profile files own
  policy/configuration data and theme files own appearance data; neither owns
  repository selectors or filesystem roots.
- Environment changes require a repository-wide consumer search and a rebuild
  of authorized generated products. Diagnostic source labels and operation
  contexts must use selector-resolved paths so installer failures name the
  actual operation source.
- Target assets use the shared installer path-placeholder namespace until the
  publication renderer materializes them. Never replace a target placeholder
  with a literal to satisfy a checker; render the candidate through the
  existing publication boundary and reject unresolved tokens.
- Repository selectors must derive from the hierarchy in `repo.env`, with
  separate groups for target assets, scripts, hosts, and installer hooks.
  Preserve installer phase and target-root boundaries; never add a second
  target mount prefix after entering the target.
- Preserve private-XWayland eligibility for Discord and Zoom, native Waybar
  module identities, AppArmor confinement, lifecycle ownership, and bounded
  retries/timeouts. Do not hide diagnostics or broaden policy permissions.
- After source changes, run `python3 -B tools/post_change_check.py` and
  `git diff --check`; run the permitted pure `make build` when payload inputs
  changed. Any native verification must be a separately recorded run inside
  the reviewed isolated-validation boundary, with host execution and fallback
  prohibited.

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

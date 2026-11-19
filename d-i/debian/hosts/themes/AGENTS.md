# Theme and appearance contract instructions

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

The repository-root, `d-i/debian/AGENTS.md`, and the Waybar/theme contract are
authoritative.

- Theme files are catalog data. Preserve the `__THEME_*__` marker grammar,
  schema allowlists, field IDs, source-line mappings and defaults-only
  appearance rendering. Do not duplicate a theme key or action table.
- Theme variables own appearance data only. They do not own repository
  selectors, installer destinations, mounted-target paths, or installed-system
  roots. Do not duplicate those roots in a theme; use `repo.env` for shared
  relative roots, `hooks/installer/di.env` for d-i-only paths, and
  `hosts/installer/runtime.env` through the shared target placeholder renderer
  for installed paths.
- Preserve `__INSTALLER_PATH_*__` tokens until the single publication renderer
  resolves them, then reject unresolved tokens. Never add ad-hoc substitutions,
  restore a literal project path to satisfy a checker, or source an environment
  file from an installed theme asset. Shared repository roots remain
  parent-derived `DIR_*` values in `repo.env`; fixed members and stable leaves
  may be documented literal data.
- Project-owned installed paths must use the shared installer placeholder
  renderer before theme substitution. Shared repository roots use the
  hierarchy in `repo.env`; fixed source members do not require global aliases.
  Preserve placeholders for project-owned target paths.
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

## Repository configuration and source staging

- `repo.env` contains the supported repository defaults and genuinely shared
  `DIR_*` roots. It is restricted assignment data, not shell code. Keep shared
  roots parent-derived; do not restore a `FILE_*` inventory, aliases for every
  file, or a second configuration authority.
- Stable source members are documented root-relative interfaces at their
  callers, including the physical `.tmpl` suffix where present. Local constants
  and literal leaves are allowed when that interface has no supported
  variability. Keep suite/profile/site choices, configurable roots and policy
  in their owning contracts; never substitute a developer-machine path or
  duplicate a shared root.
- Preseed, bootstrap and common adapters share `source_load_repo_env`. Its
  restricted AWK parser rejects executable syntax, unknown/duplicate/missing
  keys, undefined parents and unsafe relative paths. Never dot-source or
  `eval` repository configuration, and never load it on the installed target.
- Build validates supported configuration and physical source members, and
  compiles `catalog/compiled/source-members.tsv` from the captured snapshot.
  Selected APT publication uses the smaller `apt-assets.tsv` table. Those
  generated indexes carry membership data; they are not exported environment
  variables or an alternative authored path contract.
- Resolve dynamic members against the captured membership table at the owning
  loader/publication boundary. Retain containment, direct-file, template,
  ownership and permission checks there. Diagnostics name the resolved physical
  root-relative member and source line, remain advisory, and never trigger a
  fetch or change a successful operation into a failure.
- Installed paths and policy remain in `hosts/installer/runtime.env`; d-i-only
  destinations and state remain in `hooks/installer/di.env`. Profiles and themes
  retain policy/appearance ownership. Installed programs receive concrete
  rendered configuration and must not source these installer input files.
- A configuration or member change requires a consumer, diagnostic, fixture and
  generated-product audit. Preserve Dash/BusyBox compatibility, phase and
  target-root boundaries, and the single target-placeholder renderer. Do not
  add a large exported environment or an installer `stat` dependency.

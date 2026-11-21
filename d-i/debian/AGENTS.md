# Shared Debian installer subtree instructions

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
  and target state. Keep repository defaults and shared relative roots in `repo.env`. Keep
  installer-only destinations and state exclusively in
  `hooks/installer/di.env`. Do not create aliases that repeat a root or whose
  complete value is another variable.
- Stable root-relative source members and documented internal leaves may be
  local constants. Do not create a global selector for every file, duplicate
  shared roots, embed developer-machine paths, or remove supported configuration.
  `repo.env` owns only repository defaults and shared `DIR_*` roots, parsed as
  data by `source_load_repo_env`; never dot-source or `eval` it. Build validates
  the schema and physical members and compiles the source membership indexes.
  `runtime.env` and `di.env` retain their target and installer ownership.
- Target source assets use `__INSTALLER_PATH_*__` placeholders until the shared
  publication renderer materializes them. Render once, reject unresolved
  tokens, and never perform caller-specific substitutions. Profile files own
  policy/configuration data and theme files own appearance data; neither owns
  repository selectors or filesystem roots.
- Environment changes require a repository-wide consumer search and a rebuild
  of authorized generated products. Diagnostic source labels and operation
  contexts must name resolved physical root-relative members so installer failures name the
  actual operation source.
- Target assets use the shared installer path-placeholder namespace until the
  publication renderer materializes them. Never replace a target placeholder
  with a literal to satisfy a checker; render the candidate through the
  existing publication boundary and reject unresolved tokens.
- Shared repository roots derive from their hierarchy in `repo.env`, with
  fixed member leaves at their owning callers and generated membership data.
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

## Current desktop and storage remediation contract

- Shared fixes must be carried through both Forky and Trixie payload inputs:
  external Waybar normal text is weight 500, CPU btop uses a height-safe box
  set, the native backlight module keeps its cursor contract and selects a
  hardware-safe device at the renderer boundary, and
  Wayscriber remains the existing custom module with its canonical GTK action
  map and visible fallback glyph.
- Keep the exact Wi-Fi prepared-profile AppArmor rule, the frozen-layout
  PARTUUID swap identity, and the private hyprpolkit aquamarine workaround in
  their owning target assets. Do not broaden policy or add a second writer.
- Use `.build/validation/` for any host-side scratch and set `TMPDIR`, `TMP`,
  and `TEMP` explicitly; never fall back to host temporary storage.
- Keep `etc-access-denied` and `boot-access-denied` audit rules restricted to
  `EACCES`/`EPERM`; expected systemd `ELOOP` alias lookups are not permission
  failures and must not create recurring audit churn.

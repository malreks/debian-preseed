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
  It is fetched from the authenticated seed as `hooks/installer/di.env`,
  validated, and sourced before installer phase dispatch.
- Hook source members and stable internal leaf names may be documented local
  constants. Resolve shared repository roots from the restricted `repo.env`
  contract, installer destinations from `di.env`, and installed paths from
  `runtime.env`. Never duplicate configurable roots or use developer-machine
  paths. Source labels and operation contexts name the physical member.
- `repo.env` owns repository defaults and shared relative `DIR_*` roots, never
  a `FILE_*` inventory or installed settings. Use `source_load_repo_env` rather
  than dot-sourcing or `eval`. Do not publish `di.env` values into target runtime
  configuration or introduce aliases that repeat a root.
- If a target asset is staged from an installer hook, preserve its
  `__INSTALLER_PATH_*__` placeholder until the shared publication renderer
  resolves it once. Reject unresolved tokens and do not substitute paths
  locally in an individual hook.
- Keep shared repository roots and defaults in `repo.env` and installed-system target roots in
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

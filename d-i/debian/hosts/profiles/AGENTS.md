# Host profile instructions

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

The repository-root, `d-i/debian/AGENTS.md`, and the shared profile schema are
authoritative.

- Profile files are validated data contracts, not executable shell programs.
  Preserve assignment grammar, class/profile names, inheritance and sibling
  consumers. Do not add command substitution, `eval`, unbounded expansion or
  secrets.
- Profile variables own policy, feature, package, hardware, storage, network,
  security, software, and firstboot data. They do not own repository selectors,
  installer destinations, mounted-target paths, or installed-system roots.
  Do not duplicate those roots in a profile; use the owning `repo.env`,
  `hooks/installer/di.env`, or `hosts/installer/runtime.env` contract through
  the existing renderer and preserve the profile's override ownership. Stable
  relative member names and internal leaves may remain literal data.
- Shared repository `DIR_*` roots are relative and parent-derived in
  `repo.env`; stable source members belong in the selection catalog/caller; installer-only state is in `di.env`; concrete target paths are in
  `runtime.env`. Do not source repository or installer environments from an
  installed target, duplicate roots, or add variable-only aliases.
- Profile `.env` files use ordinary `${VARIABLE}` references to earlier
  validated assignments, including canonical directories from `runtime.env`.
  They must not contain template placeholders. The restricted data parser
  resolves these references without sourcing shell code. Template placeholders
  belong only to target asset templates, whose publication uses the shared
  renderer. Keep shared repository roots and defaults in `repo.env` and do not add
  installer-only path or state keys to the installed-system contract.
- Keep profile overrides compatible across desktop, hardware, storage, network,
  security, software and firstboot callers. A changed key requires a search of
  every renderer, hook, service, AppArmor rule and generated payload consumer.
- Preserve optional/unavailable outcomes and all security, thermal, private
  XWayland, Waybar-native and systemd lifecycle boundaries. Do not turn an
  informational firmware or enrollment record into a source change.
- Use only static parsing, deterministic rendering, pure `make build`, and the
  changed-file audit. Do not execute profile code or run installer/native tests.

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

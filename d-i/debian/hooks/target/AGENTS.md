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
  hook paths, or duplicate target roots in target assets. Shared repository roots
  and defaults belong to `repo.env`, installer-only paths belong to
  `hooks/installer/di.env`, and installed target paths belong to
  `hosts/installer/runtime.env`; use the shared placeholder renderer when a
  target path is needed in source. Documented stable internal leaves and exact Debian/FHS/package/AppArmor/
  systemd interfaces may be local constants; they must not duplicate shared
  roots or replace supported configuration.
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

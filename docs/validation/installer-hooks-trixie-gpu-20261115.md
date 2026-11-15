# Installer namespace hook, Trixie dependencies and GPU selection

The current source fixes the unavailable temporary-unshare hook lookup,
permits native Trixie desktop dependencies, and enforces one-way matching
CUDA/NVIDIA requirements. This record contains static and serialization
evidence. No native installation, package transaction, DKMS build, boot or GPU
acceptance was executed.

## Changes and shared contracts

- `FILE_INST_PREPKG_PLAN`, the shared installation-plan module and
  `FILE_LATE_SOFTWARE_TMPL` now use `installer_pre_pkgsel_stage_path` for the
  published namespace stage. The late consumer no longer addresses the retired
  numeric pre-pkgsel hook. It rejects a missing, non-regular, symlinked or
  non-executable stage. Existing diversion and shim marker checks remain.
- The shared managed-software stage serves Bitwarden, QoreDB, Obsidian, Tomat,
  Sleek, Postman, Discord, Tuta, Ledger, ChatGPT, Zoom and Filen; Codex retains
  its separately ordered owner. The static audit checks all 13 managed
  application owners and the shared namespace-stage contract. No servicing API,
  vendor download policy, application eligibility or target wrapper was changed.
- Trixie desktop preferences permit `xwayland`, `xserver-common` and
  `x11-xkb-utils`. Trixie server preferences permit `x11-xkb-utils` because the
  catalog records `timeshift -> libxapp1 -> libgnomekbd8 -> libxklavier16`.
  Server Xwayland and full X.Org exclusions remain. The suite policy now marks
  Trixie desktop as a source candidate, with runtime acceptance unverified.
- Private-Xwayland provisioning no longer purges or rejects those native
  Trixie dependencies. The private extracted runtime, application eligibility
  and global compositor configuration remain unchanged. Firstboot validation
  selects the appropriate package-presence rule from the validated suite
  receipt instead of requiring public Xwayland absence for every suite.
- The physical class-dispatch constraints require explicit matching selections:
  `cuda` requires `nvidia` and rejects `nvidia-legacy`; `cuda-legacy` requires
  `nvidia-legacy` and rejects `nvidia`. Both CUDA classes and both driver
  branches remain mutually exclusive. Neither driver requires CUDA.
- The compiler publishes those same requirements/conflicts into early class
  metadata and the frozen plan. The resolver also refuses missing explicit
  requirements instead of implicitly adding a driver. The existing NVIDIA
  hardware gate remains. The offline policy enumerator consumes the generated
  graph, so invalid toolkit-only and mismatched contexts are filtered there too.
- Both suites' NVIDIA classes own their repository/key declarations. Current
  NVIDIA uses the signed Debian 13 channel, open kernel modules and separate
  Wayland/compute userspace components. CUDA requests the 13.5 compiler,
  libraries, development files, command-line tools, NVML headers and NCCL.
  Desktop/server optional pins agree across both suites. The driver opt-in
  exclusion covers the additional userspace package names.
- The 580-series/CUDA 12.8-12.9 compatibility packages are retained. Their
  repository declaration moved to the legacy driver class; temporary CUDA
  helpers read that owner. Driver-only legacy selection uses ordinary apt-setup.
  The existing explicit temporary CUDA installation exception is retained, but
  late cleanup and finish-install publish a normal signed source for upgrades.
  That transition occurs before vendor source normalization and retains the
  scoped key. It does not leave the temporary authentication/date flags in the
  installed source policy.

## Public package evidence

NVIDIA's public Debian 13 `Packages.gz` was read over HTTPS as data. The observed
compressed-index SHA-256 was
`a70890b857e3554ae703f46e791d7d80c72149ab4844845374c915eb12c8a051`.
The index publishes `nvidia-kernel-open-dkms`, `nvidia-driver-cuda` and
`nvidia-egl-icd` at `620.70.06-1`; CUDA compiler/library aggregates at `13.5.0-1`;
NVML headers at `13.5.37-1`; and NCCL at `2.32.6-1+cuda13.5`.
This inspection establishes published metadata, not a passing APT solve or a
locally verified signature for this new metadata acquisition. Installation
continues to use the repository's scoped-key authentication path.

The open-source designation applies to NVIDIA's kernel modules. CUDA and
parts of the userspace driver remain proprietary. Component package selection
avoids the full NVIDIA X.Org metapackages and preserves the existing Vulkan
ICD exclusions.

## Executed checks and artifact identity

- `timeout 120s make build`: passed; pure serialization only.
- `python3 -B tools/post_change_check.py`: passed after regeneration, including
  shell syntax/ShellCheck, Python AST, structured data, decoded preseed syntax,
  source/payload equality, eight driver/toolkit selection contracts, the
  namespace-stage contract, and 22 role combination plans. An interim audit
  before regeneration refused the expected stale source/product identity.
- `git diff --check`: passed.
- Independent standard-library data inspection of both tarballs checked all
  16 optional class combinations per suite, the matching early requirement
  metadata, driver-only independence, repository ownership, the Trixie suite
  policy and identical payload bytes. Exactly five optional sets are valid:
  none, either driver alone, or either matching driver/toolkit pair.

Generated release:
`0425412490f4b0fd371361af7e73ba8f8e7bf33c7fb18c2adf7d4b25031e8653`.
Source fingerprint:
`9e8a6214be4660a7f6e2dde995efc55a8918bbf1f985bd4b5643c0097f1e92e0`.
Both normal payloads have 2,421 members and SHA-256
`c0a29dd364007ad3c8b5f246afb83ce6f7d2c6bd1e21149fe610e47c1d68de4f`.

## Deferred native evidence and preserved output

The isolated regression fixture `test_installer_contracts_20261115.py` covers
64 actual frozen-resolver combinations, suite-specific purge behavior and
shared stage paths, including invalid path input. It was authored and parsed,
not executed. Its SHA-256 is
`5a761959c7d1e82c927b4062f082f8a6b19ccd81eab4fbfaee79280ede8e5c08`.
The adjusted CUDA lifecycle fixture SHA-256 is
`7c3ff72fa40eee58368a782e634f5492eb45cc2f5a33125d509689c59b57b35e`.
The strict isolation guard was reviewed; no prepared private validation image
was identified during bounded checkout inspection. No host-native runner, installed management
helper, package manager or service was invoked for testing. Full installation,
real APT solving and target GPU/DKMS behavior remain unverified.

Offline generation was not run, as previously requested. The user-generated
offline archive was preserved with SHA-256
`be4039b1f5b1ea71f944a5b75ff421dcafe12957ced140e92c9c30347b647e94`;
its catalogs predate these corrections. The previously referenced root audit
document was absent; this record uses current owning source and generated
products as evidence.

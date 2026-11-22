# Audit remediation record — 2026-11-21

This record captures the source and generated-product work applied from
`todo/AUDIT.md`. It is an engineering receipt for review; it is not a native
installation or release approval.

## Implemented contracts

- Forky and Trixie keep the complete CUDA 12.8 and 12.9 component families.
  Each class contains 68 package names: 34 with the `-12-8` suffix and 34 with
  the `-12-9` suffix. The selected compiler wrappers are versioned and force
  Pascal `sm_61` code generation while clearing inherited CUDA and loader
  overrides.
- The NVIDIA legacy class uses the same package set and APT policy as the
  legacy repository: the 580 driver, firmware, DKMS, kernel-source, userspace,
  and library packages are pinned with `Pin: release o=xanmod` at priority
  900, with the broader XanMod archive at priority 100. The driver-only class
  does not publish CUDA answers; the separate `optional/cuda-legacy` class owns
  the Debian 12 compatibility archive and its complete 12.8/12.9 package set.
- The legacy hardware gate requires exactly one NVIDIA display adapter with
  PCI ID `10de:1d34` (Quadro P520). Unknown NVIDIA display IDs and incomplete
  PCI identity data fail closed before package selection.
- NVIDIA legacy installation no longer performs a package candidate/origin
  preflight or writes a package receipt. APT receives the selected legacy
  class directly from the XanMod source and resolves its dependencies normally.
- The requested CUDA repository exception remains scoped to the temporary
  CUDA refresh. Its existing insecure flags and date policy are unchanged.
  The configured NVIDIA key URL is staged and the installer-only source is
  removed by the existing finish-install cleanup boundary. CUDA and XanMod
  repository fingerprints are not inspected.
- The legacy NVIDIA DKMS cleanup hook is fetched into finish-install and given
  executable mode only in that installer copy; its authored repository file
  remains mode 600. The late NVIDIA receipt verifier, NVIDIA package
  preflight, CUDA late receipt verifier, and first-boot package receipt checks
  are removed, so pkgsel is not blocked by duplicate package metadata scans.
- Forky follows the legacy private-Xwayland flow: public `xwayland` is
  available during pkgsel only when needed for dependency resolution, then the
  late desktop stage purges it before publishing the private runtime. Trixie
  keeps native `xwayland`, `xserver-common`, and `x11-xkb-utils` installed for
  Labwc and keyboard dependencies while the private runtime remains the
  Discord/Zoom compatibility boundary under `/opt/xwayland`.
- The private runtime publishes a receipt for its four pinned snapshot
  packages and twelve APT-resolved libraries. Each record includes the exact
  version, architecture, SHA-256, and source class. Extraction rejects special
  files, set-ID files, escaping symlinks, and writable runtime directories.
- Secret installer values are read from the protected preseed input; command
  line secret overrides are ignored. Tailscale SSH is disabled by default,
  shields-up/stateful filtering are enabled, NFS is opt-in, and P520 NVIDIA
  tuning no longer requests unsupported power or clock limits by default.
- Secure-Boot/MOK failure is release-blocking when `module.sig_enforce=1` is
  selected. Waybar event readers use a 120-second recovery interval instead
  of frequent process restarts.
- Google Android SDK Platform-Tools is pinned to revision 37.0.3, its
  revision-specific archive URL, and SHA-256
  `214548146cadb2ca3508143d8a1d4be4c59de5bb837253e3ede89ed74cf450d1`.

## Static evidence

The pure serializer was run with all host scratch variables directed to the
checkout-owned disk-backed validation directory:

```text
env TMPDIR=.build/validation/build-20261122-cuda-line131 \
    TMP=.build/validation/build-20261122-cuda-line131 \
    TEMP=.build/validation/build-20261122-cuda-line131 \
    make build
```

It completed successfully with source identity
`2de3917e00b256f668f57877421b5d5b85e2bab1f5d464cf6885685aec77aa60`,
2,442 payload members, and regenerated Forky/Trixie payload, manifest,
receipt, source, and preseed products.
Both suite receipts report source fingerprint
`d5fc549b8903536dd7917f086712fe4c528e5be2cb1e3216e6fcbba8a553a0f4`.

The required changed-file audit completed successfully:

```text
env TMPDIR=.build/validation/post-change-20261122-cuda-line131 \
    TMP=.build/validation/post-change-20261122-cuda-line131 \
    TEMP=.build/validation/post-change-20261122-cuda-line131 \
    python3 -B tools/post_change_check.py
```

The result was `post-change static audit: PASS`. It checked the changed
Python and POSIX shell sources, ShellCheck diagnostics, rendered preseed
commands, theme markers, structured data, AppArmor structure, payload/source
member equality, and `git diff --check`. Direct `/bin/sh -n` parsing also
passed for the changed installer, late, first-boot, cleanup, and CUDA wrapper
scripts.

A dated metadata spot check also matched the source contracts: NVIDIA's
Debian 12 `Packages.gz` contains all 68 selected CUDA package names. The CUDA
hook stages the repository from the selected CUDA class, performs one scoped
metadata refresh, and returns to the normal installer package flow; it does not
run a duplicate package-shape, candidate, origin, or receipt scan. The NVIDIA
legacy hook performs only target setup and DKMS compatibility preparation before
pkgsel.

The reported early `base-network-apt` status 127 was traced to the selected
CUDA path. `installer_cuda_stage_target_key` called `capture_in_target`
solely to inspect a configured repository-key identity; that helper was not
available in the bootstrap-base child. The identity inspection and its
bootstrap support-loader dependency are removed. CUDA key staging ends after
the fixed URL fetch and file-integrity/path checks, so the selected branch no
longer invokes `capture_in_target` before the first target APT update.

The later apparent freeze was a second, unlogged 68-package receipt capture
immediately after the visible CUDA package preflight. The duplicate
`apt-cache policy/show` pass, the late CUDA receipt verifier, the first-boot
CUDA receipt scan, the NVIDIA package candidate/origin preflight, and the late
NVIDIA receipt verifier are removed. The hooks now stage the selected CUDA
class's repository and leave package availability and resolution to APT. The
corrected sources are embedded in both Forky and Trixie payloads.

The current `91cuda-legacy-apt.sh` failure at the reported line was a stale
fragment owner: the hook and late helper still fetched `nvidia-legacy.cfg` even
after that class had been restored to driver-only XanMod behavior. Both helpers
now read `cuda-legacy.cfg`; the resolver suppresses that class's repository
answers from generic apt-setup output because the dedicated CUDA source stage
owns them. This keeps the installer source and package plan on one exact
Debian 12 archive without reintroducing a fingerprint or package preflight.

The native validation boundary was exercised only as an isolation preflight.
The configured Podman client could not start because its host-side `devops`
identity is unavailable, so no container fallback was attempted. Private
mmdebstrap roots under `.build/validation/isolated-check-20261121-*` were
retained for forensics: user-unshare stopped on the host's missing subuid
allocation, fakeroot stopped because fakechroot is unavailable, and
chrootless stopped when dpkg could not apply ownership and a target helper
required root. No host service, package database, device, socket, or manager
was used as a fallback.

No Git file mode bits changed as part of this remediation (`git diff --summary`
is empty). The new authored remediation scripts are mode 600; target modes are
specified only by installer staging calls (for example, the CUDA wrappers are
published as target mode 0755).

## Acceptance gates still requiring an isolated target

The static result does not establish a fresh install, boot, or runtime
acceptance. Before release, run the reviewed disposable validation flow and
record its fixture/image identity, timeout, output path, and cleanup result.
The remaining gates are:

1. A fresh Forky and Trixie install proving the suite-specific Xwayland
   dependency contract: Trixie resolves Labwc/libxklavier with its native
   dependency packages, while Forky purges public `xwayland` in the late
   desktop stage before the private runtime is activated.
2. Target verification of both CUDA minors, the XanMod 580 package set, DKMS
   builds for every supported kernel ABI, initramfs/module signatures, and the
   `sm_61` compiler/runtime smoke test.
3. Secure Boot/MOK enrollment, cold boot, suspend/resume, external display,
   DRM/KMS, and recovery after an interrupted DKMS or installer stage.
4. Labwc/Waybar/portal startup and restart tests, including ordinary native
   applications, Discord/Zoom private-Xwayland lifecycle, namespace and cgroup
   inspection, direct public-binary denial, socket visibility, and stale-socket
   cleanup after reboot.
5. Physical Quadro P520 evidence for the PCI gate, power/thermal defaults,
   hybrid rendering, CUDA execution, and hardware hotplug behavior.

The audit's remaining policy-level items are still explicit release decisions:
all authored profiles currently leave `CRYPTO_LUKS2_ROOT` and
`CRYPTO_LUKS2_HOME` disabled, the account contract keeps local root login
enabled while denying SSH root login, and d-i NTP remains disabled in favor of
target time synchronization. The broad optional APT inventory, moving vendor
download URLs, duplicated Waybar polling readers, and profile-wide VRR/tearing
defaults require a separate policy or hardware qualification pass; they were
not silently changed while preserving the existing profile and application
interfaces.

Until those checks are recorded, the generated products should be treated as
reviewable candidates rather than production-ready release media.

# curl and LLVM Experimental selection, 2026-11-14

## Failure and changed contract

The supplied `todo/syslog` reaches pkgsel and reports that
`curl:amd64=8.22.0-1` requires exactly `libcurl4t64:amd64=8.22.0-1`, which
APT has not selected. `todo/installer.log` records successful pre-pkgsel
staging and an older generated release,
`721c29e0b0cbc9020e0fdc686eff1a3211e88a6ff9e5a7369044df2957075475`.
The native reproduction below establishes a package-selection failure rather
than an early invocation of curl.

The authored changes retain native-suite requests for both curl packages and
select all binaries from Debian's `llvm-toolchain-snapshot` source at priority
1001 from `o=Debian,a=experimental`. The existing `n=rc-buggy` exclusion also
matches Experimental, whose actual release codename is `rc-buggy`; the source
pin admits LLVM's transitive binaries despite that general exclusion.
The apt.llvm.org exclusion remains in force.

All sixteen LLVM 24 requests in desktop/full, desktop/medium and server/devops
now use the source preference without `/experimental` on individual arguments.
In the reproduced transaction, those argument suffixes recursively changed
the libcurl candidate to Experimental even when native-suite curl and
libcurl requests appeared first. Simply adding `libcurl4t64` or qualifying
both curl packages did not resolve that conflict.

The shared contract was reviewed across Forky and Trixie, desktop and server
preferences, common package fragments, role composition, the compiled class
catalog, the frozen package plan, and the pre-pkgsel APT preference staging
boundary. The curl consumer inventory included Bitwarden, QoreDB, Obsidian,
Tomat, Sleek, Postman, Discord, Tuta, Ledger, ChatGPT/Codex, Zoom and Filen.
No application downloader, runtime path, service or Xwayland policy changed.

## Controlled native solver evidence

The final comparison ran native APT inside a disposable QEMU guest, with an
initramfs assembled from public image/package data. The guest had no network,
host filesystem sharing, host mounts, host sockets, credentials, devices or
KVM access. Its writable filesystem was private guest RAM. Package operations
were `apt-get -s`; no package installation or maintainer script ran.

Identities:

- Source base: `ba9922b4dcb8f3f34029ca4715757203474bae71`, plus the changes
  recorded here. The regenerated payload release is
  `907fd551abca21b1e8b6bb8686a529c7ded054a1e57839d414725389935f35be`.
- Official `docker.io/library/debian:forky-slim` image manifest:
  `sha256:27b88700aef98dd3dd0b32538f8e5d662a88237ec8fbf969254c8d3c93dfdab1`.
- Rootfs layer SHA-256:
  `11077c1fccb63fa5dfb8a9b32cff13f9da256c63c1659634c3b47cbf981edd4d`.
- Debian Trixie netboot kernel: `6.12.107+deb13-amd64`; SHA-256:
  `2b2358b37674d2505350528875bb17afae2a36522a9e8a9417eaca65a7da0e08`.
- QEMU: `11.1.2`, Debian `1:11.1.2+ds-3`, using TCG.
- Native APT and libapt-pkg7.0: `3.3.7`. Public Debian package data was
  overlaid without executing maintainer scripts. Their respective .deb hashes
  are `8f6ad63d746631c750273f942ddf57e73cfa7f2aaa6d2d206413992435e1efb4`
  and `897a65071e15e0dc2596d1d5a61ff670e4c3db38d23479ae9d8d9359dbcaabfe`.
- Fixture builder SHA-256:
  `044c8e7b74b5dbce33f8aa5cb52ce52cd90cc02aaa796b29224f411517204dfa`.
- Final initramfs SHA-256:
  `7fc83b556b925a231a491a866674ed5916a7cc614711bd5ba544030818db2730`.
- Captured metadata identity file SHA-256:
  `9d6ffa5a3d670e49a7188d63c5ae0d1352eb7733d9c2201a517b824b05928180`.
- Serial result SHA-256:
  `61a697aea04df442a33778f2f3f276eff1839f1ac65845c4c1453b21e90c0535`.

Public repository metadata was captured over HTTPS; Package indexes were
compared with hashes in the fetched Release data. This fixture did not
perform a separate cryptographic Release signature verification. It is
solver evidence against captured metadata, not a publication or repository
authentication acceptance test.

The recorded invocation, with `fixture_dir` naming the private run directory:

```sh
env -i PATH=/usr/bin:/bin HOME="$fixture_dir" TMPDIR="$fixture_dir" \
  timeout --signal=TERM --kill-after=5s 320s /usr/bin/qemu-system-x86_64 \
  -no-user-config -nodefaults -machine pc -accel tcg -cpu max -m 2048 -smp 2 \
  -display none -monitor none -serial "file:$fixture_dir/serial-apt337.log" \
  -kernel "$fixture_dir/linux" -initrd "$fixture_dir/initrd-apt337.cpio.gz" \
  -append 'console=ttyS0 panic=1 quiet rdinit=/init' -nic none -no-reboot
```

Inside the guest, `apt-cache policy` had a 90-second timeout and each
`apt-get -q -s install` invocation had a 45-second timeout. Every case used
the same captured repository indexes and all sixteen requested LLVM 24
packages. The fixture changed only the suite preference and the argument
selection described below.

| Case | Result |
| --- | --- |
| Existing incomplete LLVM preferences and individual `/experimental` requests | APT exit 100 |
| Complete source pin, native curl requests first, individual `/experimental` requests retained | APT exit 100; libcurl retargeted to `8.23.0-2+exp1`, conflicting with curl `8.22.0-1` and requiring unavailable `libssl4` |
| Complete source pin, native curl requests first, plain LLVM 24 names | APT exit 0 |
| Complete source pin, individual `/experimental` requests first, native curl requests last | APT exit 0; diagnostic confirmation that argument ordering affected the old selection mechanism |

In the passing plain-name case, both curl packages were selected at
`8.22.0-1` from Debian testing/Forky. Every requested LLVM 24 package below,
plus `libllvm24`, `libclang-cpp24` and `libclang1-24`, was selected at
`1:24~++20261025103442+7e3c57157096-1~exp1` from **Debian Experimental**:

```text
clang-24 clang-format-24 clang-tidy-24 clang-tools-24 clangd-24
libclang-24-dev libclang-rt-24-dev
llvm-24 llvm-24-dev llvm-24-linker-tools llvm-24-runtime llvm-24-tools
lld-24 lldb-24 liblldb-24 python3-lldb-24
```

The outer QEMU invocation exited 0, the serial stream reached `VM_COMPLETE`,
and the process was reaped. The fixture deliberately exits PID 1 after that
marker; the resulting guest kernel termination is not an installer boot
acceptance result. Guest RAM was discarded on exit. Private input images,
fixture sources and serial results were retained for inspection; there was
no host cleanup or host package/service operation.

## Generated products and limits

`timeout --signal=TERM --kill-after=5s 120s make build` completed successfully
and serialized 2351 payload members. Both suites contain the same payload
and manifest, with SHA-256 values:

| Product | SHA-256 |
| --- | --- |
| Shared payload.tar.gz | `1aa6fd7e8669641db7cab1fb630fa13c9c379d14d20671f31e7cee26a4811285` |
| Shared payload.manifest | `8380dae3ad168b042d24191459cfd054396a922650b1c66e9553db36fdf1c999` |
| Forky preseed.cfg | `2ba2db973a6040c09b659299fa66884ef865fedbfac926a12da3ca3fc4a456f1` |
| Trixie preseed.cfg | `47d3b8a73086d0f724251cee319672f9fadb7421ed87964ee47e8adac44dec49` |
| Shared receipt.json | `0891cecbda542a5233234a71f8ce7ff8b27323b19cc6bb7d09c1303e34261777` |

This proves the changed Forky curl/LLVM solver contract against the captured
metadata. It does not prove a complete 696-package target transaction, an
actual installation, a reboot, firstboot, application launches, or native
Trixie compatibility. Initial attempts to solve the full plan were incomplete:
four vendor metadata endpoints returned HTTP 403, and some requested vendor
packages were absent from the captured indexes. No alternate retrieval path
was used to bypass those responses. The final focused passing cases must not
be represented as a passing full-plan install.

Trixie source preferences and all six role-package sets were inspected as
data; no Trixie native installation was run. No fixture installed packages,
contacted the development host's package manager or changed host state.

The required completion command,
`timeout --signal=TERM --kill-after=5s 180s python3 -B tools/post_change_check.py`,
passed for all 22 changed files, including 2351 payload members and 22 role
combination plans. `git diff --check` passed. A separate data-only archive
comparison confirmed that all twelve changed authored payload inputs match
their archived bytes and that both suites' payloads and manifests are
byte-identical. The serialized source fingerprint is
`73151ab68663cca06f4d2646b2ec3b2e10c66220a173100f238dceac3f72e8b9`.

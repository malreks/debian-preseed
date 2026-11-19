# CUDA source retirement before finish-install APT update

The temporary Debian 12 NVIDIA/CUDA archive is retired after pkgsel and again
between stock `07preseed` and `10apt-cdrom-setup`. The later source normalizer
uses the same retirement helper and cannot recreate this archive.

The previous late cleanup deliberately published a persistent signed source;
its selection gate also skipped legacy-driver-only installations. The existing
finish normalizer ran as `94zz-20-normalize-apt`, after the stock hook's APT update.

## Source identity and changed owners

- Base commit: `a8b60a33a00c364a1c931355710ce8b0a9575b82`.
- Generated release: `bb276d235af53c8ce84a8f567d4cae0f82d41fffcea89dd192b2c84740d186c3`.
- Runtime source fingerprint: `60ad2f3cade45f75a481da262a761dc4336a93fd5df1e17027abb1f808bfd695`.
- Changed source/fixture fingerprint: `6bb66dd24be81ee5542d863ac932844ddad4ab11cfc3dc17714ba1e8b31d625b`, SHA-256 of canonical
  compact JSON for the `authored_sha256` mapping in `evidence.json`.
- Both suite payloads contain 2,434 members; their payload and manifest bytes agree.
- Build receipts retain the generation-only runtime acceptance value.
  This separate record does not establish full installation acceptance.

- `d-i/debian/hooks/installer/d-i/early.sh`
- `d-i/debian/hooks/installer/finish-install.d/09-cuda-legacy-cleanup`
- `d-i/debian/hooks/installer/finish-install.d/95-normalize-apt`
- `d-i/debian/scripts/common/modules/context-target.sh`
- `d-i/debian/scripts/late/cuda-legacy.sh`
- `d-i/debian/scripts/late/storage-maintenance.sh`
- `d-i/debian/tests/fixtures/contracts/cuda-finish.sh`
- `d-i/debian/tests/test_cuda_legacy_apt.py`
- `d-i/debian/tests/test_installer_hardening.py`
- `d-i/debian/tests/test_managed_external_software.py`

The validation report itself is the additional authored documentation path.

## Shared-contract review

Inspected the shared URL/key policy, canonical APT paths, both suites' legacy
NVIDIA and CUDA class answers, first-update adapter/network publisher,
apt-setup generator, pre-pkgsel publisher, scoped refresh, general-refresh
suspension/restoration, late dispatch, both Btrfs/F2FS handoffs, finish guard,
early hook publication and late normalization.
The referenced historical debian-preseed-de-audit.md file is absent from this
checkout; this review used the current implementation and its source contracts.

The class-owner inventory contains 90 APT repository answers. The two Debian 12
owners are the suites' `optional/nvidia-legacy.cfg` files; the two Debian 13 CUDA
owners remain separate. Exact legacy-archive matching preserves other archives
and selected package lists. No downloader, managed-application constructor,
vendor servicing API, AppArmor or desktop launch contract changed.

Canonical sources, sourceparts and source backups use one retirement helper.
Deb822 cases cover multiple stanzas, mixed URIs, continuation comments, CRLF,
whitespace separators and extension-sensitive filenames. Only the matching URI
is removed from a mixed stanza. Modes are preserved. Unsafe symlinks/hardlinks
and write failures return errors; failed temporary-file cleanup retains private
evidence. Scoped public key files may remain; this operation retires sources.

The executable 09 hook loads cached common/bootstrap policy and validated host
data. The existing finish guard inventories it automatically. Its error path
retains the cleanup status and stops successful handoff to the stock update.

## Executed validation

- `make build` completed pure serialization for both suites, release above.
- `python3 -B tools/post_change_check.py` passed on code/generated products.
  The final audit including this report is captured as `post-change-check-final.log`.
- `git diff --check` passed on code/generated products; the final report audit
  is captured separately.
- **120/120 native contract cases passed** in the final disposable guest:
  15 cases across Dash/BusyBox ash, mawk/BusyBox awk, and Forky/Trixie policy values.
- Debian apt-setup **1:0.198**'s actual `10apt-cdrom-setup` script ran in the guest.
  APT, chroot transport, debconf and logging entrypoints were fixtures. The old
  cleanup kept the source, causing mock APT to return 100; the new 09 hook
  removed it before the same stock hook called APT.
- The late normalizer ran with mock target normalize/modernize callbacks.
  Its three callbacks observed a CUDA-free source; CD-ROM cleanup also ran.
- Publication failure, filter I/O error, retained-cleanup-evidence, missing policy, unsafe paths,
  repeatability, driver/toolkit/unselected and unrelated-source cases passed
  with their expected statuses.
- The unittest wrapper was syntax checked. The standalone source fixture ran
  directly in the guest; the full unittest suite was not run.

The final guest ran for 237.622 seconds, powered off and was
reaped. Earlier development guests 1–6 caught implementation/fixture defects;
guests 7–8 passed preceding revisions; guest 9 caught a fixture probe issue; guest 10 passed the final source.
All ten QEMU processes were reaped. Captures and input hashes remain private;
no timeout or interrupted cleanup was reported.

## Isolation and fixture identities

The guest used QEMU emulator version 11.1.2 (Debian 1:11.1.2+ds-3), TCG, one CPU, 768 MiB, no NIC or monitor,
no host mounts/devices/sockets, and an explicit QEMU sandbox. Its initramfs was
private and writable within the disposable guest. Host images/logs stayed under
disk-backed `.build/validation/` with explicit TMPDIR/TMP/TEMP. The external
deadline was 300 seconds plus five seconds for termination; the enclosing
deadline was 310 seconds. Exact argv and cleared environment are recorded in
`qemu-command-10.json`.

Runtime: Trixie installer kernel `6.12.107+deb13-amd64`, BusyBox `1.37.0`
(image package `1:1.37.0-6+b9`), Dash `0.5.12-12`, mawk `1.3.4.20250131-1`.
Both suite policy values ran on these identified binaries; no Forky OS boot is
claimed. Base image/package hashes were rechecked during guest serialization.
The HTTPS-fetched Debian apt-setup archive matched its .dsc SHA-256; this run
did not separately verify that source .dsc signature.

- Kernel SHA-256: `2b2358b37674d2505350528875bb17afae2a36522a9e8a9417eaca65a7da0e08`.
- Base initrd SHA-256: `57303d157cffce3fa402301667fbc9b2280aa7372082b081e777375ae49da5f2`.
- Fixture initrd SHA-256: `d2cac6a6e4d802b551a27c5e912b56188f9837bc85652f84278b3caab29867e9`.

A full installation, live vendor APT update, final boot, GPU/DKMS and hardware
behavior remain unverified. Lifecycle supervision beyond this cleanup/stock-hook
path was reviewed as source, not replayed end to end. Host services, package
state, network configuration, devices and security policy were not changed.

The next installation must use this release's matching preseed, payload and
manifest. The serving environment was not changed.

## Generated products

The serializer wrote the twelve authorized flat products. `source.sh` and
`support-matrix.json` stayed byte-identical to the base; eight generated paths changed.

| Product | SHA-256 |
| --- | --- |
| `d-i/forky/payload.tar.gz` | `7f0e9033868b46e967a6f5736bb7908da1484a94a7a8b56aa182a80ef1cefdbc` |
| `d-i/forky/payload.manifest` | `125ca78c76fc22b1fc0c73d8ddae93f39f9be48231be91467feef5ffa1640fcc` |
| `d-i/forky/source.sh` | `93acffbabc0addc077ecd7f7827a2ae5bdb1ec94c5b5dc60283da00dd73dd7fb` |
| `d-i/forky/receipt.json` | `6a88d42ed6e6611b52a091785808991559757776c93668d457f843040f1354eb` |
| `d-i/forky/support-matrix.json` | `d328e8a1b482f4f07a8878786019f27abd57c75550b4cd172ce45f6bf7dbb1ef` |
| `d-i/forky/preseed.cfg` | `617fa9d8f57402eff5769501c674fe480f3c8cc961df863e785c23c4cf6bca5d` |
| `d-i/trixie/payload.tar.gz` | `7f0e9033868b46e967a6f5736bb7908da1484a94a7a8b56aa182a80ef1cefdbc` |
| `d-i/trixie/payload.manifest` | `125ca78c76fc22b1fc0c73d8ddae93f39f9be48231be91467feef5ffa1640fcc` |
| `d-i/trixie/source.sh` | `93acffbabc0addc077ecd7f7827a2ae5bdb1ec94c5b5dc60283da00dd73dd7fb` |
| `d-i/trixie/receipt.json` | `6a88d42ed6e6611b52a091785808991559757776c93668d457f843040f1354eb` |
| `d-i/trixie/support-matrix.json` | `d328e8a1b482f4f07a8878786019f27abd57c75550b4cd172ce45f6bf7dbb1ef` |
| `d-i/trixie/preseed.cfg` | `98add134d6b51fbc62cf3c5f1b80cc14eaac6d97fdca7b09d6e3327d48eb1725` |

Private evidence: `.build/validation/cuda-finish-20261119/evidence.json`.
The same directory retains before-source snapshots, package/image metadata,
build/audit logs, exact QEMU commands, input fingerprints and every serial capture.

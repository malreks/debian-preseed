# Primary-account late-command repair — 2026-11-14

The reported failure was `stage=os.shared`, `profile asset lacks required
field: ACCOUNT_USERNAME`. Early account creation had already succeeded.

The late dispatcher runs each provider in its own shell. The shared foundation
stages role-filtered Perl assets before the desktop storage/account loader.
Its desktop Perl inventory includes
`LabwcNetworkScanAction/Root.pm.tmpl`, which requires the primary username.
A compiled public host profile deliberately contains no private account
identity, so loading that profile cannot satisfy this template.

The shared foundation and system-services providers now call
`installer_load_primary_account` after loading their validated path/profile
data and before staging assets. The server foundation uses that same loader
for its operator identity. It resolves only the username and
`${DIR_HOME}/${ACCOUNT_USERNAME}`; it does not need account passwords.
Inherited account values are replaced by validated installer input.

Both installer and storage-runtime readers recognize `primary_username`
and the historical `primary_user` as one command-line input. The first
occurrence of either spelling wins, including an explicit empty parameter.
When neither is present, both map to `PRESEED_PRIMARY_USERNAME` through the
existing restricted credential reader. Invalid, empty, missing and reserved
usernames cannot become target asset values. The transport registry also
recognizes the new spelling. No debconf, profile or inherited-account fallback
was added.

The target-asset publisher records the asset as its operation context and
includes the source asset in missing-field diagnostics. It continues to use
the existing scalar/path renderer and validates before replacing the target.

## Source and consumer review

Base revision: `53aa6742e9e1e84d6f2f4116b3eb2c7743cb4cf0`, with the working-tree
changes recorded by this repair.

Review traced the transport registry, credential mapping, both command-line
readers, early account answers, Btrfs/F2FS effective account snapshots, late
dispatch and account loading, the shared renderer, shared OS providers and
server foundation. Desktop software and user-configuration owners resolve
their account through the existing runtime/late-account boundary. Their
affected sibling set includes Bitwarden, QoreDB, Obsidian, Tomat, Sleek,
Postman, Discord, Tuta, Ledger, ChatGPT/Codex, Zoom and Filen. Direct identity
readers also cover Codex/DevOps, shared networking, virtualization, firmware,
server hardware/boot, and the Whisper/Llama, CrowdSec and Tailscale/Syncthing
addon paths.

No application constructor, download policy, service identity, runtime
authorization, desktop launch or private Zoom/Discord Xwayland policy changed.
Native application and full installation behavior remain deferred.

Final serialized source fingerprint:
`0270c240cccb69500e85b35b0b1344446b2ddecfe7203c990e3e896d59c19bd3`.

Final release identity:
`da833327a41cb8bde4ddece40fb6017b52b35f695d6ef64a80322e5f16ff1191`.

## Disposable native fixture

A diskless QEMU guest booted the public Debian Trixie amd64 installer kernel
and initrd from the
[Debian installer image directory](https://deb.debian.org/debian/dists/trixie/main/installer-amd64/current/images/netboot/debian-installer/amd64/).
Downloads matched the image publisher's
[SHA256SUMS](https://deb.debian.org/debian/dists/trixie/main/installer-amd64/current/images/SHA256SUMS).
The detached checksum signature was not checked; these hashes record byte
consistency with the retrieved public metadata.

| Fixture/tool | Observed identity |
| --- | --- |
| Kernel image SHA-256 | `2b2358b37674d2505350528875bb17afae2a36522a9e8a9417eaca65a7da0e08` |
| Vendor initrd SHA-256 | `57303d157cffce3fa402301667fbc9b2280aa7372082b081e777375ae49da5f2` |
| Guest kernel | `6.12.107+deb13-amd64` |
| Guest BusyBox | `1:1.37.0-6+b9` |
| QEMU | `11.1.2 (Debian 1:11.1.2+ds-3)` |
| Staged initrd SHA-256 | `984d35f22badde3e3705b5ff653ff0c1e81c1f88f13606bd67d9f609658bd5a6` |
| Regression source SHA-256 | `b8d1c7faf6adacc17c4c73329a99fbcbacc67ee10045fa11cbfcfbe3c8911865` |
| Guest init SHA-256 | `ea35ec960588d34030f5782ca003f70fb8604a27b57ea1066c28d6e7548e65d3` |
| Guest probe SHA-256 | `5680d7fb7a118e3f5009685a32a1a0c26afbb34d7a3a04285115ec60425c7aa1` |
| Guest helper SHA-256 | `68605ee2bf2495c3d48e322719668c7cbecee99b5a2ad8ab756a4d733db7d311` |
| Console capture SHA-256 | `27ad83a00acb55432b25f224618c65515d78bfd9e028b96ee7e6a71a886018aa` |

The private overlay contained only the selected source snapshots, literal
fixture programs and synthetic credential values. No host root, data,
configuration, credentials, devices, service sockets or desktop resources
were exposed. There was no guest disk, NIC, host mount, host network namespace
or device passthrough. QEMU used TCG, one vCPU, 512 MiB, no default devices
or user configuration, a cleared process environment and a private HOME.
Guest state and credential-reader temporary files were confined to the
disposable initramfs. There was no host-execution fallback.

The invocation below preserves the executed argument order. `${FIXTURE_DIR}`
denotes the privately created directory, and `${GUEST_INIT}` denotes the
init entry owned by that overlay:

```sh
/usr/bin/timeout --signal=TERM --kill-after=5s 120s \
  /usr/bin/qemu-system-x86_64 -no-user-config -nodefaults \
  -machine pc,accel=tcg -m 512 -smp 1 \
  -display none -monitor none -serial stdio -nic none -no-reboot \
  -sandbox on,obsolete=deny,elevateprivileges=deny,spawn=deny,resourcecontrol=deny \
  -kernel "${FIXTURE_DIR}/linux" -initrd "${FIXTURE_DIR}/probe-initrd.gz" \
  -append "console=ttyS0 rdinit=${GUEST_INIT} panic=1 loglevel=3"
```

A Python standard-library supervisor supplied an empty stdin, captured stdout
and stderr to the private serial log, and waited for the emulator with an
outer 130-second timeout. The emulator's hard budget was 120 seconds with a
separate 5-second forced-termination budget. The successful run took
12.588 seconds and returned QEMU status 0 after guest poweroff.

The guarded Python regression module was parsed as data on the host. Its
`SHELL_SETUP` and `FOUNDATION_SETUP` string constants were staged without
importing that module. The guest ran these shell paths and the focused cases;
the repository unittest suite was not executed. Guest helper programs also
passed `dash -n` as a separate source-only check before boot.

The fixture uses real credential parsing, command-line readers, account
resolution, scalar/path rendering, and target-file publication. Transport is a
private file-copy stub. Bootstrap, class metadata, synthetic block identity
and the target ancestry authority are bounded fixture seams. The shared-stage
replay stops immediately after its first real account-dependent Perl asset.
It does not execute Perl, services, package tooling or later storage actions.

## Captured result and limits

All 49 guest cases passed. Coverage includes both readers and both username
spellings; environment fallback; first-occurrence, empty and bare-parameter
precedence; inherited identity replacement; missing, duplicate, invalid and
symlinked inputs; identity-only operation without passwords; early/late
identity agreement; exact rendering; and preservation of prior output on
failure.

The baseline case replayed the unmodified base revision's shared-stage source
with the same private dependencies and no inherited identity. It reproduced
the missing-`ACCOUNT_USERNAME` error. The fixed stage rendered the same Perl
asset successfully from either supported input channel.

```text
GUEST_KERNEL=6.12.107+deb13-amd64
BusyBox v1.37.0 (Debian 1:1.37.0-6+b9) multi-call binary.
CASE PASS shared.baseline-reproduces
CASE PASS shared.file
CASE PASS shared.cmdline
PRIMARY_ACCOUNT_CASES_PASSED=49
PRIMARY_ACCOUNT_PROBE_STATUS=0
[   11.428568] reboot: Power down
```

Two preliminary guest attempts stopped at fixture issues: an incorrect
expectation about the existing credential-input permission contract, and a
missing private `DIR_RUN` setting. Those fixture assumptions were corrected.
The final run completed all cases; no native run was interrupted or timed out.

The guest powered off, QEMU was reaped, and the exact private fixture directory
was removed under a bounded cleanup command. Directory absence was verified.
No live fixture resources or recovery material remain.

The whole installer, target package solving, first boot, enforcing AppArmor,
services, GUI, real hardware and server enrollment were not tested. This
focused probe establishes account-selection and asset-publication behavior,
not completion of a native installation or acceptance of either suite's
support matrix.

## Source snapshot and generated products

The native source snapshot map, serialized as sorted compact JSON, has
SHA-256 `5f2eb70c35695e854eacf2523a7762c5d3f9e3c145ff2fa40a92827f06d5a1db`.

| Source member | Native snapshot SHA-256 |
| --- | --- |
| `hooks/target/usr/local/lib/desktop/perl5/site_perl/labwc-network-scan-action/LabwcNetworkScanAction/Root.pm.tmpl` | `8a18d8ff6c013bf4852b905d9470dfb610f3cfc16b4a7c54a586db636968b038` |
| `scripts/common/credential-data.awk` | `5bf41f7ba0a2da9539ef404219bca4d9ebe50be8317ea033bc04dba9c4b32208` |
| `scripts/common/credentials.sh` | `f6201722a4d8a4e2aced2ef248d27e240b907205dece7ff6819bd6ab38fac5d7` |
| `scripts/common/modules/credentials-probes.sh` | `09f8a5225613a3ed7dc653aa25f9378e0ad150627c0d25c9d80e371bf7dee1dd` |
| `scripts/common/modules/files-logging.sh` | `05181d8cbee9dbe709831bf9a7a093db3910cb7969c169e27608f9e3acda9f87` |
| `scripts/common/modules/profiles.sh` | `9969333be6acb15d31ce144ee0ca7dfd7ce305cb1ee45392397a692bfc6cb369` |
| `scripts/common/modules/target-publication.sh` | `1944dd4ef9d66646e5c9f7325d5f35a30916a3e0bb48ecfcfa28ee9662887d94` |
| `scripts/common/system-foundation.sh` | `f66d177d27aa4510081a2e8cccfc8312215732bf02206a1bb914668b88a9b924` |
| `scripts/runtime/account.sh` | `ac30857878210bf2b4a0698575967811add369557a0ce178cd5ca19f7e70281f` |
| `scripts/runtime/modules/base.sh` | `7d8e7ec06701ceffefa92173b3f7eafdb7065cd307ceecfe5033212b96424719` |

The baseline shared-stage SHA-256 was
`4cc5ca8ed8ef1ab53948dc4c519f752f0f2293c67d786e4ddd1b650aa19c6c1d`.

The generation-only command
`timeout --signal=TERM --kill-after=5s 120s make PYTHON=python3 build`
completed successfully. Both suites contain 2,351 payload members. The suite
support matrices were serialized and stayed byte-identical to their prior
versions. Generated source copies, payloads, manifests, receipts and preseeds
carry the current source pins.

| Product | SHA-256 |
| --- | --- |
| Shared payload, both suites | `cfc1c82de43bf2dca4a24afedfd3408c0e8c7ae82abc14ca0dec6beef08f06ba` |
| Shared manifest, both suites | `97d90dd69b06ffc0083b8588c8abb2fad069abb38b888948d20c4fcedab97338` |
| Shared transport, both suites | `43c1ae691c6d6c095b1f43538c93bb89b0ed2a24656eff6bd1f63ede0c6f3f33` |
| Shared receipt, both suites | `9cd1fa454ece692e8a3f1028a56542ea811fc08e973c8fe785389b0c44e6eed6` |
| Forky preseed | `0ccc9eb6c78e84be1040fce146701d367b831d7bf539b8880e180098cd8619d2` |
| Trixie preseed | `9e54b0551ff59d2b43b449512e7460e40d41e04aa394290c4b0782ef99da5660` |

The first pre-regeneration static audit stopped at expected stale-product
equality. The completion gate for the rebuilt checkout is
`python3 -B tools/post_change_check.py`, together with `git diff --check`.
Publication to the installer-serving host is a separate operator action.


# Installer stage and runtime-ruleset review, 2026-11-19

The supplied installation stopped at `94zz-99-validate-target`, after its
package/boot checks and before readiness publication. The ownership scanner
rejected twelve occurrences of four legitimate runtime fields in
`/etc/app-veth.nft`. All six pre-pkgsel stages and all nineteen selected late
stages have matching start and completion records. This is one blocking
ownership-contract defect, with repeated diagnostics for the same four fields.

## Captured input and source identity

- Starting checkout: `cfeac695b33636b2ec3a6583c0df4d01da9c4129`, clean worktree.
- Supplied run: Forky, desktop/full, desktop/btrfs-de-p15s, amd64, with the
  explicitly selected legacy NVIDIA and CUDA classes.
- Supplied release:
  `76bcd5ae24ba5e131f24b41c586f7f794e04567112e23e612feb0da021d2d780`.
  This matches the checkout's original receipts; the failure is not attributed
  to stale media or an older payload.
- `todo/syslog`: 18,595 physical lines, 1,750,540 bytes, SHA-256
  `757184bb6719ff208528e1aba0ddad065af7dd03cb10ef26e06c1f8fdac3e2ab`.
- `todo/installer.log`: 5,811 physical lines, 750,305 bytes, SHA-256
  `b5b6fe210da9058b1026d006d3610811e95090789e0a4dea3e053be200ccab8f`.
- Log references use physical newline numbers. Embedded carriage returns must
  not be counted as additional source lines. Captured diagnostic inventories
  omit generated preseed commands and kernel command lines and redact secrets,
  URL paths and network/account identifiers.

## Stage evidence from the supplied installation

The line numbers in this table refer to `todo/installer.log`. Completion means
the installation recorded that stage's return successfully; it does not prove
post-reboot activation, device behavior or application launch.

| Stage | Start line | Completion line |
| --- | ---: | ---: |
| installer.firmware | 365 | 367 |
| installer.os-prober | 368 | 370 |
| installer.namespace | 371 | 374 |
| installer.dkms | 375 | 389 |
| installer.cuda-legacy | 390 | 466 |
| installer.nvidia-legacy | 467 | 480 |
| os.shared | 491 | 522 |
| os.crowdsec | 523 | 599 |
| os.kernel | 600 | 610 |
| desktop.storage | 611 | 2117 |
| desktop.software | 2118 | 2729 |
| desktop.tailscale | 2730 | 2735 |
| desktop.whisper | 2736 | 2753 |
| os.crypto | 2754 | 2755 |
| os.uplinks | 2756 | 2765 |
| os.sharing | 2766 | 2937 |
| os.services | 2938 | 3027 |
| os.codex | 3028 | 3054 |
| desktop.devops | 3055 | 3810 |
| os.firmware | 3811 | 3827 |
| desktop.ch341a | 3828 | 3834 |
| os.timeshift | 3835 | 3863 |
| os.virtualization | 3864 | 3882 |
| desktop.virtualization | 3883 | 3893 |
| desktop.session | 3894 | 5789 |

Late dispatch completed at line 5795. Final normalization restored the real
`unshare` and initramfs executables, normalized the configured backing
directories and account files, and completed at line 5804. Final APT source
normalization completed at line 5811. In `todo/syslog`, stock
`10apt-cdrom-setup` completed its update before the subsequent finish hooks,
`94zz-10-normalize-finish` returned, and `94zz-20-normalize-apt` returned before
`94zz-99-validate-target` began at line 18574.
The early CUDA cleanup starts at `syslog:18482`, before the stock APT hook at
18484; the next stock hook starts at 18524. There are zero Debian 12 CUDA URL
references after this cleanup in the supplied syslog.

The twelve fatal marker records are at `todo/syslog:18575` through line 18586.
The final scanner report and propagated terminal failure follow at lines
18587 through 18593. The validator's ordered source places the dpkg audit,
kernel/initrd/EFI signature checks, default-target lookup, desktop-unit checks
and owned-file ancestry checks before this scanner invocation. Reaching this
specific scan is evidence that those preceding checks returned successfully
in the supplied run. It is not evidence of a subsequent successful reboot.

## Root cause and correction

`scripts/late/security.sh::configure_target_app_veth` installs a runtime
ruleset template. The installer renders
`__INSTALLER_PROXY3_PORTS_ALLOW_WEB_BROWSER__` using the validated proxy map.
The installed `app-veth` program later reads the administrator's configuration
through `app_veth_policy.read_configuration`, derives the reserved interface
names, and resolves these fields in `apply_network_identity` before any nft
invocation:

- `__APP_INTERFACES__`;
- `__DNS_ADDRESS__`;
- `__DNS_HOST_ADDRESS__`;
- `__DNS_HOST_PORT__`.

The registry had declared all four as installer scalars that must disappear,
but had no literal allowance for their installed runtime template. Its only
existing allowance was the exact `__APP_INTERFACES__` string in the program.
The final scanner therefore rejected a configuration the runtime consumer had
already validated earlier in the installation.

The correction uses the existing source-scoped `literal_members` interface.
Only the four exact fields in `hooks/target/etc/app-veth.nft.tmpl` receive the
required declarations; the program's existing interface-field literal remains
declared. Their owner now names the actual `app-veth::apply_network_identity`
consumer and their syntax identifies its validated values. Registry validation
requires the complete exact declaration and owner, preventing a refresh or
partial metadata edit from silently dropping it again. The JSON registry and
runtime TSV projection agree. The scanner, firewall program, network policy,
installer path contract and runtime substitution algorithm are unchanged.

Unknown fields, fields in an unrelated source and all unresolved installer
markers remain errors. The final readiness gate is retained.

## Shared-contract inventory

The audit traced the registry refresh/validation/projection, build exclusion of
the developer JSON, authenticated payload/manifest capture, base-stage private
registry/scanner staging, ownership journal publication, late proxy rendering,
runtime JSON parsing, runtime ruleset expansion, final scanner, readiness
publication and guarded unmount/reboot handoff. The refresh checks all 3,634
production token declarations and their complete source-member sets, including
the 734 canonical path-map keys. There are 192 non-installer scalar names;
only the four runtime-ruleset entries change. The other 3,630 registry entries
are byte-equivalent as parsed data.

The shared app-veth identity map contains these 24 application policies:
Bitwarden, ChatGPT, Chromium, Code, Codex, Discord, Filen, FreeRDP, Ledger Live,
Liferea, Microsoft Edge, Mullvad Browser, Obsidian, Postman, qBittorrent,
qBittorrent Privacy, QoreDB, Spotify, Telegram Desktop, Tuta, Vivaldi, Zoom,
Podman and Tor Browser. Role authorization remains in the existing producer.
Tomat and Sleek were also included in the shared registry/source review;
neither uses this runtime ruleset as an app-veth policy. No managed application's
URL, installer, constructor, launch policy, AppArmor profile or private
Xwayland implementation changes.

## Other diagnostics and their disposition

| Diagnostic | Evidence and disposition |
| --- | --- |
| Initial Intel Wi-Fi firmware load failure | `syslog:1139` identifies media firmware discovery; line 1140 installs `firmware-iwlwifi`, line 1154 reports the required firmware loaded, and line 1164 reports no missing firmware in loaded modules. The optional debug blob is explicitly ignored. No global firmware workaround is added. |
| Missing installer-package candidates / CD-ROM index variants | The installer continues through hardware detection, partitioning and base installation. Missing optional archive variants are not the final failure. |
| FAT codepage conversion messages | Formatting and the subsequent base installation complete. No filesystem or partitioning change is inferred from these messages alone. |
| Early debootstrap dependency and provisional dpkg status warnings | These occur while the initial minimal root is being assembled. The later final dpkg audit precedes the reported marker failure and returned successfully. |
| Debconf fd 3 / Passthrough initialization | `syslog:2944` through 2947 and 3409 through 3411 explicitly show fallback to `Noninteractive` followed by package configuration. No frontend authority or descriptor handling is changed to hide it. |
| NVIDIA archive SHA-1 binding rejection | A real upstream authentication diagnostic at `syslog:2711`, 2761 and during the selected legacy refresh. The existing explicitly selected installer-only compatibility path permits this archive; it is removed before stock finish APT and remains absent from the final policy. No additional authentication bypass or global crypto-policy weakening is introduced. Vendor authentication of this legacy archive remains a limitation of that existing compatibility path. |
| x-cursor-theme alternative missing | `syslog:14713` is immediately followed by successful alternative registration at 14714. This is an initial-registration probe, not an aborted package configuration. |
| 3proxy update-rc.d / missing chkconfig | The vendor postinst reports these at `syslog:15376` and 15377, then installs its systemd unit and reports `3proxy installed` at 15380. The desktop stage subsequently disables/masks the host daemon; managed namespace usage remains unchanged. No Red Hat compatibility package or vendor-script rewrite is added. |
| D-Bus init script missing | `syslog:17380` occurs in polkit's package setup, which continues. The selected managed dbus-broker arrangement intentionally excludes the dbus-daemon package. The later target audit completes. |
| EFI variables warning | The subsequent operations complete MokManager staging, shim fallback repair, signed-kernel/initrd preparation and the firmware-shim check. The final boot-file audit precedes the failing scan. Actual firmware boot is still unverified. |
| Pre-existing account home ownership warning | The layout creates the mount point before user creation. Final normalization explicitly reports account-owned home/file normalization at `installer.log:5801`; no blanket recursive ownership repair is introduced. |
| policy-rc.d / chroot service operations skipped | Target service activation is deferred during installation. No development-host service is contacted. |
| AppArmor optional profiles / kernel activation deferred | Optional absent programs are reported individually; staged hardware policy validation completes. No host policy load and no broad policy relaxation is performed. |
| CrowdSec / Tailscale / incomplete optional calendar inputs | Deferred enrollment and pending optional input are expected states, not installer failure. |
| GPG local trust warning / unversioned application metadata baseline | Signature verification and local trust are distinct. An unversioned URL without a digest does not establish remote artifact identity; the existing messages correctly retain that limitation. |
| Glycin sandbox / logrotate debug / missing optional logs / setuptools skipped | These appear during offline image metadata preparation, deliberate logrotate dry validation and private Python environment setup. Their containing stages complete. No live desktop sandbox or rotation behavior is inferred from these offline messages. |
| Installer USB FAT volume not cleanly unmounted | Appears at `syslog:18595`, after the terminal validation failure. It concerns the removable installer volume, not an earlier target-install abort. No host or device repair is attempted. |

## Controlled native validation

Evidence directory:
`.build/validation/installer-stage-review-20261119-2233/` on verified Btrfs.
All host scratch and subprocess temporary variables point to its private
`tmp/` directory. No repository tests or target helpers run on the development
host. The image preparation reads package/archive/source data only.

The disposable guest uses TCG, one virtual CPU, 768 MiB RAM, no NIC, no shared
directories, no host devices or sockets, and a private initramfs. A hard outer
timeout includes a separate five-second forced-termination budget. Guest
`/proc`, `/dev`, target tmpfs mounts and account fixtures belong entirely to
this identified guest. The finish fixture refuses an already mounted target
and unmounts only its own `/target` mount on exit.

- Identified Debian Installer kernel: `6.12.107+deb13-amd64`, SHA-256
  `2b2358b37674d2505350528875bb17afae2a36522a9e8a9417eaca65a7da0e08`.
- Base initrd SHA-256:
  `57303d157cffce3fa402301667fbc9b2280aa7372082b081e777375ae49da5f2`.
- Public fixture packages: Dash `0.5.12-12`, mawk `1.3.4.20250131-1`,
  Python `3.13.5-2+deb13u5`, Perl `5.40.1-6+deb13u1`, plus the base image's
  BusyBox. Package hashes are checked during image serialization and recorded
  in `fixture-packages.json`. No package maintainer script runs on the host.
- Forky and Trixie selections below refer to their actual compiled policies
  in this Trixie fixture image. They are not two complete installed target OSes.
  The supplied Forky run itself records Python `3.14.10-1`, Perl `5.44.0-3`,
  systemd `262.2-1`, dpkg `1.23.11` and nftables `1.1.7-3`; its earlier real
  app-veth configuration check completes before the final ownership failure.

`app-veth-placeholders.py` executes the actual shared Perl renderer, identity
and proxy map producers, runtime configuration parser, runtime ruleset
consumer and both mawk/BusyBox ownership scanners. Configuration checks reject
any attempted administrative command through an explicit failure guard; no
kernel firewall or network operation is claimed. The fixture reproduces all
twelve original rejections and covers desktop base/medium/full, both suite
policies, Dash/BusyBox shell producers, both AWK scanners, exact-source
allowances, unknown fields and unresolved installer fields. Its recorded
result is **41 checks passed**.

The extended `finish-environment.sh` runs the complete four project finish
hooks in sequence with real bootstrap, restricted host-policy loading,
normalization, ownership journal/scanner and readiness files. It now includes
the real rendered app-veth ruleset. Target APT operations and the chroot
boot/package audit remain explicit stubs; they are not native APT or boot
acceptance. Original-registry and unresolved-installer-field cases must fail
without publishing readiness or success. Positive desktop and server cases
must publish readiness while leaving installation success to the later
guarded unmount/reboot handoff.

The accepted guest completed all **six finish-sequence cases**:

| Case | Interpreter / suite policy | Required observed result |
| --- | --- | --- |
| Original registry with actual runtime template | Dash / Forky desktop Btrfs | Actual final validator returns nonzero with twelve marker rejections; no readiness or success |
| Injected unresolved installer path field | Dash / Forky desktop Btrfs | Actual final validator returns nonzero; no readiness or success |
| Corrected registry and runtime template | Dash / Forky desktop Btrfs | Four hooks complete; readiness published; success remains `not_yet` |
| Server without app-veth template | BusyBox / Forky server Btrfs | Four hooks complete; readiness published; success remains `not_yet` |
| Corrected registry and runtime template | BusyBox / Trixie desktop F2FS | Four hooks complete; readiness published; success remains `not_yet` |
| Server without app-veth template | Dash / Trixie server F2FS | Four hooks complete; readiness published; success remains `not_yet` |

Accepted guest attempt 2: QEMU `11.1.2 (Debian 1:11.1.2+ds-3)`, 600-second
deadline plus five-second forced-termination budget, elapsed **564.910
seconds**, QEMU exit 0, `GUEST_RESULT=0`, six case passes and 41 check passes.
Every case's owned target mount is unmounted by its exit trap before the
successful guest shutdown; QEMU is reaped. The final private initrd SHA-256 is
`a511d59a5745ff135b93e48554b87f4092b3c86850bd7dccca429b95804f80e0`.
`qemu-command-2.json` captures exact argv/environment, image identity and tool
version; `serial-2.log`, `qemu-2.log` and `guest-result-2.json` retain results.

Attempt 1 stopped before configuration checks because the fixture's redundant
Dash symlink was self-referential on the image's merged `/usr` layout. That
private guest initialization line was removed; production source was not
changed for it. The failed fixture record and serial log are retained. It
returned `GUEST_RESULT=2` and QEMU was reaped after 9.434 seconds. Neither guest
hit its deadline or required interrupted-cleanup handling.

Source/fixture fingerprint bound to the accepted guest:
`6ca5d76e088b5c4c5699cc141af86dc153bcc21ce63cb92dba72aacabc5a1d6f`.
The evidence recorder checks every staged authored production input against
current source, both final fixture files against their image hashes, all
twelve generated product hashes and both supplied log hashes.

The data-only registry refresh/validation reports 3,634 owned production tokens,
734 canonical map keys and no unowned production fields. The initial changed
file audit after generation passed for all 14 then-changed files, including
2434 payload members, 2258 current-source equality comparisons, 208 frontend
pins, 22 role-combination plans and 13 managed application owners. The final
completion audit, including this report, is captured in
`post-change-check-final.log`; its exit status and the separate `git diff
--check` result are recorded in `evidence.json`.

The relevant recorded commands are:

```text
python3 -I -B tools/validate_placeholder_registry.py --refresh --report .build/validation/installer-stage-review-20261119-2233/placeholder-registry-coverage.json
make build
python3 -I -B .build/validation/installer-stage-review-20261119-2233/prepare_guest.py
STAGE_FIXTURE_ATTEMPT=2 python3 -I -B .build/validation/installer-stage-review-20261119-2233/run_guest.py
python3 -I -B .build/validation/installer-stage-review-20261119-2233/record_evidence.py
python3 -B tools/post_change_check.py
git diff --check
```

All command subprocesses receive absolute private disk-backed `TMPDIR`, `TMP`
and `TEMP` values. Generation and native launch use a cleared, explicitly
constructed environment; the exact QEMU environment is in its command record.

## Generated products

The permitted pure `make build` regenerates both suites from the corrected
runtime TSV. New release:
`25a9a1db6f428c75e2e57387e2765b21c22eca265dc1ed77e8d7d7cab50b173c`.
Runtime source fingerprint:
`70280a8f951c457964e16125ea44a64338b6d29b87e05493f9460f3d8dd88047`.
Both payloads contain 2,434 members and have SHA-256
`82f9d56eb65e98e9db123345f83ba379a44fdb581ad523423143dd29808b991f`.
Both manifests have SHA-256
`f301cdfa0e888d645657a88931153cd859cfbe135c6b34cec0f84bd4389dc4d7`.

Changed generated files are `payload.tar.gz`, `payload.manifest`, `receipt.json`
and `preseed.cfg` under each of `d-i/forky/` and `d-i/trixie/`. The two
`source.sh` files and two `support-matrix.json` files remain byte-identical.
No class, authored APT tree or suite common/fragment input is rewritten. The
generated products are local checkout files; no separate deployment command or
remote push is performed. A new installation must receive the matching new preseed, manifest
and payload generation.

## Acceptance limits

No full unattended installation or reboot is newly completed by this task.
EFI/Secure Boot activation, NVIDIA/CUDA hardware operation, networking, desktop
launches, AppArmor kernel activation and external enrollment remain dependent
on target evidence. The supplied installation establishes the stage returns
and pre-scan checks described above, but ends at final validation and cannot
establish post-reboot health. The unittest suite is not executed on the host;
new scanner test cases are authored, while the separate reviewed guest fixture
provides native contract evidence. Serialization and source checks do not
replace a complete installation acceptance run.

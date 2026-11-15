# Supplied installer logs: Mullvad policy publication and target diagnostics

## Revision and supplied evidence

Source baseline: `95a1c8665a0133a84667ec20f465fbf20d89a758` on `mcr/main`.
This record describes the subsequent uncommitted repair and generated products.
The supplied run used release
`d06a3d6c5ae0f04d622a5e037d1a93be192fef837a04dfd6178cd9d9fc9e4889`.

Both supplied files were read as data, including their complete line inventories;
credentials, command-line secret fields and access-bearing URLs were withheld
from diagnostic excerpts.

| Supplied file | Bytes | Lines | SHA-256 |
| --- | ---: | ---: | --- |
| `todo/syslog` | 1684347 | 17919 | `01c6f14f838a19461dccacdca7bc16a2d798c4b2c3468ff4431842d81240da60` |
| `todo/installer.log` | 137929 | 836 | `8df8fb5cdab4f2baa353cf73d29cbfee82348a7cd471aa0429302109ebe1ddbc` |

The terminal cause is `todo/syslog:17912`: the target has no
`/etc/apparmor.d/mullvad`, the vendor's fixed AppArmor policy interface.
The following lines and `todo/installer.log:823-832` propagate that failure
through `install_target_mullvad_vpn_if_selected`, `desktop.storage`, and late
dispatch. The installer log records `output_lines=0`, although syslog contains
the useful `find` diagnostic. Mullvad VPN was already installed at version
`2026.5` (`todo/installer.log:816-822`).

The previous account failures are not reproduced by this supplied run:
Secure Boot pre-pkgsel completes at installer-log lines 375-376; the complete
pre-pkgsel plan completes at line 456; `os.shared` and `os.crowdsec` complete at
lines 652 and 747. Target kernel image, headers, modules and initrd verification
completes at lines 749-758, selecting `7.3.1-x64v3-xanmod1`. Account group
configuration succeeds at lines 787-791, before the Mullvad failure.

## Owning changes and shared callers

`d-i/debian/scripts/late/mullvad.sh` now stages the packaged AppArmor resource
when the target policy is absent. The resource is vendor package data, not shell
code. Its directory ownership, file ownership/mode/link count and bounded size
are checked before use. An existing policy must match every vendor byte except
the supported header-mode normalization; existing bytes are preserved.

A private adjacent candidate is compiled before publication with an explicit
empty parser configuration, target include tree and packaged ABI 4.0. The parser
uses one job, skips kernel loading and skips caches. The source identity is
rechecked. A missing destination receives complete bytes through `ln -T`, which
refuses a concurrent file, directory or symlink. New policy is root-owned, mode
0644 and has one link after private-candidate removal. File and parent syncs,
identity checks and narrow cleanup complete publication. Uncertain publication
or cleanup returns 125 and retains the private evidence and publisher lock.
Compile/publication failures preserve their cause/status and existing policy.

Both installed-package and late-download branches use this boundary. Both
Btrfs and F2FS families call the same helper. The downstream journal guard and
boot activation assets were inspected: the exact 2026.5 vendor unit still has
the expected daemon flags; policy activation remains owned by the existing
first-boot unit and daemon ordering, without loading target policy into d-i.

The upstream [Linux installation guide](https://mullvad.net/en/help/install-mullvad-app-linux)
documents the manual policy-copy path when automatic installation does not
provide it. The exact [2026.5 policy](https://raw.githubusercontent.com/mullvad/mullvadvpn-app/2026.5/dist-assets/linux/apparmor_mullvad)
and [daemon unit](https://raw.githubusercontent.com/mullvad/mullvadvpn-app/2026.5/dist-assets/linux/mullvad-daemon.service)
were checked as public source data.

`d-i/debian/scripts/common/target.sh` adds `target_exec_diagnostic`: it merges
the command's stderr inside the target before d-i `log-output` consumes it.
Logged, quiet and boolean target wrappers use that boundary. The existing
redaction and tty4 streaming paths receive those diagnostic bytes. Raw
`target_exec`, machine-readable `capture_in_target`, interactive stdin and the
Debconf descriptor protocol retain their existing interfaces. Standalone
Llama and Whisper streamers use the same diagnostic helper.

The shared-caller audit covered all 27 declared late providers, pre-pkgsel
Secure Boot, account/profile producers and consumers, target execution, both
filesystem families and the software installation boundary. The managed
software set included Bitwarden, QoreDB, Obsidian, Tomat, Sleek, Postman,
Discord, Tuta, Ledger, ChatGPT/Codex, Zoom and Filen. Their constructors,
download/trust policy, runtime paths and private Xwayland eligibility were not
changed. The sibling hardware-tuning parser stages its own input before
compilation and does not share the missing-vendor-postinst assumption.

## Other supplied diagnostics

| Diagnostic | Evidence of subsequent handling in these logs |
| --- | --- |
| Initial Intel Wi-Fi firmware missing | Firmware is retrieved from media and loaded at syslog line 1158; wlan0 is detected at line 1161. Missing optional debug firmware is explicitly ignored. |
| CUDA legacy SHA1 key warnings | The selected legacy exception is recorded at installer-log line 382; metadata/package work continues, and the legacy source/keyring is removed at line 795. No global authentication relaxation was added. |
| Debconf Passthrough descriptor warnings | Syslog line 2936 selects Noninteractive after the first failure; package preconfiguration continues at line 2937. These earlier maintainer-script messages do not terminate this run. |
| 3proxy update-rc.d/chkconfig messages | Syslog lines 15336-15338 subsequently enable the packaged systemd unit and report installation. Chroot service starts are deferred. |
| DKMS/depmod requests for the installer kernel | The selected target initrd is subsequently built at syslog line 17323; the repository target-kernel verification completes at installer-log lines 749-758. Boot remains unverified. |
| VFAT/media/PCI/alternatives warnings | They do not terminate the recorded earlier stages; mounting, package installation and GRUB work progress beyond them. No speculative storage or hardware change was made. |

## Performed validation

1. Source-only inspection parsed all 27 declared late providers and 33 unique
   relevant shell sources. Both suite-rendered Mullvad target programs passed
   shell syntax and ShellCheck error/SC2154 checks. Source assertions checked
   compile-before-publication ordering, checked identities, `ln -T`, safe data
   modes, narrow cleanup, diagnostic call-site lines, streamer helper loading
   and the separate value-capture interface. Three Python fixture ASTs and ten
   embedded shell snippets were parsed without importing or executing them.
2. A real offline AppArmor compile completed with status 0 and no diagnostics.
   Parser: AppArmor 4.1.8. Support data: Debian
   `apparmor_4.1.8-3+b1_amd64.deb`, downloaded as public HTTPS data and unpacked
   as bounded regular-file data without installing a package or executing its
   scripts. Archive SHA-256:
   `2f37a6084464dba8daa46e1195186aa7e621542357659cbea07f66a955cd710b`.
   The private support tree contained 261 files/241593 bytes, with fingerprint
   `a1e25005b35b9c8085ba6bad5f8ce0323259fc88b87d1fc951802e0dd958227d`.
   ABI 4.0 was 2205 bytes. Exact Mullvad 2026.5 policy SHA-256:
   `a7b99f7acbb7f99c6ab8ecf5bb674310294c29a561d9bd7c531508841942cab3`.
   No ABI paths required relocation. An initial request for the superseded
   `4.1.8-3` artifact failed before content was consumed; the current Debian
   pool provided the recorded `4.1.8-3+b1` support archive.
3. `timeout --signal=TERM --kill-after=5s 120s make PYTHON=python3 build`
   completed with status 0. It serialized both suites, with 2353 members each.
   A second explicitly captured generation confirmed the same source identity
   after the first generation's terminal output was unavailable.
4. Standard-library archive inspection verified every member's byte count and
   SHA-256 against the manifest, product hashes against receipts, all four
   changed runtime sources against the payload and source-input pins, preseed
   pins, and byte equality of the two suite payloads/manifests. All 26 public
   account-policy snapshots omit resolved identity fields; all 26 runtime
   snapshots retain the canonical home root. Media mount/trust, English-only
   translation and no-PDiff drop-ins remain present, including rendered media
   paths in both suites.
5. `timeout --signal=TERM --kill-after=5s 120s python3 -B tools/post_change_check.py`
   passed before this evidence record, checking 14 changed files, 2353 release
   members and all 22 role-combination plans. The final invocation after this
   record is recorded in the task result. `git diff --check` also passed.

The offline parser command below uses `PARSER_FIXTURE` only as notation for the
private temporary root allocated during this run; all these inputs and cache
destinations were private to that root:

```sh
timeout --signal=TERM --kill-after=5s 30s /usr/sbin/apparmor_parser \
  --config-file "${PARSER_FIXTURE}/parser.conf" \
  --base "${PARSER_FIXTURE}/support" --Include "${PARSER_FIXTURE}/support" \
  --features-file "${PARSER_FIXTURE}/support/abi/4.0" --jobs=1 \
  --skip-kernel-load --skip-cache \
  --cache-loc "${PARSER_FIXTURE}/unused-cache" "${PARSER_FIXTURE}/mullvad.vendor"
```

The compiler returned before cleanup. Cleanup verified the current-run marker,
root identity/mode and expected top-level contents, removed only that private
fixture using symlink-resistant cleanup, and confirmed its absence. No kernel
policy, host include/config tree, cache or kernel feature state was used.

## Generated identity and limits

Both suites now carry release
`0b880ff4898063d1115c4d2be99cdff80769643866abb25ffb03f32c8445cd7a`,
source fingerprint
`7d5a72fcf646bbf88ba0b033eb66928438b9dd9d01f6f42f597423db425b9729`.

| Product | SHA-256, identical in both suites |
| --- | --- |
| `payload.tar.gz` | `312bae7a7bee3053ad78074f388028b6aa2754b8fc1d43ef2070366fadb43e85` |
| `payload.manifest` | `3642df0cdee6faedef3666565b185dae485b08a31d66e779033497b8fc6344be` |
| `source.sh` | `43c1ae691c6d6c095b1f43538c93bb89b0ed2a24656eff6bd1f63ede0c6f3f33` |
| `support-matrix.json` | `ff0b2a12aec48418f02ad6dc591db5463826187eb4ac1fa836a1f70f05ab782a` |

Runtime source changes are `scripts/common/target.sh`, `scripts/late/mullvad.sh`,
`scripts/late/llama.sh` and `scripts/late/whisper.sh` below the shared Debian
source tree. Fixture changes are `test_target_debconf_boundary.py` and the new
`test_mullvad_apparmor_publication.py` below its tests directory. Generated Git
changes are `payload.tar.gz`, `payload.manifest`, `receipt.json`, and
`preseed.cfg` in each suite. This record is the remaining changed file.

The new publication fixture has nine methods covering missing/existing policy,
safe mode normalization, compiler failure, unsafe source/destination,
concurrent file/directory/symlink replacement, link failure, cleanup failure,
and durability failure. The Debconf fixture adds diagnostic-capture and
stdout-only-value cases. They were authored and parsed, not executed: no
isolated native fixture environment was prepared. Independent sidecar attempts
failed before source inspection with `invalid_encrypted_content`; no independent
review result is claimed.

No QEMU, full installer replay, native fixture suite, service activation,
enrollment, deployment or installed-system boot was performed. Offline parsing
proves that the recorded policy compiles against the recorded support data; it
does not prove filesystem publication behavior, boot policy activation, VPN
networking or completion of stages after the supplied run stopped. The user's
offline catalog work was not modified or executed.

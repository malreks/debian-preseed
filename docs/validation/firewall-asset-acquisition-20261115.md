# Replacement installer logs: firewall source ownership and acquisition failures

## Source and supplied run

Baseline: `a82a18895e93d7576732d66cb6a83fbde8da8c7f`, initially clean on
`mcr/main`. Both replacement logs were read as data. Secret-bearing command
lines were withheld and URLs/credential fields redacted in diagnostic output.

| Evidence | Bytes | Lines | SHA-256 |
| --- | ---: | ---: | --- |
| `todo/installer.log` | 188672 | 1327 | `d639a50ee00842ab33adfbc66565a84650de5af2c53a55742af5dfcc83b0cb1a` |
| `todo/syslog` | 1687330 | 17943 | `7a2855470d28e839f8d92f2b951bc21af9ad78ac58a4487d797c2ea78ddab899` |

The supplied syslog identifies release
`0b880ff4898063d1115c4d2be99cdff80769643866abb25ffb03f32c8445cd7a`
at lines 1266, 1381 and 17870. This matches the baseline products. The failure
therefore occurred with the previous repair present. Installer-log lines
833-841 confirm successful Mullvad policy publication, compilation, journal
contract validation and offline boot-unit enablement.

There are seven structured error records in each log, all in one terminal
chain: installer-log lines 1314-1321 and syslog lines 17935-17942. The first
cause is the old logical source request
`hooks/target/etc/nftables/firewall-security.rules`. Its existing FILE selector
names the physical desktop source, so reconstructing the repository path from
the installed destination bypassed the catalogue's ownership contract.

Two shared-boundary defects amplified the failure: the enclosing staging call
continued with an empty command-substitution result, and the acquisition EXIT
trap formatted nested helper positional arguments as the original source and
destination. The misleading destination in that diagnostic is not evidence
that acquisition wrote to the profile name.

## Repairs

- `d-i/debian/scripts/late/security.sh` uses an explicit two-row FILE-selector
  and target-path table for persistent firewall state. Both sources resolve
  through the existing catalogue. Lookup/publication status propagates, valid
  existing administrator state is preserved, and existing symlink/type/mode/
  ownership/link-count rejection remains in place.
- `d-i/debian/scripts/late/target-assets.sh` rejects an empty acquired source
  before destination preparation, temporary directory creation or fetching.
  The explicit stdin publication interface remains supported.
- `d-i/debian/scripts/common/modules/repository-apt.sh` retains acquisition
  seed/source/destination/mode in its own subshell variables. The operation and
  EXIT diagnostic use those retained values, including when a nested fatal
  helper exits. Empty source/destination requests fail with status 64 before
  loading the source library. Ordinary acquisition failure statuses are
  preserved; optional fetch policy remains with the caller.
- Diagnostic contexts in the affected boundaries now name their actual source
  lines and operations.
- Six regression methods in `test_repo_selector_diagnostics.py` cover nested
  failures, empty requests, physical firewall source selection, preservation
  of existing state, symlink rejection and failure before publication. They
  are isolated-only fixtures and were not executed.

## Cross-component source inspection

The catalogue/member audit verified all 2126 declared FILE paths. An initial
data-only expansion of 139 literal/loop asset requests found the logged
firewall request as the sole mismatch; the other expanded requests resolved.
The corrected firewall bindings were independently checked against their
physical catalogue members and target destinations.

Further data checks verified 516 fixed FILE-selector references and 75
additional constructed/table assets, including hardware tuning, managed login
policy, desktop/systemd resource drop-ins and GRUB fragments. All 41 callbacks
after the security boundary in the two filesystem-family paths have source
providers. Remaining dynamic request forms were reviewed against their finite
module/profile inventories and owning selectors.

The review included both filesystem families, nftables generation and local
state, app-veth/Stubby, Fail2Ban, firstboot logging, GRUB fragments/profiles,
Secure Boot, storage enablement, D-Bus, deferred tmpfs, networking/sharing,
hardware tuning, desktop resource policy and software staging. The shared
software boundary includes Bitwarden, QoreDB, Obsidian, Tomat, Sleek, Postman,
Discord, Tuta, Ledger, ChatGPT/Codex, Zoom and Filen. No constructor arguments,
download policies, credentials, private Xwayland eligibility or target policy
permissions were changed. Bounded independent sidecar attempts failed before
inspection with `invalid_encrypted_content`; the source findings here are the
coordinator's checks, not independent review evidence.

The nftables generator's `--write --summary` installation path was inspected:
kernel checking/reload are separate explicit options. This repair does not
activate target firewall or AppArmor policy in the installer or on the host.

Other error-shaped text was classified against subsequent progress. Wi-Fi
firmware loads at syslog line 1158; Debconf selects Noninteractive after its
Passthrough warnings; 3proxy reports installation at line 15333; the selected
target initrd is subsequently generated at line 17318 and the repository
kernel stage completes. Earlier keyboard-cache, mdstat, firmware-marker,
cursor-alternatives and D-Bus init-script diagnostics do not terminate this
recorded run. Legacy CUDA authentication warnings retain their existing
explicitly selected exception. No speculative hardware/storage repair was
performed.

## Validation and products

Commands completed with status 0:

```text
timeout --signal=TERM --kill-after=5s 120s make PYTHON=python3 build
timeout --signal=TERM --kill-after=5s 120s python3 -B tools/post_change_check.py
git diff --check
```

Generation was repeated after the final diagnostic-line adjustment. The audit
before that final adjustment passed for 12 changed files and all 22 compiled
role-combination plans. The final changed-file audit after this record is
reported in the task result.

Additional source-only checks passed: the three changed shell sources;
six suite-rendered source copies with no unresolved runtime-path tokens;
Dash and BusyBox syntax; ShellCheck error and SC2154 checks; exact diagnostic
line bindings; the changed fixture's Python AST; and five complete/assembled
fixture shell snippets, including the actual firewall-state block. No shell
body or fixture was executed.

Final archive inspection checked every one of the 2353 members per suite
against its manifest byte count and SHA-256, product hashes against receipts,
all catalogue paths, all three modified runtime sources against current bytes
and source-input pins, and frontend preseed pins. The 26 public account-policy
snapshots omit resolved identity fields. CD-ROM mount/trust, English-only
translation and disabled-PDiff policy remain present. Both suite payloads and
manifests are byte-identical.

Release:
`0798b676802d45a36ef010bfd87635f1cd8145489d5afac0e799e4056247b635`.
Source fingerprint:
`db93d708637e4fd195f435dd1e73f58314aa8f9669256583f6172a80f1969e29`.

| Product | SHA-256 |
| --- | --- |
| Either suite's `payload.tar.gz` | `eaf8bc9fcab77192c6697e2f4c071f4951fe433100d97510c0a56e32a100ef88` |
| Either suite's `payload.manifest` | `f0e9d317c5465cea31e62c6f32d2e33fb6c6ed1d3f2803fe0cab660ab61e51f5` |
| Forky `preseed.cfg` | `f9b7e09306947979a362fe7bca1c69ed71d38b394c71c571362bf5dbb05c6717` |
| Trixie `preseed.cfg` | `055a579c5a2283dd85ce542b0c193b325016d19ebe03961a621b819e8077c71c` |

Generated Git changes are `payload.tar.gz`, `payload.manifest`, `receipt.json`
and `preseed.cfg` in each suite. The remaining changes are the three runtime
sources, one fixture file and this record. The offline catalogue tool and
supplied logs were not modified.

No QEMU, native fixture execution, installer replay, host management operation,
deployment or installed-target boot was performed. The new code and products
have source/serialization evidence. Completion of the live stages after the
recorded failure and first-boot firewall, VPN and service behavior remain
unverified; the supplied logs cannot provide that evidence.

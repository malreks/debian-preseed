# Waybar and hardware-tuning hardening review — 2026-11-09

This review covers the supplied `todo/` snapshot and the current `mcr/main`
source tree. The repository instruction boundary was applied throughout:
`todo/` was read as data, while tests, installer hooks, services, D-Bus,
hardware controls, host policy and disposable environments were not executed.

## Evidence census and dispositions

The current `todo/` tree contains 92 regular files, 5,947,440 bytes and
32,504 decoded lines. Empty files are evidence of an absent capture, not a
passing runtime check. Repeated records below are grouped by profile, path and
operation so one incident is not counted once per PID.

| Evidence | Source and symptom | Disposition and source repair |
| --- | --- | --- |
| 28 AppArmor `file_inherit` records | `todo/managed/security/apparmor/apparmor.log:463-496`, profile `labwc-waybar-run`, `/dev/rfkill`, read-only inheritance | Actionable lifecycle defect. AppArmor evaluates inherited descriptors at the profile transition, before Python can call `close_range(2)`. The `labwc-waybar-run` child domain now permits only the exact read-only `/dev/rfkill` handoff and the wrapper immediately closes descriptors 3 and above before invoking `systemd-run`; no write, reopen or broad device rule was added. |
| 6 GTK schema opens | `todo/managed/security/apparmor/apparmor.log:467,471,477,481,497,501`, profile `labwc-waybar-menu`, `/usr/share/glib-2.0/schemas/gschemas.compiled` | Actionable least-privilege resource gap. The menu profile now permits the schema directory for traversal and the single compiled schema file read-only. |
| 6 XKB rule opens | `todo/managed/security/apparmor/apparmor.log:468,472,478,482,498,502`, profile `labwc-waybar-menu`, `/usr/share/xkeyboard-config-2/rules/evdev` | Actionable least-privilege resource gap. The menu profile now permits the package-owned rules directory for traversal and the single `evdev` file read-only. This follows the actual target path reached through the XKB package link; it does not grant a shared `/usr/share/**` tree. |
| GTK/XKB popup failures | `todo/journalctl:1584-1593` and the surrounding Tomat/Wayscriber launches report `status=6/ABRT`, failed keymap creation and repeated popup retries | Root cause is the two exact resource denials above. Popup ownership remains the existing GTK helper and canonical XML/action maps. Tomat and notifications now declare Waybar signal 8 so their existing state markers can refresh the native custom modules; native audio, battery, brightness and clock module ownership is unchanged. |
| Popup process churn | `todo/journalctl:1460-1593` shows distinct UUID transient units for repeated popup clicks and one signal on every marker transition | Actionable lifecycle defect. `labwc-waybar-run` now uses one fixed transient unit per popup button (`labwc-waybar-menu-{notifications,power,tomat,wayscriber}.service`), so a second click fails closed while the first owner is alive. Non-popup actions retain unique unit identities for safe concurrency. Marker cleanup remains in the transient owner's `ExecStopPost` path. |
| Hardware broker startup timeout | `todo/journalctl:1267-1269`; `todo/installer-state/logs/firstboot/data/systemctl-jobs.txt:10-12` shows `hardware-tuning-autostart.service` waiting while `hardware-tuning.service` is still running | Actionable readiness cycle. Broker initialization previously called `StartUnit(hardware-tuning-autostart.service)` before sending `READY=1`, while the autostart unit is `After=` and `BindsTo=` the broker. Initialization now records activation intent, publishes readiness, then performs the allow-listed activation and bounded recovery path. |
| Intel/NVIDIA lease failures | `todo/journalctl:1584-1593` reports both leases rejected with the same `policy-owner` timeout | Duplicate consequence of the broker readiness cycle, not two vendor defects. Vendor capability gates, thermal policy, AppArmor domains, bounded leases and recovery remain unchanged. |
| Backlight availability | `todo/journalctl:84-117` shows `intel_backlight` and keyboard backlight units completing; `validation-results.txt:142,416,472` records the managed helper and command contract | Expected supported-hardware evidence. The native Waybar `backlight` module remains native with `cursor: true`; the helper reports an explicit unavailable class when no controllable backlight exists and retains bounded `brightnessctl --class=backlight` operations. No speculative hardware change was made. |
| Firmware, ACPI, NVIDIA, SGX, MMIO, Bluetooth and storage warnings | `todo/installer-state/logs/firstboot/data/dmesg-warnings.txt`, `todo/managed/system/kernel.log`, and the corresponding journal records | Informational or evidence gaps. No repository-owned initiating transaction is established, so no kernel parameter, firmware workaround, device permission or log suppression was introduced. |
| CrowdSec and Tailscale enrollment/optional records | `todo/managed/security/crowdsec/*`, `todo/installer-state/logs/firstboot/data/*network*`, and `todo/journalctl` | Expected optional or pending-enrollment state. Existing disabled/enrollment semantics remain visible; no automatic external enrollment or retry loop was added. |
| Empty application, scanner, antivirus, zram and storage logs | The complete `todo/` census | Evidence gaps only. Absence of a log is not treated as runtime success and did not trigger unrelated source changes. |

## Complete log audit

Every regular file under `todo/` was read as data, including all 46 files with
the `.log` suffix and the journal, installer, kernel, firstboot and validation
captures without that suffix. The 46 `.log` files total 5,441,636 bytes; 41
contain no actionable diagnostic record in this snapshot. The five logs with
diagnostic records and their dispositions are:

| Log | Observed records | Disposition |
| --- | --- | --- |
| `todo/managed/security/audit/auditd.log` | 218 bounded `timeout`/CrowdSec audit probes, the same 40 AppArmor denials, old popup `systemd-run` launches, and expected cryptsetup success records | The probes and cryptsetup records are expected evidence. The 40 denials and popup launches are covered by the exact AppArmor and transient-owner repairs above; the audit stream itself remains enabled. |
| `todo/journalctl` | Hardware broker/autostart timeout, six GTK/XKB popup aborts, UUID popup churn, expected missing-global-XWayland, network/NTP timeouts, pending CrowdSec enrollment and normal storage/firmware messages | Only the broker, popup resource and popup-owner groups are actionable. Network, NTP, enrollment, firmware and missing-global-XWayland records remain classified as expected or target-evidence limits. |
| `todo/installer-state/installer.log` | Deferred AppArmor reload while the installer kernel was unavailable, successful Tor fallback after primary 404s, bounded raw-partition alignment warnings, optional profile skips | The AppArmor reload is an expected deferred target activation; Tor fallback succeeded in the captured run; alignment warnings are within the explicit recipe budget; absent optional profiles remain unavailable states. |
| `todo/managed/system/kernel.log` and `todo/installer-state/logs/firstboot/data/dmesg-warnings.txt` | ACPI operand/reservation messages, RMI descriptor rejection, PCI ROM assignment, unavailable memory ranges and dummy regulator use | Informational firmware/kernel/driver evidence. No repository-owned initiating defect or safe source-level fix was established, so no kernel parameter or blanket device permission was added. |
| `todo/managed/security/crowdsec/crowdsec.log` | Central API disabled/not enrolled, duplicate upstream grok registration and an absent optional qBittorrent log path | Expected optional/enrollment and upstream acquisition state; no automatic enrollment, parser rewrite or speculative log-path creation was introduced. |
| `todo/installer-state/logs/firstboot/data/{systemd-failed.txt,systemctl-failed.txt,security-baseline-units.txt,validation-results.txt,apparmor-status.json}` | No failed units, enforced managed profiles, passed path/command checks and explicit optional profile skips | Historical target evidence only. It supports the recorded baseline but does not prove the new source changes are deployed; no live check was rerun. |

The remaining diagnostic-bearing firstboot captures (`mounts.txt`,
`findmnt-verify.txt`, `fstab.txt`, `systemd-targets.txt`,
`network-targets.txt`, `desktop-units.txt`, `journal-warnings.txt`,
`mok-enrollment.txt`) contain mount, target, optional-device or enrollment
state rather than a new repository-owned failure. Empty application, model,
network, scanner, antivirus, initramfs, storage, timeshift, USB, zram and
component logs remain evidence gaps, not passing runtime assertions.

## Runtime path contract

`d-i/forky/hosts/installer/runtime.env` now names the target-side Perl,
Python, hardware-tuning, AppArmor, firstboot, systemd, D-Bus, icon,
application, documentation and font roots, including separate `/usr/libexec`
and `/usr/local/libexec` roots. `PERL5LIB_TARGET` and `PYTHONPATH_TARGET` are
intentionally absent; scripts and wrappers derive any process-local search path
from the canonical roots when a consumer explicitly needs one. The Perl contract has one
canonical `/usr/local/lib/perl5/site_perl` root; zram uses the descriptive
`DIR_ZRAM_PERL_MODULES` subroot and there are no duplicate parent/drop-in
aliases. Immutable Debian/FHS
locations in target helpers remain literal where the installed interpreter or
system manager requires those exact paths; the new runtime keys are the
installer/rendering contract for paths that cross phases.
Repository-relative selectors now derive from `d-i/forky/repo.env`, including
target `etc`, `usr`, `usr/local`, `var/lib/firstboot`, desktop component and
firstboot source roots. The installer-only `TARGET_ROOT`, `DIR_INSTALLER_*`,
and `FILE_INSTALLER_LOG` assignments now live exclusively in
`hooks/installer/di.env`; the bootstrap fetches and validates that file after
`repo.env` and before phase dispatch. `runtime.env` contains none of those
installer-only keys. Installer-side target access uses the canonical
`TARGET_ROOT` value, while target assets retain `__INSTALLER_PATH_*__` tokens
until the shared publication renderer materializes concrete installed paths.

## Native Waybar and security invariants

The storage, CPU, memory, power and brightness controls keep their existing
native or already-authorized custom module identities. GTK popup ownership is
limited to notifications, power, Tomat and Wayscriber. Taskview continues to
use its existing custom `window-switcher` state marker and bounded transient.
No second menu-action table, polling observer, global active flag, global
XWayland package or private Discord/Zoom boundary change was introduced.

## Allowed verification and limits

The permitted follow-up is static inspection of the changed Python, shell,
JSON/XML/CSS/template and AppArmor source, followed by the repository's
changed-file audit. The offline AppArmor parser may be used only with the
private include/configuration procedure, `-Q`, `-K`, one compile job and no
host policy load. `make build` is required only if source inputs are accepted
for payload regeneration; it may write only the three authorized products.

No test runner, fixture import/discovery, installer code, systemd manager,
D-Bus service, native application, hardware operation, network acquisition,
AppArmor load, container, VM, chroot or disposable environment was run for
this review. Static and serialized evidence cannot prove target GUI rendering,
loaded policy, boot ordering, thermal behavior, native brightness mutation,
application launch success or deployment acceptance.

Final static evidence for this source revision:

- `make build` completed the authorized pure serialization path and produced
  2,029 payload members, including `hooks/installer/di.env`.
- `python3 -B tools/post_change_check.py` passed after regeneration, covering
  235 changed shell sources, 228 changed Python sources, 672 appearance mappings,
  structured assets, AppArmor structure, and generated archive readability.
- Data-only contract checks found 550 unique assignments in `runtime.env`, 74
  repository selector assignments in `repo.env`, and 13 installer assignments
  in `hooks/installer/di.env`; all three files have zero duplicate keys and zero
  complete variable-only aliases. `runtime.env` and `repo.env` contain no
  `TARGET_ROOT`, `DIR_INSTALLER_*`, or `FILE_INSTALLER_LOG` assignments. The
  generated archive and manifest checks passed, including the packaged
  `runtime.env`, `repo.env`, `di.env`, and generated preseed pins.
- Generated product SHA-256 values are:
  `2ce8d0054049d845cd88f2b870fd40a9dde65e37431519256bde3e35e96613a7`
  (`payload.tar.gz`),
  `8fcb62f2a743c84e1e784eb93ca60c8e08ef94df39773dbbc303962d56b87bbe`
  (`payload.manifest`), and
  `10607122d1f05c8fc6280e8540fa4fabdd5069adf995c33bbebb0df60d326f63`
  (`preseed.cfg`).
- The offline AppArmor parser was not run for this revision because the private
  package support/include tree required by the repository procedure was not
  available without network acquisition. The changed-file structural policy
  checks passed; no host policy or parser cache was touched.

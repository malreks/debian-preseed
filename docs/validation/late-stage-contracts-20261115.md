# Late-stage class contracts and visible installer failures

## Scope and source identity

Reviewed the working tree based on commit
`3453518771b91c9f246310b536d874a1f8b3b085`, including the reported strict class
selector failure, both filesystem-family late-command paths, subsequent class
dispatch, managed software installation and finish-install hooks. The user
prohibited QEMU validation and excluded `tools/offline.py` from the task.

The supplied `todo/installer.log` and `todo/syslog` still identify an older
publication and the preceding firewall asset-selector failure. They do not
record execution of this working tree. Their SHA256 values are respectively
`d639a50ee00842ab33adfbc66565a84650de5af2c53a55742af5dfcc83b0cb1a`
and `7a2855470d28e839f8d92f2b951bc21af9ad78ac58a4487d797c2ea78ddab899`.
The latest unregistered-class failure is established by the user's report and
the reachable source calls, rather than a new log from this publication.

## Cause and corrected owners

`configure_target_fail2ban()` queried the retired `service/web` selector twice.
Neither suite's 44-entry class registry contains that selector. The strict
class parser aborts even when called as a predicate with stderr redirected.
The preceding firewall operation context therefore obscured the real caller.

- `scripts/late/security.sh`: removed both retired web-class branches; the
  current frozen role package plan and SSH policy continue to govern Fail2ban.
  Added entry contexts for nftables, Fail2ban, application networking and
  AppArmor/auditd, and corrected the persistent-firewall source line.
- `scripts/common/modules/class-metadata.sh`: the strict diagnostic now includes
  the grammar-validated selector that failed registry lookup.
- `scripts/late/btrfs-family.sh` and `f2fs-family.sh`: corrected all 117 operation
  source-line markers and send each operation name through the shared logger.
- `scripts/late/software.sh.tmpl`: uses the shared info/warning logger, records
  the selected application worker context, and reports start/completion around
  the existing checked worker wait. Failure status, extraction outcome markers,
  selection policy and the Zoom/Discord private Xwayland boundary are preserved.
- `hooks/installer/finish-install.d/95-normalize-apt` and `99-normalize-finish`:
  progress uses the shared logger and reaches tty4 as well as the installer log.

## GTK frontend failure path

`scripts/common/lifecycle.sh` now presents a native critical cdebconf
`Type: error` question before the terminal hold stops its main-menu ancestor.
This replaces the GTK progress view with an acknowledged error dialog. It uses
the existing installer frontend; it is not a separately launched desktop
window. The same question is supported by d-i's text frontend.

The dialog displays the first failure's phase, component, operation, source,
line and status. Context values have character and length limits; access-bearing
URLs, control characters and arbitrary detail are excluded. Detailed diagnostics
remain on tty4 and in the saved failure/log records. Continue acknowledges the
error; it cannot resume installation or permit automatic reboot.

The handler requires the initialized inherited frontend and restores the
phase-owned reply stream from FD 8. It does not start another database writer.
A private one-shot claim prevents duplicate requests from nested fatal handlers.
Template loading, progress stop, queue clearing, substitutions and critical
INPUT share a 15-second setup deadline. GO deliberately waits for acknowledgement.
On unavailable/broken transport, the original failure and terminal hold remain.
No protocol reply or arbitrary failure detail is logged by this UI path.

The canonical lifecycle is embedded byte-for-byte in the authored common
bootstrap, both generated suite bootstraps and both payload archives. The
template uses explicit shell delimiters and a single printf command so it
survives preseed's flattened bootstrap serialization before payload acquisition.

The protocol and GTK implementation were inspected as primary-source data:

- [Debconf protocol specification](https://www.debian.org/doc/packaging-manuals/debconf_specification.html)
  defines critical INPUT, GO, SUBST and the seen flag.
- cdebconf commit `080b83455933b8920257add2dc00a5711636e09b`,
  [commands.c](https://salsa.debian.org/installer-team/cdebconf/-/blob/080b83455933b8920257add2dc00a5711636e09b/src/commands.c),
  lines 631–664: X_LOADTEMPLATEFILE updates the running frontend's template and
  question databases, including the question owner.
- The same revision's
  [GTK go.c](https://salsa.debian.org/installer-team/cdebconf/-/blob/080b83455933b8920257add2dc00a5711636e09b/src/modules/frontend/gtk/go.c),
  lines 311–325 and 525–609, and
  [handlers.c](https://salsa.debian.org/installer-team/cdebconf/-/blob/080b83455933b8920257add2dc00a5711636e09b/src/modules/frontend/gtk/handlers.c),
  lines 144–158: error uses the native note/question layout; GO displays the
  question and waits for the frontend's answer.

These sources establish the intended interface, not live evidence of a popup on
the user's installer image.

## Audit beyond security

Traced the 23 distinct family callback identities after security: firstboot
logging; GRUB defaults, profiles and update; kernel tunables, module signing and
kernel/initrd repair; secure-boot preparation, optional MOK reset, USB bundle
sync and storage close; tmpfiles deduplication; storage units and default target;
D-Bus broker; deferred/volatile directories; logging foundation and archival.
F2FS uses 20 of those identities. Existing optional warning paths retain their
existing semantics; required failures remain fatal.

The full desktop late dispatch was inspected through `os.shared`, CrowdSec,
kernel, desktop storage/software, Tailscale, Whisper, crypto, uplinks, sharing,
services, Codex, DevOps, firmware, CH341A, Timeshift, system/desktop
virtualization and desktop-session installation.

The software sibling inventory covers all 13 selected workers: Tor Browser,
ChatGPT/Codex, Bitwarden, QoreDB, Obsidian, Tomat, Postman, Sleek, Zoom, Filen,
Discord, Ledger and Tuta. Reviewed worker declarations, the class-selection
wrapper, 82 software settings in all 20 compiled desktop runtime views, the
shared download/staging contracts, and servicing module/import coverage. This
does not verify current vendor availability or target application execution.

The changed-file static checker now rejects unknown literal class queries
against either suite and validates registry references, FILE selector membership,
family marker lines, worker declarations and compiled software settings from
the payload as data. It also checks canonical lifecycle embedding and the fatal
frontend's ordering, ownership, bounds and native error template.

## Verification performed

- Pure generation:
  `timeout --signal=TERM --kill-after=5s 120s make PYTHON=python3 build` — exit 0.
- Required changed-file static audit:
  `timeout --signal=TERM --kill-after=5s 180s python3 -B tools/post_change_check.py`
  — PASS, including decoded preseed shell layers in Dash and BusyBox, 11 changed
  shell sources, five Python ASTs, both payload class registries, all FILE
  members, all 117 family markers and all 20 desktop software runtime views.
  Counts repeated per identical suite archive are not distinct runtime cases.
- A separate source-only pass parsed all 194 shared installer POSIX sources
  with Dash and ShellCheck error diagnostics — zero issues.
- Data-only rendering of the seven earlier changed installer scripts across
  all 20 compiled desktop runtime views produced 140 candidates: no unresolved
  path tokens, Dash/BusyBox syntax errors or ShellCheck error diagnostics.
- A negative control appended the retired literal class query temporarily:
  the permitted static audit rejected it; the source was restored byte-for-byte.
- Standard-library archive/hash checks verified all 2,353 members' sizes and
  SHA256 values against each format-3 manifest and all receipt product hashes.
  Both suite payloads are byte-identical; lifecycle embeddings equal canonical
  source. Existing CD-ROM, English-only translation and disabled-PDiff policy
  files equal HEAD bytes.
- `git diff --check` — no whitespace errors.

Tools: Python 3.14.10, ShellCheck 0.11.0 and BusyBox 1.38.0
(Debian 1:1.38.0-3+b1). No installer snippets, managed Perl imports, tests,
services, package scripts or host management helpers were executed.

Authored/updated isolated-only fixtures are in
`d-i/debian/tests/test_repo_selector_diagnostics.py`,
`test_fail2ban_clipboard_apparmor_20260928.py`, `test_debconf_protocol.py`, and
`tools/tests/test_class_query_contract.py`. They cover the retired query,
required worker failure propagation, logging, saved frontend stdin, one-shot
display, protocol errors and private context. They were AST parsed and reviewed,
not executed. Independent sidecar review attempts failed before inspection with
the agent runtime's encrypted-content hydration error; no child findings are
claimed as verification.

The four fixture files' combined SHA256 is
`b3a47d183587e4edf774ef468fa4b2e48706f3f1fa2182eb7a3afe2e87ed05c6`:
sort their repository-relative names, then hash each UTF-8 name, a NUL byte and
the raw SHA256 digest of that file's content, in order.

## Generated publication and remaining acceptance

Both receipts identify release
`219b51ae6230ae49b34b91fa13ae6a73ec170b84f8f061de8b5a097a2d1bad1c`
and source fingerprint
`4cbdc1b950f6bda7a1c2a64e34a3d7cc62ef17ab402391822681a64eedda6157`.

| Product | SHA256 |
| --- | --- |
| Both payload archives | `309e8e89df3db17e4e661e5fac0ddc484e592a8aeb446032100532e10c55e922` |
| Both manifests | `68fcf4fa97583fef522e04ad2be4db24a1dae2ba93fce4eb86ac698f02807e2d` |
| Both source bootstraps | `8a065d4000b96f158338663fae6ae4d95949272948154a36cf33fb85ff1dce28` |
| Forky preseed | `53f28a6d132e55f1513b16ab2dabe11b6649d11fb25dec0575a54fc26279a0f2` |
| Trixie preseed | `99985252dad3a72c9d097ccee305d2837fc39c2de70c7b7d4a57a407a607059d` |

The regenerated files are the flat suite payload, manifest, bootstrap, receipt
and preseed products; the unchanged support matrices were serialized too.
No publication/deployment was performed. No QEMU, container, chroot, GTK visual
test, live installation or target boot was run. Full installation, actual GTK
display/acknowledgement, native package transactions, secure-boot/hardware and
application execution therefore remain unverified. Pending external enrollment
remains informational. The referenced `debian-preseed-de-audit.md` is absent in
this checkout, so it could not supply an additional acceptance gate.

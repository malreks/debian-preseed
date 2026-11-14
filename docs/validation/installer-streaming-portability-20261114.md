# Installer target-output portability repair — 2026-11-14

The user reported a CUDA pre-pkgsel failure during “repair legacy CUDA target apt directories”, accompanied by `installer.cuda-legacy.sh: line 370: tee: not found`. The reported diagnostic also attributed the operation to `profiles.sh` / `fetch_host_env`.

Source inspection located the missing command in the shared `target_exec_logged` pipeline. It ran `tee` in the installer shell. Consequently, an installer image without that applet could break every ordinary target operation using this pipeline. The directory-repair command executes separately inside the target; the supplied evidence does not establish that its directory operations failed independently.

Successful `installer_fetch_host_env` calls also left their operation context active. That explains the misleading profile attribution on a later target-command failure.

## Implementation and shared callers

- `scripts/common/target.sh` now relays diagnostic text using shell `read`, `printf`, tests and assignments. The capture descriptor opens once. Backslashes, whitespace, blank lines and the final line's newline state are preserved. This interface carries diagnostic text; binary/machine-data capture retains its separate entrypoint.
- SIGPIPE is ignored only in the relay process. A console write failure disables that sink while the relay continues consuming and capturing output. A capture-open failure drains remaining command output. The target command is not repeated. Its nonzero status remains primary; a successful command with failed capture returns the existing infrastructure status 125 and emits a fixed diagnostic.
- The existing live console path still passes through the flushing redactor before writing to tty4. Quiet, machine-data capture and interactive target APIs keep their existing interfaces, target execution environment and debconf descriptors.
- `scripts/common/modules/profiles.sh` restores the caller's context after successful profile acquisition, and preserves absent context after successful acquisition or data loading. Acquisition/parser failures retain their own failure context. Numeric source annotations were corrected to their actual source lines.
- `hooks/installer/pre-pkgsel.d/91cuda-legacy-apt.sh` establishes selector-resolved context at source staging, directory repair and metadata refresh. Later failures identify the owning CUDA operation.

A source inventory found 280 wrapper-name references in 70 files under the shared scripts and installer hooks. These are textual references, including definitions. The inventory includes common kernel/firmware, storage, hardware, SSH and services; both CUDA/NVIDIA pre-pkgsel hooks; late APT, account, crypto, GRUB, networking, security, CrowdSec, Podman, DevOps and Codex work; desktop asset/application staging; and server boot/foundation. The finish-install APT script has its own `run_in_target` definition and does not use the changed streaming implementation.

The managed application paths inspected through these shared callers include Bitwarden, QoreDB, Obsidian, Tomat, Sleek, Postman, Discord, Tuta, Ledger, ChatGPT/Codex, Filen, Zoom and Tor Browser. No application policy, servicing constructor, installed wrapper, AppArmor permission or private Xwayland behavior changes in this repair. The executable wrapper arguments and target paths are unchanged.

The shell interface reference used for signal/read/printf review was the [Debian Trixie Dash manual](https://manpages.debian.org/trixie/dash/dash.1.en.html). This documentation review is not evidence of execution in the failing installer image.

## Previous installation policy retained

The common suite APT trees still contain the requested `00CDMountPoint` and trusted-CD-ROM drop-ins. Bootstrap publication still preserves native media/temporary APT state through apt-setup and pkgsel; the late/final stages replace the directory with explicit managed common/role fragments while retaining the backup. The media repair's evidence is recorded separately in `apt-media-regression-20261114.md`.

English-only Translation metadata and disabled PDiffs remain in the common metadata policy, the first network refresh and the dedicated CUDA refresh. The explicitly selected CUDA-legacy source retains its scoped authentication exception; ordinary network archive defaults remain strict. Earlier primary-account and shared late-stage profile-field repairs are unchanged. No APT source or policy input was edited in this repair.

## Authored regression fixtures; not executed

`d-i/debian/tests/test_installer_progress.py` remains protected by the isolation guard before discovery/import. Its private tool PATH deliberately excludes `tee`; it inherits no caller environment and uses explicit subprocess timeouts of 10 or 15 seconds. The fixture cases cover:

- live redacted output acknowledged before the target command finishes, exact command status 37, capture-open failure 125, and primary status 37 when capture also fails;
- leading/trailing spaces, backslashes, blank lines, an unterminated final line, command statuses 0/37, and removal of stream work directories;
- a console reader closing its pipe before a command finishes more than a pipe buffer of output, with all 2048 diagnostic lines expected in capture and status 37 retained;
- caller-context restoration after successful profile fetch/load, preservation of absent context, and parser-failure attribution for rejected data.

These fixtures were reviewed as source and syntax-parsed. They were not run. No installer image/package version was supplied by the failure report, and none was inferred from the development host. Forky and Trixie remain the selected target suites.

## Observed source and generation checks

Baseline commit: `8f1b5cd` (`fixed offline mode`), with a clean worktree before this repair. Tool versions recorded: Python 3.14.10, ShellCheck 0.11.0 and GNU Make 4.4.1.

1. A bounded, standard-library-only source inspection parsed the changed Python AST and all five embedded shell programs with `/bin/sh -n`. It executed no repository module or shell fixture. It checked seven diagnostic annotations against their physical source lines, inventoried shared-wrapper references, and found no executable `tee` reference in installer scripts/hooks. The command had a 30-second outer timeout and five-second syntax-parser deadlines. An incidental Python encoding-default warning did not change the successful result.
2. `timeout --signal=TERM --kill-after=5s 120s make PYTHON=python3 build` passed. The reviewed recipe only serialized the authorized flat suite products; it ran no tests, target programs or validators.
3. A 45-second bounded archive/data check made 12 exact source-byte comparisons across the two payloads: the three changed runtime/hook sources plus `00CDMountPoint`, `00trustcdrom` and `25no-pdiffs` for each suite. It resolved shared paths through the authored repository selectors, checked the retained media/language/PDiff settings, verified receipt product hashes and preseed pins, and confirmed identical suite payloads/manifests. It extracted no files and executed no payload member.
4. `timeout --signal=TERM --kill-after=5s 120s python3 -B tools/post_change_check.py` passed after generation: 12 existing changed regular files, three shell sources, one Python AST, 2353 release members, 2218 source-byte comparisons, 198 frontend comparisons, 319 runtime-placeholder producers and 52 APT source/preference contracts. The final required audit is repeated after adding this record; the final task response records that result.
5. `git diff --check` passed, including the diff checks within the required audit.

The delegated read-only sidecar review was unavailable because of an encrypted-context hydration error before it could inspect the checkout. No independent reviewer findings are claimed; the root agent performed the source review and integration.

No QEMU, VM, container, chroot, functional fixture, APT transaction, installer replay, installed management helper or target service was executed. No validation environment was created or left for cleanup. No host configuration, package state or service was used or changed. Full installation, native console/signal behavior and boot remain unverified. Serialization and syntax consistency do not establish native acceptance.

## Serialized identity and artifacts

Source release: `bf7aa49da561e3ddb8e328d34a7df3789b7148c6cb989eae2feb450a613c296f`.
Source fingerprint: `60761a8bacf1aaa9138ef854fdcbb46a9fb583377221a399d04fad702c2b7061`.
Each payload contains 2353 members.

| Product | SHA-256 |
|---|---|
| `d-i/forky/payload.tar.gz` | `0b649523fa2eca3a52a411c5e63331b08cd4648da0ad85140f8748ae4f59aa26` |
| `d-i/forky/payload.manifest` | `b4b1f0bf9f96cd53835929e2e9c372e4e4840b953ef2b96303c7e1ee9044765d` |
| `d-i/forky/preseed.cfg` | `f4ae87376d8ed4e5d1b64af359ce7a72a9ba186cda74171ac833777fa3fa63a9` |
| `d-i/forky/receipt.json` | `6bac539a2b800bfcb606b7c94ec4b8fac8f02fbe46142523e168366f2eb79535` |
| `d-i/trixie/payload.tar.gz` | `0b649523fa2eca3a52a411c5e63331b08cd4648da0ad85140f8748ae4f59aa26` |
| `d-i/trixie/payload.manifest` | `b4b1f0bf9f96cd53835929e2e9c372e4e4840b953ef2b96303c7e1ee9044765d` |
| `d-i/trixie/preseed.cfg` | `3f832f29053d6508bfb1fa90660d6c9bc2efbab2a65d90a9a8ad13bd6007832f` |
| `d-i/trixie/receipt.json` | `6bac539a2b800bfcb606b7c94ec4b8fac8f02fbe46142523e168366f2eb79535` |

## Changed paths

```text
d-i/debian/hooks/installer/pre-pkgsel.d/91cuda-legacy-apt.sh
d-i/debian/scripts/common/modules/profiles.sh
d-i/debian/scripts/common/target.sh
d-i/debian/tests/test_installer_progress.py
d-i/forky/payload.manifest
d-i/forky/payload.tar.gz
d-i/forky/preseed.cfg
d-i/forky/receipt.json
d-i/trixie/payload.manifest
d-i/trixie/payload.tar.gz
d-i/trixie/preseed.cfg
d-i/trixie/receipt.json
docs/validation/installer-streaming-portability-20261114.md
```

Both suites' unchanged `source.sh` and `support-matrix.json` were also rewritten by the authorized generation command with identical bytes. The user's offline tooling was not edited.

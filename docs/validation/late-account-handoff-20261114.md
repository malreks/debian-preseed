# Late-command account handoff repair — 2026-11-14

The user reported CrowdSec failing because the resolved account environment was missing or unsafe. The supplied path was the installer-only late environment's `account.env`.

The compiled medium/full desktop plans in both suites confirm the broken ordering:

```text
os.shared -> os.crowdsec -> os.kernel -> desktop.storage -> desktop.software -> ...
```

Previously, `desktop.storage` published the resolved account file as a side effect of its shared late core. CrowdSec read that file before storage ran. The shared foundation resolved its own username for rendering but did not publish this file. Server foundation likewise did not provide the account snapshot needed by server Whisper. Several addon helpers instead downloaded public account policy into the resolved-account filename when it was absent. That policy intentionally contains no private username/home identity, so this fallback did not satisfy their input contract.

## Repair

`scripts/common/modules/profiles.sh` now owns `installer_prepare_late_account_env`. `scripts/late/dispatch.sh` invokes it before entering any selected late stage and exports the selected snapshot path. Publication is independent of storage family, role, stage ordering and stage completion markers. Both the parent dispatcher and the private publisher set the preparation operation context so failure finalization retains the correct attribution.

The publisher loads the authenticated compiled account policy and existing runtime account implementation. It resolves credentials through the same reader used by early account creation, including `primary_username=` / legacy alias handling and protected installer `PRESEED_PRIMARY_USERNAME`. It clears the inherited credential-ready flag so inherited identity cannot replace current validated input. Early account setup already requires the full account credentials; this repair reuses that existing contract.

The existing serializer emits 25 fields: identity, account policy, home paths and SSH/calendar settings. It omits primary/root passwords and the primary GPG passphrase. Credential variables and helper scratch values remain in the publisher's subshell. The private serializer can contain calendar settings; it is not described as a universally secret-free file.

The publisher uses a private workspace, a nonblocking directory lock, mode `0600`, restricted-data validation and an atomic rename. It checks destination ancestry before work and again before publication, rejects symlinks/nonregular destinations, and preserves the previous complete snapshot on preparation or rename failure. Cleanup names only its two private files and workspace. Cleanup failure returns 125 and retains the workspace/lock with a diagnostic. No installer directory, password or snapshot contents are logged.

The runtime serializer now explicitly propagates credential, validation, directory and write errors, including when an enclosing checked function disables shell errexit. It cannot mask a field-write error with a successful final chmod.

The shared late core and software, DevOps, Whisper and Tailscale fallbacks now use resolved preparation instead of downloading public policy as resolved state. No raw account-policy fallback remains under `scripts/late`. Core and Tailscale honor the same account/host override paths as the other consumers. The four addon data readers clear inherited username/home values before loading the snapshot. Server DevOps uses the resolved snapshot without a second identity override. CrowdSec retains its existing missing-file, symlink and username checks.

## Inspected shared scope

All 27 declared late providers were inventoried through `hooks/installer/class-dispatch.tsv` and authenticated FILE selectors:

- Common: `os.shared`, `os.crowdsec`, `os.kernel`, `os.crypto`, `os.uplinks`, `os.sharing`, `os.services`, `os.codex`, `os.firmware`, `os.timeshift`, `os.virtualization`.
- Desktop: `desktop.storage`, `desktop.software`, `desktop.session`, `desktop.devops`, `desktop.ch341a`, `desktop.tailscale`, `desktop.whisper`, `desktop.virtualization`.
- Server: `server.foundation`, `server.boot`, `server.hardware`, `server.services`, `server.devops`, `server.devops.tools`, `server.whisper`, `server.llama`.

The account handoff inventory covers dispatch, core, CrowdSec, software, DevOps, Whisper and Tailscale. Desktop session consumes the same core loader. The shared serializer's early d-i, Btrfs/F2FS partman, pre-pkgsel and late callers were inspected. Explicit entrypoint-required variables and stage-source existence were inventoried as source; this does not establish every conditional runtime input or downstream service behavior.

The shared software path includes Bitwarden, QoreDB, Obsidian, Tomat, Sleek, Postman, Discord, Tuta, Ledger, ChatGPT/Codex, Filen, Zoom and Tor Browser. Their account integration receives the same resolved identity through the repaired handoff. No application constructor, package/download policy, installed management wrapper, AppArmor authority or private Xwayland implementation changes here. The APT/media/English-metadata/PDiff/CUDA policies and the previous tee-free tty4 logger remain unchanged.

## Verification record

Baseline: clean commit `263cab4` (`fixed cuda legacy`). Recorded tools: Python 3.14.10, ShellCheck 0.11.0, GNU Make 4.4.1. The reported installation's exact image/package versions were not supplied and were not inferred from the development host.

- A standard-library-only source check passed under a 40-second outer deadline. It parsed the changed Python AST and performed 42 `/bin/sh -n` parses: 31 unique late-provider/shared shell sources and 11 embedded fixture programs/variants, with five-second parser deadlines. It verified source-line annotations, 25 unique serializer fields, explicit write-status propagation, absence of primary/root password fields, zero raw account-policy fallbacks in late scripts, and publication before the stage loop. It executed no repository shell body or test module. Earlier source-check iterations caught a fixture indentation mistake and an incorrect expected field count in the ad hoc checker; both were corrected before the passing check and build.
- `timeout --signal=TERM --kill-after=5s 120s make PYTHON=python3 build` passed. The reviewed generation-only recipe serialized the authorized flat suite products and ran no tests or target programs.
- A bounded archive/data inspection passed 22 exact source-byte comparisons for the eight changed runtime sources and three retained APT files in each suite. It checked all compiled account-policy views in both archives (52 checks), their required public policy fields, canonical home-root availability and absence of public username/home overrides. Receipt product hashes, preseed pins and suite payload/manifest equality matched.
- A separate 30-second archive/data check passed over all 22 compiled tuple plans and 932 present dependency edges. It confirmed the four medium/full suite plans place CrowdSec before storage. Account preparation now occurs before these lists, without changing the existing class dependency graph.
- `timeout --signal=TERM --kill-after=5s 120s python3 -B tools/post_change_check.py` passed after generation: 17 existing changed regular files, eight shell sources, one Python AST, 2353 release members, 2218 source-byte comparisons, 198 frontend comparisons, 319 runtime-placeholder producers and 52 APT source/preference contracts. The required audit is repeated after adding this record; the final task response records that final result.
- `git diff --check` passed.

Five isolated-only regression methods were added to `test_primary_account_contract.py`. They cover fresh-shell snapshot loading without a storage stage for both suites/roles and both username sources; primary/root password omission; mode `0600`; exact writer/rename status 42 and parser status 2; preservation of previous bytes; symlink rejection; another publisher's lock; retained evidence/status 125 after cleanup failure; and destination replacement before publication. Fetch/path authority is mocked inside the owned fixture. Credential parsing, restricted snapshot parsing and account serialization use the actual source. The fresh reader checks the shared data interface, not individual CrowdSec/vendor-service execution. All fixtures remain unexecuted.

Both delegated read-only sidecars failed before inspecting the checkout because encrypted context could not be hydrated. No independent reviewer result is claimed. The root agent performed review and integration.

No QEMU, VM, container, chroot, native fixture, installer replay, APT transaction, target service or installed management helper was executed. No native validation environment was created, and none requires cleanup. Host configuration, services and package state were not used or changed. Full late-command execution, installation, reboot and service behavior remain unverified. Source parsing and serialization consistency are not native acceptance evidence.

## Serialized identity

Release: `65c867c884794d5547c1858ee5c4cf369caf54b069971dbce520a25975e94482`.
Source fingerprint: `ed5092b31ae0ed1b8772824bbccc2eeae19c7726c5e3e003bda69e8ca0e544eb`.
Each suite payload contains 2353 members.

| Product | SHA-256 |
|---|---|
| `d-i/forky/payload.tar.gz` | `d7a50b498094f214d55c4ddcd4602a97c60aabe079b016260c63a2395f08f72c` |
| `d-i/forky/payload.manifest` | `05afbce292a07fe4c78edf4fe2bd09ae3fef5335c8543d69e73cd9b57e6e9839` |
| `d-i/forky/preseed.cfg` | `760b184805f3814edf6301376099f433fcb493b83d7f5dee7570015f04255099` |
| `d-i/forky/receipt.json` | `48ac57fdb6589303859eb1285421fa2c2bf8ed409020bf861e91ed5e5cba00ed` |
| `d-i/trixie/payload.tar.gz` | `d7a50b498094f214d55c4ddcd4602a97c60aabe079b016260c63a2395f08f72c` |
| `d-i/trixie/payload.manifest` | `05afbce292a07fe4c78edf4fe2bd09ae3fef5335c8543d69e73cd9b57e6e9839` |
| `d-i/trixie/preseed.cfg` | `2f040a167199c15db199f0576b8073e26bbfabe6beadcd1a361e38050a5fec11` |
| `d-i/trixie/receipt.json` | `48ac57fdb6589303859eb1285421fa2c2bf8ed409020bf861e91ed5e5cba00ed` |

## Changed paths

```text
d-i/debian/scripts/common/modules/profiles.sh
d-i/debian/scripts/late/core.sh
d-i/debian/scripts/late/devops/main-orchestration.sh
d-i/debian/scripts/late/dispatch.sh
d-i/debian/scripts/late/software.sh.tmpl
d-i/debian/scripts/late/tailscale.sh
d-i/debian/scripts/late/whisper.sh
d-i/debian/scripts/runtime/account.sh
d-i/debian/tests/test_primary_account_contract.py
d-i/forky/payload.manifest
d-i/forky/payload.tar.gz
d-i/forky/preseed.cfg
d-i/forky/receipt.json
d-i/trixie/payload.manifest
d-i/trixie/payload.tar.gz
d-i/trixie/preseed.cfg
d-i/trixie/receipt.json
docs/validation/late-account-handoff-20261114.md
```

Generation also rewrote each suite's unchanged `source.sh` and `support-matrix.json` with identical bytes. The user's offline tooling was not edited.

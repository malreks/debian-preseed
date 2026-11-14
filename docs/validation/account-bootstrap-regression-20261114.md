# Account bootstrap regression correction — 2026-11-14

Baseline: clean commit `5c08b71287c1d1cdf37e9f38e3722a457d24a4e0`.
The user reported Secure Boot pre-pkgsel failing to prepare its resolved
`account.env`. This is a regression introduced by the preceding account-handoff
change, not evidence of an older installer failure.

The new publisher called `bootstrap_source_module` for `FILE_RUNTIME_COMMON`
and `FILE_RUNTIME_ACCOUNT`. The resolver accepted common modules, runtime
**modules**, desktop components and DevOps modules, but neither runtime
entrypoint. It rejected the call before credentials could be resolved. The
previous unit fixture replaced the resolver with a mock and missed this
integration defect. Source comparison with the baseline confirms that both
requested entrypoints fall outside its allow-list; this comparison is static
evidence, not an executed installation replay.

## Corrected contract

- `scripts/common/bootstrap.sh` permits those two exact, selector-resolved,
  definition-only runtime entrypoints. Storage-family runtimes, the AWK parser
  and arbitrary runtime siblings remain outside that module interface.
  Authentication, relative-path validation, private staging, ownership, link,
  mode and authenticated-payload checks remain on the same resolver path.
- `scripts/common/modules/profiles.sh` loads the exact compiled host profile
  before account policy and runtime definitions. Canonical home roots no
  longer depend on caller inheritance. Module-load failures now identify the
  failed selector and source while retaining the original status. Cleanup
  includes the added private profile snapshot.
- `scripts/late/core.sh` separates public profile acquisition from resolved
  account publication. Profile/template initialization does not prepare an
  account. The account loader invokes the shared publisher after loading the
  profile, rejects unsafe/missing output, clears inherited identity/cache
  values and loads private credentials for its own caller. It does not rewrite
  the completed snapshot outside the publisher's lock.

The primary username still comes from `primary_username=` (including the
existing historical alias) or the protected installer credential file's
`PRESEED_PRIMARY_USERNAME`. No profile username fallback or target credential
file was introduced. Snapshot publication retains its private workspace,
nonblocking lock, restricted-data parser, mode `0600`, atomic rename,
previous-state preservation and retained-evidence cleanup failure path.

## Scope reviewed

The consumer inventory includes the pre-pkgsel Secure Boot hook; early d-i and
Btrfs/F2FS partman writers; late dispatch, Btrfs/F2FS storage, desktop session
and GRUB; CrowdSec, software, DevOps, Tailscale and Whisper; and all 27 declared
late providers in `class-dispatch.tsv`. All 62 inventoried selector-based
module calls, including the publisher's two dynamic selector choices, fit the
corrected resolver interface. The shared software identity path includes
Bitwarden, QoreDB, Obsidian, Tomat, Sleek, Postman, Discord, Tuta, Ledger,
ChatGPT/Codex, Filen, Zoom and Tor Browser. No component constructor,
download policy, AppArmor authority or private Xwayland policy changed.

`test_modular_installer.py` now consumes the actual flat suite products and a
minimal explicit fixture environment. Four new isolated-only methods cover
the real authenticated loader, rejected storage siblings, both suites/roles,
both username inputs, standalone preparation without inherited home roots,
fresh readers, pre-pkgsel/late core initialization and previous-snapshot
preservation when an authenticated runtime member is missing. Theme actions
are mocked in the core handoff fixture; storage and Secure Boot target actions
are outside it. The obsolete standalone loader fixture in
`test_initrd_credentials.py` was replaced by this broader integration coverage.
The publisher unit fixture in `test_primary_account_contract.py` now supplies
the additional public profile input. These fixtures were authored and parsed;
none was executed during this task.

## Observed verification

- A bounded standard-library-only source inspection confirmed the baseline
  allow-list rejects both runtime entrypoints and the corrected list accepts
  the 62 inventoried calls. It also checked four rejected non-module entries,
  profile-before-account ordering, publication cleanup members and source-line
  diagnostics. Seven owning shell sources, 19 embedded fixture shell programs
  and three changed Python ASTs parsed successfully. No repository shell body
  or test module was executed.
- A second bounded source check inventoried all 27 late providers and parsed
  37 unique shell sources with `/bin/sh -n`. It verified Secure Boot ordering,
  account publication before the selected late-stage loop, and absence of raw
  public-account-policy fallbacks under late scripts. The first inventory
  check's stage-column filter selected only the seven explicit owners; the
  second check used the actual TSV phase column and covered the provider set.
- `timeout --signal=TERM --kill-after=5s 120s make PYTHON=python3 build`
  passed using the reviewed generation-only recipe. It serialized 2353 payload
  members for both suites.
- Bounded archive inspection passed exact changed-source, manifest, receipt
  and preseed-pin comparisons in both archives. It checked all 52 account
  policy views, required account policy fields and canonical home roots. It
  also confirmed the retained media mount/trust, English-only Translation and
  no-PDiff drop-ins. An initial inspection incorrectly expected the media
  source template to contain rendered paths; it was corrected to resolve the
  existing placeholder from the compiled runtime contract. No source policy
  change was needed for that assertion.
- The required command
  `timeout --signal=TERM --kill-after=5s 120s python3 -B tools/post_change_check.py`
  passed after generation: 14 changed files before this record, three shell
  sources, three Python ASTs, 2353 release members, 2218 exact source
  comparisons, 198 frontend comparisons, 22 role plans, 319 runtime placeholder
  producers and 52 APT source/preference contracts. It is repeated after adding
  this record; the final response records the final result.
- `git diff --check` passed.

The delegated read-only sidecar failed before inspection because encrypted
context hydration failed. No independent review result is claimed.

No QEMU, VM, container, chroot, native fixture, installer replay, package
transaction, target service or installed management helper was executed. No
native validation environment was created and none requires cleanup. Target
image/package versions were not supplied and were not inferred from the
development host. Full installation, Secure Boot/DKMS target actions, reboot
and live service behavior remain unverified. The user's offline tooling was
not changed.

## Generated identity

Release: `d06a3d6c5ae0f04d622a5e037d1a93be192fef837a04dfd6178cd9d9fc9e4889`.
Source fingerprint: `ef7a59433b8336156399a2c90b54795a2da9ac185b02f5d0711080255df19895`.

| Product | SHA-256 |
|---|---|
| Both `payload.tar.gz` files | `bac11fc9522d0ad57fe25d32b488031f05776265b9f8e06f3fa5b6b570da66f1` |
| Both `payload.manifest` files | `d01c573d51763fd128c2fe763e08f07919d6489add81f15b0a223cf9d2b4a687` |
| Forky `preseed.cfg` | `2baa96e2f6919c2ed29a76278e3f266417252032cc7867db16e2fa818a028d5a` |
| Trixie `preseed.cfg` | `9fd89c3680f4687c0138b670e44fda9715f3505935098c315d36b0fb78a1f079` |
| Both `receipt.json` files | `de7c3da414a2bafbab3821ff9747adad8013ce7ba245284947e77848be11cce5` |

Changed runtime owners are the three files listed above. Changed fixture
owners are `d-i/debian/tests/{test_modular_installer.py,test_primary_account_contract.py,test_initrd_credentials.py}`.
Generated changes are each suite's `payload.tar.gz`, `payload.manifest`,
`preseed.cfg` and `receipt.json`. Generation rewrote each suite's `source.sh`
and `support-matrix.json` with identical bytes. This record is the remaining
changed file.

# Profile deletion and Partman regression evidence — 2026-11-15

## Recorded source and supplied evidence

Base revision: `c9abda1365545db376bd06bb00dfd02769de4941`; changes remain
uncommitted. This follow-up preserves the existing five-objective implementation
and corrects its ordinary-profile Partman regression. The earlier
`profile-storage-offline-20261115.md` records the preceding snapshot, not the
acceptance status or hashes of this revision.

The user-supplied installer evidence has these identities:

| Input | Lines | SHA256 |
| --- | ---: | --- |
| `todo/installer.log` | 141 | `99a67bd641c7422ebfab8a2c1c30525035e774e442bd308cf6e6388e363efed8` |
| `todo/syslog` | 1409 | `0720af47ad011756ce45150f34e2f7ca7e7f20a4a3d1d81e123d7ee8c99eab6c` |

The logs identify ordinary `btrfs-de-p15s`, unencrypted root/home and disabled
ceiling/reuse controls. They executed the previous generated release
`02a0438d8db0aaaa67eb8588e7b57da923059ed9dcda4e73b67d0017eb84144a`.
This was an implementation regression, not evidence of a stale served product.
Installer media used the Trixie `6.12.107+deb13-amd64` kernel; the target selected
Forky. No new target image or installed target package versions were obtained.
Raw command-line credentials and acquisition URLs are excluded from this record.

## Diagnosis and corrections

The preceding implementation removed the native disk/method answers from every
profile and selected the new fixed-layout adapter even for an ordinary fresh
installation with both controls disabled. `installer.log:138` confirms that
selection after GPT reinitialization; the supplied logs do not show a successful
application of that adapter or a completed installation.

Ordinary unencrypted fresh installations now use the established
`partman-auto/disk` and `partman-auto/method=regular` contract and the growing-root
recipe maximum. Ordinary encrypted fresh installations retain the selected-disk
free-extent packaged `autopartition` route. Neither native route installs the
fixed-layout commit guard. Fresh preparation retains its prior LVM/MD discovery
marker initialization, while ceiling, append and reuse use the fixed adapter.
The adapter path explicitly clears inherited native disk/method answers before
selecting its menu choice; those answers otherwise take precedence in Partman.

The mode selection is shared by Btrfs and F2FS, desktop and server:

| Profile | Ceiling | Reuse | Authority |
| --- | --- | --- | --- |
| Ordinary | false | false | Established fresh installation. |
| Ordinary | true | false | Fresh layout ending below the absolute disk ceiling. |
| Duo/Trio | false | false | Preserve existing GPT/ESP; append after the last existing partition. |
| Duo/Trio | true | false | Preserve existing GPT/ESP; append below the absolute ceiling. |
| Any | either | true | Reuse exact existing non-EFI profile partitions starting at `PARTMAN_REUSE_START`; ignore the ceiling. |

The fixed adapter had overwritten descriptor 3 for recipe input, conflicting
with Debian's cdebconf protocol. Recipe iteration now leaves descriptors 3–7
untouched. The creation request normalizes the recipe's `free` token to the
package-supported `ext2` partition-creation token; actual filesystem and usage
metadata still come from `setup_partition`. The adapter loads the frozen
installer context before using its selected profile and paths.

Before commit, every original partition must still exist at its recorded exact
extent. This catches deletion as well as resizing; iterating only current
Partman entries would miss a deleted partition. Foreign partitions and the
preserved ESP must have no format flag. Incomplete applications retain their
running state and cannot be retried or committed automatically.

F2FS recipes retain `ext4` as their fourth partition-creation field, matching the
packaged recipe/libparted interface. Their explicit `filesystem{ f2fs }` field,
F2FS backend and finish hook select `mkfs.f2fs` and F2FS mounts for root/home.
Changing that creation token alone would not establish F2FS support.

## Other supplied log diagnostics

The inherited-descriptor `pvs` warnings already occur at `syslog:978` before the
repository bootstrap, and recur before its Partman early hook. They are
packaged installer LVM discovery diagnostics. `syslog:1401` reports no matching
physical volumes after the target was emptied; it does not establish an LVM
recipe or the cause of the partitioning stop. Protocol descriptors must not be
closed merely to hide those messages. The separate adapter descriptor collision
above was found in source review; the logs do not prove that branch executed.

AX201 firmware acquisition recovers: the installer installs
`firmware-iwlwifi_20250410-2_all.deb` at `syslog:1144`, loads firmware
`77.2753b721.0` at line 1158, and reports no missing firmware at lines 1168,
1176, 1336 and 1341. Early PCI ROM allocation and Secure Boot lockdown messages
do not justify a speculative hardware or security-policy change. The FAT dirty
volume warning at line 1409 concerns removable `sda1`, not the selected NVMe;
no media repair was attempted.

## Profile management

`tools/profile.py` now implements creation and deletion, including the no-argument
`make profile` action prompt. Deletion selects exact registrations, previews
every owned member, validates the remaining complete candidate, and updates
both suites, the registry and source selectors together. Templates and unrelated
profiles are outside the deletion set.

A normal profile is protected while either corresponding Duo/Trio variant would
remain. Interactive deletion offers to include those variants first; declining
cancels all writes. Explicit command-line deletion requires all variants or
`--with-variants`; `--yes` alone never expands scope. Final interactive removal
requires typing `delete`. Publication uses one ownership lock, identity/byte/mode
checks and synchronized private recovery copies. Uncertain mutations retain
recovery material and return 75 instead of retrying.

Ten bounded generation/preview/cancellation paths were executed, covering
creation compatibility, individual/group deletion previews, protected normal
profiles, partial variant selection, final cancellation, and conflicting flags.
Observed exit statuses matched each path. SHA256/mode snapshots of 74 profile,
class, registry and selector files were unchanged after these non-publishing
commands. No existing profile was actually created or deleted.
Final-source previews repeated protected-normal rejection (exit 1), complete
group deletion (exit 0) and individual Trio deletion (exit 0), again preserving
the SHA256 values and modes of all 74 source members.
Creation rejects `duo` and `trio` as host names before source capture: otherwise
a new ordinary profile could accidentally end in a multiboot selector. Both
bounded CLI previews returned the expected status 1 without publication.

## Verification and limits

- Python 3.14.10 parsed the profile tool and three changed fixture modules as
  AST data. Separate `/bin/sh -n FILE` invocations parsed all six changed storage
  shell files without executing them; every invocation exited 0.
- Data-only checks passed for all 34 profile environments, six registered
  Duo/Trio pairs and both suite class sets, direct os-prober declarations,
  81 required P15s/Duo policy equalities, and eight root-template scalar renders.
  All 76 partition-control values across 19 compiled profiles in each suite
  match their authored host overrides (152 checked values in total).
- The new policy fixture covers 48 profile/control combinations using the
  actual suffix selector. Other fixtures cover missing ESP/malformed geometry,
  ignored reuse ceilings, missing original Partman partitions, source publication
  failure/recovery and concurrent identity changes. These fixtures were authored
  and AST parsed; they were not executed.
- `timeout --signal=TERM --kill-after=5s 180s make build` exited 0 after the final
  preservation fix. Both payloads contain 2,421 members and have identical bytes.
- The changed-file static audit passed for 112 regular files, eight Python ASTs,
  58 shell sources and 40 structured files at the final installer payload
  revision. It also checked 22 role-combination plans and 2,421 payload members.
  The command passed again after the final profile-name guard and offline
  deferral record. `git diff --check` also exited 0.
- The first follow-up offline acquisition refused publication when source
  identity changed during generation. Its output was not accepted. A stable
  intermediate archive was checksum consistent but predated the final debconf
  answer-precedence correction; current-source byte comparison rejected it.
  The user then deferred further offline generation. The task-owned job was
  stopped through a verified pidfd and exited 143. No completed final-revision
  offline generation is claimed, and no further generation was started.

Native tests were not run on the host. No reviewed disposable test image was
prepared for this follow-up, and the repository's isolation guards were retained.
Actual Partman protocol execution, disk-byte preservation, formatting, encrypted
reinstall, GRUB detection and a complete installation remain unverified for this
revision. Source checks and bundle consistency do not establish those outcomes.
The independent Trixie desktop suite gate remains; private Zoom/Discord Xwayland,
application policy and host state were not changed. The referenced historical
`debian-preseed-de-audit.md` is absent from the checkout.

## Generated identities

Installer release: `a468089f809584cf7bcd6239d9c0a0bf8994e7fb6416e17b66718ae25be2d8e8`.
Captured-input fingerprint: `e38428a4036e9409598a00ce3189736ea5c12917f8ec0e17916c02806f2f6007`.
Both suite payload SHA256 values:
`bb7e6848efd24af1653d95326c033efba8f5d48e93dff74ed0a40670c3aaefdc`.

| Changed owner or fixture | SHA256 |
| --- | --- |
| `tools/profile.py` | `27a9902cbfd65822907ae097892b73f89f7673833069fb1e36d78ed9e97598f0` |
| `scripts/runtime/modules/layout-policy.sh` | `04675aca857df29882c758ed1cb04895f2ed78f5c3eb1ad949f476c29840a883` |
| `hooks/installer/partman/layout-option.sh` | `5ef3ade54a00e17229d6c9cf6dcdd2a65866bc0f7dae9e2755f86f327c127140` |
| `tests/test_partition_policy.py` | `199bf4bb4ce1ca9c5f8a489c798946e67b2b3fdbf05d22eb5faf2088ed67a78b` |
| `tests/test_profile_management.py` | `a037081f42c735ae96aac9a73568165a73c5b7ece8c391d59a338329917f6d6f` |

Storage/test paths in this table are relative to the shared Debian source root.
Changed follow-up owners also include `hooks/installer/partman/early.sh`, both
filesystem runtime emitters, all four root recipe templates, the shared late
zram size-tolerance consumer, `tests/test_dynamic_storage_sizing_20260921.py`,
`README.md` and `docs/implementation/partitioning-profiles.md`. The authorized
normal suite products are current. Offline regeneration is deferred, and the
retained offline archive is
the intermediate release
`f7fcfa6e6b453142a0ac5a06dfa3ea40a4d82e0b014596ce7164e40120e5893d`,
SHA256 `2aebc66c0de685adfd4664b98d8b315a7678cb4344d027dab27259f75184cbea`.
It lacks the last shared driver-answer correction. Interrupted generation work
remains in the private workspace child `generation-61wn4nzz`; no broad cleanup
or cleanup-success claim was made.

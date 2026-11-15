# Profile, storage and offline generation evidence — 2026-11-15

## Source identity

Base revision: `c9abda1365545db376bd06bb00dfd02769de4941`. The checkout began clean on its existing authored branch; changes remain uncommitted.
Installer release: `02a0438d8db0aaaa67eb8588e7b57da923059ed9dcda4e73b67d0017eb84144a`.
Installer captured-input fingerprint: `0513d6e557566a5f5fe099727717f977d567837b3c00fb2aa676f7b012f6c113`.
Offline release: `cd5a966fb699e267f37716b13d8fb25826232b00fa366956229a8c420edd86ed`. Its identity additionally binds the standalone offline compiler.
Python used for generation/source parsing: `3.14.10`. No target image or installed target package versions were obtained.

## Implemented contracts

- Btrfs and F2FS child-shell operation logging now follows common-library initialization. The pre-initialization `installer_info` call explained the reported status 127 at the parent dispatch context.
- Profile suffix guards are removed. Nineteen profiles are registered, including six Trio copies paired with every existing Duo. Both suite class trees include os-prober directly in every Duo/Trio class; both optional dualboot class files and their registrations/selectors are removed.
- Eighty-one requested P15s fields match exactly between ordinary and Duo profiles. The Whisper acquisition URL also matches the synchronized model/hash. Trio and desktop templates inherit the corrected policy.
- All 34 profile environments, including twelve templates and shared defaults, explicitly declare the ceiling/reuse controls. Policy values are validated, frozen in installer context/plan and checked before layout planning.
- The first FAT GPT ESP by byte position is reused without formatting. New multiboot partitions use tail free space after the final existing extent; lower-numbered GPT holes are handled separately from physical placement.
- Ceilings use absolute decimal-MB disk coordinates. Reuse overrides the ceiling and preserves the complete existing partition geometry, selecting only the profile role count starting at PARTMAN_REUSE_START.
- The shared Partman adapter uses fixed-size creation, validates preserved geometry/format authority and blocks incomplete commits. Old deletion of every partition after a start number is removed. Running markers retain uncertain attempts, and late providers refuse missing frozen layouts.
- Server and desktop GRUB consumers follow the multiboot profile policy; shared temporary installer os-prober dispatch is registered. EFI preservation remains distinct from enabling OS probing.
- Profile generation validates the entire candidate, creates both suite class sets and environments, updates registry/selectors, refuses existing names and rolls back owned writes on caught failures. Preview mode writes no profile files.
- Offline generation uses the repository work selector or an explicit ordinary-disk override, a private generation directory, memory-only SQLite temporary storage, compact WITHOUT ROWID tables and an 8 GiB database cap. The completed work directory was empty after cleanup.

## Observed validation

- `timeout --signal=TERM --kill-after=5s 120s make build` — exit 0; 2,421 payload members. Forky and Trixie payload bytes are identical.
- `timeout --signal=TERM --kill-after=5s 180s python3 -B tools/post_change_check.py` — PASS against the rebuilt source/products before this evidence file and the final offline archive were added. It covered 108 changed regular files, 58 shell sources, seven Python ASTs, both class registries, generated pins, source equality and shared policy/rendering contracts. The completion audit is run again with those final additions.
- `git diff --check` — exit 0.
- `python3 -I -B tools/profile.py --filesystem btrfs --family both --multiboot both --name hp55 --preview` — exit 0; six candidate registrations and both suite class sets validated, no publication.
- The corresponding F2FS preview — exit 0. The interactive `python3 -I -B tools/profile.py --preview` also accepted answers f2fs / both / both / hp55 and exited 0 without publication.
- Inline standard-library source/data checks confirmed all registrations/classes, six Trio pairs, direct os-prober declarations, all four controls in every environment, 81 matching requested P15s fields, and both new shared helpers in both payloads.
- `timeout --signal=TERM --kill-after=20s 1900s make offline` — final stable-source run exited 0 and published the archive. Earlier acquisition correctly refused publication when source inputs changed while it ran; that intermediate result was not used.
- Offline verification read the archive as data without extraction, parsed all four catalogs and bundle.json, verified all 2,698 SHA256SUMS entries, bounded members/expanded bytes, and confirmed no nested payload or package archives. There are 2,699 members and 69,769,281 expanded bytes.

The required shared-consumer inspection included Bitwarden, QoreDB, Obsidian, Tomat, Sleek, Postman, Discord, Tuta, Ledger, ChatGPT/Codex, Zoom, Filen and Tor, desktop/server providers, EFI/GRUB/signing, raw swap/zram validation and both filesystem families. Application startup and target policy were inspected as source only.

## Offline catalog limits

Official package candidates: 6844; vendor candidates: 221; source records: 3685; Git entries: 150; HTTP entries: 192.
`catalog_complete=false` and `exact_sources_complete=false` remain explicit. These are catalog coverage limits, not storage/publication failures.
Official metadata reports 4 unresolved dependency records; vendor metadata reports 220 missing exact source records. Request coverage includes conditional-policy cases rather than fabricating a unique package choice.

## Deferred native acceptance

No unittest discovery, executable regression fixture, installer hook, VM/container/chroot installation, live desktop/service check or host-management helper was executed. Added/updated regression fixtures were parsed and reviewed, not reported as passing runtime tests. No host disk, package state, service, security policy or network configuration was modified.
Actual Partman protocol execution, partition-byte preservation, fresh/append/reuse/ceiling matrices, malformed GPT rejection, replacement races, encrypted reinstall, interrupt/retry paths, GRUB discovery and complete unattended installation remain unverified for this revision. They require the separately reviewed disposable-image boundary, recorded image/package identities, hard timeout and cleanup evidence.
The independent Trixie desktop Labwc/Xwayland suite-policy gate, arm64 qualification limits and F2FS/Technitium quota restriction remain. No Xwayland implementation or private-app eligibility was changed. Pending external enrollment remains informational.

## Generated product hashes

| Product | Bytes | SHA256 |
| --- | ---: | --- |
| `d-i/forky/payload.tar.gz` | 11750130 | `d9983daedcaeda666bfc932073fae888ffdefbcdc064ac8759f6d2b2f1cd815b` |
| `d-i/forky/payload.manifest` | 320107 | `9154c3c136c6be96262e944aa33092b4c91fb5d6b1cb331eb9b6ca263cdc7722` |
| `d-i/forky/preseed.cfg` | 138359 | `baeb8cf4f4662142d8d247bfedad8a1ea937e13e8853f452fa0c0cfb633a625c` |
| `d-i/forky/receipt.json` | 336600 | `c7a25302d2400b9eafcf8953d175c609809fff60c5dc67c5a651b9f8ce8cd257` |
| `d-i/forky/source.sh` | 56885 | `8a065d4000b96f158338663fae6ae4d95949272948154a36cf33fb85ff1dce28` |
| `d-i/forky/support-matrix.json` | 13080 | `ff0b2a12aec48418f02ad6dc591db5463826187eb4ac1fa836a1f70f05ab782a` |
| `d-i/trixie/payload.tar.gz` | 11750130 | `d9983daedcaeda666bfc932073fae888ffdefbcdc064ac8759f6d2b2f1cd815b` |
| `d-i/trixie/payload.manifest` | 320107 | `9154c3c136c6be96262e944aa33092b4c91fb5d6b1cb331eb9b6ca263cdc7722` |
| `d-i/trixie/preseed.cfg` | 138364 | `a08850a2acd39ba0276b615b567383b31db4d0151123600dfa4d3d5d4e440509` |
| `d-i/trixie/receipt.json` | 336600 | `c7a25302d2400b9eafcf8953d175c609809fff60c5dc67c5a651b9f8ce8cd257` |
| `d-i/trixie/source.sh` | 56885 | `8a065d4000b96f158338663fae6ae4d95949272948154a36cf33fb85ff1dce28` |
| `d-i/trixie/support-matrix.json` | 13080 | `ff0b2a12aec48418f02ad6dc591db5463826187eb4ac1fa836a1f70f05ab782a` |
| `offline/payload.tar.gz` | 18961744 | `38121e5c523e0cc38bae876f4c24870cc0ff2b7271dc990a917a7b3010a2aad4` |

## Exact changed-path inventory

This inventory includes additions, modifications and the two class-file deletions. Byte-identical regenerated products appear in the hash table even if Git reports no content change.

- `Makefile`
- `README.md`
- `d-i/debian/catalog/selection.json`
- `d-i/debian/hooks/installer/class-dispatch.tsv`
- `d-i/debian/hooks/installer/d-i/early.sh`
- `d-i/debian/hooks/installer/di.env`
- `d-i/debian/hooks/installer/partman/btrfs-early.sh`
- `d-i/debian/hooks/installer/partman/early.sh`
- `d-i/debian/hooks/installer/partman/f2fs-early.sh`
- `d-i/debian/hooks/installer/partman/finish.d/99-storage-layout.sh`
- `d-i/debian/hooks/installer/partman/layout-option.sh`
- `d-i/debian/hooks/installer/pre-pkgsel.d/88temporary-os-prober.sh`
- `d-i/debian/hosts/README.md`
- `d-i/debian/hosts/profiles/desktop/btrfs-de-duo.env`
- `d-i/debian/hosts/profiles/desktop/btrfs-de-flex-duo.env`
- `d-i/debian/hosts/profiles/desktop/btrfs-de-flex-trio.env`
- `d-i/debian/hosts/profiles/desktop/btrfs-de-flex.env`
- `d-i/debian/hosts/profiles/desktop/btrfs-de-p15s-duo.env`
- `d-i/debian/hosts/profiles/desktop/btrfs-de-p15s-trio.env`
- `d-i/debian/hosts/profiles/desktop/btrfs-de-p15s.env`
- `d-i/debian/hosts/profiles/desktop/btrfs-de-trio.env`
- `d-i/debian/hosts/profiles/desktop/btrfs-de.env`
- `d-i/debian/hosts/profiles/desktop/f2fs-de-hp14-duo.env`
- `d-i/debian/hosts/profiles/desktop/f2fs-de-hp14-trio.env`
- `d-i/debian/hosts/profiles/desktop/f2fs-de-hp14.env`
- `d-i/debian/hosts/profiles/desktop/f2fs-de-x360-duo.env`
- `d-i/debian/hosts/profiles/desktop/f2fs-de-x360-trio.env`
- `d-i/debian/hosts/profiles/desktop/f2fs-de-x360.env`
- `d-i/debian/hosts/profiles/desktop/shared-de.env`
- `d-i/debian/hosts/profiles/server/btrfs-srv-flex-duo.env`
- `d-i/debian/hosts/profiles/server/btrfs-srv-flex-trio.env`
- `d-i/debian/hosts/profiles/server/btrfs-srv-flex.env`
- `d-i/debian/hosts/profiles/server/f2fs-srv-hp14.env`
- `d-i/debian/hosts/profiles/server/shared-srv.env`
- `d-i/debian/hosts/profiles/shared.env`
- `d-i/debian/hosts/profiles/templates/btrfs-desktop-duo.env`
- `d-i/debian/hosts/profiles/templates/btrfs-desktop-trio.env`
- `d-i/debian/hosts/profiles/templates/btrfs-desktop.env`
- `d-i/debian/hosts/profiles/templates/btrfs-server-duo.env`
- `d-i/debian/hosts/profiles/templates/btrfs-server-trio.env`
- `d-i/debian/hosts/profiles/templates/btrfs-server.env`
- `d-i/debian/hosts/profiles/templates/f2fs-desktop-duo.env`
- `d-i/debian/hosts/profiles/templates/f2fs-desktop-trio.env`
- `d-i/debian/hosts/profiles/templates/f2fs-desktop.env`
- `d-i/debian/hosts/profiles/templates/f2fs-server-duo.env`
- `d-i/debian/hosts/profiles/templates/f2fs-server-trio.env`
- `d-i/debian/hosts/profiles/templates/f2fs-server.env`
- `d-i/debian/repo.env`
- `d-i/debian/scripts/common/modules/context-target.sh`
- `d-i/debian/scripts/common/modules/installation-plan.sh`
- `d-i/debian/scripts/common/modules/profiles.sh`
- `d-i/debian/scripts/late/btrfs-family.sh`
- `d-i/debian/scripts/late/core.sh`
- `d-i/debian/scripts/late/f2fs-family.sh`
- `d-i/debian/scripts/late/grub.sh`
- `d-i/debian/scripts/late/zram-swap.sh`
- `d-i/debian/scripts/preseed/answers.sh`
- `d-i/debian/scripts/runtime/btrfs.sh`
- `d-i/debian/scripts/runtime/common.sh`
- `d-i/debian/scripts/runtime/f2fs.sh`
- `d-i/debian/scripts/runtime/modules/classes.sh`
- `d-i/debian/scripts/runtime/modules/layout-policy.sh`
- `d-i/debian/scripts/runtime/templates/btrfs-02.recipe.tmpl`
- `d-i/debian/scripts/runtime/templates/btrfs-03.recipe.tmpl`
- `d-i/debian/scripts/runtime/templates/f2fs-02.recipe.tmpl`
- `d-i/debian/scripts/runtime/templates/f2fs-03.recipe.tmpl`
- `d-i/debian/scripts/server/boot.sh`
- `d-i/debian/tests/test_dynamic_storage_sizing_20260921.py`
- `d-i/debian/tests/test_env_publication_20260919.py`
- `d-i/debian/tests/test_late_profile_assets.py`
- `d-i/debian/tests/test_partition_policy.py`
- `d-i/forky/classes/class-profile/desktop/btrfs-de-duo.cfg`
- `d-i/forky/classes/class-profile/desktop/btrfs-de-flex-duo.cfg`
- `d-i/forky/classes/class-profile/desktop/btrfs-de-flex-trio.cfg`
- `d-i/forky/classes/class-profile/desktop/btrfs-de-p15s-duo.cfg`
- `d-i/forky/classes/class-profile/desktop/btrfs-de-p15s-trio.cfg`
- `d-i/forky/classes/class-profile/desktop/btrfs-de-trio.cfg`
- `d-i/forky/classes/class-profile/desktop/f2fs-de-hp14-duo.cfg`
- `d-i/forky/classes/class-profile/desktop/f2fs-de-hp14-trio.cfg`
- `d-i/forky/classes/class-profile/desktop/f2fs-de-x360-duo.cfg`
- `d-i/forky/classes/class-profile/desktop/f2fs-de-x360-trio.cfg`
- `d-i/forky/classes/class-profile/server/btrfs-srv-flex-duo.cfg`
- `d-i/forky/classes/class-profile/server/btrfs-srv-flex-trio.cfg`
- `d-i/forky/classes/class-select/optional/dualboot.cfg`
- `d-i/forky/payload.manifest`
- `d-i/forky/payload.tar.gz`
- `d-i/forky/preseed.cfg`
- `d-i/forky/receipt.json`
- `d-i/trixie/classes/class-profile/desktop/btrfs-de-duo.cfg`
- `d-i/trixie/classes/class-profile/desktop/btrfs-de-flex-duo.cfg`
- `d-i/trixie/classes/class-profile/desktop/btrfs-de-flex-trio.cfg`
- `d-i/trixie/classes/class-profile/desktop/btrfs-de-p15s-duo.cfg`
- `d-i/trixie/classes/class-profile/desktop/btrfs-de-p15s-trio.cfg`
- `d-i/trixie/classes/class-profile/desktop/btrfs-de-trio.cfg`
- `d-i/trixie/classes/class-profile/desktop/f2fs-de-hp14-duo.cfg`
- `d-i/trixie/classes/class-profile/desktop/f2fs-de-hp14-trio.cfg`
- `d-i/trixie/classes/class-profile/desktop/f2fs-de-x360-duo.cfg`
- `d-i/trixie/classes/class-profile/desktop/f2fs-de-x360-trio.cfg`
- `d-i/trixie/classes/class-profile/server/btrfs-srv-flex-duo.cfg`
- `d-i/trixie/classes/class-profile/server/btrfs-srv-flex-trio.cfg`
- `d-i/trixie/classes/class-select/optional/dualboot.cfg`
- `d-i/trixie/payload.manifest`
- `d-i/trixie/payload.tar.gz`
- `d-i/trixie/preseed.cfg`
- `d-i/trixie/receipt.json`
- `docs/implementation/class-selection.md`
- `docs/implementation/partitioning-profiles.md`
- `docs/validation/profile-storage-offline-20261115.md`
- `offline/payload.tar.gz`
- `tools/class_compiler.py`
- `tools/offline.py`
- `tools/profile.py`

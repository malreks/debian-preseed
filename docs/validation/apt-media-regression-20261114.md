# APT installation-media regression — 2026-11-14

The user reported: “An attempt to configure apt to install additional packages from the media failed.” This is the `apt-setup/cdrom/failed` error, raised by Debian's `40cdrom` generator when its media addition or identification fails. The supplied message does not contain the failing command's stderr or identify the installer image version.

Source inspection found a concrete regression in the preceding change: the complete target APT directory was replaced before this media scan. That removed native `00CDMountPoint`, `00trustcdrom`, `00NoMountCDROM` and temporary verification configuration. In particular, Debian intentionally keeps NoMount for ISO/hybrid media and conditionally removes it when physical media can be mounted. Removing that state before the generator runs can break the media operation even though the selected target repositories use the network.

Primary source references: [base-installer 1.226 library](https://sources.debian.org/src/base-installer/1.226/library.sh/), [Trixie apt-setup 1:0.198 media generator](https://sources.debian.org/src/apt-setup/1:0.198/generators/40cdrom), and [apt-setup generator dispatcher](https://sources.debian.org/src/apt-setup/1:0.198/apt-setup/). These public sources identify the contract; they do not establish the image version used by the reported installation. Forky's indexed apt-setup version is 1:0.201, but its generator contents were unavailable through the documentation reader.

## Corrected ownership and timing

- The first network update adapter, base-installer hook and apt-setup preference generator now request `bootstrap` publication. That phase stages the authenticated `25no-pdiffs` and `99noinstall-recommends` files while preserving the other current regular native APT fragments and their modes. It takes the existing private directory backup before publication.
- Bootstrap copies the current active configuration, never the backup. A second bootstrap publication therefore preserves an existing `00NoMountCDROM` for ISO/hybrid media and does not recreate it after Debian removes it for physical media. Native temporary verification/debconf configuration remains available through pkgsel.
- Complete managed replacement starts in the shared late foundation, after apt-setup and pkgsel. Late storage maintenance repeats it, and finish-install publishes the final set and suite default-release. Original fragment bytes remain in `apt.conf.d.bak`; later passes archive previously unseen filenames.
- Both suites explicitly own `00CDMountPoint` and `00trustcdrom` in their common APT trees. The shared renderer resolves the canonical target media path, and the installed files use the requested block layout and `APT::Authentication::TrustCDROM "true";`. These media fragments are retained in the final target configuration. `00installer-policy` no longer disables CD-ROM trust.
- The target media path is owned by `DIR_MEDIA` and `DIR_MEDIA_CDROM` in the canonical runtime contract, registered in the existing placeholder map. Both new files have authenticated FILE selectors. The same common files feed desktop and server policy without duplicate role owners.
- English-only Translation metadata, disabled PDiffs, no Recommends/Suggests, scoped CUDA-legacy exceptions and the prior account/ZRAM/GRUB/tty4 fixes remain part of the source. Network repository authentication defaults remain strict. CD-ROM source selection continues to follow the existing network-target policy; this repair restores media setup prerequisites without suppressing the error prompt.

## Verification boundary

No QEMU, VM, container, chroot, repository fixture, APT transaction, media scan, installed helper or host-management operation was executed for this repair. Regression cases were authored for both suites, both roles, ISO/hybrid preservation, conditional physical-media removal, subsequent bootstrap publication, late cleanup, backup preservation and native mode preservation. They remain unexecuted and require the repository's isolated runner.

These source/data checks cannot establish that a native installer or a particular physical/ISO medium succeeds.

## Observed checks

- `timeout --signal=TERM --kill-after=5s 120s make PYTHON=python3 build` completed successfully after the requested block formatting. It was pure serialization and ran no tests or target helpers.
- An independent standard-library source/data check inspected all six publication callers and verified their explicit phases. It parsed 54 selected APT file views across all four suite/role combinations, rendered the media path as `/media/cdrom`, and checked CD-ROM trust enabled, network authentication defaults strict, language selection exactly `en`, Translation targets enabled and PDiffs disabled. This used a documented-grammar model, not libapt.
- All 18 managed hook command strings and the embedded fixture setup passed `/bin/sh -n` under a minimal environment. Syntax parsing did not execute those programs.
- Eight pure data models covered the two suites, two roles and conditional physical/ISO media state. They checked native media and verification bytes/modes, no resurrection of a removed NoMount file, late removal of transient/default fragments, explicit permanent CD-ROM fragments and preservation of original backup data. They did not execute the shell publisher; the authored functional fixtures remain unexecuted.
- Archive inspection resolved the media files through the authenticated FILE selectors, confirmed that all four authored media members were in each payload with matching source bytes, and checked their rendered content. Both suite payloads and manifests were byte-identical. An initial probe assumed an unprefixed archive name and failed; the selector-based inspection passed using the actual `frontends/` namespace.
- `timeout --signal=TERM --kill-after=5s 120s python3 -B tools/post_change_check.py` passed: 69 existing changed regular files, 22 shell sources, 5 Python AST parses, 2353 current release members, 2218 source-byte comparisons, 198 frontend comparisons, 319 used runtime-placeholder producers and 52 APT source/preference contracts. The same required audit is repeated after this evidence update; its final result is reported in the task response.
- `git diff --check` passed, including the check inside the required static audit.

## Serialized identity and artifacts

Source release: `3fa3fa98f7cf41dbc255260a1653f738c46a3cb3d5d12913c979e9f85a2d99aa`.
Source fingerprint: `1ad730375f05446f539768710e9152d8bbb95f3e30cdad2d4fa3771db03eb6cf`.
Each payload contains 2353 members.

| Product | SHA-256 |
|---|---|
| `d-i/forky/payload.tar.gz` | `fb92a6588fe466f7c8d796a47e6f65ce951bf06343ab34bf4de2f2e42cd30590` |
| `d-i/forky/payload.manifest` | `2aa129dee991b0f00959d39d8fa6078b4f32844b465064fc433043c92f90928f` |
| `d-i/forky/preseed.cfg` | `cfda59c75e970be751b13a98f807c00519a69191dd82a9ff82542a23e9115ad4` |
| `d-i/forky/receipt.json` | `227a8a451b32b34f555861ff9e6261206da3a47469b1ee45930cd9559441706d` |
| `d-i/trixie/payload.tar.gz` | `fb92a6588fe466f7c8d796a47e6f65ce951bf06343ab34bf4de2f2e42cd30590` |
| `d-i/trixie/payload.manifest` | `2aa129dee991b0f00959d39d8fa6078b4f32844b465064fc433043c92f90928f` |
| `d-i/trixie/preseed.cfg` | `90cca401b4ffe8a9816c3c440c45045eb6938422781dfc4a9472453cbd92d903` |
| `d-i/trixie/receipt.json` | `227a8a451b32b34f555861ff9e6261206da3a47469b1ee45930cd9559441706d` |

## Paths changed by this repair

```text
d-i/debian/hooks/installer/apt-setup/generators/99-apt-preferences
d-i/debian/hooks/installer/base-stage.d/10-apt-install-policy
d-i/debian/hosts/installer/runtime.env
d-i/debian/repo.env
d-i/debian/scripts/common/apt-sources.sh
d-i/debian/scripts/common/modules/files-logging.sh
d-i/debian/scripts/preseed/network-apt.sh
d-i/debian/tests/test_apt_policy_publication.py
d-i/forky/hooks/target/etc/apt/apt.conf.d/00CDMountPoint
d-i/forky/hooks/target/etc/apt/apt.conf.d/00installer-policy
d-i/forky/hooks/target/etc/apt/apt.conf.d/00trustcdrom
d-i/trixie/hooks/target/etc/apt/apt.conf.d/00CDMountPoint
d-i/trixie/hooks/target/etc/apt/apt.conf.d/00installer-policy
d-i/trixie/hooks/target/etc/apt/apt.conf.d/00trustcdrom
docs/validation/apt-media-regression-20261114.md
docs/validation/late-assets-apt-console-20261114.md
d-i/forky/payload.tar.gz
d-i/forky/payload.manifest
d-i/forky/preseed.cfg
d-i/forky/receipt.json
d-i/trixie/payload.tar.gz
d-i/trixie/payload.manifest
d-i/trixie/preseed.cfg
d-i/trixie/receipt.json
```

Both suite payloads, manifests, preseeds and receipts are regenerated by the reviewed pure build. The user's unrelated `tools/offline.py` and `offline/payload.tar.gz` changes are preserved.

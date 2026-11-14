# Late assets, managed APT fragments and installer console — 2026-11-14

This is historical source and serialization evidence for the release identified below. Its assumption that media configuration could be removed during base installation was incorrect. The reported media failure and subsequent correction are recorded in [APT media regression](apt-media-regression-20261114.md), which supersedes the media lifecycle claims here. The static checks below did not establish a completed installer, boot, APT transaction, signing or desktop acceptance result. No QEMU run was made after the user prohibited further QEMU testing. No native tests or target-management programs were run on the development host.

Authored base revision: `2b6df0bb180879ade6c91fc6ebefc2e735514490`. The source release is `5019f65679ad6719588e6dccbccbcfe8de3c6e1f2d253e61dde1bf3d07e5f769`; its captured source fingerprint is `041ca99f722c7ee208628cc372687c11dd8ccb2032c786e328e3c0525e90de52`. Each payload has 2349 members.

## Corrected contracts

- The shared foundation derives `ZRAM_SETUP_UNIT` from the canonical setup service and `ZRAM_SWAP_DEVICE_NAME` from the frozen device layout. It continues to load the primary human identity through `installer_load_primary_account`, whose sources are kernel `primary_username=` (including the established alias) or installer-root `PRESEED_PRIMARY_USERNAME` credential input. The headless boot provider now uses this same loader, loads class/architecture boot policy, and supplies the exact GRUB template fields.
- Shared artifact ceilings moved from desktop-only defaults to shared defaults without changing their values or the Perl API. Server foundation publication therefore has producers for the same required artifact limits as desktop. Reviewed import consumers are Repository, Deb, CLI and Atomic. Shared software ownership includes Bitwarden, QoreDB, Obsidian, Tomat, Sleek, Postman, Discord, Tuta, Ledger, ChatGPT/Codex, Filen, Zoom and Tor Browser; application payload formats and launch policy were not changed.
- APT policy has one common source owner plus one selected role owner per filename, in each suite. Duplicate common/role ownership fails. Both fixed selector lookups and legacy logical target lookups resolve through the authenticated FILE catalog.
- `installer_apt_install_target_policy` stages and renders a complete candidate using the existing scalar/path renderer, validates required fragments and unresolved tokens, backs up the current flat directory, then publishes the replacement under an exclusive installer publisher lock. It refuses the installer root, unsafe ancestors, symlinks, hardlinks, special files and nested active configuration directories. Copy/rename/render errors propagate even when an outer shell conditional disables errexit.
- `DIR_APT_CONF_D_BACKUP` derives from the canonical APT parts path. The Debian APT interface is `/etc/apt/apt.conf.d`; its sibling backup is `apt.conf.d.bak`. The first bytes and metadata of each regular backup leaf are preserved; later passes add previously unseen filenames installed by packages. The backup directory is private (0700), active directory 0755 and managed fragments 0644. Backup contents are never sourced or used to select new policy. Matching active policy is left in place.
- The same publisher runs from the network-before-first-update adapter, base-stage hook, apt-setup generator, shared late foundation, late storage/APT repair, and final source-normalization hook. Final publication happens after source modernization; only then is the suite default-release fragment included. Thus package conffiles introduced during pkgsel or late transactions are removed from the final active set after being backed up.
- If publishing the candidate fails after moving the previous directory, the publisher attempts restoration and synchronization. An uncertain restoration or cleanup retains recovery material and the lock and returns status 125. This is an offline installer transaction; it is not a general concurrent administrator/APT servicing tool.
- Common fragments explicitly own hook-list clearing, kernel/firmware/task autoremove protection, periodic maintenance, metadata acquisition, debconf and dependency expansion. MOK post-cleanup runs before other post-hooks; its pre-hook runs last with protocol 2 on FD 3. These hooks are selected only after their helper/configuration exists. Desktop owns listchanges, local mail and Labwc package wrapping; server owns its unattended-upgrades policy without desktop hooks.
- No CD-ROM mount/trust file, AppStream cache refresh or automatic rkhunter property-database learning hook is adopted from package defaults. The selected class trees contain no graphical package catalog consumer. `01autoremove` is explicitly authored and retained in both common trees; `70debconf` is retained when its package helper exists.
- `25no-pdiffs` is installed in the d-i root during early setup and through every target policy publication. It disables PDiffs, clears inherited Languages, selects only `en`, explicitly enables the Translation target and guards DEP-11 metadata. This requests Translation-en when provided by the repository, without inheriting locale-selected languages. English UI/locales and package installation remain independent of index-language selection.
- CUDA-legacy keeps its existing exact Debian 12 source exception (`trusted=yes`, allow-insecure/weak/downgrade, date exceptions and scoped key reference). Its dedicated refresh selects only that source and overrides the global authentication defaults on its command line. Because that refresh bypasses apt.conf.d, it explicitly disables PDiffs, selects `en` and enables the Translation target there too; the generated CUDA source also has `pdiffs=no lang=en`. Finish-install retains the existing removal of temporary legacy source/key state. The trusted source exception does not establish a verified vendor-signature claim.
- Late dispatch exports the actual late stage/component identity, emits stage start/completion records, and reports each profile asset publication. Noninteractive target commands stream redacted diagnostics to installer tty4 while retaining capture files and primary command status. Capture, quiet and interactive command interfaces remain separate. The streaming redactor flushes each line and preserves stage/source identifiers.
- Path replacement still uses the existing sed publication renderer. Producing its canonical path-map substitutions now uses one awk process per asset instead of one subprocess for each path entry. Adjacent placeholder scanning no longer greedily combines two tokens.

## Checks actually performed

1. Pure serialization: `timeout --signal=TERM --kill-after=5s 120s make PYTHON=python3 build` — completed successfully. It executed no validation or target code.
2. Required audit: `timeout --signal=TERM --kill-after=5s 120s python3 -B tools/post_change_check.py` — passed before this record was added; the final run is recorded below. It parses changed files and compares generated source bytes without importing tests or target modules. A prior run correctly rejected products stale after a subsequent source edit; regeneration resolved that failure.
3. `git diff --check` — passed; included in the final audit again.
4. Independent standard-library source/data audit (no repository imports, sourced shell or target execution): 2 suites, 26 compiled profiles, 27 registered late providers, 7,922 applicable asset/profile checks, 384 unique assets; no missing required scalar-field producers. Disabled Timeshift stages were excluded for profiles that disable Timeshift. The inventory includes direct publication, fixed asset loops, shared Perl modules and complete APT catalogs; specialized renderer execution and native provider completion are not established by this check.
5. Independent APT source parser/model: all 4 suite/role combinations, 46 selected common/role file views. Parsed the documented scalar/list/scope/#clear grammar after data-only path substitution. Verified PDiffs disabled, Languages exactly `en`, Translation target enabled, no Recommends/Suggests, correct suite default-release, safe global authentication defaults, inherited-list clearing, no server desktop hooks and correct MOK cleanup/preflight order. Parsed all 18 resulting hook commands with `/bin/sh -n` under a minimal environment. A source search found no other language selections in suite hooks/fragments or installer adapters. An initial audit assertion incorrectly examined package blacklists for desktop names; restricting that assertion to executable hook lists resolved the audit-only failure without changing source policy. This is not libapt parsing, a repository refresh, package installation or live hook execution.
6. Source package inventory confirmed apt-listchanges in all desktop roles and rkhunter only in full desktop; no AppStream graphical package-store consumer was selected.

## Authored fixtures — not executed

`test_late_profile_assets.py` covers field ownership across profiles/providers, complete foundation publication, the headless boot asset loop, literal path escaping, adjacent tokens and invalid-map preservation. `test_installer_progress.py` covers output observable before command completion, secret redaction, exact failure status 37, capture failure 125 and reader cleanup using a private file transport. `test_apt_policy_publication.py` covers both suites/roles, initial and append-only backups, helper gating, unknown/default fragment removal, refused indirection/hardlinks/directories, lock ownership, failed commit restoration, retained uncertain recovery and English-only Translation selection. CUDA source/refresh assertions were extended for disabled PDiffs and English-only Translation options. Guards prevent host execution. Functional fixtures mock device discovery, target mutation, source transport and/or synchronization as explicitly indicated; they make no live or durability claim.

## Earlier interrupted isolated attempt

Before the prohibition, one diskless TCG d-i fixture attempt ran with no network, host mounts, host sockets, device passthrough or KVM. It ended at its hard 240-second timeout (status 124; 240.072 seconds). Its only case marker was the start of the first foundation case; no foundation, server boot or tty4 streaming case completed. The attempted payload predates the final source and had SHA-256 `512ae2bb9a4a3dde5c7d1c2b771812aefcf8231ac25730608b912ab41fead1a7`; overlay SHA-256 `52c4ccd3ccd15342dc676ba826638b344843db5bb89d11529d74452b2aa7362c`. No native test pass is claimed. The timeout wrapper reaped the VM; the private run-tree cleanup result is recorded below.

The fixture used Debian Trixie amd64 netboot kernel SHA-256 `2b2358b37674d2505350528875bb17afae2a36522a9e8a9417eaca65a7da0e08` and initrd SHA-256 `57303d157cffce3fa402301667fbc9b2280aa7372082b081e777375ae49da5f2`, from the Debian installer archive over HTTPS. Hashes matched its public SHA256SUMS; detached-signature authentication was not established. Tool records: QEMU 11.1.2 (Debian 1:11.1.2+ds-3), GNU timeout 9.12. The command argument structure was:

```text
timeout --signal=TERM --kill-after=5s 240s qemu-system-x86_64
  -no-user-config -nodefaults -machine pc,accel=tcg -m 512 -smp 1
  -display none -monitor none -serial stdio -nic none -no-reboot -device VGA
  -sandbox on,obsolete=deny,elevateprivileges=deny,spawn=deny,resourcecontrol=deny
  -kernel <private-run>/linux -initrd <private-run>/probe-initrd.gz
  -append "console=ttyS0 rdinit=/fixture-init panic=1 loglevel=3"
```

Kernel/initrd and all outputs lived under that run-owned private tree, stdout/stderr were captured to its serial log, stdin was empty and the outer process deadline was 250 seconds. Environment values were a private HOME, C locale and fixed binary search path; the account fixture was synthetic. A public Debian Trixie slim layer downloaded for a proposed additional fixture was never extracted or executed. No further native validation was attempted after the prohibition.

## Generated artifacts

| Product | SHA-256 |
|---|---|
| `d-i/forky/payload.tar.gz` | `e5f5c7a9a186fa35882d0e4fceba6058a6f75dad0fbc1a631942a68c0d739466` |
| `d-i/forky/payload.manifest` | `1ea3afe78eb1c0c922ef43221e7eaa8736740d1e304bed47fbe4ac9ba1a4b8d5` |
| `d-i/forky/preseed.cfg` | `f61b301d437ec9b9231cc32a5e47b0e7dd4002e4979424d5bc322126b855fd68` |
| `d-i/forky/receipt.json` | `2311940126bb976257bf638fca52fc0bc8990f550cfaba988b792ac8523c0e88` |
| `d-i/trixie/payload.tar.gz` | `e5f5c7a9a186fa35882d0e4fceba6058a6f75dad0fbc1a631942a68c0d739466` |
| `d-i/trixie/payload.manifest` | `1ea3afe78eb1c0c922ef43221e7eaa8736740d1e304bed47fbe4ac9ba1a4b8d5` |
| `d-i/trixie/preseed.cfg` | `ad740ab4a7459f653ed94a95561ec16f2d37c2e38898e0ce1f795af728f84d82` |
| `d-i/trixie/receipt.json` | `2311940126bb976257bf638fca52fc0bc8990f550cfaba988b792ac8523c0e88` |

Both payloads and manifests are byte-identical; suite frontend configurations differ as expected. `source.sh` and support-matrix products were regenerated by the same permitted command but unchanged bytes do not appear in git diff.

## Remaining limits

Complete installation, first boot, real tty4 streaming, native APT configuration parsing, CUDA-legacy weak/unsigned archive resolution, package maintainer effects, Secure Boot signing, service activation and application launches remain unverified for this revision. New package installations after deployment can introduce further APT conffiles; this change defines and enforces the installer publication boundaries and final installed fragment set. The referenced `debian-preseed-de-audit.md` file is absent in this checkout; historical reports are not treated as acceptance. The user-owned `tools/offline.py` changes were preserved.

## Changed paths owned by this task

Generated products and removed duplicate role copies are included; `tools/offline.py` is intentionally excluded from task ownership.

```text
d-i/debian/hooks/installer/apt-setup/generators/99-apt-preferences
d-i/debian/hooks/installer/base-stage.d/10-apt-install-policy
d-i/debian/hooks/installer/d-i/early.sh
d-i/debian/hooks/installer/di.env
d-i/debian/hooks/installer/finish-install.d/95-normalize-apt
d-i/debian/hooks/target/usr/local/lib/common/perl5/site_perl/apt-repo-local/APTRepoLocal/Servicing/ArtifactLimits.pm.tmpl
d-i/debian/hosts/installer/runtime.env
d-i/debian/hosts/profiles/desktop/shared-de.env
d-i/debian/hosts/profiles/shared.env
d-i/debian/repo.env
d-i/debian/scripts/common/apt-sources.sh
d-i/debian/scripts/common/modules/context-target.sh
d-i/debian/scripts/common/modules/files-logging.sh
d-i/debian/scripts/common/modules/observability.sh
d-i/debian/scripts/common/modules/repository-apt.sh
d-i/debian/scripts/common/modules/runtime-console.sh
d-i/debian/scripts/common/modules/target-publication.sh
d-i/debian/scripts/common/system-foundation.sh
d-i/debian/scripts/common/target.sh
d-i/debian/scripts/late/dispatch.sh
d-i/debian/scripts/late/storage-maintenance.sh
d-i/debian/scripts/preseed/network-apt.sh
d-i/debian/scripts/server/boot.sh
d-i/debian/tests/test_apt_policy_publication.py
d-i/debian/tests/test_cuda_legacy_apt.py
d-i/debian/tests/test_installer_progress.py
d-i/debian/tests/test_late_profile_assets.py
d-i/forky/hooks/target/etc/apt/apt.conf.d/00installer-policy
d-i/forky/hooks/target/etc/apt/apt.conf.d/01autoremove
d-i/forky/hooks/target/etc/apt/apt.conf.d/01mok-maintenance-cleanup
d-i/forky/hooks/target/etc/apt/apt.conf.d/20auto-upgrades
d-i/forky/hooks/target/etc/apt/apt.conf.d/25no-pdiffs
d-i/forky/hooks/target/etc/apt/apt.conf.d/70debconf
d-i/forky/hooks/target/etc/apt/apt.conf.d/99mok-maintenance
d-i/forky/hooks/target/etc/apt/apt.conf.d/99noinstall-recommends
d-i/forky/hooks/target/etc/apt/desktop/apt.conf.d/01mok-maintenance-cleanup
d-i/forky/hooks/target/etc/apt/desktop/apt.conf.d/20auto-upgrades
d-i/forky/hooks/target/etc/apt/desktop/apt.conf.d/20listchanges
d-i/forky/hooks/target/etc/apt/desktop/apt.conf.d/25no-pdiffs
d-i/forky/hooks/target/etc/apt/desktop/apt.conf.d/52unattended-upgrades
d-i/forky/hooks/target/etc/apt/desktop/apt.conf.d/60desktop-local-mail.conf
d-i/forky/hooks/target/etc/apt/desktop/apt.conf.d/71labwc-desktop-apps
d-i/forky/hooks/target/etc/apt/desktop/apt.conf.d/99mok-maintenance
d-i/forky/hooks/target/etc/apt/desktop/apt.conf.d/99noinstall-recommends
d-i/forky/hooks/target/etc/apt/server/apt.conf.d/01mok-maintenance-cleanup
d-i/forky/hooks/target/etc/apt/server/apt.conf.d/20auto-upgrades
d-i/forky/hooks/target/etc/apt/server/apt.conf.d/25no-pdiffs
d-i/forky/hooks/target/etc/apt/server/apt.conf.d/52unattended-upgrades
d-i/forky/hooks/target/etc/apt/server/apt.conf.d/99mok-maintenance
d-i/forky/hooks/target/etc/apt/server/apt.conf.d/99noinstall-recommends
d-i/forky/payload.manifest
d-i/forky/payload.tar.gz
d-i/forky/preseed.cfg
d-i/forky/receipt.json
d-i/trixie/hooks/target/etc/apt/apt.conf.d/00installer-policy
d-i/trixie/hooks/target/etc/apt/apt.conf.d/01autoremove
d-i/trixie/hooks/target/etc/apt/apt.conf.d/01mok-maintenance-cleanup
d-i/trixie/hooks/target/etc/apt/apt.conf.d/20auto-upgrades
d-i/trixie/hooks/target/etc/apt/apt.conf.d/25no-pdiffs
d-i/trixie/hooks/target/etc/apt/apt.conf.d/70debconf
d-i/trixie/hooks/target/etc/apt/apt.conf.d/99mok-maintenance
d-i/trixie/hooks/target/etc/apt/apt.conf.d/99noinstall-recommends
d-i/trixie/hooks/target/etc/apt/desktop/apt.conf.d/01mok-maintenance-cleanup
d-i/trixie/hooks/target/etc/apt/desktop/apt.conf.d/20auto-upgrades
d-i/trixie/hooks/target/etc/apt/desktop/apt.conf.d/20listchanges
d-i/trixie/hooks/target/etc/apt/desktop/apt.conf.d/25no-pdiffs
d-i/trixie/hooks/target/etc/apt/desktop/apt.conf.d/52unattended-upgrades
d-i/trixie/hooks/target/etc/apt/desktop/apt.conf.d/60desktop-local-mail.conf
d-i/trixie/hooks/target/etc/apt/desktop/apt.conf.d/71labwc-desktop-apps
d-i/trixie/hooks/target/etc/apt/desktop/apt.conf.d/99mok-maintenance
d-i/trixie/hooks/target/etc/apt/desktop/apt.conf.d/99noinstall-recommends
d-i/trixie/hooks/target/etc/apt/server/apt.conf.d/01mok-maintenance-cleanup
d-i/trixie/hooks/target/etc/apt/server/apt.conf.d/20auto-upgrades
d-i/trixie/hooks/target/etc/apt/server/apt.conf.d/25no-pdiffs
d-i/trixie/hooks/target/etc/apt/server/apt.conf.d/52unattended-upgrades
d-i/trixie/hooks/target/etc/apt/server/apt.conf.d/99mok-maintenance
d-i/trixie/hooks/target/etc/apt/server/apt.conf.d/99noinstall-recommends
d-i/trixie/payload.manifest
d-i/trixie/payload.tar.gz
d-i/trixie/preseed.cfg
d-i/trixie/receipt.json
docs/validation/late-assets-apt-console-20261114.md
```

Final static audit: PASS with this record included (63 existing changed regular files, 22 shell sources, 5 Python AST parses, 2349 payload members, 2214 source-byte comparisons, 194 frontend comparisons, 318 runtime-placeholder producers and 52 APT source/preference contracts). Command: `timeout --signal=TERM --kill-after=5s 120s python3 -B tools/post_change_check.py`. The same audit is repeated after recording this result; its final exit status is reported in the task response. `git diff --check` also passed.
Private validation tree cleanup: completed successfully after confirming the exact run-owned directory identity, owner, private mode, recorded timeout status and original kernel/initrd hashes. The fd-based, symlink-resistant cleanup removed only that disposable run tree; no additional validation executed.

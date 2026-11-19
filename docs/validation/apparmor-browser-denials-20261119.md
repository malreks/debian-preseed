# Historical browser AppArmor denial remediation, 2026-11-19

The supplied `todo/apparmor.log` contains 158 DENIED records, all in
`labwc-app//app-bwrap`. All four distinct requests were still missing from that
child in source revision `90a903b76d0ab3b8648a4171768f1e9b9da35172`.
The corrected, rendered policy permits every recorded request. Offline
compilation and permission checks passed; application launches and loaded
target-kernel enforcement were not exercised.

The capture SHA-256 is
`fa059b3cf536915eb8809def264f66ec9b1287065ca44e6c96ab7231dc6b6f36`.
It is historical evidence from an earlier installed system; it does not identify
the policy currently loaded on any machine.

| Recorded request | Records | Correction in `labwc-app//app-bwrap` |
| --- | ---: | --- |
| Read `/etc/chromium/policies/managed/` | 78 | Read the policy directories and their direct JSON files |
| Read `/etc/chromium/policies/recommended/` | 78 | Read the policy directories and their direct JSON files |
| Read `/etc/chromium/master_preferences` | 1 | Read this exact file |
| Execute `/usr/lib/x86_64-linux-gnu/glib-2.0/gio-launch-desktop` | 1 | Read and inherited execution of this exact GLib helper, using `@{multiarch}` |

## Owning source and shared contract

The only production change is nine lines in
`d-i/debian/hooks/target/etc/apparmor.d/desktop/desktop-wrappers.tmpl`.
The direct Chromium attachment's `local/chromium` already permits the
configuration reads. Bubblewrap payloads retain their child domain after
`no_new_privs`; that direct attachment does not supply the child's permissions.
The new policy reads belong in the child alongside its existing Chromium
execution rules. Both sandbox construction paths in
`labwc_managed_app/sandbox.py` already bind `/etc/chromium` read-only.

GLib's trampoline uses `rix`, preserving the child's execution allowlist and
denials. No directed or unconfined transition is introduced. The existing child
already permits `xdg-open`, `labwc-wayland-app`, its Python delegates and the
managed application executables. The configured HTTP/HTTPS MIME handlers select
the managed Vivaldi/Chromium/Edge desktop entries. Debian's
[Trixie](https://packages.debian.org/trixie/amd64/libglib2.0-0t64/filelist) and
[Forky](https://packages.debian.org/forky/amd64/libglib2.0-0t64/filelist) GLib
package lists confirm the reported multiarch helper path. AppArmor documents
[inherited execution](https://manpages.debian.org/trixie/apparmor/apparmor.d.5.en.html)
and the [offline parser options](https://manpages.debian.org/trixie/apparmor/apparmor_parser.8.en.html).

The consumer inventory covered the managed application registry and persistent
sandbox policy in `labwc_managed_app/profiles.py.tmpl`, alias/URI dispatch in
`generic.py`, both read-only system-configuration mount paths in `sandbox.py`,
the direct application profiles, the desktop runtime/Electron/Bubblewrap
abstractions, the AppArmor mode list, and the late security and browser-policy
staging lists. The owning path/profile/logging maps and the shared Perl renderer
were inspected. The policy source is staged by `scripts/late/security.sh`;
Chromium JSON assets are staged by `scripts/desktop/components/target-assets.sh`.
The same physical policy member is captured by both suite payloads.

The sibling set includes Bitwarden, QoreDB, Obsidian, Tomat, Sleek, Postman,
Discord, Tuta, Ledger Live, ChatGPT/Codex, Filen, Chromium, Edge, Vivaldi,
Mullvad Browser, Tor Browser, Code, KeePassXC, Spotify, Telegram, RetroArch,
mpv, Liferea, FreeRDP, qBittorrent, Help, Calix and Agenda. The generic child
serves its existing application set; ChatGPT, Code, Tor and Codex also have
separate child domains. Tomat has separate direct/controller profiles.
Zoom/Discord's private Xwayland implementation, policy and eligibility are
unchanged. No downloader, package selection, constructor, target path schema,
shared abstraction, service or authorization contract changes were needed.

## Regression and validation evidence

`d-i/debian/tests/fixtures/installed-apparmor-20261119.json` preserves the capture
identity, all four request classes and their counts. It adds policy-file and
multiarch helper probes plus explicit exclusions. The existing guarded
`test_apparmor_incidents_20261004.py` now checks the inherited execution mode
and replays the new fixture against parser-expanded permissions. Those
unittest methods were authored and statically checked; the full guarded
unittest runner was not executed.

The separate reviewed validation run is under
`.build/validation/apparmor-denials-20261119/`. Its exact commands, input hashes,
package identities and results are recorded in the accompanying JSON report.

- A disposable, networkless QEMU TCG guest ran the unchanged production
  `scripts/common/render.pl` using its `--file scalar` and `--file theme`
  interfaces. It rendered 109 common/desktop policy inputs plus the baseline
  wrapper policy. The fixture used explicit synthetic account data and path,
  AppArmor, logging, network-interface and base-theme values read from their
  owning public data contracts. No host directories, sockets, credentials,
  devices or management interfaces were exposed.
- The identified base is Debian Trixie Installer kernel
  `6.12.107+deb13-amd64` and initramfs with BusyBox `1:1.37.0-6+b9`.
  The added `perl-base` package is `5.40.1-6+deb13u1`.
  QEMU is `11.1.2` (`1:11.1.2+ds-3`), with a 120-second timeout and
  five-second forced-termination budget. The final guest reported
  `RENDERED_POLICY_FILES=110` and `GUEST_RESULT=0`; QEMU exited 0 and was reaped.
- AppArmor parser `4.1.8` used private support files extracted as data from
  Debian Trixie `apparmor 4.1.0-1`. The package hashes were checked against
  `Packages.xz`, whose hash/size were checked against the signed Trixie
  InRelease metadata; scoped fixture keyrings verified its signatures.
  No packages were installed and no maintainer scripts were executed.
- Every policy compilation or expansion used explicit private configuration, base/include
  tree, cache location and package features, `--skip-kernel-load`,
  `--skip-cache`, `--jobs=1`, and a 120-second deadline. The absolute package
  feature ABI declaration was relocated only in private validation copies.
  Host policy, configuration and kernel feature discovery were not used.
- Before/after debug masks and parser-produced path expressions compared
  158 profiles. Only `labwc-app//app-bwrap` changed. All four historical
  requests fail the baseline permission comparison and pass the corrected
  comparison. Ten positive probes and twenty negative probes passed, including
  policy writes, unrelated configuration files, unrelated GLib executables
  and `sudo` execution. The rendered helper rule was checked separately for
  inherited execution because debug masks do not retain execution qualifiers.
- Full offline compilation of the corrected `desktop-wrappers` policy passed.
  The private cache remained empty. Neither candidate nor baseline was loaded
  into a kernel.
- `make build` regenerated the twelve permitted flat suite products. Data-only
  comparison verified all 2,433 archive members against each manifest, the
  changed policy bytes against the checkout, receipt source/product hashes and
  frontend archive/manifest pins for both suites. Eight products changed;
  `source.sh` and `support-matrix.json` remain byte-identical in each suite.
- The required `python3 -B tools/post_change_check.py` and `git diff --check`
  results are recorded with the final evidence. These are static checks.

Two fixture corrections were required before the final successful validation.
The first guest rendered its inputs but could not export a gzip-compressed tar
because the minimal image lacks a `gzip` executable; export now uses tar and
Perl hex encoding. A subsequent offline parse correctly rejected an unrendered
base-theme wallpaper token in the fixture's wrapper policy; the guest now uses
the production theme renderer too. Failed fixture logs are retained. Every guest
powered down and its QEMU process was reaped; no timeout or uncertain cleanup
is being counted as a pass.

## Generated identity and remaining limits

Both suites have release
`ecdc45979c0e25a43b2887658b308666ce8ada3fe37f66dd2a7f0fb5441f25c6`
and payload SHA-256
`acd080febfa3d29fa9d5554d4055f778e45bfd7484f90135dd8cc05b97b594af`.
The JSON report records all six product hashes per suite and source fingerprints.
No remote publication or installed-system policy change was made.

Offline compilation and parser-expanded permission comparisons establish the
source policy correction. A fresh unattended install, first boot, GUI browser
launch, external-link handoff, and enforcement under each target's actual
kernel/package set remain unverified. The historical log alone cannot prove
those outcomes. The repository-referenced `debian-preseed-de-audit.md` was absent;
no acceptance claim is based on that unavailable report.

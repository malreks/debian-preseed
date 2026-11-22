# Installed-log source remediation, 22 November 2026

This records source edits based on the restored `todo/managed/`,
`todo/installer-state/` and `todo/journalctl` evidence. The supplied tree contains
108 files. Logs remain unchanged. The starting checkout was `mcr/main` at
`a04a33eabfaba7e5eb823962b2f315c57f667653`; this note describes the uncommitted
working tree, not a tested release or a working-tree fingerprint.

## Source changes

- All three P15s profiles (`btrfs-de-p15s`, `btrfs-de-p15s-duo`,
  `btrfs-de-p15s-trio`) enable the NFS server. The recorded TCP 2049 drops from
  an allowed export peer were consistent with the previously disabled server
  and missing server overlay.
- All 19 concrete host profiles and 12 templates inherit automatic firewall
  defaults. Desktop policy supplies LAN sharing, mDNS and SSDP/wsdd discovery;
  the frozen package plan adds CUPS, KDE Connect, Samba, Syncthing and Tailscale
  overlays as selected. NFS server/client and SSH feature flags select their
  own rules independently. The shared `server` selector resolves to the existing
  baseline source. The standalone server foundation retains its separate owned
  table, SSH ACL and marked NFS ACL block. No administrator table is flushed.
- mDNS and SSDP ingress match real unicast LAN senders; multicast addresses
  belong in the outbound destinations. IPv4 link-local discovery sources are
  permitted through desktop source filtering. wsdd receives UDP 3702 and TCP
  5357 LAN rules. NFS peer/interface ACLs, private app-veth networking and the
  rootless Podman network owner remain in their existing components.
- The native Labwc launch uses the existing fixed-operation session helper.
  A loaded NVIDIA 580 branch selects `WLR_EGL_NO_MODIFIERS=1` and
  `WLR_DRM_NO_MODIFIERS=1` for the main compositor. This is a driver-specific
  response to the supplied repeated `EGL_BAD_MATCH` DMA-BUF import errors;
  hardware confirmation is still required. The user-manager activation
  allow-list excludes both flags. The native GLES renderer remains selected
  by the existing desktop policy. No global software-rendering or legacy
  atomic-modesetting fallback is added. The supported flags are documented in
  [wlroots' environment interface](https://sources.debian.org/src/wlroots/0.19.3-1/docs/env_vars.md/).
- Shared desktop AppArmor rules allow broader packaged toolkit/plugin data,
  user GTK/Qt configuration, nested fonts/themes/icons, font caches and
  graphics-device metadata. This addresses the logged menu `gtk.css`,
  Fontconfig, Microsoft font, TeX font and Poppler CMap denials. Native graphics
  clients gain read-only primary DRM discovery and the NVIDIA modeset driver
  interface. These are explicit permissions; enforcing mode remains selected.
- The shared abstractions serve browsers, Bitwarden, QoreDB, Obsidian, Tomat,
  Sleek, Postman, Tuta, Ledger, ChatGPT/Codex, document applications and desktop
  helpers. Discord/Zoom's existing compatibility includes and explicit device
  denials were inspected as consumers; their private XWayland implementation,
  configuration and two-application eligibility were not edited.
- Firstboot AppArmor allows Debian awk alternatives and public installer TSV
  receipts. The logs showed `/usr/bin/mawk` execution denied. The dependency
  reader treats systemd unit names as bounded opaque arguments and skips unset
  relationship sentinels. The provided diagnostic named `invalid-related-unit`
  without preserving the rejected token, so the exact token was not reproduced.
  Firstboot no longer retries unchanged diagnostics every minute; a failure
  retains its result and evidence.
- Installer providers use the existing primary-account loader for consistent
  identity/home handling. Existing alias support was already present; these
  edits do not claim to repair a proven username-alias defect.
- The final late target-validation sweep is no longer staged. Its retained
  source-member interface exits without scanning. Completion records require
  selected-stage/finish-hook completion and clean unmount, and say
  `configured=target` instead of claiming validation was performed.
- Repeated post-install package, model metadata, ownership, icon decoding,
  desktop-file, daemon help, network-policy, rsyslog/logrotate, Fail2ban,
  Tailscale, Podman adapter and Mullvad compilation/version/hash-recording
  checks were removed from the late path. Actual provisioning, initial
  authenticated downloads, input/path/identity guards, bounded extraction,
  publication recovery and deferred boot activation remain. This does not
  disable vendor authentication or the safety checks at privileged writes.
- The experimental brightness fallback was removed. Native Waybar `backlight`
  behavior remains: an unpowered internal panel may hide the module while an
  external display is active. No backlight fallback, custom module, DDC probe
  or native-menu change is included.

## Continued installation and staging performance work

The continuation traced the shared base-stage renderer, prepared-source loader,
publication batch, common system services, resource policies, desktop terminal
and logging setup, finish-install hook, NVIDIA DKMS wrapper staging and upstream
tool provisioning. Desktop and server consumers share the common loader,
journald policy and systemd resource publication. Tool consumers reviewed here
include Codex, Bazelisk, Node 22/24/26, Rustup and samloader. Native managed-app
package import guards and the shared AI archive extractor were inspected and
retained at their trust boundaries.

- Prepared-source phases no longer run two `wc` processes and four `grep`
  processes over the renderer's diagnostic JSON receipt. The private-file
  metadata checks, completed-stage ready marker, selected-source identity
  comparisons and once-per-shell membership/path tables remain.
- Base-stage provenance logging reuses the authenticated payload identities
  instead of hashing the copied renderer again. It reports
  `renderer=payload-member` and remains advisory. Successful renderer return,
  ownership handoff and atomic ready-marker publication still own completion;
  the immediate receipt-existence postcheck was removed.
- Resource policy values are prepared once at base-stage. Desktop resource
  setup and late manager/delegation staging no longer regenerate and discard
  the same complete map. Post-render manager-setting scans and the standalone
  journald directive sweep were removed. The shared publisher still rejects
  unresolved markers and uses the frozen resource map.
- Desktop staging no longer launches Foot's configuration parser or the
  wlsunset configuration checker. It also omits the installation-time
  `journal-check`, post-creation `log-layout`, and `rsyslogd -N1` sweeps.
  Protected logging paths still receive their preflight before tmpfiles
  provisioning; the existing boot units retain their logging checks.
- Logging group provisioning adds both supplementary groups in one `usermod`
  call instead of two and omits the two `id -nG` rereads.
- Finish-install no longer walks the complete systemd configuration tree to
  rewrite modes, re-chmods the six already-published helpers, or walks and
  rereads every local bin/sbin script. Native packages and atomic publishers
  set modes when installing files. The actual final account privacy
  normalization remains.
- Removed the two Codex version launches, the three pinned Node version
  launches, and the Bazelisk, Rustup-bootstrap and samloader version launches.
  These are eight avoided binary executions when all these installers are
  selected. Authenticated release inputs and metadata remain authoritative;
  candidate entrypoint guards and Codex's publication recovery/final-path
  guards remain. The already-unused optional DevOps diagnostics are not an
  installer call path and were left available.
- Removed the NVIDIA DKMS wrapper's post-copy diversion/executable probe and
  CrowdSec's three `is-enabled` rereads. Actual diversion setup, executable
  installation, offline unit-link changes and deferred activation remain.

These are source-level reductions in reads, process launches and publication
barriers. No installation duration, boot duration or hardware performance was
measured. Actual provisioning such as schema compilation, Corepack shim
creation and protected-directory preparation remains enabled.

## Recorded messages that do not justify additional source work

Early `deferred:nmcli-failed` is an advisory readiness race; later NetworkManager
startup succeeds in the same journal. Pending CrowdSec/Tailscale enrollment is
expected without external approval. CrowdSec's missing qBittorrent acquisition
file precedes its on-demand mount/application launch. Accepted-output nftables
entries for DNS/TLS, NTP, HTTPS and discovery are accepted traffic, not drops.

The logged main-Labwc Xwayland creation diagnostic was left under the explicit
instruction to preserve Xwayland. Its existing private Zoom/Discord boundary
was not replaced or broadened.

The Intel 100 C thermal interlock, firmware ACPI messages, a single HDMI atomic
`Device or resource busy` event, and browser/extension signature/resource
warnings do not establish an additional installer-source defect. Thermal
protection remains enabled. The legacy CUDA archive's SHA-1 key-binding warning
is external archive metadata under the existing scoped legacy-source exception;
this change does not claim to repair that upstream signature. No firmware,
external enrollment, browser package/extension or legacy repository signing
material was changed.

## Execution and publication boundary

Only source/data reads, source edits and Git diff/status inspection were used.
No repository code, installer hook, managed Perl import, systemd/D-Bus operation,
package transaction, firewall loader or kernel AppArmor loader was executed.
No test, syntax checker, offline AppArmor parser, validation runner,
`post_change_check.py`, `git diff --check`, build or artifact hash comparison ran.
All adjusted existing test/fixture sources remain unexecuted. Their
expectations were updated for removed install probes, rendered resource
publication and unchanged boot-time logging checks.

The Forky and Trixie `payload.tar.gz`, `payload.manifest`, `source.sh`,
`receipt.json`, `support-matrix.json` and `preseed.cfg` products were not rebuilt
because builds were explicitly excluded. They are stale relative to these
source edits. The new compositor consumer was added to the authored JSON/TSV
registry as data. A full registry refresh, its stored source fingerprint and
source-member pruning were not regenerated. No new installation, settled boot,
enforcing policy, GUI session,
NVIDIA buffer import or NFS connectivity is proven by this work. Existing
installation logs describe the supplied installed system, not the edited tree.

## Exact changed paths

- `d-i/debian/catalog/placeholder-registry.json`
- `d-i/debian/catalog/placeholder-registry.tsv`
- `d-i/debian/hooks/installer/base-stage.d/00rendertarget`
- `d-i/debian/hooks/installer/d-i/early.sh`
- `d-i/debian/hooks/installer/finish-install.d/94zz-99-validate-target`
- `d-i/debian/hooks/installer/finish-install.d/99-normalize-finish`
- `d-i/debian/hooks/installer/pre-pkgsel.d/92nvidia-legacy-dkms.sh`
- `d-i/debian/hooks/target/etc/apparmor.d/desktop/abstractions/desktop-graphics`
- `d-i/debian/hooks/target/etc/apparmor.d/desktop/abstractions/desktop-runtime`
- `d-i/debian/hooks/target/etc/apparmor.d/desktop/abstractions/wrapper-gui`
- `d-i/debian/hooks/target/etc/apparmor.d/desktop/labwc-session`
- `d-i/debian/hooks/target/etc/nftables/desktop/README.md.tmpl`
- `d-i/debian/hooks/target/etc/nftables/desktop/profiles/desktop.yml.tmpl`
- `d-i/debian/hooks/target/etc/nftables/desktop/services/mdns.yml.tmpl`
- `d-i/debian/hooks/target/etc/nftables/desktop/services/ssdp.yml.tmpl`
- `d-i/debian/hooks/target/etc/skel-desktop/.config/systemd/user/labwc-compositor.service`
- `d-i/debian/hooks/target/usr/local/libexec/desktop/labwc-session-check`
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
- `d-i/debian/hosts/profiles/server/btrfs-srv-flex-duo.env`
- `d-i/debian/hosts/profiles/server/btrfs-srv-flex-trio.env`
- `d-i/debian/hosts/profiles/server/btrfs-srv-flex.env`
- `d-i/debian/hosts/profiles/server/f2fs-srv-hp14.env`
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
- `d-i/debian/scripts/common/bootstrap.sh`
- `d-i/debian/scripts/common/firmware.sh`
- `d-i/debian/scripts/common/kernel.sh`
- `d-i/debian/scripts/common/lifecycle.sh`
- `d-i/debian/scripts/common/profile-services.sh`
- `d-i/debian/scripts/common/source.sh`
- `d-i/debian/scripts/common/ssh.sh`
- `d-i/debian/scripts/common/system-services.sh`
- `d-i/debian/scripts/common/virtualization.sh`
- `d-i/debian/scripts/desktop/components/desktop-helpers.sh`
- `d-i/debian/scripts/desktop/components/logging.sh.tmpl`
- `d-i/debian/scripts/desktop/components/target-assets.sh`
- `d-i/debian/scripts/desktop/samloader.sh`
- `d-i/debian/scripts/desktop/virtualization.sh`
- `d-i/debian/scripts/firstboot/04-validation.sh.tmpl`
- `d-i/debian/scripts/firstboot/assets/etc/apparmor.d/firstboot.tmpl`
- `d-i/debian/scripts/firstboot/assets/etc/systemd/system/firstboot.service`
- `d-i/debian/scripts/late/ch341a.sh`
- `d-i/debian/scripts/late/codex.sh.tmpl`
- `d-i/debian/scripts/late/crowdsec.sh`
- `d-i/debian/scripts/late/crypto.sh`
- `d-i/debian/scripts/late/devops/bazelisk-node.sh`
- `d-i/debian/scripts/late/devops/codex-layout.sh`
- `d-i/debian/scripts/late/devops/codex-provision.sh`
- `d-i/debian/scripts/late/devops/codex-release.sh`
- `d-i/debian/scripts/late/devops/main-orchestration.sh`
- `d-i/debian/scripts/late/devops/upstream-rust.sh`
- `d-i/debian/scripts/late/llama.sh`
- `d-i/debian/scripts/late/mullvad.sh`
- `d-i/debian/scripts/late/network.sh`
- `d-i/debian/scripts/late/podman.sh`
- `d-i/debian/scripts/late/security.sh`
- `d-i/debian/scripts/late/software.sh.tmpl`
- `d-i/debian/scripts/late/storage-maintenance.sh`
- `d-i/debian/scripts/late/tailscale.sh`
- `d-i/debian/scripts/late/tor-browser.sh`
- `d-i/debian/scripts/late/whisper.sh`
- `d-i/debian/scripts/late/zram-swap.sh`
- `d-i/debian/scripts/preseed/guard-hook.sh`
- `d-i/debian/scripts/server/boot.sh`
- `d-i/debian/scripts/server/devops.sh`
- `d-i/debian/scripts/server/hardware.sh`
- `d-i/debian/tests/fixtures/contracts/finish-environment.sh`
- `d-i/debian/tests/test_codex_installer_session.py`
- `d-i/debian/tests/test_installation_fixes_20260912.py`
- `d-i/debian/tests/test_managed_logging_r3.py`
- `d-i/debian/tests/test_packaged_native_session_20260920.py`
- `d-i/debian/tests/test_renderer_provenance_20261119.py`
- `d-i/debian/tests/test_systemd_resource_policy.py`
- `d-i/debian/tests/test_themes.py`
- `docs/implementation/todo-remediation-20261122.md`
- `docs/network-sharing.md`

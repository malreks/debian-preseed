This is a historical validation record for the earlier finish-install/Python
implementation. Its hook placement, interpreter dependency and bootstrap
`APT::Keep-Fds` change are superseded by
[the first-base-hook Perl validation](installer-base-perl-20261116.md).

The installation failure, prepared-payload handoff, AppArmor denials, and host
scratch rule were reviewed on 2026-11-16. The starting checkout was clean at
`512aa17c7a19ec79b62dd3620594352db05120f4`. The generated release identity is
`dc64e99d74156a80814a0aa099097d22dc2facd672b46a82f77201f78316307f`, with source
fingerprint `0cfa7442fe9626f237d01e5bde4436fd933d149e8970c3dee805f2a12028265a`.
These identify the uncommitted implementation validated here.

`todo/installer.log` ends with the Packer helper calling `regular(destination)`
without its required limit. Every fetch call now supplies the appropriate local
verification budget: signing keys and checksum lists use 1 MiB, signatures use
64 KiB, and archives use their existing extraction budget. The downloader keeps
its existing HTTPS, redirect, retry, and time limits. The successful transport
and excessive-file cases were checked with a mocked download inside each guest;
live upstream plugin installation was not run.

The bootstrap APT policy now retains d-i's debconf protocol descriptor 3.
The log showed that policy publication preceded the repeated closed-descriptor
Passthrough failures. The install/final APT policy replaces that bootstrap-only
setting. This wiring was inspected statically; a complete base-install/pkgsel
run remains necessary to prove the symptom is gone.

The configured Tor Browser version was already pinned and available through the
official archive in the supplied installation log. That archive is now the
primary URL, with the distribution URL as fallback, avoiding the two observed
404 attempts. Version, checksum, and signature requirements are unchanged.

`06-render-target` is installed with the finish-install hooks and precedes
Debian's `07preseed`, which invokes `preseed/late_command`. It copies the complete
authenticated source tree, frozen host/account data, validated path/log/theme
maps, manifest, and standalone Python renderer into a private target workspace.
The target's packaged Python processes the copy once, checks it against the
authenticated manifest, renders canonical paths, logging values and eligible
theme defaults, and publishes complete selected Perl namespaces. A completed
receipt and matching payload identity enable the late consumer. Failed
candidates retain private evidence and never receive the ready marker.

Late dispatch uses the prepared stage scripts and modules directly. Module and
parser resolution use their existing allowlists; source-family gates remain in
the acquisition path. Host/account snapshots reload their values while reusing
the validated records. The account publisher reuses the frozen private identity
under its existing lock. Published Perl members are adopted by exact source,
destination, and mode, avoiding repeat copies, ancestry walks and substitutions.
Other files use their existing publication adapters with already rendered path,
logging and theme bytes. Typed scalar/block inputs determined by their owning
late operation remain in those adapters. Reusable future-account templates and
appearance mapping/token metadata retain their intended placeholders.

Verified adopted vendor Debian packages are passed to one APT transaction rather
than one transaction per package. The shared acquisition, signature, checksum,
architecture, size and extraction policy continues to govern those packages.
The relevant shared staging/software consumers include Bitwarden, QoreDB,
Obsidian, Tomat, Sleek, Postman, Discord, Tuta, Ledger Live, ChatGPT/Codex, Filen,
Tor Browser and the remaining role-selected desktop software. The shared network
broker's policy inventory additionally covers Chromium, VS Code, FreeRDP,
Liferea, Microsoft Edge, Mullvad Browser, qBittorrent and its privacy variant,
Spotify, Telegram, Vivaldi, Zoom, and Podman. The renderer, defaults, installed
wrappers/modules, source-family gates, desktop assets, network client/configuration,
service, AppArmor includes, fixtures and generated payload paths were inspected.
The private Xwayland eligibility and implementation for Discord/Zoom were not
changed.

All 33 records in `todo/apparmor.log` map to the two changed policy rules:

| Profile | Records | Allowed operation |
| --- | ---: | --- |
| `desktop-editors` | 2 | Read the current owner's `.wget-hsts`. |
| `app-veth` | 31 | Create/read/write an owner-matched eight-character CPython probe leaf under the target's `/var/tmp`. |

The broker now supplies its canonical target temporary directory explicitly to
both `TemporaryFile` calls. This avoids the default-directory search on each
service restart. The compatibility rule matches only the observed probe filename
grammar. No device-creation capability, recursive `/var/tmp` grant, or complain
mode was added. The existing target service's `PrivateTmp=yes` remains in place.
The editors sharing the first profile are l3afpad, qimgv, kdiff3, gnumeric,
xournalpp, gnote and qalculate-qt.

All six authored `AGENTS.md` files explicitly restrict development-host scratch
storage and require `TMPDIR`, `TMP` and `TEMP` under private disk-backed checkout
storage. The Debian Installer, installed system and approved guest filesystems
may still use their own `/tmp` and tmpfs. Host validation artifacts and downloads
were retained under the owned validation run on the checkout's Btrfs filesystem.

Two disposable QEMU TCG guests validated the current generated payload. There
were no host filesystem mounts, disks, NICs, shared folders, device passthrough,
host service sockets or credentials. Each guest used 1 GiB RAM, two virtual CPUs,
a public Debian installer kernel/initrd, extracted public Debian package data,
and an explicit private PID 1. Host scratch and captures stayed on disk. Package
data was downloaded through HTTPS and checked against suite Packages metadata
sizes and SHA-256 values; these fixture downloads did not independently verify
an archive signing chain or execute package maintainer scripts.

| Evidence | Forky | Trixie |
| --- | --- | --- |
| Python package/runtime | `3.14.10-1` / `3.14.10` | `3.13.5-2+deb13u5` / `3.13.5` |
| AppArmor parser/support package | `4.1.8-3+b1` | `4.1.0-1` |
| Desktop full-tree traversal/render | 14.661 s; 152 published Perl files | 16.523 s; 152 published Perl files |
| Server full-tree traversal/render | 14.790 s; 102 published Perl files | 16.158 s; 102 published Perl files |
| Manifest members / rendered files | 2,429 / 1,088 | 2,429 / 1,088 |
| Guest exit / QEMU process exit | 0 / 0 | 0 / 0 |
| Total guest command duration | 89.247 s | 91.263 s |

The traversal timer covers `render_tree`; the full command also publishes Perl
and writes its receipt. These are fixture measurements under emulation, not a
before/after measurement of total installation time. The supplied failed install
spent 2,837 seconds in late_command, including 1,512 seconds in desktop.software.
Downloads, package operations and other late work account for substantial time.

Both guests passed:

- Desktop and server render/publication using the actual rebuilt 2,429-member
  payload, preserving code bytes except canonical path materialization and
  preserving appearance mapping metadata.
- Literal replacement with adjacent tokens and special replacement characters.
- Six rejected-candidate cases: unknown field, modified copy, missing member,
  symlink, hardlink, and aggregate byte limit. No completed receipt was created.
- BusyBox common library, module and parser loading, account reload/adoption,
  theme-map reuse, prepared asset acquisition and exact publication adoption.
  A transport sentinel rejected any fallback source fetch.
- Packer fetch/local budget checks with mocked transport.
- Real temporary-file output capture by the broker with the network command
  mocked and default-directory probing forbidden by the fixture.
- Offline compilation of the full `desktop-utilities` and `app-veth` policies,
  using each suite's own parser, private configuration/include tree, explicit
  package ABI features, `-Q -K`, and one compile job. No policy was loaded.
- Successful exact workspace cleanup while retaining the published Perl tree.

The first retained guest attempt stopped at a fixture substitution error that
renamed `INSTALLER_SUITE`; it was corrected and both full fixtures then passed.
QEMU processes were reaped and their private memory released after each run.
The initial failed captures and final successful captures remain available for
inspection. The separately authored guarded unittest modules were syntax checked
but were not executed or bypassed; the guest fixture above is the native evidence.

QEMU was `11.1.2` (`Debian 1:11.1.2+ds-3`). Both runs used kernel
`6.12.107+deb13-amd64` with SHA-256
`2b2358b37674d2505350528875bb17afae2a36522a9e8a9417eaca65a7da0e08`.
The original public initrd SHA-256 was
`57303d157cffce3fa402301667fbc9b2280aa7372082b081e777375ae49da5f2`.
The final guest-driver SHA-256 was
`ee8b1eb1fb38cf3f594a1eadff21aeb0d759590f80af3ee3266b706bee30f797`.
The prepared Forky initrd SHA-256 was
`ded2c9c55e46444764c51254bc1c51ef4e69a8399659e6b6f50f814196b04b8f`;
the Trixie initrd SHA-256 was
`f181a69bfecce6ec28b9b715356d897dc9f170e0e4a60093cb197bf9a5f3363f`.

The reviewed runner used `timeout --signal=TERM --kill-after=5s 240s` around
`qemu-system-x86_64`, with an additional 250-second parent deadline. Its fixed
arguments were `-no-user-config -nodefaults -machine pc,accel=tcg -cpu max
-m 1024 -smp 2 -display none -monitor none -serial file:CAPTURE -net none
-no-reboot -rtc base=2026-11-16T00:00:00,clock=vm -sandbox
on,obsolete=deny,elevateprivileges=deny,spawn=deny,resourcecontrol=deny
-kernel KERNEL -initrd PRIVATE_INITRD -append "console=ttyS0 panic=-1
rdinit=/validation-init"`. Each parser command used a 45-second deadline and
`apparmor_parser --config-file=PRIVATE_CONFIG -Q -K -j 1 --base PRIVATE_INCLUDES
-I PRIVATE_INCLUDES --policy-features PACKAGE_ABI --kernel-features PACKAGE_ABI
POLICY`. The package-provided absolute ABI reference stayed inside the guest's
own package tree; no host policy or ABI fallback was used.

The run's `downloads.json`, `forky-vm.json`, `trixie-vm.json`, suite serial
captures and reviewed driver/assembly scripts retain exact URLs, package
versions, input hashes, commands, deadlines, results and cleanup details in the
private validation directory. No installation service or host manager was run.

The permitted pure `make build`, required `python3 -B tools/post_change_check.py`,
and `git diff --check` passed. Independent data-only comparison verified all
2,429 manifest sizes and hashes against each generated archive, and verified
the retained successful serial captures against their run records.

Both suites share payload SHA-256
`620a49b3c0f8d6da2518f302936b1710c2a5f12310dd67d02b8f98cd4ab631c3`
and manifest SHA-256
`2e7941a59b01e5b0680538670e93f3df2e3a19c780cd4045021be93ef515cd04`.
Forky's preseed SHA-256 is
`ad773e7b3706829e78bb60768024f723cb1bb8dbc64d4d3a1718bc0481a92635`;
Trixie's is
`4358e0323d80acd59f9b54005e3a58676fcebad399dcb6662d971d207b1474bd`.
The generation-only receipt intentionally retains its conservative runtime
acceptance field; the separately recorded fixture evidence does not turn the
build into a native-test or installer acceptance command.

A complete unattended install, pkgsel descriptor behavior, APT vendor-package
batch execution, live Packer downloads/signature checks, loaded AppArmor behavior,
desktop launches, networking, boot and hardware behavior remain unverified.
The NVIDIA Debian 12 legacy repository's SHA-1 signing-key binding warning and
its maintainer script's attempted initrd for the installer/media kernel remain
external/native follow-up items. The supplied log also shows a valid initrd for
the installed XanMod kernel; no speculative kernel shim or global crypto-policy
weakening was introduced. Expected pending external enrollment and offline
target AppArmor reload deferral were not classified as installation failures.

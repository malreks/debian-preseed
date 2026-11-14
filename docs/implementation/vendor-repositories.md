# Suite and vendor repository selection

Debian base/udeb/target/update selection follows the frontend suite. Forky
external sources use a publisher's Forky or Testing distribution when it is
actually published. Vendor labels such as `stable`, `any`, `current`, and
LLVM's `unstable` are publisher interfaces, not Debian-suite aliases.

All three Forky desktop classes declare the signed OBS Cramerz
`home:cramerz:debian/Debian_Unstable` repository and its Release key. It is
available at normal APT priority, with **no Cramerz preference file or
repository-specific pin**. The existing Qt Hyprpolkitagent package selection
remains its separately scoped compatibility policy.

The official [Tailscale repository instructions](https://pkgs.tailscale.com/stable/)
publish a Forky distribution and its `forky.noarmor.gpg` key. Forky medium/full
classes use that source rather than Trixie. Server classes currently do not
select Tailscale. The publisher's signed package identity remains scoped by
the family preference policy.

The Forky classes do not add a Trixie repository. When a publisher has no
Forky/Testing channel, the affected application is left out of the Forky class
and remains available in the Trixie class where its signed suite exists. The
physical role classes declare repositories and family APT preferences own
package eligibility. There is no suite JSON input to generation or installation.

| Publisher | Current Forky role scope | Reason and package boundary |
| --- | --- | --- |
| Incus | Forky desktop medium/full, Forky server DevOps | Debian Forky publishes native `incus`, `incus-base`, and `incus-client`; the Forky classes use those candidates and do not add Zabbly. Trixie keeps its explicitly scoped Zabbly source where required by that suite's role package set. |
| Microsoft PowerShell | Trixie desktop full only | The Microsoft Debian index has no Debian 14/Forky/Testing product tree. Forky full omits `powershell` instead of pulling a Debian 13/Trixie repository. Edge and Code use their separate publisher `stable` repositories on both suites. |
| Oracle MySQL Shell | Trixie desktop full only | The Oracle distribution index has no Forky/Testing entry. Forky full retains Debian's native MySQL client packages and omits `mysql-shell`; Trixie uses the signed MySQL Trixie archive for the named tool identities. |
| Debian Qt Hyprpolkitagent | Forky desktop from native Forky; Trixie desktop from signed Trixie Backports | Debian Forky now publishes `hyprpolkitagent`, so Forky uses the native candidate. Trixie retains the signed backport because its native suite does not provide the reviewed Qt package. Dependencies remain native and no package version is pinned. |

[LLVM's own instructions](https://apt.llvm.org/) identify `unstable/` as its
Forky/sid distribution. Keep that channel and the explicitly selected
toolchain families. Do not invent a `forky/` URL or rewrite an unrelated
publisher's `stable`/`any` channel.

Both native suite APT fragments declare the suite-matching XanMod source and
key. The [XanMod documentation](https://www.xanmod.org/) lists both Forky and
Trixie. Fixed image/header names come from the publisher's
[EDGE 7.3.1-xanmod1 release](https://sourceforge.net/projects/xanmod/files/releases/edge/7.3.1-xanmod1/).
There is no floating kernel meta-package or LTS substitution. Other native
Debian main packages follow their selected suite candidates.

This records public channel/index evidence and source configuration, not a
live APT solver, Release-signature or package installation result. The web
reader could not retrieve the OBS Release/key metadata or XanMod APT index;
those bytes were not independently acquired or verified in this task. The
installer must still authenticate each configured archive with its declared
key. No insecure fallback was added.

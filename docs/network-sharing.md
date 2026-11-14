# Profile-controlled network sharing

The same NFS and Filen implementation is used by Forky and Trixie, for desktop
and server roles. Every concrete host profile under
`d-i/debian/hosts/profiles/{desktop,server}/` exposes the activation choices.
Selecting a server role does not bypass these profile settings. The current
mount layout is configuration format 3; see [shared storage and Filen](sharing-filen.md).

## Profile policy and precedence

The restricted data compiler loads suite metadata, canonical runtime directories,
family defaults and the selected concrete profile. Shared NFS defaults from
`hosts/profiles/shared.env` fill missing fields afterwards. They never
overwrite a concrete profile value. Derived client flags use the selected port,
version and timeout. Profiles contain no shell code or installer placeholders.

Each concrete profile supplies `NFS_SERVER_ENABLE`, `NFS_SERVER_THREADS`,
`NFS_SERVER_PORT`, `NFS_CLIENT_ENABLE`, `NFS_CLIENT_TARGET_IP` and
`NFS_CLIENT_READ_ONLY`. Each boolean is exactly `true` or `false`. The shared
family data supplies `NETWORK_SHARING_ROOT_PATH`, `NETWORK_SHARING_HOME_BIND_PATH`,
`NFS_SERVER_PATH`, `NFS_CLIENT_PATH`, `NFS_CLIENT_EXPORT_PATH` and interface defaults;
a concrete profile can override policy values. Canonical filesystem roots derive
from `hosts/installer/runtime.env`, for example:

```sh
NETWORK_SHARING_ROOT_PATH="${DIR_DATA}/sharing"
NFS_SERVER_PATH="${NETWORK_SHARING_ROOT_PATH}/nfs-server"
NFS_CLIENT_PATH="${NETWORK_SHARING_ROOT_PATH}/nfs-client"
```

The existing host-specific enabled choices are preserved. Inspect the selected
profile before installing. Both NFS roles may be enabled together. With both
disabled, the shared local/home view remains available for explicitly selected
Filen accounts; no NFS daemon is enabled and no remote NFS mount is added.

## Shared installation and systemd ownership

`os.sharing` runs once in the frozen late plan, after physical-network publication
and the selected storage/account foundation, before desktop session or server
service publication. It stages the same validated configurator for both families.
The NFS daemon guards, identity and report services are authored under
`hooks/target/etc/systemd/common/system/`. Their installed paths derive from
`DIR_SYSTEMD_SYSTEM`; fixed unit overrides derive from the individual
`DIR_SYSTEMD_SYSTEM_*_DROPIN` values.

The NFS server guard names the firewall actually owned by its family. Desktop
policy uses the managed desktop filter; server policy uses only the
`managed_server` table. Server start/reload reads that owned source directly,
and stopping its unit does not flush administrator tables. The shared NFS
configuration replaces only the marked NFS block in the server source. It
allows TCP to the selected service port from the exact export peers on approved
physical uplinks, then drops other NFS TCP/UDP ingress. It does not add IPv6
exports or RPC discovery services. Remote mounts remain NFSv4.1/4.2 over TCP.

`NFS_INTERFACES` must be a nonempty, duplicate-free subset of the two managed
physical interface names. Primary Ethernet versus primary Wi-Fi changes route
metrics; it does not silently remove the other approved NFS interface. The
server export ACL must include the client's actual source address, including
the paired Wi-Fi address when that interface is used.

Numeric `NFS_ACCOUNT_UID` and `NFS_ACCOUNT_GID` must match the configured human
account whenever either NFS role is enabled. The installer refuses to renumber
an existing account or adopt an unrelated group. `NFS_SHARED_GID` is separate.
NFS AUTH_SYS trusts the permitted machines' numeric identities; IP allowlists
and reserved source ports do not authenticate a hostile machine.

## Terminal clients and authentication

`nfsmnt` and `filenmnt` invoke the shared `network-sharing` client. The desktop
Computer Management entry uses the separate `labwc-network-sharing` menu wrapper.
Servers require no Fuzzel picker, compositor, desktop session or desktop
credentials to use the terminal clients.

Run `nfsmnt` as the configured operator from a terminal, including an SSH login
with a TTY. It checks the installed non-secret configuration, unique fstab entry
and native systemd mount properties. A disconnected mount gets a bounded TCP
reachability check followed by the one configured mount request. An active mount
gets a stop request. PID 1 owns the actual mount job, its dependencies and timeout.
Busy mounts are never forcibly or lazily unmounted. A timed-out manager request
reports that its outcome is uncertain; it is not automatically retried.

Native Polkit authenticates administrator requests. The client supplies its
controlling terminal to mutating systemctl calls so Trixie's terminal agent can
start; passwords remain in the native agent/TTY exchange. No passwordless rule,
blanket sudo, arbitrary unit/path argument or privileged project shell is added.
Noninteractive invocations without a suitable authentication agent fail normally.
The systemd stdin requirement is documented in
[systemd terminal-agent source](https://github.com/systemd/systemd/blob/main/src/shared/polkit-agent.c).
Trixie's packaged PAM helper and Forky's socket helper have explicitly scoped
AppArmor support. Native authentication remains unverified in this checkout.

## Protocol and export policy

The default export peer definitions preserve these exact intervals:

| IPv4 peers | Access | CIDRs |
| --- | --- | --- |
| 192.168.50.82–100 | Read/write | .82/31, .84/30, .88/29, .96/30, .100/32 |
| 192.168.50.112–122 | Read-only | .112/29, .120/31, .122/32 |
| 192.168.50.212–222 | Read/write | .212/30, .216/30, .220/31, .222/32 |

The abbreviated CIDRs retain the `192.168.50` prefix. The configured export is
exactly `NFS_SERVER_PATH`, with `sync,subtree_check,root_squash,secure,sec=sys,fsid=0`
and exactly one of `ro` or `rw`. Wildcards, overlapping peers, `no_root_squash`,
`insecure`, `async`, `crossmnt` and unmanaged active exports are rejected.
Subtree checking can produce stale handles across renames; hard NFS I/O can
block during outages. Those protocol properties are not changed by this layout.

Client flags retain `hard,proto=tcp,resvport,sec=sys,nosuid,nodev,noexec,_netdev`,
explicit version/port, a bounded mount timeout, and dependencies on the client,
firewall and identity units. The remote source is `noauto`; the persistent shared
root and home view mount first. No idle automount, path trigger or remote probe
is added at boot.

## Evidence boundary

This redesign has source, serialization and static-audit evidence only. The new
NFS/Filen/hardware failure cases are authored data in
`d-i/debian/tests/fixtures/contracts/shared-profile-services.json` and remain
unexecuted. No boot, actual mount, package solver, native service, firewall,
Polkit, GUI or hardware acceptance is claimed. Earlier reports under
`docs/validation/` remain historical and do not qualify the current tree.

# Technitium installation and maintenance ownership

Technitium is a new headless implementation in the current checkout, using a
dedicated unprivileged native Incus container with its own bridge and veth.
The old sibling server repository and retired Trixie server tree were not
implementation sources. All operation examples below are for a separately
authorized installed target; none was executed in this coding task.

The physical server class supplies native Incus, Tini and native library
dependencies. `shared-srv.env` owns pinned Technitium/.NET URLs, versions,
digests, redirect hosts, member/expanded-byte limits, private bridge settings
and resource bounds. The compiler produces each profile's validated artifact
policy; native Debian dependencies follow the selected suite candidates.

Initial installation verifies the pinned artifacts and serializes the native
runtime closure into regular-file-only image data. ELF dependencies are read
as data; no `ldd`, vendor installer, external root filesystem, moving latest
artifact or downloaded setup program runs on the host. Native library bytes
and package versions are captured into the image receipt without version
assumptions. Credentials are excluded. This initial installer program runs
from private temporary staging and is removed afterwards. It neither contacts
Incus nor creates/starts a workload. Status remains installed-but-pending.

The actual initrd `/preseed.env` supplies these restricted private inputs:

```text
PRESEED_TECHNITIUM_USERNAME='dnsuser'
PRESEED_TECHNITIUM_PASSWORD=''
PRESEED_TECHNITIUM_WEB_USERNAME=''
PRESEED_TECHNITIUM_WEB_PASSWORD=''
PRESEED_TECHNITIUM_TLS_PASSPHRASE=''
PRESEED_TECHNITIUM_BACKUP_PASSPHRASE=''
```

The designated username owns the locked nologin UID/GID 2103 service identity.
It must differ from the primary human account and all reserved identities.
An optional OS password is hashed through private native stdin and the hash
remains locked; it is never used as the web password. The primary account
comes from `PRESEED_PRIMARY_*` and alone receives the primary SSH key. The
service account receives no SSH key or supplementary management groups.
Initial setup records the service identity and private credential state;
later maintenance checks that receipt against native passwd/group/shadow.

The installer privately stages the web username/password pair, TLS passphrase
and backup passphrase. Supplied passwords require at least 16 characters;
empty optional values preserve a safe pending state. The web account is
independent of the OS identity. A separate random bootstrap administrator
credential initializes the pinned vendor runtime; authenticated API setup
creates and verifies the requested named administrator. An interrupted API
mutation retains the native/web configuration journals and is never retried
automatically. Missing web credentials prevent guest configuration/start.

Public DNS ownership and ACL configuration requires an operator-owned
mode-0600 JSON input in trusted root ancestry, with exactly these fields:

```json
{
  "dns_ownership": "dedicated-port53;resolved-uplink-resolver",
  "recursion_cidrs": ["192.0.2.0/24"]
}
```

Use actual authorized client networks. That documentation address is an
example, not a deployed default. Configuration is supplied by the installed
maintenance command's positional private-input argument:

```text
installer-serverctl configure-dns server/technitium PRIVATE_JSON
```

This stages an explicit non-stub systemd-resolved handover and owned nftables
and forwarding-sysctl files. It does not reload live policy or services. The
operator must review and apply those exact staged policies and the resolver
handover before activation. Startup checks applied routing, exclusive host
port-53 ownership and the loaded owned firewall marker, then uses the local
root-authenticated Unix Incus API. No HTTP Incus management API is admitted.

Configuration validates the complete ACL, physical uplinks, IPv6 policy,
bridge overlap, firewall boundaries, resolver ownership and retained bundle
before changing policy. One firewall candidate retains both the input ACL
and forwarding rules. Before publication, the private configuration journal
named by `FILE_SERVER_DNS_CONFIGURATION_TRANSACTION` records an owned recovery
workspace containing exact previous file bytes, digests, modes, UID/GID or
absence, together with the previous resolver link. Each completed publication
is journaled. Stopped guest preparation precedes resolver handover. The
terminal state is written only after all configuration and status files are
durable; it still means activation pending.

An interrupted configuration returns outcome unknown and retains that journal,
the recovery workspace and any native Incus transaction. Start, backup, update
and restore require the terminal configuration receipt and configured marker.
Do not remove a journal or retry configuration to bypass this gate. Keep the
service and actual guest stopped, inspect the recorded file publications and
native objects, then restore only the recorded previous bytes/metadata or
absence and the exact prior resolver link. File restoration alone does not
prove restoration of previously applied live routing, resolver or firewall
state. Preserve recovery evidence until the operator has established that
state. No automatic restoration, policy reload or guest activation is implied.

All images, container volumes, snapshots and backup archives live on the
mounted `/pool` partition. Its filesystem is independent of `/`: the normal
Btrfs host profiles provide XFS with project quotas on `/pool`. Configuration
selects the native Incus `dir` driver there and enforces the guest disk limit
through project quotas. A Btrfs `/pool` uses the native Btrfs driver. No loop
image, filesystem conversion or store in the root filesystem is substituted.
The additional F2FS/ext4 profile is blocked before partitioning for Technitium
because its current pool policy does not qualify project quotas.

Configuration creates only its own project, storage pool, bridge and stopped
instance. The dir driver receives a new empty root-owned directory; the Btrfs
driver creates its own subvolume at an absent path. An existing source path or
competing object is refused without reset/adoption. Dedicated
source address pairs must not overlap physical uplinks. Native API requests,
async waits, aggregate file transfer and cleanup use bounded operation owners;
uncertain mutation retains a private transaction and prevents automatic retry.

The guest has no host bind mounts, devices or management sockets. Its native
PID-1 entrypoint configures only its guest namespace and starts the DNS child
as UID/GID 2103 with capabilities removed. A namespaced port threshold grants
only ordinary port-53 binding without host port-binding authority. The native
Incus profile supplies its confinement. The small host lifecycle controller
has the native Incus API authority and the capability needed to inspect its
owned nftables policy; vendor DNS code runs in the non-root guest.

Owned DNAT preserves client source addresses. Firewall rules match the bridge
at layer 3 while the instance receipt binds the exact veth identity. Both
physical Ethernet/Wi-Fi interfaces participate according to the validated
profile network policy. Private CIDRs control inbound DNS and recursion;
unrelated host access and private-network egress are blocked for the guest.
IPv6 neighbour discovery is allowed only on the owned bridge. Missing native
IPv6 support is handled explicitly instead of trying to set absent sysctls.

A and AAAA queries remain available over either enabled client transport.
`IPV6_ENABLE` controls actual IPv6 connectivity. With IPv6 enabled the initial
upstream transport preference may prefer IPv6; that preference does not filter
DNS records. Upstream's initialization environment applies to a new config
only. Existing credentials and recursion settings must be changed through
authenticated application administration rather than an environment rewrite.

Administration listens on guest loopback 5380 and has only a root-owned
mode-0600 host Unix proxy, named by `FILE_SERVER_DNS_MANAGEMENT_SOCKET`.
There is no host TCP management listener. An operator must use separately
authorized private access to that socket; the ordinary SSH key grants no
blanket sudo or automatic access to the service credentials. A supplied PFX
at `FILE_SERVER_DNS_TLS_CERTIFICATE` is privately copied into the guest and
enabled only after authenticated native API confirmation. A staged passphrase
without its certificate leaves TLS pending while management remains Unix/
guest-loopback only. No default-admin or remote management listener is exposed. Keep the primary
operator's SSH key and port policy separate from service/runner identities.
Native systemd state or a running container never makes status claim online.

Maintenance requires the service and actual guest to be stopped:

```text
installer-serverctl backup server/technitium
installer-serverctl update server/technitium amd64
installer-serverctl rollback server/technitium BACKUP_RECEIPT.json
installer-serverctl acknowledge server/technitium update.json
installer-serverctl acknowledge server/technitium restore.json
```

Backups require the staged backup passphrase before taking an owned snapshot.
They bind a stopped owned Incus snapshot, bounded configuration export,
private credential/policy archive, exact application/.NET bundle and digest
receipt. Archive format 3 uses Scrypt-derived AES-256-GCM with a random salt/
nonce and authenticated header, streaming ciphertext directly to the archive.
It excludes the backup passphrase and ephemeral management socket. Restore
authenticates the entire archive before parsing members or mutating state;
wrong passwords, changed bytes or old plaintext formats are rejected. The
current private backup key survives credential-directory replacement. Incus
snapshots and ordinary pool data retain the host filesystem's own encryption
policy; archive encryption does not encrypt the whole pool. Update and restore keep previous snapshots, bundles, file bytes and
durable rename journals. Restore uses the exact snapshot and policy together;
no destructive recursive cleanup or automatic activation follows it. Native
configuration and application health still need operator review. A terminal
update/restore journal may be acknowledged only after that review. A prepared
or outcome-unknown Incus transaction needs native object/evidence investigation;
it cannot be dismissed by the terminal-journal acknowledgement command.

The implementation was inspected against the native
[Incus REST API](https://linuxcontainers.org/incus/docs/main/rest-api/),
[file API source](https://raw.githubusercontent.com/lxc/incus/stable-6.0/cmd/incusd/instance_file.go),
[Btrfs driver source](https://raw.githubusercontent.com/lxc/incus/stable-6.0/internal/server/storage/drivers/driver_btrfs.go),
[directory driver and XFS quota interface](https://linuxcontainers.org/incus/docs/main/reference/storage_dir/),
and pinned Technitium
[initialization interface](https://github.com/TechnitiumSoftware/DnsServer/blob/v15.6.2/DockerEnvironmentVariables.md).
Named web accounts and TLS configuration use the pinned
[authenticated native API](https://github.com/TechnitiumSoftware/DnsServer/blob/v15.6.2/APIDOCS.md),
and private management transport follows the native
[Incus Unix proxy interface](https://linuxcontainers.org/incus/docs/main/reference/devices_proxy/).
The behavioral/failure cases in `tests/fixtures/technitium-incus-contract.json`
are authored and unexecuted. No native container, DNS query, service, firewall,
backup, restore or resolver operation was performed. Static consistency does
not establish native acceptance.

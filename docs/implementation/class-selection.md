# Physical classes and role composition

Each suite has physical class files below its own `classes/class-select/`.
Select canonical names in `classes=` separated by semicolons. The suite comes
from the preseed URL. Role, site, network, architecture, hardware,
storage and explicit profile selections remain independent.

A bare class filename without `.cfg` is also accepted when its basename is
unique in the captured class registry. For example,
`prod;full;static;btrfs-de-p15s;nvidia-legacy;cuda-legacy` resolves to
`site/prod;role/desktop/full;network/static;profile/desktop/btrfs-de-p15s;optional/nvidia-legacy;optional/cuda-legacy`.
This lookup never probes input-derived paths or restores retired classes.
Ambiguous basenames such as `arm64` require their canonical group prefix.
The installer validates separators, hyphens, length, registry membership and
duplicates before hardware merging, and persists only canonical references.

Security is a common baseline, without a standard/enhanced selector. Each
suite's `fragments/apt.cfg` supplies auditd, AppArmor, nftables, Fail2ban and
their shared dependencies to every role. The common system-services stage
installs one native auditd configuration and integrity rule set, AppArmor
startup policy and audit logging paths. The common APT fragment also includes `apparmor-notify`.
The role-specific firewall, SSH and application confinement remain enforced
by their respective installers and validated profile policy.

Exactly one desktop tier is allowed: `role/desktop/base`,
`role/desktop/medium` or `role/desktop/full`. Server selections accept any
nonempty subset of `role/server/github-actions`, `role/server/gitlab-cicd`
and `role/server/devops`. The current `role/server/technitium` is selected
alone, with explicit conflicts against those other server roles. Future
combinations require an implemented and reviewed shared service/network
contract. A desktop role cannot be
combined with a server role. Duplicate, unknown, ambiguous or traversal-bearing
class names fail before partitioning.

For example, the following class value selects both runners and explicit
server profile policy:

```text
classes=site/lab;role/server/github-actions;role/server/gitlab-cicd;network/dhcp;profile/server/btrfs-srv-flex
```

The existing hardware detector supplies architecture, CPU, kernel, GPU and disk
classes unless explicitly overridden with registered classes. These classes
do not enable a proprietary GPU driver. Shell commands containing this value
must quote it because a semicolon is a shell separator.

On amd64, `kernel/x64v2` or `kernel/x64v3` owns the exact XanMod EDGE
7.3.1-xanmod1 image/header pair. The detector intersects usable instruction
features across all CPUs; disk type and CPU vendor do not select an ISA.
Explicit `kernel/x64v2` on v3 hardware is supported. An unsupported v3 override,
missing CPU evidence or a CPU below v2 fails before partitioning. Both suite
class directories contain the plain kernel package fragments. The shared
`os.kernel` stage verifies the installed pair and regulatory database once.
The generated minimum plans use the qualified v2 baseline; native CPU/boot
acceptance remains unverified. Arm64 role installations remain unqualified.

`optional/cuda`, `optional/cuda-legacy`, `optional/nvidia`,
`optional/nvidia-legacy` may be selected together when their declared constraints and
the actual hardware permit it. Modern and 580-series NVIDIA driver branches remain mutually exclusive.
CUDA compiler selections are independent of a display-driver choice. Every server role lists the OpenSSH server packages. Desktop profiles add the
suite SSH package fragment only when `SSH_SERVER_ENABLE=true`; this boolean
also controls configuration, authorization, detection and activation on both families. Dualboot and
duo preservation profiles are quarantined before storage changes.

The real role files contain ordinary preseed answers, including package lists
and repository records. No class comment, metadata directive or shell variable
controls installation. The shared `hooks/installer/class-dispatch.tsv` table
maps selected physical class names to installer constraints and ordered phase
helpers. It contains no packages or repositories. Shared helpers run once,
with every selected contributing class retained as an owner.
Distinct stage names cannot execute the same helper twice in one phase.
Source-local APT slot numbers are compacted across fragments rather than
overwriting other classes' repositories. Package lists merge by stable union;
scalar debconf answers and `seen` records preserve their separate semantics.

The frozen plan and the non-secret installed receipt use format 2, with one
`role` record per selected role and one `class` record per resolved class.
There is no first-server-role shortcut. Server identity setup and Bash account
publication run once, while each selected runner/DNS/DevOps installation keeps
its own identity, artifact release, credentials, subordinate IDs, storage and
rootless socket. Missing private enrollment leaves that service pending.

Generation records all 22 compatible amd64/Btrfs/fresh role selections: three
desktop tiers, seven runner/DevOps combinations and Technitium alone for each
suite. All fourteen individual suite/role plans are present. These are source plans,
not booted installations or evidence of a successful package solver, service
start, firewall activation or external enrollment.

Profile `.env` values are restricted data. Canonical runtime directories are
resolved first, followed by family defaults and the explicit host profile.
For example, `NETWORK_SHARING_ROOT_PATH="${DIR_DATA}/sharing"` and
`NFS_SERVER_PATH="${NETWORK_SHARING_ROOT_PATH}/nfs-server"` use ordinary data
references. Template tokens are forbidden in profile `.env` files; they remain
valid only in target asset templates processed by the single renderer.

The headless DevOps login fragment is
`hooks/target/etc/skel-server/.profile.d/71-devops-srv.sh`. Only the
`role/server/devops` installer publishes it. The ordinary Bash profile loader
discovers numbered fragments; login does not start an engine or service.

Profile classes are family-qualified: `profile/desktop/btrfs-de` and
`profile/server/btrfs-srv-flex` resolve to their physical family directories.
Crypto and Wi-Fi are explicit host-profile booleans, never optional classes.
Root and home LUKS2 choices remain independent of the desktop tier or server roles.

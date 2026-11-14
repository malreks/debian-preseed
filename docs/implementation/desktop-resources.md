# Desktop resources and build isolation

The desktop design uses Forky and upstream systemd 262 as its minimum baseline.
Native Debian packages still follow the selected suite candidate. There is no
native systemd version pin or Trixie compatibility fallback. The reviewed
interfaces are upstream's [resource control](https://raw.githubusercontent.com/systemd/systemd/v262/man/systemd.resource-control.xml),
[scope launcher](https://raw.githubusercontent.com/systemd/systemd/v262/man/systemd-run.xml)
and [scope stop properties](https://raw.githubusercontent.com/systemd/systemd/v262/src/core/dbus-scope.c).
No installed manager or cgroup was queried.

```text
user@UID.service
├── session.slice   compositor, Waybar, dock, notifications and audio/session infrastructure
├── app.slice       managed applications and terminal GUI processes
├── build.slice     builds, the DevOps shell and compiler descendants
└── background.slice
```

`labwc-session.target` coordinates lifecycle; targets do not own processes or
take `Slice=` assignments. Labwc runs in the compositor service. Waybar, Crystal
Dock, Mako and the audio overrides now use the session slice. Managed application
constructors retain their application slice. A build enters a separate user
scope and leaves its terminal GUI in its existing application service.

Shared desktop profile defaults, overridable by a concrete profile, are:

| Field | Default | Purpose |
| --- | --- | --- |
| `SYSTEMD_MEMORY_LOW_DESKTOP_ANCESTRY` | `15%` | Soft protection through system `user.slice`, actual account slices and user managers |
| `SYSTEMD_MEMORY_LOW_USER_SESSION` | `10%` | Interactive desktop infrastructure |
| `SYSTEMD_MEMORY_LOW_USER_APP` | `5%` | Interactive applications |
| `SYSTEMD_BUILD_CPU_WEIGHT` | `20` | Lower sibling CPU preference |
| `SYSTEMD_BUILD_IO_WEIGHT` | `20` | Lower sibling block-I/O preference where profile weighting is enabled |
| `SYSTEMD_BUILD_MEMORY_HIGH` | `60%` | Aggregate build reclaim/throttling threshold |
| `SYSTEMD_BUILD_MEMORY_MAX` | `75%` | Aggregate build memory ceiling |
| `SYSTEMD_BUILD_MEMORY_SWAP_MAX` | `20%` | Aggregate build swap ceiling |
| `SYSTEMD_BUILD_TASKS_MAX` | `8192` | Aggregate build task ceiling |

Memory percentages refer to physical RAM. `MemoryLow` is best-effort reclaim
protection, not a hard reservation; unused memory remains available. Protection
must extend through ancestors. The generic account override avoids assuming
UID 1000, and multiple users share the ancestor budget under contention.
Existing CPU/I/O weighting switches remain effective. Memory protection and
build memory limits do not depend on those switches. Effective controller
delegation, block-I/O scheduling and sched-ext behavior require target evidence.
The plan compiler rejects invalid percentages, reversed build memory thresholds
and invalid aggregate zram envelopes before producing an installable publication;
the target render/configuration boundaries validate them again.

The installed `labwc-build` command preserves argv, cwd, the foreground terminal
and the toolchain environment, with one synchronous user scope. It replaces
`TMPDIR`, `TMP`, `TEMP` and `GOTMPDIR` with the private per-account build scratch
directory and `CARGO_TARGET_DIR` with the account's managed Cargo output path.
Both derive from the canonical pool build root and the native account identity;
an inherited `USER` value cannot select another account's storage. This policy
applies to ordinary compiler aliases and to nested calls already in a build
scope, independently of activating the broader DevOps environment.

Installation provisions the account build root with mode 2770 and its scratch
directory with mode 0700. The launcher requires a mounted pool, direct
directories and the expected account ownership/modes. Missing, indirect or
unsafe storage stops the launch without creating a root-filesystem substitute
or repairing an existing store. It disables systemd
argument expansion, uses a fixed description, returns command status and gives
scope cleanup a fifteen-second stop budget. Interactive builds have no imposed
runtime deadline. Root, a missing account manager and missing installed build
policy fail explicitly, without running an unconfined replacement.

The DevOps profile starts its nested shell through this launcher; directly
forked tools and linkers inherit build ownership. Its ordinary interactive
Make, Cargo, Rust, C/C++, Ninja, CMake, Meson, Go, Zig, Java and .NET commands
also route through the launcher. Bazel retains its fixed configuration argv.
Nested compiler calls check their own kernel cgroup and do not create extra
scopes or trust an environment marker.

This isolates managed workloads; it does not prevent the account owner from
bypassing shell aliases. Absolute compiler invocations outside this shell,
IDE-specific workers and external jobs need an explicit `labwc-build` owner.
Existing DevOps cache/toolchain ownership remains authoritative. Project output
paths beyond Cargo still follow each build system's explicit configuration:
keep build workspaces below the pool or provide their supported output option.
The launcher cannot invent an out-of-tree output flag for every arbitrary
Makefile and does not silently move a source checkout.

## Zram emergency pacing

Zram, PSI, pressure handling and normal maintenance stay enabled. Available
memory, PSI some and PSI full remain independent OR triggers. Profile-specific
desktop gates change moderately:

| Profiles | Pressure available memory | Emergency available memory | Emergency PSI some/full avg10 |
| --- | --- | --- | --- |
| Btrfs default/duo | `12% → 10%` | `6% → 4%` | `8.00/1.50 → 12.00/2.50` |
| Btrfs Flex | `15% → 12%` | `8% → 6%` | `8.00/1.50 → 12.00/2.50` |
| Btrfs P15s | `10% → 8%` | `5% → 3%` | `8.00/1.50 → 12.00/2.50` |
| F2FS HP14 | `15% → 12%` | `8% → 6%` | `6.00/1.00 → 9.00/1.75` |
| F2FS X360 | `10% → 8%` | `5% → 3%` | `6.00/1.00 → 9.00/1.75` |

Every desktop profile declares `ZRAM_EMERGENCY_WORK_MAX_PAGES=8192`: one envelope
for requested recompression across all tiers plus selected writeback. When disk
relief is available, at most half goes to recompression, leaving budget for
writeback. Per-tier limits, daily quota and fresh pre-I/O pressure can only
reduce admitted work. At 4 KiB per base page, 8,192 pages are 32 MiB; this is
not a wall-clock latency guarantee.

`ZRAM_PRESSURE_WORK_MAX_PAGES=16384` also bounds all work in ordinary pressure
mode. Raising an emergency threshold must not leave the intervening pressure
band with the old, much larger recompression burst. Both runtime configuration
and publication validation require emergency <= pressure <= absolute pass limit.

The emergency writeback cap changes from 32,768 to 8,192 pages, adaptive batch
from 128 to 64, I/O-pressure batch from 16 to 8 and I/O-pressure page cap from
4,096 to 2,048. Pressure batch changes from 64 to 32. Emergency compaction is
omitted because device-wide compaction has no page budget. Pressure compaction
is also deferred to normal maintenance. Bounded authoritative candidate-telemetry
rules remain intact.

Cooldown changes from thirty to ninety seconds. The controller remembers its
last completed emergency separately, preventing state oscillation from bypassing
cooldown. The first emergency still escalates immediately. A process restart
begins a new controller lifetime; no cross-restart cooldown guarantee is made.
Manual maintenance remains explicit and uses the existing ownership lock.
The implementation is shared with servers; its non-desktop default work
envelopes are 32,768 pressure pages and 16,384 emergency pages. Other server
profile thresholds and scheduling remain unchanged.

## Review and rollback

Review profile values, rendered units, receipt and the complete candidate
together, following [operations](operations.md). Retain the previous complete
release and journal. Rollback selects that whole tree, never a mixture of
frontends and payloads. No publication-pointer tool was executed here.

For an existing installation, retain the prior rendered root-owned policy and
account unit/profile files before separately authorized rollout, and restore
them as one reviewed set if required. Reloading configuration does not move an
already-running compiler into a new cgroup. Session restart is an operator
action, outside development-host validation.

Failure fixtures remain unexecuted. Static checks and serialization establish
no boot, GUI, actual compilation under pressure, package solver, loaded policy,
OOM recovery, service or hardware acceptance.

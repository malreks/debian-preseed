# Static inspection plus controlled isolated native validation
No Subagents are to be used across this code base!

## Host scratch storage prohibition

This restriction applies to the machine running development commands only.
The Debian Installer, installed target, and approved isolated guests may use
their own `/tmp`, tmpfs, and other configured memory-backed filesystems.

Never use the real host's `/tmp`, `/var/tmp`, `/dev/shm`, or any tmpfs or
RAM-backed host directory for task work, downloads, staging, caches, temporary
files, parser support, build scratch space, or validation artifacts. Never
create or mount a host tmpfs. Use a private, owned directory on the checkout's
verified disk-backed filesystem, under `.build/validation/`, and explicitly set
`TMPDIR`, `TMP`, and `TEMP` for commands and their subprocesses. A helper that
ignores these settings must be corrected or stopped; no host temporary-directory
fallback is permitted. This also applies to delegated work. Private guest
filesystems inside an approved disposable VM remain within that guest boundary;
their host images, captures, scratch files, and outputs must stay on disk.

Static inspection and deterministic generation remain the default repository
workflow. Controlled QEMU/VM, rootless-container and private-chroot validation
is permitted when it is required to validate an installer, deployment, target
service, hardware contract or other native behavior. An isolated validation
environment is additional evidence; it does not replace source review,
generated-product checks or the changed-file audit.

Every isolated environment must be disposable, privately owned by the current
validation run, bounded by a hard timeout, and created only from an identified
fixture or target image. It must not expose the host root, host `/etc`, `/var`,
`/run`, `/proc`, `/sys`, `/dev`, user HOME, XDG runtime directories, D-Bus,
systemd, package-manager state, credentials, SSH agents, browser profiles,
desktop sockets, device nodes, host network namespaces or host service
sockets. Do not use privileged containers, host PID/IPC/network namespaces,
host directory mounts, device passthrough, nested virtualization without an
explicit private test boundary, or automatic fallback to host execution.

QEMU/VM validation must use a private disk/image and private writable output
tree, explicit serial or journal capture, bounded boot/install/teardown
deadlines, and no destructive operation outside that private tree. Container
validation must be rootless where possible, use an explicit image digest,
disable host mounts and privileged capabilities, and keep state under a
private fixture directory. Chroot validation must use a private root tree,
explicit interpreter/tool paths, no host bind mounts or host package scripts,
and a bounded cleanup path. Networked validation must use an isolated user-mode
or private test network and redacted fixtures; it must not mutate host routes,
interfaces, firewalls, DNS, package state or repositories.

Native validation may execute repository tests, installer entrypoints, target
services and failure-injection fixtures only inside that reviewed isolated
boundary. The validation record must include the image or fixture identity,
tool versions, command, timeout, captured result, cleanup result and deferred
checks. A failed or interrupted cleanup leaves the environment retained for
forensics and is outcome-unknown; it must not trigger broad host cleanup.
Never place credentials in image layers, command arguments, environment dumps,
URLs or logs.

Source-level checks that do not contact the host remain allowed, including
Python, shell, JSON, YAML, TOML, XML, AppArmor and CSS syntax checks,
deterministic template rendering, placeholder rendering and data-only fixture
checks. These checks must not silently fall back to the host. Native desktop,
installer, service, network, hardware and deployment claims require the
controlled isolated or explicitly approved target evidence described above.

## Absolute prohibition on host access and host changes

**NO TEST MAY READ, USE, OR MODIFY THE REAL HOST'S CONFIGURATION, SERVICES,
PACKAGE STATE, SECURITY POLICY, NETWORKING, DEVICES, OR USER DATA. NO TEST MAY
EXECUTE AN INSTALLED HOST MANAGEMENT HELPER.**

This applies to every test, fixture, discovery/import hook, test runner,
validation command, audit, benchmark, and smoke check in this repository. A
test's name, comments, mocks, temporary directory, or use of a namespace is not
proof that it is isolated.

- Never run tests or validation runners directly on the development host.
  Use the controlled isolated-validation boundary above for native execution.
  Do not use automatic fallback, an opt-in environment variable that escapes
  the boundary, or elevated privileges without an explicitly reviewed fixture.
- Never bind the host root, host `/etc`, `/var`, `/run`, `/proc`, `/sys`, `/dev`,
  user HOME, runtime sockets, or installed `/usr/local` helpers into a test.
  Namespace isolation alone does not make a host-root bind safe.
- Never contact the host system or user systemd manager, D-Bus, desktop session,
  CrowdSec API, package manager, or other running daemon. Never start, stop,
  restart, reload, enable, disable, mask, or reset host services or timers.
- Never load AppArmor policy, change host firewall rules, routes, interfaces,
  sysctls, mounts, storage, permissions, ownership, package repositories,
  package lists, credentials, or any file outside owned test fixtures.
- Never execute installed host helpers such as `/usr/local/libexec/apt-repo-local*`
  or `/usr/local/sbin/*`. Review checkout fixture programs as source only, with
  all state paths and commands explicitly controlled.
- Review privileged-command and external-service fixture implementations before
  execution. Execute them only inside the controlled isolated boundary, with
  explicit state paths and commands. No host sockets or writable host mounts
  are permitted.
- Fixture source must not inherit host HOME, XDG runtime directories, D-Bus
  addresses, service variables, credentials, or full `PATH`.
- Fixture source must bound writes to its private owned tree and reject paths
  outside that tree. Cleanup must name only resources owned by that fixture.
  These source requirements do not authorize fixture execution.

### Explicit exception: offline AppArmor parser

The user explicitly permits `apparmor_parser` for offline policy validation.
Run it with `--skip-kernel-load` (`-Q`) and `--skip-cache` (`-K`), a bounded
timeout, and one compile job. Use an explicit private parser configuration,
include tree and package feature/ABI data so parsing does not consume local
host policy, parser configuration, caches or kernel feature state. Checkout
policy and declared public Debian package support files may be staged as data
in a private directory; do not install packages or execute package scripts.
Absolute package ABI paths may be relocated in the private validation copy.
Record the parser version, package support version and any such relocation.

This exception permits parsing and compilation only. It does not permit
loading, replacing or removing kernel policy, changing host security state, or
using a host fallback. It remains separate from the pure `make build`
serialization path and from isolated native validation.

## Work in this checkout

## Cross-component contract audit is mandatory

Treat every component-specific change as a shared-contract change until the
repository evidence proves otherwise. Auditing ChatGPT, Ledger, or any other
single application in isolation is incomplete when the same policy schema,
shared environment, downloader, installer stage, servicing CLI, vendor helper,
runtime module, desktop entry, AppArmor policy, renderer, or generated payload
is used by sibling components.

For every affected component, first inventory and inspect all related
components and all shared callers. At minimum, review the complete applicable
set of managed software, including Bitwarden, QoreDB, Obsidian, Tomat, Sleek,
Postman, Discord, Tuta, Ledger, ChatGPT/Codex, and any other application that
uses the affected contract. Extend the inventory when the source reveals more
consumers; do not stop after fixing the first reported failure.

The audit must trace each affected contract through all of these layers when
present:

- shared defaults and selected host-profile overrides;
- policy templates, rendered policy files, and variable validation;
- late installer scripts, architecture gates, download categories, hashes,
  signatures, size/member/extraction limits, and retry behavior;
- servicing modules, CLI constructors, dynamic dispatch, post-install hooks,
  package maintainer bridges, and installed helper entrypoints;
- target paths, desktop entries, icons, schemas, AppArmor profiles, services,
  timers, runtime configuration, and authorization boundaries;
- tests and source fixtures that instantiate or assert the affected contract;
- generated payload, manifest, and preseed products whenever their inputs
  change.

For policy or constructor changes, enumerate every constructor and dispatch
call site, every required attribute, every policy-shape consumer, and every
component-specific policy scope. Verify that no sibling path still uses an old
argument shape, stale URL, hash, size limit, architecture branch, filename,
or hard-coded fallback. A fix is incomplete while any related call site or
rendering path remains unaudited.

Use repository-wide text and structural inspection to perform this inventory;
do not rely on the first stack trace, one application name, or one generated
file. Report the inspected sibling set, changed owners, generated artifacts,
and any remaining verification limits. Keep source checks within the static
rules below. Native tests, installer execution and deployment checks require
the controlled isolated-validation boundary at the top of this file.

`make build` is generation only. It may write exactly each suite's
`d-i/{forky,trixie}/{payload.tar.gz,payload.manifest,source.sh,receipt.json,support-matrix.json}`,
and both frontend `preseed.cfg` files. It overwrites these same regular files;
it must not create release or publication directories. It must not execute any
tests, validators, shell snippets, browser generators, policy parsers or host
management helpers, or rewrite source inputs. This pure serialization command
is permitted in the checkout. Suite `common.cfg`, `classes/`, `fragments/` and
family APT trees are authored inputs and are never rewritten by the build.
Role class files contain ordinary preseed packages, repositories and debconf
answers only. Class comments have no behavioral meaning. Installer constraints
and phase dispatch belong to the separate shared installer dispatcher. The
pure `make build` path must not invoke validation runners. Guarded `make check`
and `make validate` may run only inside the reviewed isolated-validation
boundary, with their image, timeout and cleanup recorded.

Preserve all unrelated and uncommitted work. Inspect callers and execution
helpers before editing. Keep fixes narrow and deterministic. Do not build
software from source or change the existing private Xwayland policy for Zoom
and Discord.

Following a host-impact report, do not run a host-impact or native validation
runner until its complete execution path and isolation boundary have been
reviewed. Source-level syntax, rendering and placeholder checks remain allowed
when they satisfy the isolation rules above. Static inspection must parse source
as data without importing or executing repository modules, helpers, shell
snippets, or Makefile recipes. Native validation must execute only inside the
reviewed isolated boundary and must not authorize a host repair, service
restart, or configuration change.

Report exact changed paths and checks. Distinguish static inspection, mocks,
isolated integration, and live host execution. Never claim a test passed when
it was not run. Report any interrupted validation and stale generated artifacts.

## Runtime and authority contracts

### Configuration ownership and stable local interfaces

Keep genuinely variable configuration in its owning contract. Documented local
constants and root-relative literal leaves are appropriate for stable internal
filenames and interfaces with no supported variability. Do not create a global
variable for every physical member. Local constants must not duplicate shared
roots, embed a developer-machine path, replace supported suite/profile/site
selection or expose secrets.

- `d-i/debian/repo.env` owns repository defaults and shared repository-relative
  `DIR_*` roots. It is a small restricted data contract, with parent-derived
  roots and no `FILE_*` inventory. Preseed, bootstrap and common adapters use
  the single `source_load_repo_env` parser. Never dot-source or `eval` this
  configuration, copy its roots into target settings, or load it on the target.
- `d-i/debian/hosts/installer/runtime.env` owns installed-system target paths,
  target state and target policy values. Keep its hierarchy parent-first and
  publish concrete rendered values. Target programs must not source this file
  at runtime, and installer-only paths must not be added to it.
- `d-i/debian/hooks/installer/di.env` owns d-i-only destinations and state: the
  mounted target, temporary/runtime directories, phase hooks, partman interfaces
  and installer logs. It must not become an installed target environment or a
  repository source-member catalog.
- Target source assets may carry `__INSTALLER_PATH_*__` placeholders. Render
  them once at the shared publication boundary from the validated target
  contract, reject unresolved tokens, and do not add ad-hoc substitutions.
- `hosts/profiles/` owns validated policy and configuration data, including
  profile overrides. `hosts/themes/` owns appearance data and marker values.
  Neither owns repository, target or installer roots. Stable relative members
  in their catalogs are data interfaces; target paths still use the shared
  contract and placeholder renderer.

When changing configuration or moving a path, search every producer, consumer,
renderer, hook, generated product, payload member and diagnostic source label.
Keep source labels tied to the resolved physical root-relative member so d-i
failures identify the actual file. Preserve credentials in the dedicated
protected input channel; configuration and generated indexes are public data.

### Canonical runtime-path contract

`d-i/debian/hosts/installer/runtime.env` is the single authored path contract
for installed-system target paths. Keep its assignments in parent-first order
and derive every child from the nearest canonical parent. Do not add aliases
that repeat the same path or introduce a second owner for a root. Repository
defaults and shared roots belong in `d-i/debian/repo.env`; installer-only destination
and state paths belong in `d-i/debian/hooks/installer/di.env`.

The target hierarchy is fixed. The standard system roots include `/etc`, `/bin`,
`/sbin`, `/lib`, `/lib64`, `/usr`, `/var`, `/run`, `/tmp`, `/dev`, `/proc`,
`/sys`, `/boot`, `/home`, `/root`, `/opt`, `/srv`, `/pool`, and `/data`. The
`/usr` tree owns its binary, library, library-execution, and share children;
`/usr/local` owns the project-managed binary, administrative, library,
library-execution, and share trees. Package GTK/XKB data, the Debian Python
modules, the unversioned project Python modules, Perl modules, and hardware-tuning
modules each have one canonical root. `/usr/libexec` remains distinct from
`/usr/local/libexec`. Every package, systemd, AppArmor, firstboot, installer
state, logging, D-Bus, language, and component subtree derives from one of
these parents.

The installed-system contract owns target paths and state. The installer
contract owns the mounted target, temporary working areas, installer hook
directories, partman interfaces, and the installer log. The repository
contract owns repository defaults and shared checkout-relative roots. Keep those contracts in their
respective files; never publish installer-only state into the installed
system, duplicate a root, or introduce an alias whose value is only another
alias. After entering the target, use target-relative values directly and do
not prepend the mount point a second time.

Name concrete files, fixed executable paths, and process search paths according
to the consumer's explicit interface. Do not add process-search aliases that
merely repeat another runtime value; derive a search path in the consuming
script or wrapper. Stable internal leaves and exact Debian/FHS, interpreter, package, AppArmor
or systemd interfaces may be local constants; document the interface beside
the consumer and keep configurable/shared roots in their canonical contract.

When adding or moving a path, search every shell, Dash, Perl, Python, systemd,
AppArmor, Waybar/Labwc, preseed, late-command, target-hook, generated asset,
payload and source-fixture consumer. Replace stale duplicate project roots and
unresolved variables together, then regenerate the authorized products. A
changed path contract is incomplete while any consumer still references a
removed key or an equivalent duplicated root. The shared installer target
staging boundary canonicalizes legacy absolute destination spellings through
these roots before it validates or publishes a file; new callers must pass the
canonical variables directly, while exact paths embedded inside target helper
interfaces remain documented package/FHS contracts.

Target source assets may use the shared installer path-placeholder namespace.
The late target publication boundary renders those tokens from the validated
runtime contract before publishing a file into the target, then rejects every
unresolved installer token. Systemd units, wrappers, Python, Perl, desktop
entries, and AppArmor source profiles must use the same renderer when a
project-owned target path is represented by a placeholder; the installed file
must contain a concrete target path and must never depend on the runtime
environment file.
Do not perform ad-hoc substitutions in individual callers or create a second
path renderer. The AppArmor metadata file contains profile metadata only and
does not redefine filesystem roots. The repository file owns shared repository-relative roots and defaults,
while the installer file owns installer-only destinations and state. Neither is the installed target filesystem contract.
Shared repository roots follow their parent hierarchy; fixed source files
remain root-relative interfaces at their callers. A repository root for a
target-side Python tree remains an acquisition path and is never an installed
target path. Never replace a target asset's placeholder with a
literal merely to satisfy a source-level check; render or compare the
placeholder through the shared renderer instead.

- Installation targets are Debian Forky and Trixie. Native Debian packages
  follow the selected suite candidates, without fixed version assumptions. Validate the
  rendered target's interpreter, packaged modules and service contracts; do not
  infer target compatibility from the development host.
- Trace an affected entrypoint through its delegates, renderer, installed paths
  and applicable AppArmor, authorization and service policy before editing.
  At the existing installation verification boundary, reject unresolved
  installer tokens, invalid configured identifiers, missing delegates and
  incorrect code ownership or modes before consumer activation. Offline staging
  must not start services or contact a running host manager.
- Keep same-UID desktop state distinct from privileged code/import authority.
  Privileged imports consume validated private snapshots. Do not execute
  managed Perl imports or their BEGIN blocks as a host inspection technique.
- Preserve the shared Perl capture API's raw wait status, including timeout
  `124 << 8` and signal bits. Decode exactly once at public adapters; cover
  affected adapters with fixtures rather than rewriting unrelated runners.
- Make operation deadlines cover streaming, retries and final waits, with a
  separate bounded cleanup budget. Retain owning service cgroups for jobs that
  daemonize or escape a session. Preserve intentional interactive operations.
- In the root container-bootstrap runner, pin processes with pidfds before
  validating their current session and liveness; signal only verified pinned
  identities. Close descriptors on every path and retain the total cleanup
  deadline. Missing identity evidence must not trigger a numeric-PID fallback.
- Bind selected device, model staging, namespace and storage identities through
  mode changes and mutation. If an installed tool cannot bind the selected
  identity safely, return unavailable before mutation; do not invent selectors
  or substitute a different device.
- Preserve the rootless container engine, shared socket authority, service
  lifetime and existing-store no-reset rules when changing lifecycle helpers.

## Recovery, concurrency and bounded artifacts

- Validate a complete candidate before publication. Keep AppArmor parent and
  all affected local child modes consistent before the single explicit reload,
  then verify the loaded result inside the transaction.
- Keep standalone nftables recovery separate from the desktop transaction.
  Restore only owned tables and previous file bytes, metadata or absence;
  preserve unrelated policy.
- Retain private recovery material until restoration and any required reload
  are proven. A failure return alone does not prove rollback. On uncertainty,
  report the retained recovery path and a distinct outcome-unknown result.
- Synchronize durable published files, recovery files and their parent
  directories at the relevant transaction boundaries. Do not impose durable
  writes on unrelated transient UI state.
- Prune and reset use the same ownership locks as writers. Validate names and
  restat identity while holding the lock; skip active state. Do not introduce
  a second competing lock protocol or broaden cleanup ownership.
- Enforce aggregate parser/extraction limits during work, before member lists,
  expanded bytes or inode use can exhaust resources. Reject unsafe members,
  reuse packaged tools and existing isolation, and retain workspaces when
  worker termination cannot be proved. A watchdog is not a filesystem quota.
- Preserve final artifact identity checks when accepting staging names. Keep
  temporary files private and pass passwords through private inputs, never
  command arguments or diagnostics. Consume repaired output in the next stage
  and require a valid final artifact before reporting success.
- Document artifact trust accurately: content hashes establish byte
  consistency, vendor signatures establish the verified vendor claim, and local
  repository signing authenticates the local publisher. These are distinct.
  Check each redirect before requesting its destination under the applicable
  input policy; preserve HTTPS, credential handling and bounded hop/time limits.
- Keep failure, cancellation, unavailable and outcome-unknown results distinct
  across callers and UI adapters. Do not automatically retry an uncertain
  mutation. Keep secrets and raw hostile payloads out of diagnostics.

## Revision-specific acceptance evidence

- For affected audit work, review the relevant findings and acceptance gates in
  `debian-preseed-de-audit.md`, the current implementation and its callers.
  Historical remediation reports describe their recorded snapshots; they do
  not establish acceptance of a later working tree.
- Review `docs/test-isolation.md` for the execution boundary. Native integration
  checks and test discovery imports may run only inside the reviewed isolated
  environment described at the top of this file; never use a host fallback.
  Data-only syntax, rendering and placeholder checks remain permitted under the
  source-level boundary above. The explicitly permitted offline AppArmor parser
  remains separate from isolated native validation.
- Author and inspect failure-injection fixtures for changed contracts: exact
  previous-state recovery or retained evidence, concurrent writer/cleanup
  ownership, identity replacement, bounded termination and correct result
  propagation. Target policy, boot, GUI, network and hardware behavior remains
  unverified until native evidence is recorded. Native evidence may be produced
  only inside the reviewed isolated-validation boundary.
- Record the exact source revision or working-tree fingerprint, fixture
  revision, generated artifact hashes and target image/package versions with
  recorded evidence when available. Distinguish unexecuted fixtures and static
  inspection from historical execution evidence; do not fabricate test, target
  image or package results. List verification limits explicitly.
- Rebuild generated payload products when their inputs change, using only the
  reviewed pure serialization path. Compare generated bytes and manifest pins
  with the current inputs as data. Serialization consistency does not prove
  rendered runtime behavior or a passing acceptance gate.
- Keep native application launch and private Zoom/Discord launch/shutdown as
  regression invariants. Preserve exactly the existing two-app eligibility
  boundary without changing Xwayland implementation or configuration.

## Completion static audit

When the current goal or task is complete, run the changed-file-only audit before
reporting completion:

```text
python3 -B tools/post_change_check.py
```

The equivalent Make target is `make post-change-check`. The audit enumerates
tracked staged changes, tracked unstaged changes, and untracked files, then
checks only the existing regular files in that set. It must fail on Python
syntax errors, shell syntax errors, ShellCheck error diagnostics, changed-shell
unbound variables (`SC2154`), malformed changed JSON/YAML/TOML/XML/INI-like
data, malformed environment/TSV data, malformed theme markers in changed target
assets, changed AppArmor structural hazards, unreadable changed tar archives,
or `git diff --check` failures. It must not recurse through untouched files.
Every other changed regular text file is still checked for valid UTF-8 and NUL
content, while changed binary archives are checked for readable archive
structure. Language-specific parsers that would execute repository code (such
as managed Perl BEGIN blocks or live policy loaders) remain outside this
static command and must not be substituted with host execution.

When a payload input changes, run the permitted pure `make build` command, then
run the audit so the generated payload, manifest, and preseed changes are
included in the changed-file set. Do not replace this audit with an unreviewed
host-facing test. Approved native installer, service and deployment checks are
additional evidence and must use the isolated-validation boundary.

## Expected external and installer state

CrowdSec pending enrollment, Tailscale pending enrollment, and any other
pending-enrollment state recorded in task logs are expected until the user
approves enrollment in the respective external service. Treat those records as
informational and do not classify them as installer or desktop failures.

An offline target package maintainer script may report an AppArmor reload
failure while the installer kernel is unavailable. Preserve the deferred target
activation path and verify the staged policy contract instead of loading policy
into the development host. Hardware or compositor diagnostics such as a DRM
`Device or resource busy` event require target evidence before any source change;
do not add speculative global workarounds.

## Waybar native-menu and wrapper alignment

Waybar 0.15.0 native GTK menus are a shared module contract. Keep the existing
module type and native menu owner when changing a button. A menu action is
complete only when all of these data sources agree:

- the module object in `etc/skel-desktop/.config/waybar/modules/*.tmpl`, including
  its native `menu` event or the explicitly authorized fixed popup-service
  click binding, plus `menu-file` and `menu-actions`;
- the matching GTK builder file in `waybar/gtk/*-menu.xml.tmpl`, with exactly the
  same leaf object IDs;
- `labwc-waybar-run`'s fixed argv allow-list and any dispatcher allow-list;
- the renderer and target-asset staging cases in
  `scripts/desktop/components/core-renderers.sh.tmpl` and `target-assets.sh`;
- the Waybar, menu, helper-transition, and target-file AppArmor rules;
- `verify.sh.tmpl`, first-login/firstboot provisioning, and any payload or
  appearance paths that copy or customize the asset; and
- the appearance registry (`fields.json.tmpl`) and its source-line mappings for
  every theme token in the module or stylesheet.
- CPU, memory, and storage launch changes also cross the fixed argv table in
  `labwc-waybar-run`, the terminal wrapper, the managed application transient
  builder in `labwc_managed_app/generic.py`, the per-launch state helper, and
  their AppArmor transitions. The state marker belongs to the transient that
  owns the real terminal process, not to a short-lived click dispatcher.

Do not create a second menu action table in a new helper. Do not replace a
built-in or custom module merely because the module name changes: both use the
same native GTK menu contract. Preserve the existing Apps drawer ownership and
its `PRELIGHT`/expanded state selectors; never add a global active flag or a
second drawer protocol. If an action ID changes, update the XML ID, the module
map, the fixed argv allow-list, policy transitions, staged asset lists,
verification paths, and the relevant appearance mappings in one change, then
run the pure build and changed-file audit.

Waybar 0.15.0's native menu contract does not publish a menu-open CSS class or
an external close/destroy callback. Do not claim authoritative popup latching
from `:active`, `:prelight`, a click-only marker, a fixed timer, or a status
reader that cannot observe GTK menu destruction. If a future requirement needs
that state, use the explicitly authorized bounded transient GTK-menu service as
the lifecycle owner. The service owns one exact marker for the button, keeps
the marker while its GTK menu is mapped, and clears it from the menu's close,
destroy, Escape, outside-click, signal, failure, and service-exit paths. It
must reuse the existing rendered GtkBuilder XML and `menu-actions` map through
the fixed `labwc-waybar-run` allow-list; it must not create another action
table, an unbounded observer, or a second competing lifecycle protocol.
When that service owns the popup, the module remains the same built-in or
existing custom Waybar module; its `menu-file` and `menu-actions` data remain
the canonical contract and the fixed click binding points at the service. Do
not mix the service owner with Waybar's own `menu` event for the same click,
because that would create two popup owners.

The installation validator must keep these contracts distinct: native modules
must register exactly one press event through `menu`, while the current
Wayscriber custom popup owner must have exactly one fixed
`on-click-release` binding to `labwc-waybar-run --menu=wayscriber`, no native
`menu` event, and its fixed right-release action. Its existing GtkBuilder
asset and action map remain part of the same validated contract.

Use the transient popup owner only for custom buttons whose active class needs
an authoritative close/destroy path (currently Tomat, Wayscriber,
notifications, and power). Native status and clock modules use Waybar's own
`menu` plus `menu-file` contract and do not receive popup active state. Their
click event must remain the module's declared menu event; do not route those
clicks through `labwc-waybar-menu` merely to manufacture a marker.

An `on-click-release` command is reserved for a fixed action or the custom
popup-owner path. For Tomat, Wayscriber, notifications, and power it launches
the bounded transient whose `ExecStartPre`/`ExecStopPost` state marker and GTK
`deactivate`/`selection-done`/`hide`/`destroy` callbacks provide the exact
active-class lifetime. Native audio, battery, brightness, and clock menus must
use their Waybar `menu` event directly, so they do not incur a transient or a
second popup owner.

**Native Waybar module identity is immutable.** Never convert a built-in
Waybar module (`clock`, `pulseaudio`, `backlight`, `battery`, or any other
packaged module) into `custom/*` to obtain popup state. Keep the module's
existing native type, status reader, scroll behavior, and native
`menu/menu-file/menu-actions` contract. Popup lifecycle ownership is supplied
by the authorized transient GTK-menu service; its per-button marker styles a
widget only where a supported Waybar class consumer exists. A lifecycle marker
alone does not style a native widget and is never a reason to rewrite the
module as a custom JSON reader.

The launcher is a separate precedent, not a generic native-module interface:
`custom/launcher` has an `exec` JSON reader with `signal: 8`, and
`labwc-main-menu` publishes its marker then sends `RTMIN+8`, which causes that
reader to return `class: active`. A marker or transient service by itself does
not add a CSS class to a native module. Do not ship `.active` selectors and
claim a native popup latch unless the target Waybar contract actually updates
that module's class. Theme colors may be prepared for an authorized active
class, but the class source and its close path must be identified separately.

The `/usr/local/bin` versus `/usr/local/libexec` location is an explicit
interface decision. Keep user-facing, desktop-entry, GIO, or service `ExecStart`
entrypoints in `/usr/local/bin` when callers and AppArmor policy already use
that stable path. Keep private implementation helpers and non-user-facing
status/control workers in `/usr/local/libexec`. Relocating an existing wrapper
requires an audited update of every caller, desktop entry, systemd unit,
AppArmor transition, allow-list, renderer, target asset, verification path, and
generated payload; do not move files solely to make the directory layout look
more conventional.

## Repository configuration and source staging

- `repo.env` contains the supported repository defaults and genuinely shared
  `DIR_*` roots. It is restricted assignment data, not shell code. Keep shared
  roots parent-derived; do not restore a `FILE_*` inventory, aliases for every
  file, or a second configuration authority.
- Stable source members are documented root-relative interfaces at their
  callers, including the physical `.tmpl` suffix where present. Local constants
  and literal leaves are allowed when that interface has no supported
  variability. Keep suite/profile/site choices, configurable roots and policy
  in their owning contracts; never substitute a developer-machine path or
  duplicate a shared root.
- Preseed, bootstrap and common adapters share `source_load_repo_env`. Its
  restricted AWK parser rejects executable syntax, unknown/duplicate/missing
  keys, undefined parents and unsafe relative paths. Never dot-source or
  `eval` repository configuration, and never load it on the installed target.
- Build validates supported configuration and physical source members, and
  compiles `catalog/compiled/source-members.tsv` from the captured snapshot.
  Selected APT publication uses the smaller `apt-assets.tsv` table. Those
  generated indexes carry membership data; they are not exported environment
  variables or an alternative authored path contract.
- Resolve dynamic members against the captured membership table at the owning
  loader/publication boundary. Retain containment, direct-file, template,
  ownership and permission checks there. Diagnostics name the resolved physical
  root-relative member and source line, remain advisory, and never trigger a
  fetch or change a successful operation into a failure.
- Installed paths and policy remain in `hosts/installer/runtime.env`; d-i-only
  destinations and state remain in `hooks/installer/di.env`. Profiles and themes
  retain policy/appearance ownership. Installed programs receive concrete
  rendered configuration and must not source these installer input files.
- A configuration or member change requires a consumer, diagnostic, fixture and
  generated-product audit. Preserve Dash/BusyBox compatibility, phase and
  target-root boundaries, and the single target-placeholder renderer. Do not
  add a large exported environment or an installer `stat` dependency.

## Current desktop and storage remediation contract

- The active Waybar repair keeps native module identities and popup ownership:
  external and clock normal text use weight 500, the CPU btop profile fits the
  managed terminal height, the native backlight module keeps `cursor: true`
  and Waybar's native device selection, and the Wayscriber control retains its
  existing GTK menu and transient owner with the blue symbolic pen SVG.
- The Wi-Fi helper may unlink only its exact prepared profile; the AppArmor rule
  stays exact and read-only for the surrounding directory. Swap fallback state
  is published from the frozen layout and canonicalized to its matching
  PARTUUID before cryptsetup. The hyprpolkit client may set aquamarine's
  modifier-free allocator flag for itself only; it must never alter labwc or
  the private Discord/Zoom XWayland boundary.
- Development scratch remains on disk under `.build/validation/`; do not use
  host `/tmp`, `/var/tmp`, `/dev/shm`, or tmpfs for these repairs.
- Audit access-denied rules must match permission failures (`EACCES`/`EPERM`)
  explicitly; do not turn expected systemd symlink-resolution `ELOOP` results
  into recurring audit failure noise.
- Managed desktop reconciliation owns every generated launcher `Exec`: remove
  package vendor action sections before publication and recreate only explicit
  project policy actions. Do not retain a fallback that imports all accelerator
  or vendor actions into account-local files.
- Browser veth sessions use the shared web-port allowlist (including the
  Technitium `5380` portal alongside Incus/HTTPS ports). Chromium-family and
  Mullvad profiles bind USB/hidraw roots for hotplug WebUSB/WebHID, while
  active-seat udev ACLs remain the Ledger Stax authorization boundary.

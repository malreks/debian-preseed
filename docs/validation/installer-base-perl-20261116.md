The first base-installer hook now prepares the target using its existing Perl
runtime. This supersedes the finish-install/Python placement in
[the earlier staging record](installer-staging-20261116.md). The starting revision
was `7fb2f92`; this record describes the subsequent uncommitted working tree.

The generated release is
`d1e69f71f488c1744f0e75ca7e3b18713aae221ebd0875abed91b65fa702ee7f`;
its source fingerprint is
`5b8e15d9dee09dddb1c61e1f1ff4746887a3b7ae23a78d2b2ebf4a0bb06a840c`.
Both suite payload archives have SHA-256
`497f49738c9c42581fedd66ec833ef53f542b85a4b8a9919fc2cd19bd24083ec`,
and both manifests have SHA-256
`96230aa139f997390b6835bad620253688c7a9bb198bd93680fd6d5ced10f719`.
The per-suite preseed, receipt, source and support-matrix hashes are retained in
the private validation run's `source-evidence.json`.

Primary package contents establish the phase boundary for both suites:

| Package inspected as data | Forky | Trixie |
| --- | --- | --- |
| base-installer / bootstrap-base | 1.230 | 1.226 |
| pkgsel | 0.87 | 0.85 |
| finish-install | 2.126 | 2.124 |
| di-utils | 1.157 | 1.155 |

In both bootstrap-base postinsts, `install_base_system` precedes
`pre_install_hooks`, followed by `setup_dev`, APT configuration/update,
`post_install_hooks`, kernel selection/installation and extra packages. The
pre-install hook function executes the ordered files in Debian's
`/usr/lib/base-installer.d`. It deliberately removes the target APT source list
before those hooks. The package contents and their metadata hashes are retained
in the earlier private run's `hook-evidence` directory; the ordering and product
hashes are recorded in `source-evidence.json`.

`hooks/installer/d-i/early.sh` installs `base-stage.d/00rendertarget` first, before
the existing `10-apt-install-policy` and `20-fstab-guard`. The executable name has
no hyphen. All executable base hooks now use the existing supervisor, because
Debian's base hook runner otherwise converts a child failure into a warning.
The preparation hook requires the running bootstrap-base ownership record;
waiting for that same component's completion from inside it would deadlock.

The resulting order is:

```text
debootstrap -> 00rendertarget -> remaining base hooks -> base APT/kernel
            -> apt-setup -> pre-pkgsel/DKMS -> pkgsel -> late_command
```

An empty target cannot execute its base Perl yet. This is the first project base
hook after debootstrap has supplied the usable target. No interpreter was added
to `base-installer/includes`, and preparation performs no APT transaction. The
hook enters the mounted target with plain `chroot`, a cleared environment and
the canonical `/usr/bin/perl` interpreter interface. It does not use debconf or
the `in-target` passthrough protocol for rendering.

`scripts/common/render.pl` replaces the Python batch renderer. It uses only
`strict`, `warnings`, `bytes`, `constant`, `Fcntl`, `File::Temp`, `IPC::Open2` and
`Cwd`, supplied by the minimal base runtime. It reads maps as bytes, validates
the private candidate and aggregate limits, checks the complete copied manifest
with one packaged `sha256sum` process, and renders the scripts, target assets and
installer hooks in one batch. One streaming hasher fingerprints the output
without another recursive read; its pipe and child are closed/reaped on render
errors too. The shared Perl inventory publishes complete selected namespaces.

Logging values and eligible theme defaults are rendered with paths. Appearance
mapping/token metadata, editor grammar and reusable future-account templates
retain their intended fields. Typed operation-specific inputs remain with their
existing publication adapters. Managed software's downloader, constructor,
policy and vendor interfaces were not changed by the interpreter replacement.
The complete desktop/server payload comparison includes Bitwarden, QoreDB,
Obsidian, Tomat, Sleek, Postman, Discord, Tuta, Ledger, ChatGPT/Codex, Filen,
Tor Browser and the other selected software. Private Xwayland remains unchanged.

Pre-pkgsel requires the prepared workspace. Both the class dispatcher and the
secure-boot/DKMS helper have lost their separate per-file path-rendering pass.
The standard bootstrap copies the prepared helper rather than acquiring it
again. Late dispatch and managed software require the same completed workspace;
late cleanup also uses Perl. The old finish-install rendering hook and selector
are removed. `repo.env` names the new physical renderer and base-hook members;
installer staging state remains owned by `di.env`.

The shared diagnostic relay now accepts installer commands directly, with the
target-command API delegating to it. It drains output, captures the exact child
status, and sends redacted live output to TTY4 without depending on `tee` or
POSIX pipeline status. A missing or failed console remains advisory; output
capture failure is fatal when the command itself succeeded. Rendering remains
bounded by the existing 180-second operation deadline.

The earlier unconditional bootstrap `APT::Keep-Fds:: "3"` addition was removed.
Descriptor inheritance through APT/preconfiguration was not established by the
old symptom alone, so that global protocol change is not retained. The real
`ca-certificates`/preconfiguration pause still requires a complete installer
run for diagnosis; the fixture does not establish its live cause or resolution.

The validation run uses two separate disposable QEMU TCG boots, with no NICs,
disks, host mounts, host sockets, credentials or device passthrough. Each guest
has 1 GiB RAM and two virtual CPUs. Guest-only device nodes and a private PTY
exercise the target runtime and TTY4. The guest target contains extracted
`perl-base`, coreutils and public package library files; it has no Python
interpreter, JSON::PP or Digest::SHA. Python exists outside that target solely
for the comparison harness and previous algorithm used as a byte oracle.
Public package data was downloaded over HTTPS and checked against the recorded
suite Packages sizes/SHA-256 values. These fixture downloads did not separately
verify an archive signing chain or execute package maintainer scripts.

The reviewed host launch commands, with `TMPDIR`, `TMP` and `TEMP` explicitly
set to the run's disk-backed private scratch directory, are:

```text
python3 -B .build/validation/installer-hooks-final-20261116/run_vm.py trixie
python3 -B .build/validation/installer-hooks-final-20261116/run_vm.py forky
```

Each launcher applies `timeout --signal=TERM --kill-after=5s 240s`, a separate
250-second parent deadline, QEMU's sandbox, explicit serial capture, and no
default/user configuration. The tool is QEMU 11.1.2. The public installer kernel
has SHA-256
`2b2358b37674d2505350528875bb17afae2a36522a9e8a9417eaca65a7da0e08`;
the original initrd has SHA-256
`57303d157cffce3fa402301667fbc9b2280aa7372082b081e777375ae49da5f2`.
Per-suite image, driver, hook-fixture and serial hashes, tool versions, arguments,
exit status and cleanup are retained in the suite's VM JSON record.

Both suites completed every case with guest/QEMU exit 0. The final guest images
have SHA-256 `c265acdc3263f991f19ac9e0cb66af1b2287221057bfcab6384df52d336828f4`
(Forky) and `d27ec6de5ff7f326cd73363845d2db8a8dadb65755aa9aee605bd380aed98e9a`
(Trixie). The shared driver has SHA-256
`a2ddecf665f0979bce32e1d070724c7c2e48cd16f285528d3432bf9abd4258c1`;
the hook fixture has SHA-256
`94f2d723da43f22ada7668e0a2e3851fc8605bc8a9e840e669eeb136d4f119ee`.

| Completed observation | Forky | Trixie |
| --- | --- | --- |
| perl-base package/runtime | 5.44.0-3 / v5.44.0 | 5.40.1-6+deb13u1 / v5.40.1 |
| Desktop render plus Perl publication | 4.149 s; 152 modules | 4.168 s; 152 modules |
| Server render plus Perl publication | 3.864 s; 102 modules | 5.117 s; 102 modules |
| Full payload / changed render files | 2,429 / 1,088 | 2,429 / 1,088 |
| Full desktop/server source and module byte parity | Pass | Pass |
| Eight failure injections; failed candidates retained without receipt | Pass | Pass |
| Real first-hook chroot/Perl publication; ready marker only on success | Pass | Pass |
| Real bootstrap adoption with fetch sentinel; DKMS from prepared tree | Pass | Pass |
| Private character-device TTY4, live acknowledgement and redaction | Pass | Pass |
| Command status 37; capture-failure status 125 | Pass | Pass |
| Cleanup preserves published modules and rejects incomplete work | Pass | Pass |
| Complete guest duration | 89.883 s | 97.021 s |

The eight failures cover unknown path fields, modified/missing members,
symlinks, hardlinks, aggregate manifest bounds, duplicate map keys and existing
publication namespaces. The hook case injects an empty path map and checks the
specific missing-field cause, absent ready marker and retained private candidate,
then exercises success with the complete map. Acquisition, phase context,
account inputs and policy/theme-map preparation are controlled fixture inputs;
the real hook, chroot, Perl renderer, module publication, bootstrap adoption,
shared logger and console redactor execute inside the guest.

Earlier fixture attempts stopped for missing synthetic target device nodes,
missing checksum-library support and exhausted guest storage. Their images,
serial captures and failed result records are retained. The corrected fixture
releases completed comparison copies with the real cleanup operation before
the first-hook cases, keeping the same 1 GiB bound. Every QEMU process was
reaped and guest memory released; there was no host fallback or host repair.

`make build` and `python3 -B tools/post_change_check.py` passed for the current
source/products before this documentation update. The final changed-file audit
includes this record and the historical record's supersession link. The authored
Python unittest module was rewritten for the Perl CLI and inspected as source;
it was not executed through its separate container-only gate. The isolated
driver supplies the native cases above.

These timings are emulated fixture command measurements, not total installer
speed measurements. A complete unattended installation, real mirror/vendor
downloads, actual DKMS/kernel hooks, boot, hardware, GUI and live AppArmor policy
remain outside this evidence. The earlier AppArmor corrections and all six
development-host scratch restrictions remain in place. Host scratch, images,
captures and downloads stayed under the private disk-backed validation tree;
guest and installed-system temporary-filesystem policy was not changed.

# Finish-install target environment initialization

Base revision: `de06c4da3a0a2c52b091598c5af604d47f640fef`.
Generated release: `76bcd5ae24ba5e131f24b41c586f7f794e04567112e23e612feb0da021d2d780`.
Runtime source fingerprint: `3a2623146086fee011820d3c4b8fd942c781ad9fd7b42ea80f8d38e1dd19ce26`.
Source/fixture/checker fingerprint: `692f67e477a8acb6e232f9493bfaa3ce2d215f2a391c41988dab14ee653b95ba`.
Private captures, input hashes, commands and outcomes:
`.build/validation/finish-environment-20261119/`.

## Defect and correction

The published `94zz-10-normalize-finish` is sourced from
`hooks/installer/finish-install.d/99-normalize-finish`. In a fresh process,
common-lib loads the repository and installer path contracts. It does not
load the compiled host policy containing installed-system paths. The hook
derived its target log path using `DIR_VAR_LIB_INSTALLER_STATE` at line 36,
before its host-policy load later in the script. With `set -u`, it exited.

The downstream `94zz-99-validate-target` had the same missing input. Its
`runtime.env` is frozen partition/layout state, not the compiled target-path
contract. It never loaded `host.env` before deriving target readiness paths.

Both original hooks reproduced the exact unset parameter in the disposable
installer guest: normalizer line 36 and validator line 45. Both corrected
entrypoints load host.env through the real restricted data parser before
using target paths, preserve rejected-input exit status, and diagnose a
missing canonical state root. The normalizer also loads account/layout inputs
before restoring target-side temporary helpers. No fallback root or inherited
global target environment was added.

## Changed owners and shared-contract inspection

- `d-i/debian/hooks/installer/finish-install.d/99-normalize-finish`
- `d-i/debian/hooks/installer/finish-install.d/94zz-99-validate-target`
- `d-i/debian/tests/fixtures/contracts/finish-environment.sh`
- `tools/post_change_check.py`
- This validation record.

Inspected all five project finish hooks, their early-stage publication and
guard, common/bootstrap/transport loading, the restricted profile parser,
canonical runtime.env/di.env ownership, Btrfs/F2FS layout-state writers,
compiled host/account maps, target publication/ownership scanning and APT
policy publication. Both adjacent CUDA/APT hooks already loaded host policy;
the guard consumes installer paths only. The historical
`debian-preseed-de-audit.md` referenced by repository guidance is absent.

All **38 compiled suite/profile maps** contain the **31 canonical target
keys** referenced by the four target-consuming finish hooks. The managed
software inventory covers Bitwarden, QoreDB, Obsidian, Tomat, Sleek, Postman,
Discord, Tuta, Ledger, ChatGPT/Codex, Filen, Tor Browser and Zoom. Their
download/servicing interfaces, application selection and private Xwayland
policy were not changed. This is shared installer initialization, not native
application-launch acceptance.

The static checker now includes all four finish entrypoints in its path
publication owner set and rejects host-policy loading after the corresponding
target-path consumer. Source-data inspection rejected both saved pre-edit
snapshots and accepted all four current hooks. No hook is executed by this
static check or by the pure build.

## Validation and isolation

`make build` serialized both suites; each payload has 2,434 members. The
changed generated paths in each suite are `payload.tar.gz`, `payload.manifest`,
`receipt.json` and `preseed.cfg`. Both `source.sh` and `support-matrix.json`
remain byte-identical to the starting products. The suite payload SHA-256 is
`5504160f7ea12675fb14926fc3d242814b1476f79be78bde9f5bf69bd88291e3`;
the manifest SHA-256 is
`ae9a145d9f9b621e46f4fc02ff6620a7c433faf70a7be41295cc0d56a4456823`.

The focused complete hook chain passed in guest 5 in 107.839 seconds. It ran
09 CUDA retirement, the full finish normalizer, APT normalization/policy
publication, and final owned-file scanning/readiness publication as fresh
processes with no inherited target-path variables. Bootstrap, source/module
loading, policy parsing, filesystem normalization and readiness publication
were real. Target APT commands and the chroot boot/package audit were stubs.
The fixture checks temporary-file cleanup, account-file contents/modes,
source retirement, all sixteen target-audit arguments and readiness markers.
It verifies that readiness does not publish installation.success.

**12/12 scenario checks passed** across final guests 5 and 6: four complete
hook chains, six missing/malformed/incomplete policy rejections, and two
reproductions using the original hooks. Guest 6 completed its eleven scenarios
in 419.292 seconds. Both final guests returned QEMU status 0 and GUEST_RESULT=0;
their case-owned target mounts were cleaned up and QEMU was reaped.

| Suite | Profile | Shell | awk | Complete hook chain |
| --- | --- | --- | --- | --- |
| Forky | desktop/btrfs-de-p15s | Dash | BusyBox | passed, guest 5 |
| Forky | server/btrfs-srv-flex | BusyBox ash | BusyBox | passed, guest 6 |
| Trixie | desktop/f2fs-de-hp14 | BusyBox ash | mawk | passed, guest 6 |
| Trixie | server/f2fs-srv-hp14 | Dash | mawk | passed, guest 6 |

Policy rejections were checked for both corrected entrypoints, with malformed
data retaining status 2. The rejected normalizer inputs left target temporary
data intact and did not evaluate injected shell text; rejected validator
inputs never entered the chroot audit. The fixture uses the real policy
parser and common bootstrap, rather than substituting their implementations.

Development guests 1–4 exposed fixture setup errors: the fixed /target
interface, target mount mode, mismatched fixture Secure Boot mode, and an
incomplete fixture APT asset cache. Their captures and images are retained;
all six QEMU processes were reaped. No timeout or interrupted cleanup occurred.
The final static check is `python3 -B tools/post_change_check.py`, followed by
`git diff --check`; captures are `post-change-check-final.log` and
`diff-check-final.log`. The prior expanded static check passed, including the
four new finish-entrypoint ordering contracts.

The reviewed guest boundary uses QEMU 11.1.2 (Debian 1:11.1.2+ds-3), q35/TCG,
one CPU and 768 MiB, no NIC/monitor/host mounts/devices/sockets, no user QEMU
configuration, an explicit QEMU sandbox and captured serial output. Target
`/target` is a case-owned guest tmpfs, unmounted by that case. All host images,
logs and scratch remain on verified btrfs under the private validation tree;
TMPDIR/TMP/TEMP are explicit. There is no host execution fallback.
Final probe/matrix deadlines were 180/600 seconds, each with five seconds for
termination and an enclosing 190/610 second subprocess bound. Exact commands
and cleared environments are retained as `qemu-command-5.json` and
`qemu-command-6.json`.

Image/runtime identity: Trixie installer kernel `6.12.107+deb13-amd64`,
BusyBox `1:1.37.0-6+b9`, Dash `0.5.12-12`, mawk `1.3.4.20250131-1`.
Forky and Trixie policy data use these Trixie binaries; no Forky OS boot is
claimed. Base kernel SHA-256:
`2b2358b37674d2505350528875bb17afae2a36522a9e8a9417eaca65a7da0e08`.
Base initrd SHA-256:
`57303d157cffce3fa402301667fbc9b2280aa7372082b081e777375ae49da5f2`.
Guest 5 fixture initrd SHA-256:
`b0e98ca6f5739bd4471fafb2f3cb23d47e2ee37dc5066cff5943ea18bd0f3890`.
Guest 6 fixture initrd SHA-256:
`b1057266a57e0d8ffbbca6b4340d335b88176a5734e1c43ea9c060507d898288`.
Images and public package hashes are checked by the data-only image serializer;
the fixture stages a selected payload receipt without testing acquisition.

Full installation, real APT/network access, boot/package acceptance,
NVIDIA/DKMS, Secure Boot devices and application/hardware behavior remain
unverified. The full unittest suite is not run. The final installation must
consume matching rebuilt preseed, payload and manifest products; these changes
do not update an already cached installer snapshot or publish a remote release.

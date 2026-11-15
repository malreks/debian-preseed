# Tor Browser target-shell correction, 2026-11-15

## Observed failure and owning boundary

The user reported `desktop.software`, operation
`install_managed_application:software_install_tor_browser`, status 2, with
`sh: 18: DIR_USR_LOCAL_LIBEXEC: parameter not set`. The software dispatcher
reports its worker invocation line; the failing command is in the separate
Tor Browser module. No new installer logs were present in the checkout.

The checkout started clean at `e0d1019c820f78540df90bb61d0f5ccfca466dc7`.
The old Tor authentication shell expanded an installer variable after entering
the target. The common target executor's clean chroot branch intentionally
does not export the installer path contract. The parent could stage the helper,
while the child failed before invoking it.

The corrected module passes the rendered helper filename and private working
directory as arguments 7 and 8. The child assigns those arguments locally. The
canonical installer path renderer still owns publication; no target runtime
environment file or global variable export was added. The shared software work
directory now derives from the existing target temporary-directory placeholder.
Hash checks, vendor signature and fingerprint checks, private GnuPG directory
traps, extraction limits, application selection, and the Zoom/Discord private
Xwayland policy retain their existing behavior.

## Shared-contract inspection

Reviewed the common target executor, scalar/path publication renderer, software
worker dispatch, download/package/publication entrypoints, Tor module and
installer helper. The sibling inventory is Bitwarden, QoreDB, Obsidian, Tomat,
Sleek, Postman, Discord, Tuta, Ledger, ChatGPT/Codex desktop integration, Filen,
Zoom, Tor Browser, and the profile-controlled scx package path. The separate
Codex installer is not changed by this boundary correction.

The changed-file audit now extracts and checks all ten embedded target-shell
scripts in the two managed-software owners, including Postman's quoted shell
heredoc. Each shell is checked separately from the outer installer's variables
and ShellCheck directives, with uppercase-variable checking enabled. The check
uses source as data and does not execute the commands. This closes the blind
spot that allowed the outer shell's validation to miss the Tor child variable.

## Disposable QEMU reproduction and failure injection

The native fixture ran inside a private RAM-only guest, using QEMU 11.1.2
(`Debian 1:11.1.2+ds-3`), TCG, one virtual CPU, 512 MiB RAM, no disks, no network,
no host mounts, no host sockets, no device passthrough, no monitor, and no user
QEMU configuration. The launcher supplied only PATH, LC_ALL, and a private HOME.
The supervisor imposed a 100-second deadline. No fixture or installer command
ran on the development host.

The guest uses Debian Trixie's published netboot kernel and initrd, with a private
initramfs overlay containing the source fixture and a packaged Dash binary.
The original installer init program is replaced by the bounded fixture init;
Debian installation, APT and services are not started. The guest reported Linux
`6.12.107+deb13-amd64`, Debian kernel `6.12.107-1`, and BusyBox `1.37.0-6+b9`.
Dash is Debian `0.5.12-12`.

| Fixture input | SHA-256 |
| --- | --- |
| Debian netboot kernel | `2b2358b37674d2505350528875bb17afae2a36522a9e8a9417eaca65a7da0e08` |
| Debian netboot initrd | `57303d157cffce3fa402301667fbc9b2280aa7372082b081e777375ae49da5f2` |
| Dash package | `a8902cb6d8650134764a25fb80aec8589d858ef71ece1680a62e84816c37bb04` |
| Final combined fixture initrd | `964364080b321a779bdc81db18c15cf6c3c903a1dc894a5af7e31ea1a4bb361d` |
| Executed shell driver | `3ed7daf27da77acd321ca2f61c38703c933f566753c1b24bed06eb38ddbebbb2` |
| Corrected Tor module | `09c2985e3de57654d8e6594b4f6fee2f99e49dc6d75a28c9d717d2b6e396628f` |
| Fixture Python source | `79abf70a3e727d37c557e781a9db848b06262f2cfa361dd7205541ae9a794d82` |

Inputs were downloaded over HTTPS and compared with Debian's published
[installer checksums](https://deb.debian.org/debian/dists/trixie/main/installer-amd64/current/images/SHA256SUMS)
and [Dash package checksum](https://packages.debian.org/trixie/amd64/dash/download).
No additional local OpenPGP verification of these fixture downloads is claimed.
The Dash binary was extracted as data; package maintainer scripts were not run.

The actual Tor installer function was sourced inside the guest. The target
shell, SHA-256 checks, fingerprint-selection AWK, process status propagation and
cleanup traps were real. Downloads, APT/media installation, GPG/GPGV, the Python
archive installer, target asset staging, and media probing were controlled
mocks. The fixture deliberately removes all installer variables at the target
shell boundary. This does not test real Tor downloads, cryptographic validation
of a vendor release, archive extraction, browser launch or an entire install.

Each of the following passed in both packaged Dash and BusyBox ash (16 cases):

| Case | Expected and observed status |
| --- | --- |
| Old module, missing installer variable | 2, reproducing the reported failure |
| Corrected module, explicit helper/work-directory arguments | 0, exact helper argv verified |
| Wrong archive digest | 1, helper not invoked |
| Wrong key digest | 1, helper not invoked |
| Signature verifier failure | 71, helper not invoked |
| Wrong signing fingerprint | 1, helper not invoked |
| Archive installer failure | 73, preserved through the worker |
| Target-shell cancellation | 143, private verification directory removed |

Final guest execution took 8.380 seconds, QEMU exited 0 and was reaped, and the
guest logged its cleanup marker followed by `Power down`. RAM-only guest state
was discarded. The private input images, exact argv JSON, serial output, result
JSON and failed preparation attempts are retained as bounded validation evidence
under the run identified by `tor-shell-20261115-tj88c0fg` in the checkout's private
validation tree. `command.third.json`, `serial.third.log`, `fixture.third.json`
and `result.third.json` identify the passing run.

The first run found a missing AWK endpoint in the mocks and a fixture shutdown
PATH error; the second found a missing bracket in the helper-failure mock. Those
were fixture failures, are retained, and are not passing product evidence. No
native execution was redirected to the host. Unittest discovery and the full
installer test suite were not run; the same authored shell driver was extracted
as literal fixture data and executed only inside QEMU.

## Generated products and remaining limits

`timeout 120s make build` passed through the reviewed serialization-only path.
Both normal suite payloads contain the corrected Tor module and shared software
work-directory source, byte-identical to the current owning files. Their receipt
hashes match the archives and both suites share the following identity:

- Release: `efcde577545fe3f9f696f7a4f9b66a07e41b7933e53adad3ebacf0f0cfa0cdb2`
- Source fingerprint: `ed42b91dc24d7f62887fc7461c03d19ec7e1710150e99ba7db6266c71d74b2c6`
- Payload SHA-256: `d00d21c2e7c3a6c094f0ec7f82021aef66eeecf379b522c2bc29d15fbafafaa4`
- Payload members: 2,421.

`timeout 120s python3 -B tools/post_change_check.py` and
`timeout 15s git --no-pager diff --check` passed. The audit includes ten embedded
target shells, thirteen managed application owners, 2,248 current shared source
comparisons, both compiled class registries and the existing unshare-stage
contract. An independent stdin-only ShellCheck pass detected SC2154 for the old
child's `DIR_USR_LOCAL_LIBEXEC` and no unset-variable diagnostics for the fixed
child. This invokes parsers only, never either shell body. The initial pre-build
audit correctly rejected the then-stale generated payload.

The independent offline metadata archive is outside this repair and is not
regenerated. Complete Forky/Trixie installation, live APT package resolution,
real Tor signature/extraction and native application launch remain unverified.

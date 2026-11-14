# Security and trust boundary

This repository is privileged installer code. Boot only a preseed source you
trust. Repository work is static only: tests, managed imports, host operations
and disposable execution environments are prohibited by `AGENTS.md` and
`docs/test-isolation.md`.

## Source integrity

The generated preseed pins the bootstrap transport, payload archive and manifest
with SHA-256. Archive names, regular-file types, duplicate members, archive/member
agreement and every file hash are checked before the snapshot becomes usable.
Local source files are also checked against the built manifest, so local edits
cannot accidentally run with an outdated snapshot.

These pins detect corruption and mixed publication revisions. Seed
`url=`/`preseed/url=` and repository sources accept HTTP, HTTPS, and local
`file=` inputs. The installer performs no HTTP/HTTPS certificate, authority,
downgrade, or redirect validation; HTTP is passed directly to d-i `wget`, and
HTTPS is passed with certificate checking disabled. The existing bounded
transfer and private staging limits still apply, while the generated archive,
manifest, release, and target-suite pins remain mandatory after retrieval.
The `d-i/allow_unauthenticated_ssl=true` request is therefore accepted without
adding a second transport gate.

Redirect following is delegated to the `wget` available in the installer image,
so shorteners, GitHub endpoints, cross-authority redirects, LAN URLs, and
HTTPS-to-HTTP transitions are not rejected by this repository layer. Local
`file=` sources are read from the selected preseed's sibling publication files.
Password and passphrase boot keys, including the named d-i Wi-Fi passphrase
aliases, are an explicit installation override. They are inherently visible to
the kernel command-line and d-i diagnostics, so protected initrd
`/preseed.env` remains the preferred unattended channel. Token, bearer-secret,
access-key, private-key, generic PSK and credential-file keys remain rejected
before parsing. No credential is accepted in a URL, and HTTP/HTTPS transport
does not bypass payload or manifest authentication.

The installer image is independent of the selected target suite. `INSTALLER_SUITE`,
the authenticated payload qualification, and the early target
`/etc/apt/apt.conf.d/00suite-default-release` file select Forky or Trixie; no
`/cdrom` media marker is consulted or compared.

## Runtime handling

Runtime state and caches are under a private installer directory. Downloads use
private temporary files, atomic replacement, bounded connection timeouts/retries
and one cache keyed by the full normalized source. Once the snapshot is ready,
missing assets cannot fall back to a different moving remote revision. The
snapshot and transport are reusable within the same installation.

The initial preseed is intentionally fetched once more by the bootstrap resolver
to learn its effective redirect destination. Repository asset payloads are then
fetched as one archive plus one manifest, not repeatedly file by file. Cache
reuse does not extend across boots or across unrelated repositories.

Source path traversal, ambiguous file/url selections, unsafe local paths and
symlink escapes are rejected. The snapshot is regular-file-only. Full initial
URL schemes and absolute local filenames are required by this repository;
installer shorthand such as a bare hostname is not its source contract.

## External vendor artifacts and repository authentication

Payload members and external vendor data remain separate APIs. A missing pinned
payload member cannot fall back to a moving URL. Codex binary archives retain
their configured SHA-256 and size bounds; the repository revision is pinned.
Mullvad retains verification against its pinned code-signing key fingerprint.

### Explicit CUDA-legacy authentication exception (R4)

The `optional/cuda-legacy` class is architecture-limited to amd64 and uses exactly
NVIDIA's Debian 12 x86_64 CUDA archive. Selecting this class explicitly authorizes:

```text
deb [arch=amd64 trusted=yes allow-insecure=yes allow-weak=yes allow-downgrade-to-insecure=yes check-valid-until=no check-date=no] https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/ /
```

The selected archive's published key is staged and named by `signed-by` before
the first target update. The explicit source-local exception still accepts
weak or unauthenticated metadata; a staged key does not restore that trust.
APT may emit verifier diagnostics, but
SHA-1, unrecognized signing keys, unsigned metadata and stale metadata are not
acceptance gates for this source. This is **not** a cryptographic fix for SHA-1:
it intentionally bypasses archive authentication and freshness protection for
this one selected archive. A compromised origin, mirror or intercepted trusted
TLS endpoint could therefore supply malicious or replayed packages.

The exception is confined to the source entry, staged before pkgsel and restored
when late package repair needs it. The installer never enables a global
AllowInsecureRepositories, AllowUnauthenticated or TLS bypass and never changes
the system crypto policy. HTTPS certificate verification remains enabled.
APT still checks package bytes against index checksums, but an unauthenticated
index cannot establish trustworthy package provenance. Missing indexes, network
failures and package checksum mismatches still fail the operation.

Both early and late staging use the same renderer and atomic publisher. General
metadata refresh temporarily hides the CUDA source and keeps its cached lists;
cleanup removes it after package repair and at finish-install. Old managed CUDA
keyrings are cleanup-only state, never prerequisites. Normal CUDA, Debian and
other third-party sources retain their own authentication policy.

Unexecuted fixture sources describe SHA-1 certificates/signatures, unsigned and
expired metadata, signed-to-unsigned transitions, strict unrelated sources and
corrupted package bytes. They are not passing acceptance results for this
revision. The source-local implementation is in the shared
`scripts/common/modules/context-target.sh`; fixture source is
`tests/test_cuda_legacy_apt.py` under `d-i/debian/`.

Each suite and role family owns its physical APT tree. Forky has priority 900;
Trixie base, security and updates all have priority 900, so newer security and
updates candidates are not suppressed by a higher base priority. Foreign Debian
archives are acquisition sources pinned to -1. Native backport/vendor exceptions
name explicit package identities; vendor `stable` and `any` channels retain
their published names. These policies are not a complete package lock. No live
package solver or maintainer-script acceptance has run for this source.

The retained unattended-upgrade blacklist excludes the kernel, boot, firmware,
libc, systemd, package manager, authentication, crypto, networking and many
security components. Automatic updates therefore do not provide comprehensive
patch coverage. The server operator owns regular review of held security
candidates, bounded maintenance windows, service-specific updates, backups and
reboots. Runner and Technitium binaries use pinned releases and manual updates;
their service users do not control privileged code or update policy.

The desktop role also enables signed Debian Trixie Backports for the
`hyprpolkitagent` 0.1.3 Qt package while Forky carries the incompatible 0.2.0
hyprtoolkit build. Its package-specific preference is staged before pkgsel and
rejects the agent from Sid, Experimental and the optional OBS archive. The
installed-package compatibility check still rejects an unexpected build.

## Terminal failures and privileged publication

`common/lifecycle.sh` is the single fatal-state implementation, embedded before
bootstrap network access. First-failure records are atomically linked once with
mode 0600 in a private runtime directory. Fatal supervisors never return to d-i:
they stop the actual main-menu ancestor and wait without customization or reboot.
An already-fatal or interrupted mandatory phase cannot automatically resume.
Signals stop the supervised child tree before the terminal hold; no host-wide
process kill or PID-1 action is used. Do not SIGCONT the menu after failure.

A failure before writable target storage exists can only be retained in initrd
RAM and on the console. After a mounted target exists, diagnostics are also
copied privately to `/var/log/installer`. Power loss can destroy RAM-only evidence;
serial-console capture is an external deployment responsibility. The terminal
hold does not automatically unmount filesystems or close encryption mappings;
it avoids unsafe cleanup against uncertain partial state. Stop all work, export
evidence, and recover from trusted rescue media before re-provisioning.

Codex components are privately staged and validated before atomic publication.
Existing state is compared without running Git or code from that existing tree.
Only defined runtime-owned files/directories and managed links are allowed to
differ. Ownership, modes, hardlinks, revision and immutable contents remain checked.
Rollback removes only paths created by that transaction, never unrelated data.
The release record is published last. An interrupted installer is still terminal;
component convergence is not authorization to restart destructive phases.

## Credentials and personalized browser data

`/preseed.env` is restricted assignment data. Neither it nor a host profile is
sourced as arbitrary shell code. The installer requires a regular non-symlink
file owned by the effective installation account (root in d-i), with one hard
link and safe parent directories. The credential input's mode is not part of
the installer interface and is never changed while it is read. Private key and
other private asset files use the separate mode-hardening path. The checks use
d-i-supported numeric ls rather than the absent stat applet. Prior exposure
cannot be undone by changing mode.

An initial BOM and CRLF endings are normalized in a private temporary copy;
source output and syntax diagnostics are suppressed to avoid secret disclosure.
Any syntactically valid `PRESEED_*` name may be present because one protected
input can serve several roles and releases. Each consumer requests only its
mapped name. Values are single-line literal assignment data and are never
evaluated; standalone executable statements and arbitrary non-`PRESEED_*`
exports are rejected.
Do not deploy credentials written by an untrusted party or enable xtrace.
Missing root credentials fail before early disk planning. Password/passphrase
parameters such as `root_password` and the named Wi-Fi passphrase aliases may
override the protected file during installation, including an explicit empty
value that fails closed. Token, bearer-secret, access-key, private-key, generic
PSK and credential-file parameters remain rejected. The implementation and
precedence checks are in `d-i/debian/scripts/common/credentials.sh` and its
unexecuted fixture sources.

When the selected profile uses `SECURE_BOOT_STATE_MODE=luks`, the installer
requires `shim_signed_passphrase` or `PRESEED_SHIM_SIGNED_PASSPHRASE` in its
installer credential input to format and open `/var/lib/shim-signed`. It does not
use the account name or fall back to another credential source. The passphrase is not installed in the target; `luks-mok-open` prompts
for it when opening the partition after installation. An existing LUKS partition
with a different key must be rekeyed deliberately before reusing that state.

Normalized bookmarks, contextual site grants and coverage reports are private
information even after tracking histories and the NoScript instance UUID are
removed. Restrict access to the personalized repository and installation server.
Exports are staged through directory/file-descriptor based checks and atomic,
non-clobbering publication; no browser database is rewritten offline.

DevTools is allowed by policy but is not started automatically. The helper refuses
root, keeps the browser sandbox, binds loopback and uses a separate private
profile. An open CDP endpoint has broad unauthenticated control over that profile;
do not expose it to the LAN, untrusted local users or untrusted tooling. AppArmor
exceptions cover only each browser's dedicated debug-state directory. Live kernel
enforcement has not been tested here.

Privacy Badger's no-DNT setting also disables GPC in the inspected upstream
implementation. Browser-native DNT defaults are false for fresh seeded profiles.
Do not infer anonymity or immunity to fingerprinting from these settings.

## What this refactor does not prove

The changes above are reviewed corrections, not a complete formal or runtime
security certification. Other target policy is inherited from the supplied tree;
preservation is not an endorsement that every original package, network rule,
third-party downloader, AppArmor profile or kernel tuning suits your deployment.
Review account/env files before publishing. Do not commit real enrollment keys,
passwords, private keys, tokens or production network secrets to a public repo.

Perl syntax checking can execute BEGIN blocks and is not run. The required
changed-file audit uses non-executing source parsers and shell syntax checks;
it never imports managed modules or calls live policy/service validators.
Fixtures remain unexecuted. No current claim of boot, disk preservation, GUI,
service startup, firewall enforcement, hardware behavior or external enrollment
follows from static inspection or serialization consistency.

Upstream references consulted (2026-09-06):
- Debian installer, Using preseeding:
  https://www.debian.org/releases/forky/amd64/apbs02.en.html
- Debian installer, Advanced options:
  https://www.debian.org/releases/forky/amd64/apbs05.en.html
- Debian preseed source-location contract:
  https://sources.debian.org/src/preseed/1.122/README.preseed_fetch/
- GNU Wget TLS verification options:
  https://www.gnu.org/software/wget/manual/html_node/HTTPS-_0028SSL_002fTLS_0029-Options.html

Additional primary implementation references (consulted 2026-09-06):
- APT source-local security options: https://manpages.debian.org/testing/apt/sources.list.5.en.html
- APT archive authentication: https://manpages.debian.org/testing/apt/apt-secure.8.en.html
- APT insecure acquisition implementation: https://raw.githubusercontent.com/Debian/apt/main/apt-pkg/acquire-item.cc
- systemd filesystem restrictions and AF_UNIX: https://manpages.debian.org/testing/systemd/systemd.exec.5.en.html
- Chrome debug-profile boundary: https://developer.chrome.com/blog/remote-debugging-port
- uBOL managed settings: https://github.com/uBlockOrigin/uBOL-home/wiki/Managed-settings
- Privacy Badger managed schema: https://raw.githubusercontent.com/EFForg/privacybadger/master/src/data/schema.json
- Privacy Badger import merge: https://raw.githubusercontent.com/EFForg/privacybadger/master/src/js/storage.js

## Scoped repair and release gates (2026-09-24)

See [the security repair](docs/security-hardening.md) for firewall ownership,
privileged import/extraction boundaries, measured-boot enrollment, journal
sealing, and the limits of same-UID lifecycle isolation. Historical reports
are in `docs/validation/history/`; they are not acceptance results for this revision.

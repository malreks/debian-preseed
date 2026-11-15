# Late-script contract audit, 2026-11-15

## Scope and execution boundary

This extends the [Tor target-shell correction](tor-target-shell-20261115.md)
after the user requested a review of the other late scripts. The baseline is
`e0d1019c820f78540df90bb61d0f5ccfca466dc7` with the Tor correction already in
the working tree. Earlier edits were preserved. No new installer logs were
available for this expanded review.

The user subsequently prohibited further VM runs. No VM was launched after
that instruction. The already-running archive fixture completed and its
supervisor reaped QEMU. Subsequent work used source inspection, syntax and
data checks, and the authorized pure payload serializer. No installer helper,
test discovery, service, package operation, firmware operation or storage
operation ran on the development host. The offline catalog was not regenerated.

## Inventory and inspected contracts

The late tree contains 78 regular files: 50 shell parents, 13 Python sources
or templates, one Perl generator, two AWK programs, and 12 assets/templates.
The inventory includes account provisioning; Btrfs/F2FS, GRUB and crypto;
networking, sharing, Stubby, Tailscale and CrowdSec; security, storage,
volatile storage, zram and IOCost; managed software; Llama and Whisper;
Codex/DevOps and SSH helpers; and theme/template publication.

Reviewed the shared dispatch and storage-family entrypoints, target executor,
clean target environment, explicit DevOps account environment, helper argv,
source selectors, logging/path renderer and direct helper acquisition. Fixed
source references were resolved as data in both suite contexts: each has 428
fixed caller references and 36 stage references, all 78 late files have file
selectors, and no missing file selector was found. This proves source lookup
closure for those references, not execution of their target commands.

The managed-software sibling review includes Bitwarden, QoreDB, Obsidian,
Tomat, Sleek, Postman, Discord, Tuta, Ledger, ChatGPT/Codex desktop integration,
Filen, Zoom and Tor Browser, plus the profile-controlled scx package path.
The common installer worker and publication boundaries were inspected across
these consumers. Private Zoom/Discord Xwayland eligibility and policy were
not changed.

## Corrected owners

- [Tor Browser module](../../d-i/debian/scripts/late/tor-browser.sh): the
  authentication child receives the rendered helper and private work-directory
  paths as explicit arguments 7 and 8. It no longer expands an unavailable
  installer variable inside the clean target shell. The
  [software dispatcher](../../d-i/debian/scripts/late/software.sh.tmpl) derives
  its working directory through the existing target path placeholder.
- [GRUB](../../d-i/debian/scripts/late/grub.sh): the Secure Boot repair child
  receives the installer spelling of the efivars bind mount as argument 4.
  Both mount-table probes use fixed-string matching. The child no longer
  expands absent `TARGET_ROOT` or `DIR_SYS` variables. Disk, ESP, loader and
  firmware preflight checks remain in place.
- [Shared bootstrap acquisition](../../d-i/debian/scripts/common/bootstrap.sh):
  direct late, desktop, firstboot and target-asset acquisitions use the existing
  scalar/path renderer for named runtime path and AppArmor profile tokens.
  The previous suffix restriction missed directly fetched Python helpers and
  target re-entry scripts. A private sibling staging directory now covers
  acquisition, logging rendering, path rendering and mode application before
  replacement of the destination. Failure preserves the earlier destination;
  cleanup is restricted to the directory owned by that acquisition and
  preserves the original error status. A cleanup-only failure returns 125.
  Early raw catalog fetching tolerates selectors that are not loaded yet,
  and diagnostic strings containing only a placeholder prefix do not trigger
  path rendering before common initialization. No second renderer was added.
- [Codex archive helper](../../d-i/debian/scripts/late/codex-archive.py): ignored
  metadata payloads now count against the existing configured byte budget.
  A 16,384-member bound includes ignored entries and directories; negative
  payload sizes are rejected. The installed binary/schema selection and CLI
  argument shape remain unchanged. The separate
  [Codex release shell](../../d-i/debian/scripts/late/devops/codex-release.sh)
  only gains a scoped ShellCheck annotation for an assignment inside its
  deferred EXIT trap; its runtime cleanup body is unchanged.
- [Changed-file checker](../../tools/post_change_check.py): literal child
  shells are decoded and checked independently of outer shell assignments
  and directives. This handles concatenated shell quoting and named shell
  heredocs, and checks uppercase unset variables. Explicit DevOps account
  environment assignments and dispatcher inline assignments establish the
  child environment; arbitrary installer variables are not assumed present.
  The related child-shell lookup covers 51 owners and 62 shell bodies,
  including all ten managed-software child shells.

The guarded [regression fixture source](../../d-i/debian/tests/test_installer_contracts_20261115.py)
contains Tor, bootstrap publication, GRUB preflight and archive-boundary
drivers. It was inspected and parsed as source after the VM prohibition;
unittest discovery and the test module were not executed on the host.

## Current static and generated-product evidence

The final source-only inventory used Python AST parsing without repository
imports. All 50 shell parents passed Dash `-n`, BusyBox `sh -n`, and ShellCheck
`--norc --shell=sh --severity=error --format=json -`; all 13 Python source
files passed AST parsing. Parser subprocesses had explicit argument arrays,
minimal environments and 12-second per-process deadlines, under a 90-second
outer deadline. Perl and AWK were inspected as data; no `perl -c`, BEGIN block,
or AWK program was executed on the host.

`timeout 120s make build` passed through the reviewed serialization-only
recipe. It generated the normal flat suite products, without test or native
helper execution. `timeout 120s python3 -B tools/post_change_check.py` passed
after the expanded child-shell guard was corrected for explicit unquoted
dispatcher assignments. Earlier static attempts reported prefix-only marker
false positives and an invalid ShellCheck directive spelling; these were
corrected before the passing result. An earlier exploratory source-check
attempt timed out and is not counted as passing evidence.

The passing changed-file audit includes 62 child shells, ten managed-software
child shells, 13 managed application owners, 230 late operation source lines,
2,248 current shared source comparisons, 208 frontend source comparisons,
8,604 payload file-selector comparisons, both compiled class registries,
and the existing temporary-unshare staging contract. These are static checks.

Data-only tar/manifest/receipt comparisons verify all six changed payload
source files byte-for-byte against their owning files for both suites. The
two payload archives are identical and each has 2,421 members.

| Product identity | Value |
| --- | --- |
| Release | `6820c8e6632ddc10323003af63fd54500a4928ad88e383120adbf0ff9aef24e3` |
| Source fingerprint | `9e66857b6ec8aaea6c9b5129ad3c5f9800bda0d93b45e2f0a7fafb1885c3ebe0` |
| Payload SHA-256 | `4b8db35f40f709fba06e8929c297a3db89bf08bcebb93c92dec9be03709a33ba` |
| Manifest SHA-256 | `02aa79bd3ec7ca4953094ac225331df93d6ad306bf540ec21786f0e63c20acf6` |
| Current bootstrap source SHA-256 | `3499a01631bf059719b253e77cd3b593c736eea4bc42590d1b962dfca09230a7` |
| Current GRUB source SHA-256 | `2d17166cd12963aaaf69e03a5893ac3433c80de011b10bc13d96a35a1d0bb483` |
| Current Codex archive source SHA-256 | `1b81b2152f8a5ee70536b9f8c0e1951f47843c6bce0749c8b16ae3e22da708e3` |

The first independent product-inspection command incorrectly treated the
line-oriented manifest as JSON, and its follow-up used an incorrect receipt
key. Both exited before writing an evidence report. The corrected data check
uses manifest format 3 and `source_inputs`; it passed. These inspection-command
errors were not installer failures or passing validation evidence.

## Earlier isolated evidence and limits

The earlier runs are retained under validation run identifier
`late-audit-20261115-337nq327`, including exact argv JSON, input identities,
fixture source fingerprints, serial output, result JSON and retained images.
This section records those already-started/completed runs; it does not
authorize further execution. The preceding Tor record documents its separate
16-case reproduction and failure-injection run.

The late-script guests used QEMU 11.1.2 (`Debian 1:11.1.2+ds-3`), q35 TCG,
one CPU, 512 MiB RAM, serial output, no network, no disks, no host mounts,
no host sockets and no passthrough. Each supervisor supplied only PATH,
LC_ALL and private HOME, imposed a 100-second hard deadline, and reaped QEMU.
The guest init program was a private fixture overlay; the Debian installer,
package manager and services were not started. Kernel, initrd and Dash input
identities are recorded in the preceding Tor record. Exact commands are in
the retained `command.json` files; no host execution fallback was used.

The combined bootstrap/GRUB run passed 68 cases in 72.007 seconds: eight real
source assets through both shells and both mocked transport branches, fetch
and render failure injection, unresolved placeholders, destination preservation,
mode/cleanup checks, and GRUB mount-spelling/preflight cases. GRUB firmware
tools and source transports were mocks. It exited 0 with guest shutdown and
cleanup markers. Its combined initrd SHA-256 is
`a377214f5ecea628a7defdb8404227d28d1b046d262810c31d30abf0506a9f31`.
Its bootstrap source was
`88f03c588ed99919743492622840dd2608778add03eb54c9e4347ada8a00c5c2`.
The subsequent pre-common selector/default and full-marker detection
refinements, and their two added fixture modes, have current static evidence
only; that earlier native run is not evidence for their later revision.

The already-running Codex archive fixture completed 16 cases in 38.390
seconds, exit 0, with guest cleanup/shutdown markers and QEMU reaped. It
used packaged Python 3.13.5 (`3.13.5-2+deb13u5`) inside the guest, with
`env -i`, `-P -B -S` and a fixed fixture-only hash seed. Valid extraction,
oversized ignored metadata, aggregate ignored metadata, excessive member
count, duplicate paths, traversal, links and invalid schema were exercised
against baseline and corrected source. The baseline accepted the three
previously unbounded cases; the corrected helper rejected them. Its combined
initrd SHA-256 is
`e7ba9aef754472d8e6f0f15b22b50e044358390a169f912d5394a1eeb2a870c7`.
Public Debian Python package archives were read as data, not installed or
executed on the host; their version, URL, size and published-checksum match
are retained in the fixture metadata. No additional OpenPGP verification of
those fixture downloads is claimed.

Unsuccessful earlier runs remain part of the record:

- The initial bootstrap fixture omitted three profile identifiers required by
  the runtime contract. It failed fixture setup and shut down cleanly after
  15.444 seconds; it is not passing product evidence.
- The larger bootstrap matrix hit its 100-second deadline after 59 completed
  cases. QEMU was killed and reaped, but guest cleanup/shutdown markers were
  absent. Guest validation and cleanup are outcome-unknown; its RAM-only image
  and logs were retained. No host cleanup or retry of an uncertain mutation
  was performed.
- The first Python archive fixture could not initialize its randomized hash
  seed before early guest entropy was available. It completed zero cases and
  shut down cleanly after 5.324 seconds. The subsequent fixture-only seed
  setting resolved setup; the earlier result remains a failed preparation.

Complete Forky/Trixie installation, real Tor/vendor downloads and signatures,
live APT resolution, real firmware updates, network enrollment, target services,
boot behavior, hardware and desktop application launch remain unverified.
Static source closure and successful focused fixtures do not establish those
runtime acceptance gates or an absolute guarantee that every script is correct.

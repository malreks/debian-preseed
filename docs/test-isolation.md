# Static inspection and controlled isolated validation

Root `AGENTS.md` permits disposable QEMU/VM, rootless-container and private-
chroot validation when native installer, deployment, service, network or
hardware evidence is required. The environment must be privately owned by the
run, bounded, created from an identified fixture or target image, and isolated
from host roots, host mounts, host sockets, host credentials, host services,
host namespaces and device passthrough. Native execution must never fall back
to the development host.

Tests and host-facing validation commands must run only inside that reviewed
isolated boundary. This includes unittest discovery, importing a test or
fixture, `make test`, `make check`, `make validate`, AppArmor or systemd target
validators, benchmarks and installer smoke probes. Source-level syntax,
rendering, placeholder and changed-file audit commands remain allowed when
they do not import repository modules, contact host state or execute managed
helpers. The validation record must include the image or fixture identity,
command, tool versions, timeout, result and cleanup state. Credentials must
remain out of image layers, arguments, environments, URLs and logs.

The offline AppArmor parser exception in root `AGENTS.md` permits
`apparmor_parser -Q -K` with an explicit private configuration, staged include
tree and package feature/ABI data, a bounded timeout and one compile job. It
must not load kernel policy, read local host policy/configuration or kernel
features, write caches, install packages or execute package scripts. Staging
policy support files as data is not a substitute for native validation. Record
parser/support versions and any relocated ABI path.

## Permitted work

Inspect source and supplied reports as data. Static AST parsing, source/diff,
CSS/JSON/XML/TOML/YAML parsing, deterministic rendering, placeholder checks
and archive/hash comparison must not import or execute repository modules,
source shell snippets or invoke installed management helpers. Fixture cases may
be authored and reviewed as source. Native fixture execution is permitted only
inside the reviewed isolated boundary.

The permitted generation and static-audit paths remain separate:

- `make build` only serializes each suite's `payload.tar.gz`, `payload.manifest`,
  `source.sh`, `receipt.json`, `support-matrix.json`, and `preseed.cfg` directly
  in each suite directory, overwriting the same regular files on each run.
  It must not create release or publication directories. Suite classes,
  fragments, common answers and family APT trees are authored inputs. It must
  not execute tests, validators, shell snippets, policy parsers or management
  helpers, or rewrite source inputs.
- `python3 -B tools/post_change_check.py` is the required changed-file static
  audit after edits and again after payload regeneration. It must not import
  repository modules, execute fixtures or contact host services.
- `make check-perl` and the first stage of isolated `make check` use the
  canonical codebase auditor's `--perl-only --prepare-suite forky
  --prepare-family desktop` mode. The maintained `prepare_syntax_fixture.py`
  helper verifies the shipped payload, uses the real map producers and shared
  renderer, and supplies the actual published Perl modules. The audit stages
  those bytes unchanged under their importable filenames. The shared renderer
  and all physical role-owned modules must be included. Missing compilers,
  unresolved dependencies, incomplete templates and compilation errors fail
  this gate; none counts as successful syntax coverage. Perl compilation stays
  inside the reviewed image because imports can execute compile-time code.
  Use the same auditor command with `--prepare-suite trixie` to select Trixie.
- `make audit` is an explicit strict source diagnostic (`--source-only`). It
  reports unresolved template inputs and missing dependencies as incomplete,
  with a nonzero result. Use the prepared Perl gate for rendered compilation;
  source diagnostics do not replace it. The aggregate validator records all
  twelve flat suite products and never expects a retired release directory.

Inspect the chosen recipe and its full execution path before generation.
`make build` must remain pure serialization. Any native test, installer replay,
deployment check or target-service check must be run separately inside the
reviewed isolated boundary with bounded cleanup and recorded evidence.

## Guards and evidence

Retain `tools/isolation.py`, `tools/test-init.py` and the Makefile guards. Their
presence does not authorize host execution, privileged containers, host mounts,
host sockets or host fallback. Do not weaken a guard or run its discovery/import
path on the host.

After checking private PID and user-namespace ownership, the guard reads the
bounded `/proc/self/net/dev` inventory and requires exactly one loopback
interface with the kernel's complete counter layout. This observes the current
process's network namespace without opening a socket. The opened descriptor must
belong to the private procfs; symlink final components and submounts beneath
`/proc` are rejected. This prevents a private file or redirected lookup from
spoofing the inventory. Unreadable, oversized or malformed data fails closed.
All capability, mount, image, PID 1 and workspace
checks remain mandatory; no network permission or host fallback is added.

Report exact static checks, isolated commands, changed paths and generated
artifact hashes. State the image or fixture identity, tool versions, timeout,
cleanup result and any native checks that remain deferred. Static inspection,
offline compilation and serialization consistency do not prove runtime
behavior, loaded policy, boot, networking, application launches, hardware
performance, thermal stability or deployment without the corresponding
isolated evidence.

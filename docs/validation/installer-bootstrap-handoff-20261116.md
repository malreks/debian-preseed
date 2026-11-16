# Fresh late-command bootstrap regression

The reported `installer_lifecycle_parent_safe: not found` and subsequent
`unsafe prepared target payload ancestry` messages have one dependency cause.
The supervised phase starts a fresh shell that sources only `bootstrap.sh`,
then calls `bootstrap_run_preseed_phase`. When the repository and d-i
environments are cached, acquisition does not load `source.sh` in that parent
shell. Prepared-source adoption used lifecycle ancestry and metadata functions
before their definitions were available. A missing command was consequently
reported as an unsafe directory.

`bootstrap_load_prepared_source` now loads the cached transport library after
finding a ready marker and before checking ancestry. The transport embeds the
canonical lifecycle implementation. Initial phases without a ready marker keep
their previous path, and an already loaded transport returns immediately.
No filesystem validation was removed and no additional rendering, download or
package transaction was introduced. The shared boundary covers direct phase
dispatch, common-library loading, support-library loading and repository joins.

The previous rendering validation preloaded `source.sh` before its adoption
case. That was useful evidence for prepared copying but missed this fresh-shell
dependency. It did not prove the actual supervised late-command handoff.
The new `PreparedBootstrapTests` case in the existing target-render test module
starts with `bootstrap.sh` alone; it is authored for the guarded native suite
and was not executed through that suite's separate isolation gate in this run.

The independent disposable QEMU fixture executes the real BusyBox shell,
bootstrap, transport and cached repository/d-i environments. It calls
`bootstrap_run_preseed_phase late` from a fresh shell for both Forky and Trixie
contexts. Its prepared phase runner is a sentinel, so this is bootstrap
integration evidence, not a complete installer run. Source acquisition is
replaced with a failure sentinel to catch accidental fetching. For each suite:

- Removing only the four-line dependency fix reproduces both reported errors.
- The corrected fresh shell adopts the payload and starts the late runner.
- Non-private staging mode, a wrong source identity and a symlinked staging
  directory are rejected with their specific causes.
- An absent ready marker still permits initial repository setup without
  loading the transport unnecessarily.

The VM had no disks, NICs, host mounts, host sockets or device passthrough.
QEMU 11.1.2 used TCG, 384 MiB RAM, two virtual CPUs, a 60-second hard timeout
with a five-second forced termination budget, and a 70-second parent timeout.
The command was `python3 -B` followed by the private run's `run_vm.py`.
Host scratch and captures were under the checkout's disk-backed
`.build/validation/` tree; all three temporary-directory environment variables
were explicitly set. The guest completed in 40.142 seconds with QEMU exit 0,
both suite pass markers and `VALIDATION_EXIT=0`. The process was reaped and
guest memory released. Image, serial capture, exact argv and source hashes are
retained in the private `bootstrap-handoff-20261116` validation record.

| Evidence | SHA-256 |
| --- | --- |
| Public base initrd | `57303d157cffce3fa402301667fbc9b2280aa7372082b081e777375ae49da5f2` |
| Public installer kernel | `2b2358b37674d2505350528875bb17afae2a36522a9e8a9417eaca65a7da0e08` |
| Regression initrd | `668773c81ea9ef87644ab3c850de395a89b7717caea8b39c69bd5f2a14e56708` |
| Guest serial capture | `66e6d47a6c39a901677bdd87e8a500c8fbb2f9f5954152d1507f1972b879353a` |
| Guest fixture | `e818230cb024011581d907b7896803d241f11c1c747541d679771f81b2bed01b` |
| Corrected bootstrap | `bc6edbace24af499ab3611f8d2e7c28d1935d4795a71e7390ec293bfd1cec275` |

Pure `make build` regenerated both suites with source identity
`2e96bf4d3c95b6a2ae162b49949bfbbb37a1b43c91f59813ee058785913350b0`
and source fingerprint
`6c36b9b85f6dd2ff2dbf6549de75e00054bddd2af79347d271e5d921e34c235b`.
Both suite payloads contain the exact corrected bootstrap bytes and have
SHA-256 `785ab5c5ea6da06ef194e9204ba087952239fa6a82e2ec136e77e293097ee235`.
Both manifests have SHA-256
`21f257b7b6ff21d79fe85339e1ce96f1f45c324900ba5f4863c6781032090c7e`.
The changed-file static audit passed after generation; it is repeated after
this record is added. Existing offline bundles and external serving locations
were not regenerated or deployed. A complete live installation, real software
downloads and subsequent target activation remain unverified by this fixture.

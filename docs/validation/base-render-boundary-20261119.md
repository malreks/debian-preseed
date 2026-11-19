# Base-stage renderer boundary repair

Recorded 2026-11-19. This report covers the source changes and source/data
inspection of the `hook-base-00rendertarget` preparation failure. It does not
record a native installer run. The reported frontend message identified only
the hook and its former `prepare_target_payload` operation; neither the
selected profile nor the preceding private error was supplied.

## Confirmed defect and correction

The base hook passed the Appearance registry classifier through
`installer_repo_file_value`. That function calls
`installer_repo_assert_asset_family`, which correctly refuses a desktop asset
when the selected role is server. The classifier identifies bytes within the
captured full source tree so that `render.pl` renders registry defaults while
preserving the registry's mapping-token grammar. It does not publish that
desktop asset into the target. Both role families remain in the captured
source tree.

`hooks/installer/base-stage.d/00rendertarget` now passes the canonical
repository root plus the fixed registry leaf directly:

```sh
--appearance-registry "$DIR_TARGET_SHARE_LABWC_APPEARANCE/fields.json.tmpl"
```

The value remains repository-relative, uses the existing `repo.env` owner,
and is checked by the renderer's relative-path argument validation. The
installed-asset family guard is unchanged. Shared Perl publication still
selects only common modules and the chosen role's modules.

This fixes a concrete server preparation failure. It is not sufficient
evidence that the same defect caused the user's particular run: their role
and the underlying error remain unknown.

## More precise failure context

The hook now records 21 distinct operation contexts, each tied to its actual
current source line. They separate phase/profile/account/layout acquisition,
workspace creation, captured payload copying, input records, placeholder
ownership, runtime paths, map producer loading, system-template values,
systemd resource values, deferred module values, logging, themes, shared Perl
values, interpreter availability, the Perl rendering process, receipt
verification, ownership import and ready publication.

The new contexts preserve the existing supervised base-installer boundary,
private failed-candidate retention, bounded child execution and final ready
marker order. They allow a subsequent failure to identify the producer or
publication stage instead of reporting only `prepare_target_payload`.
The separate shared lifecycle repair is documented in the consolidated repair
report; this change does not change lifecycle result semantics.

## Inspected shared contracts

The review traced the base hook through common bootstrap/source preparation,
repository family selection, the complete shared Perl renderer, profile and
runtime scalar ownership, path/log/theme maps, full-tree rendering, shared
Perl publication, receipt creation, later prepared-source adoption, typed
publication and ownership records. It also traced the late template/resource
producers and the Btrfs/F2FS frozen-layout producers consumed before the base
hook. The following source/data checks were completed without executing those
implementations:

| Contract | Checked extent | Finding |
| --- | --- | --- |
| Canonical placeholder producers | 313 distinct canonical tokens used by captured scripts, target assets and installer assets; 38 compiled suite/profile views | No missing or empty required canonical producer. |
| Scalar alias ownership | All 38 compiled profile key sets | No `KEY` / `INSTALLER_KEY` alias collision. |
| Early system-template dependencies | 193 required uppercase input names; all 38 compiled views | 189 are present in every view. The four dynamic inputs have explicit preceding producers. |
| Systemd resource data | Seven source-declared name groups, five booleans, coredump storage mode, integer/size/percentage limits and build memory ordering; all 38 views | No invalid or missing required value in the model. Server-only omission rules match the producer. |
| Shared Perl inventory | All 160 catalog rows | The only deferred noncanonical/nonlogging fields are `ACCOUNT_USERNAME` and `SOFTWARE_APT_REPO_LOCAL_DEB_MAXIMUM_BYTES`; the hook explicitly writes both to `perl.map`. |
| Hook annotations | All 21 operation contexts | Each recorded line equals its actual line; operation names are unique. |

The four dynamic system-template inputs are:

- `INSTALLER_GRUB_MOK_MANAGER_EFI_PATH` and
  `INSTALLER_GRUB_REMOVABLE_BOOT_EFI_PATH`, assigned by
  `late_command_set_grub_arch_policy` immediately before map generation.
- `ZRAM_BACKING_RAW_DEVICE` and `ZRAM_BACKING_DEVICE`, assigned and serialized
  into the frozen runtime layout by both `scripts/runtime/btrfs.sh` and
  `scripts/runtime/f2fs.sh`, then loaded before the hook prepares its maps.

The raw zram PARTUUID remains a device-derived runtime value. Its optional
cached value and `blkid` producer were reviewed as source; no device was
read. The GRUB/module fields intentionally deferred until hardware and final
boot selection remain deferred. No renderer production rewrite was needed.

The top-level `Fcntl`, `File::Temp` and `IO::Handle` imports were checked
against Debian's official
[Trixie perl-base file list](https://packages.debian.org/trixie/amd64/perl-base/filelist)
and
[Forky perl-base file list](https://packages.debian.org/forky/amd64/perl-base/filelist).
Those modules are provided by `perl-base`; a missing full Perl modules package
does not explain those imports at this phase.

## Guarded regression fixtures

`tests/test_base_render_boundary_20261119.py` adds four cases: both roles
receive the captured registry classifier argument; the server still rejects
actual desktop asset selection; desktop selection accepts its registry; and
the granular hook contexts carry exact source-line metadata.

`tests/test_target_render_20261116.py` adds one server preparation case using
the real renderer inside the guarded guest. It asserts that registry defaults
render, mapping tokens and Appearance editor tokens remain literal, the common
Perl namespace publishes, and the desktop Perl namespace does not publish.
Its fixture helper now permits an explicitly supplied catalog and role while
retaining the previous defaults. The file contains 61 test methods after this
addition; the new selector file contains four.

The review also corrected the fixture storage boundary. The approved guest's
image root is read-only, so `/var/lib` cannot hold a fixture. The renderer's
strict ancestor policy also rejects ordinary guest `/tmp` as a source root.
All 17 `TemporaryDirectory` call sites across these two files now use the
guest's private, root-owned `/workspace` mount. Cleanup remains bound to each
owned temporary directory. The isolation guard still executes before fixture
functionality; production path checks and host-access restrictions were not
relaxed.

## Evidence and remaining validation

Completed checks for these changes were Dash parsing of the hook, Python AST
parsing of both fixture files, exact annotation-line inspection, archive and
restricted environment parsing, token inventories and the resource-domain
data model. No repository test import or test discovery was performed. No
Perl compilation, managed helper execution, native renderer invocation,
installer execution, host device probe or host service/package operation was
performed. The five new regression cases are source-reviewed and unexecuted.

An approved disposable target image was not available. A successful base
preparation in a native Debian target, failure injection of each map/render
boundary, the full installer and later service/boot behavior remain unverified.
The current frontend report alone cannot establish the precise remaining
runtime failure, if any. A subsequent native failure should provide the new
specific operation and the preceding redacted error from the private log.

Changed production/fixture owners in this review, relative to `d-i/debian/`:

- `hooks/installer/base-stage.d/00rendertarget`
- `tests/test_base_render_boundary_20261119.py`
- `tests/test_target_render_20261116.py`

The adjacent JSON record binds these source files and the inspected compiled
profile bytes. Final payload refresh, combined changed-file checks and
downloadable archive verification are the integration owner's responsibility
and are reported separately.

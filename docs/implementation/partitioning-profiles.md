# Profile partitioning and generation

The registered profile selects the storage mode. A name ending in `-duo` or
`-trio` enables multiboot; both variants use the same preservation mechanism.
Each physical class includes `d-i pkgsel/include string os-prober` directly.
The optional dualboot class is removed. The retired `dualboot_efi` and
`dualboot_debian` kernel arguments are rejected with migration guidance.

Every environment under the host profile tree declares these policy values:

| Variable | Default | Meaning |
| --- | --- | --- |
| `PARTMAN_CEILING_ENABLE` | `false` | Limit new partition extents to an absolute disk coordinate. |
| `PARTMAN_CEILING_MB` | `400000` | Maximum coordinate in decimal MB, including existing partitions and gaps. |
| `PARTMAN_REUSE_ENABLE` | `false` | Reformat only the profile's existing partitions, retaining their exact geometry. |
| `PARTMAN_REUSE_START` | `2` | Number of the first non-EFI partition when reuse is enabled. |

Reuse takes precedence over both ceiling values. It also works with an
ordinary single-system profile. It requires an existing GPT and a usable FAT
EFI System Partition. The first ESP by starting byte is selected and preserved
without formatting. All non-EFI profile partitions must exist, and none can
be an ESP. The fixed role count comes from the filesystem layout, including
its optional home, pool and signing-state partitions. Btrfs uses eleven
non-EFI partitions. F2FS's role count follows the selected optional partitions.
No partition is deleted, moved or resized in reuse mode. Partitions outside
the selected set, on either side of it, remain outside formatting authority.

With reuse disabled, a Duo/Trio installation reads the complete GPT inventory,
reuses the first ESP, and appends its new partitions in the tail free space
after the highest existing partition end. Earlier holes are left alone.
GPT partition numbers are allocated from the lowest unused numbers; this
also handles a table whose numbering contains holes. Physical placement and
partition numbering are separate. An ordinary profile creates a fresh GPT
and retains the existing whole-disk fresh-install policy.

For new partitions, a ceiling of `400000` limits the final byte to
`400000000000`, even on a `500000` MB disk. At least the final `100000` MB
remains unallocated. Configured safety margins, GPT reservations and alignment
can leave additional free space below that boundary. Existing extents and
gaps count against a multiboot ceiling; the ceiling is never added to their
sizes. Insufficient space fails before the partition preparation stage.

The shared layout policy captures partition geometry and GPT identities.
The early hook rechecks them and the selected physical disk before preparing
Partman. An ordinary unencrypted fresh profile with both controls disabled
uses the established native `partman-auto/disk` and `partman-auto/method=regular`
answers. Its root recipe can grow to absorb the remaining space. Ordinary
encrypted fresh profiles retain selected-disk free-extent `autopartition`.

| Selected profile | Ceiling | Reuse | Partitioning behavior |
| --- | --- | --- | --- |
| Ordinary | `false` | `false` | Established fresh whole-disk installation. |
| Ordinary | `true` | `false` | Fresh installation below the absolute ceiling; trailing space remains unallocated. |
| Duo or Trio | `false` | `false` | Preserve existing partitions and the first ESP; append Debian after the last existing partition. |
| Duo or Trio | `true` | `false` | Preserve existing partitions and the first ESP; append Debian below the absolute ceiling. |
| Any profile | Either | `true` | Keep existing geometry; reformat only the profile's non-EFI partition set starting at `PARTMAN_REUSE_START`. |

Disabling both controls never turns a Duo or Trio profile into a fresh disk
installation. The profile suffix independently selects preservation. Missing
EFI, incomplete reuse sets and insufficient tail space fail before mutation.

Ceiling, append and reuse modes use the bounded menu adapter. It uses the
packaged `decode_recipe`/`setup_partition` interfaces and fixed-size
`NEW_PARTITION ... beginning` requests, without recipe expansion or the old
delete-everything-after-start handler. Its final partition does not absorb the
tail. Inherited native disk/method answers are cleared before selecting the
adapter, so Partman cannot bypass the preservation choice. Only this bounded
path installs the commit guard that requires a fully
configured layout. It consumes recipe entries without taking file descriptors
3–7, which Debian reserves for cdebconf and the Partman FIFO protocol.
The guard requires every original partition to remain present at the exact
recorded extent; iterating only the remaining partitions would miss a deletion.
Interrupted preparation/application retains its running marker and refuses an
automatic retry. Late providers require the frozen layout instead of
rediscovering it.

The four leading recipe fields are minimum size, priority, maximum size and
the partition-creation type understood by libparted. In F2FS root/home recipes,
the fourth field is `ext4` for that package interface. The explicit
`filesystem{ f2fs }` field selects the actual filesystem, and the installed
F2FS backend and finish hook use `mkfs.f2fs`. Changing that partition token to
`f2fs` does not add libparted support for it. EFI, boot, pool and signing-state
partitions retain their separately declared formats.

The menu and partition-directory interfaces follow Debian's
[Partman package contract](https://d-i.debian.org/doc/partman/ch03.html).
The implementation was compared with the upstream
[recipe helpers](https://salsa.debian.org/installer-team/partman-auto/-/blob/master/lib/recipes.sh)
and [partition creation helpers](https://salsa.debian.org/installer-team/partman-auto/-/blob/master/lib/auto-shared.sh).

`make profile` first asks whether to create or delete profiles. Creation uses
the editable filesystem/family/variant environments in the profile template
directory. Ordinary and multiboot templates are copied
from the requested P15s, HP14 and Flex source policies. The server F2FS Duo
and Trio templates derive from its ordinary HP14 policy. Host names contain
one to five lowercase ASCII letters or digits. A normal profile is always
created; the names `duo` and `trio` are reserved so a normal profile cannot
accidentally select multiboot through its name. Duo, Trio or both can be added
in the same transaction. Existing
names or destinations cause failure without overwriting them.

Deletion displays the registered profile IDs. Select one or more exact IDs or
their displayed numbers, separated by spaces or commas. A normal profile cannot
be removed while either its corresponding `-duo` or `-trio` profile remains. If
needed, the interactive command asks to include those variants and delete them
first; declining cancels the operation without writing. Duo and Trio can also
be deleted individually while retaining the normal profile. A final prompt
lists every affected file and requires typing `delete` before removal.
Templates, shared environments, roles and unrelated profiles are retained.

Both actions validate the complete candidate through the class compiler before
publishing environments, classes for both suites, the registry and source
selectors. The command holds the repository directory lock and checks source
identity, bytes, ownership and modes. It stores private, synchronized recovery
copies beneath the repository build-state selector before changing sources.
Caught failures with a known outcome restore completed edits. An uncertain
mutation, interrupted publication or unproven rollback retains the recovery
directory, reports its location and exits with status 75; inspect that material
before retrying. Completed publication or proven rollback removes only the
transaction's own recovery files. Concurrent serializers retain their existing
source-capture checks. A killed process can leave source edits and recovery
material requiring review; the next build must consume a complete source set.

For a non-writing example:

```sh
python3 -I -B tools/profile.py --filesystem btrfs --family both --multiboot both --name hp55 --preview
```

To preview deletion of one existing Trio profile:

```sh
python3 -I -B tools/profile.py --action delete --profile btrfs-de-flex-trio --preview
```

To preview deletion of the normal Flex profile and all its existing variants:

```sh
python3 -I -B tools/profile.py --action delete --profile btrfs-de-flex --with-variants --preview
```

Repeat `--profile ID` to select several profiles explicitly. In command-line
previews or with `--yes`, protected normal profiles require every remaining
variant to be explicitly selected, or `--with-variants`; `--yes` alone never
expands the selection. Without `--preview`, deletion requires the final prompt,
unless `--yes` explicitly confirms the displayed selection. Existing creation
invocations with filesystem/family/name flags continue to select creation.
Neither action regenerates served products automatically; run `make build`
after reviewing the source changes.

Review the copied hardware and disk policy before using a generated profile,
then run the pure `make build` serializer and the changed-file audit. Source
checks and profile previews do not prove device preservation, formatting,
boot, or a completed installation. These native contracts still require the
reviewed disposable-image matrix from the repository execution policy.
The independent Trixie desktop Labwc/Xwayland suite-policy gate remains in
effect; removing profile-suffix guards does not qualify that package set.

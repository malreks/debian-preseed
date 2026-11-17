#!/bin/sh
# Debian partman menu adapter. It changes only the selected in-memory GPT and
# exact recipe partition directories; the packaged commit stages own formatting.
set -eu
set -f
layout_action=${1:?menu action required}
shift
layout_die() {
  printf '[partition-layout] fatal: %s\n' "$*" >&2
  exit 1
}
trap 'layout_status=$?; if [ "$layout_status" -ne 0 ]; then printf "[partition-layout] action=%s status=%s\n" "$layout_action" "$layout_status" >&2; fi' 0
runtime=${INSTALLER_RUNTIME_DIR:?installer runtime directory required}
bootstrap=${INSTALLER_BOOTSTRAP_LIB:-${runtime}/bootstrap/bootstrap.sh}
[ -f "$bootstrap" ] && [ ! -L "$bootstrap" ] || layout_die 'authenticated bootstrap is missing'
# shellcheck disable=SC1090
. "$bootstrap"
bootstrap_source_common_lib
installer_load_context_if_present || layout_die 'frozen installation context is missing'
TMP_ENV_DIR=${DIR_INSTALLER_ENV:?installer environment directory required}
installer_load_data_env "$TMP_ENV_DIR/host.env"
RUNTIME_COMMON_LIB="$TMP_ENV_DIR/runtime-common.sh"
export RUNTIME_COMMON_LIB
# shellcheck disable=SC1090
. "$TMP_ENV_DIR/runtime.sh"
# shellcheck disable=SC1090
. "$TMP_ENV_DIR/runtime.env"
runtime_validate_partman_policy
case "$RUNTIME_PARTITION_MODE" in fresh|append|reuse) ;; *) exit 1 ;; esac
case "$layout_action" in choices|do_option|check) ;; *) exit 1 ;; esac

# Packaged partman libraries use optional globals and positional sentinels.
# Their shell interface predates nounset; all project inputs above are required.
set +u
# shellcheck disable=SC1091
. "${DIR_INSTALLER_LIB_PARTMAN}/lib/base.sh"
# shellcheck disable=SC1091
. "${DIR_INSTALLER_LIB_PARTMAN}/lib/recipes.sh"
# read_line assigns these through the packaged protocol function.
num= id= size= type= fs= path= name=

layout_assert_disk() {
  "$TMP_ENV_DIR/detect-disk.sh" --verify-identity "$DEV_INSTALL_DISK" \
    "${FILE_INSTALLER_SELECTED_DISK_IDENTITY:?disk identity required}" "$DEV_INSTALL_DISK" ||
    layout_die 'selected disk identity changed'
}

layout_id_is_safe() {
  case "$1" in ''|*[!0-9-]*|*-*-*|-*|*-) return 1 ;; esac
  case "$1" in *-*) ;; *) return 1 ;; esac
  layout_id_start=${1%-*}
  layout_id_end=${1#*-}
  [ "${#layout_id_start}" -le 18 ] && [ "${#layout_id_end}" -le 18 ] &&
    [ "$layout_id_start" -le "$layout_id_end" ]
}

layout_find_partition() {
  layout_wanted=$1
  layout_found=
  open_dialog PARTITIONS
  while { read_line num id size type fs path name; [ "$id" ]; }; do
    [ "$path" = "$layout_wanted" ] || continue
    layout_id_is_safe "$id" || { close_dialog; return 1; }
    [ -z "$layout_found" ] || { close_dialog; return 1; }
    layout_found=$id
  done
  close_dialog
  [ -n "$layout_found" ] || return 1
  printf '%s\n' "$layout_found"
}

layout_assert_configured_geometry() {
  # A preserved partition deleted from Partman's in-memory table would no
  # longer appear in PARTITIONS. Check every original entry as well as the
  # entries still present, so absence cannot evade the preservation guard.
  for layout_original in $RUNTIME_PARTITION_INVENTORY; do
    layout_original_slot=${layout_original%%|*}
    layout_original_rest=${layout_original#*|}
    layout_original_start=${layout_original_rest%%|*}
    layout_original_rest=${layout_original_rest#*|}
    layout_original_end=${layout_original_rest%%|*}
    layout_original_path=$(runtime_partition_path "$layout_original_slot") || exit 1
    layout_original_id=$(layout_find_partition "$layout_original_path") ||
      layout_die 'an original partition disappeared from partman; refusing commit'
    [ "$layout_original_id" = "$layout_original_start-$layout_original_end" ] ||
      layout_die 'an original partition changed geometry in partman; refusing commit'
  done
  layout_authorized_paths=' '
  for layout_check_role in EFI $(runtime_layout_roles); do
    layout_check_path=$(runtime_role_device "$layout_check_role") || exit 1
    layout_check_id=$(layout_find_partition "$layout_check_path") || layout_die 'configured partition disappeared'
    layout_authorized_paths="$layout_authorized_paths$layout_check_path "
    if [ "$RUNTIME_PARTITION_MODE" = reuse ]; then
      layout_check_slot=$(runtime_partition_slot_from_path "$layout_check_role" "$layout_check_path") || exit 1
      layout_expected_start=$(runtime_inventory_value "$layout_check_slot" 2) || exit 1
      layout_expected_end=$(runtime_inventory_value "$layout_check_slot" 3) || exit 1
      [ "$layout_check_id" = "$layout_expected_start-$layout_expected_end" ] || layout_die 'reuse partition geometry changed in partman'
    elif [ "$layout_check_role" != EFI ] || [ "$DUALBOOT_ENABLED" != true ]; then
      [ "${layout_check_id%-*}" -ge "$RUNTIME_EXISTING_END_BYTES" ] &&
        [ "$((${layout_check_id#*-} + 1))" -le "$RUNTIME_LAYOUT_CEILING_BYTES" ] ||
        layout_die 'configured partition crosses the preserved extent or ceiling'
    fi
    if [ "$layout_check_role" = EFI ] && [ "$DUALBOOT_ENABLED" = true ]; then
      [ ! -e "$layout_check_id/format" ] || layout_die 'preserved EFI partition was marked for formatting'
    fi
  done
  open_dialog PARTITIONS
  while { read_line num id size type fs path name; [ "$id" ]; }; do
    [ "$fs" != free ] || continue
    case "$layout_authorized_paths" in *" $path "*) continue ;; esac
    layout_id_is_safe "$id" || { close_dialog; layout_die 'invalid preserved partition extent'; }
    [ ! -e "$id/format" ] || { close_dialog; layout_die 'a foreign partition was marked for formatting'; }
    if [ -f "$id/method" ]; then
      case "$(cat "$id/method")" in ''|keep|efi) ;; *) close_dialog; layout_die 'a foreign partition has a destructive usage method' ;; esac
    fi
    layout_check_slot=$(runtime_partition_slot_from_path preserved "$path") || { close_dialog; exit 1; }
    layout_expected_start=$(runtime_inventory_value "$layout_check_slot" 2) || { close_dialog; exit 1; }
    layout_expected_end=$(runtime_inventory_value "$layout_check_slot" 3) || { close_dialog; exit 1; }
    [ "$id" = "$layout_expected_start-$layout_expected_end" ] || { close_dialog; layout_die 'a foreign partition was resized in partman'; }
  done
  close_dialog
}

layout_tail_free() {
  layout_free=
  layout_tail_start=${layout_cursor:-$RUNTIME_EXISTING_END_BYTES}
  layout_best_start=-1
  open_dialog PARTITIONS
  while { read_line num id size type fs path name; [ "$id" ]; }; do
    [ "$fs" = free ] && [ "$type" != unusable ] || continue
    case "$id" in *[!0-9-]*|*-*-*|-*|*-) close_dialog; return 1 ;; esac
    layout_start=${id%-*}
    if [ "$layout_start" -ge "$layout_tail_start" ] && [ "$layout_start" -gt "$layout_best_start" ]; then
      layout_free=$id
      layout_best_start=$layout_start
    fi
  done
  close_dialog
  [ -n "$layout_free" ] || return 1
  printf '%s\n' "$layout_free"
}

layout_device_dir=
for layout_candidate in "$DEVICES"/*; do
  [ -d "$layout_candidate" ] && [ ! -L "$layout_candidate" ] || continue
  [ -f "$layout_candidate/device" ] || continue
  [ "$(cat "$layout_candidate/device")" = "$DEV_INSTALL_DISK" ] || continue
  [ -z "$layout_device_dir" ] || layout_die 'ambiguous selected disk in partman'
  layout_device_dir=$layout_candidate
done
[ -n "$layout_device_dir" ] || layout_die 'selected disk is absent from partman'
if [ "$layout_action" = choices ]; then
  printf '%s//installer-layout\tApply the validated %s layout on %s\n' \
    "$layout_device_dir" "$RUNTIME_PARTITION_MODE" "$DEV_INSTALL_DISK"
  exit 0
fi
if [ "$layout_action" != check ]; then
  [ "$#" = 1 ] && [ "$1" = "$layout_device_dir//installer-layout" ] || layout_die 'menu selection differs from the selected disk'
fi
layout_assert_disk
layout_inventory=$(runtime_partition_inventory) || layout_die 'cannot re-read selected disk GPT'
RUNTIME_PARTITION_INVENTORY=$layout_inventory
layout_hash=$(printf '%s\n' "$layout_inventory" | source_state_key) || exit 1
[ "${layout_hash%% *}" = "$RUNTIME_PARTITION_INVENTORY_HASH" ] || layout_die 'selected disk geometry changed before partitioning'
if [ "$RUNTIME_PARTITION_MODE" != fresh ]; then
  layout_identity=$(runtime_partition_identity_hash) || exit 1
  [ "${layout_identity%% *}" = "$RUNTIME_PARTITION_IDENTITY_HASH" ] || layout_die 'preserved GPT identities changed'
fi

layout_state="$(installer_runtime_state_dir)/partition-application"
cd "$layout_device_dir" || exit 1
if [ "$layout_action" = check ]; then
  [ -f "$layout_state" ] && [ ! -L "$layout_state" ] && [ "$(cat "$layout_state")" = configured ] ||
    layout_die 'layout is incomplete; refusing partition commit'
  layout_assert_configured_geometry
  exit 0
fi
[ ! -e "$layout_state" ] && [ ! -L "$layout_state" ] || layout_die 'layout application already started; do not retry an uncertain operation'
(set -C; umask 077; printf '%s\n' running >"$layout_state") || exit 1
cd "$layout_device_dir" || exit 1
if ! runtime_partman_fixed_layout_required; then
  # Preserve the existing encrypted-fresh path: partman-auto interprets the
  # authenticated crypto recipe within this selected disk's free extent.
  [ "$RUNTIME_PARTITION_MODE" = fresh ] || layout_die 'native partitioning requires a fresh layout'
  layout_free=$(layout_tail_free) || layout_die 'selected disk has no fresh free extent'
  layout_assert_disk
  if "${DIR_INSTALLER_LIB_PARTMAN}/autopartition" "$layout_device_dir" "$layout_free"; then
    printf '%s\n' configured >"$layout_state"
    exit 0
  else
    layout_status=$?
    [ "$layout_status" != 255 ] || layout_status=99
    exit "$layout_status"
  fi
fi
db_get partman-auto/expert_recipe_file
recipe=$RET
case "$recipe" in "$(installer_runtime_cache_dir)"/*) ;; *) layout_die 'recipe is outside the private runtime cache' ;; esac
[ -f "$recipe" ] && [ ! -L "$recipe" ] || layout_die 'validated recipe is missing'
decode_recipe "$recipe" default
[ -n "$scheme" ] || layout_die 'empty partition recipe'
layout_scheme="$(installer_runtime_state_dir)/partition-scheme"
(set -C; umask 077; printf '%s\n' "$scheme" >"$layout_scheme") || exit 1

# Validate the complete reuse set before any format flag is published.
if [ "$RUNTIME_PARTITION_MODE" = reuse ]; then
  for layout_role in $(runtime_layout_roles); do
    layout_path=$(runtime_role_device "$layout_role") || exit 1
    layout_find_partition "$layout_path" >/dev/null || layout_die "missing reuse partition: $layout_path"
  done
fi
layout_roles=$(runtime_layout_roles)
[ "$DUALBOOT_ENABLED" = true ] || layout_roles="EFI $layout_roles"
# Debian partman reserves 3/4/5 for cdebconf and 6/7 for its FIFO protocol.
# Consume bounded recipe text in shell variables; never replace those FDs or
# redirect the protocol's standard input while calling packaged helpers.
layout_remaining=$scheme
layout_newline='
'
for layout_role in $layout_roles; do
  case "$layout_remaining" in
    *"$layout_newline"*)
      layout_stanza=${layout_remaining%%"$layout_newline"*}
      layout_remaining=${layout_remaining#*"$layout_newline"}
      ;;
    '') layout_die 'recipe has fewer entries than the selected layout' ;;
    *) layout_stanza=$layout_remaining; layout_remaining= ;;
  esac
  # Only authenticated, validated recipe tokens reach packaged setup_partition.
  set -- $layout_stanza
  [ "$#" -ge 4 ] || layout_die 'incomplete recipe entry'
  layout_mb=$1
  case "$layout_mb" in ''|*[!0-9]*|0*) layout_die 'invalid fixed recipe size' ;; esac
  [ "$3" = "$layout_mb" ] || layout_die 'recipe maximum must equal its fixed minimum'
  layout_path=$(runtime_role_device "$layout_role") || exit 1
  if [ "$RUNTIME_PARTITION_MODE" = reuse ]; then
    layout_id=$(layout_find_partition "$layout_path") || layout_die 'reuse partition disappeared'
  else
    layout_free=$(layout_tail_free) || layout_die 'no unique tail free space remains'
    # Match partman-auto's normalization of the recipe's partition type.
    # "free" means an unformatted/EFI recipe member, not a libparted FS type;
    # setup_partition still owns its actual method/filesystem metadata.
    case "$4" in
      free) layout_creation_fs=ext2 ;;
      btrfs|ext2|ext3|ext4|xfs) layout_creation_fs=$4 ;;
      *) layout_die 'unsupported recipe partition-creation type' ;;
    esac
    layout_assert_disk
    open_dialog NEW_PARTITION primary "$layout_creation_fs" "$layout_free" beginning "${layout_mb}000000"
    read_line num layout_id size type fs path name
    close_dialog
    [ -n "$layout_id" ] && [ "$path" = "$layout_path" ] || layout_die 'partman allocated an unexpected partition identity'
    layout_id_is_safe "$layout_id" || layout_die 'partman returned an unsafe partition extent'
    layout_end=${layout_id#*-}
    case "$layout_end" in ''|*[!0-9]*) layout_die 'partman returned an invalid extent' ;; esac
    [ "$((layout_end + 1))" -le "$RUNTIME_LAYOUT_CEILING_BYTES" ] || layout_die 'partman crossed the absolute disk ceiling; refusing commit'
    layout_cursor=$((layout_end + 1))
  fi
  shift 4
  setup_partition "$layout_id" "$@" '' || layout_die 'cannot configure the selected partition'
done
[ -z "$layout_remaining" ] || layout_die 'recipe has more entries than the selected layout'
if [ "$DUALBOOT_ENABLED" = true ]; then
  layout_id=$(layout_find_partition "$DEV_PART_EFI") || layout_die 'preserved ESP disappeared'
  mkdir -p "$layout_id"
  printf '%s\n' efi >"$layout_id/method"
  rm -f -- "$layout_id/format"
fi
update_all
layout_assert_configured_geometry
printf '%s\n' configured >"$layout_state"
exit 0

#!/bin/sh
# Shared late_command target asset and template helper utilities. This file is sourced, not executed.

module_value_to_lines() {
  value=${1:-}
  if [ -n "$value" ]; then
    printf '%s\n' "$value" | tr ' ' '\n'
  else
    printf '\n'
  fi
}

target_asset_canonical_path() {
  target_path=$1
  case "$target_path" in
    __INSTALLER_PATH_*__|__INSTALLER_PATH_*__/*)
      token_body=${target_path#\_\_}
      token_name=${token_body%%__*}
      token_suffix=${token_body#"$token_name"}
      token_suffix=${token_suffix#\_\_}
      case "$token_name" in
        INSTALLER_PATH_DIR_*|INSTALLER_PATH_FILE_*) ;;
        *) installer_fatal "unsupported target path token: __${token_name}__"; return 1 ;;
      esac
      token_value=$(installer_runtime_path_placeholder_value "PATH_${token_name#INSTALLER_PATH_}") || {
        installer_fatal "target path token has no unique canonical value: __${token_name}__"
        return 1
      }
      case "$token_value" in
        /*) ;;
        *) installer_fatal "canonical target path is not absolute: __${token_name}__"; return 1 ;;
      esac
      case "$token_value" in
        *//*|*/../*|*/..|*/./*|*/.)
          installer_fatal "canonical target path is not normalized: __${token_name}__"
          return 1
          ;;
      esac
      printf '%s%s\n' "$token_value" "$token_suffix"
      ;;
    *) printf '%s\n' "$target_path" ;;
  esac
}

target_asset_validate_root_context() {
  [ -n "${TARGET_ROOT:-}" ] && [ "${1:-}" = "$TARGET_ROOT" ] || {
    installer_fatal 'target root is unset, empty or differs from the selected contract'
    return 1
  }
  installer_target_context_path
}

target_asset_is_logical_path() {
  case "$1" in
    /|/bin|/bin/*|/boot|/boot/*|/dev|/dev/*|/etc|/etc/*|/home|/home/*|/lib|/lib/*|/lib64|/lib64/*|\
    /opt|/opt/*|/proc|/proc/*|/root|/root/*|/run|/run/*|/sbin|/sbin/*|/srv|/srv/*|/sys|/sys/*|\
    /tmp|/tmp/*|/usr|/usr/*|/var|/var/*|/pool|/pool/*|/data|/data/*)
      return 0
      ;;
    *) return 1 ;;
  esac
}

# Locate a directory entry without following its leaf. Parent creation,
# readlink, link replacement and unlink may use it; all parents still
# belong to the validated mounted target. File publication uses the stricter
# target_asset_host_path below.
target_asset_entry_host_path() (
  set -eu
  [ -z "${INSTALLER_ASSET_BATCH_WORK:-}" ] || installer_asset_batch_flush || exit $?
  target_root=$(target_asset_validate_root_context "${INSTALLER_TARGET_DIR:-${TARGET_ROOT:-}}") || exit 1
  requested_path=${1:-}
  case "$requested_path" in
    "$target_root"/*)
      target_path="${target_root}$(target_asset_canonical_path "${requested_path#"$target_root"}")"
      ;;
    *)
      target_path=$(target_asset_canonical_path "$requested_path") || exit "$?"
      target_asset_is_logical_path "$target_path" || {
        installer_fatal "target asset path is outside the target namespace: $requested_path"
        exit 1
      }
      target_path="${target_root}${target_path}"
      ;;
  esac
  case "$target_path" in
    /*) ;;
    *) installer_fatal "target asset path must be absolute: $target_path"; exit 1 ;;
  esac
  case "$target_path" in
    *//*|*/../*|*/..|*/./*|*/.)
      installer_fatal "target asset path is not normalized: $target_path"; exit 1 ;;
  esac
  case "$target_path" in
    /|"$target_root") installer_fatal 'target asset must name a file, not the target root'; exit 1 ;;
    */) installer_fatal "target asset path is not normalized: $target_path"; exit 1 ;;
  esac
  case "$target_path" in
    "$target_root"/*) ;;
    *) installer_fatal "target asset escapes target root: $target_path"; exit 1 ;;
  esac
  target_parent=${target_path%/*}
  [ "$target_parent" != "$target_path" ] || target_parent=/
  checked_parent=$target_parent
  while [ "$checked_parent" != "$target_root" ]; do
    [ ! -L "$checked_parent" ] || {
      installer_fatal 'target asset ancestry contains a symlink alias'; exit 1;
    }
    checked_parent=${checked_parent%/*}; [ -n "$checked_parent" ] || checked_parent=/
  done
  ancestor=$target_parent
  while [ ! -e "$ancestor" ]; do
    [ ! -L "$ancestor" ] || {
      installer_fatal 'target asset parent is an indirect symlink'; exit 1;
    }
    ancestor=${ancestor%/*}; [ -n "$ancestor" ] || ancestor=/
  done
  [ ! -L "$ancestor" ] || {
    installer_fatal 'target asset parent is a symlink'; exit 1;
  }
  target_root_real=$(readlink -f -- "$target_root") || exit 1
  ancestor_real=$(readlink -f -- "$ancestor") || exit 1
  case "$ancestor_real/" in
    "$target_root_real/"*) ;;
    *) installer_fatal 'target asset parent escapes the mounted target'; exit 1 ;;
  esac
  printf '%s\n' "$target_path"
)

target_asset_host_path() (
  set -eu
  target_path=$(target_asset_entry_host_path "${1:-}") || exit "$?"
  if [ -e "$target_path" ] || [ -L "$target_path" ]; then
    [ ! -L "$target_path" ] || {
      installer_fatal 'target asset destination must not be a symlink'; exit 1;
    }
    if [ -f "$target_path" ]; then
      [ "$(installer_metadata_value "$target_path" links)" = 1 ] || {
        installer_fatal 'target asset destination must not be hardlinked'; exit 1;
      }
    fi
  fi
  printf '%s\n' "$target_path"
)

# Temporary inputs staged BEFORE in-target must not live below __INSTALLER_PATH_DIR_RUN__: d-i's
# chroot-setup bind-mounts the installer's __INSTALLER_PATH_DIR_RUN__ over the target runtime. Return a target
# path, not a host path; the caller owns its lifetime and must install an EXIT
# trap immediately. mktemp avoids stale-name collisions and never reuses a path.
target_private_stage_dir() (
  set -eu
  stage_name=${1:-}
  case "$stage_name" in
    ''|*[!a-z0-9-]*) installer_fatal "invalid target staging name"; exit 1 ;;
  esac
  [ "${#stage_name}" -le 32 ] || { installer_fatal "target staging name is too long"; exit 1; }
  stage_parent=$(target_asset_host_path /tmp) || exit 1
  [ -d "$stage_parent" ] && [ ! -L "$stage_parent" ] || {
    installer_fatal "target /tmp must be an existing real directory for private staging"
    exit 1
  }
  stage_host=$(umask 077; mktemp -d "$stage_parent/installer-${stage_name}.XXXXXX") || {
    installer_fatal "cannot create private target staging directory"
    exit 1
  }
  printf '/tmp/%s\n' "${stage_host##*/}"
)

ensure_target_asset_parent() (
  target_path=$1
  target_root=$(target_asset_validate_root_context "${INSTALLER_TARGET_DIR:-${TARGET_ROOT:-}}") || exit 1
  # Creating the parent never opens or replaces the final directory entry.
  target_host_path=$(target_asset_entry_host_path "$target_path") || exit 1
  target_parent=$(dirname "$target_host_path")
  canonical_root=$(readlink -f "$target_root") || exit 1
  [ -d "$canonical_root" ] || exit 1
  # Check the closest existing ancestor BEFORE mkdir, so a pre-existing parent
  # symlink cannot redirect staging outside the installation root.
  ancestor=$target_parent
  while [ ! -e "$ancestor" ]; do
    [ ! -L "$ancestor" ] || exit 1
    ancestor=$(dirname "$ancestor")
  done
  canonical_ancestor=$(readlink -f "$ancestor") || exit 1
  case "$canonical_ancestor/" in
    "$canonical_root/"*) ;;
    *) installer_fatal "target asset parent escapes target root: $target_parent"; exit 1 ;;
  esac
  target_normalize_systemd_config_parent_modes "$target_path" "$target_root" || exit 1
  # BusyBox install applies umask to intermediate directories, even with -m.
  # Only newly created public parents use 022; keep existing private parents
  # and the caller's private temporary-file umask unchanged.
  [ -d "$target_parent" ] || (umask 022; install -d -m 0755 "$target_parent") || exit 1
)

target_asset_assert_no_unresolved_installer_placeholders() {
  asset_path=$1
  asset_label=${2:-$asset_path}

  installer_assert_no_unresolved_installer_placeholders "$asset_path" "$asset_label"
}

# Publish only fully fetched/rendered files. A private work directory on the
# destination filesystem makes rename atomic and contains all renderer scratch
# files; failure and signal traps never expose a half-rendered target file.
# Prepared plain/scalar/resource assets use the shared Perl publisher. The
# hardware-derived system-template adapter retains its typed map producers;
# reaching it is an explicit dependency barrier for any queued publications.
publish_target_asset() {
  if [ "$4" != stdin ] && [ -z "$1" ]; then
    installer_fatal 'target asset source is empty; repository resolution failed'
    return 1
  fi
  case "$4" in
    plain|template-input|appearance-registry|resources)
      installer_asset_publish "$4" "$1" "$2" "$3"
      ;;
    stdin)
      (set -eu
        installer_asset_batch_begin generated-file
        installer_asset_input=$(mktemp "$INSTALLER_ASSET_BATCH_WORK/input.XXXXXX")
        cat >"$installer_asset_input"
        installer_asset_batch_add stdin "$1" "$2" "$3" INPUT_FILE "${installer_asset_input##*/}"
        installer_asset_batch_finish)
      ;;
    *)
      installer_asset_batch_flush || return $?
      publish_target_typed_asset "$@"
      ;;
  esac
}

publish_target_typed_asset() (
  set -eu
  umask 077
  asset_source=$1
  asset_target=$2
  asset_mode=$3
  asset_kind=$4
  asset_map=${5:-}
  INSTALLER_PUBLICATION_KIND=$asset_kind
  INSTALLER_PUBLICATION_MEMBER=unknown
  INSTALLER_PUBLICATION_IDENTITY=unknown
  INSTALLER_PUBLICATION_TARGET=unknown
  INSTALLER_PUBLICATION_ACQUISITION=selected-source
  INSTALLER_PUBLICATION_MAP_OWNER=${asset_map:-shared-path-and-typed-renderer}
  case "$asset_source" in *[!A-Za-z0-9_./@+\ -]*|'') ;; *) INSTALLER_PUBLICATION_MEMBER=$asset_source ;; esac
  case "$asset_target" in *[!A-Za-z0-9_./@+\ -]*|'') ;; *) INSTALLER_PUBLICATION_TARGET=$asset_target ;; esac
  [ -z "${BOOTSTRAP_PREPARED_SOURCE_ROOT:-}" ] || INSTALLER_PUBLICATION_ACQUISITION=prepared
  INSTALLER_PUBLICATION_IDENTITY=${BOOTSTRAP_PREPARED_ARCHIVE_SHA256:-unknown}
  export INSTALLER_PUBLICATION_KIND INSTALLER_PUBLICATION_MEMBER \
    INSTALLER_PUBLICATION_IDENTITY INSTALLER_PUBLICATION_TARGET INSTALLER_PUBLICATION_ACQUISITION \
    INSTALLER_PUBLICATION_MAP_OWNER
  asset_work=
  target_publish_step=validate
  target_publish_status=0
  trap 'target_publish_status=$?; trap - 0; if [ -n "$asset_work" ]; then rm -rf -- "$asset_work" || :; fi; if [ "$target_publish_status" -ne 0 ]; then installer_fatal_status "$target_publish_status" "target asset publication failed: step=${target_publish_step} kind=${asset_kind} suite=${INSTALLER_SUITE:-unknown} profile=${INSTALLER_HOST_PROFILE:-unknown} phase=${INSTALLER_PHASE:-unknown} source=${asset_source} target=${asset_target}"; fi' 0
  # A failed command substitution can leave an empty source argument while
  # the enclosing command still runs. Reject it before preparing or fetching
  # any target path; stdin publication has its own explicit source contract.
  installer_operation_context_repo scripts/late/target-assets.sh 233 validate_target_asset
  if [ "$asset_kind" != stdin ] && [ -z "$asset_source" ]; then
    installer_fatal 'target asset source is empty; repository selector resolution failed'
    exit 1
  fi
  case "$asset_mode" in [0-7][0-7][0-7]|[0-7][0-7][0-7][0-7]) ;;
    *) installer_fatal "invalid target asset mode"; exit 1 ;; esac
  if [ "$asset_kind" = helper-doc ]; then
    # Runtime storage normalization gives this tree to the primary account.
    # Keep this existing, ancestry-checked atomic handoff for that exact owner;
    # the root-only batch writer must not accept arbitrary user-owned trees.
    [ -n "${BOOTSTRAP_PREPARED_SOURCE_ROOT:-}" ] &&
      [ -n "${DIR_TARGET_DOCS:-}" ] && [ -n "${DIR_DATA_DOCS:-}" ] &&
      [ "$asset_mode" = 0644 ] || installer_fatal 'helper docs require prepared source and declared roots'
    case "$asset_source" in "$DIR_TARGET_DOCS/"*) ;; *) installer_fatal 'helper doc source escapes its owner' ;; esac
    case "$asset_target" in "$DIR_DATA_DOCS/"*) ;; *) installer_fatal 'helper doc target escapes its owner' ;; esac
  fi
  installer_target_context_init || exit 1
  target_publish_step=prepare_destination
  installer_operation_context_repo scripts/late/target-assets.sh 246 prepare_target_asset_destination
  asset_destination=$(target_asset_host_path "$asset_target") || exit "$?"
  ensure_target_asset_parent "$asset_target" || exit "$?"
  [ ! -d "$asset_destination" ] || { installer_fatal "asset destination is a directory"; exit 1; }
  asset_work=$(mktemp -d "$(dirname "$asset_destination")/.installer-asset.XXXXXX") || exit "$?"
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  target_publish_step=acquire
  installer_operation_context_repo scripts/late/target-assets.sh 255 acquire_target_asset
  (fetch_hook "$asset_source" "$asset_work/payload") || exit "$?"
  target_publish_step=render
  installer_operation_context_repo scripts/late/target-assets.sh 262 render_target_asset
  case "$asset_kind" in
    helper-doc)
      # These protected source bytes already passed base-stage path rendering.
      # The dedicated handoff only validates and publishes them atomically.
      target_asset_assert_no_unresolved_installer_placeholders "$asset_work/payload" "helper doc $asset_source"
      ;;
    template)
      (TMP_ENV_DIR=$asset_work; render_target_template "$asset_work/payload" "$asset_work/rendered" "$asset_mode") || exit "$?"
      mv -f "$asset_work/rendered" "$asset_work/payload" || exit "$?"
      ;;
    pre-clean)
      # Reuse the existing tmpfs scalar/block renderer without requiring
      # unrelated GRUB/zram template inputs on a headless target.
      (apply_tmpfs_pre_clean_placeholders "$asset_work/payload") || exit "$?"
      (target_asset_assert_no_unresolved_installer_placeholders "$asset_work/payload" "tmpfs pre-clean asset $asset_source") || exit "$?"
      ;;
    map)
      (TMP_ENV_DIR=$asset_work; apply_placeholder_map_to_target "$asset_work/payload" "$asset_map") || exit "$?"
      (target_asset_assert_no_unresolved_installer_placeholders "$asset_work/payload" "rendered target asset $asset_source") || exit "$?"
      ;;
    *) installer_fatal "invalid target asset operation"; exit 1 ;;
  esac
  target_publish_step=publish
  installer_operation_context_repo scripts/late/target-assets.sh 309 publish_target_asset
  chmod "$asset_mode" "$asset_work/payload" || exit "$?"
  installer_capture_primary_default "$asset_work/payload" "$asset_target" "$asset_mode" || exit "$?"
  [ "$(target_asset_host_path "$asset_target")" = "$asset_destination" ] || exit 1
  installer_target_ownership_record "$asset_source" "${asset_destination#"${INSTALLER_TARGET_DIR:-$TARGET_ROOT}"}" \
    "$asset_kind" "$asset_mode" || exit "$?"
  mv -fT -- "$asset_work/payload" "$asset_destination" || exit "$?"
)

stage_target_asset() {
  publish_target_asset "$1" "$2" "$3" plain
}

# A typed renderer may need its input grammar inside the target. This entry
# point accepts only a private directory returned by target_private_stage_dir;
# the consumer must reject unresolved fields before publishing final files.
stage_target_template_input() (
  set -eu
  template_source=$1; template_stage=$2; template_leaf=$3
  case "$template_stage" in
    "${DIR_TMP}/installer-"*) template_stage_name=${template_stage#"${DIR_TMP}/"} ;;
    *) installer_fatal 'template input requires a private target staging directory'; exit 1 ;;
  esac
  case "$template_stage_name" in
    *[!A-Za-z0-9.-]*|'') installer_fatal 'invalid template input staging directory'; exit 1 ;;
  esac
  case "/$template_leaf/" in
    *'/../'*|*'/./'*|*'//'*|*[!A-Za-z0-9_./@+-]*)
      installer_fatal 'invalid template input relative path'; exit 1 ;;
  esac
  template_stage_host=$(target_asset_host_path "$template_stage") || exit "$?"
  [ -d "$template_stage_host" ] && [ ! -L "$template_stage_host" ] &&
    [ "$(installer_metadata_value "$template_stage_host" uid_gid_mode)" = '0:0:700' ] || {
      installer_fatal 'template input staging directory must be private and root-owned'
      exit 1
    }
  publish_target_asset "$template_source" "$template_stage/$template_leaf" 0600 template-input
)

# Generated late-command files use the same publication contract as assets.
write_target_file() {
  publish_target_asset - "$1" "$2" stdin
}

remove_target_asset() (
  # rm unlinks the named entry, including a dangling enablement link; it must
  # never resolve the link into a destination for file publication.
  target_host_path=$(target_asset_entry_host_path "$1") || exit 1
  rm -f -- "$target_host_path" || exit "$?"
  installer_target_ownership_forget "${target_host_path#"${INSTALLER_TARGET_DIR:-$TARGET_ROOT}"}"
)

# EXIT trap for temporary target programs published through this boundary.
# Retain the command's status and its ownership evidence if removal fails.
cleanup_target_assets() {
  cleanup_status=$1
  shift
  trap - 0 HUP INT TERM
  for cleanup_asset do
    if remove_target_asset "$cleanup_asset"; then
      :
    else
      installer_error "temporary target asset cleanup failed: $cleanup_asset"
      [ "$cleanup_status" -ne 0 ] || cleanup_status=1
    fi
  done
  exit "$cleanup_status"
}

# Opt-in renderer: only explicitly selected resource-policy assets use it.
render_target_resource_asset() {
  publish_target_asset "$1" "$2" "$3" resources
}

render_target_pre_clean_asset() {
  publish_target_asset "$1" "$2" "$3" pre-clean
}

render_target_asset() {
  publish_target_asset "$1" "$2" "$3" template
}

render_target_asset_with_placeholder_map() {
  publish_target_asset "$1" "$2" "$3" map "$4"
}

render_target_asset_if_path() {
  repo_path=$1
  target_path=$2
  fallback_path=$3
  mode=$4

  if [ -n "$target_path" ]; then
    render_target_asset "$repo_path" "$target_path" "$mode"
  else
    remove_target_asset "$fallback_path"
  fi
}

stage_target_asset_if_path() {
  repo_path=$1
  target_path=$2
  fallback_path=$3
  mode=$4

  if [ -n "$target_path" ]; then
    stage_target_asset "$repo_path" "$target_path" "$mode"
  else
    remove_target_asset "$fallback_path"
  fi
}

# Chassis policy is explicit and fail-closed. Do not accept arbitrary filenames,
# use CPU vendor as a chassis proxy, or delete administrator-owned 79-* files.
stage_target_hardware_spec() (
  set -eu
  hardware_spec=${SYSTEM_HARDWARE_SPEC:-}
  case "$hardware_spec" in
    ''|79-thinkpad-acpi.conf|79-ideapad-acpi.conf|79-chromebook.conf) ;;
    *) installer_fatal "unsupported SYSTEM_HARDWARE_SPEC: $hardware_spec"; exit 1 ;;
  esac
  # Validate the parent before both publication and stale-policy removal.
  ensure_target_asset_parent __INSTALLER_PATH_DIR_ETC__/modprobe.d/.installer-parent || exit 1
  hardware_parent=$(target_asset_host_path __INSTALLER_PATH_DIR_ETC__/modprobe.d) || exit 1
  [ ! -L "$hardware_parent" ] || {
    installer_fatal "hardware policy directory must not be a symlink"; exit 1;
  }
  # Fetch successfully before removing the old policy. A failed installation
  # must not silently leave a newly selected machine without its requested file.
  if [ -n "$hardware_spec" ]; then
    stage_target_asset "$(installer_repo_asset_path DIR_TARGET_MODPROBE_D "$hardware_spec")" \
      "__INSTALLER_PATH_DIR_ETC__/modprobe.d/$hardware_spec" 0644 || exit 1
  fi
  for managed_spec in 79-thinkpad-acpi.conf 79-ideapad-acpi.conf 79-chromebook.conf; do
    [ "$managed_spec" = "$hardware_spec" ] || remove_target_asset "__INSTALLER_PATH_DIR_ETC__/modprobe.d/$managed_spec" || exit 1
  done
)

stage_target_docs_index() {
  [ -n "${DIR_DATA_DOCS:-}" ] || {
    installer_fatal "DIR_DATA_DOCS must be set before staging helper docs"
    return 1
  }
  publish_target_asset "$(installer_repo_file_value hooks/target/data/docs/README.md)" "${DIR_DATA_DOCS}/README.md" 0644 helper-doc || return $?
  target_chown_helper_doc_path "${DIR_DATA_DOCS}/README.md"
}

target_helper_doc_owner_ids() {
  helper_doc_owner_ids=${TARGET_HELPER_DOC_OWNER_IDS:-}
  if [ -z "$helper_doc_owner_ids" ]; then
    : "${ACCOUNT_USERNAME:?ACCOUNT_USERNAME must be set before staging helper docs}"
    helper_doc_passwd=$(target_asset_host_path __INSTALLER_PATH_DIR_ETC__/passwd) || return $?
    helper_doc_owner_ids=$(awk -F: -v wanted_user="$ACCOUNT_USERNAME" '$1 == wanted_user { print $3 ":" $4; exit }' "$helper_doc_passwd") || return $?
  fi
  case "$helper_doc_owner_ids" in
    ''|:*|*:|*[!0-9:]*|*:*:*)
      installer_fatal "target helper doc owner must be a numeric UID:GID pair"
      return 1 ;;
    *:*) ;;
    *) installer_fatal "target helper doc owner must be a numeric UID:GID pair"; return 1 ;;
  esac
  TARGET_HELPER_DOC_OWNER_IDS=$helper_doc_owner_ids
  printf '%s\n' "$TARGET_HELPER_DOC_OWNER_IDS"
}

target_chown_helper_doc_path() {
  doc_target_path=$1
  # Call directly so the owner cache survives subsequent documents in this shell.
  target_helper_doc_owner_ids >__INSTALLER_PATH_DIR_DEV__/null || return $?
  doc_host_path=$(target_asset_host_path "$doc_target_path") || return $?

  chown "$TARGET_HELPER_DOC_OWNER_IDS" "$doc_host_path"
}

stage_target_helper_doc_file() {
  repo_relpath=$1
  doc_name=$2

  doc_target_path="${DIR_DATA_DOCS}/${doc_name}"
  publish_target_asset "$(installer_repo_asset_path DIR_TARGET_DOCS "${repo_relpath}")" "${doc_target_path}" 0644 helper-doc || return $?
  target_chown_helper_doc_path "$doc_target_path"
}

stage_target_helper_doc() {
  stage_target_docs_index || return $?
  stage_target_helper_doc_file "$1" "$2"
}

stage_target_helper_docs() {
  [ "$#" -gt 0 ] || return 0
  stage_target_docs_index || return $?

  while [ "$#" -gt 0 ]; do
    stage_target_helper_doc_file "$1" "$1" || return $?
    shift
  done
}

remove_target_asset_and_empty_parent() (
  target_path=$1
  target_host_path=$(target_asset_entry_host_path "$target_path") || exit 1
  target_parent=$(dirname "$target_host_path")

  rm -f -- "$target_host_path" || exit "$?"
  installer_target_ownership_forget "${target_host_path#"${TARGET_ROOT}"}" || exit "$?"
  rmdir "$target_parent" 2>__INSTALLER_PATH_DIR_DEV__/null || true
)

sysctl_profile_placeholder_map() {
  profiles="BALANCED HARDENED PERFORMANCE"
  keys="SWAPPINESS PAGE_CLUSTER VFS_CACHE_PRESSURE WATERMARK_BOOST_FACTOR WATERMARK_SCALE_FACTOR COMPACTION_PROACTIVENESS EXTFRAG_THRESHOLD DIRTY_BACKGROUND_BYTES DIRTY_BYTES DIRTY_EXPIRE_CENTISECS DIRTY_WRITEBACK_CENTISECS DIRTYTIME_EXPIRE_SECONDS STAT_INTERVAL ZONE_RECLAIM_MODE AIO_MAX_NR INOTIFY_MAX_USER_INSTANCES INOTIFY_MAX_USER_WATCHES INOTIFY_MAX_QUEUED_EVENTS SOMAXCONN NETDEV_MAX_BACKLOG TCP_MAX_SYN_BACKLOG TCP_FASTOPEN TCP_KEEPALIVE_TIME TCP_FIN_TIMEOUT"

  for profile in $profiles; do
    for key in $keys; do
      var="SYSCTL_PROFILE_${profile}_${key}"
      eval "value=\${$var-}"
      [ -n "$value" ] || installer_fatal "${var} must be set"
      case "$value" in
        *[!0123456789]*)
          installer_fatal "${var} must be a non-negative integer"
          ;;
      esac
      printf '%s=%s\n' "$var" "$value"
    done
  done
}

apply_placeholder_map_to_target() (
  set -eu
  target_path=$1; map_func=$2
  map_tmp=$(mktemp "${TMP_ENV_DIR}/target-map.XXXXXX") || exit 1
  trap 'rm -f -- "$map_tmp"' 0
  "$map_func" >"$map_tmp" || exit "$?"
  installer_target_perl_render "$target_path" "$target_path" "$map_tmp"
)

replace_placeholder_line_block() {
  case "${4:-optional}" in
    required) line_kind=line ;;
    optional) line_kind=line-optional ;;
    *) installer_fatal 'invalid line-block requirement'; return 1 ;;
  esac
  installer_replace_placeholder_in_file "$1" "$2" "$3" "$line_kind"
}

apply_sysctl_profile_placeholders() {
  target_path=$1
  apply_placeholder_map_to_target "$target_path" sysctl_profile_placeholder_map
}

# Layout code supplies validated records; native file structure lives in target/.
write_target_fstab_records() (
  set -eu
  fstab_work=$(mktemp -d ${TARGET_ROOT}${DIR_ETC}/.fstab.XXXXXX) || exit 1
  trap 'rm -rf -- "$fstab_work"' 0
  trap 'exit 1' HUP INT TERM
  cat >"$fstab_work/records" || exit 1
  [ -s "$fstab_work/records" ] || { installer_fatal "empty filesystem table"; exit 1; }
  fetch_hook "$(installer_repo_file_value hooks/target/etc/fstab.tmpl)" "$fstab_work/template" || exit 1
  installer_target_perl_render "$fstab_work/template" "$fstab_work/rendered" \
    "$fstab_work/records" fstab || exit "$?"
  installer_assert_no_unresolved_installer_placeholders "$fstab_work/rendered" fstab || exit 1
  [ ! -L ${TARGET_ROOT}${DIR_ETC}/fstab ] || { installer_fatal "refusing a symlinked fstab"; exit 1; }
  chmod 0644 "$fstab_work/rendered" || exit 1
  installer_target_ownership_record "$(installer_repo_file_value hooks/target/etc/fstab.tmpl)" \
    "${DIR_ETC}/fstab" template 0644 || exit 1
  mv -fT -- "$fstab_work/rendered" ${TARGET_ROOT}${DIR_ETC}/fstab || exit 1
)

# Both storage-family hooks publish this foundation before dispatch runs any
# selected class helper. Private model policies may depend on these ancestors;
# desktop setup is later and must not be their prerequisite. Do not apply it
# before the final __INSTALLER_PATH_DIR_VAR__/log mount setup. Class helpers and rsyslog preflight
# existing paths immediately before their own tmpfiles invocation.
stage_target_logging_foundation() {
  installer_asset_batch_begin logging-foundation || return $?
  # Journald starts with forwarding off in every storage profile. Publish the
  # complete readiness owner before any selected class can enable rsyslog.
  # Debian's unnumbered vendor syslog.conf sorts after both numbered policies.
  # Replace that basename locally without assigning a competing runtime value.
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/systemd/common/journald.conf.d/syslog.conf)" \
    __INSTALLER_PATH_DIR_ETC__/systemd/journald.conf.d/syslog.conf 0644 || return $?
  stage_target_asset "$(installer_repo_file_value hooks/target/usr/local/libexec/common/journal-check)" \
    "${DIR_USR_LOCAL_LIBEXEC}/journal-check" 0755 || return $?
  stage_target_asset "$(installer_repo_file_value hooks/target/usr/local/libexec/common/journal-forwarding)" \
    "${DIR_USR_LOCAL_LIBEXEC}/journal-forwarding" 0755 || return $?
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/systemd/common/system/rsyslog-journal-forwarding.service)" \
    __INSTALLER_PATH_DIR_ETC__/systemd/system/rsyslog-journal-forwarding.service 0644 || return $?
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/systemd/common/system/rsyslog.service.d/40-journal-forwarding.conf)" \
    __INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_RSYSLOG_DROPIN__/40-journal-forwarding.conf 0644 || return $?
  # These metadata/content checks are installer-side readers. They must see
  # the just-queued candidates before any later target_exec barrier is reached.
  installer_asset_batch_flush || return $?
  for forwarding_asset in \
    etc/systemd/journald.conf.d/syslog.conf \
    usr/local/libexec/journal-check \
    usr/local/libexec/journal-forwarding \
    etc/systemd/system/rsyslog-journal-forwarding.service \
    etc/systemd/system/rsyslog.service.d/40-journal-forwarding.conf
  do
    forwarding_path=$(target_asset_host_path "/$forwarding_asset") || return $?
    case "$forwarding_asset" in usr/local/libexec/*) forwarding_mode=755 ;; *) forwarding_mode=644 ;; esac
    [ -f "$forwarding_path" ] && [ ! -L "$forwarding_path" ] &&
      [ "$(installer_metadata_value "$forwarding_path" uid_gid_mode_links)" = "0:0:$forwarding_mode:1" ] || {
      installer_fatal "unsafe staged journal forwarding asset: $forwarding_asset"; return 1;
    }
    target_asset_assert_no_unresolved_installer_placeholders "$forwarding_path" "$forwarding_asset" || return $?
  done
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/tmpfiles.d/common/59-log-layout.conf.tmpl)" \
    __INSTALLER_PATH_DIR_ETC__/tmpfiles.d/59-log-layout.conf 0644 || return $?
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/tmpfiles.d/common/65-audit-syslog.conf)" \
    __INSTALLER_PATH_DIR_ETC__/tmpfiles.d/65-audit-syslog.conf 0644 || return $?
  stage_target_asset "$(installer_repo_file_value hooks/target/usr/local/libexec/common/log-layout.tmpl)" \
    "${DIR_USR_LOCAL_LIBEXEC}/log-layout" 0755 || return $?
  # Selected helpers validate their rsyslog drop-ins before desktop setup.
  # Publish the module/template definitions and rotation callback first.
  stage_target_asset "$(installer_repo_file_value hooks/target/usr/local/libexec/common/rsyslog-size-rotate.tmpl)" \
    "${DIR_USR_LOCAL_LIBEXEC}/rsyslog-size-rotate" 0755 || return $?
  stage_target_asset "$(installer_repo_file_value hooks/target/etc/rsyslog.conf.tmpl)" \
    __INSTALLER_PATH_DIR_ETC__/rsyslog.conf 0644 || return $?
  installer_asset_batch_finish
}

# Shared GPU publication preserves the selected driver policy in either family.
stage_target_graphics_kernel_tunables() {
  case "${1:-}" in true|false) ;;
    *) installer_fatal 'GPU publication requires an explicit NVIDIA selection'; return 1 ;;
  esac
  stage_target_asset_if_path "$(installer_hardware_asset_path gpu intel-uhd etc/modprobe.d/80-i915.conf)" "${FILE_MODPROBE_I915:-}" "${DIR_MODPROBE_D}/80-i915.conf" 0644
  stage_target_asset_if_path "$(installer_hardware_asset_path gpu amd-radeon etc/modprobe.d/81-amdgpu.conf)" "${FILE_MODPROBE_AMDGPU:-}" "${DIR_MODPROBE_D}/81-amdgpu.conf" 0644
  if [ "$1" = true ]; then
    stage_target_asset "$(installer_repo_file_value hooks/target/etc/modprobe.d/50-nouveau-blacklist.conf)" "${DIR_MODPROBE_D}/50-nouveau-blacklist.conf" 0644
    stage_target_asset "$(installer_hardware_asset_path gpu nvidia etc/modprobe.d/82-nvidia.conf)" "${FILE_MODPROBE_NVIDIA}" 0644
  else
    remove_target_asset "${DIR_MODPROBE_D}/50-nouveau-blacklist.conf"
    remove_target_asset "${DIR_MODPROBE_D}/82-nvidia.conf"
  fi
}

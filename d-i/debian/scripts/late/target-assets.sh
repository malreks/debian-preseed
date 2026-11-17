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
    __INSTALLER_PATH_DIR_USR_LOCAL__/bin|__INSTALLER_PATH_DIR_USR_LOCAL__/bin/*)
      printf '%s%s\n' "${DIR_USR_LOCAL_BIN}" "${target_path#__INSTALLER_PATH_DIR_USR_LOCAL__/bin}"
      ;;
    __INSTALLER_PATH_DIR_USR_LOCAL__/sbin|__INSTALLER_PATH_DIR_USR_LOCAL__/sbin/*)
      printf '%s%s\n' "${DIR_USR_LOCAL_SBIN}" "${target_path#__INSTALLER_PATH_DIR_USR_LOCAL__/sbin}"
      ;;
    __INSTALLER_PATH_DIR_USR_LOCAL__/libexec|__INSTALLER_PATH_DIR_USR_LOCAL__/libexec/*)
      printf '%s%s\n' "${DIR_USR_LOCAL_LIBEXEC}" "${target_path#__INSTALLER_PATH_DIR_USR_LOCAL__/libexec}"
      ;;
    __INSTALLER_PATH_DIR_USR_LOCAL__/lib/perl5/site_perl|__INSTALLER_PATH_DIR_USR_LOCAL__/lib/perl5/site_perl/*)
      printf '%s%s\n' "${DIR_PERL5_SITE_PERL}" "${target_path#__INSTALLER_PATH_DIR_USR_LOCAL__/lib/perl5/site_perl}"
      ;;
    __INSTALLER_PATH_DIR_USR_LOCAL__/lib/hardware_tuning|__INSTALLER_PATH_DIR_USR_LOCAL__/lib/hardware_tuning/*)
      printf '%s%s\n' "${DIR_HARDWARE_TUNING}" "${target_path#__INSTALLER_PATH_DIR_USR_LOCAL__/lib/hardware_tuning}"
      ;;
    __INSTALLER_PATH_DIR_USR_LOCAL__/lib|__INSTALLER_PATH_DIR_USR_LOCAL__/lib/*)
      printf '%s%s\n' "${DIR_USR_LOCAL_LIB}" "${target_path#__INSTALLER_PATH_DIR_USR_LOCAL__/lib}"
      ;;
    __INSTALLER_PATH_DIR_USR_LOCAL__/share|__INSTALLER_PATH_DIR_USR_LOCAL__/share/*)
      printf '%s%s\n' "${DIR_USR_LOCAL_SHARE}" "${target_path#__INSTALLER_PATH_DIR_USR_LOCAL__/share}"
      ;;
    __INSTALLER_PATH_DIR_USR_LOCAL__|__INSTALLER_PATH_DIR_USR_LOCAL__/*)
      printf '%s%s\n' "${DIR_USR_LOCAL}" "${target_path#__INSTALLER_PATH_DIR_USR_LOCAL__}"
      ;;
    __INSTALLER_PATH_DIR_USR_LIBEXEC__|__INSTALLER_PATH_DIR_USR_LIBEXEC__/*)
      printf '%s%s\n' "${DIR_USR_LIBEXEC}" "${target_path#__INSTALLER_PATH_DIR_USR_LIBEXEC__}"
      ;;
    __INSTALLER_PATH_DIR_USR_LIB__/python3/dist-packages|__INSTALLER_PATH_DIR_USR_LIB__/python3/dist-packages/*)
      printf '%s%s\n' "${DIR_PYTHON3_SYSTEM_PACKAGES}" "${target_path#__INSTALLER_PATH_DIR_USR_LIB__/python3/dist-packages}"
      ;;
    __INSTALLER_PATH_DIR_VAR__/lib/firstboot|__INSTALLER_PATH_DIR_VAR__/lib/firstboot/*)
      printf '%s%s\n' "${DIR_FIRSTBOOT}" "${target_path#__INSTALLER_PATH_DIR_VAR__/lib/firstboot}"
      ;;
    __INSTALLER_PATH_DIR_VAR__/lib/installer-state|__INSTALLER_PATH_DIR_VAR__/lib/installer-state/*)
      printf '%s%s\n' "${DIR_VAR_LIB_INSTALLER_STATE}" "${target_path#__INSTALLER_PATH_DIR_VAR__/lib/installer-state}"
      ;;
    __INSTALLER_PATH_DIR_ETC__/systemd|__INSTALLER_PATH_DIR_ETC__/systemd/*)
      printf '%s%s\n' "${DIR_SYSTEMD_ETC}" "${target_path#__INSTALLER_PATH_DIR_ETC__/systemd}"
      ;;
    __INSTALLER_PATH_DIR_VAR__/lib|__INSTALLER_PATH_DIR_VAR__/lib/*)
      printf '%s%s\n' "${DIR_VAR_LIB}" "${target_path#__INSTALLER_PATH_DIR_VAR__/lib}"
      ;;
    __INSTALLER_PATH_DIR_VAR__|__INSTALLER_PATH_DIR_VAR__/*)
      printf '%s%s\n' "${DIR_VAR}" "${target_path#__INSTALLER_PATH_DIR_VAR__}"
      ;;
    __INSTALLER_PATH_DIR_ETC__|__INSTALLER_PATH_DIR_ETC__/*)
      printf '%s%s\n' "${DIR_ETC}" "${target_path#__INSTALLER_PATH_DIR_ETC__}"
      ;;
    __INSTALLER_PATH_DIR_RUN__|__INSTALLER_PATH_DIR_RUN__/*)
      printf '%s%s\n' "${DIR_RUN}" "${target_path#__INSTALLER_PATH_DIR_RUN__}"
      ;;
    *) printf '%s\n' "$target_path" ;;
  esac
}

target_asset_host_path() (
  target_root=${INSTALLER_TARGET_DIR:-${TARGET_ROOT}}
  case "$1" in
    "$target_root"/*)
      target_path="${target_root}$(target_asset_canonical_path "${1#"$target_root"}")"
      ;;
    *) target_path=$(target_asset_canonical_path "$1") ;;
  esac
  for checked_path in "$target_root" "$target_path"; do
    case "$checked_path" in
      /*) ;;
      *) installer_fatal "target asset paths must be absolute: $checked_path"; exit 1 ;;
    esac
    case "$checked_path" in
      *//*|*/../*|*/..|*/./*|*/.)
        installer_fatal "target asset path is not normalized: $checked_path"; exit 1 ;;
    esac
  done
  target_root=${target_root%/}
  case "$target_path" in
    /|"$target_root") installer_fatal "target asset must name a file, not the target root"; exit 1 ;;
    "$target_root"/*) printf '%s\n' "$target_path" ;;
    *) printf '%s%s\n' "$target_root" "$target_path" ;;
  esac
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
  target_root=${INSTALLER_TARGET_DIR:-${TARGET_ROOT}}
  target_host_path=$(target_asset_host_path "$target_path") || exit 1
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

target_asset_contains_installer_placeholders() {
  asset_path=$1

  installer_contains_unresolved_installer_placeholders "$asset_path"
}

target_asset_assert_no_unresolved_installer_placeholders() {
  asset_path=$1
  asset_label=${2:-$asset_path}

  installer_assert_no_unresolved_installer_placeholders "$asset_path" "$asset_label"
}

# Publish only fully fetched/rendered files. A private work directory on the
# destination filesystem makes rename atomic and contains all renderer scratch
# files; failure and signal traps never expose a half-rendered target file.
publish_target_asset() (
  set -eu
  umask 077
  asset_source=$1
  asset_target=$2
  asset_mode=$3
  asset_kind=$4
  asset_map=${5:-}
  asset_work=
  target_publish_step=validate
  target_publish_status=0
  trap 'target_publish_status=$?; trap - 0; if [ -n "$asset_work" ]; then rm -rf -- "$asset_work" || :; fi; if [ "$target_publish_status" -ne 0 ]; then installer_fatal_status "$target_publish_status" "target asset publication failed: step=${target_publish_step} kind=${asset_kind} source=${asset_source} target=${asset_target}"; fi' 0
  # A failed command substitution can leave an empty source argument while
  # the enclosing command still runs. Reject it before preparing or fetching
  # any target path; stdin publication has its own explicit source contract.
  installer_operation_context_repo FILE_LATE_TARGET_ASSETS 178 validate_target_asset
  if [ "$asset_kind" != stdin ] && [ -z "$asset_source" ]; then
    installer_fatal 'target asset source is empty; repository selector resolution failed'
    exit 1
  fi
  case "$asset_mode" in [0-7][0-7][0-7]|[0-7][0-7][0-7][0-7]) ;;
    *) installer_fatal "invalid target asset mode"; exit 1 ;; esac
  if [ "$asset_kind" = plain ] &&
      bootstrap_prepared_asset_published "$asset_source" "$asset_target" "$asset_mode"; then
    exit 0
  fi
  target_publish_step=prepare_destination
  installer_operation_context_repo FILE_LATE_TARGET_ASSETS 186 prepare_target_asset_destination
  asset_destination=$(target_asset_host_path "$asset_target") || exit "$?"
  ensure_target_asset_parent "$asset_target" || exit "$?"
  [ ! -d "$asset_destination" ] || { installer_fatal "asset destination is a directory"; exit 1; }
  asset_work=$(mktemp -d "$(dirname "$asset_destination")/.installer-asset.XXXXXX") || exit "$?"
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  target_publish_step=acquire
  installer_operation_context_repo FILE_LATE_TARGET_ASSETS 195 acquire_target_asset
  if [ "$asset_kind" = stdin ]; then
    cat >"$asset_work/payload" || exit "$?"
  else
    (fetch_hook "$asset_source" "$asset_work/payload") || exit "$?"
  fi
  target_publish_step=render
  installer_operation_context_repo FILE_LATE_TARGET_ASSETS 202 render_target_asset
  case "$asset_kind" in
    plain|stdin)
      # Resolve canonical runtime fields through the shared map. Any other
      # named token needs its typed adapter before this publication boundary.
      (installer_apply_scalar_placeholders \
        "$asset_work/payload" "$asset_work/path-rendered") || exit "$?"
      mv -f "$asset_work/path-rendered" "$asset_work/payload" || exit "$?"
      installer_assert_no_unresolved_installer_placeholders \
        "$asset_work/payload" "target asset $asset_source" || exit "$?"
      ;;
    template)
      (TMP_ENV_DIR=$asset_work; render_target_template "$asset_work/payload" "$asset_work/rendered" "$asset_mode") || exit "$?"
      mv -f "$asset_work/rendered" "$asset_work/payload" || exit "$?"
      ;;
    resources)
      (TMP_ENV_DIR=$asset_work; apply_systemd_resource_placeholders "$asset_work/payload") || exit "$?"
      (target_asset_assert_no_unresolved_installer_placeholders "$asset_work/payload" "resource asset $asset_source") || exit "$?"
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
  installer_operation_context_repo FILE_LATE_TARGET_ASSETS 235 publish_target_asset
  chmod "$asset_mode" "$asset_work/payload" || exit "$?"
  installer_capture_primary_default "$asset_work/payload" "$asset_target" "$asset_mode" || exit "$?"
  mv -fT -- "$asset_work/payload" "$asset_destination" || exit "$?"
)

stage_target_asset() {
  publish_target_asset "$1" "$2" "$3" plain
}

# Generated late-command files use the same publication contract as assets.
write_target_file() {
  publish_target_asset - "$1" "$2" stdin
}

remove_target_asset() (
  target_host_path=$(target_asset_host_path "$1") || exit 1
  rm -f -- "$target_host_path"
)

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
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_DOCS_README)" "${DIR_DATA_DOCS}/README.md" 0644 || return $?
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
  stage_target_asset "$(installer_repo_asset_path DIR_TARGET_DOCS "${repo_relpath}")" "${doc_target_path}" 0644 || return $?
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

remove_target_asset_and_empty_parent() {
  target_path=$1
  target_host_path=$(target_asset_host_path "$target_path")
  target_parent=$(dirname "$target_host_path")

  rm -f "$target_host_path"
  rmdir "$target_parent" 2>__INSTALLER_PATH_DIR_DEV__/null || true
}

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

apply_placeholder_map_to_target() {
  target_path=$1
  map_func=$2
  rendered_tmp="${target_path}.map.$$"
  map_tmp="${TMP_ENV_DIR}/target-placeholder-map.$$.tmp"

  set --
  if ! "$map_func" >"$map_tmp"; then
    rm -f "$map_tmp"
    installer_fatal "failed to render placeholder map ${map_func} for ${target_path}"
  fi
  while IFS= read -r map_line || [ -n "$map_line" ]; do
    map_name=${map_line%%=*}
    map_value=${map_line#*=}
    [ -n "$map_name" ] || continue
    set -- "$@" "$map_name" "$map_value"
  done <"$map_tmp"
  rm -f "$map_tmp"
  installer_apply_scalar_placeholders "$target_path" "$rendered_tmp" "$@" || {
    rm -f "$map_tmp"
    rm -f "$rendered_tmp"
    installer_fatal "failed to apply placeholder map ${map_func} to ${target_path}"
  }
  mv "$rendered_tmp" "$target_path"
}

replace_placeholder_line_block() {
  target_path=$1
  placeholder=$2
  replacement=$3
  rendered_tmp="${target_path}.line.$$"

  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "$placeholder" ]; then
      [ -n "$replacement" ] && printf '%s\n' "$replacement"
      continue
    fi
    printf '%s\n' "$line"
  done <"$target_path" >"$rendered_tmp"
  mv "$rendered_tmp" "$target_path"
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
  fetch_hook "$(installer_repo_file_value FILE_TARGET_FSTAB_TMPL)" "$fstab_work/template" || exit 1
  awk '
    FILENAME == ARGV[1] {
      if (NF == 0) next
      count++
      if ($0 ~ /^[[:space:]]*#/) {
        comments[count] = $0
        section++
        next
      }
      if (NF != 6) { invalid = 1; exit 1 }
      records++
      sections[count] = section
      for (field = 1; field <= 6; field++) {
        cells[count, field] = $field
        if (length($field) > widths[section, field]) widths[section, field] = length($field)
      }
      next
    }
    $0 == ("__INSTALLER_" "FSTAB_RECORDS__") {
      for (row = 1; row <= count; row++) {
        if (row in comments) { print comments[row]; continue }
        section = sections[row]
        # BusyBox awk does not support * widths; use the computed integer.
        # Align within comment-delimited sections, with no empty spacer rows.
        for (field = 1; field < 6; field++)
          printf "%-" widths[section, field] "s  ", cells[row, field]
        print cells[row, 6]
      }
      next
    }
    NF { print }
    END { if (invalid || records == 0) exit 1 }
  ' "$fstab_work/records" "$fstab_work/template" >"$fstab_work/rendered" || exit 1
  installer_assert_no_unresolved_installer_placeholders "$fstab_work/rendered" fstab || exit 1
  [ ! -L ${TARGET_ROOT}${DIR_ETC}/fstab ] || { installer_fatal "refusing a symlinked fstab"; exit 1; }
  chmod 0644 "$fstab_work/rendered" || exit 1
  mv -fT -- "$fstab_work/rendered" ${TARGET_ROOT}${DIR_ETC}/fstab || exit 1
)

# Both storage-family hooks publish this foundation before dispatch runs any
# selected class helper. Private model policies may depend on these ancestors;
# desktop setup is later and must not be their prerequisite. Do not apply it
# before the final __INSTALLER_PATH_DIR_VAR__/log mount setup. Class helpers and rsyslog preflight
# existing paths immediately before their own tmpfiles invocation.
stage_target_logging_foundation() {
  # Journald starts with forwarding off in every storage profile. Publish the
  # complete readiness owner before any selected class can enable rsyslog.
  # Debian's unnumbered vendor syslog.conf sorts after both numbered policies.
  # Replace that basename locally without assigning a competing runtime value.
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_SYSTEMD_JOURNALD_CONF_D_SYSLOG)" \
    __INSTALLER_PATH_DIR_ETC__/systemd/journald.conf.d/syslog.conf 0644 || return $?
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_LIBEXEC_JOURNAL_CHECK)" \
    "${DIR_USR_LOCAL_LIBEXEC}/journal-check" 0755 || return $?
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_LIBEXEC_JOURNAL_FORWARDING)" \
    "${DIR_USR_LOCAL_LIBEXEC}/journal-forwarding" 0755 || return $?
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_UNIT_RSYSLOG_JOURNAL_FORWARDING_SERVICE)" \
    __INSTALLER_PATH_DIR_ETC__/systemd/system/rsyslog-journal-forwarding.service 0644 || return $?
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_UNIT_RSYSLOG_SERVICE_D_40_JOURNAL_FORWARDING)" \
    __INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_RSYSLOG_DROPIN__/40-journal-forwarding.conf 0644 || return $?
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
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_TMPFILES_D_59_LOG_LAYOUT_TMPL)" \
    __INSTALLER_PATH_DIR_ETC__/tmpfiles.d/59-log-layout.conf 0644 || return $?
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_TMPFILES_D_65_AUDIT_SYSLOG)" \
    __INSTALLER_PATH_DIR_ETC__/tmpfiles.d/65-audit-syslog.conf 0644 || return $?
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_LIBEXEC_LOG_LAYOUT_TMPL)" \
    "${DIR_USR_LOCAL_LIBEXEC}/log-layout" 0755 || return $?
  # Selected helpers validate their rsyslog drop-ins before desktop setup.
  # Publish the module/template definitions and rotation callback first.
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_LIBEXEC_RSYSLOG_SIZE_ROTATE_TMPL)" \
    "${DIR_USR_LOCAL_LIBEXEC}/rsyslog-size-rotate" 0755 || return $?
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_RSYSLOG_TMPL)" \
    __INSTALLER_PATH_DIR_ETC__/rsyslog.conf 0644 || return $?
}

#!/bin/sh
# Shared late_command storage maintenance helpers. This file is sourced, not executed.


repair_target_pkgsel_include_packages() {
  stage_target_apt_login_policy_assets
  require_in_target "pkgsel/include package repair"

  # shellcheck disable=SC2016
  missing_packages=$(capture_in_target "detect missing pkgsel/include packages" __INSTALLER_PATH_DIR_BIN__/sh -c '
set -eu
packages=$1
[ -n "$packages" ] || exit 0
# One checked database read also accounts for virtual packages (for example
# mesa-utils-extra provided by mesa-utils). Do not call apt for an installed
# provider merely because the virtual name has no standalone dpkg record.
installed=$(dpkg-query -W -f="\${Status}\t\${binary:Package}\t\${Provides}\t\${Version}\n")
printf "%s\n" "$installed" | awk -F "\t" -v requested="$packages" '\''
$1 == "install ok installed" {
  present[$2] = 1; versions[$2] = $4
  name = $2; sub(/:.*/, "", name); present[name] = 1; versions[name] = $4
  n = split($3, providers, ",")
  for (i = 1; i <= n; i++) {
    name = providers[i]; sub(/^[ \t]+/, "", name); sub(/[ \t:(].*$/, "", name)
    if (name != "") present[name] = 1
  }
}

END {
  n = split(requested, pkgs, /[ \t\n]+/)
  for (i = 1; i <= n; i++) {
    name = pkgs[i]; sub(/\/.*/, "", name)
    count = split(name, wanted, "="); name = wanted[1]
    if (name != "" && (!(name in present) || (count == 2 && versions[name] != wanted[2]))) print pkgs[i]
  }
}'\''

' sh "${INSTALLER_PKGSEL_INCLUDE}")

  legacy_cuda_repair_active=false
  if command -v cuda_legacy_target_apt_required >__INSTALLER_PATH_DIR_DEV__/null 2>&1 && cuda_legacy_target_apt_required; then
    legacy_cuda_repair_active=true
  fi

  repair_status=0
  cleanup_status=0
  if [ -n "$missing_packages" ]; then
    installer_warn "repairing missing pkgsel/include packages in target:${missing_packages:+ ${missing_packages}}"
    if [ "$legacy_cuda_repair_active" = true ]; then
      cuda_legacy_prepare_target_apt_state
    fi
    prepare_target_volatile_dirs_for_apt
    if refresh_non_cuda_target_metadata \
      env DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
      apt-get \
        -o APT::Get::List-Cleanup=0 \
        -o APT::Update::Error-Mode=any \
        -o Acquire::Retries=5 \
        -o Acquire::http::Timeout=45 \
        -o Acquire::https::Timeout=45 \
        -o Binary::apt::APT::Keep-Downloaded-Packages=false \
        -o DPkg::Use-Pty=0 \
        update
    then
      # shellcheck disable=SC2086
      set -- $missing_packages
      if ( run_in_target "install missing pkgsel/include packages" \
          env DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
          apt-get \
            -o Acquire::Retries=5 \
            -o Acquire::http::Timeout=45 \
            -o Acquire::https::Timeout=45 \
            -o Binary::apt::APT::Keep-Downloaded-Packages=false \
            -o DPkg::Use-Pty=0 \
            -y install --no-install-recommends --no-install-suggests "$@" )
      then
        :
      else
        repair_status=$?
      fi
    else
      repair_status=$?
    fi
  fi

  if [ "$legacy_cuda_repair_active" = true ]; then
    if cuda_legacy_cleanup_target_apt_state; then
      :
    else
      cleanup_status=$?
    fi
  fi

  [ "$repair_status" -eq 0 ] || return "$repair_status"
  [ "$cleanup_status" -eq 0 ] || return "$cleanup_status"
  [ -n "$missing_packages" ] || return 0
}

managed_target_policy_assets() {
  cat <<'EOF'
etc/apt/apt.conf.d/20auto-upgrades|__INSTALLER_PATH_DIR_ETC__/apt/apt.conf.d/20auto-upgrades|0644
etc/apt/apt.conf.d/25no-pdiffs|__INSTALLER_PATH_DIR_ETC__/apt/apt.conf.d/25no-pdiffs|0644
etc/apt/apt.conf.d/52unattended-upgrades|__INSTALLER_PATH_DIR_ETC__/apt/apt.conf.d/52unattended-upgrades|0644
etc/apt/apt.conf.d/99noinstall-recommends|__INSTALLER_PATH_DIR_ETC__/apt/apt.conf.d/99noinstall-recommends|0644
etc/login.defs|__INSTALLER_PATH_DIR_ETC__/login.defs|0644
etc/pam.d/polkit-1|__INSTALLER_PATH_DIR_ETC__/pam.d/polkit-1|0644
etc/pam.d/systemd-user|__INSTALLER_PATH_DIR_ETC__/pam.d/systemd-user|0644
etc/systemd/system/apt-daily-upgrade.service.d/50-unattended-upgrades-notify.conf|__INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_APT_DAILY_UPGRADE_DROPIN__/50-unattended-upgrades-notify.conf|0644
etc/systemd/system/fwupd.service.d/20-upower-ordering.conf|__INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_FWUPD_DROPIN__/20-upower-ordering.conf|0644
etc/systemd/system/unattended-upgrades.service.d/override.conf|__INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_UNATTENDED_UPGRADES_DROPIN__/override.conf|0644
usr/local/libexec/unattended-upgrades-notify|__INSTALLER_PATH_DIR_USR_LOCAL__/libexec/unattended-upgrades-notify|0755
EOF
}

stage_target_apt_login_policy_assets() {
  while IFS='|' read -r repo_relpath target_path mode || [ -n "$repo_relpath" ]; do
    [ -n "$repo_relpath" ] || continue
    stage_target_asset "$(installer_repo_asset_path DIR_HOOKS_TARGET "$repo_relpath")" "$target_path" "$mode"
  done <<EOF
$(managed_target_policy_assets)
EOF
}

stage_target_conditional_apt_refresh_assets() {
  if tmpfs_policy_enabled TMPFS_VAR_LIB_APT_LISTS; then
    render_target_template "$TMP_ENV_DIR/apt-refresh-lists.tmpl" "${TARGET_ROOT}${FILE_APT_REFRESH_LISTS_HELPER}" 0755
    render_target_template "$TMP_ENV_DIR/apt-refresh-lists.service.tmpl" "${TARGET_ROOT}${FILE_APT_REFRESH_LISTS_SERVICE}" 0644
  else
    remove_target_asset "${FILE_APT_REFRESH_LISTS_HELPER}"
    remove_target_asset "${FILE_APT_REFRESH_LISTS_SERVICE}"
    remove_target_asset "__INSTALLER_PATH_DIR_ETC__/systemd/system/multi-user.target.wants/apt-refresh-lists.service"
  fi
}

validate_target_tmpfiles_policy_path() {
  case "${1:-}" in
    /*) ;;
    *) installer_fatal "managed tmpfiles policy path must be absolute: ${1:-unset}" ;;
  esac
  case "$1" in
    /|*..*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-]*)
      installer_fatal "managed tmpfiles policy path contains unsupported syntax: ${1}"
      ;;
  esac
}

normalize_target_tmpfiles_directory_policy() {
  tmpfiles_policy_path=$1
  tmpfiles_policy_label=${2:-managed tmpfiles directory policy}

  validate_target_tmpfiles_policy_path "$tmpfiles_policy_path"
  [ -r "${TARGET_ROOT}${tmpfiles_policy_path}" ] ||
    installer_fatal "managed tmpfiles policy is missing before normalization: ${tmpfiles_policy_path}"

  # The short-lived installer program validates the complete d-row plan,
  # pins directory identities and retains durable recovery data on uncertainty.
  # Non-directory tmpfiles records remain the native tool's separate owner.
  installer_run_target_setup FILE_LATE_TMPFILES_DIRECTORIES \
    "normalize ${tmpfiles_policy_label}" "$tmpfiles_policy_path" "$tmpfiles_policy_label" || return "$?"
}

stage_target_runtime_storage_root_policy() {
  render_target_asset "$(installer_repo_file_value FILE_TARGET_TMPFILES_D_10_RUNTIME_STORAGE_ROOTS_TMPL)" "__INSTALLER_PATH_DIR_ETC__/tmpfiles.d/10-runtime-storage-roots.conf" 0644
}

ensure_target_managed_runtime_storage_roots() {
  run_in_target_quiet "ensure shared devops group" __INSTALLER_PATH_DIR_BIN__/sh -eu -c '
getent group devops >__INSTALLER_PATH_DIR_DEV__/null 2>&1 || groupadd --system devops
' sh
  stage_target_runtime_storage_root_policy
  normalize_target_tmpfiles_directory_policy "__INSTALLER_PATH_DIR_ETC__/tmpfiles.d/10-runtime-storage-roots.conf" "shared runtime storage roots"
}

# Global manager/delegation policy is installed even without the desktop role.
# Manager defaults are not tied to a filesystem or to user-slice publication.
# Reapply at the final desktop boundary so the selected profile is authoritative.
stage_target_systemd_manager_accounting() (
  set -eu
  systemd_resource_placeholder_map >__INSTALLER_PATH_DIR_DEV__/null || exit 1
  case "$SYSTEMD_DEFAULT_IOACCOUNTING_ENABLE" in
    true) expected_io=yes ;;
    false) expected_io=no ;;
  esac
  for resource_asset in \
    etc/systemd/system.conf.d/60-resource-accounting.conf \
    etc/systemd/user.conf.d/60-resource-accounting.conf
  do
    render_target_resource_asset \
      "$(installer_repo_asset_path DIR_HOOKS_TARGET "$resource_asset")" \
      "/$resource_asset" 0644 || exit 1
    resource_path=$(target_asset_host_path "/$resource_asset") || exit 1
    # Verify the actual installed bytes, not just the placeholder map.
    for expected_line in "DefaultIOAccounting=$expected_io" \
      DefaultMemoryAccounting=yes DefaultTasksAccounting=yes
    do
      grep -Fxq "$expected_line" "$resource_path" || {
        installer_fatal "manager accounting mismatch in $resource_path: $expected_line"; exit 1;
      }
    done
    [ "$(grep -c '^DefaultIOAccounting=' "$resource_path")" = 1 ] || exit 1
  done
)

stage_target_systemd_resource_policy_assets() (
  set -eu
  # Validate the complete resource profile before publishing any new policy.
  systemd_resource_placeholder_map >__INSTALLER_PATH_DIR_DEV__/null || exit 1
  stage_target_systemd_manager_accounting || exit 1
  for resource_asset in \
    etc/systemd/system/user@.service.d/60-resource-delegation.conf \
    etc/systemd/coredump.conf.d/60-limits.conf \
    etc/systemd/system/systemd-coredump.socket.d/60-poll-limit.conf \
    etc/systemd/system/system-maintenance.slice \
    etc/systemd/system/system-maintenance.slice.d/60-resources.conf \
    etc/systemd/system/system-background.slice \
    etc/systemd/system/system-background.slice.d/60-resources.conf \
    etc/systemd/system/apt-daily.service.d/60-resource-class.conf \
    etc/systemd/system/apt-daily-upgrade.service.d/60-resource-class.conf
  do
    render_target_resource_asset \
      "$(installer_repo_asset_path DIR_HOOKS_TARGET "$resource_asset")" \
      "/$resource_asset" 0644 || exit 1
  done
)

# Validate rendered values, not hard-coded profile defaults. Retain the original
# routing/retention contract while allowing the requested storage overrides.
validate_target_journal_storage_policy() (
  set -eu
  journal_path=$(target_asset_host_path "$FILE_JOURNALD_STORAGE_CONF") || exit 1
  journal_policy=$(systemd_journal_policy_map) || exit 1
  journal_storage=$(printf '%s\n' "$journal_policy" | sed -n 's/^SYSTEMD_JOURNAL_STORAGE=//p')
  journal_seal=$(printf '%s\n' "$journal_policy" | sed -n 's/^SYSTEMD_JOURNAL_SEAL=//p')
  # A duplicate setting could override the expected value despite a successful
  # grep. Require exactly one assignment for every managed directive.
  awk '
    /^[[:space:]]*[#;]/ { next }
    /^[[:space:]]*\[/ { next }
    /^[[:space:]]*[A-Za-z][A-Za-z0-9]*[[:space:]]*=/ {
      key = $0; sub(/[[:space:]]*=.*/, "", key); gsub(/^[[:space:]]+/, "", key)
      if (++seen[key] != 1) exit 1
    }
  ' "$journal_path" || { installer_fatal "duplicate managed journald directive"; exit 1; }
  for required_line in \
    "Storage=$journal_storage" \
    "Seal=$journal_seal" \
    "SystemMaxUse=$SYSTEMD_JOURNAL_SYSTEM_MAX_USE" \
    "SystemKeepFree=$SYSTEMD_JOURNAL_SYSTEM_KEEP_FREE" \
    "SystemMaxFileSize=$SYSTEMD_JOURNAL_SYSTEM_MAX_FILE_SIZE" \
    "SystemMaxFiles=$SYSTEMD_JOURNAL_SYSTEM_MAX_FILES" \
    "RuntimeMaxUse=$SYSTEMD_JOURNAL_RUNTIME_MAX_USE" \
    "RuntimeKeepFree=$SYSTEMD_JOURNAL_RUNTIME_KEEP_FREE" \
    "RuntimeMaxFileSize=$SYSTEMD_JOURNAL_RUNTIME_MAX_FILE_SIZE" \
    "RuntimeMaxFiles=$SYSTEMD_JOURNAL_RUNTIME_MAX_FILES" \
    'MaxRetentionSec=1month' \
    'ForwardToSyslog=no' \
    'ForwardToKMsg=no' \
    'ReadKMsg=no'
  do
    grep -Fxq -- "$required_line" "$journal_path" || {
      installer_fatal "managed journald policy mismatch: $required_line"; exit 1;
    }
  done
)

stage_target_common_storage_maintenance_assets() {
  # Shared by scheduled APT and desktop network consumers. Stage code only;
  # never probe connectivity or contact a service while preparing the target.
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_LIBEXEC_NETWORK_ONLINE_CHECK)" "${DIR_USR_LOCAL_LIBEXEC}/network-online-check" 0755 || return 1
  # Shared by both storage families. Install rules only; never retrigger live
  # installer devices or modify their PCI configuration while staging the target.
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_UDEV_RULES_D_74_NVME_LINK_IDLE)" "__INSTALLER_PATH_DIR_ETC__/udev/rules.d/74-nvme-link-idle.rules" 0644 || return 1
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_SBIN_NVME_PCIE_STATUS)" "__INSTALLER_PATH_DIR_USR_LOCAL__/sbin/nvme-pcie-status" 0755 || return 1
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_INITRAMFS_HOOKS_NVME_LINK_IDLE)" "__INSTALLER_PATH_DIR_ETC__/initramfs-tools/hooks/nvme-link-idle" 0755 || return 1
  stage_target_runtime_storage_root_policy
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_TMPFILES_D_TMP)" "__INSTALLER_PATH_DIR_ETC__/tmpfiles.d/tmp.conf" 0644
  grep -Fxq 'D! /tmp 1777 root root 0' ${TARGET_ROOT}${DIR_ETC}/tmpfiles.d/tmp.conf &&
    grep -Fxq 'e /tmp 1777 root root 7d' ${TARGET_ROOT}${DIR_ETC}/tmpfiles.d/tmp.conf &&
    grep -Fxq 'd __INSTALLER_PATH_DIR_VAR__/tmp 1777 root root 30d' ${TARGET_ROOT}${DIR_ETC}/tmpfiles.d/tmp.conf ||
    installer_fatal "managed temporary-directory tmpfiles policy is incomplete"
  stage_target_apt_login_policy_assets
  render_target_template "$TMP_ENV_DIR/apt-daily.override.conf.tmpl" "${TARGET_ROOT}${FILE_APT_DAILY_SERVICE_OVERRIDE}" 0644
  stage_target_asset "$(installer_repo_file_value FILE_LATE_ASSET_ETC_APT_LISTCHANGES_CONF_INSTALLER_BASE)" "${FILE_APT_LISTCHANGES_CONF}" 0644
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_UNIT_FSTRIM_SERVICE_D_OVERRIDE)" "${FILE_FSTRIM_SERVICE_OVERRIDE}" 0644
  stage_target_asset "$(installer_repo_file_value FILE_TARGET_UNIT_FSTRIM_TIMER_D_OVERRIDE)" "${FILE_FSTRIM_TIMER_OVERRIDE}" 0644
}

target_xfs_scrub_cpuaccounting_units() {
  printf '%s\n' \
    xfs_scrub@.service \
    xfs_scrub_all.service \
    xfs_scrub_media@.service \
    system-xfs_scrub.slice \
    xfs_healer@.service \
    xfs_healer_start.service \
    system-xfs_healer.slice
}

sanitize_target_xfs_scrub_systemd_units() {
  sanitized_count=0

  for xfs_unit in $(target_xfs_scrub_cpuaccounting_units); do
    xfs_unit_path=$(target_systemd_unit_path "$xfs_unit" system 2>__INSTALLER_PATH_DIR_DEV__/null || true)
    [ -n "$xfs_unit_path" ] || continue
    [ -r "${TARGET_ROOT}${xfs_unit_path}" ] || continue
    grep -q '^[[:space:]]*CPUAccounting[[:space:]]*=' "${TARGET_ROOT}${xfs_unit_path}" || continue

    xfs_unit_dest="${TARGET_ROOT}${DIR_SYSTEMD_SYSTEM}/${xfs_unit}"
    xfs_unit_tmp="${xfs_unit_dest}.tmp.$$"
    install -d -m 0755 "${TARGET_ROOT}${DIR_SYSTEMD_SYSTEM}"
    if ! sed '/^[[:space:]]*CPUAccounting[[:space:]]*=/d' "${TARGET_ROOT}${xfs_unit_path}" >"$xfs_unit_tmp"; then
      rm -f "$xfs_unit_tmp"
      installer_fatal "failed to sanitize xfs scrub unit: ${xfs_unit_path}"
    fi
    [ -s "$xfs_unit_tmp" ] || {
      rm -f "$xfs_unit_tmp"
      installer_fatal "sanitized xfs scrub unit is empty: ${xfs_unit_path}"
    }
    install -m 0644 "$xfs_unit_tmp" "$xfs_unit_dest"
    rm -f "$xfs_unit_tmp"
    grep -q '^[[:space:]]*CPUAccounting[[:space:]]*=' "$xfs_unit_dest" &&
      installer_fatal "sanitized xfs scrub unit still contains a CPUAccounting directive: ${xfs_unit_dest#${TARGET_ROOT}}"

    for xfs_unit_link in "${TARGET_ROOT}${DIR_SYSTEMD_SYSTEM}"/*.wants/"$xfs_unit" "${TARGET_ROOT}${DIR_SYSTEMD_SYSTEM}"/*.requires/"$xfs_unit"; do
      [ -L "$xfs_unit_link" ] || continue
      ln -sf "${DIR_SYSTEMD_SYSTEM}/${xfs_unit}" "$xfs_unit_link"
    done
    sanitized_count=$((sanitized_count + 1))
  done

  [ "$sanitized_count" -eq 0 ] ||
    installer_info "sanitized xfs scrub systemd units with removed CPUAccounting directives: ${sanitized_count}"

  # Only stage the drop-in offline. The target's own system manager refreshes
  # its unit cache before the native healer starter scans existing mounts.
  if target_systemd_unit_path xfs_healer_start.service system >__INSTALLER_PATH_DIR_DEV__/null 2>&1; then
    stage_target_asset \
      "$(installer_repo_file_value FILE_TARGET_UNIT_XFS_HEALER_START_SERVICE_D_20_REFRESH_UNIT_CACHE)" \
      __INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_XFS_HEALER_START_DROPIN__/20-refresh-unit-cache.conf 0644 || return 1
  fi
}




apply_apt_refresh_placeholders() {
  target_path=$1
  installer_apply_scalar_placeholders "$target_path" "$target_path.apt-refresh.$$" \
    APT_REFRESH_LISTS_TIMEOUT "$APT_REFRESH_LISTS_TIMEOUT" \
    APT_REFRESH_LISTS_CONNECTIVITY_URL "$APT_REFRESH_LISTS_CONNECTIVITY_URL"
  mv "$target_path.apt-refresh.$$" "$target_path"
}

# A subshell guarantees restoration even if the general update fails or is
# interrupted. Preserve the selected CUDA lists without extending its explicit
# authentication exception to the ordinary Debian/vendor metadata refresh.
refresh_non_cuda_target_metadata() (
  set -eu
  target="${INSTALLER_TARGET_DIR:-${TARGET_ROOT}}"
  source="${target}__INSTALLER_PATH_DIR_APT__/sources.list"
  held="${source}.installer-disabled"
  repository=${CUDA_LEGACY_REPOSITORY_URL:-}
  [ -n "$repository" ] || { installer_fatal 'CUDA legacy repository URL is unavailable while suspending its source'; exit 1; }
  temp=
  restore_cuda_source() {
    status=$?
    trap - 0 HUP INT TERM
    [ -z "$temp" ] || rm -f "$temp"
    if [ -f "$held" ]; then
      rm -f "$source"
      mv -f "$held" "$source" || [ "$status" -ne 0 ] || status=$?
    fi
    exit "$status"
  }
  [ ! -e "$held" ] || { installer_fatal 'stale CUDA source suspension; restore it before retrying'; exit 1; }
  if [ -f "$source" ] && grep -Fq "$repository" "$source"; then
    installer_apt_safe_path "$source" || exit 1
    [ "$(installer_metadata_value "$source" links)" = 1 ] || exit 1
    trap restore_cuda_source 0 HUP INT TERM
    ln "$source" "$held"
    temp=$(mktemp "${source}.cuda-free.XXXXXX")
    awk -v repository="$repository" 'index($0, repository) == 0 {print}' "$source" >"$temp"
    source_mode=$(installer_metadata_value "$source" mode)
    chmod "$source_mode" "$temp"
    mv -f "$temp" "$source"
  fi
  run_in_target 'refresh non-CUDA apt metadata with the default crypto policy' "$@"
)

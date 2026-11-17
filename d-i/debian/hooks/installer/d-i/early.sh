#!/bin/sh
# Shared d-i early hook implementation used by storage families.

early_bool_is_true() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
  esac
  return 1
}

early_bootstrap_fatal() {
  early_bootstrap_message=$(printf '%s' "$*" | tr '\r\n\t' '   ')
  printf '[bootstrap] fatal: %s\n' "$early_bootstrap_message" >&2
  if [ -c /dev/tty4 ] && [ -w /dev/tty4 ]; then
    printf '[bootstrap] fatal: %s\n' "$early_bootstrap_message" >/dev/tty4 || :
  fi
  if command -v logger >/dev/null 2>&1; then
    logger -t preseed-early "fatal: $early_bootstrap_message" 2>/dev/null || :
  fi
  exit 1
}

early_load_bootstrap() {
  requested_seed_base=${1:-}
  runtime_dir=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
  bootstrap_lib=${INSTALLER_BOOTSTRAP_LIB:-${runtime_dir}/bootstrap/bootstrap.sh}

  if [ ! -s "$bootstrap_lib" ]; then
    early_bootstrap_fatal "installer bootstrap library is unavailable: ${bootstrap_lib}"
  fi

  # shellcheck disable=SC1090,SC1091
  . "$bootstrap_lib"
  bootstrap_source_common_lib "$requested_seed_base"
}

early_ensure_crypto_dm_modules() {
  kernel_release=$(uname -r 2>/dev/null || true)
  if [ -n "$kernel_release" ]; then
    hook_anna_install_optional "crypto-dm-modules-${kernel_release}-di" || true
  fi
  hook_anna_install_optional crypto-dm-modules || true
}

early_preload_f2fs_kernel_support() {
  kernel_release=$(uname -r 2>/dev/null || true)
  if [ -n "$kernel_release" ]; then
    hook_anna_install_optional "f2fs-modules-${kernel_release}-di" || true
  fi
  hook_anna_install_optional f2fs-modules || true
  if command -v depmod >/dev/null 2>&1; then
    depmod -a >/dev/null 2>&1 || true
  fi
  if command -v modprobe >/dev/null 2>&1; then
    modprobe f2fs >/dev/null 2>&1 || true
  fi
}

early_preload_f2fs_tooling() {
  early_preload_f2fs_kernel_support
  hook_preload_installer_udeb f2fs-tools-udeb || true
  hook_preload_installer_command mkfs.f2fs f2fs-tools-udeb || true
  hook_preload_installer_command mkfs.ext4 e2fsprogs-udeb || true
  hook_preload_installer_command mkfs.fat dosfstools-udeb || true
}

family_d_i_early_main() {
  requested_seed_base=${1:-}
  requested_host_profile=${2:-}
  hook_family=${3:-}
  runtime_script_path=${4:-}
  preload_f2fs=${6:-false}

  [ -n "$hook_family" ] || early_bootstrap_fatal "d-i early hook family is required"
  [ -n "$runtime_script_path" ] || early_bootstrap_fatal "runtime script path is required"

  early_load_bootstrap "$requested_seed_base"

  LOG="$(installer_runtime_log_file)"
  installer_init_log_file "$LOG" "" "${hook_family} d-i early hook" d-i-early preseed_loaded
  installer_operation_context_repo FILE_INST_DI_EARLY 82 family_d_i_early_main
  trap 'installer_finalize_log "$?"' EXIT
  installer_load_context_if_present || true

  SEED_BASE=$(installer_seed_base "$requested_seed_base")
  installer_persist_seed_source "$SEED_BASE"
  HOST_PROFILE=$(installer_resolve_host_profile "$requested_host_profile")
  installer_log_boot_context
  installer_log_network_context

  install -d -m 0755 \
    ${DIR_INSTALLER_APT_SETUP_GENERATORS} \
    ${DIR_INSTALLER_BASE_INSTALLER_D} \
    ${DIR_INSTALLER_PRE_PKGSEL_D} \
    ${DIR_INSTALLER_FINISH_INSTALL_D} \
    ${DIR_INSTALLER_LIB_PARTMAN_FINISH_D}

  TMP_ENV_DIR="${DIR_INSTALLER_ENV}"
  RUNTIME_DIR=$(installer_runtime_dir)
  STATE_DIR=$(installer_runtime_state_dir)
  CACHE_DIR=$(installer_runtime_cache_dir)
  RUNTIME_ACCOUNT_FILE="${STATE_DIR}/account.answers.cfg"
  RUNTIME_CRYPTO_FILE="${STATE_DIR}/crypto.answers.cfg"
  RUNTIME_PARTMAN_FILE="${STATE_DIR}/partman.answers.cfg"
  RUNTIME_ENV_FILE="${STATE_DIR}/runtime.env"
  RUNTIME_RECIPE_FILE="${CACHE_DIR}/expert_recipe"

  install -d -m 0700 "$TMP_ENV_DIR" "$RUNTIME_DIR"
  bootstrap_source_common_support_libs "$SEED_BASE" "$TMP_ENV_DIR" fetch hook
  fetch_hook_file \
    "$(installer_repo_apt_file APT_CONF_D_99NOINSTALL_RECOMMENDS)" \
    "$TMP_ENV_DIR/99noinstall-recommends"
  chmod 0644 "$TMP_ENV_DIR/99noinstall-recommends"
  fetch_hook_file \
    "$(installer_repo_apt_file APT_CONF_D_25NO_PDIFFS)" \
    "$TMP_ENV_DIR/25no-pdiffs"
  installer_apt_publish_metadata_policy "$TMP_ENV_DIR/25no-pdiffs" \
    "${DIR_INSTALLER_APT_CONF_D}/25no-pdiffs"

  fetch_hook_file "$(installer_repo_file_value FILE_INST_APT_99_APT_PREFERENCES)" "${DIR_INSTALLER_APT_SETUP_GENERATORS}/99-apt-preferences"
  fetch_hook_file "$(installer_repo_file_value FILE_INST_APT_98_CUDA_LEGACY_SOURCE)" "${DIR_INSTALLER_APT_SETUP_GENERATORS}/98-cuda-legacy-source"
  chmod 0755 ${DIR_INSTALLER_APT_SETUP_GENERATORS}/98-cuda-legacy-source
  chmod 0755 ${DIR_INSTALLER_APT_SETUP_GENERATORS}/99-apt-preferences
  fetch_hook_file "$(installer_repo_file_value FILE_INST_BASE_RENDER_TARGET)" "${DIR_INSTALLER_BASE_INSTALLER_D}/00rendertarget"
  chmod 0755 "${DIR_INSTALLER_BASE_INSTALLER_D}/00rendertarget"
  fetch_hook_file "$(installer_repo_file_value FILE_INST_BASE_10_APT_INSTALL_POLICY)" "${DIR_INSTALLER_BASE_INSTALLER_D}/10-apt-install-policy"
  fetch_hook_file "$(installer_repo_file_value FILE_INST_BASE_20_FSTAB_GUARD)" "${DIR_INSTALLER_BASE_INSTALLER_D}/20-fstab-guard"
  chmod 0755 ${DIR_INSTALLER_BASE_INSTALLER_D}/10-apt-install-policy
  fetch_hook_file "$(installer_repo_file_value FILE_INST_PREPKG_PLAN)" "${DIR_INSTALLER_PRE_PKGSEL_D}/50-class-plan"
  chmod 0755 "${DIR_INSTALLER_PRE_PKGSEL_D}/50-class-plan"
  # Finalize volatile backing directories before any target-side APT command,
  # then repair/modernize sources; both still precede validation and 95umount.
  fetch_hook_file "$(installer_repo_file_value FILE_INST_FINISH_99_NORMALIZE_FINISH)" "${DIR_INSTALLER_FINISH_INSTALL_D}/94zz-10-normalize-finish"
  fetch_hook_file "$(installer_repo_file_value FILE_INST_FINISH_95_NORMALIZE_APT)" "${DIR_INSTALLER_FINISH_INSTALL_D}/94zz-20-normalize-apt"
  chmod 0755 ${DIR_INSTALLER_FINISH_INSTALL_D}/94zz-10-normalize-finish ${DIR_INSTALLER_FINISH_INSTALL_D}/94zz-20-normalize-apt
  fetch_hook_file "$(installer_repo_file_value FILE_INST_FINISH_00_INSTALLER_GUARD)" ${DIR_INSTALLER_FINISH_INSTALL_D}/00-installer-guard
  fetch_hook_file "$(installer_repo_file_value FILE_INST_FINISH_94ZZ_99_VALIDATE_TARGET)" ${DIR_INSTALLER_FINISH_INSTALL_D}/94zz-99-validate-target
  # Interpose on the first base-installer APT update, not on the later
  # apt-setup generator. The adapter rejects unknown d-i waypoint layouts.
  fetch_hook_file "$(installer_repo_file_value FILE_COMMON_APT_SOURCES)" "$RUNTIME_DIR/bootstrap/apt-sources.sh"
  fetch_hook_file "$(installer_repo_file_value FILE_PRESEED_NETWORK_APT)" "$RUNTIME_DIR/bootstrap/network-apt.sh"
  fetch_hook_file "$(installer_repo_file_value FILE_PRESEED_BASE_APT_ADAPTER)" "$RUNTIME_DIR/bootstrap/base-apt-adapter.sh"
  /bin/sh -eu "$RUNTIME_DIR/bootstrap/base-apt-adapter.sh" \
    /var/lib/dpkg/info/bootstrap-base.postinst "$RUNTIME_DIR/bootstrap/network-apt.sh"
  # anna has loaded these mandatory components before preseed/early_command.
  # Refuse an installer image missing them rather than run an unguarded phase.
  for component in bootstrap-base apt-setup-udeb pkgsel grub-installer finish-install partman-base; do
    installer_guard_hook "/var/lib/dpkg/info/$component.postinst" component ||
      installer_fatal "cannot supervise mandatory d-i component: $component"
  done
  # Both base hook runners treat child failures as warnings. Supervision must
  # hold on preparation failure before any later hook or kernel transaction.
  for base_hook in "${DIR_INSTALLER_BASE_INSTALLER_D}"/*; do
    [ -x "$base_hook" ] || continue
    installer_guard_hook "$base_hook" base || installer_fatal 'cannot supervise base hook'
  done
  for base_hook in ${DIR_INSTALLER_POST_BASE_INSTALLER_D}/*; do
    [ -x "$base_hook" ] || continue
    installer_guard_hook "$base_hook" post-base || installer_fatal 'cannot supervise post-base hook'
  done
  fetch_hook_file "$(installer_repo_file_value FILE_RUNTIME_COMMON)" "$TMP_ENV_DIR/runtime-common.sh"
  fetch_hook_file "$runtime_script_path" "$TMP_ENV_DIR/runtime.sh"
  fetch_hook_file "$(installer_repo_file_value FILE_RUNTIME_ACCOUNT)" "$TMP_ENV_DIR/account.sh"
  fetch_hook_file "$(installer_repo_file_value FILE_PARTMAN_DETECT_DISK)" "$TMP_ENV_DIR/detect-disk.sh"
  installer_fetch_host_env "$SEED_BASE" "$HOST_PROFILE" "$TMP_ENV_DIR/host.env" 0600
  installer_fetch_account_env "$SEED_BASE" "$TMP_ENV_DIR/account.env" 0600

  # shellcheck disable=SC1090,SC1091
  installer_load_data_env "$TMP_ENV_DIR/host.env"
  RUNTIME_COMMON_LIB="$TMP_ENV_DIR/runtime-common.sh"
  export RUNTIME_COMMON_LIB
  # Load the complete dependency chain before a family can define functions.
  # A failed sourced common module must not be hidden by a later definition.
  # shellcheck disable=SC1090,SC1091
  . "$RUNTIME_COMMON_LIB" || installer_fatal_status "$?" 'cannot load shared storage runtime dependencies'
  # shellcheck disable=SC1090,SC1091
  . "$TMP_ENV_DIR/runtime.sh" || installer_fatal_status "$?" 'cannot load selected storage runtime'
  # shellcheck disable=SC1090,SC1091
  . "$TMP_ENV_DIR/account.sh" || installer_fatal_status "$?" 'cannot load account runtime'
  # shellcheck disable=SC1090,SC1091
  installer_load_data_env "$TMP_ENV_DIR/account.env"

  # Validate credentials before disk discovery, partition tooling or storage
  # planning. /preseed.env belongs to the running initrd, never the target.
  runtime_validate_account_settings

  write_crypto_answers=false
  if command -v runtime_crypto_answers_required >/dev/null 2>&1; then
    if runtime_crypto_answers_required; then
      write_crypto_answers=true
    fi
  fi

  hook_resolve_install_disk "$TMP_ENV_DIR/detect-disk.sh" "$HOST_PROFILE"
  installer_log_disk_context
  # Automatic GPT/ESP planning needs the real installer tools before probing.
  hook_ensure_partition_tooling

  runtime_apply_ssh_from_classes
  runtime_apply_layout_from_cmdline
  runtime_apply_account_from_credentials
  runtime_seed_identity_answers
  installer_log_preseed_context
  installer_info "seeded runtime identity fragment from generated hostname"

  # Partman crypto and later Secure Boot helpers need cryptsetup in d-i.
  hook_ensure_installer_command cryptsetup cryptsetup-udeb
  if runtime_dualboot_class_selected; then
    # grub-installer invokes the installer udeb directly before it evaluates
    # the preseeded GRUB policy. Ensure the real command exists before the
    # pre-pkgsel hook preserves it and installs the temporary no-output shim.
    hook_ensure_installer_command os-prober os-prober-udeb
  fi
  if early_bool_is_true "$write_crypto_answers"; then
    early_ensure_crypto_dm_modules
  fi
  hook_preload_partition_tooling
  if early_bool_is_true "$preload_f2fs"; then
    early_preload_f2fs_tooling
  fi

  runtime_write_account_answers "$RUNTIME_ACCOUNT_FILE"
  runtime_apply_answers_file "$RUNTIME_ACCOUNT_FILE"
  installer_info "seeded runtime account fragment from ${RUNTIME_ACCOUNT_FILE}"

  if early_bool_is_true "$write_crypto_answers"; then
    runtime_write_crypto_answers "$RUNTIME_CRYPTO_FILE"
    runtime_apply_answers_file "$RUNTIME_CRYPTO_FILE"
    installer_info "seeded runtime crypto fragment from ${RUNTIME_CRYPTO_FILE}"
  fi
  runtime_write_effective_account_env "$TMP_ENV_DIR/account.env"

  runtime_capture_dualboot_partition_sizes
  runtime_write_runtime_env "$RUNTIME_ENV_FILE"
  cp "$RUNTIME_ENV_FILE" "${TMP_ENV_DIR}/runtime.env"
  runtime_write_expert_recipe "$RUNTIME_RECIPE_FILE"
  runtime_write_partman_fragment "$RUNTIME_PARTMAN_FILE" "$RUNTIME_RECIPE_FILE"
  runtime_apply_answers_file "$RUNTIME_PARTMAN_FILE"
  installer_info "seeded runtime partman fragment from ${RUNTIME_PARTMAN_FILE}"
  installer_info "hooks installed from $(installer_seed_source_type "$SEED_BASE") seed source $SEED_BASE"
}

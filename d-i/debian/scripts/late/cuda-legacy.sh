#!/bin/sh
# Shared late-command helpers for temporary CUDA 12.8/12.9 target repair state.

cuda_legacy_fragment_cache_path() {
  printf '%s/cuda-legacy.fragment.cfg\n' "${TMP_ENV_DIR:-${DIR_INSTALLER_LATE_ENV}}"
}

cuda_legacy_target_keyring_path() {
  printf '%s\n' __INSTALLER_PATH_FILE_APT_CUDA_LEGACY_ARCHIVE_KEY__
}

cuda_legacy_target_source_path() {
  printf '%s\n' __INSTALLER_PATH_DIR_APT__/sources.list
}

cuda_legacy_target_apt_required() {
  installer_cuda_legacy_selected
}

cuda_legacy_fetch_fragment() {
  installer_cuda_legacy_selected || installer_fatal "cuda-legacy fragment requested without optional/cuda-legacy selected"
  fragment_path=$(cuda_legacy_fragment_cache_path)
  if [ ! -s "$fragment_path" ]; then
    installer_fetch_file "$SEED_BASE" \
      "$(installer_repo_file_value FILE_CLASS_OPTIONAL_NVIDIA_LEGACY)" \
      "$fragment_path" 0600
  fi
  printf '%s\n' "$fragment_path"
}

cuda_legacy_fragment_field_value() {
  field_name=$1
  fragment_path=$(cuda_legacy_fetch_fragment)
  field_value=$(sed -n "s/^d-i[[:space:]]\\+apt-setup\\/local[0-9][0-9]*\\/${field_name}[[:space:]]\\+string[[:space:]]\\+//p" "$fragment_path" | sed -n '1p')
  [ -n "$field_value" ] || installer_fatal "cuda-legacy fragment is missing apt-setup/${field_name}"
  printf '%s\n' "$field_value"
}

cuda_legacy_repository_value() {
  cuda_legacy_fragment_field_value repository
}

cuda_legacy_fragment_repository_url() {
  repo_value=$(cuda_legacy_repository_value)
  set -- $repo_value
  [ "$#" -ge 1 ] || installer_fatal "cuda-legacy repository value is empty"
  printf '%s\n' "$1"
}

cuda_legacy_repository_url() {
  fragment_url=$(cuda_legacy_fragment_repository_url)
  policy_url=$(installer_cuda_repository_url) ||
    installer_fatal "shared host profile policy defines an unsupported CUDA repository"
  [ "$fragment_url" = "$policy_url" ] ||
    installer_fatal "cuda-legacy fragment repository does not match CUDA_LEGACY_REPOSITORY_URL"
  printf '%s\n' "$policy_url"
}

cuda_legacy_repository_suite() {
  repo_value=$(cuda_legacy_repository_value)
  set -- $repo_value
  [ "$#" -ge 2 ] || installer_fatal "cuda-legacy repository value must define a suite"
  printf '%s\n' "$2"
}

cuda_legacy_repository_components() {
  repo_value=$(cuda_legacy_repository_value)
  set -- $repo_value
  [ "$#" -ge 2 ] || installer_fatal "cuda-legacy repository value must define a suite"
  shift 2
  printf '%s\n' "$*"
}

cuda_legacy_target_repo_line() {
  installer_cuda_source_line \
    "$(cuda_legacy_repository_url)" "$(cuda_legacy_repository_suite)" "$(cuda_legacy_repository_components)"
}

cuda_legacy_target_repo_present() {
  source_path="${INSTALLER_TARGET_DIR:-${TARGET_ROOT}}$(cuda_legacy_target_source_path)"
  [ -r "$source_path" ] || return 1
  grep -F -x -q "$(cuda_legacy_target_repo_line)" "$source_path"
}

cuda_legacy_stage_target_repo_source() {
  installer_cuda_stage_target_source \
    "$(cuda_legacy_repository_url)" "$(cuda_legacy_repository_suite)" "$(cuda_legacy_repository_components)"
}

cuda_legacy_prepare_target_apt_state() {
  repo_url=$(cuda_legacy_repository_url)

  cuda_legacy_stage_target_repo_source || return "$?"
  cuda_legacy_target_repo_present "$repo_url" ||
    installer_fatal "cuda-legacy failed to stage ${repo_url} in the target before pkgsel/include repair"
  installer_cuda_refresh_target_apt || return "$?"
  installer_info "prepared legacy CUDA target apt state for pkgsel/include repair"
}

cuda_legacy_cleanup_target_apt_state() {
  # nvidia-legacy now owns this repository even when no toolkit is selected.
  # Retain its scoped key and repository for upgrades, without the temporary
  # installer authentication/date exception.
  installer_cuda_stage_target_source "$(installer_cuda_repository_url)" / "" persistent || return "$?"
  installer_info "retained signed legacy NVIDIA repository after pkgsel/include repair"
}

#!/bin/sh

fetch_resolve_seed_base() {
  if [ -n "${SEED_BASE:-}" ]; then
    FETCH_SEED_BASE=$SEED_BASE
    return 0
  fi

  [ -n "${FETCH_SEED_BASE:-}" ] || FETCH_SEED_BASE=$(installer_current_seed_base)
}

fetch_seed_file() {
  src=$1
  dest=$2
  mode=$3
  label=$4
  fetch_resolve_seed_base || return $?
  if installer_fetch_seed_path "$FETCH_SEED_BASE" "$src" "$dest" "$mode"; then
    return 0
  else
    fetch_seed_status=$?
    installer_error "failed to fetch ${label}: source=${src} destination=${dest} status=${fetch_seed_status}"
    return "$fetch_seed_status"
  fi
}

fetch_env_file() {
  src=$1
  dest=$2
  fetch_resolve_seed_base || return $?
  installer_fetch_file "$FETCH_SEED_BASE" "$src" "$dest" 0600
}

fetch_hook_file() {
  src=$1
  dest=$2
  fetch_resolve_seed_base || return $?
  installer_fetch_file "$FETCH_SEED_BASE" "$src" "$dest" 0755 || return $?
  fetch_render_runtime_path_asset "$src" "$dest" 0755 || return $?
  case "$dest" in
    ${DIR_INSTALLER_BASE_INSTALLER_D}/*) installer_guard_hook "$dest" base ;;
    ${DIR_INSTALLER_POST_BASE_INSTALLER_D}/*) installer_guard_hook "$dest" post-base ;;
    ${DIR_INSTALLER_PRE_PKGSEL_D}/*) installer_guard_hook "$dest" pre-pkgsel ;;
    ${DIR_INSTALLER_APT_SETUP_GENERATORS}/*) installer_guard_hook "$dest" apt ;;
    ${DIR_INSTALLER_FINISH_INSTALL_D}/*) installer_guard_hook "$dest" finish ;;
    ${DIR_INSTALLER_LIB_PARTMAN_FINISH_D}/*) installer_guard_hook "$dest" partman ;;
  esac
}

fetch_render_runtime_path_asset() {
  fetch_path_source=$1
  fetch_path_dest=$2
  fetch_path_mode=${3:-0755}
  case "$fetch_path_source" in
    "${DIR_SCRIPTS_LATE}/"*|"${DIR_SCRIPTS_DESKTOP}/"*|"${DIR_SCRIPTS_FIRSTBOOT}/"*|"${DIR_HOOKS_TARGET}/"*) ;;
    *) return 0 ;;
  esac
  if LC_ALL=C grep -q '__INSTALLER_PATH_' "$fetch_path_dest"; then
    fetch_path_rendered="${fetch_path_dest}.path-rendered"
    installer_apply_scalar_placeholders "$fetch_path_dest" "$fetch_path_rendered" || {
      rm -f -- "$fetch_path_rendered"
      return 1
    }
    installer_assert_no_unresolved_path_placeholders "$fetch_path_rendered" "$fetch_path_source" || {
      rm -f -- "$fetch_path_rendered"
      return 1
    }
    chmod "$fetch_path_mode" "$fetch_path_rendered" || {
      rm -f -- "$fetch_path_rendered"
      return 1
    }
    mv -f -- "$fetch_path_rendered" "$fetch_path_dest"
  else
    fetch_path_probe_status=$?
    [ "$fetch_path_probe_status" = 1 ] || return 1
  fi
}

fetch_ssh_asset() {
  src=$1
  dest=$2
  ssh_repo_dir=ssh

  case "$src" in
    "${ssh_repo_dir}"/*) ;;
    *)
      installer_fatal "SSH asset path must stay under ${ssh_repo_dir}: ${src}"
      ;;
  esac
  case "$src" in
    *..*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-]*)
      installer_fatal "SSH asset path contains unsupported characters: ${src}"
      ;;
  esac
  fetch_resolve_seed_base || return $?
  installer_fetch_seed_path "$FETCH_SEED_BASE" "$src" "$dest" 0600 || {
    ssh_fetch_status=$?
    installer_fatal_status "$ssh_fetch_status" "failed to fetch SSH asset: source=${src} destination=${dest}"
  }

  chmod 0600 "$dest"
}

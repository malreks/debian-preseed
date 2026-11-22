#!/bin/sh
# Sourced installer module; edit this file directly.
# shellcheck disable=SC2154

devops_prepare_codex_layout() {
  # shellcheck disable=SC2016
  run_in_target "prepare OpenAI Codex installation layout" __INSTALLER_PATH_DIR_BIN__/sh -eu -c '
account_user=$1
codex_root=$2
codex_log_dir=$3
codex_sqlite_home=$4
codex_runtime_root=$5

for required_command in chmod getent id install find; do
  command -v "$required_command" >__INSTALLER_PATH_DIR_DEV__/null 2>&1 || {
    printf "fatal: required Codex target command is unavailable: %s\n" "$required_command" >&2
    exit 1
  }
done
getent passwd "$account_user" >__INSTALLER_PATH_DIR_DEV__/null 2>&1 || {
  printf "fatal: required Codex account is missing: %s\n" "$account_user" >&2
  exit 1
}
devops_group_record=$(getent group devops) || {
  printf "fatal: required target group is missing: devops\n" >&2
  exit 1
}
account_uid=$(id -u "$account_user")
devops_gid=${devops_group_record#*:}
devops_gid=${devops_gid#*:}
devops_gid=${devops_gid%%:*}
case "$account_uid:$devops_gid" in
  *[!0123456789:]*|:*|*:)
    printf "fatal: unable to resolve Codex account or devops group ids\n" >&2
    exit 1
    ;;
esac

codex_prepare_directory() {
  directory_label=$1
  directory_path=$2
  expected_uid=$3
  expected_gid=$4
  expected_mode=$5
  expected_metadata="${expected_uid}:${expected_gid}:${expected_mode}"

  if [ -L "$directory_path" ]; then
    printf "fatal: Codex %s must not be a symlink: %s\n" \
      "$directory_label" "$directory_path" >&2
    exit 1
  fi
  if [ -e "$directory_path" ]; then
    [ -d "$directory_path" ] || {
      printf "fatal: Codex %s is not a directory: %s\n" \
        "$directory_label" "$directory_path" >&2
      exit 1
    }
    actual_metadata=$(find -P "$directory_path" -maxdepth 0 -printf "%U:%G:%m")
    [ "$actual_metadata" = "$expected_metadata" ] || {
      printf "fatal: existing Codex %s has unexpected ownership or mode: expected %s, found %s\n" \
        "$directory_label" "$expected_metadata" "$actual_metadata" >&2
      exit 1
    }
    return 0
  fi

  install -d -m "$expected_mode" -o "$expected_uid" -g "$expected_gid" \
    "$directory_path"
  chmod a-s -- "$directory_path"
  chmod "$expected_mode" -- "$directory_path"
  actual_metadata=$(find -P "$directory_path" -maxdepth 0 -printf "%U:%G:%m")
  [ "$actual_metadata" = "$expected_metadata" ] || {
    printf "fatal: prepared Codex %s has unexpected ownership or mode: expected %s, found %s\n" \
      "$directory_label" "$expected_metadata" "$actual_metadata" >&2
    exit 1
  }
}

[ -d __INSTALLER_PATH_DIR_DATA__ ] || install -d -m 0755 -o root -g root __INSTALLER_PATH_DIR_DATA__
[ ! -L __INSTALLER_PATH_DIR_DATA__ ] || {
  printf "fatal: __INSTALLER_PATH_DIR_DATA__ must not be a symlink\n" >&2
  exit 1
}

# A resumed late stage may revisit this installer-owned skeleton. Reuse only
# directories whose type, owner, group, and mode exactly match the contract.
codex_prepare_directory root "$codex_root" 0 "$devops_gid" 3770
codex_prepare_directory share "$codex_root/share" 0 0 755
codex_prepare_directory binary "$codex_root/share/bin" 0 0 755
codex_prepare_directory library "$codex_root/lib" 0 0 755
codex_prepare_directory log "$codex_log_dir" "$account_uid" "$devops_gid" 2770
codex_prepare_directory SQLite "$codex_sqlite_home" "$account_uid" "$devops_gid" 2770
codex_prepare_directory runtime "$codex_runtime_root" "$account_uid" "$devops_gid" 2770
' sh \
    "$ACCOUNT_USERNAME" \
    "$DEVOPS_CODEX_ROOT" \
    "$DEVOPS_CODEX_LOG_DIR" \
    "$DEVOPS_CODEX_SQLITE_HOME" \
    "$DEVOPS_CODEX_RUNTIME_ROOT"
}

devops_apply_codex_tmpfiles() {
  codex_tmpfiles_policy=__INSTALLER_PATH_DIR_ETC__/tmpfiles.d/80-codex-storage.conf

  [ -r "${target_root}${codex_tmpfiles_policy}" ] ||
    devops_fatal "Codex tmpfiles policy is missing before application: ${codex_tmpfiles_policy}"
  if [ "$INSTALLER_HOST_VARIANT" = desktop ]; then
    run_in_target "preflight desktop logging paths before Codex tmpfiles" \
      __INSTALLER_PATH_DIR_USR_LOCAL__/libexec/log-layout --preflight || return $?
    run_in_target "apply desktop logging and Codex directory policy" \
      __INSTALLER_PATH_DIR_USR_BIN__/systemd-tmpfiles --create \
        __INSTALLER_PATH_DIR_ETC__/tmpfiles.d/59-log-layout.conf "$codex_tmpfiles_policy" || return $?
  else
    # Server logging has a separate native policy. Codex owns only its own
    # private runtime/log paths; no desktop notification groups are required.
    run_in_target "apply headless Codex directory policy" \
      __INSTALLER_PATH_DIR_USR_BIN__/systemd-tmpfiles --create "$codex_tmpfiles_policy" || return $?
  fi
}

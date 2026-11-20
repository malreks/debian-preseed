#!/bin/sh
# Sourced installer module; edit this file directly.

desktop_validate_obsidian_git_auto_enable() {
  case "${OBSIDIAN_GIT_AUTO_ENABLE-}" in
    true|false) ;;
    *) installer_fatal "OBSIDIAN_GIT_AUTO_ENABLE must be exactly true or false" ;;
  esac
}

desktop_validate_obsidian_git_policy() {
  installer_desktop_class_selected || installer_fatal "private desktop repositories require a desktop role"
  desktop_validate_obsidian_git_auto_enable
  : "${OBSIDIAN_GIT_REPOSITORY_URL:?desktop profile must define the Obsidian Git SSH repository}"
  : "${OBSIDIAN_GIT_REPOSITORY_BRANCH:?desktop profile must define the Obsidian branch}"
  : "${OBSIDIAN_GIT_DIRECTORY:?desktop profile must define the Obsidian checkout}"
  : "${OBSIDIAN_GIT_SYNC_INTERVAL:?desktop profile must define the Obsidian sync interval}"
  case "$OBSIDIAN_GIT_REPOSITORY_URL" in
    git@[A-Za-z0-9.-]*:*/[A-Za-z0-9._-]*) ;;
    *) installer_fatal "Obsidian repository must use a valid Git SSH source" ;;
  esac
  case "$OBSIDIAN_GIT_REPOSITORY_BRANCH" in
    ''|*[!A-Za-z0-9._/-]*|/*|*/|*//*|*..*)
      installer_fatal "Obsidian branch contains unsupported syntax" ;;
  esac
  case "$OBSIDIAN_GIT_DIRECTORY" in
    ''|/*|*..*|*//*|*/*/*|*[!A-Za-z0-9._/-]*)
      installer_fatal "Obsidian checkout path contains unsupported syntax" ;;
  esac
}

desktop_install_obsidian_repository() {
  installer_desktop_class_selected || installer_fatal "private desktop repositories require a desktop role"
  desktop_validate_obsidian_git_policy
  if managed_git_ssh_target_action clone-obsidian; then
    :
  else
    desktop_clone_status=$?
    installer_fatal_status "$desktop_clone_status" 'cannot clone Obsidian vault with the managed GitLab SSH identity'
  fi
  desktop_log "cloned_obsidian_git_repository branch=${OBSIDIAN_GIT_REPOSITORY_BRANCH} path=${ACCOUNT_HOME}/${OBSIDIAN_GIT_DIRECTORY}"
}

desktop_install_browser_repository() {
  installer_desktop_class_selected || installer_fatal "private desktop repositories require a desktop role"
  : "${BROWSER_NETSCAPE_REPOSITORY_URL:?desktop profile must define the browser Git SSH repository}"
  : "${BROWSER_NETSCAPE_REPOSITORY_BRANCH:?desktop profile must define the browser branch}"
  : "${BROWSER_NETSCAPE_DIRECTORY:?desktop profile must define the browser checkout}"
  case "$BROWSER_NETSCAPE_REPOSITORY_URL" in
    git@[A-Za-z0-9.-]*:*/[A-Za-z0-9._-]*) ;;
    *) installer_fatal "browser repository must use a valid Git SSH source" ;;
  esac
  case "$BROWSER_NETSCAPE_REPOSITORY_BRANCH" in
    ''|*[!A-Za-z0-9._/-]*|/*|*/|*//*|*..*)
      installer_fatal "browser branch contains unsupported syntax" ;;
  esac
  case "$BROWSER_NETSCAPE_DIRECTORY" in
    ''|/*|*..*|*//*|*/*/*|*[!A-Za-z0-9._/-]*)
      installer_fatal "browser checkout path contains unsupported syntax" ;;
  esac
  if managed_git_ssh_target_action clone-netscape \
    --repository-url "$BROWSER_NETSCAPE_REPOSITORY_URL" \
    --repository-branch "$BROWSER_NETSCAPE_REPOSITORY_BRANCH"; then
    :
  else
    desktop_clone_status=$?
    installer_fatal_status "$desktop_clone_status" 'cannot clone browser exports with the managed GitLab SSH identity'
  fi
  desktop_log "cloned_browser_repository branch=${BROWSER_NETSCAPE_REPOSITORY_BRANCH} path=${ACCOUNT_HOME}/${BROWSER_NETSCAPE_DIRECTORY}"
}

desktop_install_user_config() {
  : "${ACCOUNT_USERNAME:?ACCOUNT_USERNAME must be set}"
  : "${ACCOUNT_HOME:?ACCOUNT_HOME must be set}"

  desktop_log "installing primary account desktop config user=${ACCOUNT_USERNAME} home=${ACCOUNT_HOME}"
  installer_publish_primary_defaults desktop "$ACCOUNT_USERNAME" "$ACCOUNT_HOME"
  installer_run_target_setup scripts/common/primary-defaults.py 'create fresh primary-account btop config views' \
    btop-profiles "${DIR_INSTALLER_TARGET_DEFAULTS}/desktop" "$ACCOUNT_USERNAME" "$ACCOUNT_HOME"
  # shellcheck disable=SC2016
  run_in_target "install Labwc desktop config for primary account" __INSTALLER_PATH_DIR_BIN__/sh -c '
set -eu
account_user=$1
account_home=$2
payload_defaults=$3
uid=$(id -u "$account_user")
gid=$(id -g "$account_user")
[ "$uid" -ne 0 ] || exit 1
[ -d "$account_home" ] && [ ! -L "$account_home" ] || exit 1
for private_dir in \
  "$account_home/.config" \
  "$account_home/.cache" \
  "$account_home/.cache/recoll" \
  "$account_home/.local" \
  "$account_home/.local/share" \
  "$account_home/.local/share/task" \
  "$account_home/.local/share/task/hooks" \
  "$account_home/Syncthing" \
  "$account_home/Syncthing/micro" \
  "$account_home/Syncthing/keepassxc" \
  "$account_home/Syncthing/keepassxc/backups"
do
  [ ! -L "$private_dir" ] || exit 1
  install -d -m 0700 "$private_dir"
  chown "$uid:$gid" "$private_dir"
done
if [ ! -f "$payload_defaults/.config/wireplumber/wireplumber.conf.d/30-p15s-audio.conf" ]; then
  rm -f "$account_home/.config/wireplumber/wireplumber.conf.d/30-p15s-audio.conf"
fi
chown "$uid:$gid" "$account_home"
chmod 0700 "$account_home"
if [ -x __INSTALLER_PATH_DIR_USR_BIN__/vivaldi-stable ]; then
  for vivaldi_dir in \
    "$account_home/.cache" \
    "$account_home/.cache/vivaldi" \
    "$account_home/.config/vivaldi"
  do
    install -d -m 0700 "$vivaldi_dir"
    chown "$uid:$gid" "$vivaldi_dir"
  done
fi
# Only normalize account-owned entries. Prune foreign-owned directories before
# descending or changing modes: NFS bind parents are root-owned and immutable,
# and their unmounted endpoints must retain mode 0000. -xdev alone is insufficient.
find -P "$account_home" -xdev ! -uid "$uid" -prune -o -type d -exec chmod 0700 {} +
find -P "$account_home" -xdev ! -uid "$uid" -prune -o -type f -perm /0100 -exec chmod 0700 {} +
find -P "$account_home" -xdev ! -uid "$uid" -prune -o -type f ! -perm /0100 -exec chmod 0600 {} +
# Unit files and drop-ins are data, never programs. Do not preserve execute
# bits from a copied/restored skeleton on Whisper or other user units.
find -P "$account_home/.config/systemd/user" -xdev ! -uid "$uid" -prune -o -type f -exec chmod 0600 {} +
zsh_path=$(command -v zsh 2>__INSTALLER_PATH_DIR_DEV__/null || true)
if [ -n "$zsh_path" ]; then
  usermod -s "$zsh_path" "$account_user"
fi
account_shell=$(getent passwd "$account_user" | cut -d: -f7)
printf "desktop_account_config user=%s home=%s source=rendered-payload shell=%s\n" "$account_user" "$account_home" "$account_shell"
' sh "$ACCOUNT_USERNAME" "$ACCOUNT_HOME" "${DIR_INSTALLER_TARGET_DEFAULTS}/desktop"
  desktop_install_primary_account_calendar_stack
  run_in_target "synchronize primary account application launchers" \
    __INSTALLER_PATH_DIR_USR_LOCAL__/bin/labwc-sync-application-launchers "$ACCOUNT_USERNAME" "$ACCOUNT_HOME"
  desktop_bootstrap_primary_account_gpg_key
  desktop_install_obsidian_repository
  desktop_install_browser_repository
  desktop_log "installed primary account desktop config user=${ACCOUNT_USERNAME}"
}

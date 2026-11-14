# POSIX login environment for headless server accounts.
if [ "${SERVER_PROFILE_LOADED:-0}" = 1 ]; then return; fi
SERVER_PROFILE_LOADED=1
umask 077
PATH=__INSTALLER_PATH_DIR_USR_LOCAL_BIN__:__INSTALLER_PATH_DIR_USR_BIN__:__INSTALLER_PATH_DIR_BIN__
export PATH
for server_profile in "$HOME"/.profile.d/[0-9][0-9]-*.sh; do
  if [ -f "$server_profile" ] && [ ! -L "$server_profile" ]; then
    . "$server_profile"
  fi
done
unset server_profile
if [ -n "${BASH_VERSION:-}" ] && [ -f "$HOME/.bashrc" ] && [ ! -L "$HOME/.bashrc" ]; then
  . "$HOME/.bashrc"
fi

# Minimal POSIX login environment for an explicitly created local account.
# Use the login account's HOME; no desktop, server, toolchain or service hooks.
umask 077
PATH=__INSTALLER_PATH_DIR_USR_LOCAL_BIN__:__INSTALLER_PATH_DIR_USR_BIN__:__INSTALLER_PATH_DIR_BIN__
export PATH
XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-"$HOME/.config"}
XDG_CACHE_HOME=${XDG_CACHE_HOME:-"$HOME/.cache"}
XDG_DATA_HOME=${XDG_DATA_HOME:-"$HOME/.local/share"}
XDG_STATE_HOME=${XDG_STATE_HOME:-"$HOME/.local/state"}
export XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME
if [ -n "${BASH_VERSION:-}" ] && [ -f "$HOME/.bashrc" ] && [ ! -L "$HOME/.bashrc" ]; then
  # shellcheck disable=SC1091
  . "$HOME/.bashrc"
fi

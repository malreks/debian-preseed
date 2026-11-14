# Codex login environment only. Installation belongs to the unattended installer.
codex_srv_apply_environment() {
  [ -x __INSTALLER_PATH_DIR_DATA_CODEX__/lib/codex ] &&
    [ -d __INSTALLER_PATH_DIR_DATA_CODEX__/usr/home ] &&
    [ ! -L __INSTALLER_PATH_DIR_DATA_CODEX__/usr/home ] &&
    [ -O __INSTALLER_PATH_DIR_DATA_CODEX__/usr/home ] || return 1
  CODEX_AGENTS=__INSTALLER_PATH_DIR_DATA_CODEX__/usr/agents
  CODEX_HOME=__INSTALLER_PATH_DIR_DATA_CODEX__/usr/home
  CODEX_SKILLS=__INSTALLER_PATH_DIR_DATA_CODEX__/usr/skills
  CODEX_LOG_DIR=__INSTALLER_PATH_DIR_DATA_CODEX__/log
  CODEX_SQLITE_HOME=__INSTALLER_PATH_DIR_DATA_CODEX__/sqlite
  export CODEX_AGENTS CODEX_HOME CODEX_SKILLS CODEX_LOG_DIR CODEX_SQLITE_HOME
  case :$PATH: in
    *:__INSTALLER_PATH_DIR_DATA_CODEX__/lib:*) ;;
    *) PATH=$PATH:__INSTALLER_PATH_DIR_DATA_CODEX__/lib ;;
  esac
  export PATH
}
codex_srv_apply_environment

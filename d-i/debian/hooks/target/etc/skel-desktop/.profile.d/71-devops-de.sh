# shellcheck shell=sh
# Managed by unattended-installer.
#
# DevOps tooling is deliberately opt-in for ordinary terminals. Sourcing this
# fragment defines the environment and toggle functions; the optional managed
# Podman client section at the end also exports its ordinary-shell endpoints.
# Sourcing does not alter PATH or activate the broader DevOps toolchain. `devops_de_apply_environment` is the authoritative
# noninteractive environment used when managed Codex CLI and ChatGPT/Codex
# desktop-app launches do not already inherit an active DevOps shell. An active
# shell is marked only after construction completes so Codex can preserve its
# exact exported values and PATH. The `devops` command starts a nested
# interactive shell in the current terminal and working directory. Exiting that
# shell, or running `devops` again from it, returns to the unchanged ordinary
# shell environment.

DEVOPS_DE_SCX_WORKER_PERFORMANCE="__INSTALLER_HARDWARE_CPU_SCHEDULER_SCX_WORKER_PERFORMANCE__"

devops_de_prepend_path() {
  case "$#" in
    1) ;;
    *) return 64 ;;
  esac

  case "$1" in
    /*) ;;
    *) return 64 ;;
  esac
  case "$1" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./@+-]*)
      return 64
      ;;
  esac
  case "/$1/" in
    */./*|*/../*) return 64 ;;
  esac

  case ":${PATH:-}:" in
    *":$1:"*) ;;
    *) PATH="$1${PATH:+:${PATH}}" ;;
  esac
}

devops_de_append_path() {
  case "$#" in
    1) ;;
    *) return 64 ;;
  esac

  case "$1" in
    /*) ;;
    *) return 64 ;;
  esac
  case "$1" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./@+-]*)
      return 64
      ;;
  esac
  case "/$1/" in
    */./*|*/../*) return 64 ;;
  esac

  case ":${PATH:-}:" in
    *":$1:"*) ;;
    *) PATH="${PATH:+${PATH}:}$1" ;;
  esac
}

# Runtime filesystem validation. These helpers run in subshells so their
# scratch variables never leak into an interactive caller.
devops_de_account_owned_directory_is_mode() (
  case "$#" in
    2) ;;
    *) return 64 ;;
  esac

  devops_de_path_value=$1
  devops_de_path_mode=$2
  case "$devops_de_path_value" in
    /*) ;;
    *) return 1 ;;
  esac
  case "$devops_de_path_mode" in
    ''|*[!0-7]*) return 1 ;;
  esac

  [ -d "$devops_de_path_value" ] &&
    [ ! -L "$devops_de_path_value" ] &&
    [ -r "$devops_de_path_value" ] &&
    [ -w "$devops_de_path_value" ] &&
    [ -x "$devops_de_path_value" ] ||
    return 1

  devops_de_path_real=$(__INSTALLER_PATH_DIR_USR__/bin/readlink -f -- "$devops_de_path_value" 2>__INSTALLER_PATH_DIR_DEV__/null) ||
    return 1
  [ "$devops_de_path_real" = "$devops_de_path_value" ] || return 1
  devops_de_path_owner=$(__INSTALLER_PATH_DIR_USR__/bin/find -P "$devops_de_path_value" -maxdepth 0 -printf '%U' 2>__INSTALLER_PATH_DIR_DEV__/null) ||
    return 1
  devops_de_path_actual_mode=$(__INSTALLER_PATH_DIR_USR__/bin/find -P "$devops_de_path_value" -maxdepth 0 -printf '%m' 2>__INSTALLER_PATH_DIR_DEV__/null) ||
    return 1
  devops_de_path_uid=$(__INSTALLER_PATH_DIR_USR__/bin/id -u 2>__INSTALLER_PATH_DIR_DEV__/null) || return 1
  [ "$devops_de_path_owner" = "$devops_de_path_uid" ] &&
    [ "$devops_de_path_actual_mode" = "$devops_de_path_mode" ]
)

# This internal helper deliberately rejects all arguments.
# shellcheck disable=SC2120
devops_de_validate_runtime_directory() (
  case "$#" in
    0) ;;
    *) return 64 ;;
  esac

  devops_de_runtime_uid=$(__INSTALLER_PATH_DIR_USR__/bin/id -u 2>__INSTALLER_PATH_DIR_DEV__/null) || {
    printf '%s\n' 'devops: cannot resolve the current account identifier' >&2
    return 1
  }
  case "$devops_de_runtime_uid" in
    ''|*[!0-9]*)
      printf '%s\n' 'devops: the current account identifier is malformed' >&2
      return 1
      ;;
  esac
  devops_de_expected_runtime_dir="__INSTALLER_PATH_DIR_RUN_USER__/${devops_de_runtime_uid}"
  [ "${XDG_RUNTIME_DIR:-}" = "$devops_de_expected_runtime_dir" ] || {
    printf 'devops: XDG_RUNTIME_DIR must be %s\n' "$devops_de_expected_runtime_dir" >&2
    return 1
  }
  devops_de_account_owned_directory_is_mode "$XDG_RUNTIME_DIR" 700 || {
    printf '%s\n' 'devops: XDG_RUNTIME_DIR must be a direct account-owned mode-0700 directory' >&2
    return 1
  }
)

devops_de_ensure_private_runtime_directory() (
  case "$#" in
    1) ;;
    *) return 64 ;;
  esac

  devops_de_private_runtime_path=$1
  case "$devops_de_private_runtime_path" in
    /*) ;;
    *) return 64 ;;
  esac
  if [ ! -e "$devops_de_private_runtime_path" ] &&
     [ ! -L "$devops_de_private_runtime_path" ]; then
    (umask 077 && __INSTALLER_PATH_DIR_USR__/bin/mkdir -- "$devops_de_private_runtime_path") || return 1
    __INSTALLER_PATH_DIR_USR__/bin/chmod 00700 -- "$devops_de_private_runtime_path" || return 1
  fi
  devops_de_account_owned_directory_is_mode \
    "$devops_de_private_runtime_path" \
    700
)

# Interactive shell integration.
devops_de_push_terminal_title() {
  printf '\033[22;0t'
}

devops_de_set_terminal_title() {
  case "${DEVOPS_DE_ACTIVE:-}" in
    1) printf '\033]0;%s\007' '[devops]' ;;
  esac
}

devops_de_restore_terminal_title() {
  printf '\033[23;0t'
}

devops_de_enable_zsh_terminal_title() {
  case "${DEVOPS_DE_ACTIVE:-}:${ZSH_VERSION:-}" in
    1:?*) ;;
    *) return 0 ;;
  esac

  autoload -Uz add-zsh-hook || return 1
  add-zsh-hook -d precmd devops_de_set_terminal_title 2>__INSTALLER_PATH_DIR_DEV__/null || true
  add-zsh-hook -d preexec devops_de_set_terminal_title 2>__INSTALLER_PATH_DIR_DEV__/null || true
  add-zsh-hook precmd devops_de_set_terminal_title || return 1
  add-zsh-hook preexec devops_de_set_terminal_title || return 1
  devops_de_set_terminal_title
}

devops_de_enable_shell_completions() {
  case "${DEVOPS_DE_ACTIVE:-}:${DEVOPS_DE_COMPLETIONS_ENABLED:-}" in
    1:) ;;
    *) return 0 ;;
  esac

  case "${BASH_VERSION:-}:${ZSH_VERSION:-}" in
    ?*:|:?*) ;;
    *) return 0 ;;
  esac

  # The shell gate above leaves only Bash and Zsh, both of which provide
  # function-local variables through `local`.
  # shellcheck disable=SC3043
  local devops_de_ansible_completion

  case "${BASH_VERSION:-}:${ZSH_VERSION:-}" in
    ?*:)
      devops_de_ansible_completion=__INSTALLER_PATH_DIR_USR_LOCAL_LIB__/ansible/share/bash-completion/completions/ansible
      ;;
    :?*)
      autoload -Uz bashcompinit || return 1
      bashcompinit || return 1
      devops_de_ansible_completion=__INSTALLER_PATH_DIR_USR_LOCAL_LIB__/ansible/share/zsh/site-functions/_ansible-managed
      ;;
    *) return 0 ;;
  esac

  if [ -x __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/ansible/bin/ansible ]; then
    [ -r "$devops_de_ansible_completion" ] || return 1
    # shellcheck disable=SC1090
    . "$devops_de_ansible_completion" || return 1
  fi
  if [ -x __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/hashicorp/terraform/bin/terraform ]; then
    # Bash provides `complete` directly; Zsh provides it through bashcompinit above.
    # shellcheck disable=SC3044
    complete -o nospace \
      -C __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/hashicorp/terraform/bin/terraform \
      terraform || return 1
  fi
  if [ -x __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/hashicorp/packer/bin/packer ]; then
    # Bash provides `complete` directly; Zsh provides it through bashcompinit above.
    # shellcheck disable=SC3044
    complete -o nospace \
      -C __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/hashicorp/packer/bin/packer \
      packer || return 1
  fi

  DEVOPS_DE_COMPLETIONS_ENABLED=1
}

devops_de_deactivate() {
  case "${DEVOPS_DE_ACTIVE:-}" in
    1)
      printf '%s\n' 'DevOps environment deactivated'
      exit 0
      ;;
    *)
      printf '%s\n' 'devops: no DevOps environment is active' >&2
      return 1
      ;;
  esac
}

devops_de_environment_is_active() {
  case "$#" in
    0) ;;
    *) return 64 ;;
  esac

  [ "${DEVOPS_DE_ACTIVE:-}" = 1 ] &&
    [ "${DEVOPS_DE_ENVIRONMENT_READY:-}" = 1 ] &&
    [ -n "${PATH:-}" ]
}

# Switch the system loader to the scheduler that is tuned for interactive
# build and toolchain work. This is a best-effort side effect of entering the
# shell: scheduler availability must never prevent the shell itself from
# opening. All arguments are fixed, output is bounded and suppressed, and the
# postcondition is checked without retrying an uncertain mutation.
devops_de_select_scx_scheduler() {
  case "$#" in
    0) ;;
    *) return 64 ;;
  esac

  [ -x __INSTALLER_PATH_DIR_USR__/bin/scxctl ] && [ -x __INSTALLER_PATH_DIR_USR__/bin/timeout ] || {
    printf '%s\n' 'devops: scx_loader control client is unavailable' >&2
    return 69
  }

  devops_de_scx_state=$(
    __INSTALLER_PATH_DIR_USR__/bin/timeout --signal=TERM --kill-after=2s 10s \
      __INSTALLER_PATH_DIR_USR__/bin/scxctl get 2>__INSTALLER_PATH_DIR_DEV__/null
  ) || {
    printf '%s\n' 'devops: could not query scx_loader; continuing without scheduler handoff' >&2
    return 69
  }

  case "$devops_de_scx_state" in
    'no scx scheduler running')
      __INSTALLER_PATH_DIR_USR__/bin/timeout --signal=TERM --kill-after=2s 10s \
        __INSTALLER_PATH_DIR_USR__/bin/scxctl start --sched "$DEVOPS_DE_SCX_WORKER_PERFORMANCE" --mode auto \
        >__INSTALLER_PATH_DIR_DEV__/null 2>&1 || {
          printf 'devops: scx_loader could not start %s; continuing\n' "$DEVOPS_DE_SCX_WORKER_PERFORMANCE" >&2
          return 69
        }
      ;;
    'running '*)
      __INSTALLER_PATH_DIR_USR__/bin/timeout --signal=TERM --kill-after=2s 10s \
        __INSTALLER_PATH_DIR_USR__/bin/scxctl switch --sched "$DEVOPS_DE_SCX_WORKER_PERFORMANCE" --mode auto \
        >__INSTALLER_PATH_DIR_DEV__/null 2>&1 || {
          printf 'devops: scx_loader could not switch to %s; continuing\n' "$DEVOPS_DE_SCX_WORKER_PERFORMANCE" >&2
          return 69
        }
      ;;
    *)
      printf '%s\n' 'devops: scx_loader returned an unrecognized state; continuing' >&2
      return 69
      ;;
  esac

  # scxctl reports the loader state after its D-Bus request. A failed or stale
  # state is outcome-unknown, so do not retry and risk a second transition.
  devops_de_scx_state=$(
    __INSTALLER_PATH_DIR_USR__/bin/timeout --signal=TERM --kill-after=2s 10s \
      __INSTALLER_PATH_DIR_USR__/bin/scxctl get 2>__INSTALLER_PATH_DIR_DEV__/null
  ) || {
    printf '%s\n' 'devops: scx_loader handoff outcome is unknown; continuing' >&2
    return 69
  }
  case "$devops_de_scx_state" in
    "running "*)
      printf 'DevOps scheduler selected: %s\n' "$DEVOPS_DE_SCX_WORKER_PERFORMANCE"
      return 0
      ;;
    *)
      printf 'devops: scx_loader did not report a running scheduler after selecting %s; continuing\n' "$DEVOPS_DE_SCX_WORKER_PERFORMANCE" >&2
      return 69
      ;;
  esac
}

# Managed environment construction.
# This public shell helper deliberately rejects all arguments.
# shellcheck disable=SC2120
# The ordinary desktop and opt-in host shell use the same systemd-owned agent.
devops_de_apply_ssh_agent_environment() {
  [ "$#" -eq 0 ] || return 64
  SSH_AUTH_SOCK="${XDG_RUNTIME_DIR}/openssh_agent"
  export SSH_AUTH_SOCK
  unset SSH_AGENT_PID
  __INSTALLER_PATH_DIR_USR_LOCAL_BIN__/git-ssh unlock || return 1
  [ -S "$SSH_AUTH_SOCK" ] && [ ! -L "$SSH_AUTH_SOCK" ] || return 1
  [ "$(__INSTALLER_PATH_DIR_USR__/bin/find -P "$SSH_AUTH_SOCK" -maxdepth 0 -printf '%U:%m')" = "$(__INSTALLER_PATH_DIR_USR__/bin/id -u):600" ]
}

devops_de_apply_environment() {
  case "$#" in
    0) ;;
    *)
      printf '%s\n' 'devops: devops_de_apply_environment accepts no arguments' >&2
      return 64
      ;;
  esac
  devops_de_account_uid=$(__INSTALLER_PATH_DIR_USR__/bin/id -u) || return 1
  case "$devops_de_account_uid" in
    ''|0|*[!0-9]*)
      printf '%s\n' 'devops: compilation tools must run as a non-root desktop account' >&2
      return 1
      ;;
  esac
  devops_de_account_name=$(__INSTALLER_PATH_DIR_USR__/bin/id -un) || return 1
  devops_de_account_home=$(__INSTALLER_PATH_DIR_USR__/bin/getent passwd "$devops_de_account_uid" | __INSTALLER_PATH_DIR_USR__/bin/cut -d: -f6) || return 1
  [ "${USER:-}" = "$devops_de_account_name" ] && [ "${HOME:-}" = "$devops_de_account_home" ] || {
    printf '%s\n' 'devops: USER and HOME must match the current account' >&2
    return 1
  }
  case "${USER:-}" in
    ''|.|..|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.@-]*)
      printf '%s\n' 'devops: the current account name is unsafe for managed paths' >&2
      return 1
      ;;
  esac
  case "${HOME:-}" in
    /|//*)
      printf '%s\n' 'devops: HOME must not be the filesystem root' >&2
      return 1
      ;;
    /*) ;;
    *)
      printf '%s\n' 'devops: HOME must be an absolute path' >&2
      return 1
      ;;
  esac
  devops_de_validate_runtime_directory || return 1
  devops_de_apply_ssh_agent_environment || return 1

  PATH=__INSTALLER_PATH_DIR_USR_LOCAL_SBIN__:__INSTALLER_PATH_DIR_USR_LOCAL_BIN__:__INSTALLER_PATH_DIR_USR__/sbin:__INSTALLER_PATH_DIR_USR__/bin:/sbin:/bin
  export PATH
  unset \
    XDG_CONFIG_HOME \
    XDG_CACHE_HOME \
    XDG_DATA_HOME \
    XDG_STATE_HOME \
    DEVOPS_DE_ACTIVE \
    DEVOPS_DE_ENVIRONMENT_READY \
    DEVOPS_DE_COMPLETIONS_ENABLED \
    DEVOPS_DE_MISE_ENABLED \
    DEVOPS_DE_BAZELISK_ENABLED \
    CARGO_HOME \
    CARGO_TARGET_DIR \
    CARGO_INSTALL_ROOT \
    RUSTUP_HOME \
    RUSTUP_TOOLCHAIN \
    SCCACHE_DIR \
    RUSTC_WRAPPER \
    CMAKE_C_COMPILER_LAUNCHER \
    CMAKE_CXX_COMPILER_LAUNCHER \
    MISE_CONFIG_DIR \
    MISE_DATA_DIR \
    MISE_STATE_DIR \
    MISE_CACHE_DIR \
    MISE_TMP_DIR \
    NPM_CONFIG_CACHE \
    NPM_CONFIG_PREFIX \
    COREPACK_HOME \
    NODE_REPL_HISTORY \
    DENO_DIR \
    DENO_INSTALL_ROOT \
    DENO_REPL_HISTORY \
    DENO_NO_UPDATE_CHECK \
    PNPM_HOME \
    PNPM_CONFIG_STORE_DIR \
    PNPM_CONFIG_CACHE_DIR \
    PNPM_CONFIG_STATE_DIR \
    PNPM_CONFIG_GLOBAL_DIR \
    PNPM_CONFIG_GLOBAL_BIN_DIR \
    YARN_CACHE_FOLDER \
    YARN_GLOBAL_FOLDER \
    YARN_ENABLE_GLOBAL_CACHE \
    PYTHONDONTWRITEBYTECODE \
    PYTHONHASHSEED \
    PYTHONHOME \
    PYTHONINSPECT \
    PYTHONOPTIMIZE \
    PYTHONPATH \
    PYTHONPYCACHEPREFIX \
    PYTHONSTARTUP \
    PYTHONUSERBASE \
    PYTHON_HISTORY \
    PYTHONSAFEPATH \
    PYTHONUTF8 \
    PYTHONWARNINGS \
    PYTHONWARNDEFAULTENCODING \
    PIP_CACHE_DIR \
    PIP_DISABLE_PIP_VERSION_CHECK \
    UV_CACHE_DIR \
    UV_TOOL_DIR \
    UV_TOOL_BIN_DIR \
    VIRTUAL_ENV \
    VIRTUAL_ENV_PROMPT \
    GOPATH \
    GOROOT \
    GOBIN \
    GOMODCACHE \
    GOCACHE \
    GOENV \
    GOTMPDIR \
    GOTOOLCHAIN \
    ANSIBLE_HOME \
    ANSIBLE_GALAXY_CACHE_DIR \
    ANSIBLE_LOCAL_TEMP \
    ANSIBLE_NOCOWS \
    ANSIBLE_PERSISTENT_CONTROL_PATH_DIR \
    ANSIBLE_RETRY_FILES_ENABLED \
    ANSIBLE_SSH_CONTROL_PATH_DIR \
    CHECKPOINT_DISABLE \
    PACKER_CACHE_DIR \
    PACKER_CONFIG \
    PACKER_CONFIG_DIR \
    PACKER_CONFIG_PATH \
    PACKER_GETTER_READ_TIMEOUT \
    PACKER_PLUGIN_PATH \
    TF_PLUGIN_CACHE_DIR \
    TF_REGISTRY_CLIENT_TIMEOUT \
    TF_REGISTRY_DISCOVERY_RETRY \
    BAZELISK_HOME \
    CODEX_AGENTS \
    CODEX_HOME \
    CODEX_LOG_DIR \
    CODEX_SKILLS \
    CODEX_SQLITE_HOME \
    GITBUILD_WORKSPACE \
    GITBUILD_CACHE_HOME \
    GITBUILD_STATE_HOME \
    GITBUILD_DISTRIBUTION \
    DEVOPS_DATABASE_HOME \
    PGDATA \
    PGSERVICEFILE \
    PGPASSFILE \
    PSQL_HISTORY \
    MYSQL_HOME \
    MYSQL_HISTFILE \
    MYSQLSH_USER_CONFIG_HOME \
    SQLITE_HISTORY \
    DUCKDB_HISTORY \
    REDISCLI_HISTFILE \
    USQL_CONFIG_FILE \
    QOREDB_CONFIG_DIR

  devops_de_pool_root=__INSTALLER_PATH_DIR_POOL__
  devops_de_build_home="${devops_de_pool_root}/build/${USER}"
  devops_de_cache_home="${devops_de_pool_root}/cache/${USER}"
  devops_de_db_home="${devops_de_pool_root}/db/${USER}"
  XDG_CONFIG_HOME="${HOME}/.config"
  XDG_CACHE_HOME="${HOME}/.cache"
  XDG_DATA_HOME="${HOME}/.local/share"
  XDG_STATE_HOME="${HOME}/.local/state"
  export XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME
  devops_de_xdg_config_home=$XDG_CONFIG_HOME

  # gitbuild intentionally does not inherit arbitrary project/toolchain hooks.
  # Its private caches live alongside, not inside, credential-bearing state.
  export GITBUILD_WORKSPACE="${HOME}/Workspace"
  export GITBUILD_CACHE_HOME="${devops_de_cache_home}/gitbuild"
  export GITBUILD_STATE_HOME="${devops_de_db_home}/gitbuild"
  export GITBUILD_DISTRIBUTION=__INSTALLER_GITBUILD_DISTRIBUTION__

  for devops_de_account_root in \
    "$devops_de_build_home" \
    "$devops_de_cache_home" \
    "$devops_de_db_home"
  do
    devops_de_account_owned_directory_is_mode "$devops_de_account_root" 2770 || {
      printf 'devops: account work root must be a direct account-owned writable mode-2770 directory: %s\n' \
        "$devops_de_account_root" >&2
      return 1
    }
  done
  devops_de_ensure_private_runtime_directory "${devops_de_build_home}/tmp" || return 1
  export TMPDIR="${devops_de_build_home}/tmp"
  for devops_de_private_database_dir in \
    "$devops_de_db_home/postgresql" \
    "$devops_de_db_home/postgresql/data" \
    "$devops_de_db_home/mysql" \
    "$devops_de_db_home/mysql/config" \
    "$devops_de_db_home/mysql-shell" \
    "$devops_de_db_home/sqlite" \
    "$devops_de_db_home/duckdb" \
    "$devops_de_db_home/redis-compatible" \
    "$devops_de_db_home/usql" \
    "$devops_de_db_home/qoredb" \
    "$devops_de_db_home/qoredb/config"
  do
    devops_de_ensure_private_runtime_directory "$devops_de_private_database_dir" || {
      printf 'devops: cannot create or validate private database directory: %s\n' \
        "$devops_de_private_database_dir" >&2
      return 1
    }
  done

  # Native database-client selectors keep histories, credentials, service
  # definitions, and database state below the account-scoped /pool root.
  export DEVOPS_DATABASE_HOME="$devops_de_db_home"
  export PGDATA="$devops_de_db_home/postgresql/data"
  export PGSERVICEFILE="$devops_de_db_home/postgresql/pg_service.conf"
  export PGPASSFILE="$devops_de_db_home/postgresql/pgpass"
  export PSQL_HISTORY="$devops_de_db_home/postgresql/psql_history"
  export MYSQL_HOME="$devops_de_db_home/mysql/config"
  export MYSQL_HISTFILE="$devops_de_db_home/mysql/history"
  export MYSQLSH_USER_CONFIG_HOME="$devops_de_db_home/mysql-shell"
  export SQLITE_HISTORY="$devops_de_db_home/sqlite/history"
  export DUCKDB_HISTORY="$devops_de_db_home/duckdb/history"
  export REDISCLI_HISTFILE="$devops_de_db_home/redis-compatible/history"
  export QOREDB_CONFIG_DIR="$devops_de_db_home/qoredb/config"
  # usql consumes --config rather than a native environment selector.
  export USQL_CONFIG_FILE="$devops_de_db_home/usql/config.yaml"

  # Keep Python bytecode ephemeral and isolated below the validated account
  # runtime directory. Persistent interpreter history, user installs, pip
  # downloads, and uv state remain on the account-scoped /pool roots. Clear
  # inherited Python and virtual-environment selectors above before rebuilding
  # this deterministic environment.
  devops_de_python_runtime_root="${XDG_RUNTIME_DIR}/python"
  for devops_de_private_runtime_dir in \
    "$devops_de_python_runtime_root" \
    "$devops_de_python_runtime_root/pycache"
  do
    devops_de_ensure_private_runtime_directory "$devops_de_private_runtime_dir" || {
      printf 'devops: cannot create or validate private Python runtime directory: %s\n' \
        "$devops_de_private_runtime_dir" >&2
      return 1
    }
  done

  export PYTHONPYCACHEPREFIX="${devops_de_python_runtime_root}/pycache"
  export PYTHONUSERBASE="${devops_de_build_home}/python"
  export PYTHON_HISTORY="${devops_de_db_home}/python/history"
  export PYTHONSAFEPATH=1
  export PYTHONUTF8=1
  export PYTHONWARNDEFAULTENCODING=1
  export PIP_CACHE_DIR="${devops_de_cache_home}/pip"
  export PIP_DISABLE_PIP_VERSION_CHECK=1
  export UV_CACHE_DIR="${devops_de_cache_home}/uv"
  export UV_TOOL_DIR="${devops_de_db_home}/uv/tools"
  export UV_TOOL_BIN_DIR="${devops_de_build_home}/uv/bin"
  devops_de_prepend_path "${PYTHONUSERBASE}/bin" || return 1
  devops_de_prepend_path "${UV_TOOL_BIN_DIR}" || return 1

  # Keep Ansible local temporary files and persistent control sockets inside
  # the authenticated account's private runtime directory. Persistent Ansible
  # state and Galaxy downloads use their account-scoped /pool roots.
  devops_de_ansible_runtime_root="${XDG_RUNTIME_DIR}/ansible"
  for devops_de_private_runtime_dir in \
    "$devops_de_ansible_runtime_root" \
    "$devops_de_ansible_runtime_root/tmp" \
    "$devops_de_ansible_runtime_root/pc" \
    "$devops_de_ansible_runtime_root/ssh"
  do
    devops_de_ensure_private_runtime_directory "$devops_de_private_runtime_dir" || {
      printf '%s\n' 'devops: cannot create or validate a private Ansible runtime directory' >&2
      return 1
    }
  done
  export ANSIBLE_HOME="${devops_de_db_home}/ansible"
  export ANSIBLE_GALAXY_CACHE_DIR="${devops_de_cache_home}/ansible/galaxy"
  export ANSIBLE_LOCAL_TEMP="${devops_de_ansible_runtime_root}__INSTALLER_PATH_DIR_TMP__"
  export ANSIBLE_PERSISTENT_CONTROL_PATH_DIR="${devops_de_ansible_runtime_root}/pc"
  export ANSIBLE_SSH_CONTROL_PATH_DIR="${devops_de_ansible_runtime_root}/ssh"
  export ANSIBLE_NOCOWS=1
  export ANSIBLE_RETRY_FILES_ENABLED=0

  # HashiCorp release binaries remain isolated from ordinary terminals. Packer
  # uses PACKER_CONFIG; PACKER_CONFIG_PATH is a managed path alias retained for
  # operator scripts because upstream does not consume that name directly.
  devops_de_hashicorp_cache_root="${devops_de_cache_home}/hashicorp"
  export CHECKPOINT_DISABLE=1
  export TF_PLUGIN_CACHE_DIR="${devops_de_hashicorp_cache_root}/terraform/plugin-cache"
  export TF_REGISTRY_CLIENT_TIMEOUT=30
  export TF_REGISTRY_DISCOVERY_RETRY=3
  export PACKER_CACHE_DIR="${devops_de_hashicorp_cache_root}/packer/cache"
  export PACKER_CONFIG_DIR="${devops_de_hashicorp_cache_root}/packer.d"
  export PACKER_CONFIG_PATH="${PACKER_CONFIG_DIR}/config.json"
  export PACKER_CONFIG="$PACKER_CONFIG_PATH"
  export PACKER_PLUGIN_PATH="${PACKER_CONFIG_DIR}/plugins"
  export PACKER_GETTER_READ_TIMEOUT=30m

  # Keep Go workspaces and downloaded modules on the account-scoped /pool
  # roots. Managed publication wrappers are prepended below and therefore
  # cannot be shadowed by a binary installed into GOPATH/bin.
  export GOPATH="${devops_de_build_home}/go"
  export GOBIN="${GOPATH}/bin"
  export GOMODCACHE="${devops_de_cache_home}/go-mod"
  export GOCACHE="${devops_de_cache_home}/go-build"
  export GOENV="${devops_de_db_home}/go/env"
  export GOTMPDIR="${devops_de_build_home}/go/tmp"
  # Use Debian's system toolchain; module directives cannot download another compiler.
  export GOTOOLCHAIN=local
  devops_de_prepend_path "${GOPATH}/bin" || return 1

  # Expose only the class-gated publication command entrypoints.
  if [ -d __INSTALLER_PATH_DIR_USR_LOCAL_LIBEXEC__/obs-publishing-bin ]; then
    devops_de_prepend_path __INSTALLER_PATH_DIR_USR_LOCAL_LIBEXEC__/obs-publishing-bin || return 1
  fi
  if [ -d __INSTALLER_PATH_DIR_USR_LOCAL_LIBEXEC__/aptly-publishing-bin ]; then
    devops_de_prepend_path __INSTALLER_PATH_DIR_USR_LOCAL_LIBEXEC__/aptly-publishing-bin || return 1
  fi

  # Keep the isolated upstream tool roots visible only in the opt-in DevOps
  # shell. Aptly and osc remain behind their prepended credential-aware
  # publication wrappers, while their direct binaries stay available by path.
  if [ -d __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/opentufo/bin ]; then
    devops_de_append_path __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/opentufo/bin || return 1
  fi
  if [ -d __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/ansible/bin ]; then
    devops_de_append_path __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/ansible/bin || return 1
  fi
  if [ -x __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/deno/bin/deno ]; then
    export DENO_DIR="${devops_de_cache_home}/deno"
    export DENO_INSTALL_ROOT="${devops_de_build_home}/deno"
    export DENO_REPL_HISTORY="${devops_de_db_home}/deno/repl_history"
    export DENO_NO_UPDATE_CHECK=1
    devops_de_append_path __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/deno/bin || return 1
    devops_de_append_path "${DENO_INSTALL_ROOT}/bin" || return 1
  fi
  if [ -x __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/yt-dlp/bin/yt-dlp ]; then
    # The checksum-pinned official standalone payload bundles yt-dlp-ejs; its
    # wrapper binds that component to the managed Deno runtime and system ffmpeg.
    devops_de_append_path __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/yt-dlp/bin || return 1
  fi
  if [ -d __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/hashicorp/terraform/bin ]; then
    devops_de_append_path __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/hashicorp/terraform/bin || return 1
  fi
  if [ -d __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/hashicorp/packer/bin ]; then
    devops_de_append_path __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/hashicorp/packer/bin || return 1
  fi
  if [ -d __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/wrangler/node_modules/.bin ]; then
    devops_de_append_path __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/wrangler/node_modules/.bin || return 1
  fi
  if [ -d __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/aptly/bin ]; then
    devops_de_append_path __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/aptly/bin || return 1
  fi
  if [ -d __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/osc/bin ]; then
    devops_de_append_path __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/osc/bin || return 1
  fi
  if [ -d __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/obs-build/bin ]; then
    devops_de_append_path __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/obs-build/bin || return 1
  fi

  if [ -x __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/rustup/bin/rustup-init ]; then
    export CARGO_HOME="${devops_de_cache_home}/cargo"
    export CARGO_TARGET_DIR="${devops_de_build_home}/cargo/target"
    export CARGO_INSTALL_ROOT="${devops_de_build_home}/cargo/install"
    export RUSTUP_HOME="${devops_de_db_home}/rustup"
    RUSTUP_TOOLCHAIN=nightly
    export RUSTUP_TOOLCHAIN
    devops_de_prepend_path "${CARGO_HOME}/bin" || return 1
    devops_de_prepend_path "${CARGO_INSTALL_ROOT}/bin" || return 1
    devops_de_prepend_path __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/rustup/bin || return 1
  fi

  if command -v sccache >__INSTALLER_PATH_DIR_DEV__/null 2>&1; then
    export SCCACHE_DIR="${devops_de_cache_home}/sccache"
    export RUSTC_WRAPPER=sccache
    export CMAKE_C_COMPILER_LAUNCHER=sccache
    export CMAKE_CXX_COMPILER_LAUNCHER=sccache
  fi

  if [ -x __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/node-26/bin/node ]; then
    # Keep Node 26 ahead of any distribution Node binary as the fallback.
    # Mise's standard shim directory is prepended below and therefore wins
    # whenever the user selects a project or shell-specific Node version.
    devops_de_prepend_path __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/node-26/bin || return 1
  fi

  if command -v mise >__INSTALLER_PATH_DIR_DEV__/null 2>&1; then
    export MISE_CONFIG_DIR="${devops_de_xdg_config_home}/mise"
    export MISE_DATA_DIR="${devops_de_db_home}/mise/data"
    export MISE_STATE_DIR="${devops_de_db_home}/mise/state"
    export MISE_CACHE_DIR="${devops_de_cache_home}/mise"
    export MISE_TMP_DIR="${devops_de_cache_home}/mise/tmp"

    export NPM_CONFIG_CACHE="${devops_de_cache_home}/npm"
    export NPM_CONFIG_PREFIX="${devops_de_build_home}/npm-global"
    export COREPACK_HOME="${devops_de_cache_home}/corepack"
    export NODE_REPL_HISTORY="${devops_de_db_home}/node/repl_history"
    export PNPM_HOME="${devops_de_build_home}/pnpm"
    export PNPM_CONFIG_STORE_DIR="${devops_de_cache_home}/pnpm/store"
    export PNPM_CONFIG_CACHE_DIR="${devops_de_cache_home}/pnpm/cache"
    export PNPM_CONFIG_STATE_DIR="${devops_de_db_home}/pnpm/state"
    export PNPM_CONFIG_GLOBAL_DIR="${PNPM_HOME}/global"
    export PNPM_CONFIG_GLOBAL_BIN_DIR="${PNPM_HOME}/bin"
    export YARN_CACHE_FOLDER="${devops_de_cache_home}/yarn"
    export YARN_GLOBAL_FOLDER="${devops_de_build_home}/yarn-global"
    export YARN_ENABLE_GLOBAL_CACHE=false
    # This marker is intentionally exported to the exec'ed child shell.
    # shellcheck disable=SC2030
    DEVOPS_DE_MISE_ENABLED=1
    export DEVOPS_DE_MISE_ENABLED
    devops_de_prepend_path "${NPM_CONFIG_PREFIX}/bin" || return 1
    devops_de_prepend_path "${PNPM_HOME}/bin" || return 1
    devops_de_prepend_path "${YARN_GLOBAL_FOLDER}/bin" || return 1
    devops_de_prepend_path "${MISE_DATA_DIR}/shims" || return 1
  fi

  # Keep every packaged LLVM toolchain available. Iterate oldest first so the
  # newest installed toolchain is first in PATH after each prepend.
  for devops_de_llvm_version in 21 22 24; do
    if [ -x "__INSTALLER_PATH_DIR_USR__/lib/llvm-${devops_de_llvm_version}/bin/clang" ] &&
       [ -x "__INSTALLER_PATH_DIR_USR__/lib/llvm-${devops_de_llvm_version}/bin/clang++" ] &&
       [ -x "__INSTALLER_PATH_DIR_USR__/lib/llvm-${devops_de_llvm_version}/bin/llvm-config" ] &&
       [ -x "__INSTALLER_PATH_DIR_USR__/lib/llvm-${devops_de_llvm_version}/bin/lld" ] &&
       [ -x "__INSTALLER_PATH_DIR_USR__/lib/llvm-${devops_de_llvm_version}/bin/ld.lld" ]; then
      devops_de_prepend_path "__INSTALLER_PATH_DIR_USR__/lib/llvm-${devops_de_llvm_version}/bin" || return 1
    fi
  done
  unset devops_de_llvm_version

  # The CUDA classes install versioned toolkits below __INSTALLER_PATH_DIR_USR__/local. Add only
  # installed toolkit paths, oldest first, because each successful prepend
  # moves the newer toolkit ahead of the older one in the final PATH.
  if [ -d __INSTALLER_PATH_DIR_USR_LOCAL__/cuda-12.8/bin ]; then
    devops_de_prepend_path __INSTALLER_PATH_DIR_USR_LOCAL__/cuda-12.8/bin || return 1
  fi
  if [ -d __INSTALLER_PATH_DIR_USR_LOCAL__/cuda-12.9/bin ]; then
    devops_de_prepend_path __INSTALLER_PATH_DIR_USR_LOCAL__/cuda-12.9/bin || return 1
  fi
  if [ -d __INSTALLER_PATH_DIR_USR_LOCAL__/cuda-13.1/bin ]; then
    devops_de_prepend_path __INSTALLER_PATH_DIR_USR_LOCAL__/cuda-13.1/bin || return 1
  fi

  if [ -x __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/bazelisk/bazel ]; then
    export BAZELISK_HOME="${devops_de_db_home}/bazelisk"
    # This marker is intentionally exported to the exec'ed child shell.
    # shellcheck disable=SC2030
    DEVOPS_DE_BAZELISK_ENABLED=1
    export DEVOPS_DE_BAZELISK_ENABLED
  fi

  export CODEX_AGENTS="__INSTALLER_PATH_DIR_DATA__/codex/usr/agents"
  export CODEX_HOME="__INSTALLER_PATH_DIR_DATA__/codex/usr/home"
  export CODEX_LOG_DIR="__INSTALLER_PATH_DIR_DATA__/codex/log"
  export CODEX_SKILLS="__INSTALLER_PATH_DIR_DATA__/codex/usr/skills"
  export CODEX_SQLITE_HOME="__INSTALLER_PATH_DIR_DATA__/codex/sqlite"
  # Keep only the sandboxing wrapper on the host PATH. The wrapper injects the
  # checksum-pinned release directory into the confined Codex runtime PATH.
  devops_de_append_path __INSTALLER_PATH_DIR_DATA__/codex/lib || return 1

  if [ -x __INSTALLER_PATH_DIR_DATA__/llama/lib/llama ]; then
    devops_de_append_path __INSTALLER_PATH_DIR_DATA__/llama/lib || return 1
  fi
  if [ -d __INSTALLER_PATH_DIR_DATA__/llama/bin ]; then
    devops_de_append_path __INSTALLER_PATH_DIR_DATA__/llama/bin || return 1
  fi

  # Mark the environment active only after every managed variable and PATH
  # entry has been constructed successfully. Codex uses the ready marker to
  # preserve this exact interactive DevOps environment instead of rebuilding
  # and overwriting it in its wrapper process.
  DEVOPS_DE_ACTIVE=1
  DEVOPS_DE_ENVIRONMENT_READY=1
  export DEVOPS_DE_ACTIVE DEVOPS_DE_ENVIRONMENT_READY PATH
  unset \
    devops_de_pool_root \
    devops_de_account_uid \
    devops_de_account_name \
    devops_de_account_home \
    devops_de_build_home \
    devops_de_cache_home \
    devops_de_db_home \
    devops_de_account_root \
    devops_de_ansible_runtime_root \
    devops_de_hashicorp_cache_root \
    devops_de_private_database_dir \
    devops_de_private_runtime_dir \
    devops_de_python_runtime_root \
    devops_de_xdg_config_home
  return 0
}

# Same-terminal nested-shell activation.
devops_de_activate() (
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    printf '%s\n' 'devops: an interactive terminal is required' >&2
    return 1
  fi

  # This function executes in a subshell. Environment construction and the
  # nested interactive shell therefore cannot modify the ordinary caller.
  devops_de_apply_environment || return 1

  case "${SHELL:-}" in
    /bin/bash|__INSTALLER_PATH_DIR_USR__/bin/bash|/bin/zsh|__INSTALLER_PATH_DIR_USR__/bin/zsh)
      devops_de_shell=$SHELL
      ;;
    *)
      devops_de_shell=/bin/bash
      ;;
  esac
  if [ ! -x "$devops_de_shell" ]; then
    printf '%s\n' 'devops: no supported interactive shell is available' >&2
    return 1
  fi

  # Revalidate immediately before entering the nested shell so a malformed or
  # replaced runtime directory cannot be used after environment construction.
  devops_de_validate_runtime_directory || return 1
  devops_de_apply_ssh_agent_environment || return 1

  # Foot, Kitty, and xterm-compatible fallbacks implement the xterm title
  # stack. Restore the caller's exact title when the nested shell ends instead
  # of guessing an ordinary-shell title.
  devops_de_title_pushed=0
  devops_de_restore_terminal_title_once() {
    case "${devops_de_title_pushed:-0}" in
      1)
        devops_de_title_pushed=0
        devops_de_restore_terminal_title
        ;;
      *) return 0 ;;
    esac
  }
  trap 'devops_de_restore_terminal_title_once' 0

  devops_de_push_terminal_title || return 1
  devops_de_title_pushed=1
  devops_de_set_terminal_title || return 1
  if ! devops_de_select_scx_scheduler; then
    printf '%s\n' 'DevOps scheduler handoff unavailable; the shell remains usable' >&2
  fi
  printf '%s\n' 'Entering DevOps environment; run devops or exit to return'

  # Foreground call: the helper watches this activation SUBSHELL's real PID.
  # Each terminal gets its own pidfd-backed lease; the nested shell is unchanged.
  if [ -x __INSTALLER_PATH_DIR_USR_LOCAL_BIN__/labwc-hardware-tuning ]; then
    __INSTALLER_PATH_DIR_USR_LOCAL_BIN__/labwc-hardware-tuning devops-start ||
      printf '%s\n' 'DevOps tuning sidecar unavailable; continuing without hardware tuning' >&2
  fi
  __INSTALLER_PATH_DIR_USR_LOCAL_BIN__/labwc-build "$devops_de_shell" -i
  devops_de_shell_status=$?
  devops_de_restore_terminal_title_once || {
    [ "$devops_de_shell_status" -ne 0 ] || devops_de_shell_status=1
  }
  trap - 0
  return "$devops_de_shell_status"
)

# Public interactive command.
devops() {
  case "$#" in
    0) ;;
    *)
      printf '%s\n' 'usage: devops' >&2
      return 64
      ;;
  esac

  # The active marker is inherited only by the nested shell started above.
  # shellcheck disable=SC2031
  case "${DEVOPS_DE_ACTIVE:-}" in
    1) devops_de_deactivate ;;
    '') devops_de_activate ;;
    *)
      printf '%s\n' 'devops: invalid DevOps activation marker' >&2
      return 1
      ;;
  esac
}

# Active-shell command shims.
# Ordinary interactive invocations also enter the shared build slice. Once
# inside it, child compilers inherit that ownership without extra scopes.
# Aliases preserve c++/clang++ names without non-POSIX function identifiers.
case $- in
  *i*)
    alias make='__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/labwc-build make'
    alias gmake='__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/labwc-build gmake'
    alias ninja='__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/labwc-build ninja'
    alias cmake='__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/labwc-build cmake'
    alias meson='__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/labwc-build meson'
    alias cargo='__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/labwc-build cargo'
    alias rustc='__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/labwc-build rustc'
    alias cc='__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/labwc-build cc'
    alias c++='__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/labwc-build c++'
    alias gcc='__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/labwc-build gcc'
    alias g++='__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/labwc-build g++'
    alias clang='__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/labwc-build clang'
    alias clang++='__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/labwc-build clang++'
    alias go='__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/labwc-build go'
    alias zig='__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/labwc-build zig'
    alias javac='__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/labwc-build javac'
    alias dotnet='__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/labwc-build dotnet'
    ;;
esac
# The marker comes from the parent process that execs this interactive shell.
# shellcheck disable=SC2031
case "${DEVOPS_DE_BAZELISK_ENABLED:-}" in
  1)
    bazel() {
      __INSTALLER_PATH_DIR_USR_LOCAL_BIN__/labwc-build __INSTALLER_PATH_DIR_USR_LOCAL_LIB__/bazelisk/bazel \
        "--bazelrc=${XDG_CONFIG_HOME:-${HOME}/.config}/bazel/bazelrc" \
        "$@"
    }
    ;;
esac

devops_de_enable_zsh_terminal_title

# Managed Podman/Docker is available in ordinary terminals as well as the
# opt-in DevOps shell. These are CLIENT settings, not the devops user's daemon
# environment. Do not change HOME, USER, XDG_RUNTIME_DIR or the desktop D-Bus
# address to impersonate the service account.
podman_devops_apply_environment() {
  [ -r __INSTALLER_PATH_DIR_ETC__/podman-devops/client.conf ] &&
    [ -x __INSTALLER_PATH_DIR_USR_LOCAL_LIBEXEC__/podman-devops-client ] || return 0

  # Native Podman and Docker client selectors.
  CONTAINER_HOST=unix://__INSTALLER_PATH_DIR_RUN__/podman-devops/podman.sock
  DOCKER_HOST=$CONTAINER_HOST
  CONTAINERS_CONF=__INSTALLER_PATH_DIR_ETC__/podman-devops/client.conf
  PODMAN_COMPOSE_PROVIDER=__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/docker-compose
  # Podman's Docker-compatible API is not a Docker BuildKit/Swarm daemon.
  DOCKER_BUILDKIT=0
  COMPOSE_BAKE=false
  REGISTRY_AUTH_FILE=${REGISTRY_AUTH_FILE:-${XDG_CONFIG_HOME:-${HOME}/.config}/containers/auth.json}
  DOCKER_CONFIG=${DOCKER_CONFIG:-${XDG_CONFIG_HOME:-${HOME}/.config}/docker}
  unset CONTAINER_CONNECTION CONTAINER_SSHKEY CONTAINERS_CONF_OVERRIDE \
    CONTAINERS_CONF_MODULES CONTAINERS_STORAGE_CONF STORAGE_DRIVER STORAGE_OPTS \
    DOCKER_CONTEXT DOCKER_TLS_VERIFY DOCKER_CERT_PATH
  export CONTAINER_HOST DOCKER_HOST CONTAINERS_CONF PODMAN_COMPOSE_PROVIDER \
    DOCKER_BUILDKIT COMPOSE_BAKE REGISTRY_AUTH_FILE DOCKER_CONFIG

  # Discoverable paths below are managed metadata, NOT native Podman switches.
  PODMAN_SERVICE_USER=devops
  PODMAN_SERVICE_HOME=__INSTALLER_PATH_DIR_DATA__/accounts/devops
  PODMAN_SOCKET=__INSTALLER_PATH_DIR_RUN__/podman-devops/podman.sock
  PODMAN_POOL=__INSTALLER_PATH_DIR_POOL__/podman
  PODMAN_STORAGE_ROOT=__INSTALLER_PATH_DIR_POOL__/podman/storage
  PODMAN_VOLUME_ROOT=__INSTALLER_PATH_DIR_POOL__/podman/volumes
  PODMAN_NETWORK_ROOT=__INSTALLER_PATH_DIR_POOL__/podman/networks
  PODMAN_WORKSPACE=__INSTALLER_PATH_DIR_POOL__/podman/workspace
  PODMAN_SERVER_CONTAINERS_CONF=__INSTALLER_PATH_DIR_DATA__/accounts/devops/.config/containers/containers.conf
  PODMAN_SERVER_STORAGE_CONF=__INSTALLER_PATH_DIR_DATA__/accounts/devops/.config/containers/storage.conf
  PODMAN_SERVER_REGISTRIES_CONF=__INSTALLER_PATH_DIR_DATA__/accounts/devops/.config/containers/registries.conf
  PODMAN_QUADLET_ROOT=__INSTALLER_PATH_DIR_DATA__/accounts/devops/.config/containers/systemd
  export PODMAN_SERVICE_USER PODMAN_SERVICE_HOME PODMAN_SOCKET PODMAN_POOL \
    PODMAN_STORAGE_ROOT PODMAN_VOLUME_ROOT PODMAN_NETWORK_ROOT PODMAN_WORKSPACE \
    PODMAN_SERVER_CONTAINERS_CONF PODMAN_SERVER_STORAGE_CONF \
    PODMAN_SERVER_REGISTRIES_CONF PODMAN_QUADLET_ROOT

  # The daemon alone uses CONTAINERS_STORAGE_CONF and its private XDG runtime
  # runroot under __INSTALLER_PATH_DIR_RUN_USER__/<devops-uid>. Do not export that storage configuration
  # into a desktop client or alias buildah/unshare/mount to the remote API.
  alias podman='__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/podman'
  alias docker='__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/docker'
  alias docker-compose='__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/docker-compose'
  alias pps='__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/podman ps --all'
  alias pimages='__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/podman images'
  alias pvolumes='__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/podman volume ls'
  alias pnetworks='__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/podman network ls'
  alias pbuild='__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/podman build'
  alias plogs='__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/podman logs --follow'
  alias pstats='__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/podman stats'
  alias pcompose='__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/docker-compose'
  alias pinfo='__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/podman info'
  alias pcontainers='__INSTALLER_PATH_DIR_USR_LOCAL_BIN__/labwc-podman-menu'
}

podman_devops_apply_environment

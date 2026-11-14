# Interactive aliases for the managed desktop account.

if command -v fdfind >__INSTALLER_PATH_DIR_DEV__/null 2>&1 && ! command -v fd >__INSTALLER_PATH_DIR_DEV__/null 2>&1; then
  alias fd='fdfind'
fi

alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'
alias grep='grep --color=auto'
alias ip='ip --color=auto'
alias btop='btop --utf-force'
# Local capacity stays available while a hard-mounted NFS server is offline.
# Use __INSTALLER_PATH_DIR_USR__/bin/df explicitly when remote filesystem usage is wanted.
alias df='df --local'

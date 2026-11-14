# Bash only. Server roles do not load desktop, zsh, Starship or user services.
case $- in *i*) ;; *) return ;; esac
if [ "${SERVER_BASHRC_LOADED:-0}" = 1 ]; then return; fi
SERVER_BASHRC_LOADED=1
if [ "${SERVER_PROFILE_LOADED:-0}" != 1 ] && [ -f "$HOME/.profile" ] && [ ! -L "$HOME/.profile" ]; then
  . "$HOME/.profile"
fi
umask 077
HISTCONTROL=ignoredups:erasedups
HISTSIZE=1000
HISTFILESIZE=5000
shopt -s histappend checkwinsize
PS1='\u@\h:\w\$ '
if [ -f "$HOME/.bash_aliases" ] && [ ! -L "$HOME/.bash_aliases" ]; then
  . "$HOME/.bash_aliases"
fi

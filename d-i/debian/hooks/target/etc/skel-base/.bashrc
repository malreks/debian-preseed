# Interactive Bash only. Do not start services or load privileged helpers.
case $- in *i*) ;; *) return ;; esac
umask 077
HISTFILE="$HOME/.bash_history"
HISTCONTROL=ignoreboth:erasedups
HISTSIZE=1000
HISTFILESIZE=2000
shopt -s histappend checkwinsize
PS1='\u@\h:\w\$ '

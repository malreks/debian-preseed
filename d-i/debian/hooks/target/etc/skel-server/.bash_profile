# Bash login entrypoint; .profile remains the POSIX environment owner.
if [ -f "$HOME/.profile" ] && [ ! -L "$HOME/.profile" ]; then
  . "$HOME/.profile"
fi

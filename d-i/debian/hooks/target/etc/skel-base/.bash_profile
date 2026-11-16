# Bash login reads the account's minimal POSIX environment.
if [ -f "$HOME/.profile" ] && [ ! -L "$HOME/.profile" ]; then
  # shellcheck disable=SC1091
  . "$HOME/.profile"
fi

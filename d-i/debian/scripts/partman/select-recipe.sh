#!/bin/sh
set -eu

fatal() {
  select_recipe_message=$(printf '%s' "$*" | tr '\r\n\t' '   ')
  printf '[select-recipe] fatal: %s\n' "$select_recipe_message" >&2
  if [ -c /dev/tty4 ] && [ -w /dev/tty4 ]; then
    printf '[select-recipe] fatal: %s\n' "$select_recipe_message" >/dev/tty4 || :
  fi
  if [ -c /dev/console ] && [ -w /dev/console ]; then
    printf '[select-recipe] fatal: %s\n' "$select_recipe_message" >/dev/console || :
  fi
  if command -v logger >/dev/null 2>&1; then
    logger -t preseed-select-recipe "fatal: $select_recipe_message" 2>/dev/null || :
  fi
  exit 1
}

host_profile=${1:-}
case "$host_profile" in
  *-*)
    family=${host_profile%%-*}
    variant=${host_profile#*-}
    ;;
  *)
    fatal "unsupported host profile: ${host_profile}"
    ;;
esac

[ -n "$family" ] || fatal "host profile must include both family and variant: ${host_profile}"
[ -n "$variant" ] || fatal "host profile must include both family and variant: ${host_profile}"

case "$family" in
  *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-]*)
    fatal "host profile family contains unsupported characters: ${family}"
    ;;
esac
case "$variant" in
  *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-]*)
    fatal "host profile variant contains unsupported characters: ${variant}"
    ;;
esac

printf '%s-layout-%s\n' "$family" "$variant"

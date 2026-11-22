#!/bin/sh
# The supervisor is an independent shell; `if external-command` cannot disable
# errexit inside the child. Stock d-i must never receive a fatal hook status.
set -eu
runtime=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
. "$runtime/bootstrap/source.sh"
# Stock d-i maintainer scripts are invoked by basename (for example,
# partman-base.postinst contains only `partman`).  The supervised process is a
# new shell and cannot rely on the PATH of the main-menu process that launched
# it.  Load the installer-only path contract and publish the standard d-i
# search path before any component is executed.
[ -f "$runtime/bootstrap/di.env" ] && [ ! -L "$runtime/bootstrap/di.env" ] && [ -r "$runtime/bootstrap/di.env" ] || {
  INSTALLER_FAILURE_SOURCE=$runtime/bootstrap/di.env
  INSTALLER_FAILURE_LINE=path-contract
  INSTALLER_FAILURE_OPERATION=guard-hook-path
  export INSTALLER_FAILURE_SOURCE INSTALLER_FAILURE_LINE INSTALLER_FAILURE_OPERATION
  installer_lifecycle_abort 127 guard-hook-path 'installer path environment is unavailable for supervised d-i component'
}
# shellcheck disable=SC1090,SC1091
. "$runtime/bootstrap/di.env"
PATH="${DIR_INSTALLER_USR_LOCAL_SBIN}:${DIR_INSTALLER_USR_LOCAL_BIN}:${DIR_INSTALLER_USR_SBIN}:${DIR_INSTALLER_USR_BIN}:${DIR_INSTALLER_SBIN}:${DIR_INSTALLER_BIN}${PATH:+:${PATH}}"
export PATH
# d-i calls maintainer scripts after the preseed command has exited.  Restore
# the generated installer context before loading any guarded component so the
# suite, selected classes, profile and target selectors are available in this
# fresh shell.  Do not silently accept an indirect or malformed state file.
context="$runtime/state/context.env"
[ -f "$context" ] && [ ! -L "$context" ] && [ -r "$context" ] || {
  INSTALLER_FAILURE_SOURCE=$context
  INSTALLER_FAILURE_LINE=context-contract
  INSTALLER_FAILURE_OPERATION=guard-hook-context
  export INSTALLER_FAILURE_SOURCE INSTALLER_FAILURE_LINE INSTALLER_FAILURE_OPERATION
  installer_lifecycle_abort 125 guard-hook-context 'installer context is unavailable for supervised d-i component'
}
/bin/sh -n "$context" || {
  INSTALLER_FAILURE_SOURCE=$context
  INSTALLER_FAILURE_LINE=context-syntax
  INSTALLER_FAILURE_OPERATION=guard-hook-context
  export INSTALLER_FAILURE_SOURCE INSTALLER_FAILURE_LINE INSTALLER_FAILURE_OPERATION
  installer_lifecycle_abort 125 guard-hook-context 'installer context has invalid shell syntax'
}
# The guarded child is a separate process.  Context assignments are deliberately
# data-only and must be exported so bootstrap/common-lib and every d-i hook see
# the same suite, profile, class, and target identity as this supervisor shell.
set -a
# shellcheck disable=SC1090,SC1091
. "$context"
set +a
case "${INSTALLER_SUITE:-}" in
  forky|trixie) ;;
  *)
    INSTALLER_FAILURE_SOURCE=$context
    INSTALLER_FAILURE_LINE=suite-identity
    INSTALLER_FAILURE_OPERATION=guard-hook-context
    export INSTALLER_FAILURE_SOURCE INSTALLER_FAILURE_LINE INSTALLER_FAILURE_OPERATION
    installer_lifecycle_abort 125 guard-hook-context 'installer context has no supported suite identity'
    ;;
esac
# chroot-setup.sh uses this Debian Installer interface before target locales
# are generated. Keep stock component APT/debconf operations in the portable C
# locale without changing the selected installed-system language.
LANG=C
LC_ALL=C
IT_LANG_OVERRIDE=C
export LANG LC_ALL IT_LANG_OVERRIDE
id=$1
script=$2
shift 2
if installer_lifecycle_begin "$id"; then :; else
  rc=$?
  [ "$rc" -eq 10 ] || exit "$rc"
  case "$id" in
    hook-finish-99reboot|hook-component-finish-install.postinst)
      [ -f "$LC_STATE/installation.success" ] || installer_lifecycle_abort 125 "$id" 'missing final success record'
      trap - 0
      exit 11
      ;;
  esac
  exit 0
fi
[ -f "$script" ] && [ -x "$script" ] && [ ! -L "$script" ] ||
  installer_lifecycle_abort 125 "$id" 'missing or indirect supervised executable'
# The reboot sentinel follows successful selected stages and clean unmount.
if [ "$id" = hook-finish-99reboot ]; then
  for required in prepare-context apply early partman late hook-component-bootstrap-base.postinst hook-component-apt-setup-udeb.postinst hook-component-pkgsel.postinst hook-component-grub-installer.postinst; do
    [ -f "$LC_STATE/$required.done" ] || installer_lifecycle_abort 125 "$id" "missing completion: $required"
  done
  [ -s "$LC_STATE/finish-hooks.list" ] || installer_lifecycle_abort 125 "$id" 'finish hook inventory missing'
  while IFS= read -r name; do
    [ "$name" = 99reboot ] && continue
    [ -f "$LC_STATE/hook-finish-$name.done" ] || installer_lifecycle_abort 125 "$id" "finish hook not completed: $name"
  done <"$LC_STATE/finish-hooks.list"
  for hook in ${DIR_INSTALLER_FINISH_INSTALL_D}/*; do
    [ -x "$hook" ] || continue
    grep -Fqx "${hook##*/}" "$LC_STATE/finish-hooks.list" || installer_lifecycle_abort 125 "$id" 'finish hook inventory changed'
  done
fi
if installer_run_supervised "$script" "$@"; then rc=0; else rc=$?; fi
case "$id:$rc" in
  hook-finish-99reboot:11)
    installer_lifecycle_complete
    tmp=$(mktemp "$LC_STATE/.success.XXXXXX")
    printf 'state=SUCCESS\nconfigured=target\nfinish_hooks=complete\nunmount=complete\n' >"$tmp"
    chmod 0600 "$tmp"
    mv "$tmp" "$LC_STATE/installation.success"
    sync
    trap - 0
    exit 11
    ;;
  hook-component-finish-install.postinst:11)
    [ -f "$LC_STATE/installation.success" ] || installer_lifecycle_abort 125 "$id" 'finish-install requested exit without completed reboot handoff'
    installer_lifecycle_complete
    trap - 0
    exit 11
    ;;
  hook-finish-99reboot:0|hook-component-finish-install.postinst:0)
    installer_lifecycle_abort 125 "$id" 'missing d-i reboot sentinel status 11' ;;
  *:0) installer_lifecycle_complete ;;
  *)
    INSTALLER_FAILURE_SOURCE=$script
    INSTALLER_FAILURE_LINE=child
    INSTALLER_FAILURE_OPERATION=$id
    export INSTALLER_FAILURE_SOURCE INSTALLER_FAILURE_LINE INSTALLER_FAILURE_OPERATION
    installer_lifecycle_abort "$rc" "$id" "supervised hook failed: ${script} exited with status ${rc}; automatic re-entry is forbidden" ;;
esac

#!/bin/sh

case $- in
  *i*) ;;
  *) return 0 ;;
esac

[ "$(id -u 2>__INSTALLER_PATH_DIR_DEV__/null || printf '0')" -ne 0 ] || return 0
[ -t 0 ] && [ -t 1 ] || return 0
pending_file=__INSTALLER_PATH_FILE_CRYPTO_PENDING__
[ -r "$pending_file" ] || return 0
pending_user=$(cat "$pending_file")
[ -n "$pending_user" ] || return 0
[ "$(id -un 2>__INSTALLER_PATH_DIR_DEV__/null)" = "$pending_user" ] || return 0
[ -x __INSTALLER_PATH_DIR_USR_LOCAL_SBIN__/tpm2-enroll.sh ] || return 0
command -v sudo >__INSTALLER_PATH_DIR_DEV__/null 2>&1 || return 0

printf '%s\n' 'TPM2 disk enrollment is pending; recovery passphrase and PIN setup will start now.'
sudo __INSTALLER_PATH_DIR_USR_LOCAL_SBIN__/tpm2-enroll.sh

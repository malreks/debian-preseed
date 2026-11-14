#!/bin/sh
set -u

PATH=__INSTALLER_PATH_DIR_USR_LOCAL_SBIN__:__INSTALLER_PATH_DIR_USR_LOCAL_BIN__:__INSTALLER_PATH_DIR_USR_SBIN__:__INSTALLER_PATH_DIR_USR_BIN__:__INSTALLER_PATH_DIR_SBIN__:__INSTALLER_PATH_DIR_BIN__
export PATH
umask 077

FIRSTBOOT_LOG_DIR=${FIRSTBOOT_LOG_DIR:-__INSTALLER_PATH_DIR_FIRSTBOOT_LOG__}
FIRSTBOOT_DATA_DIR=${FIRSTBOOT_DATA_DIR:-${FIRSTBOOT_LOG_DIR}__INSTALLER_PATH_DIR_DATA__}
FIRSTBOOT_LOG_FILE=${FIRSTBOOT_LOG_FILE:-${FIRSTBOOT_LOG_DIR}/20-firstboot.log}

mkdir -p "$FIRSTBOOT_LOG_DIR" "$FIRSTBOOT_DATA_DIR" 2>__INSTALLER_PATH_DIR_DEV__/null || exit 1
: >>"$FIRSTBOOT_LOG_FILE" 2>__INSTALLER_PATH_DIR_DEV__/null || exit 1

timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ' 2>__INSTALLER_PATH_DIR_DEV__/null || printf '%s\n' unknown-time
}

log_line() {
  stage=$1
  level=$2
  component=$3
  shift 3
  printf '%s stage=%s level=%s component=%s %s\n' \
    "$(timestamp)" "$stage" "$level" "$component" "$*" >>"$FIRSTBOOT_LOG_FILE"
}

if [ -r __INSTALLER_PATH_DIR_FIRSTBOOT_LIB__/logging.sh ]; then
  # shellcheck disable=SC1091
  . __INSTALLER_PATH_DIR_FIRSTBOOT_LIB__/logging.sh
fi

capture() {
  output_name=$1
  shift
  output_file="${FIRSTBOOT_DATA_DIR}/${output_name}"
  {
    printf '# command:'
    for arg in "$@"; do
      printf ' %s' "$arg"
    done
    printf '\n'
    timeout --signal=TERM --kill-after=2s 20s "$@"
  } >"$output_file" 2>&1 || printf 'status=%s\n' "$?" >>"$output_file"
  chmod 0600 "$output_file" 2>__INSTALLER_PATH_DIR_DEV__/null || true
}

capture_file() {
  output_name=$1
  src=$2
  if [ -r "$src" ]; then
    cp "$src" "${FIRSTBOOT_DATA_DIR}/${output_name}" 2>__INSTALLER_PATH_DIR_DEV__/null || true
    chmod 0600 "${FIRSTBOOT_DATA_DIR}/${output_name}" 2>__INSTALLER_PATH_DIR_DEV__/null || true
  fi
}

capture_redacted_file() {
  output_name=$1
  src=$2
  output_file="${FIRSTBOOT_DATA_DIR}/${output_name}"

  if [ -r "$src" ]; then
    sed \
      -e 's/^\(MANAGED_NETWORK_WIFI_PSK=\).*/\1REDACTED/' \
      -e 's/^\(MANAGED_NETWORK_WIFI_WPA=\).*/\1REDACTED/' \
      -e 's/^\(MANAGED_NETWORK_WIFI_WEP=\).*/\1REDACTED/' \
      -e 's/^\(.*[Ww][Pp][Aa].*= \{0,1\}\).*/\1REDACTED/' \
      -e 's/^\([[:space:]]*[Ww][Pp][Aa]-[Pp][Ss][Kk][[:space:]][[:space:]]*\).*/\1REDACTED/' \
      "$src" >"$output_file" 2>__INSTALLER_PATH_DIR_DEV__/null || true
    chmod 0600 "$output_file" 2>__INSTALLER_PATH_DIR_DEV__/null || true
  fi
}

capture_networkctl_status() {
  # Do not report an absent backend as broken networking. A failed or expected
  # enabled backend still gets its original diagnostic, including exit status.
  networkd_state=$(timeout --kill-after=1s 3s systemctl show --property=ActiveState --value systemd-networkd.service 2>__INSTALLER_PATH_DIR_DEV__/null || true)
  networkd_enabled=$(timeout --kill-after=1s 3s systemctl is-enabled systemd-networkd.service 2>__INSTALLER_PATH_DIR_DEV__/null || true)
  case "${networkd_state}:${networkd_enabled}" in
    inactive:disabled|inactive:masked)
      capture networkctl-status.txt __INSTALLER_PATH_DIR_USR_BIN__/printf '%s\n' 'NOT_APPLICABLE: systemd-networkd is inactive and disabled/masked; see network-targets.txt for the installed network services.'
      ;;
    *) capture networkctl-status.txt networkctl status --no-pager ;;
  esac
}

if command -v hostnamectl >__INSTALLER_PATH_DIR_DEV__/null 2>&1; then
  capture hostnamectl.txt hostnamectl
else
  hostname >"${FIRSTBOOT_DATA_DIR}/hostname.txt" 2>&1 || true
  chmod 0600 "${FIRSTBOOT_DATA_DIR}/hostname.txt" 2>__INSTALLER_PATH_DIR_DEV__/null || true
fi

if command -v ip >__INSTALLER_PATH_DIR_DEV__/null 2>&1; then
  capture ip-brief-address.txt ip -brief addr
  capture ip-address.txt ip addr
  capture ip-route.txt ip route
  capture ip-rule.txt ip rule
fi
if command -v resolvectl >__INSTALLER_PATH_DIR_DEV__/null 2>&1; then
  capture resolvectl-status.txt resolvectl status
fi
if command -v networkctl >__INSTALLER_PATH_DIR_DEV__/null 2>&1; then
  capture networkctl-list.txt networkctl list --no-pager
  capture_networkctl_status
fi
if command -v ss >__INSTALLER_PATH_DIR_DEV__/null 2>&1; then
  # Socket ownership (-p) walks unrelated desktop processes and requires
  # cross-profile ptrace reads; the network inventory needs only endpoints.
  capture sockets-listening.txt ss -ltnu
fi
if command -v systemctl >__INSTALLER_PATH_DIR_DEV__/null 2>&1; then
  capture network-targets.txt systemctl status network-online.target networking.service network.service wpa_supplicant.service systemd-networkd.service NetworkManager.service NetworkManager-dispatcher.service --no-pager --lines=40
fi
capture_file resolv.conf.txt __INSTALLER_PATH_DIR_ETC__/resolv.conf
capture_file network-interfaces.txt __INSTALLER_PATH_FILE_NETWORK_INTERFACES__
capture_redacted_file network-network.txt __INSTALLER_PATH_FILE_MANAGED_NETWORK_INTERFACES__
capture_redacted_file network-network-default.txt __INSTALLER_PATH_FILE_MANAGED_NETWORK_DEFAULT__

log_line network-online info network "network_collection_complete=true"
exit 0

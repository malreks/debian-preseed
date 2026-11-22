#!/bin/sh
set -eu

target_root=${1:-${TARGET_ROOT}}
[ -d "$target_root" ] || { printf 'fatal: missing CrowdSec target root\n' >&2; exit 1; }

crowdsec_fatal() {
  crowdsec_message=$(printf '%s' "$*" | tr '\r\n\t' '   ')
  if command -v installer_error >/dev/null 2>&1; then
    installer_error "CrowdSec: ${crowdsec_message}"
  else
    printf 'fatal: %s\n' "$crowdsec_message" >&2
    if [ -c /dev/tty4 ] && [ -w /dev/tty4 ]; then
      printf '[late:crowdsec] fatal: %s\n' "$crowdsec_message" >/dev/tty4 || :
    fi
    if command -v logger >/dev/null 2>&1; then
      logger -t preseed-crowdsec "fatal: $crowdsec_message" 2>/dev/null || :
    fi
  fi
  exit 1
}

crowdsec_info() {
  printf '[late:crowdsec] %s\n' "$*" >&2
}

crowdsec_validate_abs_target_path() {
  case "${1:-}" in
    /*) ;;
    *) crowdsec_fatal "target path must be absolute: ${1:-unset}" ;;
  esac
  case "$1" in *'/../'*|*'/./'*|*/..|*/.) crowdsec_fatal "unsafe target path" ;; esac
  installer_apt_safe_path "${target_root}${1}" || crowdsec_fatal "unsafe target path ownership or link"
}

crowdsec_normalize_token() {
  crowdsec_token_value=$1

  case "$crowdsec_token_value" in
    \"*\")
      crowdsec_token_value=${crowdsec_token_value#\"}
      crowdsec_token_value=${crowdsec_token_value%\"}
      ;;
    \'*\')
      crowdsec_token_value=${crowdsec_token_value#\'}
      crowdsec_token_value=${crowdsec_token_value%\'}
      ;;
  esac

  [ -n "$crowdsec_token_value" ] || crowdsec_fatal "crowdsec token must not be empty"
  case "$crowdsec_token_value" in
    *[![:print:]]*|*[[:space:]]*)
      crowdsec_fatal "crowdsec token must be a single printable token without whitespace"
      ;;
  esac
  printf '%s\n' "$crowdsec_token_value"
}

crowdsec_cmdline_token() {
  crowdsec_token=
  for crowdsec_token_key in crowdsec_token crowdsec_enroll_token crowdsec_attachment_key; do
    crowdsec_token=$(installer_cmdline_value "$crowdsec_token_key" 2>__INSTALLER_PATH_DIR_DEV__/null || true)
    [ -n "$crowdsec_token" ] && break
  done
  [ -n "$crowdsec_token" ] || return 1
  crowdsec_token=$(crowdsec_normalize_token "$crowdsec_token") || return 2
  [ "${#crowdsec_token}" -le 512 ] || return 2
  printf '%s\n' "$crowdsec_token"
}

crowdsec_stage_target_asset() {
  repo_path=$1
  target_path=$2
  mode=$3
  shift 3
  asset_renderer=installer_apply_scalar_placeholders
  if [ "${1:-}" = --environment ]; then
    asset_renderer=installer_apply_systemd_environment_placeholders
    shift
  fi
  target_host_path="${target_root}${target_path}"
  crowdsec_validate_abs_target_path "$target_path"
  target_normalize_systemd_config_parent_modes "$target_path" "$target_root"
  [ -d "${target_host_path%/*}" ] || install -d -m 0755 "${target_host_path%/*}"
  tmp_asset=$(mktemp "${target_host_path%/*}/.crowdsec-asset.XXXXXX") || return $?
  if bootstrap_fetch_seed_file "$seed_base" "$repo_path" "$tmp_asset" 0600 "crowdsec asset ${repo_path}"; then
    tmp_paths_rendered="${tmp_asset}.paths"
    installer_apply_scalar_placeholders "$tmp_asset" "$tmp_paths_rendered" || return $?
    mv -f "$tmp_paths_rendered" "$tmp_asset" || return $?
    if [ "$#" -gt 0 ]; then
      "$asset_renderer" "$tmp_asset" "${tmp_asset}.rendered" "$@" || return $?
      mv -f "${tmp_asset}.rendered" "$tmp_asset" || return $?
    fi
    if LC_ALL=C grep -Eq '__INSTALLER_[A-Z0-9_]+__' "$tmp_asset"; then
      rm -f "$tmp_asset"
      crowdsec_fatal "unresolved CrowdSec template: $repo_path"
    fi
    chmod "$mode" "$tmp_asset" || return $?
    mv -f "$tmp_asset" "$target_host_path" || return $?
  else
    status=$?
    rm -f "$tmp_asset"
    return "$status"
  fi
}


crowdsec_stage_logging_overlay() {
  logging_overlay_repo=$1
  logging_overlay_target=$2
  logging_overlay_kind=$3
  crowdsec_validate_abs_target_path "$logging_overlay_target"
  logging_overlay_host=${target_root}${logging_overlay_target}
  if [ -e "$logging_overlay_host" ] || [ -L "$logging_overlay_host" ]; then
    [ -f "$logging_overlay_host" ] && [ ! -L "$logging_overlay_host" ] ||
      crowdsec_fatal "unsafe CrowdSec logging overlay"
    LC_ALL=C awk -v kind="$logging_overlay_kind" '
      BEGIN {
        capi[1]="api:"; capi[2]="  server:"; capi[3]="    online_client:"
        capi[4]="      credentials_path: __INSTALLER_PATH_DIR_ETC__/crowdsec/online_api_credentials.yaml"
        capi[5]="      sharing: true"; capi[6]="      pull:"
        capi[7]="        community: true"; capi[8]="        blocklists: true"
      }
      /^[ \t]*#/ || /^[ \t]*$/ { next }
      {
        if (kind=="engine" && ($0=="api:" || capi_line)) {
          if ($0!=capi[++capi_line]) exit 1
          next
        }
        if (kind=="engine" && $0=="common:") {
          if (section++) exit 1
          next
        }
        if (kind=="engine" && (!section || $0 !~ /^  [a-z_]+: /)) exit 1
        if (kind=="bouncer" && $0 !~ /^[a-z_]+: /) exit 1
        key=$0; sub(/^[ ]*/,"",key); sub(/:.*/,"",key)
        value=$0; sub(/^[^:]*:[ ]*/,"",value)
        if (seen[key]++ || value !~ /^[A-Za-z0-9_.\/:-]+$/) exit 1
        if (kind=="engine") {
          if (key !~ /^(log_media|log_dir|log_level|log_max_size|log_max_age|log_max_files|compress_logs)$/) exit 1
        } else {
          if (key=="api_url" && value=="http://127.0.0.1:8080/") next
          if (key=="mode" && value=="nftables") next
          if (key !~ /^(log_mode|log_dir|log_level|log_max_size|log_max_age|log_max_backups|log_compression)$/) exit 1
        }
      }
      END { if (capi_line && capi_line!=8) exit 1 }
    ' "$logging_overlay_host" || crowdsec_fatal "preserving administrator CrowdSec overlay: $logging_overlay_target"
  fi
  crowdsec_stage_target_asset "$logging_overlay_repo" "$logging_overlay_target" 0600
}

crowdsec_remove_target_asset() {
  target_path=$1
  crowdsec_validate_abs_target_path "$target_path"
  rm -f "${target_root}${target_path}"
}

runtime_dir=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
bootstrap_lib=${INSTALLER_BOOTSTRAP_LIB:-${runtime_dir}/bootstrap/bootstrap.sh}

[ -s "$bootstrap_lib" ] || crowdsec_fatal "installer bootstrap library is unavailable: ${bootstrap_lib}"
# shellcheck disable=SC1090,SC1091
. "$bootstrap_lib"
bootstrap_source_common_lib ""
# Load di.env through the common bootstrap before deriving d-i state paths.
tmp_env_dir=${INSTALLER_LATE_TMP_ENV_DIR:-${DIR_INSTALLER_LATE_ENV}/crowdsec}
installer_operation_context_repo scripts/late/crowdsec.sh 168 crowdsec
seed_base=$(installer_current_seed_base 2>__INSTALLER_PATH_DIR_DEV__/null || installer_seed_base "")
bootstrap_source_common_support_libs "$seed_base" "$tmp_env_dir" fetch hook target
installer_ensure_context_loaded "$seed_base"

installer_any_role_class_selected 2>__INSTALLER_PATH_DIR_DEV__/null || exit 0

host_profile=${INSTALLER_HOST_PROFILE:-$(installer_resolve_host_profile "" 2>__INSTALLER_PATH_DIR_DEV__/null || true)}
[ -n "$host_profile" ] || crowdsec_fatal "selected host profile is unavailable for crowdsec helper"
host_env=${INSTALLER_LATE_HOST_ENV:-${DIR_INSTALLER_LATE_ENV}/host.env}
[ -r "$host_env" ] || installer_fetch_host_env "$seed_base" "$host_profile" "$host_env" 0600
# shellcheck disable=SC1090,SC1091
installer_load_data_env "$host_env"
case "${SSH_SERVER_ENABLE:-}" in
  true|false) ;;
  *) crowdsec_fatal "SSH_SERVER_ENABLE must be true or false in the host profile" ;;
esac

# Only a selected qBittorrent application needs an account-specific acquisition.
if installer_class_selected_any role/desktop/medium role/desktop/full; then
account_env=${INSTALLER_LATE_ACCOUNT_ENV:-${DIR_INSTALLER_LATE_ENV}/account.env}
[ -f "$account_env" ] && [ -r "$account_env" ] && [ -s "$account_env" ] && [ ! -L "$account_env" ] ||
  crowdsec_fatal "resolved account env is missing or unsafe: ${account_env}"
unset ACCOUNT_USERNAME
# shellcheck disable=SC1090,SC1091
installer_load_data_env "$account_env"
[ -n "${ACCOUNT_USERNAME:-}" ] ||
  crowdsec_fatal "ACCOUNT_USERNAME is missing from the resolved account env"
printf '%s\n' "$ACCOUNT_USERNAME" | LC_ALL=C grep -Eq '^[a-z_][a-z0-9_-]{0,31}$' ||
  crowdsec_fatal "ACCOUNT_USERNAME must match ^[a-z_][a-z0-9_-]{0,31}$"
fi

# Reject unsafe existing native output paths before any tmpfiles or daemon use.
crowdsec_stage_target_asset \
  "$(installer_repo_file_value hooks/target/usr/local/libexec/common/native-logging.tmpl)" \
  "${DIR_USR_LOCAL_LIBEXEC}/native-logging" 0755
run_in_target "validate existing native log paths" \
  "${DIR_USR_LOCAL_LIBEXEC}/native-logging" --preflight

# Create native logging paths before the first boot activates CrowdSec.
crowdsec_stage_logging_overlay \
  "$(installer_repo_file_value hooks/target/etc/crowdsec/common/config.yaml.local.tmpl)" \
  __INSTALLER_PATH_DIR_ETC__/crowdsec/config.yaml.local engine
crowdsec_stage_target_asset \
  "$(installer_repo_file_value hooks/target/etc/tmpfiles.d/common/57-crowdsec-logs.conf.tmpl)" \
  __INSTALLER_PATH_DIR_ETC__/tmpfiles.d/57-crowdsec-logs.conf 0644
run_in_target "create native CrowdSec log directory" \
  __INSTALLER_PATH_DIR_USR_BIN__/systemd-tmpfiles --create __INSTALLER_PATH_DIR_ETC__/tmpfiles.d/57-crowdsec-logs.conf
for logging_unit in crowdsec crowdsec-firewall-bouncer; do
  case "$logging_unit" in
    crowdsec) logging_selector=hooks/target/etc/systemd/common/system/crowdsec.service.d/40-logging.conf.tmpl ;;
    crowdsec-firewall-bouncer) logging_selector=hooks/target/etc/systemd/common/system/crowdsec-firewall-bouncer.service.d/40-logging.conf.tmpl ;;
  esac
  crowdsec_stage_target_asset \
    "$(installer_repo_file_value "$logging_selector")" \
    "$(installer_systemd_dropin_dir system "${logging_unit}.service")/40-logging.conf" 0644
done
crowdsec_stage_target_asset \
  "$(installer_repo_file_value hooks/target/etc/systemd/common/system/crowdsec.service.d/20-capi-retry.conf)" \
  __INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_CROWDSEC_DROPIN__/20-capi-retry.conf 0644

# The d-i locale may not exist inside the target yet; scope C to this package operation.
run_in_target "install CrowdSec bouncer after engine configuration" env LC_ALL=C DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install crowdsec-firewall-bouncer-nftables
run_in_target "protect installed CrowdSec bouncer configuration" __INSTALLER_PATH_DIR_BIN__/sh -eu -c '
config=__INSTALLER_PATH_DIR_ETC__/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml
[ -s "$config" ] && [ ! -L "$config" ] && [ "$(find -P "$config" -maxdepth 0 -printf %n)" = 1 ] || {
  printf "CrowdSec bouncer configuration is missing or unsafe\n" >&2
  exit 1
}
chown root:root "$config"
chmod 0600 "$config"
' sh

crowdsec_validate_abs_target_path __INSTALLER_PATH_DIR_VAR__/lib/firstboot/bin
install -d -m 0700 "${target_root}__INSTALLER_PATH_DIR_VAR__/lib/firstboot" "${target_root}__INSTALLER_PATH_DIR_VAR__/lib/firstboot/bin"

: "${FILE_CROWDSEC_ENROLL_TOKEN:?FILE_CROWDSEC_ENROLL_TOKEN must be set}"
: "${FILE_CROWDSEC_COMPLETE:?FILE_CROWDSEC_COMPLETE must be set}"
: "${FILE_CROWDSEC_STATUS:?FILE_CROWDSEC_STATUS must be set}"
: "${LOG_SYSTEM_SERVICES_FILE:?LOG_SYSTEM_SERVICES_FILE must be set}"
token_file=$FILE_CROWDSEC_ENROLL_TOKEN
complete_file=$FILE_CROWDSEC_COMPLETE
status_file=$FILE_CROWDSEC_STATUS
log_file=$LOG_SYSTEM_SERVICES_FILE

crowdsec_validate_abs_target_path "$token_file"
crowdsec_validate_abs_target_path "$complete_file"
crowdsec_validate_abs_target_path "$status_file"
crowdsec_validate_abs_target_path "$log_file"

install -d -m 0700 \
  "${target_root}$(dirname "$token_file")" \
  "${target_root}$(dirname "$complete_file")" \
  "${target_root}$(dirname "$status_file")"

crowdsec_auth_selector=hooks/target/etc/crowdsec/common/acquis.d/20-sshd.yaml.tmpl
if [ "$INSTALLER_HOST_VARIANT" = server ]; then crowdsec_auth_selector=hooks/target/etc/crowdsec/server/acquis.d/20-server-sshd.yaml.tmpl; fi
crowdsec_stage_target_asset \
  "$(installer_repo_file_value "$crowdsec_auth_selector")" \
  __INSTALLER_PATH_DIR_ETC__/crowdsec/acquis.d/20-sshd.yaml \
  0644
crowdsec_stage_target_asset \
  "$(installer_repo_file_value hooks/target/etc/crowdsec/common/acquis.d/21-auditd.yaml.tmpl)" \
  __INSTALLER_PATH_DIR_ETC__/crowdsec/acquis.d/21-auditd.yaml \
  0644
crowdsec_stage_target_asset \
  "$(installer_repo_file_value hooks/target/etc/crowdsec/common/acquis.d/22-nftables.yaml.tmpl)" \
  __INSTALLER_PATH_DIR_ETC__/crowdsec/acquis.d/22-nftables.yaml \
  0644
crowdsec_stage_target_asset \
  "$(installer_repo_file_value hooks/target/etc/crowdsec/common/acquis.d/23-system-syslog.yaml.tmpl)" \
  __INSTALLER_PATH_DIR_ETC__/crowdsec/acquis.d/23-system-syslog.yaml \
  0644
crowdsec_remove_target_asset __INSTALLER_PATH_DIR_ETC__/crowdsec/acquis.d/22-server-syslog.yaml
if installer_class_selected_any role/desktop/medium role/desktop/full; then
crowdsec_stage_target_asset \
  "$(installer_repo_file_value hooks/target/etc/crowdsec/desktop/acquis.d/24-qbittorrent.yaml.tmpl)" \
  __INSTALLER_PATH_DIR_ETC__/crowdsec/acquis.d/24-qbittorrent.yaml 0644 \
  ACCOUNT_USERNAME "$ACCOUNT_USERNAME"
fi
# No HTTP access-log or AppSec bouncer integration is configured. Keep the
# requested qBittorrent source without loading unrelated web/container parsers.
crowdsec_stage_target_asset \
  "$(installer_repo_file_value hooks/target/etc/crowdsec/common/parsers/s01-parse/00-auditd-daemon.yaml)" \
  __INSTALLER_PATH_DIR_ETC__/crowdsec/parsers/s01-parse/00-auditd-daemon.yaml 0644
# Local rules match the managed producers and retain the existing log budget.
# JSON documents are valid YAML and keep complex expressions unambiguously quoted.
for crowdsec_detection_asset in \
  parsers/s01-parse/00-nftables-nondrop.yaml \
  parsers/s02-enrich/00-audit-security.yaml \
  scenarios/nftables-tcp-scan.yaml \
  scenarios/nftables-udp-scan.yaml \
  scenarios/apparmor-denial-burst.yaml; do
  crowdsec_stage_target_asset \
    "$(installer_repo_asset_path DIR_TARGET_CROWDSEC "${crowdsec_detection_asset}")" \
    "__INSTALLER_PATH_DIR_ETC__/crowdsec/${crowdsec_detection_asset}" 0644
done
unset crowdsec_detection_asset
# The packaged setup acquisitions target files this managed layout does not
# create; retain only the explicit managed sources above.
crowdsec_remove_target_asset __INSTALLER_PATH_DIR_ETC__/crowdsec/acquis.d/setup.auditd.yaml
crowdsec_remove_target_asset __INSTALLER_PATH_DIR_ETC__/crowdsec/acquis.d/setup.linux.yaml
crowdsec_stage_logging_overlay \
  "$(installer_repo_file_value hooks/target/etc/crowdsec/common/bouncers/crowdsec-firewall-bouncer.yaml.local.tmpl)" \
  __INSTALLER_PATH_DIR_ETC__/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml.local bouncer
crowdsec_stage_target_asset \
  "$(installer_repo_file_value hooks/target/etc/systemd/common/system/crowdsec-firewall-bouncer.service.d/override.conf)" \
  __INSTALLER_PATH_DIR_SYSTEMD_SYSTEM_CROWDSEC_FIREWALL_BOUNCER_DROPIN__/override.conf \
  0644
crowdsec_stage_target_asset \
  "$(installer_repo_file_value hooks/target/etc/audit/crowdsec/common.rules)" \
  __INSTALLER_PATH_DIR_ETC__/audit/rules.d/zz-crowdsec.rules \
  0640
crowdsec_desktop_tools=false
if installer_class_selected_any role/desktop/medium role/desktop/full; then crowdsec_desktop_tools=true; fi
crowdsec_stage_target_asset \
  "$(installer_repo_file_value scripts/firstboot/assets/var/lib/firstboot/bin/crowdsec-firstboot.tmpl)" \
  __INSTALLER_PATH_DIR_VAR__/lib/firstboot/bin/crowdsec-firstboot \
  0755 SSH_SERVER_ENABLE "$SSH_SERVER_ENABLE" CROWDSEC_HOST_VARIANT "$INSTALLER_HOST_VARIANT" \
  CROWDSEC_RELEASE_ID "$INSTALLER_RELEASE_ID" CROWDSEC_DESKTOP_TOOLS_ENABLE "$crowdsec_desktop_tools"
crowdsec_unit_selector=scripts/firstboot/assets/etc/systemd/system/crowdsec-firstboot.service.tmpl
if [ "$INSTALLER_HOST_VARIANT" = server ]; then crowdsec_unit_selector=hooks/target/etc/systemd/server/system/crowdsec-firstboot.service.tmpl; fi
crowdsec_stage_target_asset \
  "$(installer_repo_file_value "$crowdsec_unit_selector")" \
  __INSTALLER_PATH_DIR_ETC__/systemd/system/crowdsec-firstboot.service \
  0644 --environment \
  CROWDSEC_HOST_VARIANT "$INSTALLER_HOST_VARIANT" \
  CROWDSEC_ENROLL_TOKEN_FILE "$token_file" \
  CROWDSEC_COMPLETE_FILE "$complete_file" \
  CROWDSEC_STATUS_FILE "$status_file"

crowdsec_stage_target_asset \
  "$(installer_repo_file_value hooks/target/usr/local/libexec/common/crowdsec-bouncer-verify)" \
  "${DIR_USR_LOCAL_LIBEXEC}/crowdsec-bouncer-verify" \
  0755

if crowdsec_token=$(crowdsec_cmdline_token 2>__INSTALLER_PATH_DIR_DEV__/null); then
  token_tmp=$(mktemp "${target_root}${token_file}.XXXXXX")
  printf '%s\n' "$crowdsec_token" >"$token_tmp"
  chmod 0600 "$token_tmp"
  mv -f "$token_tmp" "${target_root}${token_file}"
  crowdsec_info "staged optional console enrollment token for deferred post-boot enrollment"
else
  token_status=$?
  [ "$token_status" -eq 1 ] || crowdsec_fatal "invalid supplied CrowdSec enrollment token"
  rm -f "${target_root}${token_file}"
  crowdsec_info "crowdsec_token not provided by the installer cmdline or /preseed.env; deferred enrollment stays disabled"
fi
unset crowdsec_token 2>__INSTALLER_PATH_DIR_DEV__/null || true


run_in_target "enable crowdsec target units" __INSTALLER_PATH_DIR_BIN__/sh -eu -c '
systemctl --root=/ disable crowdsec.service crowdsec-firewall-bouncer.service >__INSTALLER_PATH_DIR_DEV__/null
systemctl --root=/ enable crowdsec-firstboot.service >__INSTALLER_PATH_DIR_DEV__/null
' sh

crowdsec_info "staged CrowdSec target assets for host_variant=$INSTALLER_HOST_VARIANT"

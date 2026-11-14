#!/bin/sh
set -eu

RUNTIME_DIR=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
BOOTSTRAP_LIB=${INSTALLER_BOOTSTRAP_LIB:-${RUNTIME_DIR}/bootstrap/bootstrap.sh}
if [ ! -s "$BOOTSTRAP_LIB" ]; then
  SELF_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
  BOOTSTRAP_LIB="${SELF_DIR}/../common/bootstrap.sh"
fi
[ -s "$BOOTSTRAP_LIB" ] || {
  answers_message=$(printf '%s' "installer bootstrap library is unavailable: ${BOOTSTRAP_LIB}" | tr '\r\n\t' '   ')
  printf '[preseed-answers] fatal: %s\n' "$answers_message" >&2
  if [ -c /dev/tty4 ] && [ -w /dev/tty4 ]; then
    printf '[preseed-answers] fatal: %s\n' "$answers_message" >/dev/tty4 || :
  fi
  if [ -c /dev/console ] && [ -w /dev/console ]; then
    printf '[preseed-answers] fatal: %s\n' "$answers_message" >/dev/console || :
  fi
  if command -v logger >/dev/null 2>&1; then
    logger -t preseed-answers "fatal: $answers_message" 2>/dev/null || :
  fi
  exit 1
}
# shellcheck disable=SC1090,SC1091
. "$BOOTSTRAP_LIB"
bootstrap_source_common_lib "${2:-}"
installer_init_stderr_log_file "$(installer_runtime_log_file)" "" "preseed answers (${1:-unset})" preseed-answers preseed_loaded
installer_operation_context_repo FILE_PRESEED_ANSWERS 28 "preseed_answers:${1:-unset}"
trap 'installer_finalize_log "$?"' EXIT

apply_answers_file() {
  # The installer utility accepts a FILE, not stdin or the Perl tool's -c.
  # Never retry a failed database write as a supposed syntax check.
  installer_debconf_apply_file "$1"
}

append_unique_words() {
  var_name=$1
  shift
  eval "current_words=\${$var_name:-}"
  for word in "$@"; do
    [ -n "$word" ] || continue
    case " ${current_words} " in
      *" ${word} "*) ;;
      *) current_words="${current_words:+$current_words }${word}" ;;
    esac
  done
  eval "$var_name=\$current_words"
}

append_unique_word_list() {
  var_name=$1
  list_words=$2
  for word in $list_words; do
    append_unique_words "$var_name" "$word"
  done
}

validate_single_line_token() {
  label=$1
  value=$2
  case "$value" in
    ''|*[![:print:]]*|*[[:space:]]*)
      installer_fatal "${label} must be a single printable token"
      ;;
  esac
}

validate_hostname_component() {
  label=$1
  value=$2
  case "$value" in
    ''|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-]*|.*|*.|*..*)
      installer_fatal "${label} must contain only hostname-safe labels"
      ;;
  esac
}

validate_word_list() {
  label=$1
  value=$2
  count=0

  for word in $value; do
    validate_single_line_token "${label} entry" "$word"
    count=$((count + 1))
  done

  [ "$count" -ge 1 ] || installer_fatal "${label} must contain at least one token"
}

answer_value() {
  for answer_key in "$@"; do
    value=$(installer_cmdline_value "$answer_key" 2>/dev/null || true)
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return 0
    fi
  done

  for answer_key in "$@"; do
    value=$(installer_debconf_value "$answer_key" 2>/dev/null || true)
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      return 0
    fi
  done

  return 1
}

validate_ipv4_address() {
  label=$1
  value=$2
  old_ifs=$IFS

  case "$value" in
    ''|*[!0123456789.]*|.*|*.|*..*)
      installer_fatal "${label} must be an IPv4 dotted-quad address"
      ;;
  esac

  IFS=.
  # shellcheck disable=SC2086
  set -- $value
  IFS=$old_ifs

  [ "$#" -eq 4 ] || installer_fatal "${label} must contain four IPv4 octets"
  for octet in "$@"; do
    case "$octet" in
      ''|*[!0123456789]*|????*)
        installer_fatal "${label} contains an invalid IPv4 octet"
        ;;
    esac
    [ "$octet" -le 255 ] || installer_fatal "${label} octet is outside 0-255"
  done
}

validate_ipv4_address_list() {
  label=$1
  value=$2
  count=0

  case "$value" in
    *','*) installer_fatal "${label} must use spaces between IPv4 addresses, not commas" ;;
  esac

  for address in $value; do
    count=$((count + 1))
    validate_ipv4_address "${label} entry" "$address"
  done

  [ "$count" -ge 1 ] || installer_fatal "${label} must contain at least one IPv4 address"
  [ "$count" -le 3 ] || installer_fatal "${label} must contain no more than three IPv4 addresses"
}

selected_dualboot_class() {
  installer_class_selected optional/dualboot 2>/dev/null
}

validate_positive_integer() {
  label=$1
  value=$2
  case "$value" in
    ''|*[!0123456789]*)
      installer_fatal "${label} must be a positive integer"
      ;;
    0)
      installer_fatal "${label} must be greater than zero"
      ;;
  esac
}

validate_dualboot_cmdline_contract() {
  dualboot_efi_value=$(installer_cmdline_value dualboot_efi 2>/dev/null || true)
  dualboot_debian_value=$(installer_cmdline_value dualboot_debian 2>/dev/null || true)

  if [ "$DUALBOOT_ENABLED" = true ]; then
    [ -n "$dualboot_efi_value" ] || installer_fatal "classes=...,dualboot requires dualboot_efi=<integer> on the kernel cmdline"
    [ -n "$dualboot_debian_value" ] || installer_fatal "classes=...,dualboot requires dualboot_debian=<integer> on the kernel cmdline"
    validate_positive_integer dualboot_efi "$dualboot_efi_value"
    validate_positive_integer dualboot_debian "$dualboot_debian_value"
    [ "$dualboot_efi_value" -lt "$dualboot_debian_value" ] || installer_fatal "dualboot_efi must be lower than dualboot_debian"
  elif [ -n "$dualboot_efi_value" ] || [ -n "$dualboot_debian_value" ]; then
    installer_fatal "dualboot_efi and dualboot_debian require classes=...,dualboot"
  fi
}

static_network_requested() {
  [ "$NETWORK_MODE" = static ]
}

read_network_domain_answer() {
  domain_value=$(answer_value netcfg/get_domain domain 2>/dev/null || true)
  [ -n "$domain_value" ] || return 0
  validate_hostname_component "netcfg/get_domain" "$domain_value"
  SYSTEM_DOMAIN=$domain_value
}

read_static_network_answers() {
  static_network_requested || return 0

  STATIC_IP_ADDRESS=$(answer_value netcfg/get_ipaddress ip 2>/dev/null || true)
  STATIC_NETMASK=$(answer_value netcfg/get_netmask netmask 2>/dev/null || true)
  STATIC_GATEWAY=$(answer_value netcfg/get_gateway gateway 2>/dev/null || true)
  # Installer bootstrap DNS is explicit host identity policy. Do not inherit a
  # DHCP/site answer or use TLS-only system upstreams as port-53 resolvers.
  STATIC_NAMESERVERS=${STATIC_INSTALLER_NAMESERVER:-}
  [ -n "$STATIC_NAMESERVERS" ] || installer_fatal "STATIC_INSTALLER_NAMESERVER is required for static installation"
}

validate_static_network_answers() {
  static_network_requested || return 0

  validate_ipv4_address STATIC_IP_ADDRESS "$STATIC_IP_ADDRESS"
  validate_ipv4_address STATIC_NETMASK "$STATIC_NETMASK"
  validate_ipv4_address STATIC_GATEWAY "$STATIC_GATEWAY"
  if [ -n "$STATIC_NAMESERVERS" ]; then
    validate_ipv4_address_list STATIC_NAMESERVERS "$STATIC_NAMESERVERS"
  fi
}

write_installer_nameserver_answers() {
  validate_ipv4_address STATIC_INSTALLER_NAMESERVER "${STATIC_INSTALLER_NAMESERVER:-}"
  printf 'd-i netcfg/get_nameservers string %s\n' "$STATIC_INSTALLER_NAMESERVER"
  printf 'd-i netcfg/get_nameservers seen true\n'
}

write_static_network_answers() {
  static_network_requested || return 0

  printf 'd-i netcfg/use_autoconfig boolean false\n'
  printf 'd-i netcfg/use_autoconfig seen true\n'
  printf 'd-i netcfg/disable_autoconfig boolean true\n'
  printf 'd-i netcfg/disable_autoconfig seen true\n'
  printf 'd-i netcfg/disable_dhcp boolean true\n'
  printf 'd-i netcfg/disable_dhcp seen true\n'
  printf 'd-i netcfg/dhcp_options select Configure network manually\n'
  printf 'd-i netcfg/dhcp_options seen true\n'
  printf 'd-i netcfg/get_ipaddress string %s\n' "$STATIC_IP_ADDRESS"
  printf 'd-i netcfg/get_ipaddress seen true\n'
  printf 'd-i netcfg/get_netmask string %s\n' "$STATIC_NETMASK"
  printf 'd-i netcfg/get_netmask seen true\n'
  printf 'd-i netcfg/get_gateway string %s\n' "$STATIC_GATEWAY"
  printf 'd-i netcfg/get_gateway seen true\n'
  printf 'd-i netcfg/confirm_static boolean true\n'
  printf 'd-i netcfg/confirm_static seen true\n'
}

selected_arch_class() {
  if [ -n "${PRESEED_SELECTED_ARCH_CLASS:-}" ]; then
    printf '%s\n' "$PRESEED_SELECTED_ARCH_CLASS"
    return 0
  fi

  PRESEED_SELECTED_ARCH_CLASS=${INSTALLER_ARCH_CLASS:-$(installer_selected_class_for_purpose arch 2>/dev/null || true)}
  [ -n "$PRESEED_SELECTED_ARCH_CLASS" ] ||
    installer_fatal "selected arch class is unavailable while resolving pkgsel/include"
  printf '%s\n' "$PRESEED_SELECTED_ARCH_CLASS"
}

secure_boot_boot_chain_packages_for_selected_arch() {
  arch_class=${INSTALLER_ARCH_CLASS:-$(installer_selected_class_for_purpose arch 2>/dev/null || true)}

  case "$arch_class" in
    amd64)
      printf '%s\n' "grub-efi-amd64 grub-efi-amd64-signed shim-signed shim-helpers-amd64-signed"
      ;;
    arm64)
      printf '%s\n' "grub-efi-arm64 grub-efi-arm64-signed shim-signed shim-helpers-arm64-signed"
      ;;
    *)
      installer_fatal "unsupported arch class for Secure Boot packages: ${arch_class:-unset}"
      ;;
  esac
}

word_list_contains() {
  words=$1
  needle=$2

  case " ${words} " in
    *" ${needle} "*) return 0 ;;
  esac
  return 1
}

validate_policy_subset() {
  label=$1
  subset_words=$2
  superset_words=$3

  for word in $subset_words; do
    word_list_contains "$superset_words" "$word" || installer_fatal "${label} references package missing from d-i pkgsel/include: ${word}"
  done
}

validate_class_policy() {
  [ -n "$PKGSEL_INCLUDE" ] || installer_fatal "selected classes resolved an empty d-i pkgsel/include package set"
  validate_policy_subset secure_boot_boot_chain_packages "$SECURE_BOOT_BOOT_CHAIN_PACKAGES" "$PKGSEL_INCLUDE"
  validate_policy_subset secure_boot_support_packages "$SECURE_BOOT_SUPPORT_PACKAGES" "$PKGSEL_INCLUDE"
}

write_class_policy_env() {
  policy_file=$1
  secure_boot_target_packages=

  append_unique_word_list secure_boot_target_packages "$SECURE_BOOT_BOOT_CHAIN_PACKAGES"
  append_unique_word_list secure_boot_target_packages "$SECURE_BOOT_SUPPORT_PACKAGES"

  {
    printf '# Generated by scripts/preseed/answers.sh from selected installer class fragments\n'
    printf 'INSTALLER_PKGSEL_INCLUDE=%s\n' "$(installer_shell_quote "$PKGSEL_INCLUDE")"
    printf 'INSTALLER_SECURE_BOOT_BOOT_CHAIN_PACKAGES=%s\n' "$(installer_shell_quote "$SECURE_BOOT_BOOT_CHAIN_PACKAGES")"
    printf 'INSTALLER_SECURE_BOOT_SUPPORT_PACKAGES=%s\n' "$(installer_shell_quote "$SECURE_BOOT_SUPPORT_PACKAGES")"
    printf 'INSTALLER_SECURE_BOOT_TARGET_PACKAGES=%s\n' "$(installer_shell_quote "$secure_boot_target_packages")"
  } >"$policy_file"
  chmod 0600 "$policy_file"
}

# All public answers, package lists and repository policies come from the
# frozen plan. This formatter never reparses class files or imports shell data.
load_planned_answers() {
  planned_output=$1
  installer_assert_class_plan || return "$?"
  planned_source=$(installer_class_plan_path)
  awk -F '\t' '
    $1=="answer" {
      if(NF!=5) exit 2
      printf "%s %s %s",$2,$3,$4
      if(length($5)) printf " %s",$5
      printf "\n"
      count++
    }
    END {if(!count) exit 2}
  ' "$planned_source" >"$planned_output" || installer_fatal 'frozen preseed answers are invalid or absent'
  chmod 0600 "$planned_output" || return "$?"
  PKGSEL_INCLUDE=$(awk -F '\t' '$1=="answer" && $3=="pkgsel/include" && $4=="string" {print $5}' "$planned_source")
  ANNA_CHOOSE_MODULES=$(awk -F '\t' '$1=="answer" && $3=="anna/choose_modules" && $4=="multiselect" {print $5}' "$planned_source")
}

write_answers_file() {
  answers_file=$1
  merged_file=$2
  [ -r "$merged_file" ] || installer_fatal "merged preseed fragment file is not readable: ${merged_file}"
  install -d -m 0700 "$(dirname "$answers_file")"
  cat "$merged_file" >"$answers_file"

  {
    printf '# Generated by scripts/preseed/answers.sh from selected preseed cfg fragments\n'
    printf '# Runtime overrides are appended after the class fragments so host- and cmdline-derived values win.\n'
    printf 'd-i anna/choose_modules multiselect %s\n' "$ANNA_CHOOSE_MODULES"
    printf 'd-i anna/choose_modules seen true\n'
    printf 'd-i pkgsel/include string %s\n' "$PKGSEL_INCLUDE"
    printf 'd-i pkgsel/include seen true\n'
    printf 'd-i netcfg/get_hostname string %s\n' "$SYSTEM_HOSTNAME"
    printf 'd-i netcfg/get_hostname seen true\n'
    printf 'd-i netcfg/hostname string %s\n' "$SYSTEM_HOSTNAME"
    printf 'd-i netcfg/hostname seen true\n'
    printf 'd-i netcfg/get_domain string %s\n' "$SYSTEM_DOMAIN"
    printf 'd-i netcfg/get_domain seen true\n'
    if [ "$DUALBOOT_ENABLED" != true ]; then
      printf 'd-i grub-installer/only_debian boolean true\n'
      printf 'd-i grub-installer/only_debian seen true\n'
      printf 'd-i grub-installer/with_other_os boolean false\n'
      printf 'd-i grub-installer/with_other_os seen true\n'
      printf 'd-i grub-installer/enable_os_prober_otheros_yes boolean false\n'
      printf 'd-i grub-installer/enable_os_prober_otheros_yes seen true\n'
      printf 'd-i grub-installer/enable_os_prober_otheros_no boolean false\n'
      printf 'd-i grub-installer/enable_os_prober_otheros_no seen true\n'
      printf 'grub2 grub2/enable_os_prober boolean false\n'
      printf 'grub2 grub2/enable_os_prober seen true\n'
    fi
    printf 'd-i grub-installer/force-efi-extra-removable boolean false\n'
    printf 'd-i grub-installer/force-efi-extra-removable seen true\n'
    printf 'd-i grub-installer/update-nvram boolean true\n'
    printf 'd-i grub-installer/update-nvram seen true\n'
    printf 'd-i grub-installer/skip boolean false\n'
    printf 'd-i grub-installer/skip seen true\n'
    write_static_network_answers
    write_installer_nameserver_answers
  } >>"$answers_file"
  chmod 0600 "$answers_file"
}

usage() {
  echo "usage: ${0##*/} {apply|prepare-context|render|show-host} [seed-base]" >&2
  exit 1
}

render_answers_file() {
  MERGED_FRAGMENT_FILE="${CACHE_DIR}/preseed.fragments.cfg"
  load_planned_answers "$MERGED_FRAGMENT_FILE"
  validate_class_policy
  HOST_POLICY_ENV="${STATE_DIR}/selected-host.env"
  if [ ! -s "$HOST_POLICY_ENV" ]; then
    installer_fetch_host_env "$seed_base" "$HOST_PROFILE" "$HOST_POLICY_ENV" 0600
  fi
  # shellcheck disable=SC1090,SC1091
  installer_load_data_env "$HOST_POLICY_ENV"
  read_network_domain_answer
  if selected_dualboot_class; then
    DUALBOOT_ENABLED=true
  fi
  validate_dualboot_cmdline_contract
  case "$NETWORK_MODE" in
    static|dhcp) ;;
    *)
      installer_fatal "unsupported network mode: ${NETWORK_MODE}"
      ;;
  esac
  read_static_network_answers
  validate_hostname_component SYSTEM_DOMAIN "$SYSTEM_DOMAIN"
  validate_static_network_answers
  validate_word_list ANNA_CHOOSE_MODULES "$ANNA_CHOOSE_MODULES"
  validate_word_list PKGSEL_INCLUDE "$PKGSEL_INCLUDE"
  installer_info "preseed answers classes raw: ${INSTALLER_CLASSES_RAW:-unset}"
  installer_info "preseed answers selected class refs: ${INSTALLER_SELECTED_CLASS_REFS:-unset}"
  installer_info "preseed answers anna modules: ${ANNA_CHOOSE_MODULES}"
  installer_info "preseed answers pkgsel/include: ${PKGSEL_INCLUDE}"
  installer_info "preseed answers secure boot boot-chain packages: ${SECURE_BOOT_BOOT_CHAIN_PACKAGES}"
  installer_info "preseed answers secure boot support packages: ${SECURE_BOOT_SUPPORT_PACKAGES}"
  planned_mirror_suite=$INSTALLER_SUITE
  planned_local_repos=selected-class-and-suite
  case "$INSTALLER_SUITE" in
    trixie) planned_update_origins=trixie-security,trixie-updates ;;
    forky) planned_update_origins=forky-testing ;;
  esac
  installer_append_log_category apt apt_config info apt "planned mirror=${planned_mirror_suite} update_origins=${planned_update_origins} backports=explicit-package-policy local_repos=${planned_local_repos} upgrade=safe-upgrade" || true
  installer_append_log_category package package_install info pkgsel "planned pkgsel/include=${PKGSEL_INCLUDE}" || true
  installer_append_log_category bootloader bootloader info grub "planned dualboot_class=${DUALBOOT_ENABLED} update_nvram=true force_extra_removable=false" || true
  installer_ensure_system_identity
  write_class_policy_env "$POLICY_ENV_FILE"
  answers_file="${STATE_DIR}/preseed.answers.cfg"
  write_answers_file "$answers_file" "$MERGED_FRAGMENT_FILE"
  installer_info "rendered preseed answers file: ${answers_file}"
  printf '%s\n' "$answers_file"
}

RUNTIME_DIR=$(installer_runtime_dir)
CACHE_DIR=$(installer_runtime_cache_dir)
STATE_DIR=$(installer_runtime_state_dir)
install -d -m 0700 "$CACHE_DIR/classes" "$STATE_DIR"
installer_ensure_log_files
POLICY_ENV_FILE=$(installer_class_policy_env_path)

seed_base=$(installer_seed_base "${2:-}")
case "${1:-}" in
  prepare-context)
    installer_write_context "$seed_base" >/dev/null
    ;;
  *)
    installer_ensure_context_loaded "$seed_base"
    ;;
esac
installer_load_context_if_present || true
installer_info "preseed release identity=${INSTALLER_RELEASE_ID:-unknown} suite=${INSTALLER_SUITE:-unknown}"

HOST_PROFILE=${INSTALLER_HOST_PROFILE:-$(installer_resolve_host_profile "" 2>/dev/null || true)}
[ -n "$HOST_PROFILE" ] || installer_fatal "selected host profile is unavailable in installer context"


ANNA_CHOOSE_MODULES=
NETWORK_MODE=${INSTALLER_NETWORK_CLASS:-$(installer_selected_class_for_purpose network 2>/dev/null || true)}
[ -n "$NETWORK_MODE" ] || installer_fatal "selected network class is unavailable in installer context"
DUALBOOT_ENABLED=false
STATIC_IP_ADDRESS=
STATIC_NETMASK=
STATIC_GATEWAY=
STATIC_NAMESERVERS=
PKGSEL_INCLUDE=
SECURE_BOOT_BOOT_CHAIN_PACKAGES=$(secure_boot_boot_chain_packages_for_selected_arch)
SECURE_BOOT_SUPPORT_PACKAGES="initramfs-tools busybox cryptsetup efibootmgr mokutil sbsigntool openssl kmod python3 util-linux util-linux-extra xz-utils zstd"

case "${1:-}" in
  apply)
    answers_file=$(render_answers_file)
    apply_answers_file "$answers_file"
    installer_log "applied dynamic preseed answers for ${HOST_PROFILE} from classes=${INSTALLER_CLASSES_RAW}"
    ;;
  prepare-context)
    MERGED_FRAGMENT_FILE="${CACHE_DIR}/preseed.fragments.cfg"
    load_planned_answers "$MERGED_FRAGMENT_FILE"
    validate_class_policy
    installer_fetch_host_env "$seed_base" "$HOST_PROFILE" "${STATE_DIR}/selected-host.env" 0600
    /bin/sh -n "${STATE_DIR}/selected-host.env" || installer_fatal 'selected host environment has invalid shell syntax'
    write_class_policy_env "$POLICY_ENV_FILE"
    ;;
  render)
    answers_file=$(render_answers_file)
    installer_log "rendered dynamic preseed answers for ${HOST_PROFILE} from classes=${INSTALLER_CLASSES_RAW}"
    printf '%s\n' "$answers_file"
    ;;
  show-host)
    printf '%s\n' "$HOST_PROFILE"
    ;;
  *)
    usage
    ;;
esac

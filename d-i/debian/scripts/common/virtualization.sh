#!/bin/sh
# Shared direct-QEMU and confined Incus installation; no daemon is started here.
set -eu
runtime_dir=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
bootstrap_lib=${INSTALLER_BOOTSTRAP_LIB:-${runtime_dir}/bootstrap/bootstrap.sh}
# shellcheck disable=SC1090
. "$bootstrap_lib"
bootstrap_source_common_lib ""
seed_base=$(installer_seed_base "")
installer_ensure_context_loaded "$seed_base"
installer_assert_class_plan
case "$INSTALLER_HOST_VARIANT" in
  desktop)
    installer_tools_class_selected || installer_fatal 'virtualization requires the medium or full desktop class'
    ;;
  server)
    installer_class_selected role/server/devops || installer_fatal 'server virtualization requires the DevOps class'
    ;;
  *) installer_fatal 'unknown virtualization role family' ;;
esac
profile="${DIR_INSTALLER_LATE_ENV}/virtualization.env"
installer_fetch_host_env "$seed_base" "$INSTALLER_HOST_PROFILE" "$profile" 0600
installer_load_data_env "$profile"
bootstrap_source_common_support_libs "$seed_base" "${DIR_INSTALLER_LATE_ENV}/virtualization-support" fetch hook target
case "${INCUS_BRIDGE_NAME:?Incus bridge name required}" in
  ''|*[!A-Za-z0-9_.-]*|.*|*..*) installer_fatal 'invalid Incus bridge name' ;;
esac
operator=$(installer_cmdline_value primary_user) || installer_fatal 'virtualization operator identity is missing'
case "$operator" in
  ''|root|ci-github|ci-gitlab|srv-devops|technitium|*[!a-z0-9_-]*) installer_fatal 'virtualization requires an explicit human operator' ;;
esac

# Package identities and native unit/socket layouts are checked inside the
# offline target. The Zabbly channel is explicitly suite-scoped by the class.
# shellcheck disable=SC2016
run_in_target 'verify shared QEMU/Incus package and operator contracts' "${DIR_BIN}/sh" -eu -c '
  operator=$1
  PATH=/usr/sbin:/usr/bin:/sbin:/bin
  export PATH
  for package in qemu-system-x86 qemu-system-modules-opengl qemu-utils qemu-block-extra ovmf swtpm swtpm-tools virtiofsd incus incus-client uidmap libosinfo-bin genisoimage python3; do
    [ "$(dpkg-query -W -f="\${db:Status-Abbrev}" "$package")" = "ii " ] || exit 1
  done
  [ "$(id -u "$operator")" -ge 1000 ] || exit 1
  case " $(id -nG "$operator") " in *" incus-admin "*) exit 1 ;; esac
  for group in kvm incus; do getent group "$group" >/dev/null || exit 1; done
  for service_account in ci-github ci-gitlab; do
    if getent passwd "$service_account" >/dev/null; then
      case " $(id -nG "$service_account") " in
        *" incus "*|*" incus-admin "*|*" kvm "*|*" devops "*) exit 1 ;;
      esac
    fi
  done
  getent group devops >/dev/null || groupadd --system devops
  for group in devops kvm incus; do usermod -a -G "$group" -- "$operator"; done
' sh "$operator"

installer_stage_profile_file FILE_TARGET_INCUS_HOST_TMPL "${DIR_ETC_INCUS}/host.conf" 0644
installer_stage_profile_file FILE_TARGET_TMPFILES_D_85_QEMU_INCUS_STORAGE_TMPL \
  "${DIR_TMPFILES_D}/85-qemu-incus-storage.conf" 0644
installer_stage_profile_file FILE_TARGET_QEMU_BRIDGE_TMPL "${DIR_ETC_QEMU}/bridge.conf" 0644
installer_stage_profile_file FILE_TARGET_LIBEXEC_INCUS_HOST "${DIR_USR_LOCAL_LIBEXEC}/incus-host" 0755
installer_stage_profile_file FILE_TARGET_AA_INCUS_HOST "${DIR_APPARMOR}/incus-host" 0644
installer_stage_profile_file FILE_TARGET_UNIT_INCUS_HOST_SERVICE "${DIR_SYSTEMD_SYSTEM}/incus-host.service" 0644
installer_stage_profile_file FILE_TARGET_UNIT_INCUS_USER_SERVICE_D_20_BOOTSTRAP \
  "${DIR_SYSTEMD_SYSTEM_INCUS_USER_DROPIN}/20-bootstrap.conf" 0644
installer_stage_profile_file FILE_TARGET_SYSUSERS_D_SWTPM_SYSUSERS "${DIR_ETC_SYSUSERS_D}/swtpm-sysusers.conf" 0644
run_in_target 'prepare owned QEMU and Incus storage without starting a daemon' \
  "${DIR_USR_LOCAL_LIBEXEC}/incus-host" --prepare-install


# Keep all Incus daemons demand-triggered by the confined socket. Remove only
# known links to these exact units; never replace a mask or competing owner.
for unit in incus.service incus-lxcfs.service incus-startup.service incus-user.service incus-host.service; do
  for target in default.target graphical.target multi-user.target; do
    parent="${TARGET_ROOT}${DIR_SYSTEMD_SYSTEM}/${target}.wants"
    installer_apt_safe_path "$parent" || installer_fatal 'unsafe virtualization activation ancestry'
    link="$parent/$unit"
    if [ -L "$link" ]; then
      case "$(readlink "$link")" in
        "${DIR_SYSTEMD_SYSTEM}/$unit"|"${DIR_SYSTEMD_SYSTEM_LIB}/$unit"|"../$unit") rm -f "$link" ;;
        *) installer_fatal 'competing Incus activation owner' ;;
      esac
    elif [ -e "$link" ]; then installer_fatal 'Incus activation path is not a link'; fi
  done
done
installer_stage_offline_unit_link "${DIR_SYSTEMD_SYSTEM_LIB}/incus.socket"
installer_stage_offline_unit_link "${DIR_SYSTEMD_SYSTEM_LIB}/incus-user.socket"
installer_info 'QEMU/KVM and confined Incus sockets staged; bridge NAT follows the active host uplink; no remote API or CI management authority'

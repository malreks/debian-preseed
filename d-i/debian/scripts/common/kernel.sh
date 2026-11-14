#!/bin/sh
# Shared installer-only kernel verification and native regulatory data policy.
set -eu
runtime_dir=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
bootstrap_lib=${INSTALLER_BOOTSTRAP_LIB:-${runtime_dir}/bootstrap/bootstrap.sh}
# shellcheck disable=SC1090
. "$bootstrap_lib"
bootstrap_source_common_lib ""
seed_base=$(installer_seed_base "")
installer_ensure_context_loaded "$seed_base"
kernel_env="${DIR_INSTALLER_LATE_ENV}/kernel.env"
installer_fetch_host_env "$seed_base" "$INSTALLER_HOST_PROFILE" "$kernel_env" 0600
installer_load_data_env "$kernel_env"
bootstrap_source_common_support_libs "$seed_base" "${DIR_INSTALLER_LATE_ENV}/kernel-support" fetch hook target
installer_assert_class_plan
kernel_image=$(awk -F '\t' '$1=="package" && $2 ~ /^linux-image-[0-9].*-x64v[23]-xanmod[0-9]+$/ {image=$2;count++}
  END {if(count!=1) exit 1;print image}' "$(installer_class_plan_path)") || installer_fatal 'the frozen amd64 plan requires one fixed XanMod image'
kernel_abi=${kernel_image#linux-image-}
kernel_headers="linux-headers-$kernel_abi"
installer_plan_package_selected "$kernel_headers" || installer_fatal 'the frozen XanMod image has no matching headers'
# Native Debian kernel package paths and dpkg status fields are fixed package
# interfaces. All project-owned roots remain runtime-contract arguments.
run_in_target 'verify the fixed XanMod image, matching headers and initrd' "${DIR_BIN}/sh" -eu -c '
  image=$1; headers=$2; abi=$3; boot=$4
  for package in "$image" "$headers"; do
    test "$(dpkg-query -W -f="\${db:Status-Status}" "$package")" = installed
  done
  test -s "$boot/vmlinuz-$abi"
  test -s "$boot/initrd.img-$abi"
  test -d "/usr/src/linux-headers-$abi"
  test -d "/lib/modules/$abi"
' sh "$kernel_image" "$kernel_headers" "$kernel_abi" "$DIR_BOOT"

# XanMod trusts upstream wireless-regdb certificates. Keep Debian's package
# and its matching upstream signature under the native alternatives owner.
run_in_target 'select the packaged upstream regulatory database for XanMod' "${DIR_BIN}/sh" -eu -c '
  test "$(dpkg-query -W -f="\${db:Status-Status}" wireless-regdb)" = installed
  choice=
  for candidate in "$1/firmware/regulatory.db-upstream" "$2/firmware/regulatory.db-upstream"; do
    if update-alternatives --query regulatory.db | grep -Fxq "Alternative: $candidate"; then choice=$candidate; break; fi
  done
  test -n "$choice"
  test -s "$choice"
  test -s "${choice%-upstream}.p7s-upstream"
  update-alternatives --set regulatory.db "$choice"
  test "$(readlink -e "$1/firmware/regulatory.db")" = "$(readlink -e "$choice")"
  test "$(readlink -e "$1/firmware/regulatory.db.p7s")" = "$(readlink -e "${choice%-upstream}.p7s-upstream")"
' sh "$DIR_USR_LIB" "$DIR_LIB"
installer_info "verified the selected fixed XanMod image/header pair: $kernel_abi"

#!/bin/sh
# First target APT update uses the authenticated network archive. Preserve the
# native media configuration for the later apt-setup scan, even when the first
# update replaces media sources. Apt-setup supplies mixed-suite policy and pins.
set -eu
runtime=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
. "$runtime/bootstrap/source.sh"
. "$runtime/bootstrap/di.env"
. "$runtime/bootstrap/common-lib.sh"
host_env="${DIR_INSTALLER_ENV}/host.env"
[ -r "$host_env" ] || {
  installer_fatal "composed host environment is unavailable: ${host_env}"
}
# shellcheck disable=SC1090,SC1091
if installer_load_data_env "$host_env"; then
  :
else
  host_env_status=$?
  installer_fatal_status "$host_env_status" "base-network-apt host profile data was rejected: ${host_env}"
fi
# apt-sources.sh consumes this already validated path contract in its child
# helpers; it must not parse host.env a second time at the APT waypoint.
INSTALLER_APT_RUNTIME_PATHS_READY=1
export INSTALLER_APT_RUNTIME_PATHS_READY
if installer_lifecycle_begin base-network-apt; then :; else
  rc=$?; [ "$rc" -eq 10 ] && exit 0; exit "$rc"
fi
. "$runtime/bootstrap/apt-sources.sh"
. /usr/share/debconf/confmodule
# bootstrap-base invokes this helper in a child process.  Recover the
# authenticated preseed context before falling back to its DISTRIBUTION
# argument, which may be a generic media label rather than the selected suite.
if [ -z "${INSTALLER_SUITE:-}" ] && [ -r "$runtime/state/context.env" ]; then
  /bin/sh -n "$runtime/state/context.env" ||
    installer_lifecycle_abort 125 base-network-apt 'installer suite context has invalid shell syntax'
  # shellcheck disable=SC1090
  . "$runtime/state/context.env" ||
    installer_lifecycle_abort 125 base-network-apt 'installer suite context could not be loaded'
fi
suite=${INSTALLER_SUITE:-$1}
case "$suite" in forky|trixie) ;; *) installer_lifecycle_abort 125 base-network-apt 'target APT suite is unavailable' ;; esac
# The frozen plan is the class-selection boundary. Validate that its
# class-owned apt-setup/local repository answers exist before the first target
# APT update; otherwise d-i would proceed with only the media/base source and
# pkgsel would later report packages as unavailable.
plan_path=$(installer_class_plan_path)
apt_class_source_count=$(awk -F '\t' '$1=="answer" && $3 ~ /^apt-setup\/local[0-9]+\/repository$/ {count++} END {print count+0}' "$plan_path") ||
  installer_lifecycle_abort 125 base-network-apt 'class-selected APT repository answers could not be read'
[ "$apt_class_source_count" -gt 0 ] ||
  installer_lifecycle_abort 125 base-network-apt 'class plan contains no APT repository answers before the first target update'
installer_info "class-selected APT repository answers available before first target update count=${apt_class_source_count}"
db_get mirror/protocol
protocol=$RET
case "$protocol" in http|https) ;; *) installer_lifecycle_abort 125 base-network-apt 'network Debian mirror is required' ;; esac
db_get "mirror/$protocol/hostname"
host=$RET
db_get "mirror/$protocol/directory"
directory=$RET
target=${INSTALLER_TARGET_DIR:-${TARGET_ROOT}}
installer_apt_install_target_policy "$target" bootstrap
# Match d-i's base-installer ordering: remove media sources and publish the
# authenticated Debian source before the first target update.  The managed
# APT::Default-Release file is intentionally written later by the
# finish-install normalizer, after apt-setup has completed and sources have
# been modernized, as in the legacy installer flow.
installer_operation_context_repo scripts/common/apt-sources.sh 66 apt_bootstrap_source
if installer_apt_bootstrap_source "$target" "$protocol" "$host" "$directory" "$suite"; then
  :
else
  apt_source_status=$?
  installer_fatal_status "$apt_source_status" 'failed to publish the authenticated Debian APT source'
fi
if installer_cuda_legacy_selected 2>/dev/null; then
  installer_cuda_stage_target_key
  installer_cuda_stage_target_source "$(installer_cuda_repository_url)" / ""
  printf 'stage=base_install level=info component=network-apt published legacy CUDA source before first update\n' >&2
fi
printf 'stage=base_install level=info component=network-apt normalized sources before first update suite=%s\n' "$suite" >&2
installer_operation_context_repo scripts/preseed/network-apt.sh 67 base_network_apt_update
installer_run_supervised in-target env LC_ALL=C DEBIAN_FRONTEND=noninteractive \
  apt-get -o APT::Update::Error-Mode=any -o Acquire::Retries=3 \
  -o Acquire::PDiffs=false -o Acquire::Languages=en \
  -o Acquire::IndexTargets::deb::Translations::DefaultEnabled=true \
  -o Acquire::http::Timeout=45 -o Acquire::https::Timeout=45 update
installer_lifecycle_complete

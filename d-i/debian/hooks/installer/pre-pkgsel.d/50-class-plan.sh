#!/bin/sh
# The one pre-pkgsel dispatcher reads the same frozen plan as every other phase.
set -eu
runtime_dir=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
bootstrap_lib=${INSTALLER_BOOTSTRAP_LIB:-${runtime_dir}/bootstrap/bootstrap.sh}
# shellcheck disable=SC1090
. "$bootstrap_lib"
bootstrap_source_common_lib ""
installer_init_log_file "$(installer_runtime_log_file)" "" "pre-pkgsel class plan" pre-pkgsel package_install
installer_operation_context_repo hooks/installer/pre-pkgsel.d/50-class-plan.sh 10 pre_pkgsel_plan
trap 'installer_finalize_log "$?"' EXIT
seed_base=$(installer_seed_base "")
installer_ensure_context_loaded "$seed_base"
installer_assert_class_plan
[ -n "${BOOTSTRAP_PREPARED_SOURCE_ROOT:-}" ] ||
  installer_fatal 'pre-pkgsel requires the target payload prepared by the first base-stage hook'
# This dispatcher runs in a new shell after apt-setup. Context carries the
# selected profile, not its target paths; load the authenticated policy before
# using the already rendered installer/DKMS helpers.
class_plan_host_env="${DIR_INSTALLER_ENV}/host.env"
[ -r "$class_plan_host_env" ] || installer_fatal 'pre-pkgsel host policy is unavailable'
if installer_load_data_env "$class_plan_host_env"; then
  :
else
  class_plan_status=$?
  installer_fatal_status "$class_plan_status" 'pre-pkgsel host policy could not be loaded'
fi
stage_file="$(installer_runtime_state_dir)/pre-pkgsel-stages.list"
installer_plan_stage_records pre-pkgsel >"$stage_file" ||
  installer_fatal 'invalid pre-pkgsel stage record'
while IFS='|' read -r stage_id stage_phase stage_selector || [ -n "$stage_id" ]; do
  if installer_phase_stage_begin pre-pkgsel "$stage_id"; then
    installer_info "starting pre-pkgsel stage ${stage_id} (${stage_selector})"
    installer_operation_context_repo "$stage_selector" 1 "pre_pkgsel:${stage_id}"
    destination=$(installer_pre_pkgsel_stage_path "$stage_id") ||
      installer_fatal 'invalid pre-pkgsel stage destination'
    installer_fetch_file "$seed_base" "$(installer_repo_file_value "$stage_selector")" "$destination" 0755
    if installer_run_supervised "$destination" </dev/null; then
      :
    else
      stage_status=$?
      installer_fatal_status "$stage_status" "pre-pkgsel stage ${stage_id} failed (${stage_selector})"
    fi
    installer_phase_stage_finish pre-pkgsel "$stage_id"
    installer_info "completed pre-pkgsel stage ${stage_id}"
  else
    stage_status=$?
    [ "$stage_status" -eq 1 ] || installer_fatal_status "$stage_status" 'cannot claim pre-pkgsel stage ownership'
  fi
done <"$stage_file"

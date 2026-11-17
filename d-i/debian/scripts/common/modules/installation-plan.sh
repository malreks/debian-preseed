#!/bin/sh
# The frozen plan binds plain class answers to the shared installer dispatcher.

installer_class_plan_path() {
  printf '%s/installation-plan.tsv\n' "$(installer_runtime_state_dir)"
}

# A selected pre-pkgsel provider is published once by the frozen-plan dispatcher.
# Late consumers must address that same stage instead of a retired d-i hook name.
installer_pre_pkgsel_stage_path() {
  case "${1:-}" in ''|*[!a-z0-9.-]*) return 1 ;; esac
  printf '%s/bootstrap/%s.sh\n' "${DIR_INSTALLER_RUNTIME:?installer runtime required}" "$1"
}

installer_multiboot_profile_selected() {
  case "${INSTALLER_HOST_PROFILE_ENV_NAME:-}" in *-duo|*-trio) return 0 ;; esac
  return 1
}

installer_class_selected() {
  case "${1:-}" in ''|*[!a-z0-9/-]*|*../*|*/..|*//*|/*) return 1 ;; esac
  class_plan=$(installer_class_plan_path) || return "$?"
  [ -r "$class_plan" ] || return 1
  awk -F '\t' -v wanted="$1" '$1 == "class" && $2 == wanted { found=1 } END {exit !found}' "$class_plan"
}

installer_class_selected_any() {
  for selected_ref in "$@"; do
    if installer_class_selected "$selected_ref"; then return 0; fi
  done
  return 1
}

installer_plan_package_selected() {
  case "${1:-}" in ''|*[!a-z0-9+.-]*) return 1 ;; esac
  awk -F '\t' -v wanted="$1" '$1=="package" {split($2, fields, /[\/:=]/); if(fields[1]==wanted) found=1} END {exit !found}' \
    "$(installer_class_plan_path)"
}

installer_desktop_class_selected() {
  installer_class_selected_any role/desktop/base role/desktop/medium role/desktop/full
}

installer_plan_roles() {
  awk -F '\t' '$1=="role" {print $2}' "$(installer_class_plan_path)"
}

installer_tools_class_selected() {
  installer_class_selected_any role/desktop/medium role/desktop/full role/server/devops
}

installer_any_role_class_selected() {
  installer_class_selected_any role/desktop/base role/desktop/medium role/desktop/full \
    role/server/github-actions role/server/gitlab-cicd role/server/technitium role/server/devops
}

installer_snapshots_enabled() {
  [ "$(installer_plan_value timeshift_enable)" = true ] &&
    [ "$(installer_plan_value snapshots)" = timeshift-btrfs ]
}

installer_plan_value() {
  case "${1:-}" in ''|*[!a-z0-9_-]*) return 1 ;; esac
  awk -F '\t' -v wanted="$1" '$1 == wanted {if (++count != 1) exit 2; value=$2} END {if(count != 1) exit 1; print value}' \
    "$(installer_class_plan_path)"
}

installer_prepare_class_plan() (
  set -eu
  umask 077
  plan_seed=$1
  case "${INSTALLER_SUITE:-}" in forky|trixie) ;; *) installer_fatal 'invalid suite identity' ;; esac
  plan_qualification_file=$(installer_class_metadata_read_path FILE_SUITE_QUALIFICATION) || exit "$?"
  plan_qualification=$(awk -F '\t' -v suite="$INSTALLER_SUITE" -v family="$INSTALLER_HOST_VARIANT" '
    $1==suite && $2==family {if(NF!=5) bad=1; count++; status=$3; reason=$4 ": " $5}
    END {if(bad || count!=1) exit 2; print status "|" reason}
  ' "$plan_qualification_file") || installer_fatal 'missing or ambiguous native suite qualification'
  case "$plan_qualification" in
    source-candidate\|*) ;;
    blocked\|*) installer_fatal "blocked before partitioning: ${plan_qualification#*|}" ;;
    *) installer_fatal 'invalid native suite qualification state' ;;
  esac
  case "${INSTALLER_ARCH_CLASS:-}" in amd64) ;; *) installer_fatal 'this release requires qualified amd64 artifacts; architecture unavailable before partman' ;; esac
  plan_profile=${INSTALLER_HOST_PROFILE_ENV_NAME:?explicit profile required}
  plan_roles=${INSTALLER_ROLE_IDS:?registered roles required}
  plan_release=${INSTALLER_RELEASE_ID:?trusted release identity required}
  case " $INSTALLER_SELECTED_CLASS_REFS " in
    *' optional/nvidia '*|*' optional/nvidia-legacy '*)
      installer_nvidia_gpu_detected || installer_fatal 'an explicit NVIDIA driver requires detected NVIDIA display hardware before partitioning'
      ;;
  esac
  # The registered profile owns multiboot selection; disk safety is checked
  # against the actual selected-disk inventory before any partman mutation.
  plan_mode=fresh
  case "$plan_profile" in *-duo|*-trio) plan_mode=multiboot ;; esac
  [ "${INSTALLER_PROFILE_PARTMAN_REUSE_ENABLE:?reuse policy required}" != true ] || plan_mode=reuse
  case " $plan_roles :$INSTALLER_HOST_FAMILY" in
    *' server/technitium '*:f2fs) installer_fatal 'Technitium requires project quotas on /pool; the selected F2FS layout provides ext4 without qualified project quotas' ;;
  esac
  plan_snapshots=${INSTALLER_PROFILE_SNAPSHOTS_POLICY:?profile snapshot policy required}
  case "$plan_snapshots:$INSTALLER_HOST_FAMILY" in
    timeshift-btrfs:btrfs|timeshift-btrfs:vm) ;;
    none:btrfs|none:vm) ;;
    none:f2fs)
      plan_snapshot_input=$(installer_cmdline_value snapshots 2>/dev/null || true)
      [ "$plan_snapshot_input" = none ] || installer_fatal 'F2FS requires explicit snapshots=none; no filesystem is changed'
      ;;
    *) installer_fatal 'snapshot policy conflicts with the selected filesystem' ;;
  esac
  plan_graph=$(installer_class_metadata_read_path FILE_PLAN_GRAPH) || exit "$?"
  plan_resolver=$(installer_class_metadata_read_path FILE_PLAN_RESOLVER) || exit "$?"
  plan_path=$(installer_class_plan_path)
  plan_crypto_root=${INSTALLER_PROFILE_CRYPTO_LUKS2_ROOT:?explicit root crypto boolean required}
  plan_crypto_home=${INSTALLER_PROFILE_CRYPTO_LUKS2_HOME:?explicit home crypto boolean required}
  plan_wifi_enable=${INSTALLER_PROFILE_WIFI_ENABLE:?explicit Wi-Fi boolean required}
  plan_primary_iface=${INSTALLER_PROFILE_NETWORK_PRIMARY_IFACE:?primary interface required}
  plan_ipv6_enable=${INSTALLER_PROFILE_IPV6_ENABLE:?IPv6 boolean required}
  plan_ssh_enable=${INSTALLER_PROFILE_SSH_SERVER_ENABLE:?explicit SSH boolean required}
  plan_ssh_port=${INSTALLER_PROFILE_SSH_SERVER_PORT:?explicit SSH port required}
  plan_codex_only=${INSTALLER_PROFILE_CODEX_ONLY_ENABLE:?explicit Codex policy required}
  case "$plan_codex_only" in true|false) ;; *) installer_fatal 'invalid frozen Codex policy' ;; esac
  plan_whisper_enable=${INSTALLER_PROFILE_WHISPER_ENABLE:?explicit Whisper policy required}
  plan_llama_enable=${INSTALLER_PROFILE_LLAMA_ENABLE:?explicit Llama policy required}
  case "$plan_whisper_enable:$plan_llama_enable" in true:true|true:false|false:true|false:false) ;; *) installer_fatal 'invalid frozen AI policy' ;; esac
  plan_key=$(printf '%s\n' "$INSTALLER_SUITE|$plan_roles|$plan_profile|amd64|$INSTALLER_SELECTED_CLASS_REFS|$plan_release|$plan_snapshots|$plan_crypto_root|$plan_crypto_home|$plan_wifi_enable|$plan_primary_iface|$plan_ipv6_enable|$plan_ssh_enable|$plan_ssh_port|$plan_codex_only|$plan_whisper_enable|$plan_llama_enable|$plan_mode|$INSTALLER_PROFILE_PARTMAN_CEILING_ENABLE|$INSTALLER_PROFILE_PARTMAN_CEILING_MB|$INSTALLER_PROFILE_PARTMAN_REUSE_ENABLE|$INSTALLER_PROFILE_PARTMAN_REUSE_START" | source_state_key)
  plan_key=${plan_key%% *}
  if [ -e "$plan_path" ]; then
    [ ! -L "$plan_path" ] && [ "$(installer_plan_value input_key)" = "$plan_key" ] ||
      installer_fatal 'installation inputs changed after the plan was frozen; do not reuse full/base state'
    exit 0
  fi
  plan_lock="${plan_path}.lock"
  mkdir "$plan_lock" || installer_fatal 'installation plan already has an owner; do not recompute concurrently'
  plan_work=$(mktemp "${plan_path}.candidate.XXXXXX") || exit "$?"
  plan_error_file=$(mktemp "${plan_path}.error.XXXXXX") || exit "$?"
  trap 'rm -f "$plan_work" "$plan_error_file"; rmdir "$plan_lock"' 0
  trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
  {
    printf 'input_key\t%s\nrelease\t%s\nprofile\t%s\nfilesystem\t%s\nmode\t%s\nsnapshots\t%s\n' \
      "$plan_key" "$plan_release" "$INSTALLER_HOST_VARIANT/$plan_profile" "$INSTALLER_HOST_FAMILY" "$plan_mode" "$plan_snapshots"
    printf 'crypto_root\t%s\ncrypto_home\t%s\nwifi_enable\t%s\nprimary_iface\t%s\nipv6_enable\t%s\n' \
      "$plan_crypto_root" "$plan_crypto_home" "$plan_wifi_enable" "$plan_primary_iface" "$plan_ipv6_enable"
    printf 'ssh_enable\t%s\nssh_port\t%s\n' "$plan_ssh_enable" "$plan_ssh_port"
    printf 'whisper_enable\t%s\nllama_enable\t%s\n' "$plan_whisper_enable" "$plan_llama_enable"
    printf 'partman_ceiling_enable\t%s\npartman_ceiling_mb\t%s\npartman_reuse_enable\t%s\npartman_reuse_start\t%s\n' \
      "$INSTALLER_PROFILE_PARTMAN_CEILING_ENABLE" "$INSTALLER_PROFILE_PARTMAN_CEILING_MB" \
      "$INSTALLER_PROFILE_PARTMAN_REUSE_ENABLE" "$INSTALLER_PROFILE_PARTMAN_REUSE_START"
    case "$plan_snapshots" in
      timeshift-btrfs) printf 'timeshift_enable\ttrue\n' ;;
      none) printf 'timeshift_enable\tfalse\n' ;;
    esac
    if awk -v suite="$INSTALLER_SUITE" -v roles="$plan_roles" -v family="$INSTALLER_HOST_VARIANT" \
      -v architecture="$INSTALLER_ARCH_CLASS" -v filesystem="$INSTALLER_HOST_FAMILY" \
      -v snapshots="$plan_snapshots" \
      -v profile_codex_only="$plan_codex_only" \
      -v profile_whisper_enable="$plan_whisper_enable" \
      -v profile_llama_enable="$plan_llama_enable" \
      -v refs="$INSTALLER_SELECTED_CLASS_REFS" -v profile_ssh="${INSTALLER_PROFILE_SSH_SERVER_ENABLE:-false}" \
      -f "$plan_resolver" "$plan_graph" 2>"$plan_error_file"; then
      :
    else
      plan_status=$?
      if [ -s "$plan_error_file" ]; then
        installer_redact_log_stream <"$plan_error_file" |
          while IFS= read -r plan_error_line || [ -n "$plan_error_line" ]; do
            [ -n "$plan_error_line" ] || continue
            installer_error "class-plan: $plan_error_line"
          done
      fi
      exit "$plan_status"
    fi
    printf 'reason\tclasses|authenticated physical class files\n'
    for plan_reference in $INSTALLER_SELECTED_CLASS_REFS; do
      printf 'selection\t%s\n' "$plan_reference"
    done
    printf 'phase\tpreseed\nphase\tearly\nphase\tpartman\nphase\tpre-pkgsel\nphase\tlate\nphase\tfirstboot\n'
  } >"$plan_work"
  chmod 0400 "$plan_work" || exit "$?"
  mv "$plan_work" "$plan_path" || exit "$?"
  printf 'ready\n' >"${plan_path}.ready"
  chmod 0400 "${plan_path}.ready"
)

installer_assert_class_plan() {
  plan_path=$(installer_class_plan_path)
  [ -f "$plan_path" ] && [ ! -L "$plan_path" ] &&
    [ -f "${plan_path}.ready" ] && [ ! -L "${plan_path}.ready" ] ||
    installer_fatal 'validated installation plan is unavailable'
  [ "$(installer_plan_value suite)" = "$INSTALLER_SUITE" ] &&
    [ "$(installer_plan_value release)" = "$INSTALLER_RELEASE_ID" ] || installer_fatal 'installation plan/release mismatch'
}

installer_publish_class_receipt() {
  installer_assert_class_plan || return "$?"
  receipt_target=${INSTALLER_TARGET_DIR:-${TARGET_ROOT}}
  receipt_path="$receipt_target${FILE_INSTALLER_CLASSES:?target receipt path required}"
  receipt_parent=${receipt_path%/*}
  install -d -m 0755 "$receipt_parent" || return "$?"
  [ ! -L "$receipt_parent" ] && [ ! -L "$receipt_path" ] || return 1
  receipt_work=$(mktemp "$receipt_parent/.classes.XXXXXX") || return "$?"
  awk -F '\t' '$1 ~ /^(format|suite|role|family|architecture|profile|release|mode|partman_ceiling_enable|partman_ceiling_mb|partman_reuse_enable|partman_reuse_start|snapshots|timeshift_enable|crypto_root|crypto_home|wifi_enable|primary_iface|ipv6_enable|ssh_enable|ssh_port|codex_only_enable|codex_enable|whisper_enable|llama_enable|class|omission)$/ {print}' \
    "$(installer_class_plan_path)" >"$receipt_work" || return "$?"
  chmod 0644 "$receipt_work" && mv -f "$receipt_work" "$receipt_path"
}

# Phase entrypoints and each selected helper use the same release-bound owner
# stamps. An interrupted stage retains .running and may not silently rerun.
installer_phase_stage_begin() {
  case "$1:$2" in
    *[!a-z0-9.:-]*|:*) installer_fatal 'invalid phase stage identity' ;;
  esac
  # Status 1 is reserved for an authenticated completion stamp, never an I/O
  # failure while checking the frozen plan.
  installer_assert_class_plan || return 2
  phase_state="$(installer_runtime_state_dir)/phase-$1-$2"
  if [ -e "${phase_state}.complete" ] || [ -L "${phase_state}.complete" ]; then
    [ -f "${phase_state}.complete" ] && [ ! -L "${phase_state}.complete" ] ||
      installer_fatal 'phase completion stamp has an invalid identity'
    [ "$(cat "${phase_state}.complete")" = "$INSTALLER_RELEASE_ID" ] || installer_fatal 'phase stamp release differs'
    return 1
  fi
  [ ! -e "${phase_state}.running" ] && [ ! -L "${phase_state}.running" ] ||
    installer_fatal "phase outcome is uncertain; retained evidence: $phase_state"
  (umask 077; set -C; printf '%s\n' "$INSTALLER_RELEASE_ID" >"${phase_state}.running") ||
    installer_fatal 'phase stage already has an owner'
  return 0
}

installer_phase_stage_finish() {
  phase_state="$(installer_runtime_state_dir)/phase-$1-$2"
  [ -f "${phase_state}.running" ] && [ ! -L "${phase_state}.running" ] || installer_fatal 'phase stage owner is missing'
  [ "$(cat "${phase_state}.running")" = "$INSTALLER_RELEASE_ID" ] || installer_fatal 'phase stage release changed'
  [ ! -e "${phase_state}.complete" ] && [ ! -L "${phase_state}.complete" ] || installer_fatal 'phase completion already has an owner'
  mv "${phase_state}.running" "${phase_state}.complete"
}

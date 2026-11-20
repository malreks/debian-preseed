#!/bin/sh
# Installer common entrypoint. Policy and implementation live beside this file.
# A standalone cached hook may not have sourced bootstrap.sh in this process.
if ! command -v bootstrap_source_module >/dev/null 2>&1 ||
   ! command -v bootstrap_repo_join_var >/dev/null 2>&1 ||
   ! command -v bootstrap_repo_file_value >/dev/null 2>&1 ||
   ! command -v bootstrap_load_source_library >/dev/null 2>&1 ||
   ! command -v bootstrap_ensure_repo_env >/dev/null 2>&1; then
  [ -s "${INSTALLER_BOOTSTRAP_LIB:-${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}/bootstrap/bootstrap.sh}" ] || {
    printf '%s\n' 'fatal: installer bootstrap is unavailable; start with preseed.cfg' >&2
    return 1
  }
  # shellcheck disable=SC1090
  . "${INSTALLER_BOOTSTRAP_LIB:-${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}/bootstrap/bootstrap.sh}" || return "$?"
fi

bootstrap_load_source_library "${INSTALLER_SOURCE_ROOT:-}" || return "$?"
bootstrap_ensure_repo_env "" || return "$?"

bootstrap_source_module "$(bootstrap_repo_file_value scripts/common/debconf.sh)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value scripts/common/lifecycle.sh)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value scripts/common/apt-sources.sh)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value scripts/common/credentials.sh)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value scripts/common/modules/runtime-console.sh)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value scripts/common/modules/files-logging.sh)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value scripts/common/modules/credentials-probes.sh)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value scripts/common/modules/observability.sh)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value scripts/common/modules/repository-apt.sh)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value scripts/common/modules/profiles.sh)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value scripts/common/modules/app-veth-identity.sh)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value scripts/common/modules/class-plan.sh)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value scripts/common/modules/class-metadata.sh)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value scripts/common/modules/class-selection.sh)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value scripts/common/modules/installation-plan.sh)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value scripts/common/modules/context-target.sh)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value scripts/common/modules/target-publication.sh)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value scripts/common/modules/raw-storage.sh)" || return "$?"

# Resolve source selectors and cache dynamic FILE lookups once per caller shell.
installer_ensure_repo_env "" || return "$?"

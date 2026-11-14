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

bootstrap_source_module "$(bootstrap_repo_file_value FILE_COMMON_DEBCONF)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value FILE_COMMON_LIFECYCLE)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value FILE_COMMON_APT_SOURCES)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value FILE_COMMON_CREDENTIALS)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value FILE_COMMON_MOD_RUNTIME_CONSOLE)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value FILE_COMMON_MOD_FILES_LOGGING)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value FILE_COMMON_MOD_CREDENTIALS_PROBES)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value FILE_COMMON_MOD_OBSERVABILITY)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value FILE_COMMON_MOD_REPOSITORY_APT)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value FILE_COMMON_MOD_PROFILES)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value FILE_COMMON_MOD_APP_VETH_IDENTITY)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value FILE_COMMON_MOD_CLASS_PLAN)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value FILE_COMMON_MOD_CLASS_METADATA)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value FILE_COMMON_MOD_CLASS_SELECTION)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value FILE_COMMON_MOD_INSTALLATION_PLAN)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value FILE_COMMON_MOD_CONTEXT_TARGET)" || return "$?"
bootstrap_source_module "$(bootstrap_repo_file_value FILE_COMMON_MOD_TARGET_PUBLICATION)" || return "$?"

# Resolve source selectors and cache dynamic FILE lookups once per caller shell.
installer_ensure_repo_env "" || return "$?"

#!/bin/sh
# Shared runtime for both filesystem families; loaded after installer bootstrap.
# Definitions only: sourcing does not partition disks or change configuration.
bootstrap_source_module "$(installer_repo_file_value FILE_COMMON_DEBCONF)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value FILE_COMMON_CREDENTIALS)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value FILE_RUNTIME_MOD_BASE)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value FILE_RUNTIME_MOD_CLASSES)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value FILE_RUNTIME_MOD_ARITHMETIC)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value FILE_RUNTIME_MOD_ANSWERS)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value FILE_RUNTIME_MOD_IDENTITY)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value FILE_RUNTIME_MOD_CRYPTO)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value FILE_RUNTIME_MOD_DEVICES)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value FILE_RUNTIME_MOD_LAYOUT_POLICY)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value FILE_RUNTIME_MOD_RECIPES)" || return "$?"
# Only a fully loaded dependency chain is reusable by a family or account
# consumer. runtime_fatal is defined by the first module, before later loads.
RUNTIME_COMMON_READY=1

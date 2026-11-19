#!/bin/sh
# Shared runtime for both filesystem families; loaded after installer bootstrap.
# Definitions only: sourcing does not partition disks or change configuration.
bootstrap_source_module "$(installer_repo_file_value scripts/common/debconf.sh)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value scripts/common/credentials.sh)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value scripts/runtime/modules/base.sh)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value scripts/runtime/modules/classes.sh)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value scripts/runtime/modules/arithmetic.sh)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value scripts/runtime/modules/answers.sh)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value scripts/runtime/modules/identity.sh)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value scripts/runtime/modules/crypto.sh)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value scripts/runtime/modules/devices.sh)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value scripts/runtime/modules/layout-policy.sh)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value scripts/runtime/modules/recipes.sh)" || return "$?"
# Only a fully loaded dependency chain is reusable by a family or account
# consumer. runtime_fatal is defined by the first module, before later loads.
RUNTIME_COMMON_READY=1

#!/bin/sh
# Labwc component definitions, loaded in explicit dependency order.
# The late desktop entrypoint has already initialized the shared bootstrap.

bootstrap_source_module "$(installer_repo_file_value FILE_DESKTOP_COMP_STAGE_ASSETS)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value FILE_DESKTOP_COMP_APPS)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value FILE_DESKTOP_COMP_RELEASE_ASSETS)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value FILE_DESKTOP_COMP_ARTIFACTS_IDENTITIES)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value FILE_DESKTOP_COMP_RENDERING_ACCESS)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value FILE_DESKTOP_COMP_DEVICES_NETWORK)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value FILE_DESKTOP_COMP_DESKTOP_CONFIG)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value FILE_DESKTOP_COMP_GPG_BOOTSTRAP)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value FILE_DESKTOP_COMP_USER_SESSION)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value FILE_DESKTOP_COMP_CORE_RENDERERS_TMPL)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value FILE_DESKTOP_COMP_DESKTOP_HELPERS)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value FILE_DESKTOP_COMP_LOGGING_TMPL)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value FILE_DESKTOP_COMP_COMPZ)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value FILE_DESKTOP_COMP_APPEARANCE)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value FILE_DESKTOP_COMP_TARGET_ASSETS)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value FILE_DESKTOP_COMP_USER_CONFIG)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value FILE_DESKTOP_COMP_SERVICES)" || return "$?"

#!/bin/sh
# Labwc component definitions, loaded in explicit dependency order.
# The late desktop entrypoint has already initialized the shared bootstrap.

bootstrap_source_module "$(installer_repo_file_value scripts/desktop/components/stage-assets.sh)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value scripts/desktop/components/apps.sh)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value scripts/desktop/components/release-assets.sh)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value scripts/desktop/components/artifacts-identities.sh)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value scripts/desktop/components/rendering-access.sh)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value scripts/desktop/components/devices-network.sh)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value scripts/desktop/components/desktop-config.sh)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value scripts/desktop/components/gpg-bootstrap.sh)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value scripts/desktop/components/user-session.sh)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value scripts/desktop/components/core-renderers.sh.tmpl)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value scripts/desktop/components/desktop-helpers.sh)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value scripts/desktop/components/logging.sh.tmpl)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value scripts/desktop/components/compz.sh)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value scripts/desktop/components/appearance.sh)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value scripts/desktop/components/target-assets.sh)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value scripts/desktop/components/user-config.sh)" || return "$?"
bootstrap_source_module "$(installer_repo_file_value scripts/desktop/components/services.sh)" || return "$?"

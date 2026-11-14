#!/bin/sh
# Shared late-command module loader for installer storage families.

late_command_source_module() {
  module_name=$1
  runtime_dir=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
  module_dir=${INSTALLER_LATE_MODULE_DIR:-${runtime_dir}/bootstrap/late-modules}
  module_path="${module_dir}/${module_name}.sh"

  [ -r "$module_path" ] || {
    late_module_message="shared late module is missing: ${module_path}"
    printf '[late-command] fatal: %s\n' "$late_module_message" >&2
    if [ -c /dev/tty4 ] && [ -w /dev/tty4 ]; then
      printf '[late-command] fatal: %s\n' "$late_module_message" >/dev/tty4 || :
    fi
    if command -v logger >/dev/null 2>&1; then
      logger -t preseed-late-command "fatal: $late_module_message" 2>/dev/null || :
    fi
    exit 1
  }

  # shellcheck disable=SC1090
  . "$module_path"
}

for late_module in \
  core \
  target-assets \
  iocost \
  volatile-storage \
  storage-maintenance \
  mullvad \
  templates \
  network \
  network-sharing \
  grub \
  security \
  dbus-broker \
  podman \
  zram-swap \
  btrfs-family \
  f2fs-family \
  account
do
  late_command_source_module "$late_module"
done

if [ -r "${INSTALLER_LATE_MODULE_DIR:-${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}/bootstrap/late-modules}/cuda-legacy.sh" ]; then
  late_command_source_module cuda-legacy
fi

unset late_module

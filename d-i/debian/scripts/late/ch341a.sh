#!/bin/sh
# Desktop CH341A login and GUI integration; the firmware backend is shared.
set -eu
runtime_dir=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
bootstrap_lib=${INSTALLER_BOOTSTRAP_LIB:-${runtime_dir}/bootstrap/bootstrap.sh}
# shellcheck disable=SC1090
. "$bootstrap_lib"
bootstrap_source_common_lib ""
seed_base=$(installer_seed_base "")
installer_ensure_context_loaded "$seed_base"
installer_assert_class_plan
[ "$INSTALLER_HOST_VARIANT" = desktop ] && installer_tools_class_selected || installer_fatal 'desktop firmware integration requires medium/full desktop'
profile="${DIR_INSTALLER_LATE_ENV}/desktop-firmware.env"
installer_fetch_host_env "$seed_base" "$INSTALLER_HOST_PROFILE" "$profile" 0600
installer_load_data_env "$profile"
bootstrap_source_common_support_libs "$seed_base" "${DIR_INSTALLER_LATE_ENV}/desktop-firmware-support" fetch hook target
installer_load_primary_account
printf '%s\n' "$ACCOUNT_USERNAME" | LC_ALL=C grep -Eq '^[a-z_][a-z0-9_-]{0,31}$' || installer_fatal 'invalid desktop firmware operator'
installer_stage_profile_file hooks/target/etc/skel-desktop/.profile.d/75-firmware-workspace.sh.tmpl "${DIR_ETC_SKEL_DESKTOP}/.profile.d/75-firmware-workspace.sh" 0644
# shellcheck disable=SC2016
run_in_target 'publish desktop firmware login profile' "${DIR_USR_BIN}/python3" -I -c '
from pathlib import Path
import os, pwd, stat, sys
account=pwd.getpwnam(sys.argv[1])
if account.pw_uid<1000:
    raise SystemExit("desktop firmware requires a human operator")
parent=Path(account.pw_dir)/".profile.d"
info=parent.lstat()
if not stat.S_ISDIR(info.st_mode) or info.st_uid!=account.pw_uid or info.st_mode&0o077:
    raise SystemExit("unsafe desktop login profile directory")
source=Path(sys.argv[2])
source_info=source.lstat()
if not stat.S_ISREG(source_info.st_mode) or source_info.st_uid or source_info.st_mode&0o022:
    raise SystemExit("untrusted desktop firmware profile source")
output=parent/"75-firmware-workspace.sh"
if output.exists() or output.is_symlink():
    raise SystemExit("desktop firmware login profile already has an owner")
fd=os.open(output,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
with os.fdopen(fd,"wb") as stream:
    stream.write(source.read_bytes());os.fchown(stream.fileno(),account.pw_uid,account.pw_gid)
    stream.flush();os.fsync(stream.fileno())
' "$ACCOUNT_USERNAME" "${DIR_INSTALLER_TARGET_DEFAULTS}/desktop/.profile.d/75-firmware-workspace.sh"
installer_info 'desktop firmware login/GUI integration staged independently of the common backend'

#!/bin/sh
# shellcheck disable=SC2154
# Sourced only by the Software installer after its class/architecture gates.

software_install_tor_media_runtime() {
  # Forky's unversioned libavcodec-extra now selects FFmpeg 9 / ABI 63.
  # The pinned Firefox ESR 140 browser supports ABI 62, not ABI 63. Keep
  # the versioned compatibility libraries alongside the current system FFmpeg.
  # Existing signed repository policy supplies these packages (currently Sid);
  # never add a repository, weaken signature checks or replace the system ABI.
  if ! run_in_target "install Tor Browser compatible FFmpeg runtime" \
    __INSTALLER_PATH_DIR_USR_BIN__/env -i DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    NEEDRESTART_SUSPEND=1 HOME=__INSTALLER_PATH_DIR_ROOT_HOME__ LC_ALL=C.UTF-8 PATH=__INSTALLER_PATH_DIR_USR__/sbin:__INSTALLER_PATH_DIR_USR__/bin:__INSTALLER_PATH_DIR_SBIN__:__INSTALLER_PATH_DIR_BIN__ \
    __INSTALLER_PATH_DIR_USR_BIN__/timeout --signal=TERM --kill-after=5s 300s \
    __INSTALLER_PATH_DIR_USR_BIN__/apt-get -y -o DPkg::Lock::Timeout=60 -o DPkg::Use-Pty=0 \
      --no-remove --no-install-recommends --no-install-suggests \
      install libavcodec62 libavutil60 libswresample6
  then
    software_fatal "Tor Browser requires libavcodec62, libavutil60 and libswresample6 from the configured signed repositories; the unversioned FFmpeg 9 packages do not supply ABI 62"
  fi
}

software_download_tor_browser_asset() {
  tor_asset_label=$1
  tor_primary_url=$2
  tor_archive_url=$3
  tor_asset_destination=$4
  tor_asset_content_policy=$5

  if software_download \
    "$tor_asset_label" \
    "$tor_primary_url" \
    "$tor_asset_destination" \
    "$tor_asset_content_policy" \
    retry
  then
    return 0
  fi

  software_info "${tor_asset_label} primary URL failed; retrying the configured official Tor fallback"
  if software_download \
    "$tor_asset_label" \
    "$tor_archive_url" \
    "$tor_asset_destination" \
    "$tor_asset_content_policy" \
    retry
  then
    return 0
  fi
  software_warn "${tor_asset_label} failed at both official origins after the three-retry budget"
  return 75
}

software_install_tor_browser() (
  tor_version=${SOFTWARE_TOR_BROWSER_VERSION:?SOFTWARE_TOR_BROWSER_VERSION must be set}
  tor_url=${SOFTWARE_TOR_BROWSER_URL:?SOFTWARE_TOR_BROWSER_URL must be set}
  tor_sha=${SOFTWARE_TOR_BROWSER_SHA256:?SOFTWARE_TOR_BROWSER_SHA256 must be set}
  tor_key_sha=${SOFTWARE_TOR_BROWSER_KEY_SHA256:?SOFTWARE_TOR_BROWSER_KEY_SHA256 must be set}
  software_validate_release_version SOFTWARE_TOR_BROWSER_VERSION "$tor_version"
  software_validate_sha256 SOFTWARE_TOR_BROWSER_SHA256 "$tor_sha"
  software_validate_sha256 SOFTWARE_TOR_BROWSER_KEY_SHA256 "$tor_key_sha"
  case "$tor_url" in https://*/*) ;; *) software_fatal "Tor Browser URL must be an HTTPS release URL" ;; esac
  tor_archive_url=${SOFTWARE_TOR_BROWSER_ARCHIVE_FALLBACK_URL:?SOFTWARE_TOR_BROWSER_ARCHIVE_FALLBACK_URL must be set}
  software_install_tor_media_runtime
  tor_archive="${work_dir}/tor-browser.tar.xz"
  tor_signature="${work_dir}/tor-browser.tar.xz.asc"
  tor_key=__INSTALLER_PATH_DIR_USR_LOCAL_SHARE_SOFTWARE__/tor-browser/developers.asc
  tor_install_helper=__INSTALLER_PATH_DIR_USR_LOCAL_LIBEXEC__/tor-browser-install
  software_stage_seed_asset \
    "$(installer_repo_file_value FILE_TARGET_SHARE_SOFTWARE_TOR_BROWSER_DEVELOPERS_ASC)" \
    "$tor_key" 0644
  software_stage_seed_asset \
    "$(installer_repo_file_value FILE_TARGET_LIBEXEC_TOR_BROWSER_INSTALL)" \
    "$tor_install_helper" 0755
  software_download_tor_browser_asset \
    "Tor Browser" \
    "$tor_url" \
    "$tor_archive_url" \
    "$tor_archive" \
    artifact
  software_download_tor_browser_asset \
    "Tor Browser signature" \
    "${tor_url}.asc" \
    "${tor_archive_url}.asc" \
    "$tor_signature" \
    signature
  # Target execution does not inherit installer path variables. Pass the
  # rendered helper and private work directory as data, never shell source.
  run_in_target "authenticate and install Tor Browser" __INSTALLER_PATH_DIR_BIN__/sh -eu -c '
    umask 077
    archive=$1; signature=$2; key=$3; expected=$4; key_expected=$5; fingerprint=$6
    installer=$7; work_dir=$8
    key_actual=$(sha256sum "$key"); [ "${key_actual%% *}" = "$key_expected" ]
    actual=$(sha256sum "$archive"); [ "${actual%% *}" = "$expected" ]
    key_home=$(mktemp -d "$work_dir/tor-verify.XXXXXX")
    trap '\''rm -rf -- "$key_home"'\'' 0
    trap '\''exit 129'\'' HUP
    trap '\''exit 130'\'' INT
    trap '\''exit 143'\'' TERM
    __INSTALLER_PATH_DIR_USR_BIN__/gpg --batch --no-options --homedir "$key_home" --dearmor \
      --output "$key_home/developers.gpg" "$key"
    __INSTALLER_PATH_DIR_USR_BIN__/gpgv --homedir "$key_home" --keyring "$key_home/developers.gpg" \
      --status-fd 1 "$signature" "$archive" >"$key_home/status"
    __INSTALLER_PATH_DIR_USR_BIN__/awk -v expected="$fingerprint" '\''$1 == "[GNUPG:]" && $2 == "VALIDSIG" &&
      ($3 == expected || $NF == expected) { valid++ }
      END { exit valid != 1 }'\'' "$key_home/status"
    __INSTALLER_PATH_DIR_USR_BIN__/python3 -I -B "$installer" "$archive"
  ' sh "$tor_archive" "$tor_signature" "$tor_key" "$tor_sha" "$tor_key_sha" \
    "$SOFTWARE_TOR_BROWSER_SIGNING_FINGERPRINT" "$tor_install_helper" "$work_dir"
  # The root-owned immutable bundle is maintained through release pins and
  # installer publication; never permit a browser-owned binary replacement.
  software_stage_seed_asset \
    "$(installer_repo_file_value FILE_TARGET_OPT_TOR_BROWSER_BROWSER_DISTRIBUTION_POLICIES)" \
    __INSTALLER_PATH_DIR_OPT_TOR_BROWSER__/Browser/distribution/policies.json 0644
  software_stage_seed_asset \
    "$(installer_repo_file_value FILE_TARGET_LIBEXEC_TOR_BROWSER_RUN)" \
    __INSTALLER_PATH_DIR_USR_LOCAL_LIBEXEC__/tor-browser-run 0755
  software_stage_seed_asset \
    "$(installer_repo_file_value FILE_TARGET_APPS_TOR_BROWSER_TMPL)" \
    __INSTALLER_PATH_DIR_USR_LOCAL_SHARE_APPLICATIONS__/tor-browser.desktop 0644
  # Firefox uses the distribution FFmpeg library for H.264/AAC. Check the
  # actual target ABI and decoders, not merely the ffmpeg command's presence.
  # This is installer target execution with dropped privileges, never a host
  # test or a decode of untrusted media. Only APT-owned system libraries load.
  run_in_target "verify Tor Browser system media decoders" \
    __INSTALLER_PATH_DIR_USR_BIN__/env -i PATH=__INSTALLER_PATH_DIR_USR__/bin:__INSTALLER_PATH_DIR_BIN__ LANG=C.UTF-8 \
    __INSTALLER_PATH_DIR_USR_BIN__/timeout --signal=TERM --kill-after=3s 20s \
    __INSTALLER_PATH_DIR_USR_SBIN__/runuser -u "$ACCOUNT_USERNAME" -- __INSTALLER_PATH_DIR_USR_BIN__/python3 -I -B -c '
import ctypes
import os
import subprocess
for package in ("libavcodec62", "libavutil60", "libswresample6"):
    status = subprocess.run(["__INSTALLER_PATH_DIR_USR_BIN__/dpkg-query", "-W", "-f=${Status}", package],
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                            text=True, timeout=3, check=False)
    if status.returncode or status.stdout != "install ok installed":
        raise SystemExit("Tor Browser compatible runtime package is not configured: " + package)
try:
    library = ctypes.CDLL("__INSTALLER_PATH_DIR_USR_LIB__/x86_64-linux-gnu/libavcodec.so.62", mode=os.RTLD_NOW | os.RTLD_LOCAL)
except OSError:
    raise SystemExit("Tor Browser FFmpeg ABI 62 or one of its shared-library dependencies is unavailable; check libavcodec62, libavutil60 and libswresample6") from None
library.avcodec_version.argtypes = []
library.avcodec_version.restype = ctypes.c_uint
if library.avcodec_version() >> 16 != 62:
    raise SystemExit("Tor Browser loaded an incompatible FFmpeg ABI; expected 62")
library.avcodec_find_decoder_by_name.argtypes = [ctypes.c_char_p]
library.avcodec_find_decoder_by_name.restype = ctypes.c_void_p
required = {
    "h264": ("h264",), "aac": ("aac",), "mp3": ("mp3", "mp3float"),
    "flac": ("flac",), "opus": ("opus", "libopus"),
    "vp8": ("vp8", "libvpx"), "vp9": ("vp9", "libvpx-vp9"),
    "av1": ("libdav1d", "libaom-av1", "av1"),
}
missing = [name for name, alternatives in required.items()
           if not any(library.avcodec_find_decoder_by_name(decoder.encode("ascii"))
                      for decoder in alternatives)]
if missing:
    raise SystemExit("Tor Browser system media decoders missing: " + ", ".join(missing))
print("Tor Browser FFmpeg ABI 62 decoder availability: " + ", ".join(required))
'
  chroot "$target_root" __INSTALLER_PATH_DIR_USR_BIN__/desktop-file-validate __INSTALLER_PATH_DIR_USR_LOCAL_SHARE_APPLICATIONS__/tor-browser.desktop
  software_info "installed authenticated Tor Browser version=${tor_version} sha256=${tor_sha}"
)

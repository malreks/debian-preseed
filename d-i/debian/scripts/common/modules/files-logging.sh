#!/bin/sh
# Sourced installer module; edit this file directly.

installer_mounts_find_record() {
  installer_mountpoint=$1
  installer_mounts_file=${2:-/proc/mounts}
  INSTALLER_MOUNT_SOURCE=
  INSTALLER_MOUNT_POINT=
  INSTALLER_MOUNT_FSTYPE=
  INSTALLER_MOUNT_OPTIONS=

  [ -r "$installer_mounts_file" ] || return 1
	  while IFS=' ' read -r mount_source mount_point mount_fstype mount_options _mount_rest || [ -n "${mount_source:-}" ]; do
	    [ "$mount_point" = "$installer_mountpoint" ] || continue
	    INSTALLER_MOUNT_SOURCE=$mount_source
	    INSTALLER_MOUNT_POINT=$mount_point
	    INSTALLER_MOUNT_FSTYPE=$mount_fstype
    INSTALLER_MOUNT_OPTIONS=$mount_options
    return 0
  done <"$installer_mounts_file"
  return 1
}

installer_mounts_has_mountpoint() {
  installer_mounts_find_record "$1" "${2:-/proc/mounts}" >/dev/null 2>&1
}

installer_mount_source_for_mountpoint() {
  installer_mounts_find_record "$1" "${2:-/proc/mounts}" || return 1
  printf '%s\n' "$INSTALLER_MOUNT_SOURCE"
}

installer_target_is_mounted() {
  [ -d ${TARGET_ROOT} ] || return 1
  installer_mounts_has_mountpoint ${TARGET_ROOT} /proc/mounts
}

installer_escape_sed_replacement() {
  printf '%s' "$1" | sed 's/[&|\\]/\\&/g'
}

installer_contains_unresolved_installer_placeholders() {
  installer_placeholder_path=$1

  [ -f "$installer_placeholder_path" ] && [ -r "$installer_placeholder_path" ] || return 2
  # Runtime helpers deliberately contain the bare prefix as a data guard.
  # Require a name character; still reject named markers with a missing suffix
  # or invalid lowercase names instead of accepting a partially rendered file.
  LC_ALL=C grep -Eq '__INSTALLER_[[:alnum:]_]' "$installer_placeholder_path"
}

installer_assert_no_unresolved_installer_placeholders() {
  installer_placeholder_path=$1
  installer_placeholder_label=${2:-$installer_placeholder_path}

  if installer_contains_unresolved_installer_placeholders "$installer_placeholder_path"; then
    :
  else
    installer_placeholder_status=$?
    [ "$installer_placeholder_status" -eq 1 ] && return 0
    installer_fatal "cannot inspect installer placeholders: ${installer_placeholder_label}"
    return 1
  fi

  installer_unresolved_tokens=$(
    LC_ALL=C grep -o '__INSTALLER_[A-Z0-9_]\+__' "$installer_placeholder_path" 2>/dev/null |
      sort -u |
      tr '\n' ' '
  )
  installer_unresolved_tokens=${installer_unresolved_tokens%" "}
  if [ -z "$installer_unresolved_tokens" ]; then
    installer_unresolved_tokens=$(
      LC_ALL=C grep -oE '__INSTALLER_[[:alnum:]_]+' "$installer_placeholder_path" 2>/dev/null |
        sort -u |
        tr '\n' ' '
    )
    installer_unresolved_tokens=${installer_unresolved_tokens%" "}
  fi
  [ -n "$installer_unresolved_tokens" ] || installer_unresolved_tokens="unknown placeholder(s)"
  installer_fatal "${installer_placeholder_label} has unresolved installer placeholders: ${installer_unresolved_tokens}"
}

installer_contains_unresolved_path_placeholders() {
  installer_placeholder_path=$1

  [ -f "$installer_placeholder_path" ] && [ -r "$installer_placeholder_path" ] || return 2
  # Include every canonical runtime-map namespace, including suite policy.
  LC_ALL=C grep -Eq '__INSTALLER_(PATH_[A-Z0-9_]+|APPARMOR_PROFILE_[A-Z0-9_]+|GITBUILD_DISTRIBUTION)__' \
    "$installer_placeholder_path"
}

installer_assert_no_unresolved_path_placeholders() {
  installer_placeholder_path=$1
  installer_placeholder_label=${2:-$installer_placeholder_path}

  if installer_contains_unresolved_path_placeholders "$installer_placeholder_path"; then
    installer_unresolved_tokens=$(
      LC_ALL=C grep -oE '__INSTALLER_(PATH_[A-Z0-9_]+|APPARMOR_PROFILE_[A-Z0-9_]+|GITBUILD_DISTRIBUTION)__' \
        "$installer_placeholder_path" 2>/dev/null |
        sort -u |
        tr '\n' ' '
    )
    installer_unresolved_tokens=${installer_unresolved_tokens%" "}
    [ -n "$installer_unresolved_tokens" ] || installer_unresolved_tokens="unknown path placeholder(s)"
    installer_fatal "${installer_placeholder_label} has unresolved installer path placeholders: ${installer_unresolved_tokens}"
    return 1
  else
    installer_placeholder_status=$?
    [ "$installer_placeholder_status" -eq 1 ] && return 0
    installer_fatal "cannot inspect installer path placeholders: ${installer_placeholder_label}"
    return 1
  fi
}

installer_replace_placeholder_in_file() {
  installer_placeholder_file=$1
  installer_placeholder=$2
  installer_placeholder_value=$3
  installer_placeholder_tmp="${installer_placeholder_file}.replace.$$"
  installer_escaped_placeholder_value=$(installer_escape_sed_replacement "$installer_placeholder_value")

  sed "s|${installer_placeholder}|${installer_escaped_placeholder_value}|g" \
    "$installer_placeholder_file" >"$installer_placeholder_tmp" || {
      rm -f "$installer_placeholder_tmp"
      return 1
    }
  mv "$installer_placeholder_tmp" "$installer_placeholder_file"
}

installer_validate_placeholder_map() {
  installer_placeholder_map=$1
  [ -f "$installer_placeholder_map" ] && [ ! -L "$installer_placeholder_map" ] || return 1
  # Map rows are data, not shell assignments.  Reject duplicate names before
  # any renderer consumes them, and validate the canonical path namespaces
  # before a value can enter a target file or executable.
  LC_ALL=C awk '
    # /dev/stderr is the immutable BusyBox/POSIX diagnostic interface; this
    # validator runs before the target path map is available.
    function invalid(message) { print "fatal: " message > "/dev/stderr"; status = 1 }
    {
      separator = index($0, "=")
      if (separator < 2) { invalid("malformed placeholder map row"); next }
      name = substr($0, 1, separator - 1)
      value = substr($0, separator + 1)
      if (name !~ /^[A-Z][A-Z0-9_]*$/) invalid("invalid placeholder map key")
      if (name in seen) invalid("duplicate placeholder map key: " name)
      seen[name] = 1
      if (value == "" || value ~ /[\r\n]/) invalid("empty or multiline placeholder map value: " name)
      if (name ~ /^PATH_(DIR_|FILE_)/) {
        if (value !~ /^\// || value ~ /[^A-Za-z0-9_./@+ -]/ || value ~ /(^|\/)\.\.?($|\/)|\/\// || (value != "/" && value ~ /\/$/))
          invalid("non-normalized path placeholder value: " name)
      } else if (name ~ /^APPARMOR_PROFILE_/) {
        if (value !~ /^[A-Za-z0-9_.-]+$/) invalid("invalid AppArmor profile value: " name)
      } else if (name == "GITBUILD_DISTRIBUTION") {
        if (value !~ /^[a-z][a-z0-9.-]*$/) invalid("invalid distribution value")
      }
    }
    END { exit status }
  ' "$installer_placeholder_map"
}

installer_runtime_path_placeholder_map() {
  [ -n "${DIR_APT_STATE:-}" ] && printf 'PATH_DIR_APT_STATE=%s\n' "$DIR_APT_STATE"
  # Emit only validated, non-empty values. Missing values leave their token
  # unresolved so the publication boundary fails closed instead of writing an
  # empty path into a target executable, unit, or policy.
  [ -n "${DIR_ETC:-}" ] && printf 'PATH_DIR_ETC=%s\n' "$DIR_ETC"
  [ -n "${DIR_BIN:-}" ] && printf 'PATH_DIR_BIN=%s\n' "$DIR_BIN"
  [ -n "${DIR_SBIN:-}" ] && printf 'PATH_DIR_SBIN=%s\n' "$DIR_SBIN"
  [ -n "${DIR_LIB:-}" ] && printf 'PATH_DIR_LIB=%s\n' "$DIR_LIB"
  [ -n "${DIR_LIB64:-}" ] && printf 'PATH_DIR_LIB64=%s\n' "$DIR_LIB64"
  [ -n "${DIR_USR:-}" ] && printf 'PATH_DIR_USR=%s\n' "$DIR_USR"
  [ -n "${DIR_USR_BIN:-}" ] && printf 'PATH_DIR_USR_BIN=%s\n' "$DIR_USR_BIN"
  [ -n "${DIR_USR_SBIN:-}" ] && printf 'PATH_DIR_USR_SBIN=%s\n' "$DIR_USR_SBIN"
  [ -n "${DIR_USR_LIB:-}" ] && printf 'PATH_DIR_USR_LIB=%s\n' "$DIR_USR_LIB"
  [ -n "${DIR_USR_LIBEXEC:-}" ] && printf 'PATH_DIR_USR_LIBEXEC=%s\n' "$DIR_USR_LIBEXEC"
  [ -n "${DIR_USR_SHARE:-}" ] && printf 'PATH_DIR_USR_SHARE=%s\n' "$DIR_USR_SHARE"
  [ -n "${DIR_USR_SHARE_APPLICATIONS:-}" ] && printf 'PATH_DIR_USR_SHARE_APPLICATIONS=%s\n' "$DIR_USR_SHARE_APPLICATIONS"
  [ -n "${DIR_USR_SHARE_ICONS:-}" ] && printf 'PATH_DIR_USR_SHARE_ICONS=%s\n' "$DIR_USR_SHARE_ICONS"
  [ -n "${DIR_USR_SHARE_ICONS_HICOLOR:-}" ] && printf 'PATH_DIR_USR_SHARE_ICONS_HICOLOR=%s\n' "$DIR_USR_SHARE_ICONS_HICOLOR"
  [ -n "${DIR_USR_SHARE_ICONS_HICOLOR_512_APPS:-}" ] && printf 'PATH_DIR_USR_SHARE_ICONS_HICOLOR_512_APPS=%s\n' "$DIR_USR_SHARE_ICONS_HICOLOR_512_APPS"
  [ -n "${DIR_USR_SHARE_DOC:-}" ] && printf 'PATH_DIR_USR_SHARE_DOC=%s\n' "$DIR_USR_SHARE_DOC"
  [ -n "${DIR_USR_SHARE_FONTS:-}" ] && printf 'PATH_DIR_USR_SHARE_FONTS=%s\n' "$DIR_USR_SHARE_FONTS"
  [ -n "${DIR_USR_SHARE_MIME:-}" ] && printf 'PATH_DIR_USR_SHARE_MIME=%s\n' "$DIR_USR_SHARE_MIME"
  [ -n "${DIR_USR_SHARE_KEYRINGS:-}" ] && printf 'PATH_DIR_USR_SHARE_KEYRINGS=%s\n' "$DIR_USR_SHARE_KEYRINGS"
  [ -n "${DIR_USR_SHARE_X11:-}" ] && printf 'PATH_DIR_USR_SHARE_X11=%s\n' "$DIR_USR_SHARE_X11"
  [ -n "${DIR_USR_SHARE_XKB:-}" ] && printf 'PATH_DIR_USR_SHARE_XKB=%s\n' "$DIR_USR_SHARE_XKB"
  [ -n "${DIR_USR_SHARE_XKB_CONFIG:-}" ] && printf 'PATH_DIR_USR_SHARE_XKB_CONFIG=%s\n' "$DIR_USR_SHARE_XKB_CONFIG"
  [ -n "${DIR_USR_SHARE_BACKGROUNDS:-}" ] && printf 'PATH_DIR_USR_SHARE_BACKGROUNDS=%s\n' "$DIR_USR_SHARE_BACKGROUNDS"
  [ -n "${DIR_USR_SHARE_BACKGROUNDS_DESKTOP:-}" ] && printf 'PATH_DIR_USR_SHARE_BACKGROUNDS_DESKTOP=%s\n' "$DIR_USR_SHARE_BACKGROUNDS_DESKTOP"
  [ -n "${DIR_USR_SHARE_BACKGROUNDS_LOGIN:-}" ] && printf 'PATH_DIR_USR_SHARE_BACKGROUNDS_LOGIN=%s\n' "$DIR_USR_SHARE_BACKGROUNDS_LOGIN"
  [ -n "${DIR_USR_SHARE_BACKGROUNDS_OTHER:-}" ] && printf 'PATH_DIR_USR_SHARE_BACKGROUNDS_OTHER=%s\n' "$DIR_USR_SHARE_BACKGROUNDS_OTHER"
  [ -n "${DIR_USR_SHARE_GLIB:-}" ] && printf 'PATH_DIR_USR_SHARE_GLIB=%s\n' "$DIR_USR_SHARE_GLIB"
  [ -n "${DIR_USR_SHARE_GLIB_SCHEMAS:-}" ] && printf 'PATH_DIR_USR_SHARE_GLIB_SCHEMAS=%s\n' "$DIR_USR_SHARE_GLIB_SCHEMAS"
  [ -n "${DIR_USR_SHARE_GVFS:-}" ] && printf 'PATH_DIR_USR_SHARE_GVFS=%s\n' "$DIR_USR_SHARE_GVFS"
  [ -n "${DIR_USR_SHARE_GVFS_REMOTE_VOLUME_MONITORS:-}" ] && printf 'PATH_DIR_USR_SHARE_GVFS_REMOTE_VOLUME_MONITORS=%s\n' "$DIR_USR_SHARE_GVFS_REMOTE_VOLUME_MONITORS"
  [ -n "${DIR_USR_SHARE_MIME_PACKAGES:-}" ] && printf 'PATH_DIR_USR_SHARE_MIME_PACKAGES=%s\n' "$DIR_USR_SHARE_MIME_PACKAGES"
  [ -n "${DIR_USR_SHARE_PAM_CONFIGS:-}" ] && printf 'PATH_DIR_USR_SHARE_PAM_CONFIGS=%s\n' "$DIR_USR_SHARE_PAM_CONFIGS"
  [ -n "${DIR_USR_SHARE_PIXMAPS:-}" ] && printf 'PATH_DIR_USR_SHARE_PIXMAPS=%s\n' "$DIR_USR_SHARE_PIXMAPS"
  [ -n "${DIR_USR_SHARE_POLKIT:-}" ] && printf 'PATH_DIR_USR_SHARE_POLKIT=%s\n' "$DIR_USR_SHARE_POLKIT"
  [ -n "${DIR_USR_SHARE_POLKIT_ACTIONS:-}" ] && printf 'PATH_DIR_USR_SHARE_POLKIT_ACTIONS=%s\n' "$DIR_USR_SHARE_POLKIT_ACTIONS"
  [ -n "${DIR_USR_SHARE_WAYLAND_SESSIONS:-}" ] && printf 'PATH_DIR_USR_SHARE_WAYLAND_SESSIONS=%s\n' "$DIR_USR_SHARE_WAYLAND_SESSIONS"
  [ -n "${DIR_USR_SHARE_WIREPLUMBER:-}" ] && printf 'PATH_DIR_USR_SHARE_WIREPLUMBER=%s\n' "$DIR_USR_SHARE_WIREPLUMBER"
  [ -n "${DIR_USR_SHARE_WIREPLUMBER_SCRIPTS:-}" ] && printf 'PATH_DIR_USR_SHARE_WIREPLUMBER_SCRIPTS=%s\n' "$DIR_USR_SHARE_WIREPLUMBER_SCRIPTS"
  [ -n "${DIR_USR_SHARE_XFCE4:-}" ] && printf 'PATH_DIR_USR_SHARE_XFCE4=%s\n' "$DIR_USR_SHARE_XFCE4"
  [ -n "${DIR_USR_SHARE_XFCE4_HELPERS:-}" ] && printf 'PATH_DIR_USR_SHARE_XFCE4_HELPERS=%s\n' "$DIR_USR_SHARE_XFCE4_HELPERS"
  [ -n "${DIR_USR_LOCAL:-}" ] && printf 'PATH_DIR_USR_LOCAL=%s\n' "$DIR_USR_LOCAL"
  [ -n "${DIR_USR_LOCAL_BIN:-}" ] && printf 'PATH_DIR_USR_LOCAL_BIN=%s\n' "$DIR_USR_LOCAL_BIN"
  [ -n "${DIR_USR_LOCAL_SBIN:-}" ] && printf 'PATH_DIR_USR_LOCAL_SBIN=%s\n' "$DIR_USR_LOCAL_SBIN"
  [ -n "${FILE_ACCOUNT_CREATE:-}" ] && printf 'PATH_FILE_ACCOUNT_CREATE=%s\n' "$FILE_ACCOUNT_CREATE"
  [ -n "${DIR_USR_LOCAL_LIB:-}" ] && printf 'PATH_DIR_USR_LOCAL_LIB=%s\n' "$DIR_USR_LOCAL_LIB"
  [ -n "${DIR_USR_LOCAL_LIBEXEC:-}" ] && printf 'PATH_DIR_USR_LOCAL_LIBEXEC=%s\n' "$DIR_USR_LOCAL_LIBEXEC"
  [ -n "${DIR_USR_LOCAL_SHARE:-}" ] && printf 'PATH_DIR_USR_LOCAL_SHARE=%s\n' "$DIR_USR_LOCAL_SHARE"
  [ -n "${DIR_USR_LOCAL_SHARE_AGENDA:-}" ] && printf 'PATH_DIR_USR_LOCAL_SHARE_AGENDA=%s\n' "$DIR_USR_LOCAL_SHARE_AGENDA"
  [ -n "${DIR_USR_LOCAL_SHARE_AGENDA_SCHEMAS:-}" ] && printf 'PATH_DIR_USR_LOCAL_SHARE_AGENDA_SCHEMAS=%s\n' "$DIR_USR_LOCAL_SHARE_AGENDA_SCHEMAS"
  [ -n "${DIR_USR_LOCAL_SHARE_APPLICATIONS:-}" ] && printf 'PATH_DIR_USR_LOCAL_SHARE_APPLICATIONS=%s\n' "$DIR_USR_LOCAL_SHARE_APPLICATIONS"
  [ -n "${DIR_USR_LOCAL_SHARE_DEBUGSYS:-}" ] && printf 'PATH_DIR_USR_LOCAL_SHARE_DEBUGSYS=%s\n' "$DIR_USR_LOCAL_SHARE_DEBUGSYS"
  [ -n "${DIR_USR_LOCAL_SHARE_DEBUGSYS_INITRAMFS:-}" ] && printf 'PATH_DIR_USR_LOCAL_SHARE_DEBUGSYS_INITRAMFS=%s\n' "$DIR_USR_LOCAL_SHARE_DEBUGSYS_INITRAMFS"
  [ -n "${DIR_USR_LOCAL_SHARE_DEVOPS:-}" ] && printf 'PATH_DIR_USR_LOCAL_SHARE_DEVOPS=%s\n' "$DIR_USR_LOCAL_SHARE_DEVOPS"
  [ -n "${DIR_USR_LOCAL_SHARE_DEVOPS_TEMPLATES:-}" ] && printf 'PATH_DIR_USR_LOCAL_SHARE_DEVOPS_TEMPLATES=%s\n' "$DIR_USR_LOCAL_SHARE_DEVOPS_TEMPLATES"
  [ -n "${DIR_USR_LOCAL_SHARE_DOC:-}" ] && printf 'PATH_DIR_USR_LOCAL_SHARE_DOC=%s\n' "$DIR_USR_LOCAL_SHARE_DOC"
  [ -n "${DIR_USR_LOCAL_SHARE_DOC_GIT:-}" ] && printf 'PATH_DIR_USR_LOCAL_SHARE_DOC_GIT=%s\n' "$DIR_USR_LOCAL_SHARE_DOC_GIT"
  [ -n "${DIR_USR_LOCAL_SHARE_DOC_YT_DLP:-}" ] && printf 'PATH_DIR_USR_LOCAL_SHARE_DOC_YT_DLP=%s\n' "$DIR_USR_LOCAL_SHARE_DOC_YT_DLP"
  [ -n "${DIR_USR_LOCAL_SHARE_GITBUILD:-}" ] && printf 'PATH_DIR_USR_LOCAL_SHARE_GITBUILD=%s\n' "$DIR_USR_LOCAL_SHARE_GITBUILD"
  [ -n "${DIR_USR_LOCAL_SHARE_GRUB_PROFILES:-}" ] && printf 'PATH_DIR_USR_LOCAL_SHARE_GRUB_PROFILES=%s\n' "$DIR_USR_LOCAL_SHARE_GRUB_PROFILES"
  [ -n "${DIR_USR_LOCAL_SHARE_ICONS:-}" ] && printf 'PATH_DIR_USR_LOCAL_SHARE_ICONS=%s\n' "$DIR_USR_LOCAL_SHARE_ICONS"
  [ -n "${DIR_USR_LOCAL_SHARE_ICONS_HICOLOR:-}" ] && printf 'PATH_DIR_USR_LOCAL_SHARE_ICONS_HICOLOR=%s\n' "$DIR_USR_LOCAL_SHARE_ICONS_HICOLOR"
  [ -n "${DIR_USR_LOCAL_SHARE_LABWC_AI_COPILOTS:-}" ] && printf 'PATH_DIR_USR_LOCAL_SHARE_LABWC_AI_COPILOTS=%s\n' "$DIR_USR_LOCAL_SHARE_LABWC_AI_COPILOTS"
  [ -n "${DIR_USR_LOCAL_SHARE_LABWC_APPEARANCE:-}" ] && printf 'PATH_DIR_USR_LOCAL_SHARE_LABWC_APPEARANCE=%s\n' "$DIR_USR_LOCAL_SHARE_LABWC_APPEARANCE"
  [ -n "${DIR_USR_LOCAL_SHARE_LABWC_GREETER:-}" ] && printf 'PATH_DIR_USR_LOCAL_SHARE_LABWC_GREETER=%s\n' "$DIR_USR_LOCAL_SHARE_LABWC_GREETER"
  [ -n "${DIR_USR_LOCAL_SHARE_LABWC_HELP:-}" ] && printf 'PATH_DIR_USR_LOCAL_SHARE_LABWC_HELP=%s\n' "$DIR_USR_LOCAL_SHARE_LABWC_HELP"
  [ -n "${DIR_USR_LOCAL_SHARE_LABWC_HELP_ARTICLES:-}" ] && printf 'PATH_DIR_USR_LOCAL_SHARE_LABWC_HELP_ARTICLES=%s\n' "$DIR_USR_LOCAL_SHARE_LABWC_HELP_ARTICLES"
  [ -n "${DIR_USR_LOCAL_SHARE_NMAP:-}" ] && printf 'PATH_DIR_USR_LOCAL_SHARE_NMAP=%s\n' "$DIR_USR_LOCAL_SHARE_NMAP"
  [ -n "${DIR_USR_LOCAL_SHARE_NMAP_SCRIPTS:-}" ] && printf 'PATH_DIR_USR_LOCAL_SHARE_NMAP_SCRIPTS=%s\n' "$DIR_USR_LOCAL_SHARE_NMAP_SCRIPTS"
  [ -n "${DIR_USR_LOCAL_SHARE_SOFTWARE:-}" ] && printf 'PATH_DIR_USR_LOCAL_SHARE_SOFTWARE=%s\n' "$DIR_USR_LOCAL_SHARE_SOFTWARE"
  [ -n "${DIR_USR_LOCAL_SHARE_SOFTWARE_LEDGER:-}" ] && printf 'PATH_DIR_USR_LOCAL_SHARE_SOFTWARE_LEDGER=%s\n' "$DIR_USR_LOCAL_SHARE_SOFTWARE_LEDGER"
  [ -n "${DIR_USR_LOCAL_SHARE_SOFTWARE_CHATGPT:-}" ] && printf 'PATH_DIR_USR_LOCAL_SHARE_SOFTWARE_CHATGPT=%s\n' "$DIR_USR_LOCAL_SHARE_SOFTWARE_CHATGPT"
  [ -n "${DIR_USR_LOCAL_SHARE_SOFTWARE_TOR_BROWSER:-}" ] && printf 'PATH_DIR_USR_LOCAL_SHARE_SOFTWARE_TOR_BROWSER=%s\n' "$DIR_USR_LOCAL_SHARE_SOFTWARE_TOR_BROWSER"
  [ -n "${DIR_USR_LOCAL_SHARE_SOFTWARE_TUTA:-}" ] && printf 'PATH_DIR_USR_LOCAL_SHARE_SOFTWARE_TUTA=%s\n' "$DIR_USR_LOCAL_SHARE_SOFTWARE_TUTA"
  [ -n "${DIR_VAR:-}" ] && printf 'PATH_DIR_VAR=%s\n' "$DIR_VAR"
  [ -n "${DIR_RUN:-}" ] && printf 'PATH_DIR_RUN=%s\n' "$DIR_RUN"
  [ -n "${DIR_RUN_LOCK:-}" ] && printf 'PATH_DIR_RUN_LOCK=%s\n' "$DIR_RUN_LOCK"
  [ -n "${DIR_RUN_USER:-}" ] && printf 'PATH_DIR_RUN_USER=%s\n' "$DIR_RUN_USER"
  [ -n "${DIR_RUN_DBUS:-}" ] && printf 'PATH_DIR_RUN_DBUS=%s\n' "$DIR_RUN_DBUS"
  [ -n "${DIR_RUN_SYSTEMD:-}" ] && printf 'PATH_DIR_RUN_SYSTEMD=%s\n' "$DIR_RUN_SYSTEMD"
  [ -n "${DIR_TMP:-}" ] && printf 'PATH_DIR_TMP=%s\n' "$DIR_TMP"
  [ -n "${DIR_DEV:-}" ] && printf 'PATH_DIR_DEV=%s\n' "$DIR_DEV"
  [ -n "${DIR_DEV_SHM:-}" ] && printf 'PATH_DIR_DEV_SHM=%s\n' "$DIR_DEV_SHM"
  [ -n "${DIR_PROC:-}" ] && printf 'PATH_DIR_PROC=%s\n' "$DIR_PROC"
  [ -n "${DIR_VAR_LIB_SOFTWARE_REPO_POOL:-}" ] && printf 'PATH_DIR_VAR_LIB_SOFTWARE_REPO_POOL=%s\n' "$DIR_VAR_LIB_SOFTWARE_REPO_POOL"
  [ -n "${DIR_SYS:-}" ] && printf 'PATH_DIR_SYS=%s\n' "$DIR_SYS"
  [ -n "${DIR_ROOT_HOME:-}" ] && printf 'PATH_DIR_ROOT_HOME=%s\n' "$DIR_ROOT_HOME"
  [ -n "${DIR_HOME:-}" ] && printf 'PATH_DIR_HOME=%s\n' "$DIR_HOME"
  [ -n "${DIR_BOOT:-}" ] && printf 'PATH_DIR_BOOT=%s\n' "$DIR_BOOT"
  [ -n "${DIR_MEDIA:-}" ] && printf 'PATH_DIR_MEDIA=%s\n' "$DIR_MEDIA"
  [ -n "${DIR_MEDIA_CDROM:-}" ] && printf 'PATH_DIR_MEDIA_CDROM=%s\n' "$DIR_MEDIA_CDROM"
  [ -n "${DIR_OPT:-}" ] && printf 'PATH_DIR_OPT=%s\n' "$DIR_OPT"
  [ -n "${DIR_SRV:-}" ] && printf 'PATH_DIR_SRV=%s\n' "$DIR_SRV"
  [ -n "${DIR_POOL:-}" ] && printf 'PATH_DIR_POOL=%s\n' "$DIR_POOL"
  [ -n "${DIR_POOL_TMP:-}" ] && printf 'PATH_DIR_POOL_TMP=%s\n' "$DIR_POOL_TMP"
  [ -n "${GITBUILD_DISTRIBUTION:-}" ] && printf 'GITBUILD_DISTRIBUTION=%s\n' "$GITBUILD_DISTRIBUTION"
  [ -n "${DIR_DATA:-}" ] && printf 'PATH_DIR_DATA=%s\n' "$DIR_DATA"
  [ -n "${DIR_VAR_LIB:-}" ] && printf 'PATH_DIR_VAR_LIB=%s\n' "$DIR_VAR_LIB"
  [ -n "${DIR_ACCOUNT_PROVISIONING:-}" ] && printf 'PATH_DIR_ACCOUNT_PROVISIONING=%s\n' "$DIR_ACCOUNT_PROVISIONING"
  [ -n "${DIR_VAR_LIB_SHSIGNED:-}" ] && printf 'PATH_DIR_VAR_LIB_SHSIGNED=%s\n' "$DIR_VAR_LIB_SHSIGNED"
  [ -n "${DIR_VAR_LIB_DBUS:-}" ] && printf 'PATH_DIR_VAR_LIB_DBUS=%s\n' "$DIR_VAR_LIB_DBUS"
  [ -n "${DIR_VAR_LIB_SOFTWARE:-}" ] && printf 'PATH_DIR_VAR_LIB_SOFTWARE=%s\n' "$DIR_VAR_LIB_SOFTWARE"
  [ -n "${DIR_VAR_LIB_SOFTWARE_REPO:-}" ] && printf 'PATH_DIR_VAR_LIB_SOFTWARE_REPO=%s\n' "$DIR_VAR_LIB_SOFTWARE_REPO"
  [ -n "${DIR_VAR_LIB_SOFTWARE_INBOX:-}" ] && printf 'PATH_DIR_VAR_LIB_SOFTWARE_INBOX=%s\n' "$DIR_VAR_LIB_SOFTWARE_INBOX"
  [ -n "${DIR_VAR_LIB_TAILSCALE:-}" ] && printf 'PATH_DIR_VAR_LIB_TAILSCALE=%s\n' "$DIR_VAR_LIB_TAILSCALE"
  [ -n "${DIR_VAR_LIB_CROWDSEC:-}" ] && printf 'PATH_DIR_VAR_LIB_CROWDSEC=%s\n' "$DIR_VAR_LIB_CROWDSEC"
  [ -n "${DIR_VAR_LIB_SYSTEMD_USER:-}" ] && printf 'PATH_DIR_VAR_LIB_SYSTEMD_USER=%s\n' "$DIR_VAR_LIB_SYSTEMD_USER"
  [ -n "${DIR_VAR_LIB_INSTALLER_STATE:-}" ] && printf 'PATH_DIR_VAR_LIB_INSTALLER_STATE=%s\n' "$DIR_VAR_LIB_INSTALLER_STATE"
  [ -n "${DIR_TMPFILES_POLICY_RECOVERY:-}" ] && printf 'PATH_DIR_TMPFILES_POLICY_RECOVERY=%s\n' "$DIR_TMPFILES_POLICY_RECOVERY"
  [ -n "${FILE_TMPFILES_POLICY_LOCK:-}" ] && printf 'PATH_FILE_TMPFILES_POLICY_LOCK=%s\n' "$FILE_TMPFILES_POLICY_LOCK"
  [ -n "${DIR_ETC_SNANDER:-}" ] && printf 'PATH_DIR_ETC_SNANDER=%s\n' "$DIR_ETC_SNANDER"
  [ -n "${DIR_SNANDER_RELEASES:-}" ] && printf 'PATH_DIR_SNANDER_RELEASES=%s\n' "$DIR_SNANDER_RELEASES"
  [ -n "${DIR_SNANDER_STATE:-}" ] && printf 'PATH_DIR_SNANDER_STATE=%s\n' "$DIR_SNANDER_STATE"
  [ -n "${FILE_SNANDER_POLICY:-}" ] && printf 'PATH_FILE_SNANDER_POLICY=%s\n' "$FILE_SNANDER_POLICY"
  [ -n "${FILE_SNANDER_LOCK:-}" ] && printf 'PATH_FILE_SNANDER_LOCK=%s\n' "$FILE_SNANDER_LOCK"
  [ -n "${FILE_SNANDER_PENDING:-}" ] && printf 'PATH_FILE_SNANDER_PENDING=%s\n' "$FILE_SNANDER_PENDING"
  [ -n "${DIR_INCUS_BOOTSTRAP_STATE:-}" ] && printf 'PATH_DIR_INCUS_BOOTSTRAP_STATE=%s\n' "$DIR_INCUS_BOOTSTRAP_STATE"
  [ -n "${FILE_INCUS_BOOTSTRAP_JOURNAL:-}" ] && printf 'PATH_FILE_INCUS_BOOTSTRAP_JOURNAL=%s\n' "$FILE_INCUS_BOOTSTRAP_JOURNAL"
  [ -n "${FILE_CRYPTO_MUTATION:-}" ] && printf 'PATH_FILE_CRYPTO_MUTATION=%s\n' "$FILE_CRYPTO_MUTATION"
  [ -n "${FILE_CRYPTO_DEVICE_SESSION:-}" ] && printf 'PATH_FILE_CRYPTO_DEVICE_SESSION=%s\n' "$FILE_CRYPTO_DEVICE_SESSION"
  [ -n "${FILE_CRYPTO_BOOT_ARTIFACTS_CLEANED:-}" ] && printf 'PATH_FILE_CRYPTO_BOOT_ARTIFACTS_CLEANED=%s\n' "$FILE_CRYPTO_BOOT_ARTIFACTS_CLEANED"
  [ -n "${DIR_STATE_LOG:-}" ] && printf 'PATH_DIR_STATE_LOG=%s\n' "$DIR_STATE_LOG"
  [ -n "${DIR_INSTALL_LOG:-}" ] && printf 'PATH_DIR_INSTALL_LOG=%s\n' "$DIR_INSTALL_LOG"
  [ -n "${DIR_ETC_DEFAULT:-}" ] && printf 'PATH_DIR_ETC_DEFAULT=%s\n' "$DIR_ETC_DEFAULT"
  [ -n "${DIR_ETC_AUDIT:-}" ] && printf 'PATH_DIR_ETC_AUDIT=%s\n' "$DIR_ETC_AUDIT"
  [ -n "${DIR_ETC_AUDIT_CROWDSEC:-}" ] && printf 'PATH_DIR_ETC_AUDIT_CROWDSEC=%s\n' "$DIR_ETC_AUDIT_CROWDSEC"
  [ -n "${DIR_ETC_AUDIT_RULES:-}" ] && printf 'PATH_DIR_ETC_AUDIT_RULES=%s\n' "$DIR_ETC_AUDIT_RULES"
  [ -n "${DIR_ETC_BLUETOOTH:-}" ] && printf 'PATH_DIR_ETC_BLUETOOTH=%s\n' "$DIR_ETC_BLUETOOTH"
  [ -n "${DIR_ETC_CHATGPT:-}" ] && printf 'PATH_DIR_ETC_CHATGPT=%s\n' "$DIR_ETC_CHATGPT"
  [ -n "${DIR_ETC_CHROMIUM:-}" ] && printf 'PATH_DIR_ETC_CHROMIUM=%s\n' "$DIR_ETC_CHROMIUM"
  [ -n "${DIR_ETC_CHROMIUM_POLICIES:-}" ] && printf 'PATH_DIR_ETC_CHROMIUM_POLICIES=%s\n' "$DIR_ETC_CHROMIUM_POLICIES"
  [ -n "${DIR_ETC_CHROMIUM_POLICIES_MANAGED:-}" ] && printf 'PATH_DIR_ETC_CHROMIUM_POLICIES_MANAGED=%s\n' "$DIR_ETC_CHROMIUM_POLICIES_MANAGED"
  [ -n "${DIR_ETC_CHROMIUM_POLICIES_RECOMMENDED:-}" ] && printf 'PATH_DIR_ETC_CHROMIUM_POLICIES_RECOMMENDED=%s\n' "$DIR_ETC_CHROMIUM_POLICIES_RECOMMENDED"
  [ -n "${DIR_ETC_CHROMIUM_D:-}" ] && printf 'PATH_DIR_ETC_CHROMIUM_D=%s\n' "$DIR_ETC_CHROMIUM_D"
  [ -n "${DIR_ETC_CODEX:-}" ] && printf 'PATH_DIR_ETC_CODEX=%s\n' "$DIR_ETC_CODEX"
  [ -n "${DIR_ETC_CRON_D:-}" ] && printf 'PATH_DIR_ETC_CRON_D=%s\n' "$DIR_ETC_CRON_D"
  [ -n "${DIR_ETC_CROWDSEC:-}" ] && printf 'PATH_DIR_ETC_CROWDSEC=%s\n' "$DIR_ETC_CROWDSEC"
  [ -n "${DIR_ETC_CROWDSEC_ACQUIS_AVAILABLE:-}" ] && printf 'PATH_DIR_ETC_CROWDSEC_ACQUIS_AVAILABLE=%s\n' "$DIR_ETC_CROWDSEC_ACQUIS_AVAILABLE"
  [ -n "${DIR_ETC_CROWDSEC_ACQUIS_D:-}" ] && printf 'PATH_DIR_ETC_CROWDSEC_ACQUIS_D=%s\n' "$DIR_ETC_CROWDSEC_ACQUIS_D"
  [ -n "${DIR_ETC_CROWDSEC_BOUNCERS:-}" ] && printf 'PATH_DIR_ETC_CROWDSEC_BOUNCERS=%s\n' "$DIR_ETC_CROWDSEC_BOUNCERS"
  [ -n "${DIR_ETC_CROWDSEC_PARSERS:-}" ] && printf 'PATH_DIR_ETC_CROWDSEC_PARSERS=%s\n' "$DIR_ETC_CROWDSEC_PARSERS"
  [ -n "${DIR_ETC_CROWDSEC_SCENARIOS:-}" ] && printf 'PATH_DIR_ETC_CROWDSEC_SCENARIOS=%s\n' "$DIR_ETC_CROWDSEC_SCENARIOS"
  [ -n "${DIR_ETC_CRYPTSETUP_INITRAMFS:-}" ] && printf 'PATH_DIR_ETC_CRYPTSETUP_INITRAMFS=%s\n' "$DIR_ETC_CRYPTSETUP_INITRAMFS"
  [ -n "${DIR_ETC_CREDSTORE:-}" ] && printf 'PATH_DIR_ETC_CREDSTORE=%s\n' "$DIR_ETC_CREDSTORE"
  [ -n "${DIR_ETC_DBUS_SESSION_D:-}" ] && printf 'PATH_DIR_ETC_DBUS_SESSION_D=%s\n' "$DIR_ETC_DBUS_SESSION_D"
  [ -n "${DIR_ETC_DBUS_SYSTEM_D:-}" ] && printf 'PATH_DIR_ETC_DBUS_SYSTEM_D=%s\n' "$DIR_ETC_DBUS_SYSTEM_D"
  [ -n "${DIR_ETC_DPKG:-}" ] && printf 'PATH_DIR_ETC_DPKG=%s\n' "$DIR_ETC_DPKG"
  [ -n "${DIR_ETC_DPKG_CFG_D:-}" ] && printf 'PATH_DIR_ETC_DPKG_CFG_D=%s\n' "$DIR_ETC_DPKG_CFG_D"
  [ -n "${DIR_ETC_ENVIRONMENT_D:-}" ] && printf 'PATH_DIR_ETC_ENVIRONMENT_D=%s\n' "$DIR_ETC_ENVIRONMENT_D"
  [ -n "${DIR_ETC_FAIL2BAN:-}" ] && printf 'PATH_DIR_ETC_FAIL2BAN=%s\n' "$DIR_ETC_FAIL2BAN"
  [ -n "${DIR_ETC_FAIL2BAN_ACTION_D:-}" ] && printf 'PATH_DIR_ETC_FAIL2BAN_ACTION_D=%s\n' "$DIR_ETC_FAIL2BAN_ACTION_D"
  [ -n "${DIR_ETC_FAIL2BAN_FILTER_D:-}" ] && printf 'PATH_DIR_ETC_FAIL2BAN_FILTER_D=%s\n' "$DIR_ETC_FAIL2BAN_FILTER_D"
  [ -n "${DIR_ETC_FAIL2BAN_JAIL_D:-}" ] && printf 'PATH_DIR_ETC_FAIL2BAN_JAIL_D=%s\n' "$DIR_ETC_FAIL2BAN_JAIL_D"
  [ -n "${DIR_ETC_FILEN:-}" ] && printf 'PATH_DIR_ETC_FILEN=%s\n' "$DIR_ETC_FILEN"
  [ -n "${DIR_ETC_GITOPS:-}" ] && printf 'PATH_DIR_ETC_GITOPS=%s\n' "$DIR_ETC_GITOPS"
  [ -n "${DIR_ETC_GREETD:-}" ] && printf 'PATH_DIR_ETC_GREETD=%s\n' "$DIR_ETC_GREETD"
  [ -n "${DIR_ETC_HARDWARE_TUNING:-}" ] && printf 'PATH_DIR_ETC_HARDWARE_TUNING=%s\n' "$DIR_ETC_HARDWARE_TUNING"
  [ -n "${DIR_ETC_INCUS:-}" ] && printf 'PATH_DIR_ETC_INCUS=%s\n' "$DIR_ETC_INCUS"
  [ -n "${DIR_ETC_KEY_MANAGER:-}" ] && printf 'PATH_DIR_ETC_KEY_MANAGER=%s\n' "$DIR_ETC_KEY_MANAGER"
  [ -n "${DIR_ETC_LABWC:-}" ] && printf 'PATH_DIR_ETC_LABWC=%s\n' "$DIR_ETC_LABWC"
  [ -n "${DIR_ETC_LABWC_3PROXY:-}" ] && printf 'PATH_DIR_ETC_LABWC_3PROXY=%s\n' "$DIR_ETC_LABWC_3PROXY"
  [ -n "${DIR_ETC_LLAMA:-}" ] && printf 'PATH_DIR_ETC_LLAMA=%s\n' "$DIR_ETC_LLAMA"
  [ -n "${DIR_ETC_NFS_CONF_D:-}" ] && printf 'PATH_DIR_ETC_NFS_CONF_D=%s\n' "$DIR_ETC_NFS_CONF_D"
  [ -n "${DIR_ETC_NFTABLES:-}" ] && printf 'PATH_DIR_ETC_NFTABLES=%s\n' "$DIR_ETC_NFTABLES"
  [ -n "${DIR_ETC_NFTABLES_D:-}" ] && printf 'PATH_DIR_ETC_NFTABLES_D=%s\n' "$DIR_ETC_NFTABLES_D"
  [ -n "${DIR_ETC_NFTABLES_PROFILES:-}" ] && printf 'PATH_DIR_ETC_NFTABLES_PROFILES=%s\n' "$DIR_ETC_NFTABLES_PROFILES"
  [ -n "${DIR_ETC_NFTABLES_SERVICES:-}" ] && printf 'PATH_DIR_ETC_NFTABLES_SERVICES=%s\n' "$DIR_ETC_NFTABLES_SERVICES"
  [ -n "${DIR_ETC_NETWORK_SHARING:-}" ] && printf 'PATH_DIR_ETC_NETWORK_SHARING=%s\n' "$DIR_ETC_NETWORK_SHARING"
  [ -n "${DIR_ETC_OPT:-}" ] && printf 'PATH_DIR_ETC_OPT=%s\n' "$DIR_ETC_OPT"
  [ -n "${DIR_ETC_OPT_CHROME:-}" ] && printf 'PATH_DIR_ETC_OPT_CHROME=%s\n' "$DIR_ETC_OPT_CHROME"
  [ -n "${DIR_ETC_OPT_CHROME_POLICIES:-}" ] && printf 'PATH_DIR_ETC_OPT_CHROME_POLICIES=%s\n' "$DIR_ETC_OPT_CHROME_POLICIES"
  [ -n "${DIR_ETC_OPT_CHROME_POLICIES_MANAGED:-}" ] && printf 'PATH_DIR_ETC_OPT_CHROME_POLICIES_MANAGED=%s\n' "$DIR_ETC_OPT_CHROME_POLICIES_MANAGED"
  [ -n "${DIR_ETC_OPT_CHROME_POLICIES_RECOMMENDED:-}" ] && printf 'PATH_DIR_ETC_OPT_CHROME_POLICIES_RECOMMENDED=%s\n' "$DIR_ETC_OPT_CHROME_POLICIES_RECOMMENDED"
  [ -n "${DIR_ETC_OPT_EDGE:-}" ] && printf 'PATH_DIR_ETC_OPT_EDGE=%s\n' "$DIR_ETC_OPT_EDGE"
  [ -n "${DIR_ETC_OPT_EDGE_POLICIES:-}" ] && printf 'PATH_DIR_ETC_OPT_EDGE_POLICIES=%s\n' "$DIR_ETC_OPT_EDGE_POLICIES"
  [ -n "${DIR_ETC_OPT_EDGE_POLICIES_MANAGED:-}" ] && printf 'PATH_DIR_ETC_OPT_EDGE_POLICIES_MANAGED=%s\n' "$DIR_ETC_OPT_EDGE_POLICIES_MANAGED"
  [ -n "${DIR_ETC_OPT_EDGE_POLICIES_RECOMMENDED:-}" ] && printf 'PATH_DIR_ETC_OPT_EDGE_POLICIES_RECOMMENDED=%s\n' "$DIR_ETC_OPT_EDGE_POLICIES_RECOMMENDED"
  [ -n "${DIR_ETC_PAM_D:-}" ] && printf 'PATH_DIR_ETC_PAM_D=%s\n' "$DIR_ETC_PAM_D"
  [ -n "${DIR_ETC_PIPEWIRE:-}" ] && printf 'PATH_DIR_ETC_PIPEWIRE=%s\n' "$DIR_ETC_PIPEWIRE"
  [ -n "${DIR_ETC_POLKIT:-}" ] && printf 'PATH_DIR_ETC_POLKIT=%s\n' "$DIR_ETC_POLKIT"
  [ -n "${DIR_ETC_QBITTORRENT:-}" ] && printf 'PATH_DIR_ETC_QBITTORRENT=%s\n' "$DIR_ETC_QBITTORRENT"
  [ -n "${DIR_ETC_QEMU:-}" ] && printf 'PATH_DIR_ETC_QEMU=%s\n' "$DIR_ETC_QEMU"
  [ -n "${DIR_ETC_RKHUNTER_D:-}" ] && printf 'PATH_DIR_ETC_RKHUNTER_D=%s\n' "$DIR_ETC_RKHUNTER_D"
  [ -n "${DIR_ETC_SCX_LOADER:-}" ] && printf 'PATH_DIR_ETC_SCX_LOADER=%s\n' "$DIR_ETC_SCX_LOADER"
  [ -n "${DIR_ETC_SECURITY:-}" ] && printf 'PATH_DIR_ETC_SECURITY=%s\n' "$DIR_ETC_SECURITY"
  [ -n "${DIR_ETC_SSH:-}" ] && printf 'PATH_DIR_ETC_SSH=%s\n' "$DIR_ETC_SSH"
  [ -n "${DIR_ETC_STUBBY:-}" ] && printf 'PATH_DIR_ETC_STUBBY=%s\n' "$DIR_ETC_STUBBY"
  [ -n "${DIR_ETC_SUDOERS_D:-}" ] && printf 'PATH_DIR_ETC_SUDOERS_D=%s\n' "$DIR_ETC_SUDOERS_D"
  [ -n "${DIR_ETC_SYSUSERS_D:-}" ] && printf 'PATH_DIR_ETC_SYSUSERS_D=%s\n' "$DIR_ETC_SYSUSERS_D"
  [ -n "${DIR_ETC_VIVALDI:-}" ] && printf 'PATH_DIR_ETC_VIVALDI=%s\n' "$DIR_ETC_VIVALDI"
  [ -n "${DIR_ETC_WHISPER:-}" ] && printf 'PATH_DIR_ETC_WHISPER=%s\n' "$DIR_ETC_WHISPER"
  [ -n "${DIR_ETC_WIREPLUMBER:-}" ] && printf 'PATH_DIR_ETC_WIREPLUMBER=%s\n' "$DIR_ETC_WIREPLUMBER"
  [ -n "${DIR_ETC_WIREPLUMBER_CONF_D:-}" ] && printf 'PATH_DIR_ETC_WIREPLUMBER_CONF_D=%s\n' "$DIR_ETC_WIREPLUMBER_CONF_D"
  [ -n "${DIR_ETC_XDG:-}" ] && printf 'PATH_DIR_ETC_XDG=%s\n' "$DIR_ETC_XDG"
  [ -n "${DIR_ETC_YT_DLP:-}" ] && printf 'PATH_DIR_ETC_YT_DLP=%s\n' "$DIR_ETC_YT_DLP"
  [ -n "${DIR_NETWORK:-}" ] && printf 'PATH_DIR_NETWORK=%s\n' "$DIR_NETWORK"
  [ -n "${DIR_NETWORK_INTERFACES_D:-}" ] && printf 'PATH_DIR_NETWORK_INTERFACES_D=%s\n' "$DIR_NETWORK_INTERFACES_D"
  [ -n "${DIR_BOOT_EFI:-}" ] && printf 'PATH_DIR_BOOT_EFI=%s\n' "$DIR_BOOT_EFI"
  [ -n "${DIR_TIMESHIFT:-}" ] && printf 'PATH_DIR_TIMESHIFT=%s\n' "$DIR_TIMESHIFT"
  [ -n "${DIR_GRUB_BTRFS_DEFAULT:-}" ] && printf 'PATH_DIR_GRUB_BTRFS_DEFAULT=%s\n' "$DIR_GRUB_BTRFS_DEFAULT"
  [ -n "${DIR_POOL_BUILD:-}" ] && printf 'PATH_DIR_POOL_BUILD=%s\n' "$DIR_POOL_BUILD"
  [ -n "${DIR_POOL_BUILD_RUNNERS:-}" ] && printf 'PATH_DIR_POOL_BUILD_RUNNERS=%s\n' "$DIR_POOL_BUILD_RUNNERS"
  [ -n "${DIR_POOL_CACHE:-}" ] && printf 'PATH_DIR_POOL_CACHE=%s\n' "$DIR_POOL_CACHE"
  [ -n "${DIR_POOL_CACHE_RUNNERS:-}" ] && printf 'PATH_DIR_POOL_CACHE_RUNNERS=%s\n' "$DIR_POOL_CACHE_RUNNERS"
  [ -n "${DIR_POOL_DB:-}" ] && printf 'PATH_DIR_POOL_DB=%s\n' "$DIR_POOL_DB"
  [ -n "${DIR_POOL_QEMU:-}" ] && printf 'PATH_DIR_POOL_QEMU=%s\n' "$DIR_POOL_QEMU"
  [ -n "${DIR_POOL_INCUS:-}" ] && printf 'PATH_DIR_POOL_INCUS=%s\n' "$DIR_POOL_INCUS"
  [ -n "${DIR_POOL_FIRMWARE:-}" ] && printf 'PATH_DIR_POOL_FIRMWARE=%s\n' "$DIR_POOL_FIRMWARE"
  [ -n "${DIR_POOL_PODMAN:-}" ] && printf 'PATH_DIR_POOL_PODMAN=%s\n' "$DIR_POOL_PODMAN"
  [ -n "${DIR_POOL_LOG:-}" ] && printf 'PATH_DIR_POOL_LOG=%s\n' "$DIR_POOL_LOG"
  [ -n "${DIR_POOL_APTLY:-}" ] && printf 'PATH_DIR_POOL_APTLY=%s\n' "$DIR_POOL_APTLY"
  [ -n "${DIR_DATA_CONFIG:-}" ] && printf 'PATH_DIR_DATA_CONFIG=%s\n' "$DIR_DATA_CONFIG"
  [ -n "${DIR_DATA_SERVICES:-}" ] && printf 'PATH_DIR_DATA_SERVICES=%s\n' "$DIR_DATA_SERVICES"
  [ -n "${DIR_DATA_SERVICES_USR:-}" ] && printf 'PATH_DIR_DATA_SERVICES_USR=%s\n' "$DIR_DATA_SERVICES_USR"
  [ -n "${DIR_DATA_BIN:-}" ] && printf 'PATH_DIR_DATA_BIN=%s\n' "$DIR_DATA_BIN"
  [ -n "${DIR_DATA_DOCS:-}" ] && printf 'PATH_DIR_DATA_DOCS=%s\n' "$DIR_DATA_DOCS"
  [ -n "${DIR_DATA_DOWNLOADS:-}" ] && printf 'PATH_DIR_DATA_DOWNLOADS=%s\n' "$DIR_DATA_DOWNLOADS"
  [ -n "${DIR_DATA_PKI:-}" ] && printf 'PATH_DIR_DATA_PKI=%s\n' "$DIR_DATA_PKI"
  [ -n "${DIR_DATA_BACKUP:-}" ] && printf 'PATH_DIR_DATA_BACKUP=%s\n' "$DIR_DATA_BACKUP"
  [ -n "${DIR_DATA_CODEX:-}" ] && printf 'PATH_DIR_DATA_CODEX=%s\n' "$DIR_DATA_CODEX"
  [ -n "${DIR_DATA_CODEX_LIB:-}" ] && printf 'PATH_DIR_DATA_CODEX_LIB=%s\n' "$DIR_DATA_CODEX_LIB"
  [ -n "${DIR_DATA_CONFIG_PODMAN:-}" ] && printf 'PATH_DIR_DATA_CONFIG_PODMAN=%s\n' "$DIR_DATA_CONFIG_PODMAN"
  [ -n "${DIR_DATA_CONFIG_PODMAN_TEMPLATES:-}" ] && printf 'PATH_DIR_DATA_CONFIG_PODMAN_TEMPLATES=%s\n' "$DIR_DATA_CONFIG_PODMAN_TEMPLATES"
  [ -n "${DIR_DATA_CONFIG_PODMAN_TEMPLATES_DEVOPS:-}" ] && printf 'PATH_DIR_DATA_CONFIG_PODMAN_TEMPLATES_DEVOPS=%s\n' "$DIR_DATA_CONFIG_PODMAN_TEMPLATES_DEVOPS"
  [ -n "${DIR_DATA_LLAMA:-}" ] && printf 'PATH_DIR_DATA_LLAMA=%s\n' "$DIR_DATA_LLAMA"
  [ -n "${DIR_DATA_LLAMA_LIB:-}" ] && printf 'PATH_DIR_DATA_LLAMA_LIB=%s\n' "$DIR_DATA_LLAMA_LIB"
  [ -n "${DIR_ETC_SKEL_BASE:-}" ] && printf 'PATH_DIR_ETC_SKEL_BASE=%s\n' "$DIR_ETC_SKEL_BASE"
  [ -n "${DIR_ETC_SKEL_DESKTOP:-}" ] && printf 'PATH_DIR_ETC_SKEL_DESKTOP=%s\n' "$DIR_ETC_SKEL_DESKTOP"
  [ -n "${DIR_ETC_SKEL_SERVER:-}" ] && printf 'PATH_DIR_ETC_SKEL_SERVER=%s\n' "$DIR_ETC_SKEL_SERVER"
  [ -n "${DIR_ETC_SKEL_DESKTOP_CONFIG:-}" ] && printf 'PATH_DIR_ETC_SKEL_DESKTOP_CONFIG=%s\n' "$DIR_ETC_SKEL_DESKTOP_CONFIG"
  [ -n "${DIR_ETC_SKEL_DESKTOP_LOCAL:-}" ] && printf 'PATH_DIR_ETC_SKEL_DESKTOP_LOCAL=%s\n' "$DIR_ETC_SKEL_DESKTOP_LOCAL"
  [ -n "${DIR_ETC_SKEL_DESKTOP_SHARE:-}" ] && printf 'PATH_DIR_ETC_SKEL_DESKTOP_SHARE=%s\n' "$DIR_ETC_SKEL_DESKTOP_SHARE"
  [ -n "${DIR_VAR_LOG:-}" ] && printf 'PATH_DIR_VAR_LOG=%s\n' "$DIR_VAR_LOG"
  [ -n "${DIR_VAR_CACHE:-}" ] && printf 'PATH_DIR_VAR_CACHE=%s\n' "$DIR_VAR_CACHE"
  [ -n "${DIR_VAR_TMP:-}" ] && printf 'PATH_DIR_VAR_TMP=%s\n' "$DIR_VAR_TMP"
  [ -n "${DIR_VAR_SPOOL:-}" ] && printf 'PATH_DIR_VAR_SPOOL=%s\n' "$DIR_VAR_SPOOL"
  [ -n "${DIR_VAR_SPOOL_RSYSLOG:-}" ] && printf 'PATH_DIR_VAR_SPOOL_RSYSLOG=%s\n' "$DIR_VAR_SPOOL_RSYSLOG"
  [ -n "${DIR_VAR_LOG_JOURNAL:-}" ] && printf 'PATH_DIR_VAR_LOG_JOURNAL=%s\n' "$DIR_VAR_LOG_JOURNAL"
  [ -n "${DIR_APT_LISTS:-}" ] && printf 'PATH_DIR_APT_LISTS=%s\n' "$DIR_APT_LISTS"
  [ -n "${DIR_SYSTEMD:-}" ] && printf 'PATH_DIR_SYSTEMD=%s\n' "$DIR_SYSTEMD"
  [ -n "${DIR_SYSTEMD_COREDUMP:-}" ] && printf 'PATH_DIR_SYSTEMD_COREDUMP=%s\n' "$DIR_SYSTEMD_COREDUMP"
  [ -n "${DIR_DATA_RUN:-}" ] && printf 'PATH_DIR_DATA_RUN=%s\n' "$DIR_DATA_RUN"
  [ -n "${DIR_DATA_RUN_MNT:-}" ] && printf 'PATH_DIR_DATA_RUN_MNT=%s\n' "$DIR_DATA_RUN_MNT"
  [ -n "${DIR_RUN_MEDIA:-}" ] && printf 'PATH_DIR_RUN_MEDIA=%s\n' "$DIR_RUN_MEDIA"
  [ -n "${DIR_RUN_TAILSCALE:-}" ] && printf 'PATH_DIR_RUN_TAILSCALE=%s\n' "$DIR_RUN_TAILSCALE"
  [ -n "${DIR_RUN_ZRAM:-}" ] && printf 'PATH_DIR_RUN_ZRAM=%s\n' "$DIR_RUN_ZRAM"
  [ -n "${DIR_GRUB_DEFAULT:-}" ] && printf 'PATH_DIR_GRUB_DEFAULT=%s\n' "$DIR_GRUB_DEFAULT"
  [ -n "${DIR_GRUB_SCRIPTS:-}" ] && printf 'PATH_DIR_GRUB_SCRIPTS=%s\n' "$DIR_GRUB_SCRIPTS"
  [ -n "${DIR_BOOT_GRUB_FONTS:-}" ] && printf 'PATH_DIR_BOOT_GRUB_FONTS=%s\n' "$DIR_BOOT_GRUB_FONTS"
  [ -n "${DIR_SYSCTL:-}" ] && printf 'PATH_DIR_SYSCTL=%s\n' "$DIR_SYSCTL"
  [ -n "${DIR_SYSCTL_PROFILES:-}" ] && printf 'PATH_DIR_SYSCTL_PROFILES=%s\n' "$DIR_SYSCTL_PROFILES"
  [ -n "${DIR_INITRAMFS:-}" ] && printf 'PATH_DIR_INITRAMFS=%s\n' "$DIR_INITRAMFS"
  [ -n "${DIR_INITRAMFS_CONF:-}" ] && printf 'PATH_DIR_INITRAMFS_CONF=%s\n' "$DIR_INITRAMFS_CONF"
  [ -n "${DIR_INITRAMFS_SCRIPTS:-}" ] && printf 'PATH_DIR_INITRAMFS_SCRIPTS=%s\n' "$DIR_INITRAMFS_SCRIPTS"
  [ -n "${DIR_INITRAMFS_INIT_TOP:-}" ] && printf 'PATH_DIR_INITRAMFS_INIT_TOP=%s\n' "$DIR_INITRAMFS_INIT_TOP"
  [ -n "${DIR_INITRAMFS_INIT_PREMOUNT:-}" ] && printf 'PATH_DIR_INITRAMFS_INIT_PREMOUNT=%s\n' "$DIR_INITRAMFS_INIT_PREMOUNT"
  [ -n "${DIR_INITRAMFS_LOCAL_TOP:-}" ] && printf 'PATH_DIR_INITRAMFS_LOCAL_TOP=%s\n' "$DIR_INITRAMFS_LOCAL_TOP"
  [ -n "${DIR_INITRAMFS_LOCAL_BLOCK:-}" ] && printf 'PATH_DIR_INITRAMFS_LOCAL_BLOCK=%s\n' "$DIR_INITRAMFS_LOCAL_BLOCK"
  [ -n "${DIR_INITRAMFS_LOCAL_PREMOUNT:-}" ] && printf 'PATH_DIR_INITRAMFS_LOCAL_PREMOUNT=%s\n' "$DIR_INITRAMFS_LOCAL_PREMOUNT"
  [ -n "${DIR_INITRAMFS_LOCAL_BOTTOM:-}" ] && printf 'PATH_DIR_INITRAMFS_LOCAL_BOTTOM=%s\n' "$DIR_INITRAMFS_LOCAL_BOTTOM"
  [ -n "${DIR_INITRAMFS_NFS_TOP:-}" ] && printf 'PATH_DIR_INITRAMFS_NFS_TOP=%s\n' "$DIR_INITRAMFS_NFS_TOP"
  [ -n "${DIR_INITRAMFS_NFS_PREMOUNT:-}" ] && printf 'PATH_DIR_INITRAMFS_NFS_PREMOUNT=%s\n' "$DIR_INITRAMFS_NFS_PREMOUNT"
  [ -n "${DIR_INITRAMFS_NFS_BOTTOM:-}" ] && printf 'PATH_DIR_INITRAMFS_NFS_BOTTOM=%s\n' "$DIR_INITRAMFS_NFS_BOTTOM"
  [ -n "${DIR_INITRAMFS_INIT_BOTTOM:-}" ] && printf 'PATH_DIR_INITRAMFS_INIT_BOTTOM=%s\n' "$DIR_INITRAMFS_INIT_BOTTOM"
  [ -n "${DIR_MODPROBE_D:-}" ] && printf 'PATH_DIR_MODPROBE_D=%s\n' "$DIR_MODPROBE_D"
  [ -n "${DIR_MODULES_LOAD:-}" ] && printf 'PATH_DIR_MODULES_LOAD=%s\n' "$DIR_MODULES_LOAD"
  [ -n "${DIR_TMPFILES_D:-}" ] && printf 'PATH_DIR_TMPFILES_D=%s\n' "$DIR_TMPFILES_D"
  [ -n "${DIR_UDEV_CONF_D:-}" ] && printf 'PATH_DIR_UDEV_CONF_D=%s\n' "$DIR_UDEV_CONF_D"
  [ -n "${DIR_UDEV_RULES:-}" ] && printf 'PATH_DIR_UDEV_RULES=%s\n' "$DIR_UDEV_RULES"
  [ -n "${DIR_UDISKS2:-}" ] && printf 'PATH_DIR_UDISKS2=%s\n' "$DIR_UDISKS2"
  [ -n "${DIR_POLKIT_RULES_D:-}" ] && printf 'PATH_DIR_POLKIT_RULES_D=%s\n' "$DIR_POLKIT_RULES_D"
  [ -n "${DIR_POLKIT_LOCAL_RULES_D:-}" ] && printf 'PATH_DIR_POLKIT_LOCAL_RULES_D=%s\n' "$DIR_POLKIT_LOCAL_RULES_D"
  [ -n "${DIR_POLKIT_RUNTIME_RULES_D:-}" ] && printf 'PATH_DIR_POLKIT_RUNTIME_RULES_D=%s\n' "$DIR_POLKIT_RUNTIME_RULES_D"
  [ -n "${DIR_WPA_SUPPLICANT:-}" ] && printf 'PATH_DIR_WPA_SUPPLICANT=%s\n' "$DIR_WPA_SUPPLICANT"
  [ -n "${DIR_NETWORKMANAGER:-}" ] && printf 'PATH_DIR_NETWORKMANAGER=%s\n' "$DIR_NETWORKMANAGER"
  [ -n "${DIR_NETWORKMANAGER_CONF_D:-}" ] && printf 'PATH_DIR_NETWORKMANAGER_CONF_D=%s\n' "$DIR_NETWORKMANAGER_CONF_D"
  [ -n "${DIR_TAILSCALE:-}" ] && printf 'PATH_DIR_TAILSCALE=%s\n' "$DIR_TAILSCALE"
  [ -n "${DIR_JOURNALD_CONF_D:-}" ] && printf 'PATH_DIR_JOURNALD_CONF_D=%s\n' "$DIR_JOURNALD_CONF_D"
  [ -n "${DIR_LOGIND_CONF_D:-}" ] && printf 'PATH_DIR_LOGIND_CONF_D=%s\n' "$DIR_LOGIND_CONF_D"
  [ -n "${DIR_SYSTEMD_ETC:-}" ] && printf 'PATH_DIR_SYSTEMD_ETC=%s\n' "$DIR_SYSTEMD_ETC"
  [ -n "${DIR_SYSTEMD_SYSTEM:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM=%s\n' "$DIR_SYSTEMD_SYSTEM"
  [ -n "${DIR_SYSTEMD_SYSTEM_LIB:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_LIB=%s\n' "$DIR_SYSTEMD_SYSTEM_LIB"
  [ -n "${DIR_SYSTEMD_USER:-}" ] && printf 'PATH_DIR_SYSTEMD_USER=%s\n' "$DIR_SYSTEMD_USER"
  [ -n "${DIR_SYSTEMD_USER_LIB:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_LIB=%s\n' "$DIR_SYSTEMD_USER_LIB"
  [ -n "${DIR_DBUS_ETC:-}" ] && printf 'PATH_DIR_DBUS_ETC=%s\n' "$DIR_DBUS_ETC"
  [ -n "${DIR_USR_SHARE_DBUS:-}" ] && printf 'PATH_DIR_USR_SHARE_DBUS=%s\n' "$DIR_USR_SHARE_DBUS"
  [ -n "${DIR_DBUS_SESSION_SERVICES:-}" ] && printf 'PATH_DIR_DBUS_SESSION_SERVICES=%s\n' "$DIR_DBUS_SESSION_SERVICES"
  [ -n "${DIR_DBUS_LOCAL_SESSION_SERVICES:-}" ] && printf 'PATH_DIR_DBUS_LOCAL_SESSION_SERVICES=%s\n' "$DIR_DBUS_LOCAL_SESSION_SERVICES"
  [ -n "${DIR_USR_LOCAL_SHARE_DBUS:-}" ] && printf 'PATH_DIR_USR_LOCAL_SHARE_DBUS=%s\n' "$DIR_USR_LOCAL_SHARE_DBUS"
  [ -n "${DIR_USR_LOCAL_SHARE_FONTS:-}" ] && printf 'PATH_DIR_USR_LOCAL_SHARE_FONTS=%s\n' "$DIR_USR_LOCAL_SHARE_FONTS"
  [ -n "${DIR_APPARMOR:-}" ] && printf 'PATH_DIR_APPARMOR=%s\n' "$DIR_APPARMOR"
  [ -n "${DIR_APPARMOR_LOCAL:-}" ] && printf 'PATH_DIR_APPARMOR_LOCAL=%s\n' "$DIR_APPARMOR_LOCAL"
  [ -n "${DIR_FIRSTBOOT:-}" ] && printf 'PATH_DIR_FIRSTBOOT=%s\n' "$DIR_FIRSTBOOT"
  [ -n "${DIR_FIRSTBOOT_BIN:-}" ] && printf 'PATH_DIR_FIRSTBOOT_BIN=%s\n' "$DIR_FIRSTBOOT_BIN"
  [ -n "${DIR_FIRSTBOOT_DATA:-}" ] && printf 'PATH_DIR_FIRSTBOOT_DATA=%s\n' "$DIR_FIRSTBOOT_DATA"
  [ -n "${DIR_FIRSTBOOT_STATE:-}" ] && printf 'PATH_DIR_FIRSTBOOT_STATE=%s\n' "$DIR_FIRSTBOOT_STATE"
  [ -n "${DIR_FIRSTBOOT_LOG:-}" ] && printf 'PATH_DIR_FIRSTBOOT_LOG=%s\n' "$DIR_FIRSTBOOT_LOG"
  [ -n "${DIR_APT:-}" ] && printf 'PATH_DIR_APT=%s\n' "$DIR_APT"
  [ -n "${DIR_APT_PREFERENCES_D:-}" ] && printf 'PATH_DIR_APT_PREFERENCES_D=%s\n' "$DIR_APT_PREFERENCES_D"
  [ -n "${DIR_RSYSLOG_D:-}" ] && printf 'PATH_DIR_RSYSLOG_D=%s\n' "$DIR_RSYSLOG_D"
  [ -n "${DIR_LOGROTATE_D:-}" ] && printf 'PATH_DIR_LOGROTATE_D=%s\n' "$DIR_LOGROTATE_D"
  [ -n "${DIR_SYNCTHING:-}" ] && printf 'PATH_DIR_SYNCTHING=%s\n' "$DIR_SYNCTHING"
  [ -n "${DIR_ZRAM:-}" ] && printf 'PATH_DIR_ZRAM=%s\n' "$DIR_ZRAM"
  [ -n "${DIR_DKMS:-}" ] && printf 'PATH_DIR_DKMS=%s\n' "$DIR_DKMS"
  [ -n "${DIR_FRAMEWORK_CONF_D:-}" ] && printf 'PATH_DIR_FRAMEWORK_CONF_D=%s\n' "$DIR_FRAMEWORK_CONF_D"
  [ -n "${DIR_KERNEL_POSTINST_D:-}" ] && printf 'PATH_DIR_KERNEL_POSTINST_D=%s\n' "$DIR_KERNEL_POSTINST_D"
  [ -n "${DIR_KERNEL_POSTRM_D:-}" ] && printf 'PATH_DIR_KERNEL_POSTRM_D=%s\n' "$DIR_KERNEL_POSTRM_D"
  [ -n "${DIR_KERNEL_HEADER_POSTINST_D:-}" ] && printf 'PATH_DIR_KERNEL_HEADER_POSTINST_D=%s\n' "$DIR_KERNEL_HEADER_POSTINST_D"
  [ -n "${DIR_SYSTEMD_SYSTEM_CI_GITHUB_USER_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_CI_GITHUB_USER_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_CI_GITHUB_USER_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_CI_GITLAB_USER_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_CI_GITLAB_USER_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_CI_GITLAB_USER_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_SERVER_DEVOPS_USER_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_SERVER_DEVOPS_USER_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_SERVER_DEVOPS_USER_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_TECHNITIUM_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_TECHNITIUM_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_TECHNITIUM_DROPIN"
  [ -n "${DIR_SYSTEMD_RESOLVED_CONF_D:-}" ] && printf 'PATH_DIR_SYSTEMD_RESOLVED_CONF_D=%s\n' "$DIR_SYSTEMD_RESOLVED_CONF_D"
  [ -n "${DIR_SYSTEMD_SYSTEM_APPARMOR_MODES_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_APPARMOR_MODES_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_APPARMOR_MODES_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_APPARMOR_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_APPARMOR_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_APPARMOR_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_APT_DAILY_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_APT_DAILY_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_APT_DAILY_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_APT_DAILY_UPGRADE_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_APT_DAILY_UPGRADE_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_APT_DAILY_UPGRADE_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_APT_REPO_LOCAL_FAMILY_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_APT_REPO_LOCAL_FAMILY_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_APT_REPO_LOCAL_FAMILY_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_APT_REPO_LOCAL_REFRESH_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_APT_REPO_LOCAL_REFRESH_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_APT_REPO_LOCAL_REFRESH_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_AUDITD_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_AUDITD_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_AUDITD_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_AUDIT_RULES_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_AUDIT_RULES_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_AUDIT_RULES_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_BLUETOOTH_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_BLUETOOTH_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_BLUETOOTH_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_CLAMAV_DAEMON_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_CLAMAV_DAEMON_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_CLAMAV_DAEMON_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_CLAMAV_FRESHCLAM_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_CLAMAV_FRESHCLAM_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_CLAMAV_FRESHCLAM_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_CLAMAV_SIGNATURE_UPDATE_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_CLAMAV_SIGNATURE_UPDATE_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_CLAMAV_SIGNATURE_UPDATE_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_CROWDSEC_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_CROWDSEC_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_CROWDSEC_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_CROWDSEC_FIREWALL_BOUNCER_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_CROWDSEC_FIREWALL_BOUNCER_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_CROWDSEC_FIREWALL_BOUNCER_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_DATA_RUN_MOUNT_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_DATA_RUN_MOUNT_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_DATA_RUN_MOUNT_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_DBUS_BROKER_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_DBUS_BROKER_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_DBUS_BROKER_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_DEV_SHM_MOUNT_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_DEV_SHM_MOUNT_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_DEV_SHM_MOUNT_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_FAIL2BAN_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_FAIL2BAN_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_FAIL2BAN_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_FSTRIM_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_FSTRIM_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_FSTRIM_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_FSTRIM_TIMER_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_FSTRIM_TIMER_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_FSTRIM_TIMER_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_FWUPD_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_FWUPD_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_FWUPD_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_GREETD_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_GREETD_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_GREETD_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_HOME_MCRAMER_SHARING_MOUNT_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_HOME_MCRAMER_SHARING_MOUNT_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_HOME_MCRAMER_SHARING_MOUNT_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_IFUP_TEMPLATE_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_IFUP_TEMPLATE_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_IFUP_TEMPLATE_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_INCUS_USER_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_INCUS_USER_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_INCUS_USER_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_LOGROTATE_TIMER_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_LOGROTATE_TIMER_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_LOGROTATE_TIMER_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_LYNIS_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_LYNIS_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_LYNIS_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_MULLVAD_DAEMON_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_MULLVAD_DAEMON_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_MULLVAD_DAEMON_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_NETWORKING_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_NETWORKING_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_NETWORKING_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_NETWORKMANAGER_DISPATCHER_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_NETWORKMANAGER_DISPATCHER_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_NETWORKMANAGER_DISPATCHER_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_NETWORKMANAGER_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_NETWORKMANAGER_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_NETWORKMANAGER_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_NFS_IDMAPD_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_NFS_IDMAPD_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_NFS_IDMAPD_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_NFS_MOUNTD_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_NFS_MOUNTD_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_NFS_MOUNTD_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_NFS_SERVER_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_NFS_SERVER_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_NFS_SERVER_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_NFTABLES_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_NFTABLES_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_NFTABLES_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_NVIDIA_HIBERNATE_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_NVIDIA_HIBERNATE_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_NVIDIA_HIBERNATE_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_NVIDIA_POWERD_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_NVIDIA_POWERD_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_NVIDIA_POWERD_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_NVIDIA_RESUME_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_NVIDIA_RESUME_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_NVIDIA_RESUME_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_NVIDIA_SUSPEND_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_NVIDIA_SUSPEND_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_NVIDIA_SUSPEND_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_NVIDIA_SUSPEND_THEN_HIBERNATE_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_NVIDIA_SUSPEND_THEN_HIBERNATE_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_NVIDIA_SUSPEND_THEN_HIBERNATE_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_POWER_PROFILES_DAEMON_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_POWER_PROFILES_DAEMON_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_POWER_PROFILES_DAEMON_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_RSYSLOG_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_RSYSLOG_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_RSYSLOG_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_SCX_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_SCX_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_SCX_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_SCX_LOADER_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_SCX_LOADER_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_SCX_LOADER_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_SLEEP_TARGET_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_SLEEP_TARGET_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_SLEEP_TARGET_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_SSH_SOCKET_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_SSH_SOCKET_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_SSH_SOCKET_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_STUBBY_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_STUBBY_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_STUBBY_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_SYNCTHING_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_SYNCTHING_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_SYNCTHING_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_SYSTEMD_COREDUMP_SOCKET_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_SYSTEMD_COREDUMP_SOCKET_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_SYSTEMD_COREDUMP_SOCKET_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_SYSTEMD_CREDS_SOCKET_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_SYSTEMD_CREDS_SOCKET_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_SYSTEMD_CREDS_SOCKET_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_SYSTEMD_HIBERNATE_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_SYSTEMD_HIBERNATE_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_SYSTEMD_HIBERNATE_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_SYSTEMD_HYBRID_SLEEP_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_SYSTEMD_HYBRID_SLEEP_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_SYSTEMD_HYBRID_SLEEP_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_SYSTEMD_RESOLVED_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_SYSTEMD_RESOLVED_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_SYSTEMD_RESOLVED_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_SYSTEMD_SUSPEND_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_SYSTEMD_SUSPEND_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_SYSTEMD_SUSPEND_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_SYSTEMD_SUSPEND_THEN_HIBERNATE_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_SYSTEMD_SUSPEND_THEN_HIBERNATE_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_SYSTEMD_SUSPEND_THEN_HIBERNATE_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_SYSTEM_BACKGROUND_SLICE_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_SYSTEM_BACKGROUND_SLICE_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_SYSTEM_BACKGROUND_SLICE_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_SYSTEM_MAINTENANCE_SLICE_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_SYSTEM_MAINTENANCE_SLICE_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_SYSTEM_MAINTENANCE_SLICE_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_TAILSCALED_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_TAILSCALED_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_TAILSCALED_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_TEST_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_TEST_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_TEST_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_TIMESHIFT_FAMILY_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_TIMESHIFT_FAMILY_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_TIMESHIFT_FAMILY_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_TMP_MOUNT_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_TMP_MOUNT_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_TMP_MOUNT_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_UNATTENDED_UPGRADES_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_UNATTENDED_UPGRADES_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_UNATTENDED_UPGRADES_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_USER_1000_SLICE_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_USER_1000_SLICE_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_USER_1000_SLICE_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_USER_MANAGER_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_USER_MANAGER_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_USER_MANAGER_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_VAR_CACHE_MOUNT_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_VAR_CACHE_MOUNT_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_VAR_CACHE_MOUNT_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_VAR_LIB_APT_LISTS_MOUNT_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_VAR_LIB_APT_LISTS_MOUNT_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_VAR_LIB_APT_LISTS_MOUNT_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_VAR_LIB_SYSTEMD_COREDUMP_MOUNT_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_VAR_LIB_SYSTEMD_COREDUMP_MOUNT_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_VAR_LIB_SYSTEMD_COREDUMP_MOUNT_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_VAR_LOG_MOUNT_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_VAR_LOG_MOUNT_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_VAR_LOG_MOUNT_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_VAR_SPOOL_RSYSLOG_MOUNT_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_VAR_SPOOL_RSYSLOG_MOUNT_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_VAR_SPOOL_RSYSLOG_MOUNT_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_WPA_SUPPLICANT_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_WPA_SUPPLICANT_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_WPA_SUPPLICANT_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_XFS_HEALER_START_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_XFS_HEALER_START_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_XFS_HEALER_START_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_X_CLAMAV_SIGNATURE_UPDATE_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_X_CLAMAV_SIGNATURE_UPDATE_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_X_CLAMAV_SIGNATURE_UPDATE_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_X_SYNCTHING_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_X_SYNCTHING_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_X_SYNCTHING_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_ZRAM_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_ZRAM_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_ZRAM_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_APP_FAMILY_SCOPE_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_APP_FAMILY_SCOPE_DROPIN=%s\n' "$DIR_SYSTEMD_USER_APP_FAMILY_SCOPE_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_APP_SLICE_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_APP_SLICE_DROPIN=%s\n' "$DIR_SYSTEMD_USER_APP_SLICE_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_USER_FAMILY_SLICE_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_USER_FAMILY_SLICE_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_USER_FAMILY_SLICE_DROPIN"
  [ -n "${DIR_SYSTEMD_SYSTEM_USER_SLICE_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_SYSTEM_USER_SLICE_DROPIN=%s\n' "$DIR_SYSTEMD_SYSTEM_USER_SLICE_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_BACKGROUND_SLICE_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_BACKGROUND_SLICE_DROPIN=%s\n' "$DIR_SYSTEMD_USER_BACKGROUND_SLICE_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_CRYSTAL_DOCK_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_CRYSTAL_DOCK_DROPIN=%s\n' "$DIR_SYSTEMD_USER_CRYSTAL_DOCK_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_DBUS_BROKER_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_DBUS_BROKER_DROPIN=%s\n' "$DIR_SYSTEMD_USER_DBUS_BROKER_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_FILTER_CHAIN_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_FILTER_CHAIN_DROPIN=%s\n' "$DIR_SYSTEMD_USER_FILTER_CHAIN_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_FOOT_SERVER_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_FOOT_SERVER_DROPIN=%s\n' "$DIR_SYSTEMD_USER_FOOT_SERVER_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_FOOT_SERVER_SOCKET_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_FOOT_SERVER_SOCKET_DROPIN=%s\n' "$DIR_SYSTEMD_USER_FOOT_SERVER_SOCKET_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_GVFS_DAEMON_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_GVFS_DAEMON_DROPIN=%s\n' "$DIR_SYSTEMD_USER_GVFS_DAEMON_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_GVFS_UDISKS2_VOLUME_MONITOR_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_GVFS_UDISKS2_VOLUME_MONITOR_DROPIN=%s\n' "$DIR_SYSTEMD_USER_GVFS_UDISKS2_VOLUME_MONITOR_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_HYPRPOLKITAGENT_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_HYPRPOLKITAGENT_DROPIN=%s\n' "$DIR_SYSTEMD_USER_HYPRPOLKITAGENT_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_KANSHI_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_KANSHI_DROPIN=%s\n' "$DIR_SYSTEMD_USER_KANSHI_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_LABWC_BITWARDEN_FAMILY_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_LABWC_BITWARDEN_FAMILY_DROPIN=%s\n' "$DIR_SYSTEMD_USER_LABWC_BITWARDEN_FAMILY_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_LABWC_COMPAT_FAMILY_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_LABWC_COMPAT_FAMILY_DROPIN=%s\n' "$DIR_SYSTEMD_USER_LABWC_COMPAT_FAMILY_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_LABWC_DEVOPS_FAMILY_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_LABWC_DEVOPS_FAMILY_DROPIN=%s\n' "$DIR_SYSTEMD_USER_LABWC_DEVOPS_FAMILY_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_LABWC_ELECTRON_FAMILY_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_LABWC_ELECTRON_FAMILY_DROPIN=%s\n' "$DIR_SYSTEMD_USER_LABWC_ELECTRON_FAMILY_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_LABWC_NATIVE_FAMILY_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_LABWC_NATIVE_FAMILY_DROPIN=%s\n' "$DIR_SYSTEMD_USER_LABWC_NATIVE_FAMILY_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_LABWC_QBITTORRENT_FAMILY_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_LABWC_QBITTORRENT_FAMILY_DROPIN=%s\n' "$DIR_SYSTEMD_USER_LABWC_QBITTORRENT_FAMILY_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_LABWC_SESSION_STATE_PREPARE_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_LABWC_SESSION_STATE_PREPARE_DROPIN=%s\n' "$DIR_SYSTEMD_USER_LABWC_SESSION_STATE_PREPARE_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_LABWC_WAYLAND_FAMILY_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_LABWC_WAYLAND_FAMILY_DROPIN=%s\n' "$DIR_SYSTEMD_USER_LABWC_WAYLAND_FAMILY_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_LABWC_WAYLAND_FOOT_FAMILY_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_LABWC_WAYLAND_FOOT_FAMILY_DROPIN=%s\n' "$DIR_SYSTEMD_USER_LABWC_WAYLAND_FOOT_FAMILY_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_LLAMA_SERVER_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_LLAMA_SERVER_DROPIN=%s\n' "$DIR_SYSTEMD_USER_LLAMA_SERVER_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_MAKO_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_MAKO_DROPIN=%s\n' "$DIR_SYSTEMD_USER_MAKO_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_PIPEWIRE_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_PIPEWIRE_DROPIN=%s\n' "$DIR_SYSTEMD_USER_PIPEWIRE_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_PIPEWIRE_PULSE_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_PIPEWIRE_PULSE_DROPIN=%s\n' "$DIR_SYSTEMD_USER_PIPEWIRE_PULSE_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_PIPEWIRE_PULSE_SOCKET_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_PIPEWIRE_PULSE_SOCKET_DROPIN=%s\n' "$DIR_SYSTEMD_USER_PIPEWIRE_PULSE_SOCKET_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_PIPEWIRE_SOCKET_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_PIPEWIRE_SOCKET_DROPIN=%s\n' "$DIR_SYSTEMD_USER_PIPEWIRE_SOCKET_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_SESSION_SLICE_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_SESSION_SLICE_DROPIN=%s\n' "$DIR_SYSTEMD_USER_SESSION_SLICE_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_SSH_AGENT_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_SSH_AGENT_DROPIN=%s\n' "$DIR_SYSTEMD_USER_SSH_AGENT_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_SSH_AGENT_SOCKET_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_SSH_AGENT_SOCKET_DROPIN=%s\n' "$DIR_SYSTEMD_USER_SSH_AGENT_SOCKET_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_THUNAR_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_THUNAR_DROPIN=%s\n' "$DIR_SYSTEMD_USER_THUNAR_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_WAYBAR_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_WAYBAR_DROPIN=%s\n' "$DIR_SYSTEMD_USER_WAYBAR_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_WAYSCRIBER_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_WAYSCRIBER_DROPIN=%s\n' "$DIR_SYSTEMD_USER_WAYSCRIBER_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_WIREPLUMBER_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_WIREPLUMBER_DROPIN=%s\n' "$DIR_SYSTEMD_USER_WIREPLUMBER_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_XDG_DESKTOP_PORTAL_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_XDG_DESKTOP_PORTAL_DROPIN=%s\n' "$DIR_SYSTEMD_USER_XDG_DESKTOP_PORTAL_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_XDG_DESKTOP_PORTAL_FAMILY_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_XDG_DESKTOP_PORTAL_FAMILY_DROPIN=%s\n' "$DIR_SYSTEMD_USER_XDG_DESKTOP_PORTAL_FAMILY_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_XDG_DESKTOP_PORTAL_GTK_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_XDG_DESKTOP_PORTAL_GTK_DROPIN=%s\n' "$DIR_SYSTEMD_USER_XDG_DESKTOP_PORTAL_GTK_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_XDG_DESKTOP_PORTAL_LXQT_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_XDG_DESKTOP_PORTAL_LXQT_DROPIN=%s\n' "$DIR_SYSTEMD_USER_XDG_DESKTOP_PORTAL_LXQT_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_XDG_DESKTOP_PORTAL_WLR_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_XDG_DESKTOP_PORTAL_WLR_DROPIN=%s\n' "$DIR_SYSTEMD_USER_XDG_DESKTOP_PORTAL_WLR_DROPIN"
  [ -n "${DIR_SYSTEMD_USER_XDG_DESKTOP_PORTAL_XAPP_DROPIN:-}" ] && printf 'PATH_DIR_SYSTEMD_USER_XDG_DESKTOP_PORTAL_XAPP_DROPIN=%s\n' "$DIR_SYSTEMD_USER_XDG_DESKTOP_PORTAL_XAPP_DROPIN"
  [ -n "${DIR_PERL5_SITE_PERL:-}" ] && printf 'PATH_DIR_PERL5_SITE_PERL=%s\n' "$DIR_PERL5_SITE_PERL"
  [ -n "${DIR_PERL5_SITE_PERL_AI_COPILOTS:-}" ] && printf 'PATH_DIR_PERL5_SITE_PERL_AI_COPILOTS=%s\n' "$DIR_PERL5_SITE_PERL_AI_COPILOTS"
  [ -n "${DIR_PERL5_SITE_PERL_APPARMOR_MODES:-}" ] && printf 'PATH_DIR_PERL5_SITE_PERL_APPARMOR_MODES=%s\n' "$DIR_PERL5_SITE_PERL_APPARMOR_MODES"
  [ -n "${DIR_PERL5_SITE_PERL_APT_REPO_LOCAL:-}" ] && printf 'PATH_DIR_PERL5_SITE_PERL_APT_REPO_LOCAL=%s\n' "$DIR_PERL5_SITE_PERL_APT_REPO_LOCAL"
  [ -n "${DIR_PERL5_SITE_PERL_DIGITAL_ASSETS:-}" ] && printf 'PATH_DIR_PERL5_SITE_PERL_DIGITAL_ASSETS=%s\n' "$DIR_PERL5_SITE_PERL_DIGITAL_ASSETS"
  [ -n "${DIR_PERL5_SITE_PERL_FILEN:-}" ] && printf 'PATH_DIR_PERL5_SITE_PERL_FILEN=%s\n' "$DIR_PERL5_SITE_PERL_FILEN"
  [ -n "${DIR_PERL5_SITE_PERL_LABWC_ADB:-}" ] && printf 'PATH_DIR_PERL5_SITE_PERL_LABWC_ADB=%s\n' "$DIR_PERL5_SITE_PERL_LABWC_ADB"
  [ -n "${DIR_PERL5_SITE_PERL_LABWC_COMPZ:-}" ] && printf 'PATH_DIR_PERL5_SITE_PERL_LABWC_COMPZ=%s\n' "$DIR_PERL5_SITE_PERL_LABWC_COMPZ"
  [ -n "${DIR_PERL5_SITE_PERL_LABWC_NETWORK_CONTROL_ACTION:-}" ] && printf 'PATH_DIR_PERL5_SITE_PERL_LABWC_NETWORK_CONTROL_ACTION=%s\n' "$DIR_PERL5_SITE_PERL_LABWC_NETWORK_CONTROL_ACTION"
  [ -n "${DIR_PERL5_SITE_PERL_LABWC_NETWORK_SCAN_ACTION:-}" ] && printf 'PATH_DIR_PERL5_SITE_PERL_LABWC_NETWORK_SCAN_ACTION=%s\n' "$DIR_PERL5_SITE_PERL_LABWC_NETWORK_SCAN_ACTION"
  [ -n "${DIR_PERL5_SITE_PERL_LABWC_SECURITY_ACTION:-}" ] && printf 'PATH_DIR_PERL5_SITE_PERL_LABWC_SECURITY_ACTION=%s\n' "$DIR_PERL5_SITE_PERL_LABWC_SECURITY_ACTION"
  [ -n "${DIR_PERL5_SITE_PERL_NETWORK:-}" ] && printf 'PATH_DIR_PERL5_SITE_PERL_NETWORK=%s\n' "$DIR_PERL5_SITE_PERL_NETWORK"
  [ -n "${DIR_PERL5_SITE_PERL_RUNTIME:-}" ] && printf 'PATH_DIR_PERL5_SITE_PERL_RUNTIME=%s\n' "$DIR_PERL5_SITE_PERL_RUNTIME"
  [ -n "${DIR_PERL5_SITE_PERL_TIMESHIFT:-}" ] && printf 'PATH_DIR_PERL5_SITE_PERL_TIMESHIFT=%s\n' "$DIR_PERL5_SITE_PERL_TIMESHIFT"
  [ -n "${DIR_PERL5_SITE_PERL_WHISPER:-}" ] && printf 'PATH_DIR_PERL5_SITE_PERL_WHISPER=%s\n' "$DIR_PERL5_SITE_PERL_WHISPER"
  [ -n "${DIR_PYTHON3_SYSTEM_PACKAGES:-}" ] && printf 'PATH_DIR_PYTHON3_SYSTEM_PACKAGES=%s\n' "$DIR_PYTHON3_SYSTEM_PACKAGES"
  [ -n "${DIR_PYTHON3_LOCAL:-}" ] && printf 'PATH_DIR_PYTHON3_LOCAL=%s\n' "$DIR_PYTHON3_LOCAL"
  [ -n "${FILE_INSTALLER_CLASSES:-}" ] && printf 'PATH_FILE_INSTALLER_CLASSES=%s\n' "$FILE_INSTALLER_CLASSES"
  [ -n "${FILE_NETWORK_UPLINK_POLICY:-}" ] && printf 'PATH_FILE_NETWORK_UPLINK_POLICY=%s\n' "$FILE_NETWORK_UPLINK_POLICY"
  [ -n "${FILE_CRYPTO_BOOTSTRAP_CREDENTIAL:-}" ] && printf 'PATH_FILE_CRYPTO_BOOTSTRAP_CREDENTIAL=%s\n' "$FILE_CRYPTO_BOOTSTRAP_CREDENTIAL"
  [ -n "${FILE_CRYPTO_BOOTSTRAP_TRANSACTION:-}" ] && printf 'PATH_FILE_CRYPTO_BOOTSTRAP_TRANSACTION=%s\n' "$FILE_CRYPTO_BOOTSTRAP_TRANSACTION"
  [ -n "${DIR_SERVER_STATE:-}" ] && printf 'PATH_DIR_SERVER_STATE=%s\n' "$DIR_SERVER_STATE"
  [ -n "${DIR_SERVER_GITHUB:-}" ] && printf 'PATH_DIR_SERVER_GITHUB=%s\n' "$DIR_SERVER_GITHUB"
  [ -n "${FILE_SERVER_GITHUB_JOB_BAZELRC:-}" ] && printf 'PATH_FILE_SERVER_GITHUB_JOB_BAZELRC=%s\n' "$FILE_SERVER_GITHUB_JOB_BAZELRC"
  [ -n "${FILE_SERVER_GITHUB_JOB_ENV:-}" ] && printf 'PATH_FILE_SERVER_GITHUB_JOB_ENV=%s\n' "$FILE_SERVER_GITHUB_JOB_ENV"
  [ -n "${FILE_SERVER_GITHUB_JOB_START:-}" ] && printf 'PATH_FILE_SERVER_GITHUB_JOB_START=%s\n' "$FILE_SERVER_GITHUB_JOB_START"
  [ -n "${DIR_SERVER_GITLAB:-}" ] && printf 'PATH_DIR_SERVER_GITLAB=%s\n' "$DIR_SERVER_GITLAB"
  [ -n "${DIR_SERVER_GITLAB_CONFIG:-}" ] && printf 'PATH_DIR_SERVER_GITLAB_CONFIG=%s\n' "$DIR_SERVER_GITLAB_CONFIG"
  [ -n "${FILE_SERVER_GITLAB_CONFIG:-}" ] && printf 'PATH_FILE_SERVER_GITLAB_CONFIG=%s\n' "$FILE_SERVER_GITLAB_CONFIG"
  [ -n "${FILE_SERVER_GITLAB_JOB_BAZELRC:-}" ] && printf 'PATH_FILE_SERVER_GITLAB_JOB_BAZELRC=%s\n' "$FILE_SERVER_GITLAB_JOB_BAZELRC"
  [ -n "${DIR_SERVER_DNS:-}" ] && printf 'PATH_DIR_SERVER_DNS=%s\n' "$DIR_SERVER_DNS"
  [ -n "${DIR_SERVER_DEVOPS:-}" ] && printf 'PATH_DIR_SERVER_DEVOPS=%s\n' "$DIR_SERVER_DEVOPS"
  [ -n "${DIR_SERVER_RELEASES:-}" ] && printf 'PATH_DIR_SERVER_RELEASES=%s\n' "$DIR_SERVER_RELEASES"
  [ -n "${DIR_SERVER_GITHUB_WORK:-}" ] && printf 'PATH_DIR_SERVER_GITHUB_WORK=%s\n' "$DIR_SERVER_GITHUB_WORK"
  [ -n "${DIR_SERVER_GITLAB_WORK:-}" ] && printf 'PATH_DIR_SERVER_GITLAB_WORK=%s\n' "$DIR_SERVER_GITLAB_WORK"
  [ -n "${DIR_SERVER_DEVOPS_WORK:-}" ] && printf 'PATH_DIR_SERVER_DEVOPS_WORK=%s\n' "$DIR_SERVER_DEVOPS_WORK"
  [ -n "${DIR_SERVER_BUILDBUDDY_STATE:-}" ] && printf 'PATH_DIR_SERVER_BUILDBUDDY_STATE=%s\n' "$DIR_SERVER_BUILDBUDDY_STATE"
  [ -n "${FILE_SERVER_BUILDBUDDY_CONFIG:-}" ] && printf 'PATH_FILE_SERVER_BUILDBUDDY_CONFIG=%s\n' "$FILE_SERVER_BUILDBUDDY_CONFIG"
  [ -n "${DIR_SERVER_DNS_IMAGES:-}" ] && printf 'PATH_DIR_SERVER_DNS_IMAGES=%s\n' "$DIR_SERVER_DNS_IMAGES"
  [ -n "${DIR_SERVER_DNS_WORK:-}" ] && printf 'PATH_DIR_SERVER_DNS_WORK=%s\n' "$DIR_SERVER_DNS_WORK"
  [ -n "${DIR_SERVER_DNS_BACKUPS:-}" ] && printf 'PATH_DIR_SERVER_DNS_BACKUPS=%s\n' "$DIR_SERVER_DNS_BACKUPS"
  [ -n "${DIR_SERVER_DNS_INCUS_POOL:-}" ] && printf 'PATH_DIR_SERVER_DNS_INCUS_POOL=%s\n' "$DIR_SERVER_DNS_INCUS_POOL"
  [ -n "${DIR_SERVER_RUNTIME:-}" ] && printf 'PATH_DIR_SERVER_RUNTIME=%s\n' "$DIR_SERVER_RUNTIME"
  [ -n "${FILE_SERVER_DNS_INCUS:-}" ] && printf 'PATH_FILE_SERVER_DNS_INCUS=%s\n' "$FILE_SERVER_DNS_INCUS"
  [ -n "${FILE_SERVER_DNS_INIT:-}" ] && printf 'PATH_FILE_SERVER_DNS_INIT=%s\n' "$FILE_SERVER_DNS_INIT"
  [ -n "${DIR_SERVER_DNS_GUEST_APP:-}" ] && printf 'PATH_DIR_SERVER_DNS_GUEST_APP=%s\n' "$DIR_SERVER_DNS_GUEST_APP"
  [ -n "${DIR_SERVER_DNS_GUEST_CONFIG:-}" ] && printf 'PATH_DIR_SERVER_DNS_GUEST_CONFIG=%s\n' "$DIR_SERVER_DNS_GUEST_CONFIG"
  [ -n "${DIR_SERVER_DNS_GUEST_PRIVATE:-}" ] && printf 'PATH_DIR_SERVER_DNS_GUEST_PRIVATE=%s\n' "$DIR_SERVER_DNS_GUEST_PRIVATE"
  [ -n "${FILE_INCUS_ADMIN_SOCKET:-}" ] && printf 'PATH_FILE_INCUS_ADMIN_SOCKET=%s\n' "$FILE_INCUS_ADMIN_SOCKET"
  [ -n "${FILE_SERVER_CONTROL:-}" ] && printf 'PATH_FILE_SERVER_CONTROL=%s\n' "$FILE_SERVER_CONTROL"
  [ -n "${FILE_SERVER_DNS_PREFLIGHT:-}" ] && printf 'PATH_FILE_SERVER_DNS_PREFLIGHT=%s\n' "$FILE_SERVER_DNS_PREFLIGHT"
  [ -n "${FILE_SERVER_DNS_RESOLVED:-}" ] && printf 'PATH_FILE_SERVER_DNS_RESOLVED=%s\n' "$FILE_SERVER_DNS_RESOLVED"
  [ -n "${FILE_SERVER_DNS_POLICY:-}" ] && printf 'PATH_FILE_SERVER_DNS_POLICY=%s\n' "$FILE_SERVER_DNS_POLICY"
  [ -n "${FILE_SERVER_DNS_FORWARDING_CANDIDATE:-}" ] && printf 'PATH_FILE_SERVER_DNS_FORWARDING_CANDIDATE=%s\n' "$FILE_SERVER_DNS_FORWARDING_CANDIDATE"
  [ -n "${FILE_SERVER_DNS_CONFIGURATION_TRANSACTION:-}" ] && printf 'PATH_FILE_SERVER_DNS_CONFIGURATION_TRANSACTION=%s\n' "$FILE_SERVER_DNS_CONFIGURATION_TRANSACTION"
  [ -n "${FILE_SERVER_DNS_IDENTITY:-}" ] && printf 'PATH_FILE_SERVER_DNS_IDENTITY=%s\n' "$FILE_SERVER_DNS_IDENTITY"
  [ -n "${FILE_SERVER_DNS_MANAGEMENT_SOCKET:-}" ] && printf 'PATH_FILE_SERVER_DNS_MANAGEMENT_SOCKET=%s\n' "$FILE_SERVER_DNS_MANAGEMENT_SOCKET"
  [ -n "${FILE_SERVER_DNS_TLS_CERTIFICATE:-}" ] && printf 'PATH_FILE_SERVER_DNS_TLS_CERTIFICATE=%s\n' "$FILE_SERVER_DNS_TLS_CERTIFICATE"
  [ -n "${FILE_SERVER_DNS_GUEST_TLS_CERTIFICATE:-}" ] && printf 'PATH_FILE_SERVER_DNS_GUEST_TLS_CERTIFICATE=%s\n' "$FILE_SERVER_DNS_GUEST_TLS_CERTIFICATE"
  [ -n "${FILE_SYSCTL_DNS_FORWARDING:-}" ] && printf 'PATH_FILE_SYSCTL_DNS_FORWARDING=%s\n' "$FILE_SYSCTL_DNS_FORWARDING"
  [ -n "${FILE_SERVER_ARTIFACTS:-}" ] && printf 'PATH_FILE_SERVER_ARTIFACTS=%s\n' "$FILE_SERVER_ARTIFACTS"
  [ -n "${FILE_SERVER_WHISPER_MODEL:-}" ] && printf 'PATH_FILE_SERVER_WHISPER_MODEL=%s\n' "$FILE_SERVER_WHISPER_MODEL"
  [ -n "${DIR_PYTHON3_SITE_PACKAGES:-}" ] && printf 'PATH_DIR_PYTHON3_SITE_PACKAGES=%s\n' "$DIR_PYTHON3_SITE_PACKAGES"
  [ -n "${DIR_PYTHON3_SITE_GITBUILD:-}" ] && printf 'PATH_DIR_PYTHON3_SITE_GITBUILD=%s\n' "$DIR_PYTHON3_SITE_GITBUILD"
  [ -n "${DIR_PYTHON3_SITE_KEY_MANAGER:-}" ] && printf 'PATH_DIR_PYTHON3_SITE_KEY_MANAGER=%s\n' "$DIR_PYTHON3_SITE_KEY_MANAGER"
  [ -n "${DIR_PYTHON3_SITE_LABWC_AI_COPILOTS:-}" ] && printf 'PATH_DIR_PYTHON3_SITE_LABWC_AI_COPILOTS=%s\n' "$DIR_PYTHON3_SITE_LABWC_AI_COPILOTS"
  [ -n "${DIR_PYTHON3_SITE_LABWC_APPEARANCE:-}" ] && printf 'PATH_DIR_PYTHON3_SITE_LABWC_APPEARANCE=%s\n' "$DIR_PYTHON3_SITE_LABWC_APPEARANCE"
  [ -n "${DIR_PYTHON3_SITE_LABWC_COMPZ:-}" ] && printf 'PATH_DIR_PYTHON3_SITE_LABWC_COMPZ=%s\n' "$DIR_PYTHON3_SITE_LABWC_COMPZ"
  [ -n "${DIR_PYTHON3_SITE_LABWC_FIREWALL:-}" ] && printf 'PATH_DIR_PYTHON3_SITE_LABWC_FIREWALL=%s\n' "$DIR_PYTHON3_SITE_LABWC_FIREWALL"
  [ -n "${DIR_PYTHON3_SITE_LABWC_HELP:-}" ] && printf 'PATH_DIR_PYTHON3_SITE_LABWC_HELP=%s\n' "$DIR_PYTHON3_SITE_LABWC_HELP"
  [ -n "${DIR_PYTHON3_SITE_LABWC_MANAGED_APP:-}" ] && printf 'PATH_DIR_PYTHON3_SITE_LABWC_MANAGED_APP=%s\n' "$DIR_PYTHON3_SITE_LABWC_MANAGED_APP"
  [ -n "${DIR_PYTHON3_SITE_MANAGED_WORKFLOWS:-}" ] && printf 'PATH_DIR_PYTHON3_SITE_MANAGED_WORKFLOWS=%s\n' "$DIR_PYTHON3_SITE_MANAGED_WORKFLOWS"
  [ -n "${DIR_USR_LIB_SYSUSERS_D:-}" ] && printf 'PATH_DIR_USR_LIB_SYSUSERS_D=%s\n' "$DIR_USR_LIB_SYSUSERS_D"
  [ -n "${DIR_USR_LIB_CHATGPT:-}" ] && printf 'PATH_DIR_USR_LIB_CHATGPT=%s\n' "$DIR_USR_LIB_CHATGPT"
  [ -n "${DIR_USR_LIB_CHATGPT_RESOURCES:-}" ] && printf 'PATH_DIR_USR_LIB_CHATGPT_RESOURCES=%s\n' "$DIR_USR_LIB_CHATGPT_RESOURCES"
  [ -n "${DIR_USR_LIB_CHATGPT_CODEX:-}" ] && printf 'PATH_DIR_USR_LIB_CHATGPT_CODEX=%s\n' "$DIR_USR_LIB_CHATGPT_CODEX"
  [ -n "${FILE_PYTHON3_SITE_APP_VETH_POLICY:-}" ] && printf 'PATH_FILE_PYTHON3_SITE_APP_VETH_POLICY=%s\n' "$FILE_PYTHON3_SITE_APP_VETH_POLICY"
  [ -n "${FILE_PYTHON3_SITE_CALENDAR_REMINDERS:-}" ] && printf 'PATH_FILE_PYTHON3_SITE_CALENDAR_REMINDERS=%s\n' "$FILE_PYTHON3_SITE_CALENDAR_REMINDERS"
  [ -n "${FILE_PYTHON3_SITE_CALENDAR_REMINDERS_GTK:-}" ] && printf 'PATH_FILE_PYTHON3_SITE_CALENDAR_REMINDERS_GTK=%s\n' "$FILE_PYTHON3_SITE_CALENDAR_REMINDERS_GTK"
  [ -n "${FILE_PYTHON3_SITE_DESKTOP_RUNTIME:-}" ] && printf 'PATH_FILE_PYTHON3_SITE_DESKTOP_RUNTIME=%s\n' "$FILE_PYTHON3_SITE_DESKTOP_RUNTIME"
  [ -n "${FILE_PYTHON3_SITE_LOCAL_REMINDERS:-}" ] && printf 'PATH_FILE_PYTHON3_SITE_LOCAL_REMINDERS=%s\n' "$FILE_PYTHON3_SITE_LOCAL_REMINDERS"
  [ -n "${FILE_PYTHON3_SITE_WAYBAR_STATE:-}" ] && printf 'PATH_FILE_PYTHON3_SITE_WAYBAR_STATE=%s\n' "$FILE_PYTHON3_SITE_WAYBAR_STATE"
  [ -n "${DIR_HARDWARE_TUNING:-}" ] && printf 'PATH_DIR_HARDWARE_TUNING=%s\n' "$DIR_HARDWARE_TUNING"
  [ -n "${FILE_WAYBAR:-}" ] && printf 'PATH_FILE_WAYBAR=%s\n' "$FILE_WAYBAR"
  [ -n "${FILE_LABWC_WAYBAR_RUN:-}" ] && printf 'PATH_FILE_LABWC_WAYBAR_RUN=%s\n' "$FILE_LABWC_WAYBAR_RUN"
  [ -n "${FILE_LABWC_WAYBAR_MENU:-}" ] && printf 'PATH_FILE_LABWC_WAYBAR_MENU=%s\n' "$FILE_LABWC_WAYBAR_MENU"
  [ -n "${FILE_LABWC_WAYBAR_EVENTS:-}" ] && printf 'PATH_FILE_LABWC_WAYBAR_EVENTS=%s\n' "$FILE_LABWC_WAYBAR_EVENTS"
  [ -n "${FILE_LABWC_WAYBAR_BATTERY:-}" ] && printf 'PATH_FILE_LABWC_WAYBAR_BATTERY=%s\n' "$FILE_LABWC_WAYBAR_BATTERY"
  [ -n "${FILE_LABWC_SESSION_CHECK:-}" ] && printf 'PATH_FILE_LABWC_SESSION_CHECK=%s\n' "$FILE_LABWC_SESSION_CHECK"
  [ -n "${FILE_LABWC_SYSTEM_MENU_ACTION:-}" ] && printf 'PATH_FILE_LABWC_SYSTEM_MENU_ACTION=%s\n' "$FILE_LABWC_SYSTEM_MENU_ACTION"
  [ -n "${FILE_LABWC_MAIN_MENU:-}" ] && printf 'PATH_FILE_LABWC_MAIN_MENU=%s\n' "$FILE_LABWC_MAIN_MENU"
  [ -n "${FILE_LABWC_SESSION:-}" ] && printf 'PATH_FILE_LABWC_SESSION=%s\n' "$FILE_LABWC_SESSION"
  [ -n "${DIR_TAILSCALE_STATE:-}" ] && printf 'PATH_DIR_TAILSCALE_STATE=%s\n' "$DIR_TAILSCALE_STATE"
  [ -n "${DIR_CROWDSEC_STATE:-}" ] && printf 'PATH_DIR_CROWDSEC_STATE=%s\n' "$DIR_CROWDSEC_STATE"
  [ -n "${DIR_CRYPTO_STATE:-}" ] && printf 'PATH_DIR_CRYPTO_STATE=%s\n' "$DIR_CRYPTO_STATE"
  [ -n "${DIR_PODMAN_STATE:-}" ] && printf 'PATH_DIR_PODMAN_STATE=%s\n' "$DIR_PODMAN_STATE"
  [ -n "${DIR_FIRSTBOOT_LIB:-}" ] && printf 'PATH_DIR_FIRSTBOOT_LIB=%s\n' "$DIR_FIRSTBOOT_LIB"
  [ -n "${DIR_LIBEXEC_INSTALL_TOOLS:-}" ] && printf 'PATH_DIR_LIBEXEC_INSTALL_TOOLS=%s\n' "$DIR_LIBEXEC_INSTALL_TOOLS"
  [ -n "${DIR_ZRAM_PERL_MODULES:-}" ] && printf 'PATH_DIR_ZRAM_PERL_MODULES=%s\n' "$DIR_ZRAM_PERL_MODULES"
  [ -n "${DIR_OPT_TOR_BROWSER:-}" ] && printf 'PATH_DIR_OPT_TOR_BROWSER=%s\n' "$DIR_OPT_TOR_BROWSER"
  [ -n "${DIR_OPT_TOR_BROWSER_BROWSER:-}" ] && printf 'PATH_DIR_OPT_TOR_BROWSER_BROWSER=%s\n' "$DIR_OPT_TOR_BROWSER_BROWSER"
  [ -n "${DIR_OPT_TOR_BROWSER_DISTRIBUTION:-}" ] && printf 'PATH_DIR_OPT_TOR_BROWSER_DISTRIBUTION=%s\n' "$DIR_OPT_TOR_BROWSER_DISTRIBUTION"
  [ -n "${DIR_OPT_CHROME:-}" ] && printf 'PATH_DIR_OPT_CHROME=%s\n' "$DIR_OPT_CHROME"
  [ -n "${DIR_OPT_EDGE:-}" ] && printf 'PATH_DIR_OPT_EDGE=%s\n' "$DIR_OPT_EDGE"
  [ -n "${DIR_OPT_BITWARDEN:-}" ] && printf 'PATH_DIR_OPT_BITWARDEN=%s\n' "$DIR_OPT_BITWARDEN"
  [ -n "${DIR_OPT_DISCORD:-}" ] && printf 'PATH_DIR_OPT_DISCORD=%s\n' "$DIR_OPT_DISCORD"
  [ -n "${DIR_OPT_FILEN:-}" ] && printf 'PATH_DIR_OPT_FILEN=%s\n' "$DIR_OPT_FILEN"
  [ -n "${DIR_OPT_GLIBC:-}" ] && printf 'PATH_DIR_OPT_GLIBC=%s\n' "$DIR_OPT_GLIBC"
  [ -n "${DIR_OPT_INCUS:-}" ] && printf 'PATH_DIR_OPT_INCUS=%s\n' "$DIR_OPT_INCUS"
  [ -n "${DIR_OPT_LEDGER_LIVE:-}" ] && printf 'PATH_DIR_OPT_LEDGER_LIVE=%s\n' "$DIR_OPT_LEDGER_LIVE"
  [ -n "${DIR_OPT_MULLVAD:-}" ] && printf 'PATH_DIR_OPT_MULLVAD=%s\n' "$DIR_OPT_MULLVAD"
  [ -n "${DIR_OPT_OBSIDIAN:-}" ] && printf 'PATH_DIR_OPT_OBSIDIAN=%s\n' "$DIR_OPT_OBSIDIAN"
  [ -n "${DIR_OPT_POSTMAN:-}" ] && printf 'PATH_DIR_OPT_POSTMAN=%s\n' "$DIR_OPT_POSTMAN"
  [ -n "${DIR_OPT_SLEEK:-}" ] && printf 'PATH_DIR_OPT_SLEEK=%s\n' "$DIR_OPT_SLEEK"
  [ -n "${DIR_OPT_TUTA_MAIL:-}" ] && printf 'PATH_DIR_OPT_TUTA_MAIL=%s\n' "$DIR_OPT_TUTA_MAIL"
  [ -n "${DIR_OPT_VIVALDI:-}" ] && printf 'PATH_DIR_OPT_VIVALDI=%s\n' "$DIR_OPT_VIVALDI"
  [ -n "${DIR_OPT_WAYPAPER:-}" ] && printf 'PATH_DIR_OPT_WAYPAPER=%s\n' "$DIR_OPT_WAYPAPER"
  [ -n "${DIR_OPT_XWAYLAND:-}" ] && printf 'PATH_DIR_OPT_XWAYLAND=%s\n' "$DIR_OPT_XWAYLAND"
  [ -n "${DIR_APT_CONF_D:-}" ] && printf 'PATH_DIR_APT_CONF_D=%s\n' "$DIR_APT_CONF_D"
  [ -n "${DIR_APT_KEYRINGS:-}" ] && printf 'PATH_DIR_APT_KEYRINGS=%s\n' "$DIR_APT_KEYRINGS"
  [ -n "${DIR_APT_SOURCES_LIST_D:-}" ] && printf 'PATH_DIR_APT_SOURCES_LIST_D=%s\n' "$DIR_APT_SOURCES_LIST_D"
  [ -n "${DIR_ETC_SKEL_DESKTOP_APPLICATIONS:-}" ] && printf 'PATH_DIR_ETC_SKEL_DESKTOP_APPLICATIONS=%s\n' "$DIR_ETC_SKEL_DESKTOP_APPLICATIONS"
  [ -n "${DIR_SECURE_BOOT_STATE:-}" ] && printf 'PATH_DIR_SECURE_BOOT_STATE=%s\n' "$DIR_SECURE_BOOT_STATE"
  [ -n "${DIR_RUN_SYSCTL:-}" ] && printf 'PATH_DIR_RUN_SYSCTL=%s\n' "$DIR_RUN_SYSCTL"
  [ -n "${DIR_SECURE_BOOT_ENROLLMENT_ESP:-}" ] && printf 'PATH_DIR_SECURE_BOOT_ENROLLMENT_ESP=%s\n' "$DIR_SECURE_BOOT_ENROLLMENT_ESP"
  [ -n "${FILE_BOOTPROFILE_APPLY:-}" ] && printf 'PATH_FILE_BOOTPROFILE_APPLY=%s\n' "$FILE_BOOTPROFILE_APPLY"
  [ -n "${FILE_BOOTPROFILE_SERVICE:-}" ] && printf 'PATH_FILE_BOOTPROFILE_SERVICE=%s\n' "$FILE_BOOTPROFILE_SERVICE"
  [ -n "${FILE_MODPROBE_ZRAM:-}" ] && printf 'PATH_FILE_MODPROBE_ZRAM=%s\n' "$FILE_MODPROBE_ZRAM"
  [ -n "${FILE_MODULES_LOAD_ZRAM:-}" ] && printf 'PATH_FILE_MODULES_LOAD_ZRAM=%s\n' "$FILE_MODULES_LOAD_ZRAM"
  [ -n "${FILE_ZRAM_DEFAULT:-}" ] && printf 'PATH_FILE_ZRAM_DEFAULT=%s\n' "$FILE_ZRAM_DEFAULT"
  [ -n "${FILE_ZRAM_CONFIG:-}" ] && printf 'PATH_FILE_ZRAM_CONFIG=%s\n' "$FILE_ZRAM_CONFIG"
  [ -n "${FILE_ZRAM_TMPFILES:-}" ] && printf 'PATH_FILE_ZRAM_TMPFILES=%s\n' "$FILE_ZRAM_TMPFILES"
  [ -n "${FILE_ZRAM_RSYSLOG:-}" ] && printf 'PATH_FILE_ZRAM_RSYSLOG=%s\n' "$FILE_ZRAM_RSYSLOG"
  [ -n "${FILE_ZRAM_LOGROTATE:-}" ] && printf 'PATH_FILE_ZRAM_LOGROTATE=%s\n' "$FILE_ZRAM_LOGROTATE"
  [ -n "${FILE_ZRAM_SETUP_HELPER:-}" ] && printf 'PATH_FILE_ZRAM_SETUP_HELPER=%s\n' "$FILE_ZRAM_SETUP_HELPER"
  [ -n "${FILE_ZRAM_WRITEBACK_HELPER:-}" ] && printf 'PATH_FILE_ZRAM_WRITEBACK_HELPER=%s\n' "$FILE_ZRAM_WRITEBACK_HELPER"
  [ -n "${FILE_ZRAM_SETUP_SERVICE:-}" ] && printf 'PATH_FILE_ZRAM_SETUP_SERVICE=%s\n' "$FILE_ZRAM_SETUP_SERVICE"
  [ -n "${FILE_ZRAM_WRITEBACK_SERVICE:-}" ] && printf 'PATH_FILE_ZRAM_WRITEBACK_SERVICE=%s\n' "$FILE_ZRAM_WRITEBACK_SERVICE"
  [ -n "${FILE_ZRAM_WRITEBACKD_SERVICE:-}" ] && printf 'PATH_FILE_ZRAM_WRITEBACKD_SERVICE=%s\n' "$FILE_ZRAM_WRITEBACKD_SERVICE"
  [ -n "${FILE_ZRAM_IDLE_WRITEBACK_TIMER:-}" ] && printf 'PATH_FILE_ZRAM_IDLE_WRITEBACK_TIMER=%s\n' "$FILE_ZRAM_IDLE_WRITEBACK_TIMER"
  [ -n "${FILE_ZRAM_COLD_TIER_TIMER:-}" ] && printf 'PATH_FILE_ZRAM_COLD_TIER_TIMER=%s\n' "$FILE_ZRAM_COLD_TIER_TIMER"
  [ -n "${FILE_RSYSLOG_CONF:-}" ] && printf 'PATH_FILE_RSYSLOG_CONF=%s\n' "$FILE_RSYSLOG_CONF"
  [ -n "${FILE_LOGROTATE_CONF:-}" ] && printf 'PATH_FILE_LOGROTATE_CONF=%s\n' "$FILE_LOGROTATE_CONF"
  [ -n "${FILE_SWAP_FALLBACK_CONFIG:-}" ] && printf 'PATH_FILE_SWAP_FALLBACK_CONFIG=%s\n' "$FILE_SWAP_FALLBACK_CONFIG"
  [ -n "${FILE_SWAP_FALLBACK_HELPER:-}" ] && printf 'PATH_FILE_SWAP_FALLBACK_HELPER=%s\n' "$FILE_SWAP_FALLBACK_HELPER"
  [ -n "${FILE_SWAP_FALLBACK_SERVICE:-}" ] && printf 'PATH_FILE_SWAP_FALLBACK_SERVICE=%s\n' "$FILE_SWAP_FALLBACK_SERVICE"
  [ -n "${FILE_FIRSTBOOT_HELPER:-}" ] && printf 'PATH_FILE_FIRSTBOOT_HELPER=%s\n' "$FILE_FIRSTBOOT_HELPER"
  [ -n "${FILE_FIRSTBOOT_INITRAMFS_CLEANUP_PENDING:-}" ] && printf 'PATH_FILE_FIRSTBOOT_INITRAMFS_CLEANUP_PENDING=%s\n' "$FILE_FIRSTBOOT_INITRAMFS_CLEANUP_PENDING"
  [ -n "${FILE_FIRSTBOOT_SERVICE:-}" ] && printf 'PATH_FILE_FIRSTBOOT_SERVICE=%s\n' "$FILE_FIRSTBOOT_SERVICE"
  [ -n "${FILE_SECONDBOOT_HELPER:-}" ] && printf 'PATH_FILE_SECONDBOOT_HELPER=%s\n' "$FILE_SECONDBOOT_HELPER"
  [ -n "${FILE_SECONDBOOT_SERVICE:-}" ] && printf 'PATH_FILE_SECONDBOOT_SERVICE=%s\n' "$FILE_SECONDBOOT_SERVICE"
  [ -n "${FILE_XSSH_SEND:-}" ] && printf 'PATH_FILE_XSSH_SEND=%s\n' "$FILE_XSSH_SEND"
  [ -n "${FILE_XSSH_RETRIEVE:-}" ] && printf 'PATH_FILE_XSSH_RETRIEVE=%s\n' "$FILE_XSSH_RETRIEVE"
  [ -n "${FILE_NETWORK_INTERFACES:-}" ] && printf 'PATH_FILE_NETWORK_INTERFACES=%s\n' "$FILE_NETWORK_INTERFACES"
  [ -n "${FILE_MANAGED_NETWORK_INTERFACES:-}" ] && printf 'PATH_FILE_MANAGED_NETWORK_INTERFACES=%s\n' "$FILE_MANAGED_NETWORK_INTERFACES"
  [ -n "${FILE_MANAGED_NETWORK_DEFAULT:-}" ] && printf 'PATH_FILE_MANAGED_NETWORK_DEFAULT=%s\n' "$FILE_MANAGED_NETWORK_DEFAULT"
  [ -n "${FILE_MANAGED_NETWORK_HELPER:-}" ] && printf 'PATH_FILE_MANAGED_NETWORK_HELPER=%s\n' "$FILE_MANAGED_NETWORK_HELPER"
  [ -n "${FILE_SOFTWARE_RELEASE_POLICY:-}" ] && printf 'PATH_FILE_SOFTWARE_RELEASE_POLICY=%s\n' "$FILE_SOFTWARE_RELEASE_POLICY"
  [ -n "${FILE_MANAGED_NETWORK_SERVICE:-}" ] && printf 'PATH_FILE_MANAGED_NETWORK_SERVICE=%s\n' "$FILE_MANAGED_NETWORK_SERVICE"
  [ -n "${FILE_TAILSCALED_DEFAULT:-}" ] && printf 'PATH_FILE_TAILSCALED_DEFAULT=%s\n' "$FILE_TAILSCALED_DEFAULT"
  [ -n "${FILE_TAILSCALE_MANAGED_HELPER:-}" ] && printf 'PATH_FILE_TAILSCALE_MANAGED_HELPER=%s\n' "$FILE_TAILSCALE_MANAGED_HELPER"
  [ -n "${FILE_TAILSCALE_BOOTSTRAP_SERVICE:-}" ] && printf 'PATH_FILE_TAILSCALE_BOOTSTRAP_SERVICE=%s\n' "$FILE_TAILSCALE_BOOTSTRAP_SERVICE"
  [ -n "${FILE_TAILSCALED_SERVICE_OVERRIDE:-}" ] && printf 'PATH_FILE_TAILSCALED_SERVICE_OVERRIDE=%s\n' "$FILE_TAILSCALED_SERVICE_OVERRIDE"
  [ -n "${FILE_TAILSCALE_TUN_MODULES_LOAD:-}" ] && printf 'PATH_FILE_TAILSCALE_TUN_MODULES_LOAD=%s\n' "$FILE_TAILSCALE_TUN_MODULES_LOAD"
  [ -n "${FILE_TAILSCALE_AUTH_KEY:-}" ] && printf 'PATH_FILE_TAILSCALE_AUTH_KEY=%s\n' "$FILE_TAILSCALE_AUTH_KEY"
  [ -n "${FILE_TAILSCALE_COMPLETE:-}" ] && printf 'PATH_FILE_TAILSCALE_COMPLETE=%s\n' "$FILE_TAILSCALE_COMPLETE"
  [ -n "${FILE_TAILSCALE_STATUS:-}" ] && printf 'PATH_FILE_TAILSCALE_STATUS=%s\n' "$FILE_TAILSCALE_STATUS"
  [ -n "${FILE_MANAGED_SYNCTHING_DEFAULT:-}" ] && printf 'PATH_FILE_MANAGED_SYNCTHING_DEFAULT=%s\n' "$FILE_MANAGED_SYNCTHING_DEFAULT"
  [ -n "${FILE_MANAGED_SYNCTHING_HELPER:-}" ] && printf 'PATH_FILE_MANAGED_SYNCTHING_HELPER=%s\n' "$FILE_MANAGED_SYNCTHING_HELPER"
  [ -n "${FILE_MANAGED_SYNCTHING_SERVICE:-}" ] && printf 'PATH_FILE_MANAGED_SYNCTHING_SERVICE=%s\n' "$FILE_MANAGED_SYNCTHING_SERVICE"
  [ -n "${FILE_CROWDSEC_ENROLL_TOKEN:-}" ] && printf 'PATH_FILE_CROWDSEC_ENROLL_TOKEN=%s\n' "$FILE_CROWDSEC_ENROLL_TOKEN"
  [ -n "${FILE_CROWDSEC_COMPLETE:-}" ] && printf 'PATH_FILE_CROWDSEC_COMPLETE=%s\n' "$FILE_CROWDSEC_COMPLETE"
  [ -n "${FILE_CROWDSEC_STATUS:-}" ] && printf 'PATH_FILE_CROWDSEC_STATUS=%s\n' "$FILE_CROWDSEC_STATUS"
  [ -n "${FILE_CRYPTO_STATE_CONFIG:-}" ] && printf 'PATH_FILE_CRYPTO_STATE_CONFIG=%s\n' "$FILE_CRYPTO_STATE_CONFIG"
  [ -n "${FILE_CRYPTO_PENDING:-}" ] && printf 'PATH_FILE_CRYPTO_PENDING=%s\n' "$FILE_CRYPTO_PENDING"
  [ -n "${FILE_CRYPTO_COMPLETE:-}" ] && printf 'PATH_FILE_CRYPTO_COMPLETE=%s\n' "$FILE_CRYPTO_COMPLETE"
  [ -n "${FILE_WPA_SUPPLICANT_CONF:-}" ] && printf 'PATH_FILE_WPA_SUPPLICANT_CONF=%s\n' "$FILE_WPA_SUPPLICANT_CONF"
  [ -n "${FILE_WPA_SUPPLICANT_P2P_DEVICE_CONF:-}" ] && printf 'PATH_FILE_WPA_SUPPLICANT_P2P_DEVICE_CONF=%s\n' "$FILE_WPA_SUPPLICANT_P2P_DEVICE_CONF"
  [ -n "${FILE_WPA_SUPPLICANT_DBUS_SERVICE_OVERRIDE:-}" ] && printf 'PATH_FILE_WPA_SUPPLICANT_DBUS_SERVICE_OVERRIDE=%s\n' "$FILE_WPA_SUPPLICANT_DBUS_SERVICE_OVERRIDE"
  [ -n "${FILE_WPA_SUPPLICANT_DBUS_SERVICE_ALIAS:-}" ] && printf 'PATH_FILE_WPA_SUPPLICANT_DBUS_SERVICE_ALIAS=%s\n' "$FILE_WPA_SUPPLICANT_DBUS_SERVICE_ALIAS"
  [ -n "${FILE_SMARTMONTOOLS_DEFAULT:-}" ] && printf 'PATH_FILE_SMARTMONTOOLS_DEFAULT=%s\n' "$FILE_SMARTMONTOOLS_DEFAULT"
  [ -n "${FILE_NETWORKMANAGER_LINK_PRIVACY_CONF:-}" ] && printf 'PATH_FILE_NETWORKMANAGER_LINK_PRIVACY_CONF=%s\n' "$FILE_NETWORKMANAGER_LINK_PRIVACY_CONF"
  [ -n "${FILE_NETWORKMANAGER_MANAGED_UNMANAGED_CONF:-}" ] && printf 'PATH_FILE_NETWORKMANAGER_MANAGED_UNMANAGED_CONF=%s\n' "$FILE_NETWORKMANAGER_MANAGED_UNMANAGED_CONF"
  [ -n "${FILE_POLKIT_RUNTIME_TMPFILES:-}" ] && printf 'PATH_FILE_POLKIT_RUNTIME_TMPFILES=%s\n' "$FILE_POLKIT_RUNTIME_TMPFILES"
  [ -n "${FILE_INITRAMFS_HEALTH_COMMON:-}" ] && printf 'PATH_FILE_INITRAMFS_HEALTH_COMMON=%s\n' "$FILE_INITRAMFS_HEALTH_COMMON"
  [ -n "${FILE_TPM2_CRYPTROOT_CONFIG:-}" ] && printf 'PATH_FILE_TPM2_CRYPTROOT_CONFIG=%s\n' "$FILE_TPM2_CRYPTROOT_CONFIG"
  [ -n "${FILE_INITRAMFS_HEALTH_INIT_TOP:-}" ] && printf 'PATH_FILE_INITRAMFS_HEALTH_INIT_TOP=%s\n' "$FILE_INITRAMFS_HEALTH_INIT_TOP"
  [ -n "${FILE_INITRAMFS_HEALTH_INIT_PREMOUNT:-}" ] && printf 'PATH_FILE_INITRAMFS_HEALTH_INIT_PREMOUNT=%s\n' "$FILE_INITRAMFS_HEALTH_INIT_PREMOUNT"
  [ -n "${FILE_INITRAMFS_HEALTH_LOCAL_TOP:-}" ] && printf 'PATH_FILE_INITRAMFS_HEALTH_LOCAL_TOP=%s\n' "$FILE_INITRAMFS_HEALTH_LOCAL_TOP"
  [ -n "${FILE_INITRAMFS_HEALTH_LOCAL_BLOCK:-}" ] && printf 'PATH_FILE_INITRAMFS_HEALTH_LOCAL_BLOCK=%s\n' "$FILE_INITRAMFS_HEALTH_LOCAL_BLOCK"
  [ -n "${FILE_INITRAMFS_HEALTH_LOCAL_PREMOUNT:-}" ] && printf 'PATH_FILE_INITRAMFS_HEALTH_LOCAL_PREMOUNT=%s\n' "$FILE_INITRAMFS_HEALTH_LOCAL_PREMOUNT"
  [ -n "${FILE_INITRAMFS_HEALTH_LOCAL_BOTTOM:-}" ] && printf 'PATH_FILE_INITRAMFS_HEALTH_LOCAL_BOTTOM=%s\n' "$FILE_INITRAMFS_HEALTH_LOCAL_BOTTOM"
  [ -n "${FILE_INITRAMFS_HEALTH_INIT_BOTTOM:-}" ] && printf 'PATH_FILE_INITRAMFS_HEALTH_INIT_BOTTOM=%s\n' "$FILE_INITRAMFS_HEALTH_INIT_BOTTOM"
  [ -n "${FILE_TMPFS_PRE_CLEAN_HELPER:-}" ] && printf 'PATH_FILE_TMPFS_PRE_CLEAN_HELPER=%s\n' "$FILE_TMPFS_PRE_CLEAN_HELPER"
  [ -n "${FILE_TMPFS_PRE_CLEAN_SERVICE:-}" ] && printf 'PATH_FILE_TMPFS_PRE_CLEAN_SERVICE=%s\n' "$FILE_TMPFS_PRE_CLEAN_SERVICE"
  [ -n "${FILE_TMPFS_PRE_CLEAN_TMP_MOUNT_OVERRIDE:-}" ] && printf 'PATH_FILE_TMPFS_PRE_CLEAN_TMP_MOUNT_OVERRIDE=%s\n' "$FILE_TMPFS_PRE_CLEAN_TMP_MOUNT_OVERRIDE"
  [ -n "${FILE_TMPFS_PRE_CLEAN_DEV_SHM_MOUNT_OVERRIDE:-}" ] && printf 'PATH_FILE_TMPFS_PRE_CLEAN_DEV_SHM_MOUNT_OVERRIDE=%s\n' "$FILE_TMPFS_PRE_CLEAN_DEV_SHM_MOUNT_OVERRIDE"
  [ -n "${FILE_TMPFS_PRE_CLEAN_VAR_SPOOL_RSYSLOG_MOUNT_OVERRIDE:-}" ] && printf 'PATH_FILE_TMPFS_PRE_CLEAN_VAR_SPOOL_RSYSLOG_MOUNT_OVERRIDE=%s\n' "$FILE_TMPFS_PRE_CLEAN_VAR_SPOOL_RSYSLOG_MOUNT_OVERRIDE"
  [ -n "${FILE_TMPFS_PRE_CLEAN_VAR_LOG_MOUNT_OVERRIDE:-}" ] && printf 'PATH_FILE_TMPFS_PRE_CLEAN_VAR_LOG_MOUNT_OVERRIDE=%s\n' "$FILE_TMPFS_PRE_CLEAN_VAR_LOG_MOUNT_OVERRIDE"
  [ -n "${FILE_TMPFS_PRE_CLEAN_VAR_CACHE_MOUNT_OVERRIDE:-}" ] && printf 'PATH_FILE_TMPFS_PRE_CLEAN_VAR_CACHE_MOUNT_OVERRIDE=%s\n' "$FILE_TMPFS_PRE_CLEAN_VAR_CACHE_MOUNT_OVERRIDE"
  [ -n "${FILE_TMPFS_PRE_CLEAN_APT_LISTS_MOUNT_OVERRIDE:-}" ] && printf 'PATH_FILE_TMPFS_PRE_CLEAN_APT_LISTS_MOUNT_OVERRIDE=%s\n' "$FILE_TMPFS_PRE_CLEAN_APT_LISTS_MOUNT_OVERRIDE"
  [ -n "${FILE_TMPFS_PRE_CLEAN_COREDUMP_MOUNT_OVERRIDE:-}" ] && printf 'PATH_FILE_TMPFS_PRE_CLEAN_COREDUMP_MOUNT_OVERRIDE=%s\n' "$FILE_TMPFS_PRE_CLEAN_COREDUMP_MOUNT_OVERRIDE"
  [ -n "${FILE_TMPFS_PRE_CLEAN_DATA_RUN_MOUNT_OVERRIDE:-}" ] && printf 'PATH_FILE_TMPFS_PRE_CLEAN_DATA_RUN_MOUNT_OVERRIDE=%s\n' "$FILE_TMPFS_PRE_CLEAN_DATA_RUN_MOUNT_OVERRIDE"
  [ -n "${FILE_DATA_RUN_TMPFILES:-}" ] && printf 'PATH_FILE_DATA_RUN_TMPFILES=%s\n' "$FILE_DATA_RUN_TMPFILES"
  [ -n "${FILE_APT_REFRESH_LISTS_HELPER:-}" ] && printf 'PATH_FILE_APT_REFRESH_LISTS_HELPER=%s\n' "$FILE_APT_REFRESH_LISTS_HELPER"
  [ -n "${FILE_APT_REFRESH_LISTS_SERVICE:-}" ] && printf 'PATH_FILE_APT_REFRESH_LISTS_SERVICE=%s\n' "$FILE_APT_REFRESH_LISTS_SERVICE"
  [ -n "${FILE_APT_DAILY_SERVICE_OVERRIDE:-}" ] && printf 'PATH_FILE_APT_DAILY_SERVICE_OVERRIDE=%s\n' "$FILE_APT_DAILY_SERVICE_OVERRIDE"
  [ -n "${FILE_APT_DEBIAN_ARCHIVE_KEYRING:-}" ] && printf 'PATH_FILE_APT_DEBIAN_ARCHIVE_KEYRING=%s\n' "$FILE_APT_DEBIAN_ARCHIVE_KEYRING"
  [ -n "${FILE_APT_CUDA_LEGACY_ARCHIVE_KEY:-}" ] && printf 'PATH_FILE_APT_CUDA_LEGACY_ARCHIVE_KEY=%s\n' "$FILE_APT_CUDA_LEGACY_ARCHIVE_KEY"
  [ -n "${FILE_FSTRIM_SERVICE_OVERRIDE:-}" ] && printf 'PATH_FILE_FSTRIM_SERVICE_OVERRIDE=%s\n' "$FILE_FSTRIM_SERVICE_OVERRIDE"
  [ -n "${FILE_FSTRIM_TIMER_OVERRIDE:-}" ] && printf 'PATH_FILE_FSTRIM_TIMER_OVERRIDE=%s\n' "$FILE_FSTRIM_TIMER_OVERRIDE"
  [ -n "${FILE_APT_LISTCHANGES_CONF:-}" ] && printf 'PATH_FILE_APT_LISTCHANGES_CONF=%s\n' "$FILE_APT_LISTCHANGES_CONF"
  [ -n "${FILE_JOURNALD_STORAGE_CONF:-}" ] && printf 'PATH_FILE_JOURNALD_STORAGE_CONF=%s\n' "$FILE_JOURNALD_STORAGE_CONF"
  [ -n "${FILE_LOGIND_OVERRIDE_CONF:-}" ] && printf 'PATH_FILE_LOGIND_OVERRIDE_CONF=%s\n' "$FILE_LOGIND_OVERRIDE_CONF"
  [ -n "${FILE_TMPFILES_VOLATILE_BASE:-}" ] && printf 'PATH_FILE_TMPFILES_VOLATILE_BASE=%s\n' "$FILE_TMPFILES_VOLATILE_BASE"
  [ -n "${FILE_TMPFILES_VAR_LOG_GENERATED:-}" ] && printf 'PATH_FILE_TMPFILES_VAR_LOG_GENERATED=%s\n' "$FILE_TMPFILES_VAR_LOG_GENERATED"
  [ -n "${FILE_TMPFILES_APT_LISTS_GENERATED:-}" ] && printf 'PATH_FILE_TMPFILES_APT_LISTS_GENERATED=%s\n' "$FILE_TMPFILES_APT_LISTS_GENERATED"
  [ -n "${FILE_TMPFILES_VAR_CACHE_GENERATED:-}" ] && printf 'PATH_FILE_TMPFILES_VAR_CACHE_GENERATED=%s\n' "$FILE_TMPFILES_VAR_CACHE_GENERATED"
  [ -n "${FILE_UDISKS2_CONF:-}" ] && printf 'PATH_FILE_UDISKS2_CONF=%s\n' "$FILE_UDISKS2_CONF"
  [ -n "${FILE_UDISKS2_MOUNT_OPTIONS_CONF:-}" ] && printf 'PATH_FILE_UDISKS2_MOUNT_OPTIONS_CONF=%s\n' "$FILE_UDISKS2_MOUNT_OPTIONS_CONF"
  [ -n "${FILE_UDEV_HARDENING_CONF:-}" ] && printf 'PATH_FILE_UDEV_HARDENING_CONF=%s\n' "$FILE_UDEV_HARDENING_CONF"
  [ -n "${FILE_UDEV_UDISKS_BEHAVIOR_RULES:-}" ] && printf 'PATH_FILE_UDEV_UDISKS_BEHAVIOR_RULES=%s\n' "$FILE_UDEV_UDISKS_BEHAVIOR_RULES"
  [ -n "${FILE_POLKIT_USB_POLICY_RULES:-}" ] && printf 'PATH_FILE_POLKIT_USB_POLICY_RULES=%s\n' "$FILE_POLKIT_USB_POLICY_RULES"
  [ -n "${FILE_SECURE_BOOT_TOOL:-}" ] && printf 'PATH_FILE_SECURE_BOOT_TOOL=%s\n' "$FILE_SECURE_BOOT_TOOL"
  [ -n "${FILE_BTRFSMAINTENANCE_DEFAULT:-}" ] && printf 'PATH_FILE_BTRFSMAINTENANCE_DEFAULT=%s\n' "$FILE_BTRFSMAINTENANCE_DEFAULT"
  [ -n "${FILE_MODULES_LOAD_BTRFS:-}" ] && printf 'PATH_FILE_MODULES_LOAD_BTRFS=%s\n' "$FILE_MODULES_LOAD_BTRFS"
  [ -n "${FILE_LUKS_MOK_OPEN_HELPER:-}" ] && printf 'PATH_FILE_LUKS_MOK_OPEN_HELPER=%s\n' "$FILE_LUKS_MOK_OPEN_HELPER"
  [ -n "${FILE_LUKS_MOK_CLOSE_HELPER:-}" ] && printf 'PATH_FILE_LUKS_MOK_CLOSE_HELPER=%s\n' "$FILE_LUKS_MOK_CLOSE_HELPER"
  [ -n "${FILE_LUKS_MOK_PASSWD_HELPER:-}" ] && printf 'PATH_FILE_LUKS_MOK_PASSWD_HELPER=%s\n' "$FILE_LUKS_MOK_PASSWD_HELPER"
  [ -n "${FILE_SECURE_BOOT_CONFIG:-}" ] && printf 'PATH_FILE_SECURE_BOOT_CONFIG=%s\n' "$FILE_SECURE_BOOT_CONFIG"
  [ -n "${FILE_SECURE_BOOT_MOK_KEY:-}" ] && printf 'PATH_FILE_SECURE_BOOT_MOK_KEY=%s\n' "$FILE_SECURE_BOOT_MOK_KEY"
  [ -n "${FILE_SECURE_BOOT_MOK_CERT_PEM:-}" ] && printf 'PATH_FILE_SECURE_BOOT_MOK_CERT_PEM=%s\n' "$FILE_SECURE_BOOT_MOK_CERT_PEM"
  [ -n "${FILE_SECURE_BOOT_MOK_CERT_DER:-}" ] && printf 'PATH_FILE_SECURE_BOOT_MOK_CERT_DER=%s\n' "$FILE_SECURE_BOOT_MOK_CERT_DER"
  [ -n "${FILE_SECURE_BOOT_OPENSSL_CONFIG:-}" ] && printf 'PATH_FILE_SECURE_BOOT_OPENSSL_CONFIG=%s\n' "$FILE_SECURE_BOOT_OPENSSL_CONFIG"
  [ -n "${FILE_DKMS_FRAMEWORK_SECURE_BOOT:-}" ] && printf 'PATH_FILE_DKMS_FRAMEWORK_SECURE_BOOT=%s\n' "$FILE_DKMS_FRAMEWORK_SECURE_BOOT"
  [ -n "${FILE_KERNEL_POSTINST_SIGN:-}" ] && printf 'PATH_FILE_KERNEL_POSTINST_SIGN=%s\n' "$FILE_KERNEL_POSTINST_SIGN"
  [ -n "${FILE_KERNEL_POSTRM_SIGN:-}" ] && printf 'PATH_FILE_KERNEL_POSTRM_SIGN=%s\n' "$FILE_KERNEL_POSTRM_SIGN"
  [ -n "${FILE_KERNEL_HEADER_POSTINST_SIGN:-}" ] && printf 'PATH_FILE_KERNEL_HEADER_POSTINST_SIGN=%s\n' "$FILE_KERNEL_HEADER_POSTINST_SIGN"
  [ -n "${FILE_SYSCTL_BASELINE:-}" ] && printf 'PATH_FILE_SYSCTL_BASELINE=%s\n' "$FILE_SYSCTL_BASELINE"
  [ -n "${FILE_SYSCTL_STORAGE_MEMORY:-}" ] && printf 'PATH_FILE_SYSCTL_STORAGE_MEMORY=%s\n' "$FILE_SYSCTL_STORAGE_MEMORY"
  [ -n "${FILE_SYSCTL_PROFILE_DEFAULT:-}" ] && printf 'PATH_FILE_SYSCTL_PROFILE_DEFAULT=%s\n' "$FILE_SYSCTL_PROFILE_DEFAULT"
  [ -n "${FILE_SYSCTL_PROFILE_HARDENED:-}" ] && printf 'PATH_FILE_SYSCTL_PROFILE_HARDENED=%s\n' "$FILE_SYSCTL_PROFILE_HARDENED"
  [ -n "${FILE_SYSCTL_PROFILE_PERFORMANCE:-}" ] && printf 'PATH_FILE_SYSCTL_PROFILE_PERFORMANCE=%s\n' "$FILE_SYSCTL_PROFILE_PERFORMANCE"
  [ -n "${FILE_SYSCTL_FAMILY_OVERRIDE:-}" ] && printf 'PATH_FILE_SYSCTL_FAMILY_OVERRIDE=%s\n' "$FILE_SYSCTL_FAMILY_OVERRIDE"
  [ -n "${FILE_SECURE_BOOT_MOK_CERT_DER_ESP:-}" ] && printf 'PATH_FILE_SECURE_BOOT_MOK_CERT_DER_ESP=%s\n' "$FILE_SECURE_BOOT_MOK_CERT_DER_ESP"
  [ -n "${FILE_GRUB_DISPLAY_CFG:-}" ] && printf 'PATH_FILE_GRUB_DISPLAY_CFG=%s\n' "$FILE_GRUB_DISPLAY_CFG"
  [ -n "${FILE_GRUB_DISPLAY_FONT:-}" ] && printf 'PATH_FILE_GRUB_DISPLAY_FONT=%s\n' "$FILE_GRUB_DISPLAY_FONT"
  [ -n "${FILE_TIMESHIFT_CONFIG:-}" ] && printf 'PATH_FILE_TIMESHIFT_CONFIG=%s\n' "$FILE_TIMESHIFT_CONFIG"
  [ -n "${FILE_TIMESHIFT_SNAPSHOT_HELPER:-}" ] && printf 'PATH_FILE_TIMESHIFT_SNAPSHOT_HELPER=%s\n' "$FILE_TIMESHIFT_SNAPSHOT_HELPER"
  [ -n "${FILE_TIMESHIFT_NOTIFY_SHIM:-}" ] && printf 'PATH_FILE_TIMESHIFT_NOTIFY_SHIM=%s\n' "$FILE_TIMESHIFT_NOTIFY_SHIM"
  [ -n "${FILE_TIMESHIFT_GRUB_REFRESH_HOOK:-}" ] && printf 'PATH_FILE_TIMESHIFT_GRUB_REFRESH_HOOK=%s\n' "$FILE_TIMESHIFT_GRUB_REFRESH_HOOK"
  [ -n "${FILE_TIMESHIFT_DAILY_SERVICE:-}" ] && printf 'PATH_FILE_TIMESHIFT_DAILY_SERVICE=%s\n' "$FILE_TIMESHIFT_DAILY_SERVICE"
  [ -n "${FILE_TIMESHIFT_DAILY_TIMER:-}" ] && printf 'PATH_FILE_TIMESHIFT_DAILY_TIMER=%s\n' "$FILE_TIMESHIFT_DAILY_TIMER"
  [ -n "${FILE_TIMESHIFT_WEEKLY_SERVICE:-}" ] && printf 'PATH_FILE_TIMESHIFT_WEEKLY_SERVICE=%s\n' "$FILE_TIMESHIFT_WEEKLY_SERVICE"
  [ -n "${FILE_TIMESHIFT_WEEKLY_TIMER:-}" ] && printf 'PATH_FILE_TIMESHIFT_WEEKLY_TIMER=%s\n' "$FILE_TIMESHIFT_WEEKLY_TIMER"
  [ -n "${FILE_TIMESHIFT_MONTHLY_SERVICE:-}" ] && printf 'PATH_FILE_TIMESHIFT_MONTHLY_SERVICE=%s\n' "$FILE_TIMESHIFT_MONTHLY_SERVICE"
  [ -n "${FILE_TIMESHIFT_MONTHLY_TIMER:-}" ] && printf 'PATH_FILE_TIMESHIFT_MONTHLY_TIMER=%s\n' "$FILE_TIMESHIFT_MONTHLY_TIMER"
  [ -n "${FILE_GRUB_BTRFS_CONFIG:-}" ] && printf 'PATH_FILE_GRUB_BTRFS_CONFIG=%s\n' "$FILE_GRUB_BTRFS_CONFIG"
  [ -n "${FILE_GRUB_BTRFS_REFRESH_HELPER:-}" ] && printf 'PATH_FILE_GRUB_BTRFS_REFRESH_HELPER=%s\n' "$FILE_GRUB_BTRFS_REFRESH_HELPER"
  [ -n "${FILE_GRUB_BTRFS_REFRESH_SERVICE:-}" ] && printf 'PATH_FILE_GRUB_BTRFS_REFRESH_SERVICE=%s\n' "$FILE_GRUB_BTRFS_REFRESH_SERVICE"
  [ -n "${FILE_GRUB_BTRFS_REFRESH_PATH:-}" ] && printf 'PATH_FILE_GRUB_BTRFS_REFRESH_PATH=%s\n' "$FILE_GRUB_BTRFS_REFRESH_PATH"
  [ -n "${FILE_MODPROBE_NVME_BLACKLIST:-}" ] && printf 'PATH_FILE_MODPROBE_NVME_BLACKLIST=%s\n' "$FILE_MODPROBE_NVME_BLACKLIST"
  [ -n "${FILE_MODPROBE_MEI_BLACKLIST:-}" ] && printf 'PATH_FILE_MODPROBE_MEI_BLACKLIST=%s\n' "$FILE_MODPROBE_MEI_BLACKLIST"
  [ -n "${FILE_MODPROBE_VM_BLACKLIST:-}" ] && printf 'PATH_FILE_MODPROBE_VM_BLACKLIST=%s\n' "$FILE_MODPROBE_VM_BLACKLIST"
  [ -n "${FILE_MODPROBE_LEGACY_BLACKLIST:-}" ] && printf 'PATH_FILE_MODPROBE_LEGACY_BLACKLIST=%s\n' "$FILE_MODPROBE_LEGACY_BLACKLIST"
  [ -n "${FILE_MODPROBE_FILESYSTEM_BLACKLIST:-}" ] && printf 'PATH_FILE_MODPROBE_FILESYSTEM_BLACKLIST=%s\n' "$FILE_MODPROBE_FILESYSTEM_BLACKLIST"
  [ -n "${FILE_MODPROBE_SES_BLACKLIST:-}" ] && printf 'PATH_FILE_MODPROBE_SES_BLACKLIST=%s\n' "$FILE_MODPROBE_SES_BLACKLIST"
  [ -n "${FILE_MODPROBE_NETPROTO_BLACKLIST:-}" ] && printf 'PATH_FILE_MODPROBE_NETPROTO_BLACKLIST=%s\n' "$FILE_MODPROBE_NETPROTO_BLACKLIST"
  [ -n "${FILE_MODPROBE_SND_HDA_INTEL:-}" ] && printf 'PATH_FILE_MODPROBE_SND_HDA_INTEL=%s\n' "$FILE_MODPROBE_SND_HDA_INTEL"
  [ -n "${FILE_MODPROBE_IWLWIFI:-}" ] && printf 'PATH_FILE_MODPROBE_IWLWIFI=%s\n' "$FILE_MODPROBE_IWLWIFI"
  [ -n "${FILE_MODPROBE_E1000E:-}" ] && printf 'PATH_FILE_MODPROBE_E1000E=%s\n' "$FILE_MODPROBE_E1000E"
  [ -n "${FILE_MODPROBE_VFIO:-}" ] && printf 'PATH_FILE_MODPROBE_VFIO=%s\n' "$FILE_MODPROBE_VFIO"
  [ -n "${FILE_MODPROBE_I915:-}" ] && printf 'PATH_FILE_MODPROBE_I915=%s\n' "$FILE_MODPROBE_I915"
  [ -n "${FILE_MODPROBE_AMDGPU:-}" ] && printf 'PATH_FILE_MODPROBE_AMDGPU=%s\n' "$FILE_MODPROBE_AMDGPU"
  [ -n "${FILE_MODPROBE_NVIDIA:-}" ] && printf 'PATH_FILE_MODPROBE_NVIDIA=%s\n' "$FILE_MODPROBE_NVIDIA"
  [ -n "${FILE_MODPROBE_THUNDERBOLT:-}" ] && printf 'PATH_FILE_MODPROBE_THUNDERBOLT=%s\n' "$FILE_MODPROBE_THUNDERBOLT"
  [ -n "${FILE_MODPROBE_USBCORE:-}" ] && printf 'PATH_FILE_MODPROBE_USBCORE=%s\n' "$FILE_MODPROBE_USBCORE"
  [ -n "${FILE_MODPROBE_CFG80211:-}" ] && printf 'PATH_FILE_MODPROBE_CFG80211=%s\n' "$FILE_MODPROBE_CFG80211"
  [ -n "${FILE_MODPROBE_NVME_OPTS:-}" ] && printf 'PATH_FILE_MODPROBE_NVME_OPTS=%s\n' "$FILE_MODPROBE_NVME_OPTS"
  [ -n "${FILE_UDEV_REGDOM_RULE:-}" ] && printf 'PATH_FILE_UDEV_REGDOM_RULE=%s\n' "$FILE_UDEV_REGDOM_RULE"
  [ -n "${FILE_MODULES_LOAD_STORAGE_MEMORY:-}" ] && printf 'PATH_FILE_MODULES_LOAD_STORAGE_MEMORY=%s\n' "$FILE_MODULES_LOAD_STORAGE_MEMORY"
  [ -n "${FILE_MODULES_LOAD_TPM:-}" ] && printf 'PATH_FILE_MODULES_LOAD_TPM=%s\n' "$FILE_MODULES_LOAD_TPM"
  [ -n "${FILE_MODULES_LOAD_VFIO:-}" ] && printf 'PATH_FILE_MODULES_LOAD_VFIO=%s\n' "$FILE_MODULES_LOAD_VFIO"
  [ -n "${FILE_MODULES_LOAD_VIRT_HOST:-}" ] && printf 'PATH_FILE_MODULES_LOAD_VIRT_HOST=%s\n' "$FILE_MODULES_LOAD_VIRT_HOST"
  [ -n "${FILE_MODULES_LOAD_KVM_GUEST:-}" ] && printf 'PATH_FILE_MODULES_LOAD_KVM_GUEST=%s\n' "$FILE_MODULES_LOAD_KVM_GUEST"
  [ -n "${FILE_MODULES_LOAD_EMMC_STORAGE:-}" ] && printf 'PATH_FILE_MODULES_LOAD_EMMC_STORAGE=%s\n' "$FILE_MODULES_LOAD_EMMC_STORAGE"
  [ -n "${FILE_INITRAMFS_CUSTOM_CONF:-}" ] && printf 'PATH_FILE_INITRAMFS_CUSTOM_CONF=%s\n' "$FILE_INITRAMFS_CUSTOM_CONF"
  [ -n "${FILE_INITRAMFS_MODULES:-}" ] && printf 'PATH_FILE_INITRAMFS_MODULES=%s\n' "$FILE_INITRAMFS_MODULES"
  [ -n "${FILE_INITRAMFS_RESUME:-}" ] && printf 'PATH_FILE_INITRAMFS_RESUME=%s\n' "$FILE_INITRAMFS_RESUME"
  [ -n "${FILE_DBUS_BLOCKED_PACKAGES_APT_PREFERENCE:-}" ] && printf 'PATH_FILE_DBUS_BLOCKED_PACKAGES_APT_PREFERENCE=%s\n' "$FILE_DBUS_BLOCKED_PACKAGES_APT_PREFERENCE"
  [ -n "${FILE_DBUS_SYSTEM_LOCAL_CONF:-}" ] && printf 'PATH_FILE_DBUS_SYSTEM_LOCAL_CONF=%s\n' "$FILE_DBUS_SYSTEM_LOCAL_CONF"
  [ -n "${FILE_DBUS_SYSTEM_CONF:-}" ] && printf 'PATH_FILE_DBUS_SYSTEM_CONF=%s\n' "$FILE_DBUS_SYSTEM_CONF"
  [ -n "${FILE_DBUS_SYSTEM_SERVICE_ALIAS:-}" ] && printf 'PATH_FILE_DBUS_SYSTEM_SERVICE_ALIAS=%s\n' "$FILE_DBUS_SYSTEM_SERVICE_ALIAS"
  [ -n "${FILE_DBUS_USER_SERVICE_ALIAS:-}" ] && printf 'PATH_FILE_DBUS_USER_SERVICE_ALIAS=%s\n' "$FILE_DBUS_USER_SERVICE_ALIAS"
  [ -n "${FILE_DBUS_SYSTEM_BROKER_SERVICE_OVERRIDE:-}" ] && printf 'PATH_FILE_DBUS_SYSTEM_BROKER_SERVICE_OVERRIDE=%s\n' "$FILE_DBUS_SYSTEM_BROKER_SERVICE_OVERRIDE"
  [ -n "${FILE_DBUS_USER_BROKER_SERVICE_OVERRIDE:-}" ] && printf 'PATH_FILE_DBUS_USER_BROKER_SERVICE_OVERRIDE=%s\n' "$FILE_DBUS_USER_BROKER_SERVICE_OVERRIDE"
  [ -n "${FILE_DBUS_BROKER_BINARY:-}" ] && printf 'PATH_FILE_DBUS_BROKER_BINARY=%s\n' "$FILE_DBUS_BROKER_BINARY"
  [ -n "${FILE_DBUS_BROKER_LAUNCH_BINARY:-}" ] && printf 'PATH_FILE_DBUS_BROKER_LAUNCH_BINARY=%s\n' "$FILE_DBUS_BROKER_LAUNCH_BINARY"
  [ -n "${APPARMOR_PROFILE_LABWC_SESSION:-}" ] && printf 'APPARMOR_PROFILE_LABWC_SESSION=%s\n' "$APPARMOR_PROFILE_LABWC_SESSION"
  [ -n "${APPARMOR_PROFILE_WAYBAR:-}" ] && printf 'APPARMOR_PROFILE_WAYBAR=%s\n' "$APPARMOR_PROFILE_WAYBAR"
  [ -n "${APPARMOR_PROFILE_WAYBAR_RUN:-}" ] && printf 'APPARMOR_PROFILE_WAYBAR_RUN=%s\n' "$APPARMOR_PROFILE_WAYBAR_RUN"
  [ -n "${APPARMOR_PROFILE_WAYBAR_MENU:-}" ] && printf 'APPARMOR_PROFILE_WAYBAR_MENU=%s\n' "$APPARMOR_PROFILE_WAYBAR_MENU"
  [ -n "${APPARMOR_PROFILE_WAYBAR_EVENTS:-}" ] && printf 'APPARMOR_PROFILE_WAYBAR_EVENTS=%s\n' "$APPARMOR_PROFILE_WAYBAR_EVENTS"
  [ -n "${APPARMOR_PROFILE_WAYBAR_BATTERY:-}" ] && printf 'APPARMOR_PROFILE_WAYBAR_BATTERY=%s\n' "$APPARMOR_PROFILE_WAYBAR_BATTERY"
  [ -n "${APPARMOR_PROFILE_SESSION_CHECK:-}" ] && printf 'APPARMOR_PROFILE_SESSION_CHECK=%s\n' "$APPARMOR_PROFILE_SESSION_CHECK"
  # Optional fields may be absent in a role or before its policy is loaded.
  # An absent final field is not an emitter failure; unresolved tokens are
  # rejected separately by the publication boundary that consumes this map.
  return 0
}

installer_apply_scalar_placeholders() (
  set -eu
  umask 077
  installer_placeholder_src=$1
  installer_placeholder_final=$2
  [ -f "$installer_placeholder_src" ] && [ ! -L "$installer_placeholder_src" ] || return 1
  installer_placeholder_parent=${installer_placeholder_final%/*}
  [ "$installer_placeholder_parent" != "$installer_placeholder_final" ] || installer_placeholder_parent=.
  [ -d "$installer_placeholder_parent" ] && [ ! -L "$installer_placeholder_parent" ] || return 1
  installer_placeholder_work=$(mktemp -d "$installer_placeholder_parent/.installer-scalars.XXXXXX") || return 1
  trap 'rm -rf -- "$installer_placeholder_work"' 0
  trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
  installer_placeholder_dest=$installer_placeholder_work/payload
  if [ -e "$installer_placeholder_final" ] || [ -L "$installer_placeholder_final" ]; then
    [ -f "$installer_placeholder_final" ] && [ ! -L "$installer_placeholder_final" ] || return 1
    installer_placeholder_listing=$(LC_ALL=C ls -ln -- "$installer_placeholder_final") || return 1
    IFS=' ' read -r installer_placeholder_permissions installer_placeholder_links installer_placeholder_rest <<EOF
$installer_placeholder_listing
EOF
    [ "$installer_placeholder_links" = 1 ] || return 1
    # Preserve candidate metadata; publish only after a complete render.
    cp -p -- "$installer_placeholder_final" "$installer_placeholder_dest" || return 1
  fi
  installer_placeholder_script="$installer_placeholder_work/replacements.sed"
  installer_path_placeholder_map="${installer_placeholder_script}.paths"
  shift 2

  [ $(( $# % 2 )) -eq 0 ] || installer_fatal "placeholder replacement arguments must be name/value pairs"
  # The pre-late batch has already resolved canonical paths. Most published
  # assets now need only a copy; template adapters supply their own few scalar
  # fields without rebuilding the complete runtime map for each file.
  installer_placeholder_needs_paths=false
  if installer_contains_unresolved_path_placeholders "$installer_placeholder_src"; then
    installer_placeholder_needs_paths=true
  else
    installer_placeholder_probe=$?
    [ "$installer_placeholder_probe" -eq 1 ] || return "$installer_placeholder_probe"
  fi
  if [ "$#" -eq 0 ] && [ "$installer_placeholder_needs_paths" = false ]; then
    cat "$installer_placeholder_src" >"$installer_placeholder_dest" || return 1
    mv -fT -- "$installer_placeholder_dest" "$installer_placeholder_final"
    return
  fi
  : >"$installer_placeholder_script" || {
    rm -f "$installer_placeholder_script"
    return 1
  }
  installer_placeholder_seen=
  while [ "$#" -gt 1 ]; do
    installer_placeholder_name=$1
    installer_placeholder_value=$2
    shift 2
    case "$installer_placeholder_name" in
      ''|*[!A-Z0-9_]*) installer_fatal 'invalid scalar placeholder name' ;;
    esac
    case "$installer_placeholder_name" in
      [A-Z]*) ;; *) installer_fatal 'scalar placeholder name must start with a letter' ;;
    esac
    case "$installer_placeholder_value" in
      *"
"*|*"$(printf '\r')"*) installer_fatal 'scalar placeholder value must be a single line' ;;
    esac
    case " $installer_placeholder_seen " in
      *" $installer_placeholder_name "*)
        installer_fatal "duplicate scalar placeholder key: $installer_placeholder_name" ;;
      *) installer_placeholder_seen="${installer_placeholder_seen:+$installer_placeholder_seen }$installer_placeholder_name" ;;
    esac
    case "$installer_placeholder_value" in
      # Keep prefix probes incomplete so the early batch cannot render the
      # renderer's own token detector into a suite-specific string.
      *__INSTALLER_PATH_*|*__INSTALLER_APPARMOR_PROFILE_*|*__INSTALLER_GITBUILD_DISTRIBUTION_*) installer_placeholder_needs_paths=true ;;
    esac
    installer_escaped_placeholder_value=$(installer_escape_sed_replacement "$installer_placeholder_value")
    printf 's|__INSTALLER_%s__|%s|g\n' \
      "$installer_placeholder_name" \
      "$installer_escaped_placeholder_value" >>"$installer_placeholder_script" || {
        rm -f "$installer_placeholder_script"
        return 1
      }
  done
  if [ "$installer_placeholder_needs_paths" = false ]; then
    : >"$installer_path_placeholder_map"
  elif [ -n "${BOOTSTRAP_PREPARED_SOURCE_ROOT:-}" ]; then
    cp "${BOOTSTRAP_PREPARED_SOURCE_ROOT%/source}/inputs/paths.map" "$installer_path_placeholder_map" || return "$?"
  elif ! installer_runtime_path_placeholder_map >"$installer_path_placeholder_map"; then
    rm -f "$installer_placeholder_script" "$installer_path_placeholder_map"
    return 1
  fi
  installer_validate_placeholder_map "$installer_path_placeholder_map" || {
    rm -f "$installer_placeholder_script" "$installer_path_placeholder_map"
    return 1
  }
  # The canonical path map is single-line NAME=value data. Escape all of it
  # in one process, rather than launching sed for every path on every asset.
  # Keep the same sed renderer and scalar/block replacement semantics.
  if ! LC_ALL=C awk -v scalar_names="$installer_placeholder_seen" '
    BEGIN { count = split(scalar_names, names, " "); for (i = 1; i <= count; i++) seen[names[i]] = 1 }
    function replacement(value, output, position, character) {
      output = ""
      for (position = 1; position <= length(value); position++) {
        character = substr(value, position, 1)
        if (character == "\\" || character == "&" || character == "|") output = output "\\"
        output = output character
      }
      return output
    }
    NF {
      separator = index($0, "=")
      name = substr($0, 1, separator - 1)
      if (separator < 2 || name !~ /^[A-Z][A-Z0-9_]*$/) exit 1
      if (name in seen) exit 1
      seen[name] = 1
      print "s|__INSTALLER_" name "__|" replacement(substr($0, separator + 1)) "|g"
    }
  ' "$installer_path_placeholder_map" >>"$installer_placeholder_script"; then
    rm -f "$installer_placeholder_script" "$installer_path_placeholder_map"
    return 1
  fi
  rm -f "$installer_path_placeholder_map"
  sed -f "$installer_placeholder_script" "$installer_placeholder_src" >"$installer_placeholder_dest" || {
    rm -f "$installer_placeholder_script" "$installer_placeholder_dest" "$installer_path_placeholder_map"
    return 1
  }
  rm -f "$installer_placeholder_script"
  [ ! -L "$installer_placeholder_parent" ] && [ ! -L "$installer_placeholder_final" ] || return 1
  mv -fT -- "$installer_placeholder_dest" "$installer_placeholder_final"
)

installer_copy_path_with_mode() (
  umask 077
  copy_src_path=$1
  copy_dest_path=$2
  copy_mode=$3
  copy_label=${4:-file}
  case "$copy_mode" in
    [0-7][0-7][0-7]|[0-7][0-7][0-7][0-7]) ;;
    *) installer_error "invalid copy mode for ${copy_label}"; exit 1 ;;
  esac

  if [ "$copy_src_path" = "$copy_dest_path" ]; then
    [ -f "$copy_dest_path" ] && [ ! -L "$copy_dest_path" ] || exit 1
    chmod "$copy_mode" "$copy_dest_path"
    exit $?
  fi

  copy_parent_dir=$(dirname "$copy_dest_path") || exit 1
  [ -d "$copy_parent_dir" ] || install -d -m 0700 "$copy_parent_dir" || exit 1
  [ ! -d "$copy_dest_path" ] || {
    installer_error "copy destination is a directory: ${copy_dest_path}"
    exit 1
  }
  copy_work=$(mktemp -d "$copy_parent_dir/.installer-copy.XXXXXX") || exit 1
  trap 'rm -rf -- "$copy_work"' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  copy_tmp_path="$copy_work/payload"
  copy_err_path="$copy_work/copy.err"
  if cp -- "$copy_src_path" "$copy_tmp_path" >"$copy_err_path" 2>&1; then
    copy_status=0
  else
    copy_status=$?
  fi
  if [ "$copy_status" -ne 0 ]; then
    installer_error "failed to copy ${copy_label} from ${copy_src_path} to ${copy_dest_path} (status ${copy_status})"
    [ ! -s "$copy_err_path" ] || sed -n '1,40s/^/[cp] /p' "$copy_err_path" >&2
    exit 1
  fi
  [ -s "$copy_tmp_path" ] || {
    installer_fatal "copied ${copy_label} is empty: ${copy_src_path}"
    exit 1
  }
  chmod "$copy_mode" "$copy_tmp_path" || exit 1
  mv -fT -- "$copy_tmp_path" "$copy_dest_path" || exit 1
)

installer_log_path_is_numbered() {
  installer_check_log_path=$1
  installer_check_log_name=${installer_check_log_path##*/}

  case "$installer_check_log_name" in
    [0-9]*-*) return 0 ;;
  esac
  return 1
}

installer_log_sequence_file() {
  installer_sequence_log_dir=$1
  printf '%s/.log-sequence\n' "$installer_sequence_log_dir"
}

installer_next_log_sequence() {
  installer_sequence_log_dir=$1
  installer_sequence_path=$(installer_log_sequence_file "$installer_sequence_log_dir")
  installer_sequence_tmp="${installer_sequence_path}.tmp.$$"
  installer_current_sequence=0

  [ -d "$installer_sequence_log_dir" ] || install -d -m 0700 "$installer_sequence_log_dir"
  if [ -r "$installer_sequence_path" ]; then
    installer_current_sequence=$(cat "$installer_sequence_path" 2>/dev/null || printf '0\n')
  fi
  case "$installer_current_sequence" in
    ''|*[!0-9]*) installer_current_sequence=0 ;;
  esac

  installer_next_sequence=$((installer_current_sequence + 1))
  printf '%s\n' "$installer_next_sequence" >"$installer_sequence_tmp"
  mv "$installer_sequence_tmp" "$installer_sequence_path"
  chmod 0600 "$installer_sequence_path" 2>/dev/null || true
  printf '%s\n' "$installer_next_sequence"
}

installer_log_dir_for_path() {
  installer_dir_path=$1
  printf '%s\n' "$(dirname "$installer_dir_path")"
}

installer_basename_for_path() {
  installer_base_path=$1
  printf '%s\n' "${installer_base_path##*/}"
}

installer_runtime_log_path_requested() {
  requested_log_path=$1
  runtime_log_dir=$(installer_runtime_log_dir)

  case "$requested_log_path" in
    "${runtime_log_dir}/"*) return 0 ;;
  esac
  return 1
}

installer_resolve_runtime_log_path() {
  requested_log_path=$1
  printf '%s\n' "$requested_log_path"
}

installer_runtime_temp_log_path() {
  temp_log_name=$1
  temp_log_dir=$(installer_runtime_temp_log_dir)
  temp_log_name=${temp_log_name%.log}
  install -d -m 0700 "$temp_log_dir" 2>/dev/null || true
  printf '%s/%s-%s.err\n' "$temp_log_dir" "$$" "$temp_log_name"
}

installer_resolve_target_log_path() {
  requested_target_log_path=$1
  INSTALLER_RESOLVED_TARGET_LOG_PATH=

  [ -n "$requested_target_log_path" ] || return 1
  if installer_log_path_is_numbered "$requested_target_log_path"; then
    INSTALLER_RESOLVED_TARGET_LOG_PATH=$requested_target_log_path
    return 0
  fi

  if [ -n "${INSTALLER_LOG_TARGET_FILE_RESOLVED:-}" ] && \
     [ "${INSTALLER_LOG_TARGET_FILE:-}" = "$requested_target_log_path" ]
  then
    INSTALLER_RESOLVED_TARGET_LOG_PATH=$INSTALLER_LOG_TARGET_FILE_RESOLVED
    return 0
  fi

  target_log_dir=$(installer_log_dir_for_path "$requested_target_log_path")
  target_log_name=$(installer_basename_for_path "$requested_target_log_path")
  target_log_seq=$(installer_next_log_sequence "$target_log_dir")
  resolved_target_log_path="${target_log_dir}/${target_log_seq}-${target_log_name}"

  if [ "${INSTALLER_LOG_TARGET_FILE:-}" = "$requested_target_log_path" ]; then
    INSTALLER_LOG_TARGET_FILE_RESOLVED=$resolved_target_log_path
  fi

  INSTALLER_RESOLVED_TARGET_LOG_PATH=$resolved_target_log_path
  return 0
}

installer_copy_log_to_target() {
  log_path=$1
  target_log_file=$2

  installer_logging_enabled || return 0
  [ -s "$log_path" ] || return 0
  [ -n "$target_log_file" ] || return 0
  installer_target_is_mounted || return 0

  if installer_log_path_is_numbered "$log_path" && \
     ! installer_log_path_is_numbered "$target_log_file"
  then
    resolved_target_log_file="$(installer_log_dir_for_path "$target_log_file")/$(installer_basename_for_path "$log_path")"
  else
    installer_resolve_target_log_path "$target_log_file" || return 0
    resolved_target_log_file=$INSTALLER_RESOLVED_TARGET_LOG_PATH
  fi
  install -d -m 0700 "$(dirname "$resolved_target_log_file")"
  resolved_target_log_tmp="${resolved_target_log_file}.tmp.$$"
  if installer_redact_log_stream <"$log_path" >"$resolved_target_log_tmp" 2>/dev/null; then
    chmod 0600 "$resolved_target_log_tmp" 2>/dev/null || true
    mv -f "$resolved_target_log_tmp" "$resolved_target_log_file"
  else
    rm -f "$resolved_target_log_tmp" 2>/dev/null || true
    installer_warn "failed to sanitize installer log ${log_path}"
  fi
}

installer_persist_log_file() {
  log_path=$1
  target_log_file=$2

  # Runtime logs are archived once at the end of the installer flow.  Keep this
  # compatibility entrypoint as a no-op so phase hooks do not create partial
  # target-side log copies before finish-install runs.
  [ -n "$log_path" ] || return 0
  [ -n "$target_log_file" ] || return 0
  return 0
}

installer_init_log_file() {
  log_path=$1
  target_log_file=${2:-}
  log_context=${3:-${0##*/}}
  log_tag=${4:-}
  log_stage=${5:-}
  log_path=$(installer_resolve_runtime_log_path "$log_path")

  if command -v installer_operation_context_repo >/dev/null 2>&1 &&
     [ -z "${INSTALLER_FAILURE_SOURCE:-}" ]; then
    installer_operation_context_repo FILE_COMMON_MOD_FILES_LOGGING 936 "$log_context"
  fi

  installer_export_logging_policy
  if ! installer_logging_enabled; then
    INSTALLER_LOG_PATH=
    INSTALLER_LOG_TARGET_FILE=
    INSTALLER_LOG_TARGET_FILE_RESOLVED=
    INSTALLER_LOG_CONTEXT=$log_context
    INSTALLER_LOG_FINALIZED=0
    INSTALLER_LOG_START_EPOCH=$(installer_log_epoch)
    [ -n "$log_tag" ] && INSTALLER_LOG_TAG=$log_tag
    if [ -n "$log_stage" ]; then
      INSTALLER_LOG_STAGE=$log_stage
    else
      INSTALLER_LOG_STAGE=$(installer_stage_from_tag "$(installer_log_tag)")
    fi
    return 0
  fi

  log_dir=$(dirname "$log_path")

  [ -d "$log_dir" ] || install -d -m 0700 "$log_dir" 2>/dev/null || true
  : >>"$log_path" || installer_fatal "unable to initialize log file: ${log_path}"
  chmod 0600 "$log_path" 2>/dev/null || true

  # shellcheck disable=SC2034 # Exposed for phase hooks sourced after logging setup.
  INSTALLER_LOG_PATH=$log_path
  INSTALLER_LOG_TARGET_FILE=$target_log_file
  INSTALLER_LOG_TARGET_FILE_RESOLVED=
  INSTALLER_LOG_CONTEXT=$log_context
  INSTALLER_LOG_FINALIZED=0
  INSTALLER_LOG_START_EPOCH=$(installer_log_epoch)
  if [ -n "$log_tag" ]; then
    INSTALLER_LOG_TAG=$log_tag
  fi
  if [ -n "$log_stage" ]; then
    INSTALLER_LOG_STAGE=$log_stage
  else
    INSTALLER_LOG_STAGE=$(installer_stage_from_tag "$(installer_log_tag)")
  fi

  exec >>"$log_path" 2>&1
  installer_info "starting ${INSTALLER_LOG_CONTEXT}"
  return 0
}

installer_init_stderr_log_file() {
  log_path=$1
  target_log_file=${2:-}
  log_context=${3:-${0##*/}}
  log_tag=${4:-}
  log_stage=${5:-}
  log_path=$(installer_resolve_runtime_log_path "$log_path")

  if command -v installer_operation_context_repo >/dev/null 2>&1 &&
     [ -z "${INSTALLER_FAILURE_SOURCE:-}" ]; then
    installer_operation_context_repo FILE_COMMON_MOD_FILES_LOGGING 993 "$log_context"
  fi

  installer_export_logging_policy
  if ! installer_logging_enabled; then
    INSTALLER_LOG_PATH=
    INSTALLER_LOG_TARGET_FILE=
    INSTALLER_LOG_TARGET_FILE_RESOLVED=
    INSTALLER_LOG_CONTEXT=$log_context
    INSTALLER_LOG_FINALIZED=0
    INSTALLER_LOG_START_EPOCH=$(installer_log_epoch)
    [ -n "$log_tag" ] && INSTALLER_LOG_TAG=$log_tag
    if [ -n "$log_stage" ]; then
      INSTALLER_LOG_STAGE=$log_stage
    else
      INSTALLER_LOG_STAGE=$(installer_stage_from_tag "$(installer_log_tag)")
    fi
    return 0
  fi

  log_dir=$(dirname "$log_path")

  [ -d "$log_dir" ] || install -d -m 0700 "$log_dir" 2>/dev/null || true
  : >>"$log_path" || installer_fatal "unable to initialize log file: ${log_path}"
  chmod 0600 "$log_path" 2>/dev/null || true

  # shellcheck disable=SC2034 # Exposed for phase hooks sourced after logging setup.
  INSTALLER_LOG_PATH=$log_path
  INSTALLER_LOG_TARGET_FILE=$target_log_file
  INSTALLER_LOG_TARGET_FILE_RESOLVED=
  INSTALLER_LOG_CONTEXT=$log_context
  INSTALLER_LOG_FINALIZED=0
  INSTALLER_LOG_START_EPOCH=$(installer_log_epoch)
  if [ -n "$log_tag" ]; then
    INSTALLER_LOG_TAG=$log_tag
  fi
  if [ -n "$log_stage" ]; then
    INSTALLER_LOG_STAGE=$log_stage
  else
    INSTALLER_LOG_STAGE=$(installer_stage_from_tag "$(installer_log_tag)")
  fi

  exec 2>>"$log_path"
  installer_info "starting ${INSTALLER_LOG_CONTEXT}"
  return 0
}

installer_finalize_log() {
  exit_code=${1:-0}

  if [ "${INSTALLER_LOG_FINALIZED:-0}" -eq 1 ]; then
    return 0
  fi
  INSTALLER_LOG_FINALIZED=1

  log_context=${INSTALLER_LOG_CONTEXT:-${0##*/}}
  log_duration=
  if [ -n "${INSTALLER_LOG_START_EPOCH:-}" ]; then
    log_end_epoch=$(installer_log_epoch)
    case "$log_end_epoch:${INSTALLER_LOG_START_EPOCH:-}" in
      [0-9]*:[0-9]*)
        log_duration=" duration_seconds=$((log_end_epoch - INSTALLER_LOG_START_EPOCH))"
        ;;
    esac
  fi
  if [ "$exit_code" -eq 0 ]; then
    installer_info "completed ${log_context}${log_duration}"
  else
    log_failure_context=unknown
    if command -v installer_failure_context >/dev/null 2>&1; then
      log_failure_context=$(installer_failure_context 2>/dev/null || printf '%s' unknown)
    fi
    installer_error "${log_context} exited with status ${exit_code}${log_duration}; ${log_failure_context}; inspect the preceding diagnostic for the failed operation"
    if [ "${INSTALLER_LIFECYCLE_ACTIVE:-0}" = 1 ]; then
      installer_record_failure "$exit_code" "$log_context" "operation failed: status=${exit_code}; ${log_failure_context}; see the preceding diagnostic for command output" || :
    fi
  fi

  if installer_bool_is_true "${INSTALLER_ARCHIVE_LOGS_ON_FINALIZE:-false}"; then
    installer_archive_logs_to_target || true
  fi
}

installer_fatal_status() {
  fatal_status=${1:-1}
  shift || :
  case "$fatal_status" in
    ''|*[!0-9]*|0) fatal_status=1 ;;
  esac
  fatal_context=unknown
  if command -v installer_failure_context >/dev/null 2>&1; then
    fatal_context=$(installer_failure_context 2>/dev/null || printf '%s' unknown)
  fi
  installer_error "$* (status=${fatal_status}; ${fatal_context})"
  if [ "${INSTALLER_LIFECYCLE_ACTIVE:-0}" = 1 ]; then
    installer_record_failure "$fatal_status" "${INSTALLER_LOG_CONTEXT:-unknown}" "$* (status=${fatal_status}; ${fatal_context})" || :
  fi
  exit "$fatal_status"
}

installer_fatal() {
  installer_fatal_status 1 "$@"
}

installer_shell_quote() {
  printf "'%s'" "$(printf '%s' "${1-}" | sed "s/'/'\\\\''/g")"
}

# Quote the VALUE inside a double-quoted Environment="KEY=value" unit entry.
# Reject controls; escape unit syntax and literal percent specifiers. Never eval.
installer_systemd_environment_value() (
  [ "$#" -eq 1 ] || exit 64
  LC_ALL=C; export LC_ALL
  # case sees embedded/trailing newlines, unlike a line-oriented grep. These
  # bootstrap values are bounded ASCII identifiers, paths and command flags.
  case "$1" in *[![:print:]]*)
    printf '%s\n' 'fatal: non-printable systemd environment value' >&2; exit 1 ;;
  esac
  [ "${#1}" -le 4096 ] || exit 1
  printf '%s' "$1" | sed 's/[\\"]/\\&/g; s/%/%%/g'
)

# Validate and escape before substitution, propagating failures instead of
# hiding them inside nested command-substitution arguments to a renderer.
installer_apply_systemd_environment_placeholders() (
  set -eu
  environment_input=$1
  environment_output=$2
  shift 2
  remaining=$#
  [ $((remaining % 2)) -eq 0 ] || exit 64
  while [ "$remaining" -gt 0 ]; do
    environment_name=$1
    environment_value=$(installer_systemd_environment_value "$2") || exit 1
    shift 2
    set -- "$@" "$environment_name" "$environment_value"
    remaining=$((remaining - 2))
  done
  installer_apply_scalar_placeholders "$environment_input" "$environment_output" "$@"
)

# A unit identity is data; only registered unit paths can reach staging.
installer_systemd_dropin_dir() {
  [ "$#" -eq 2 ] || return 64
  case "$1/$2" in
    system/apparmor-modes.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_APPARMOR_MODES_DROPIN" ;;
    system/NetworkManager-dispatcher.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_NETWORKMANAGER_DISPATCHER_DROPIN" ;;
    system/NetworkManager.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_NETWORKMANAGER_DROPIN" ;;
    system/apparmor.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_APPARMOR_DROPIN" ;;
    system/apt-daily-upgrade.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_APT_DAILY_UPGRADE_DROPIN" ;;
    system/apt-daily.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_APT_DAILY_DROPIN" ;;
    system/apt-repo-local-.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_APT_REPO_LOCAL_FAMILY_DROPIN" ;;
    system/apt-repo-local-refresh.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_APT_REPO_LOCAL_REFRESH_DROPIN" ;;
    system/audit-rules.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_AUDIT_RULES_DROPIN" ;;
    system/auditd.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_AUDITD_DROPIN" ;;
    system/bluetooth.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_BLUETOOTH_DROPIN" ;;
    system/clamav-daemon.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_CLAMAV_DAEMON_DROPIN" ;;
    system/clamav-freshclam.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_CLAMAV_FRESHCLAM_DROPIN" ;;
    system/clamav-signature-update.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_CLAMAV_SIGNATURE_UPDATE_DROPIN" ;;
    system/crowdsec-firewall-bouncer.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_CROWDSEC_FIREWALL_BOUNCER_DROPIN" ;;
    system/crowdsec.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_CROWDSEC_DROPIN" ;;
    system/data-run.mount) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_DATA_RUN_MOUNT_DROPIN" ;;
    system/dbus-broker.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_DBUS_BROKER_DROPIN" ;;
    system/dev-shm.mount) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_DEV_SHM_MOUNT_DROPIN" ;;
    system/fail2ban.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_FAIL2BAN_DROPIN" ;;
    system/fstrim.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_FSTRIM_DROPIN" ;;
    system/fstrim.timer) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_FSTRIM_TIMER_DROPIN" ;;
    system/fwupd.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_FWUPD_DROPIN" ;;
    system/greetd.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_GREETD_DROPIN" ;;
    system/home-mcramer-Sharing.mount) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_HOME_MCRAMER_SHARING_MOUNT_DROPIN" ;;
    system/ifup@.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_IFUP_TEMPLATE_DROPIN" ;;
    system/incus-user.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_INCUS_USER_DROPIN" ;;
    system/logrotate.timer) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_LOGROTATE_TIMER_DROPIN" ;;
    system/lynis.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_LYNIS_DROPIN" ;;
    system/mullvad-daemon.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_MULLVAD_DAEMON_DROPIN" ;;
    system/networking.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_NETWORKING_DROPIN" ;;
    system/nfs-idmapd.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_NFS_IDMAPD_DROPIN" ;;
    system/nfs-mountd.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_NFS_MOUNTD_DROPIN" ;;
    system/nfs-server.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_NFS_SERVER_DROPIN" ;;
    system/nftables.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_NFTABLES_DROPIN" ;;
    system/technitium.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_TECHNITIUM_DROPIN" ;;
    system/nvidia-hibernate.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_NVIDIA_HIBERNATE_DROPIN" ;;
    system/nvidia-powerd.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_NVIDIA_POWERD_DROPIN" ;;
    system/nvidia-resume.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_NVIDIA_RESUME_DROPIN" ;;
    system/nvidia-suspend-then-hibernate.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_NVIDIA_SUSPEND_THEN_HIBERNATE_DROPIN" ;;
    system/nvidia-suspend.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_NVIDIA_SUSPEND_DROPIN" ;;
    system/power-profiles-daemon.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_POWER_PROFILES_DAEMON_DROPIN" ;;
    system/rsyslog.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_RSYSLOG_DROPIN" ;;
    system/scx.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_SCX_DROPIN" ;;
    system/scx_loader.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_SCX_LOADER_DROPIN" ;;
    system/sleep.target) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_SLEEP_TARGET_DROPIN" ;;
    system/ssh.socket) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_SSH_SOCKET_DROPIN" ;;
    system/stubby.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_STUBBY_DROPIN" ;;
    system/syncthing.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_SYNCTHING_DROPIN" ;;
    system/system-background.slice) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_SYSTEM_BACKGROUND_SLICE_DROPIN" ;;
    system/system-maintenance.slice) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_SYSTEM_MAINTENANCE_SLICE_DROPIN" ;;
    system/systemd-coredump.socket) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_SYSTEMD_COREDUMP_SOCKET_DROPIN" ;;
    system/systemd-creds.socket) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_SYSTEMD_CREDS_SOCKET_DROPIN" ;;
    system/systemd-hibernate.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_SYSTEMD_HIBERNATE_DROPIN" ;;
    system/systemd-hybrid-sleep.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_SYSTEMD_HYBRID_SLEEP_DROPIN" ;;
    system/systemd-resolved.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_SYSTEMD_RESOLVED_DROPIN" ;;
    system/systemd-suspend-then-hibernate.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_SYSTEMD_SUSPEND_THEN_HIBERNATE_DROPIN" ;;
    system/systemd-suspend.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_SYSTEMD_SUSPEND_DROPIN" ;;
    system/tailscaled.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_TAILSCALED_DROPIN" ;;
    system/test.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_TEST_DROPIN" ;;
    system/timeshift-.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_TIMESHIFT_FAMILY_DROPIN" ;;
    system/tmp.mount) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_TMP_MOUNT_DROPIN" ;;
    system/unattended-upgrades.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_UNATTENDED_UPGRADES_DROPIN" ;;
    system/user-1000.slice) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_USER_1000_SLICE_DROPIN" ;;
    system/user@.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_USER_MANAGER_DROPIN" ;;
    system/var-cache.mount) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_VAR_CACHE_MOUNT_DROPIN" ;;
    system/var-lib-apt-lists.mount) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_VAR_LIB_APT_LISTS_MOUNT_DROPIN" ;;
    system/var-lib-systemd-coredump.mount) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_VAR_LIB_SYSTEMD_COREDUMP_MOUNT_DROPIN" ;;
    system/var-log.mount) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_VAR_LOG_MOUNT_DROPIN" ;;
    system/var-spool-rsyslog.mount) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_VAR_SPOOL_RSYSLOG_MOUNT_DROPIN" ;;
    system/wpa_supplicant.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_WPA_SUPPLICANT_DROPIN" ;;
    system/x-clamav-signature-update.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_X_CLAMAV_SIGNATURE_UPDATE_DROPIN" ;;
    system/x-syncthing.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_X_SYNCTHING_DROPIN" ;;
    system/xfs_healer_start.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_XFS_HEALER_START_DROPIN" ;;
    system/zram-writeback.service) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_ZRAM_DROPIN" ;;
    user/app-.scope) printf '%s\n' "$DIR_SYSTEMD_USER_APP_FAMILY_SCOPE_DROPIN" ;;
    user/app.slice) printf '%s\n' "$DIR_SYSTEMD_USER_APP_SLICE_DROPIN" ;;
    system/user-.slice) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_USER_FAMILY_SLICE_DROPIN" ;;
    system/user.slice) printf '%s\n' "$DIR_SYSTEMD_SYSTEM_USER_SLICE_DROPIN" ;;
    user/background.slice) printf '%s\n' "$DIR_SYSTEMD_USER_BACKGROUND_SLICE_DROPIN" ;;
    user/crystal-dock.service) printf '%s\n' "$DIR_SYSTEMD_USER_CRYSTAL_DOCK_DROPIN" ;;
    user/dbus-broker.service) printf '%s\n' "$DIR_SYSTEMD_USER_DBUS_BROKER_DROPIN" ;;
    user/filter-chain.service) printf '%s\n' "$DIR_SYSTEMD_USER_FILTER_CHAIN_DROPIN" ;;
    user/foot-server.service) printf '%s\n' "$DIR_SYSTEMD_USER_FOOT_SERVER_DROPIN" ;;
    user/foot-server.socket) printf '%s\n' "$DIR_SYSTEMD_USER_FOOT_SERVER_SOCKET_DROPIN" ;;
    user/gvfs-daemon.service) printf '%s\n' "$DIR_SYSTEMD_USER_GVFS_DAEMON_DROPIN" ;;
    user/gvfs-udisks2-volume-monitor.service) printf '%s\n' "$DIR_SYSTEMD_USER_GVFS_UDISKS2_VOLUME_MONITOR_DROPIN" ;;
    user/hyprpolkitagent.service) printf '%s\n' "$DIR_SYSTEMD_USER_HYPRPOLKITAGENT_DROPIN" ;;
    user/kanshi.service) printf '%s\n' "$DIR_SYSTEMD_USER_KANSHI_DROPIN" ;;
    user/labwc-bitwarden-.service) printf '%s\n' "$DIR_SYSTEMD_USER_LABWC_BITWARDEN_FAMILY_DROPIN" ;;
    user/labwc-compat-.service) printf '%s\n' "$DIR_SYSTEMD_USER_LABWC_COMPAT_FAMILY_DROPIN" ;;
    user/labwc-devops-.service) printf '%s\n' "$DIR_SYSTEMD_USER_LABWC_DEVOPS_FAMILY_DROPIN" ;;
    user/labwc-electron-.service) printf '%s\n' "$DIR_SYSTEMD_USER_LABWC_ELECTRON_FAMILY_DROPIN" ;;
    user/labwc-native-.service) printf '%s\n' "$DIR_SYSTEMD_USER_LABWC_NATIVE_FAMILY_DROPIN" ;;
    user/labwc-qbittorrent-.service) printf '%s\n' "$DIR_SYSTEMD_USER_LABWC_QBITTORRENT_FAMILY_DROPIN" ;;
    user/labwc-session-state@prepare.service) printf '%s\n' "$DIR_SYSTEMD_USER_LABWC_SESSION_STATE_PREPARE_DROPIN" ;;
    user/labwc-wayland-.service) printf '%s\n' "$DIR_SYSTEMD_USER_LABWC_WAYLAND_FAMILY_DROPIN" ;;
    user/labwc-wayland-foot-.service) printf '%s\n' "$DIR_SYSTEMD_USER_LABWC_WAYLAND_FOOT_FAMILY_DROPIN" ;;
    user/llama-server.service) printf '%s\n' "$DIR_SYSTEMD_USER_LLAMA_SERVER_DROPIN" ;;
    user/mako.service) printf '%s\n' "$DIR_SYSTEMD_USER_MAKO_DROPIN" ;;
    user/pipewire-pulse.service) printf '%s\n' "$DIR_SYSTEMD_USER_PIPEWIRE_PULSE_DROPIN" ;;
    user/pipewire-pulse.socket) printf '%s\n' "$DIR_SYSTEMD_USER_PIPEWIRE_PULSE_SOCKET_DROPIN" ;;
    user/pipewire.service) printf '%s\n' "$DIR_SYSTEMD_USER_PIPEWIRE_DROPIN" ;;
    user/pipewire.socket) printf '%s\n' "$DIR_SYSTEMD_USER_PIPEWIRE_SOCKET_DROPIN" ;;
    user/session.slice) printf '%s\n' "$DIR_SYSTEMD_USER_SESSION_SLICE_DROPIN" ;;
    user/ssh-agent.service) printf '%s\n' "$DIR_SYSTEMD_USER_SSH_AGENT_DROPIN" ;;
    user/ssh-agent.socket) printf '%s\n' "$DIR_SYSTEMD_USER_SSH_AGENT_SOCKET_DROPIN" ;;
    user/thunar.service) printf '%s\n' "$DIR_SYSTEMD_USER_THUNAR_DROPIN" ;;
    user/waybar.service) printf '%s\n' "$DIR_SYSTEMD_USER_WAYBAR_DROPIN" ;;
    user/wayscriber.service) printf '%s\n' "$DIR_SYSTEMD_USER_WAYSCRIBER_DROPIN" ;;
    user/wireplumber.service) printf '%s\n' "$DIR_SYSTEMD_USER_WIREPLUMBER_DROPIN" ;;
    user/xdg-desktop-portal-.service) printf '%s\n' "$DIR_SYSTEMD_USER_XDG_DESKTOP_PORTAL_FAMILY_DROPIN" ;;
    user/xdg-desktop-portal-gtk.service) printf '%s\n' "$DIR_SYSTEMD_USER_XDG_DESKTOP_PORTAL_GTK_DROPIN" ;;
    user/xdg-desktop-portal-lxqt.service) printf '%s\n' "$DIR_SYSTEMD_USER_XDG_DESKTOP_PORTAL_LXQT_DROPIN" ;;
    user/xdg-desktop-portal-wlr.service) printf '%s\n' "$DIR_SYSTEMD_USER_XDG_DESKTOP_PORTAL_WLR_DROPIN" ;;
    user/xdg-desktop-portal-xapp.service) printf '%s\n' "$DIR_SYSTEMD_USER_XDG_DESKTOP_PORTAL_XAPP_DROPIN" ;;
    user/xdg-desktop-portal.service) printf '%s\n' "$DIR_SYSTEMD_USER_XDG_DESKTOP_PORTAL_DROPIN" ;;
    *) installer_fatal "unregistered systemd drop-in unit"; return 1 ;;
  esac
}

#!/bin/sh

# Caches belong to this bootstrap shell, never to an inherited environment.
unset BOOTSTRAP_PREPARED_BOUND_READY BOOTSTRAP_SOURCED_MODULES

bootstrap_log() {
  printf '[bootstrap] %s\n' "$*" >&2
}

bootstrap_fatal() {
  bootstrap_message=$(printf '%s' "$*" | tr '\r\n\t' '   ')
  bootstrap_log "fatal: $bootstrap_message"
  if [ -c /dev/tty4 ] && [ -w /dev/tty4 ]; then
    printf '[bootstrap] fatal: %s\n' "$bootstrap_message" >/dev/tty4 || :
  fi
  if [ -c /dev/console ] && [ -w /dev/console ]; then
    printf '[bootstrap] fatal: %s\n' "$bootstrap_message" >/dev/console || :
  fi
  if command -v logger >/dev/null 2>&1; then
    logger -t preseed-bootstrap "fatal: $bootstrap_message" 2>/dev/null || :
  fi
  exit 1
}

bootstrap_runtime_dir() {
  printf '%s\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"
}

bootstrap_runtime_log_dir() {
  bootstrap_runtime_log_path=${FILE_INSTALLER_LOG:-/tmp/installer.log}
  printf '%s\n' "${bootstrap_runtime_log_path%/*}"
}

bootstrap_runtime_log_file() {
  printf '%s\n' "${FILE_INSTALLER_LOG:-/tmp/installer.log}"
}

bootstrap_runtime_cache_dir() {
  printf '%s/cache\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"
}

bootstrap_runtime_seed_cache_dir() {
  printf '%s/cache/seed\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"
}

bootstrap_runtime_bootstrap_dir() {
  printf '%s/bootstrap\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"
}

bootstrap_seed_url_path() {
  printf '%s/bootstrap/seed.url\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"
}

bootstrap_seed_file_path() {
  printf '%s/bootstrap/seed.file\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"
}

bootstrap_lib_path() {
  printf '%s/bootstrap/bootstrap.sh\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"
}

bootstrap_repo_env_relpath() {
  printf '%s\n' repo.env
}

bootstrap_repo_env_path() {
  printf '%s/bootstrap/repo.env\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"
}

bootstrap_di_env_path() {
  printf '%s/bootstrap/di.env\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"
}

bootstrap_validate_repo_dir_value() {
  bootstrap_repo_validate_var=$1
  bootstrap_repo_validate_value=$2

  case "$bootstrap_repo_validate_value" in
    ''|/*|../*|*/..|*../*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/@+-]*)
      bootstrap_fatal "${bootstrap_repo_validate_var} must be a safe repository-relative directory path: ${bootstrap_repo_validate_value:-unset}"
      ;;
  esac
}

bootstrap_validate_repo_file_value() {
  bootstrap_repo_validate_file_name=$1
  bootstrap_repo_validate_file_value=$2

  case "$bootstrap_repo_validate_file_value" in
    "${DIR_TARGET_SKEL_VIVALDI:-}/Local State") ;;
    ''|/*|../*|*/..|*../*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/@+-]*)
      bootstrap_fatal "${bootstrap_repo_validate_file_name} must be a safe repository-relative file path: ${bootstrap_repo_validate_file_value:-unset}"
      ;;
  esac
}

bootstrap_repo_env_selector_vars() {
  bootstrap_repo_env_vars_path=$1
  sed -n 's/^\(DIR_[A-Z0-9_]*\|FILE_[A-Z0-9_]*\)=.*/\1/p' "$bootstrap_repo_env_vars_path"
}

bootstrap_repo_dir_input_is_var() {
  case "${1:-}" in
    DIR_[ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*)
      case "$1" in
        *[!ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*) return 1 ;;
      esac
      return 0
      ;;
  esac
  return 1
}

bootstrap_validate_repo_env() {
  bootstrap_repo_env_path_value=$(bootstrap_repo_env_path) || return $?
  [ -r "$bootstrap_repo_env_path_value" ] ||
    bootstrap_fatal "repository path environment is not readable: $bootstrap_repo_env_path_value"
  while IFS= read -r bootstrap_repo_env_var || [ -n "$bootstrap_repo_env_var" ]; do
    [ -n "$bootstrap_repo_env_var" ] || continue
    bootstrap_repo_env_value=
    eval "bootstrap_repo_env_value=\${$bootstrap_repo_env_var:-}"
    case "$bootstrap_repo_env_var" in
      DIR_*) bootstrap_validate_repo_dir_value "$bootstrap_repo_env_var" "$bootstrap_repo_env_value" ;;
      FILE_*) bootstrap_validate_repo_file_value "$bootstrap_repo_env_var" "$bootstrap_repo_env_value" ;;
      *) bootstrap_fatal "unsupported repository selector: $bootstrap_repo_env_var" ;;
    esac
  done <<EOF
$(bootstrap_repo_env_selector_vars "$bootstrap_repo_env_path_value")
EOF
}

bootstrap_di_required_vars() {
  cat <<'EOF'
TARGET_ROOT
DIR_INSTALLER_RUNTIME
DIR_INSTALLER_ENV
DIR_INSTALLER_LATE_ENV
DIR_INSTALLER_PRE_PKGSEL_ENV
DIR_INSTALLER_RUNTIME_STATE
DIR_INSTALLER_TARGET_OWNERSHIP
DIR_INSTALLER_BIN
DIR_INSTALLER_SBIN
DIR_INSTALLER_USR
DIR_INSTALLER_USR_BIN
DIR_INSTALLER_USR_SBIN
DIR_INSTALLER_USR_LOCAL
DIR_INSTALLER_USR_LOCAL_BIN
DIR_INSTALLER_USR_LOCAL_SBIN
DIR_INSTALLER_USR_LOCAL_LIBEXEC
DIR_INSTALLER_STATE
DIR_INSTALLER_TARGET_STAGE
FILE_INSTALLER_LOG
FILE_INSTALLER_TARGET_RENDER_READY
FILE_INSTALLER_SELECTED_DISK_IDENTITY
FILE_INSTALLER_APT_NORMALIZE_SOURCES
FILE_INSTALLER_DPKG_DIVERT
FILE_INSTALLER_OS_PROBER
FILE_INSTALLER_OS_PROBER_REAL
FILE_INSTALLER_OS_PROBER_STATE
FILE_INSTALLER_UNSHARE
FILE_INSTALLER_UNSHARE_REAL
FILE_INSTALLER_UNSHARE_STATE
FILE_INSTALLER_UPDATE_INITRAMFS
FILE_INSTALLER_UPDATE_INITRAMFS_REAL
DIR_INSTALLER_BASE_INSTALLER_D
DIR_INSTALLER_POST_BASE_INSTALLER_D
DIR_INSTALLER_PRE_PKGSEL_D
DIR_INSTALLER_APT_SETUP_GENERATORS
DIR_INSTALLER_FINISH_INSTALL_D
DIR_INSTALLER_LIB_PARTMAN
DIR_INSTALLER_LIB_PARTMAN_FINISH_D
DIR_INSTALLER_VAR_LIB_PARTMAN
EOF
}

bootstrap_validate_di_source() {
  bootstrap_di_source_path=$1
  [ -r "$bootstrap_di_source_path" ] || bootstrap_fatal "installer environment is not readable: $bootstrap_di_source_path"
  /bin/sh -n "$bootstrap_di_source_path" || bootstrap_fatal "installer environment has invalid shell syntax: $bootstrap_di_source_path"
  bootstrap_di_source_names=

  while IFS= read -r bootstrap_di_source_line || [ -n "$bootstrap_di_source_line" ]; do
    case "$bootstrap_di_source_line" in
      ''|[[:space:]]*|\#*)
        case "$bootstrap_di_source_line" in
          ''|\#*) continue ;;
          *) bootstrap_fatal "installer environment contains unsupported leading whitespace: $bootstrap_di_source_path" ;;
        esac
        ;;
    esac
    case "$bootstrap_di_source_line" in
      *'$('*|*'`'*|*';'*|*'|'*|*'&'*)
        bootstrap_fatal "installer environment contains executable syntax: $bootstrap_di_source_path"
        ;;
      [A-Z_][A-Z0-9_]*=\"[A-Za-z0-9._/@+\$\{\}-]*\")
        bootstrap_di_source_name=${bootstrap_di_source_line%%=*}
        case "$bootstrap_di_source_name" in
          TARGET_ROOT|FILE_INSTALLER_*|DIR_INSTALLER_*) ;;
          *) bootstrap_fatal "installer environment contains an unsupported variable: $bootstrap_di_source_name" ;;
        esac
        case " $bootstrap_di_source_names " in
          *" $bootstrap_di_source_name "*) bootstrap_fatal "installer environment contains a duplicate variable: $bootstrap_di_source_name" ;;
        esac
        bootstrap_di_source_names="$bootstrap_di_source_names $bootstrap_di_source_name"
        ;;
      *) bootstrap_fatal "installer environment contains an invalid assignment: $bootstrap_di_source_path" ;;
    esac
  done <"$bootstrap_di_source_path"
}

bootstrap_validate_di_env() {
  bootstrap_validate_di_value=
  for bootstrap_di_env_var in $(bootstrap_di_required_vars); do
    eval "bootstrap_validate_di_value=\${$bootstrap_di_env_var:-}"
    case "$bootstrap_di_env_var:$bootstrap_validate_di_value" in
      TARGET_ROOT:/target) ;;
      TARGET_ROOT:*) bootstrap_fatal 'TARGET_ROOT must be exactly /target' ;;
      DIR_INSTALLER_*:*|FILE_INSTALLER_*:/*)
        case "$bootstrap_validate_di_value" in
          /*) ;;
          *) bootstrap_fatal "${bootstrap_di_env_var} must be absolute" ;;
        esac
        case "$bootstrap_validate_di_value" in
          *..*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/@+-]*)
            bootstrap_fatal "${bootstrap_di_env_var} contains an unsafe path: ${bootstrap_validate_di_value:-unset}"
            ;;
        esac
        ;;
      *) bootstrap_fatal "${bootstrap_di_env_var} is missing from installer environment" ;;
    esac
  done
}

bootstrap_ensure_di_env() {
  bootstrap_di_seed_base=${1:-}
  [ "${BOOTSTRAP_DI_ENV_READY:-0}" -eq 1 ] && return 0
  [ -n "${FILE_HOOKS_INSTALLER_DI_ENV:-}" ] || bootstrap_fatal 'FILE_HOOKS_INSTALLER_DI_ENV is unset in repo.env'
  bootstrap_validate_repo_file_value FILE_HOOKS_INSTALLER_DI_ENV "$FILE_HOOKS_INSTALLER_DI_ENV"

  bootstrap_di_env_file=$(bootstrap_di_env_path) || return $?
  if [ ! -s "$bootstrap_di_env_file" ]; then
    [ -n "$bootstrap_di_seed_base" ] || bootstrap_di_seed_base=$(bootstrap_require_seed_base "") || return $?
    bootstrap_fetch_seed_file "$bootstrap_di_seed_base" "$FILE_HOOKS_INSTALLER_DI_ENV" "$bootstrap_di_env_file" 0600 "installer path environment" || return $?
  fi
  bootstrap_validate_di_source "$bootstrap_di_env_file"
  # shellcheck disable=SC1090
  . "$bootstrap_di_env_file" || return $?
  bootstrap_validate_di_env || return $?
  BOOTSTRAP_DI_ENV_READY=1
}

bootstrap_load_persisted_suite() {
  # d-i invokes maintainer scripts and hook wrappers in fresh processes after
  # the preseed command that exported INSTALLER_SUITE has exited.  Recover only
  # the generated suite context here; an absent context is valid during the
  # initial preseed bootstrap and is handled by the caller's exported value.
  [ -n "${INSTALLER_SUITE:-}" ] && return 0
  bootstrap_context_env=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}/state/context.env
  if [ ! -e "$bootstrap_context_env" ] && [ ! -L "$bootstrap_context_env" ]; then
    return 0
  fi
  [ -f "$bootstrap_context_env" ] && [ ! -L "$bootstrap_context_env" ] && [ -r "$bootstrap_context_env" ] ||
    bootstrap_fatal "installer context is not a regular readable file: $bootstrap_context_env"
  /bin/sh -n "$bootstrap_context_env" ||
    bootstrap_fatal "installer context has invalid shell syntax: $bootstrap_context_env"
  # shellcheck disable=SC1090
  . "$bootstrap_context_env" ||
    bootstrap_fatal "cannot load installer context: $bootstrap_context_env"
  # The caller may launch another d-i helper after loading this state.  Keep
  # the recovered suite in that child environment as well as this shell.
  export INSTALLER_SUITE
}

bootstrap_ensure_repo_env() {
  bootstrap_repo_seed_base=${1:-}

  if [ "${BOOTSTRAP_REPO_ENV_READY:-0}" -eq 1 ]; then
    return 0
  fi

  bootstrap_repo_seed_base=$(bootstrap_require_seed_base "$bootstrap_repo_seed_base") || return $?
  bootstrap_repo_env_file=$(bootstrap_repo_env_path) || return $?
  if [ ! -s "$bootstrap_repo_env_file" ]; then
    bootstrap_fetch_seed_file "$bootstrap_repo_seed_base" "$(bootstrap_repo_env_relpath)" "$bootstrap_repo_env_file" 0600 "repository path environment" || return $?
  fi
  # shellcheck disable=SC1090
  case "${INSTALLER_SUITE:-}" in forky|trixie) ;; *) bootstrap_fatal "pinned suite is missing or unsupported" ;; esac
  . "$bootstrap_repo_env_file" || return $?
  bootstrap_validate_repo_env || return $?
  bootstrap_ensure_di_env "$bootstrap_repo_seed_base" || return $?
  bootstrap_load_prepared_source "$bootstrap_repo_seed_base" || return $?
  BOOTSTRAP_REPO_ENV_READY=1
}

# A single private, root-owned candidate is prepared by the first base hook
# before kernel installation. Bind it once per shell to the authenticated payload identity;
# consumers then copy files/directories without rerendering or revalidating
# the same source ancestry for every member. This is installer state only.
bootstrap_load_prepared_source() {
  if [ "${BOOTSTRAP_PREPARED_BOUND_READY:-0}" = 1 ]; then
    bootstrap_bound_identity=$(source_normalize_base "$1") || return "$?"
    [ "$bootstrap_bound_identity" = "$BOOTSTRAP_PREPARED_SEED_BASE" ] &&
      [ -f "$FILE_INSTALLER_TARGET_RENDER_READY" ] && [ ! -L "$FILE_INSTALLER_TARGET_RENDER_READY" ] &&
      cmp -s "$FILE_INSTALLER_TARGET_RENDER_READY" "${BOOTSTRAP_PREPARED_SOURCE_ROOT%/source}/identity" ||
      bootstrap_fatal 'bound prepared source identity changed'
    return 0
  fi
  BOOTSTRAP_PREPARED_SOURCE_ROOT=
  BOOTSTRAP_PREPARED_SEED_BASE=
  BOOTSTRAP_PREPARED_ARCHIVE_SHA256=
  BOOTSTRAP_PREPARED_PUBLISHED_ASSETS=
  BOOTSTRAP_PREPARED_PRESENT=0
  [ -n "${FILE_INSTALLER_TARGET_RENDER_READY:-}" ] || return 0
  if [ ! -e "$FILE_INSTALLER_TARGET_RENDER_READY" ] && [ ! -L "$FILE_INSTALLER_TARGET_RENDER_READY" ]; then
    bootstrap_prepared_stage_probe=${TARGET_ROOT}${DIR_INSTALLER_TARGET_STAGE:-}
    if [ -n "${DIR_INSTALLER_TARGET_STAGE:-}" ] &&
       { [ -e "$bootstrap_prepared_stage_probe" ] || [ -L "$bootstrap_prepared_stage_probe" ]; }; then
      bootstrap_fatal 'prepared target payload exists without its ready marker'
    fi
    return 0
  fi
  BOOTSTRAP_PREPARED_PRESENT=1
  # Fresh phase runners can reach this before common-lib.sh loads lifecycle.
  # Fetch helpers run in subshells; load the cached transport (which embeds
  # lifecycle) here so its ancestry and metadata helpers exist in this shell.
  bootstrap_load_source_library "$1" || return "$?"
  bootstrap_prepared_stage=${TARGET_ROOT}${DIR_INSTALLER_TARGET_STAGE}
  installer_lifecycle_parent_safe "$bootstrap_prepared_stage" || bootstrap_fatal 'unsafe prepared target payload ancestry'
  for bootstrap_prepared_file in "$FILE_INSTALLER_TARGET_RENDER_READY" \
      "$bootstrap_prepared_stage/identity" "$bootstrap_prepared_stage/receipt.json" \
      "$bootstrap_prepared_stage/inputs/rendered.checksums" \
      "$bootstrap_prepared_stage/inputs/published-assets.tsv"; do
    [ -f "$bootstrap_prepared_file" ] && [ ! -L "$bootstrap_prepared_file" ] ||
      bootstrap_fatal 'prepared target payload is incomplete or indirect'
    [ "$(installer_metadata_value "$bootstrap_prepared_file" uid_gid_mode_links)" = 0:0:600:1 ] ||
      bootstrap_fatal 'unsafe prepared target payload metadata'
  done
  [ "$(installer_metadata_value "$bootstrap_prepared_stage" uid_gid_mode)" = 0:0:700 ] ||
    bootstrap_fatal 'prepared target payload must remain private'
  cmp -s "$FILE_INSTALLER_TARGET_RENDER_READY" "$bootstrap_prepared_stage/identity" &&
    cmp -s "$FILE_INSTALLER_TARGET_RENDER_READY" "${DIR_INSTALLER_RUNTIME}/bootstrap/payload.ready" ||
    bootstrap_fatal 'prepared target payload belongs to a different authenticated source'
  IFS=' ' read -r bootstrap_identity_archive bootstrap_identity_manifest bootstrap_identity_base \
    <"$bootstrap_prepared_stage/identity" ||
    bootstrap_fatal 'prepared target payload identity cannot be parsed'
  case "$bootstrap_identity_archive" in ''|*[!a-f0-9]*) bootstrap_fatal 'prepared target payload archive identity has invalid digest' ;; esac
  case "$bootstrap_identity_manifest" in ''|*[!a-f0-9]*) bootstrap_fatal 'prepared target payload manifest identity has invalid digest' ;; esac
  [ "${#bootstrap_identity_archive}" -eq 64 ] && [ "${#bootstrap_identity_manifest}" -eq 64 ] ||
    bootstrap_fatal 'prepared target payload identity digest length is invalid'
  [ "$(wc -l <"$bootstrap_prepared_stage/receipt.json")" -eq 1 ] &&
    [ "$(wc -c <"$bootstrap_prepared_stage/receipt.json")" -le 16384 ] &&
    LC_ALL=C grep -Eq '^\{"format":1,"members":[1-9][0-9]{0,4},"input_bytes":[0-9]{1,9},"rendered_files":[0-9]{1,5},"rendered_bytes":[0-9]{1,9},"published_perl_files":[1-9][0-9]{0,4},"rendered_sha256":"[a-f0-9]{64}","rendered_manifest_sha256":"[a-f0-9]{64}","published_manifest_sha256":"[a-f0-9]{64}","source_archive_sha256":"[a-f0-9]{64}","source_manifest_sha256":"[a-f0-9]{64}","source_identity":"[A-Za-z0-9:/._+?%#@ -]+"\}$' "$bootstrap_prepared_stage/receipt.json" ||
    bootstrap_fatal 'prepared target receipt schema is invalid'
  grep -Fqx "\"source_archive_sha256\":\"$bootstrap_identity_archive\"" \
    "$bootstrap_prepared_stage/receipt.json" 2>/dev/null ||
    grep -Fq "\"source_archive_sha256\":\"$bootstrap_identity_archive\"" \
      "$bootstrap_prepared_stage/receipt.json" ||
    bootstrap_fatal 'prepared target receipt archive identity mismatch'
  grep -Fq "\"source_manifest_sha256\":\"$bootstrap_identity_manifest\"" \
    "$bootstrap_prepared_stage/receipt.json" ||
    bootstrap_fatal 'prepared target receipt manifest identity mismatch'
  grep -Fq "\"source_identity\":\"$bootstrap_identity_base\"" \
    "$bootstrap_prepared_stage/receipt.json" ||
    bootstrap_fatal 'prepared target receipt seed identity mismatch'
  BOOTSTRAP_PREPARED_SOURCE_ROOT=$bootstrap_prepared_stage/source
  if command -v source_normalize_base >/dev/null 2>&1; then
    bootstrap_requested_identity=$(source_normalize_base "$1") ||
      bootstrap_fatal 'prepared target payload seed identity is not canonical'
  else
    bootstrap_requested_identity=$1
  fi
  [ "$bootstrap_identity_base" = "$bootstrap_requested_identity" ] ||
    bootstrap_fatal 'prepared target payload seed identity differs from authenticated request'
  bootstrap_rendered_expected=$(sed -n 's/.*"rendered_manifest_sha256":"\([a-f0-9]\{64\}\)".*/\1/p' \
    "$bootstrap_prepared_stage/receipt.json") || return "$?"
  bootstrap_rendered_actual=$(sha256sum "$bootstrap_prepared_stage/inputs/rendered.checksums") || return "$?"
  [ "${bootstrap_rendered_actual%% *}" = "$bootstrap_rendered_expected" ] ||
    bootstrap_fatal 'prepared rendered member index differs from its receipt'
  bootstrap_published_expected=$(sed -n 's/.*"published_manifest_sha256":"\([a-f0-9]\{64\}\)".*/\1/p' \
    "$bootstrap_prepared_stage/receipt.json") || return "$?"
  bootstrap_published_actual=$(sha256sum "$bootstrap_prepared_stage/inputs/published-assets.tsv") || return "$?"
  [ "${bootstrap_published_actual%% *}" = "$bootstrap_published_expected" ] ||
    bootstrap_fatal 'prepared published member index differs from its receipt'
  bootstrap_expected_members=$(sed -n 's/.*"members":\([0-9]*\),.*/\1/p' "$bootstrap_prepared_stage/receipt.json")
  # One bounded metadata walk rejects extra files, links, unsafe ownership and
  # writable members. Parse only fixed numeric ls columns, never filenames.
  (LC_ALL=C ls -lnR -- "$BOOTSTRAP_PREPARED_SOURCE_ROOT"; printf '\nSCAN_STATUS=%s\n' "$?") |
    LC_ALL=C awk -v expected="$bootstrap_expected_members" '
      /^SCAN_STATUS=/ { if ($0 != "SCAN_STATUS=0") bad=1; completed++; next }
      /^[[:space:]]*$/ || /^total [0-9]+$/ || /^\// { next }
      {
        if (++entries > 20000 || length($1) < 10 || $3 != 0 || $4 != 0 ||
            substr($1,6,1) == "w" || substr($1,9,1) == "w") bad=1
        if (substr($1,1,1) == "-") {
          if ($2 != 1 || ++members > 10000) bad=1
        } else if (substr($1,1,1) != "d") bad=1
      }
      END { exit bad || completed != 1 || members != expected }
    ' || bootstrap_fatal 'prepared source inventory or member metadata differs from its receipt'
  # The base hook already authenticated/rendered the entire snapshot. Retain
  # its verified index and validate only members that cross an execution or
  # publication boundary, instead of rehashing thousands of unrelated files
  # every time a phase starts or loads another support library.
  BOOTSTRAP_PREPARED_MEMBER_INDEX=$(cat "$bootstrap_prepared_stage/inputs/rendered.checksums") || return "$?"
  BOOTSTRAP_PREPARED_PATH_VALUES=$(cat "$bootstrap_prepared_stage/inputs/paths.map") || return "$?"
  BOOTSTRAP_PREPARED_SEED_BASE=$bootstrap_requested_identity
  BOOTSTRAP_PREPARED_ARCHIVE_SHA256=$bootstrap_identity_archive
  BOOTSTRAP_PREPARED_PUBLISHED_ASSETS=$(cat "$bootstrap_prepared_stage/inputs/published-assets.tsv") || return "$?"
  BOOTSTRAP_PREPARED_BOUND_READY=1
}

bootstrap_prepared_member_digest() {
  printf '%s\n' "$BOOTSTRAP_PREPARED_MEMBER_INDEX" | LC_ALL=C awk -v member="$1" '
    substr($0,67) == member { digest=substr($0,1,64); count++ }
    END { if (count != 1 || length(digest) != 64 || digest !~ /^[a-f0-9]+$/) exit 1; print digest }
  '
}

bootstrap_prepared_member_path() (
  set -eu
  prepared_member=$1
  source_validate_relative "$prepared_member" || exit 1
  prepared_source=$BOOTSTRAP_PREPARED_SOURCE_ROOT/$prepared_member
  installer_lifecycle_parent_safe "${prepared_source%/*}" || exit 1
  [ -f "$prepared_source" ] && [ ! -L "$prepared_source" ] &&
    [ "$(installer_metadata_value "$prepared_source" uid_gid_mode_links)" = 0:0:644:1 ] || {
      bootstrap_log 'fatal: prepared executable/parser member has unsafe metadata'; exit 1;
    }
  prepared_expected=$(bootstrap_prepared_member_digest "$prepared_member") || exit 1
  prepared_actual=$(sha256sum "$prepared_source") || exit 1
  [ "${prepared_actual%% *}" = "$prepared_expected" ] || {
    bootstrap_log 'fatal: prepared executable/parser member differs from its receipt'; exit 1;
  }
  printf '%s\n' "$prepared_source"
)

# Complete namespaces were published before late_command. The receipt binds
# source, destination, mode and digest; a declared member cannot silently fall
# back to another acquisition/publication path when its identity changes.
bootstrap_prepared_asset_published() {
  [ -n "${BOOTSTRAP_PREPARED_SOURCE_ROOT:-}" ] || return 1
  case "$3" in 644|0644) ;; *) return 1 ;; esac
  bootstrap_published_prefix=$(printf '%s\t%s\t0644\t' "$1" "$2")
  case "
$BOOTSTRAP_PREPARED_PUBLISHED_ASSETS
" in *"
$bootstrap_published_prefix"*) ;; *) return 1 ;; esac
  [ -f "${TARGET_ROOT}$2" ] && [ ! -L "${TARGET_ROOT}$2" ] ||
    bootstrap_fatal 'published prepared Perl member is missing or indirect'
  [ "$(installer_metadata_value "${TARGET_ROOT}$2" uid_gid_mode_links)" = 0:0:644:1 ] ||
    bootstrap_fatal 'published prepared Perl member metadata changed'
  bootstrap_published_digest=$(sha256sum "${TARGET_ROOT}$2") || return "$?"
  bootstrap_published_digest=${bootstrap_published_digest%% *}
  bootstrap_published_row=$(printf '%s\t%s\t0644\t%s' "$1" "$2" "$bootstrap_published_digest")
  case "
$BOOTSTRAP_PREPARED_PUBLISHED_ASSETS
" in *"
$bootstrap_published_row
"*) return 0 ;; esac
  bootstrap_fatal 'published prepared Perl member digest changed'
}

bootstrap_copy_prepared_file() (
  set -eu
  umask 077
  [ -n "${BOOTSTRAP_PREPARED_SOURCE_ROOT:-}" ] || exit 125
  prepared_requested_seed=$1
  if command -v source_normalize_base >/dev/null 2>&1; then
    prepared_requested_seed=$(source_normalize_base "$prepared_requested_seed") || exit 125
  fi
  [ "$prepared_requested_seed" = "$BOOTSTRAP_PREPARED_SEED_BASE" ] || exit 125
  prepared_relative=$2; prepared_destination=$3; prepared_mode=${4:-0600}
  source_validate_relative "$prepared_relative" || exit 1
  case "$prepared_mode" in [0-7][0-7][0-7]|0[0-7][0-7][0-7]) ;; *) exit 1 ;; esac
  prepared_source=$BOOTSTRAP_PREPARED_SOURCE_ROOT/$prepared_relative
  case "$prepared_relative" in
    *.tmpl) ;;
    *)
      if [ -e "$prepared_source.tmpl" ] || [ -L "$prepared_source.tmpl" ]; then
        [ ! -e "$prepared_source" ] && [ ! -L "$prepared_source" ] || exit 1
        prepared_source=$prepared_source.tmpl
      fi ;;
  esac
  [ -f "$prepared_source" ] && [ ! -L "$prepared_source" ] || {
    bootstrap_log "fatal: file absent from prepared target payload: $prepared_relative"; exit 1;
  }
  installer_lifecycle_parent_safe "${prepared_source%/*}" || exit 1
  [ "$(installer_metadata_value "$prepared_source" links)" = 1 ] || {
    bootstrap_log 'fatal: prepared target member is hardlinked'; exit 1;
  }
  prepared_member=${prepared_source#"$BOOTSTRAP_PREPARED_SOURCE_ROOT/"}
  prepared_digest=$(bootstrap_prepared_member_digest "$prepared_member") || {
    bootstrap_log 'fatal: prepared target member has no unique rendered digest'; exit 1;
  }
  case "$prepared_destination" in
    "$BOOTSTRAP_PREPARED_SOURCE_ROOT"|"$BOOTSTRAP_PREPARED_SOURCE_ROOT/"*)
      bootstrap_log 'fatal: prepared target source is immutable'; exit 1 ;;
  esac
  prepared_parent=${prepared_destination%/*}
  [ "$prepared_parent" != "$prepared_destination" ] || prepared_parent=.
  mkdir -p "$prepared_parent"
  prepared_temporary=$(mktemp "$prepared_parent/.prepared-asset.XXXXXX")
  trap 'rm -f -- "$prepared_temporary"' 0
  trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
  cat "$prepared_source" >"$prepared_temporary"
  prepared_actual=$(sha256sum "$prepared_temporary") || exit 1
  [ "${prepared_actual%% *}" = "$prepared_digest" ] || {
    bootstrap_log 'fatal: prepared target member digest changed before publication'; exit 1;
  }
  chmod "$prepared_mode" "$prepared_temporary"
  mv -fT -- "$prepared_temporary" "$prepared_destination"
)

bootstrap_repo_dir_value() {
  bootstrap_repo_dir_name=$1
  bootstrap_repo_dir_value=
  bootstrap_repo_dir_path=

  if ! bootstrap_repo_dir_input_is_var "$bootstrap_repo_dir_name"; then
    bootstrap_repo_dir_path=$bootstrap_repo_dir_name
    bootstrap_validate_repo_dir_value repository_path "$bootstrap_repo_dir_path"
    printf '%s\n' "$bootstrap_repo_dir_path"
    return 0
  fi

  eval "bootstrap_repo_dir_value=\${$bootstrap_repo_dir_name:-}"
  [ -n "$bootstrap_repo_dir_value" ] || bootstrap_fatal "repository directory variable is unset: $bootstrap_repo_dir_name"
  bootstrap_validate_repo_dir_value "$bootstrap_repo_dir_name" "$bootstrap_repo_dir_value"
  printf '%s\n' "$bootstrap_repo_dir_value"
}

bootstrap_repo_file_value() {
  bootstrap_repo_file_name=$1
  case "$bootstrap_repo_file_name" in
    FILE_[A-Z0-9_]*) ;;
    *) bootstrap_fatal "repository file selector is invalid: ${bootstrap_repo_file_name:-unset}" ;;
  esac
  case "$bootstrap_repo_file_name" in
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*)
      bootstrap_fatal "repository file selector is invalid: $bootstrap_repo_file_name"
      ;;
  esac

  bootstrap_repo_file_value_result=
  eval "bootstrap_repo_file_value_result=\${$bootstrap_repo_file_name:-}"
  [ -n "$bootstrap_repo_file_value_result" ] ||
    bootstrap_fatal "repository file variable is unset: $bootstrap_repo_file_name"
  bootstrap_validate_repo_file_value "$bootstrap_repo_file_name" "$bootstrap_repo_file_value_result"
  printf '%s\n' "$bootstrap_repo_file_value_result"
}

bootstrap_repo_join_var() {
  bootstrap_repo_join_dir=$1
  bootstrap_repo_join_leaf=${2:-}
  bootstrap_repo_join_base=$(bootstrap_repo_dir_value "$bootstrap_repo_join_dir") || return $?

  # Systemd template-unit paths legitimately contain "@", for example
  # etc/systemd/system/user@.service.d/50-oom-score.conf.
  case "$bootstrap_repo_join_leaf" in
    '') printf '%s\n' "$bootstrap_repo_join_base" ;;
    # Chromium-derived Vivaldi profiles require this exact space-containing
    # filename. Keep the exception limited to the managed seed asset, and
    # normalize a leading slash if an older caller supplies one.
    "etc/skel-desktop/.config/vivaldi/Local State")
      printf '%s/%s\n' "$bootstrap_repo_join_base" "$bootstrap_repo_join_leaf"
      ;;
    "/etc/skel-desktop/.config/vivaldi/Local State")
      printf '%s/etc/skel-desktop/.config/vivaldi/Local State\n' "$bootstrap_repo_join_base"
      ;;
    /*|../*|*/..|*../*|*//*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/@-]*)
      bootstrap_fatal "unsafe repository path suffix for ${bootstrap_repo_join_dir}: ${bootstrap_repo_join_leaf:-unset}"
      ;;
    *) printf '%s/%s\n' "$bootstrap_repo_join_base" "$bootstrap_repo_join_leaf" ;;
  esac
}

bootstrap_repo_resolve_path() {
  bootstrap_repo_source_path=$1

  case "$bootstrap_repo_source_path" in
    "$(bootstrap_repo_env_relpath)")
      printf '%s\n' "$bootstrap_repo_source_path"
      return 0
      ;;
  esac

  bootstrap_ensure_repo_env ""
  case "$bootstrap_repo_source_path" in
    "${DIR_SCRIPTS_COMMON}/"*)
      bootstrap_repo_join_var DIR_SCRIPTS_COMMON "${bootstrap_repo_source_path#"${DIR_SCRIPTS_COMMON}"/}"
      ;;
    "${DIR_SCRIPTS_PRESEED}/"*)
      bootstrap_repo_join_var DIR_SCRIPTS_PRESEED "${bootstrap_repo_source_path#"${DIR_SCRIPTS_PRESEED}"/}"
      ;;
    "${DIR_SCRIPTS_EARLY}/"*)
      bootstrap_repo_join_var DIR_SCRIPTS_EARLY "${bootstrap_repo_source_path#"${DIR_SCRIPTS_EARLY}"/}"
      ;;
    "${DIR_SCRIPTS_PARTMAN}/"*)
      bootstrap_repo_join_var DIR_SCRIPTS_PARTMAN "${bootstrap_repo_source_path#"${DIR_SCRIPTS_PARTMAN}"/}"
      ;;
    "${DIR_SCRIPTS_LATE}/"*)
      bootstrap_repo_join_var DIR_SCRIPTS_LATE "${bootstrap_repo_source_path#"${DIR_SCRIPTS_LATE}"/}"
      ;;
    *)
      printf '%s\n' "$bootstrap_repo_source_path"
      ;;
  esac
}

bootstrap_phase_runner_path() {
  runner_name=$1
  printf '%s/bootstrap/%s\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}" "$runner_name"
}

bootstrap_seed_source_type() {
  case "${1:-}" in
    /*) printf '%s\n' file ;;
    *) printf '%s\n' url ;;
  esac
}

bootstrap_trim_seed_base() {
  seed_base=$1

  while [ "${#seed_base}" -gt 1 ]; do
    case "$seed_base" in
      */) seed_base=${seed_base%/} ;;
      *) break ;;
    esac
  done
  printf '%s\n' "$seed_base"
}

bootstrap_cmdline() {
  if [ -n "${INSTALLER_CMDLINE:-}" ]; then
    printf '%s\n' "$INSTALLER_CMDLINE"
    return 0
  fi
  if [ "${BOOTSTRAP_CMDLINE_CACHE_READY:-0}" -eq 1 ]; then
    printf '%s\n' "$BOOTSTRAP_CMDLINE_CACHE"
    return 0
  fi
  if [ -r /proc/cmdline ]; then
    BOOTSTRAP_CMDLINE_CACHE=$(cat /proc/cmdline)
  else
    BOOTSTRAP_CMDLINE_CACHE=
  fi
  BOOTSTRAP_CMDLINE_CACHE_READY=1
  printf '%s\n' "$BOOTSTRAP_CMDLINE_CACHE"
}

bootstrap_assign_normalized_seed_base() {
  output_var_name=$1
  seed_base=$2
  seed_type=$3

  seed_base=${seed_base%%\?*}
  case "$seed_base" in
    */*.cfg) seed_base=${seed_base%/*} ;;
  esac
  seed_base=$(bootstrap_trim_seed_base "$seed_base")

  case "$seed_type" in
    file)
      case "$seed_base" in
        /*) ;;
        *) bootstrap_fatal "installation file base must be an absolute path: ${seed_base:-unset}" ;;
      esac
      case "$seed_base" in
        *..*|*//*)
          bootstrap_fatal "installation file base contains unsupported traversal: $seed_base"
          ;;
      esac
      ;;
    url)
      [ -n "$seed_base" ] || bootstrap_fatal "installation URL base is empty"
      ;;
    *)
      bootstrap_fatal "unsupported installation source type: $seed_type"
      ;;
  esac

  eval "$output_var_name=\$seed_base"
}

bootstrap_normalize_seed_base() {
  normalized_seed_base=
  bootstrap_assign_normalized_seed_base normalized_seed_base "$1" "$2"
  printf '%s\n' "$normalized_seed_base"
}

bootstrap_validate_relative_seed_path() {
  seed_relative_path=$1

  case "$seed_relative_path" in
    ''|/*|../*|*/..|*../*|*//*)
      bootstrap_fatal "seed source path must stay relative to the seed base: ${seed_relative_path:-unset}"
      ;;
  esac
}

bootstrap_log_path_is_numbered() {
  bootstrap_check_log_path=$1
  bootstrap_check_log_name=${bootstrap_check_log_path##*/}

  case "$bootstrap_check_log_name" in
    [0-9]*-*) return 0 ;;
  esac
  return 1
}

bootstrap_log_sequence_file() {
  bootstrap_sequence_log_dir=$1
  printf '%s/.log-sequence\n' "$bootstrap_sequence_log_dir"
}

bootstrap_next_log_sequence() {
  bootstrap_sequence_log_dir=$1
  bootstrap_sequence_path=$(bootstrap_log_sequence_file "$bootstrap_sequence_log_dir")
  bootstrap_sequence_tmp="${bootstrap_sequence_path}.tmp.$$"
  bootstrap_current_sequence=0

  [ -d "$bootstrap_sequence_log_dir" ] || install -d -m 0700 "$bootstrap_sequence_log_dir"
  if [ -r "$bootstrap_sequence_path" ]; then
    bootstrap_current_sequence=$(cat "$bootstrap_sequence_path" 2>/dev/null || printf '0\n')
  fi
  case "$bootstrap_current_sequence" in
    ''|*[!0-9]*) bootstrap_current_sequence=0 ;;
  esac

  bootstrap_next_sequence=$((bootstrap_current_sequence + 1))
  printf '%s\n' "$bootstrap_next_sequence" >"$bootstrap_sequence_tmp"
  mv "$bootstrap_sequence_tmp" "$bootstrap_sequence_path"
  chmod 0600 "$bootstrap_sequence_path" 2>/dev/null || true
  printf '%s\n' "$bootstrap_next_sequence"
}

bootstrap_runtime_log_path_requested() {
  requested_log_path=$1
  runtime_log_dir=$(bootstrap_runtime_log_dir)

  case "$requested_log_path" in
    "${runtime_log_dir}/"*) return 0 ;;
  esac
  return 1
}

bootstrap_resolve_runtime_log_path() {
  bootstrap_runtime_log_file
}

bootstrap_file_safe_token() {
  printf '%s\n' "$(printf '%s' "${1:-seed}" | sed 's/[^A-Za-z0-9._-]/_/g')"
}

bootstrap_seed_cache_key() (
  bootstrap_load_source_library "$1" || exit 1
  normalized=$(source_normalize_base "$1") || exit 1
  key=$(printf '%s' "$normalized" | source_hash) || exit 1
  printf '%s\n' "${key%% *}"
)

bootstrap_seed_cache_path() (
  bootstrap_load_source_library "$1" || exit 1
  source_validate_relative "$2" || exit 1
  printf '%s/%s\n' "$(source_cache_root "$1")" "$2"
)

bootstrap_persist_seed_source() {
  seed_base=$1
  seed_type=$(bootstrap_seed_source_type "$seed_base") || return $?
  seed_url_path=$(bootstrap_seed_url_path) || return $?
  seed_file_path=$(bootstrap_seed_file_path) || return $?

  install -d -m 0700 "${seed_file_path%/*}" || return $?

  case "$seed_type" in
    file)
      printf '%s\n' "$seed_base" >"$seed_file_path" || return $?
      rm -f "$seed_url_path" || return $?
      ;;
    url)
      printf '%s\n' "$seed_base" >"$seed_url_path" || return $?
      rm -f "$seed_file_path" || return $?
      ;;
    *)
      bootstrap_fatal "unsupported installation source type: $seed_type"
      ;;
  esac
}

bootstrap_choose_seed_base_from_pair() {
  seed_url_base=$1
  seed_file_base=$2
  seed_label=$3

  if [ -n "$seed_url_base" ] && [ -n "$seed_file_base" ]; then
    bootstrap_fatal "${seed_label} defines both URL and file seed sources"
  fi
  if [ -n "$seed_url_base" ]; then
    bootstrap_assign_normalized_seed_base BOOTSTRAP_RESOLVED_SEED_BASE "$seed_url_base" url
    return 0
  fi
  if [ -n "$seed_file_base" ]; then
    bootstrap_assign_normalized_seed_base BOOTSTRAP_RESOLVED_SEED_BASE "$seed_file_base" file
    return 0
  fi

  BOOTSTRAP_RESOLVED_SEED_BASE=
  return 1
}

bootstrap_persisted_seed_base() {
  persisted_seed_url_base=
  persisted_seed_file_base=
  seed_url_path=$(bootstrap_seed_url_path)
  seed_file_path=$(bootstrap_seed_file_path)

  if [ -f "$seed_url_path" ]; then
    persisted_seed_url_base=$(cat "$seed_url_path")
  fi
  if [ -f "$seed_file_path" ]; then
    persisted_seed_file_base=$(cat "$seed_file_path")
  fi

  bootstrap_choose_seed_base_from_pair "$persisted_seed_url_base" "$persisted_seed_file_base" "persisted installer state"
}

bootstrap_cmdline_seed_base() {
  if [ "${BOOTSTRAP_CMDLINE_SEED_PAIR_READY:-0}" -eq 1 ]; then
    if bootstrap_choose_seed_base_from_pair "$BOOTSTRAP_CMDLINE_SEED_URL_BASE" "$BOOTSTRAP_CMDLINE_SEED_FILE_BASE" "kernel cmdline"; then
      printf '%s\n' "$BOOTSTRAP_RESOLVED_SEED_BASE"
      return 0
    fi
    return 1
  fi

  cmdline_seed_url_base=
  cmdline_seed_file_base=

  for arg in $(bootstrap_cmdline); do
    case "$arg" in
      preseed/url=*|url=*)
        [ -n "$cmdline_seed_url_base" ] || cmdline_seed_url_base=${arg#*=}
        ;;
      preseed/file=*|file=*)
        [ -n "$cmdline_seed_file_base" ] || cmdline_seed_file_base=${arg#*=}
        ;;
    esac
  done

  BOOTSTRAP_CMDLINE_SEED_URL_BASE=$cmdline_seed_url_base
  BOOTSTRAP_CMDLINE_SEED_FILE_BASE=$cmdline_seed_file_base
  BOOTSTRAP_CMDLINE_SEED_PAIR_READY=1

  if bootstrap_choose_seed_base_from_pair "$cmdline_seed_url_base" "$cmdline_seed_file_base" "kernel cmdline"; then
    printf '%s\n' "$BOOTSTRAP_RESOLVED_SEED_BASE"
    return 0
  fi
  return 1
}

bootstrap_require_seed_base() {
  # source.sh validates the selected suite while resolving a fresh preseed
  # source, so restore persisted context before any seed discovery can run.
  bootstrap_load_persisted_suite
  if [ -n "${1:-}" ]; then
    bootstrap_normalize_seed_base "$1" "$(bootstrap_seed_source_type "$1")"
    return 0
  fi
  if bootstrap_persisted_seed_base; then
    printf '%s\n' "$BOOTSTRAP_RESOLVED_SEED_BASE"
    return 0
  fi
  bootstrap_load_source_library "${INSTALLER_SOURCE_ROOT:-}" || return 1
  source_resolve_seed
}

bootstrap_require_seed_url_base() {
  bootstrap_require_seed_base "${1:-}"
}

bootstrap_fetch_seed_file() (
  bootstrap_load_source_library "$1" || exit "$?"
  if [ -n "${BOOTSTRAP_PREPARED_SOURCE_ROOT:-}" ] && [ "$1" = "$BOOTSTRAP_PREPARED_SEED_BASE" ]; then
    if command -v installer_repo_assert_asset_family >/dev/null 2>&1; then
      installer_repo_assert_asset_family "$2" || exit "$?"
    fi
    bootstrap_copy_prepared_file "$@"
    exit "$?"
  fi
  # repository-apt is loaded before context-target during common bootstrap.
  # Delegate only when its source-library dependency exists. The initialized
  # publisher already owns the private fetch/render transaction.
  if command -v installer_fetch_seed_path >/dev/null 2>&1 &&
     command -v installer_load_source_library >/dev/null 2>&1; then
    installer_fetch_seed_path "$1" "$2" "$3" "${4:-0600}"
    exit "$?"
  fi
  bootstrap_path_destination=$3
  bootstrap_path_work=
  case "$2" in
    "${DIR_REPO_SCRIPTS:-}/"*|"${DIR_HOOKS_TARGET:-}/"*)
      # Keep the previous destination intact until acquisition and rendering
      # both succeed. The private sibling also bounds cleanup to this fetch.
      bootstrap_path_parent=$(dirname "$bootstrap_path_destination") || exit "$?"
      mkdir -p "$bootstrap_path_parent" || exit "$?"
      bootstrap_path_work=$(mktemp -d "$bootstrap_path_parent/.bootstrap-asset.XXXXXX") || exit "$?"
      bootstrap_path_cleanup() {
        bootstrap_cleanup_status=$?
        trap - 0
        if ! rm -rf -- "$bootstrap_path_work"; then
          [ "$bootstrap_cleanup_status" -ne 0 ] || bootstrap_cleanup_status=125
        fi
        exit "$bootstrap_cleanup_status"
      }
      trap bootstrap_path_cleanup 0
      trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
      chmod 0700 "$bootstrap_path_work" || exit "$?"
      set -- "$1" "$2" "$bootstrap_path_work/asset" "${4:-0600}"
      ;;
  esac
  source_fetch "$1" "$2" "$3" "${4:-0600}" || exit "$?"
  if command -v installer_render_logging_asset >/dev/null 2>&1; then
    installer_render_logging_asset "$1" "$2" "$3" || exit "$?"
  else
    case "$2" in
      "${DIR_HOOKS_TARGET:-}/"*|"${DIR_REPO_SCRIPTS:-}/"*)
        if LC_ALL=C grep -Eq '__INSTALLER_LOG_[A-Z0-9_]+__' "$3"; then
          bootstrap_fatal 'logging template requested before common library initialization'
        fi ;;
    esac
  fi
  case "$2" in
    "${DIR_REPO_SCRIPTS:-}/"*|"${DIR_HOOKS_TARGET:-}/"*)
      if LC_ALL=C grep -Eq '__INSTALLER_((PATH|APPARMOR_PROFILE)_[A-Z0-9_]+|GITBUILD_DISTRIBUTION)__' "$3"; then
        # Direct helper fetches (including Python and target re-entry scripts)
        # share the publication renderer. Early common/bootstrap modules and
        # authenticated parser data contain no concrete path tokens, so they
        # can load before the renderer and profile are initialized.
        bootstrap_path_cache=$(source_cache_root "$1") || exit "$?"
        case "$bootstrap_path_destination" in
          "$bootstrap_path_cache"|"$bootstrap_path_cache"/*)
            bootstrap_fatal 'refusing to render inside the authenticated source snapshot' ;;
        esac
        command -v installer_apply_scalar_placeholders >/dev/null 2>&1 &&
          command -v installer_assert_no_unresolved_path_placeholders >/dev/null 2>&1 ||
          bootstrap_fatal 'runtime path asset requested before common library initialization'
        # The caller supplies the protected destination mode.  Do not invoke
        # `stat`: busybox-udeb intentionally omits that applet.
        bootstrap_path_mode=${4:-0600}
        bootstrap_path_rendered="${3}.path-rendered"
        installer_apply_scalar_placeholders "$3" "$bootstrap_path_rendered" || exit "$?"
        installer_assert_no_unresolved_path_placeholders "$bootstrap_path_rendered" "$2" || exit "$?"
        chmod "$bootstrap_path_mode" "$bootstrap_path_rendered" || exit "$?"
        mv -f -- "$bootstrap_path_rendered" "$3" || exit "$?"
      else
        bootstrap_path_probe_status=$?
        [ "$bootstrap_path_probe_status" -eq 1 ] || exit 1
      fi
      ;;
  esac
  if [ -n "$bootstrap_path_work" ]; then
    mv -f -- "$3" "$bootstrap_path_destination" || exit "$?"
  fi
)

# Modules share the same source snapshot, transport and logging renderer as every
# other installer asset. Explicit callers define order; no glob, eval or PATH
# search chooses executable code. This resolver runs in a subshell so source
# transfer/rendering cannot clobber the caller's phase variables.
bootstrap_module_path() (
  set -eu
  umask 077
  [ "$#" -eq 1 ] || { bootstrap_log 'fatal: one module path is required'; exit 1; }
  # The catalog names physical template members; sourcing still receives the
  # same validated shell module after the shared renderer has run.
  case "${1%.tmpl}" in
    "${DIR_SCRIPTS_COMMON}/"*.sh|"${DIR_SCRIPTS_COMMON_MODULES}/"*.sh|"${DIR_SCRIPTS_RUNTIME_MODULES}/"*.sh|"${DIR_SCRIPTS_DESKTOP_COMPONENTS}/"*.sh|"${DIR_SCRIPTS_LATE_DEVOPS}/"*.sh) ;;
    *)
      # Account publication runs before a storage-family runtime is loaded.
      # Permit only its two definition-only entrypoints here; storage runtimes
      # and arbitrary siblings remain outside the shell-module interface.
      module_common_entry=$(bootstrap_repo_file_value FILE_RUNTIME_COMMON) || exit "$?"
      module_account_entry=$(bootstrap_repo_file_value FILE_RUNTIME_ACCOUNT) || exit "$?"
      case "$1" in
        "$module_common_entry"|"$module_account_entry") ;;
        *) bootstrap_log "fatal: unsupported module path: $1"; exit 1 ;;
      esac
      ;;
  esac
  bootstrap_load_source_library "${INSTALLER_SOURCE_ROOT:-}" || exit 1
  source_validate_relative "$1" || exit 1
  module_relative=$1
  module_seed=$(bootstrap_require_seed_base "") || exit 1
  if [ -n "${BOOTSTRAP_PREPARED_SOURCE_ROOT:-}" ] && [ "$module_seed" = "$BOOTSTRAP_PREPARED_SEED_BASE" ]; then
    bootstrap_prepared_member_path "$module_relative"
    exit 0
  fi
  # Remote code always requires the preseed-pinned payload. Explicit local
  # source trees remain usable by the existing developer/test bootstrap path.
  case "$module_seed" in
    /*) ;;
    *)
      [ -f "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}/bootstrap/payload.ready" ] || {
        bootstrap_log 'fatal: remote module loading requires the authenticated payload'; exit 1;
      } ;;
  esac
  installer_lifecycle_paths || { bootstrap_log 'fatal: unsafe module runtime directory'; exit 1; }
  module_destination="${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}/bootstrap/modules/$module_relative"
  module_parent=${module_destination%/*}
  module_probe=$module_parent
  # Refuse links and writable directories before mkdir, never repair an
  # untrusted pre-existing path into one we subsequently treat as trusted.
  while [ "$module_probe" != / ]; do
    [ ! -L "$module_probe" ] || { bootstrap_log 'fatal: symlinked module directory'; exit 1; }
    if [ -e "$module_probe" ]; then
      [ -d "$module_probe" ] || exit 1
      case "$module_probe" in
        "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"/*)
          [ "$(installer_metadata_value "$module_probe" uid)" = "$(id -u)" ] || exit 1
          case "$(installer_metadata_value "$module_probe" mode)" in
            700|500|750|550|755|555) ;;
            *) bootstrap_log 'fatal: writable or unsafe module directory'; exit 1 ;;
          esac ;;
      esac
    fi
    module_probe=${module_probe%/*}; [ -n "$module_probe" ] || module_probe=/
  done
  if [ -e "$module_destination" ] || [ -L "$module_destination" ]; then
    [ -f "$module_destination" ] && [ ! -L "$module_destination" ] || exit 1
    [ "$(installer_metadata_value "$module_destination" uid)" = "$(id -u)" ] || exit 1
    [ "$(installer_metadata_value "$module_destination" links)" = 1 ] || exit 1
  fi
  mkdir -p "$module_parent" || exit 1
  # Common and runtime modules follow the same checked publication path. The
  # bootstrap fallback handles definition-only dependencies before the higher
  # library is ready; no module may bypass path validation merely by its root.
  bootstrap_fetch_seed_file "$module_seed" "$module_relative" "$module_destination" 0600 'installer module' || exit "$?"
  [ -s "$module_destination" ] && [ ! -L "$module_destination" ] || exit 1
  [ "$(installer_metadata_value "$module_destination" mode)" = 600 ] || exit 1
  printf '%s\n' "$module_destination"
)

# Data/parser assets use a separate resolver. They are authenticated payload
# members, never shell modules: callers may pass the returned path only to the
# parser named by the exact allow-list below. Keep this list narrow until a
# future asset has its own bounded grammar and manifest contract.
bootstrap_parser_asset_path() (
  set -eu
  umask 077
  [ "$#" -eq 1 ] || { bootstrap_log 'fatal: one parser asset path is required'; exit 1; }
  parser_relative=$1
  case "$parser_relative" in
    "${DIR_SCRIPTS_COMMON}/credential-data.awk") ;;
    *) bootstrap_log "fatal: unsupported parser asset path: $parser_relative"; exit 1 ;;
  esac
  bootstrap_load_source_library "${INSTALLER_SOURCE_ROOT:-}" || exit 1
  source_validate_relative "$parser_relative" || exit 1
  parser_seed=$(bootstrap_require_seed_base "") || exit 1
  if [ -n "${BOOTSTRAP_PREPARED_SOURCE_ROOT:-}" ] && [ "$parser_seed" = "$BOOTSTRAP_PREPARED_SEED_BASE" ]; then
    bootstrap_prepared_member_path "$parser_relative"
    exit 0
  fi
  [ -f "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}/bootstrap/payload.ready" ] || {
    bootstrap_log 'fatal: parser asset loading requires the authenticated payload'; exit 1;
  }
  parser_manifest=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}/bootstrap/payload.manifest
  [ -f "$parser_manifest" ] && [ ! -L "$parser_manifest" ] || {
    bootstrap_log 'fatal: authenticated payload manifest is unavailable for parser asset'; exit 1;
  }
  parser_record=$(awk -F '\t' -v wanted="$parser_relative" '
    NR == 1 { if ($0 != "format=3") exit 2; next }
    NF == 3 && $3 == wanted { if (++count != 1) exit 2; print $1 "\t" $2 }
    END { if (count != 1) exit 1 }
  ' "$parser_manifest") || {
    bootstrap_log 'fatal: parser asset is absent from the authenticated payload manifest'; exit 1;
  }
  parser_size=${parser_record%%	*}
  parser_digest=${parser_record#*	}
  case "$parser_size:$parser_digest" in
    ''|*[!0-9a-f:]*) bootstrap_log 'fatal: parser asset manifest record is malformed'; exit 1 ;;
  esac
  [ "$parser_size" -le 65536 ] && [ "${#parser_digest}" -eq 64 ] || {
    bootstrap_log 'fatal: parser asset exceeds its size or digest bound'; exit 1;
  }
  installer_lifecycle_paths || { bootstrap_log 'fatal: unsafe parser runtime directory'; exit 1; }
  parser_destination="${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}/bootstrap/data/$parser_relative"
  parser_parent=${parser_destination%/*}
  parser_probe=$parser_parent
  while [ "$parser_probe" != / ]; do
    [ ! -L "$parser_probe" ] || { bootstrap_log 'fatal: symlinked parser directory'; exit 1; }
    if [ -e "$parser_probe" ]; then
      [ -d "$parser_probe" ] || exit 1
      case "$parser_probe" in
        "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}"/*)
          [ "$(installer_metadata_value "$parser_probe" uid)" = "$(id -u)" ] || exit 1
          case "$(installer_metadata_value "$parser_probe" mode)" in
            700|500|750|550|755|555) ;;
            *) bootstrap_log 'fatal: writable or unsafe parser directory'; exit 1 ;;
          esac
          ;;
      esac
    fi
    parser_probe=${parser_probe%/*}; [ -n "$parser_probe" ] || parser_probe=/
  done
  if [ -e "$parser_destination" ] || [ -L "$parser_destination" ]; then
    [ -f "$parser_destination" ] && [ ! -L "$parser_destination" ] || exit 1
    [ "$(installer_metadata_value "$parser_destination" uid)" = "$(id -u)" ] || exit 1
    [ "$(installer_metadata_value "$parser_destination" links)" -eq 1 ] || exit 1
    [ "$(installer_metadata_value "$parser_destination" mode)" = 600 ] || exit 1
  fi
  mkdir -p "$parser_parent" || exit 1
  bootstrap_fetch_seed_file "$parser_seed" "$parser_relative" "$parser_destination" 0600 'parser asset' || exit "$?"
  [ -f "$parser_destination" ] && [ ! -L "$parser_destination" ] || exit 1
  [ "$(installer_metadata_value "$parser_destination" uid)" = "$(id -u)" ] || exit 1
  [ "$(installer_metadata_value "$parser_destination" links)" -eq 1 ] || exit 1
  [ "$(installer_metadata_value "$parser_destination" mode)" = 600 ] || exit 1
  [ "$(wc -c <"$parser_destination")" -eq "$parser_size" ] || exit 1
  parser_actual=$(source_hash <"$parser_destination") || exit 1
  [ "${parser_actual%% *}" = "$parser_digest" ] || {
    bootstrap_log 'fatal: parser asset digest differs from the authenticated manifest'; exit 1;
  }
  printf '%s\n' "$parser_destination"
)

bootstrap_source_module() {
  # Function positional parameters are local to this call in dash and ash.
  # Modules define functions/constants only. Phase actions run in the explicit
  # entrypoint, after every dependency has loaded successfully.
  case " ${BOOTSTRAP_SOURCED_MODULES:-} " in *" $1 "*) return 0 ;; esac
  bootstrap_module_source_path=$(bootstrap_module_path "$1") || return "$?"
  set -- "$1" "$bootstrap_module_source_path"
  unset bootstrap_module_source_path
  [ -n "$2" ] || return 1
  # shellcheck disable=SC1090
  . "$2" || return "$?"
  BOOTSTRAP_SOURCED_MODULES="${BOOTSTRAP_SOURCED_MODULES:+$BOOTSTRAP_SOURCED_MODULES }$1"
}

bootstrap_source_common_lib() {
  requested_seed_base=${1:-}
  common_lib_path=${2:-$(bootstrap_phase_runner_path common-lib.sh)} || return $?
  # bootstrap_module_path uses the authenticated lifecycle helpers for its
  # private staging checks. Load source.sh in this caller shell before the
  # first module is resolved; bootstrap_fetch_seed_file loads it in a
  # subshell and cannot provide those functions to common-lib.sh.
  bootstrap_load_source_library "${INSTALLER_SOURCE_ROOT:-}" || return $?
  seed_base=$(bootstrap_require_seed_base "$requested_seed_base") || return $?
  bootstrap_persist_seed_source "$seed_base" || return $?
  bootstrap_ensure_repo_env "$seed_base" || return $?

  common_lib_source=$(bootstrap_repo_file_value FILE_COMMON_LIB) || return $?
  if [ -n "${BOOTSTRAP_PREPARED_SOURCE_ROOT:-}" ] && [ "$seed_base" = "$BOOTSTRAP_PREPARED_SEED_BASE" ]; then
    common_lib_path=$(bootstrap_prepared_member_path "$common_lib_source") || return "$?"
  else
    bootstrap_fetch_seed_file "$seed_base" "$common_lib_source" "$common_lib_path" 0600 "common library" || return $?
  fi
  # shellcheck disable=SC1090,SC1091
  . "$common_lib_path" || return $?
}

bootstrap_source_common_support_libs() {
  requested_seed_base=${1:-}
  tmp_env_dir=$2
  shift 2

  seed_base=$(bootstrap_require_seed_base "$requested_seed_base") || return $?
  bootstrap_persist_seed_source "$seed_base" || return $?
  bootstrap_ensure_repo_env "$seed_base" || return $?
  install -d -m 0700 "$tmp_env_dir" || return $?

  for lib_name in "$@"; do
    case "$lib_name" in
      fetch)
        src=$(bootstrap_repo_file_value FILE_COMMON_FETCH) || return $?
        dest="${tmp_env_dir}/fetch.sh"
        ;;
      hook)
        src=$(bootstrap_repo_file_value FILE_COMMON_HOOK) || return $?
        dest="${tmp_env_dir}/hook.sh"
        ;;
      target)
        src=$(bootstrap_repo_file_value FILE_COMMON_TARGET) || return $?
        dest="${tmp_env_dir}/target-common.sh"
        ;;
      ssh)
        src=$(bootstrap_repo_file_value FILE_COMMON_SSH) || return $?
        dest="${tmp_env_dir}/ssh.sh"
        ;;
      *)
        bootstrap_fatal "unsupported installer support library: ${lib_name}"
        ;;
    esac
    if [ -n "${BOOTSTRAP_PREPARED_SOURCE_ROOT:-}" ] && [ "$seed_base" = "$BOOTSTRAP_PREPARED_SEED_BASE" ]; then
      dest=$BOOTSTRAP_PREPARED_SOURCE_ROOT/$src
    else
      bootstrap_fetch_seed_file "$seed_base" "$src" "$dest" 0600 "shared helper" || return $?
    fi
    # shellcheck disable=SC1090,SC1091
    . "$dest" || return $?
  done
}

bootstrap_run_preseed_phase() {
  phase=$1
  requested_seed_base=${2:-}
  seed_base=$(bootstrap_require_seed_base "$requested_seed_base") || return $?
  bootstrap_ensure_repo_env "$seed_base" || return $?

  case "$phase" in
    prepare-context|apply)
      runner_src=$(bootstrap_repo_file_value FILE_PRESEED_ANSWERS) || return $?
      runner=${3:-$(bootstrap_phase_runner_path preseed-answers.sh)} || return $?
      set -- "$phase" "$seed_base"
      ;;
    early)
      runner_src=$(bootstrap_repo_file_value FILE_EARLY_DISPATCH) || return $?
      runner=${3:-$(bootstrap_phase_runner_path early-dispatch.sh)} || return $?
      set -- "$seed_base"
      ;;
    partman)
      runner_src=$(bootstrap_repo_file_value FILE_PARTMAN_DISPATCH) || return $?
      runner=${3:-$(bootstrap_phase_runner_path partman-dispatch.sh)} || return $?
      set -- "$seed_base"
      ;;
    late)
      runner_src=$(bootstrap_repo_file_value FILE_LATE_DISPATCH) || return $?
      runner=${3:-$(bootstrap_phase_runner_path late-dispatch.sh)} || return $?
      set -- "$seed_base"
      ;;
    *)
      bootstrap_fatal "unsupported preseed phase: ${phase}"
      ;;
  esac

  bootstrap_persist_seed_source "$seed_base" || return $?
  bootstrap_fetch_seed_file "$seed_base" "$runner_src" "$runner" 0755 "phase runner" || return $?
  bootstrap_log "info: invoking preseed phase ${phase}"
  INSTALLER_BOOTSTRAP_LIB=${INSTALLER_BOOTSTRAP_LIB:-$(bootstrap_lib_path)} "$runner" "$@"
}

bootstrap_load_source_library() {
  command -v source_fetch >/dev/null 2>&1 && return 0
  bootstrap_source_scripts_dir=${DIR_REPO_SCRIPTS:-scripts}
  bootstrap_source_common_dir=${DIR_SCRIPTS_COMMON:-${bootstrap_source_scripts_dir}/common}
  for source_library in "${INSTALLER_SOURCE_LIBRARY:-}" \
      "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}/bootstrap/source.sh" \
      "${INSTALLER_SOURCE_ROOT:-/nonexistent}/${bootstrap_source_common_dir}/source.sh" \
      "${1:-/nonexistent}/${bootstrap_source_common_dir}/source.sh"; do
    [ -n "$source_library" ] && [ -s "$source_library" ] || continue
    # shellcheck disable=SC1090
    . "$source_library" || return $?
    command -v source_fetch >/dev/null 2>&1 || return 1
    return 0
  done
  bootstrap_fatal 'repository transport is missing; start with the generated preseed.cfg'
}

#!/bin/sh
# Run only in a reviewed disposable VM/image. Transport, logging and delegated
# helpers are fixtures; the path emitter, renderer, policy parser, plan hash,
# phase ownership and dispatcher are the real source under test.
set -eu
# Fixed packaged interpreter/tool directories inside the disposable image.
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
source_root=${1:?source snapshot required}
fixture_parent=${2:?private fixture parent required}
fixture_case=${3:?case required}
fixture_shell=${4:-/bin/sh}
case "$source_root:$fixture_parent" in
  *'/../'*|*'/./'*|*'//'*) exit 64 ;;
esac
case "$source_root" in /*) ;; *) exit 64 ;; esac
case "$fixture_parent" in /*) ;; *) exit 64 ;; esac
[ -d "$fixture_parent" ] && [ ! -L "$fixture_parent" ] || exit 64
work=$(mktemp -d "$fixture_parent/pre-pkgsel.XXXXXX")
mkdir -p "$work/runtime/bootstrap" "$work/runtime/state" "$work/policy"

cat >"$work/bootstrap.sh" <<'BOOTSTRAP'
bootstrap_source_common_lib() {
  . "$TEST_SOURCE/scripts/common/modules/files-logging.sh"
  . "$TEST_SOURCE/scripts/common/modules/profiles.sh"
  . "$TEST_SOURCE/scripts/common/modules/installation-plan.sh"
  . "$TEST_SOURCE/scripts/common/lifecycle.sh"
  installer_runtime_state_dir() { printf '%s/runtime/state\n' "$TEST_WORK"; }
  installer_runtime_log_file() { printf '%s/installer.log\n' "$TEST_WORK"; }
  installer_init_log_file() { :; }
  installer_finalize_log() { :; }
  installer_seed_base() { printf '%s\n' "$TEST_WORK"; }
  installer_ensure_context_loaded() { :; }
  installer_info() { printf '%s\n' "$*"; }
  installer_error() { printf '%s\n' "$*" >&2; }
  installer_fatal_status() { test_status=$1; shift; printf '%s\n' "$*" >&2; exit "$test_status"; }
  installer_fatal() { installer_fatal_status 1 "$@"; }
  installer_operation_context_repo() { :; }
  source_hash() { sha256sum; }
  bootstrap_repo_file_value() { printf '%s\n' "$TEST_SOURCE/scripts/common/credential-data.awk"; }
  bootstrap_parser_asset_path() { printf '%s\n' "$1"; }
  installer_repo_file_value() {
    case "$1" in
      FILE_FIXTURE_FIRST) printf '%s/first.sh\n' "$TEST_WORK" ;;
      FILE_FIXTURE_SECOND) printf '%s/second.sh\n' "$TEST_WORK" ;;
      *) return 2 ;;
    esac
  }
  installer_fetch_file() { cp "$2" "$3" && chmod "$4" "$3"; }
}
BOOTSTRAP

cat >"$work/first.sh" <<'FIRST'
#!/bin/sh
set -eu
printf 'first\n' >>"$TEST_WORK/launched"
[ "$TEST_CASE" != child-failure ] || exit 37
FIRST
cat >"$work/second.sh" <<'SECOND'
#!/bin/sh
set -eu
[ '__INSTALLER_PATH_DIR_ETC__' = /fixture-etc ]
printf 'second\n' >>"$TEST_WORK/launched"
SECOND
printf "DIR_ETC='/fixture-etc'\n" >"$work/policy/host.env"
plan="$work/runtime/state/installation-plan.tsv"
printf 'format\t1\nsuite\tforky\nrelease\tfixture\nstage\tinstaller.first|pre-pkgsel|FILE_FIXTURE_FIRST\nstage\tinstaller.second|pre-pkgsel|FILE_FIXTURE_SECOND\n' >"$plan"
plan_hash=$(sha256sum <"$plan")
printf '%s\n' "${plan_hash%% *}" >"${plan}.sha256"

case "$fixture_case" in
  map-empty|map-partial)
    cat >"$work/map.sh" <<'MAP'
set -eu
. "$TEST_SOURCE/scripts/common/modules/files-logging.sh"
case "$TEST_CASE" in
  map-empty)
    installer_runtime_path_placeholder_map >"$TEST_WORK/map"
    [ ! -s "$TEST_WORK/map" ]
    ;;
  map-partial)
    DIR_ETC=/fixture-etc
    installer_runtime_path_placeholder_map >"$TEST_WORK/map"
    grep -Fxq 'PATH_DIR_ETC=/fixture-etc' "$TEST_WORK/map"
    installer_apply_scalar_placeholders "$TEST_WORK/second.sh" "$TEST_WORK/rendered.sh"
    grep -Fq "'/fixture-etc'" "$TEST_WORK/rendered.sh"
    ;;
esac
MAP
    script="$work/map.sh"
    ;;
  dispatch|child-failure|unresolved|invalid-policy|changed-plan|completed)
    script="$source_root/hooks/installer/pre-pkgsel.d/50-class-plan.sh"
    case "$fixture_case" in
      unresolved) printf "DIR_ETC=''\n" >"$work/policy/host.env" ;;
      invalid-policy) printf "DIR_ETC='unterminated\n" >"$work/policy/host.env" ;;
      changed-plan) printf 'changed\n' >>"$plan" ;;
      completed)
        printf 'fixture\n' >"$work/runtime/state/phase-pre-pkgsel-installer.first.complete"
        printf 'fixture\n' >"$work/runtime/state/phase-pre-pkgsel-installer.second.complete"
        ;;
    esac
    ;;
  guard-locale)
    script="$source_root/scripts/preseed/guard-hook.sh"
    cat >"$work/runtime/bootstrap/source.sh" <<'LIFECYCLE'
. "$TEST_SOURCE/scripts/common/lifecycle.sh"
LC_STATE=$TEST_WORK/runtime/state
installer_lifecycle_begin() { :; }
installer_lifecycle_complete() { :; }
installer_lifecycle_abort() { exit "$1"; }
LIFECYCLE
    # Debian/FHS process search directories in this disposable guest only.
    cat >"$work/runtime/bootstrap/di.env" <<'DI_ENV'
DIR_INSTALLER_USR_LOCAL_SBIN=/usr/local/sbin
DIR_INSTALLER_USR_LOCAL_BIN=/usr/local/bin
DIR_INSTALLER_USR_SBIN=/usr/sbin
DIR_INSTALLER_USR_BIN=/usr/bin
DIR_INSTALLER_SBIN=/sbin
DIR_INSTALLER_BIN=/bin
DI_ENV
    printf 'INSTALLER_SUITE=forky\n' >"$work/runtime/state/context.env"
    cat >"$work/locale-child.sh" <<'LOCALE'
#!/bin/sh
set -eu
[ "$LANG:$LC_ALL:${IT_LANG_OVERRIDE:-}" = C:C:C ]
printf 'locale\n' >>"$TEST_WORK/launched"
LOCALE
    chmod 0755 "$work/locale-child.sh"
    ;;
  *) exit 64 ;;
esac

set --
if [ "$fixture_case" = guard-locale ]; then
  set -- hook-fixture-locale "$work/locale-child.sh"
fi
# Never inherit HOME, session buses, credentials, agents or a caller's PATH.
if env -i PATH="$PATH" LC_ALL=C LANG=C TEST_SOURCE="$source_root" TEST_WORK="$work" \
    TEST_CASE="$fixture_case" INSTALLER_RUNTIME_DIR="$work/runtime" \
    INSTALLER_BOOTSTRAP_LIB="$work/bootstrap.sh" DIR_INSTALLER_ENV="$work/policy" \
    INSTALLER_SUITE=forky INSTALLER_RELEASE_ID=fixture \
    "$fixture_shell" -eu "$script" "$@" >"$work/stdout" 2>"$work/stderr"; then
  status=0
else
  status=$?
fi

case "$fixture_case" in
  map-empty|map-partial) [ "$status" -eq 0 ] ;;
  dispatch)
    [ "$status" -eq 0 ]
    [ "$(cat "$work/launched")" = "$(printf 'first\nsecond')" ]
    [ -f "$work/runtime/state/phase-pre-pkgsel-installer.first.complete" ]
    [ -f "$work/runtime/state/phase-pre-pkgsel-installer.second.complete" ]
    ;;
  child-failure)
    [ "$status" -eq 37 ]
    [ "$(cat "$work/launched")" = first ]
    [ -f "$work/runtime/state/phase-pre-pkgsel-installer.first.running" ]
    [ ! -e "$work/runtime/state/phase-pre-pkgsel-installer.first.complete" ]
    grep -Fq 'installer.first failed (FILE_FIXTURE_FIRST)' "$work/stderr"
    ;;
  unresolved)
    [ "$status" -eq 1 ]
    [ "$(cat "$work/launched")" = first ]
    [ -f "$work/runtime/state/phase-pre-pkgsel-installer.second.running" ]
    [ ! -e "$work/runtime/state/phase-pre-pkgsel-installer.second.complete" ]
    grep -Fq 'unresolved installer path placeholders' "$work/stderr"
    ;;
  invalid-policy)
    [ "$status" -eq 2 ]
    [ ! -e "$work/launched" ]
    grep -Fq 'host policy could not be loaded' "$work/stderr"
    ;;
  changed-plan)
    [ "$status" -eq 1 ]
    [ ! -e "$work/launched" ]
    grep -Fq 'immutable installation plan changed' "$work/stderr"
    ;;
  completed)
    [ "$status" -eq 0 ]
    [ ! -e "$work/launched" ]
    ;;
  guard-locale)
    [ "$status" -eq 0 ]
    [ "$(cat "$work/launched")" = locale ]
    ;;
esac
printf 'PASS case=%s shell=%s status=%s evidence=%s\n' "$fixture_case" "$fixture_shell" "$status" "$work"

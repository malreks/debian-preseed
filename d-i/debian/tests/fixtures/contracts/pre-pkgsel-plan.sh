#!/bin/sh
# Run only in a reviewed disposable VM/image. Transport, logging and delegated
# helpers are fixtures; the path emitter, policy parser, record validation,
# phase ownership and dispatcher are the real source under test.
set -eu
# Fixed packaged interpreter/tool directories inside the disposable image.
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
source_root=${1:?source snapshot required}
fixture_parent=${2:?private fixture parent required}
fixture_case=${3:?case required}
fixture_shell=${4:-/bin/sh}
case "$fixture_shell" in /bin/sh|/bin/dash|/bin/busybox) ;; *) exit 64 ;; esac
case "$source_root:$fixture_parent" in
  *'/../'*|*'/./'*|*'//'*) exit 64 ;;
esac
case "$source_root" in /*) ;; *) exit 64 ;; esac
case "$fixture_parent" in /*) ;; *) exit 64 ;; esac
[ -d "$source_root" ] && [ ! -L "$source_root" ] || exit 64
[ -d "$fixture_parent" ] && [ ! -L "$fixture_parent" ] || exit 64
umask 077
work=$(mktemp -d "$fixture_parent/pre-pkgsel.XXXXXX")
mkdir -p "$work/runtime/bootstrap" "$work/runtime/state" "$work/policy" \
  "$work/prepared/hooks/installer/pre-pkgsel.d"
fixture_report_failure() {
  fixture_status=$?
  if [ "$fixture_status" -ne 0 ]; then
    printf 'FAIL case=%s evidence=%s\n' "$fixture_case" "$work" >&2
    if [ -f "$work/stderr" ]; then tail -n 20 "$work/stderr" >&2; fi
  fi
}
trap 'fixture_report_failure' 0

cat >"$work/bootstrap.sh" <<'BOOTSTRAP'
bootstrap_source_common_lib() {
  . "$TEST_SOURCE/scripts/common/modules/files-logging.sh"
  . "$TEST_SOURCE/scripts/common/modules/profiles.sh"
  . "$TEST_SOURCE/scripts/common/modules/installation-plan.sh"
  . "$TEST_SOURCE/scripts/common/modules/repository-apt.sh"
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
  source_state_key() { sha256sum; }
  bootstrap_repo_file_value() { printf '%s\n' "$TEST_SOURCE/scripts/common/credential-data.awk"; }
  bootstrap_parser_asset_path() { printf '%s\n' "$1"; }
  installer_fetch_file() {
    case "$2" in
      hooks/installer/pre-pkgsel.d/first.sh|hooks/installer/pre-pkgsel.d/second.sh) ;;
      *) installer_fatal_status 42 'unexpected fixture source' ;;
    esac
    case "$3" in "$TEST_WORK"/runtime/bootstrap/*.sh) ;; *) exit 64 ;; esac
    [ ! -L "$3" ] || exit 64
    [ "$TEST_CASE" != fetch-failure ] || installer_fatal_status 41 'fixture transfer failed'
    cp "$TEST_WORK/prepared/$2" "$3" && chmod "$4" "$3"
  }
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
[ "$DIR_ETC" = /fixture-etc ]
printf 'second\n' >>"$TEST_WORK/launched"
[ "$TEST_CASE" != second-failure ] || exit 38
SECOND
# These are the already rendered providers, as published by base-stage.
cp "$work/first.sh" "$work/prepared/hooks/installer/pre-pkgsel.d/first.sh"
cp "$work/second.sh" "$work/prepared/hooks/installer/pre-pkgsel.d/second.sh"
# The policy parser restores shell values; a child receives exported fixture
# policy just as the real common loader exports the rendered runtime contract.
DIR_ETC=/fixture-etc
export DIR_ETC
printf "DIR_ETC='/fixture-etc'\n" >"$work/policy/host.env"
plan="$work/runtime/state/installation-plan.tsv"
printf 'format\t2\nsuite\tforky\nrelease\tfixture\nstage\tinstaller.first|pre-pkgsel|hooks/installer/pre-pkgsel.d/first.sh\nstage\tinstaller.second|pre-pkgsel|hooks/installer/pre-pkgsel.d/second.sh\nstage\tdesktop.fixture|late|scripts/late/fixture.sh.tmpl\n' >"$plan"
printf 'ready\n' >"${plan}.ready"

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
    printf "'__INSTALLER_PATH_DIR_ETC__'\n" >"$TEST_WORK/second.sh"
    installer_apply_scalar_placeholders "$TEST_WORK/second.sh" "$TEST_WORK/rendered.sh"
    grep -Fq "'/fixture-etc'" "$TEST_WORK/rendered.sh"
    ;;
esac
MAP
    script="$work/map.sh"
    ;;
  dispatch|child-failure|second-failure|fetch-failure|unresolved|invalid-policy|changed-plan|completed|interrupted|wrong-stamp|symlink-stamp|missing-ready|unprepared|invalid-*)
    script="$source_root/hooks/installer/pre-pkgsel.d/50-class-plan.sh"
    case "$fixture_case" in
      unresolved) printf 'stage\tinstaller.unresolved|pre-pkgsel|__INSTALLER_PATH_DIR_ETC__/child.sh\n' >>"$plan" ;;
      invalid-policy) printf "DIR_ETC='unterminated\n" >"$work/policy/host.env" ;;
      changed-plan) sed 's/release.fixture/release\tchanged/' "$plan" >"$work/changed"; mv "$work/changed" "$plan" ;;
      missing-ready) rm "${plan}.ready" ;;
      unprepared) ;;
      interrupted) printf 'fixture\n' >"$work/runtime/state/phase-pre-pkgsel-installer.first.running" ;;
      wrong-stamp) printf 'other-release\n' >"$work/runtime/state/phase-pre-pkgsel-installer.first.complete" ;;
      symlink-stamp) ln -s "$plan" "$work/runtime/state/phase-pre-pkgsel-installer.first.complete" ;;
      invalid-id) printf 'stage\tinstaller/invalid|pre-pkgsel|hooks/installer/pre-pkgsel.d/third.sh\n' >>"$plan" ;;
      invalid-phase) printf 'stage\tinstaller.invalid|unknown|hooks/installer/pre-pkgsel.d/third.sh\n' >>"$plan" ;;
      invalid-path) printf 'stage\tinstaller.invalid|pre-pkgsel|/absolute.sh\n' >>"$plan" ;;
      invalid-traversal) printf 'stage\tinstaller.invalid|pre-pkgsel|hooks/../escape.sh\n' >>"$plan" ;;
      invalid-dot) printf 'stage\tinstaller.invalid|pre-pkgsel|hooks/./escape.sh\n' >>"$plan" ;;
      invalid-empty-component) printf 'stage\tinstaller.invalid|pre-pkgsel|hooks//escape.sh\n' >>"$plan" ;;
      invalid-trailing-slash) printf 'stage\tinstaller.invalid|pre-pkgsel|hooks/escape.sh/\n' >>"$plan" ;;
      invalid-empty-path) printf 'stage\tinstaller.invalid|pre-pkgsel|\n' >>"$plan" ;;
      invalid-field) printf 'stage\tinstaller.invalid|pre-pkgsel|hooks/third.sh|extra\n' >>"$plan" ;;
      invalid-column) printf 'stage\tinstaller.invalid|pre-pkgsel|hooks/third.sh\textra\n' >>"$plan" ;;
      invalid-duplicate-id) printf 'stage\tinstaller.first|pre-pkgsel|hooks/third.sh\n' >>"$plan" ;;
      invalid-duplicate-provider) printf 'stage\tinstaller.third|pre-pkgsel|hooks/installer/pre-pkgsel.d/first.sh\n' >>"$plan" ;;
      invalid-late-path) printf 'stage\tinstaller.invalid|late|../escape.sh\n' >>"$plan" ;;
      completed)
        printf 'fixture\n' >"$work/runtime/state/phase-pre-pkgsel-installer.first.complete"
        printf 'fixture\n' >"$work/runtime/state/phase-pre-pkgsel-installer.second.complete"
        ;;
    esac
    ;;
  records)
    script="$work/records.sh"
    cat >"$script" <<'RECORDS'
. "$TEST_WORK/bootstrap.sh"
bootstrap_source_common_lib
installer_plan_stage_records pre-pkgsel >"$TEST_WORK/pre-pkgsel.records"
installer_plan_stage_records late >"$TEST_WORK/late.records"
[ "$(wc -l <"$TEST_WORK/pre-pkgsel.records")" -eq 2 ]
grep -Fxq 'desktop.fixture|late|scripts/late/fixture.sh.tmpl' "$TEST_WORK/late.records"
if installer_plan_stage_records unknown; then exit 90; fi
RECORDS
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
prepared=$work/prepared
[ "$fixture_case" != unprepared ] || prepared=
case "$fixture_shell" in
  /bin/busybox) set -- ash -eu "$script" "$@" ;;
  *) set -- -eu "$script" "$@" ;;
esac
# Never inherit HOME, session buses, credentials, agents or a caller's PATH.
if env -i PATH="$PATH" LC_ALL=C LANG=C TEST_SOURCE="$source_root" TEST_WORK="$work" \
    TEST_CASE="$fixture_case" INSTALLER_RUNTIME_DIR="$work/runtime" \
    TMPDIR="$work" TMP="$work" TEMP="$work" HOME="$work" \
    DIR_ETC="$DIR_ETC" DIR_INSTALLER_RUNTIME="$work/runtime" \
    BOOTSTRAP_PREPARED_SOURCE_ROOT="$prepared" \
    INSTALLER_BOOTSTRAP_LIB="$work/bootstrap.sh" DIR_INSTALLER_ENV="$work/policy" \
    INSTALLER_SUITE=forky INSTALLER_RELEASE_ID=fixture \
    "$fixture_shell" "$@" >"$work/stdout" 2>"$work/stderr"; then
  status=0
else
  status=$?
fi

case "$fixture_case" in
  map-empty|map-partial|records) [ "$status" -eq 0 ] ;;
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
    grep -Fq 'installer.first failed (hooks/installer/pre-pkgsel.d/first.sh)' "$work/stderr"
    ;;
  second-failure)
    [ "$status" -eq 38 ]
    [ "$(cat "$work/launched")" = "$(printf 'first\nsecond')" ]
    [ -f "$work/runtime/state/phase-pre-pkgsel-installer.first.complete" ]
    [ -f "$work/runtime/state/phase-pre-pkgsel-installer.second.running" ]
    [ ! -e "$work/runtime/state/phase-pre-pkgsel-installer.second.complete" ]
    grep -Fq 'installer.second failed (hooks/installer/pre-pkgsel.d/second.sh)' "$work/stderr"
    ;;
  invalid-policy)
    [ "$status" -eq 2 ]
    [ ! -e "$work/launched" ]
    grep -Fq 'host policy could not be loaded' "$work/stderr"
    ;;
  changed-plan)
    [ "$status" -eq 1 ]
    [ ! -e "$work/launched" ]
    grep -Fq 'installation plan/release mismatch' "$work/stderr"
    ;;
  completed)
    [ "$status" -eq 0 ]
    [ ! -e "$work/launched" ]
    ;;
  fetch-failure)
    [ "$status" -eq 41 ]
    [ ! -e "$work/launched" ]
    [ -f "$work/runtime/state/phase-pre-pkgsel-installer.first.running" ]
    [ ! -e "$work/runtime/state/phase-pre-pkgsel-installer.first.complete" ]
    ;;
  interrupted|wrong-stamp|symlink-stamp|missing-ready|unprepared|invalid-*|unresolved)
    [ "$status" -eq 1 ]
    [ ! -e "$work/launched" ]
    case "$fixture_case" in
      interrupted) grep -Fq 'phase outcome is uncertain; retained evidence:' "$work/stderr" ;;
      wrong-stamp) grep -Fq 'phase stamp release differs' "$work/stderr" ;;
      symlink-stamp) grep -Fq 'phase completion stamp has an invalid identity' "$work/stderr" ;;
      missing-ready) grep -Fq 'validated installation plan is unavailable' "$work/stderr" ;;
      unprepared) grep -Fq 'pre-pkgsel requires the target payload prepared' "$work/stderr" ;;
      *)
        grep -Fq 'invalid pre-pkgsel stage record' "$work/stderr"
        [ ! -e "$work/runtime/state/phase-pre-pkgsel-installer.first.running" ]
        ;;
    esac
    ;;
  guard-locale)
    [ "$status" -eq 0 ]
    [ "$(cat "$work/launched")" = locale ]
    ;;
esac
printf 'PASS case=%s shell=%s status=%s evidence=%s\n' "$fixture_case" "$fixture_shell" "$status" "$work"

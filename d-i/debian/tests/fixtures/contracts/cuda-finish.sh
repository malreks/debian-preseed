#!/bin/sh
# Execute only inside a reviewed disposable image. The source retirement,
# metadata checks, late handoff and finish hooks are real; bootstrap/profile
# loading, target APT and unrelated final policy publication are fixtures.
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
source_root=${1:?source snapshot required}
fixture_parent=${2:?private fixture parent required}
fixture_case=${3:?case required}
fixture_shell=${4:-/bin/sh}
fixture_suite=${5:-forky}
case "$fixture_shell" in /bin/sh|/bin/dash|/bin/busybox) ;; *) exit 64 ;; esac
case "$fixture_suite" in forky|trixie) ;; *) exit 64 ;; esac
case "$source_root:$fixture_parent" in *[!A-Za-z0-9_./:-]*|*'/../'*|*'/./'*|*'//'*) exit 64 ;; esac
case "$source_root" in /*) ;; *) exit 64 ;; esac
case "$fixture_parent" in /|''|/tmp|/var/tmp|/dev/shm) exit 64 ;; /*) ;; *) exit 64 ;; esac
[ -d "$source_root" ] && [ ! -L "$source_root" ] || exit 64
[ -d "$fixture_parent" ] && [ ! -L "$fixture_parent" ] || exit 64
umask 077
work=$(mktemp -d "$fixture_parent/cuda-finish.XXXXXX")
fixture_report_failure() {
  fixture_status=$?
  if [ "$fixture_status" -ne 0 ]; then
    printf 'FAIL case=%s status=%s evidence=%s\n' "$fixture_case" "$fixture_status" "$work" >&2
    [ ! -f "$work/stderr" ] || tail -n 12 "$work/stderr" >&2
  fi
}
trap fixture_report_failure 0
target="$work/target"
parts="$target/etc/apt/sources.list.d"
source="$target/etc/apt/sources.list"
repo=https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/
mkdir -p "$parts" "$work/runtime/bootstrap" "$work/runtime/state" "$work/policy" "$work/bin" "$work/tmp" "$work/home"
printf 'deb https://deb.debian.org/debian %s main\n' "$fixture_suite" >"$work/unrelated"
cat "$work/unrelated" >"$source"
printf 'deb [trusted=yes] %s /\n' "$repo" >>"$source"
chmod 0640 "$source"
cat >"$work/policy/host.env" <<EOF
INSTALLER_TARGET_DIR='$target'
DIR_APT='/etc/apt'
DIR_APT_SOURCES_LIST_D='/etc/apt/sources.list.d'
DIR_VAR='/var'
DIR_VAR_CACHE='/var/cache'
DIR_TMP='/tmp'
FILE_INSTALLER_APT_NORMALIZE_SOURCES='/usr/local/libexec/apt-repo-local-normalize-sources'
CUDA_LEGACY_REPOSITORY_URL='$repo'
EOF
printf "INSTALLER_SUITE='%s'\n" "$fixture_suite" >"$work/runtime/state/context.env"
cat >"$work/runtime/bootstrap/common-lib.sh" <<'BOOTSTRAP'
. "$TEST_SOURCE/scripts/common/lifecycle.sh"
. "$TEST_SOURCE/scripts/common/apt-sources.sh"
. "$TEST_SOURCE/scripts/common/modules/context-target.sh"
DIR_INSTALLER_ENV="$TEST_WORK/policy"
installer_operation_context_repo() { :; }
installer_load_data_env() { . "$1"; }
installer_runtime_log_file() { printf '%s/finish.log\n' "$TEST_WORK"; }
installer_runtime_dir() { printf '%s/runtime\n' "$TEST_WORK"; }
installer_info() { printf '%s\n' "$*"; }
installer_error() { printf '%s\n' "$*" >&2; }
installer_fatal() { installer_error "$*"; exit 1; }
installer_fatal_status() { code=$1; shift; installer_error "$*"; exit "$code"; }
installer_apt_install_target_policy() { :; }
installer_apt_dedupe_source_list() { :; }
if [ "${TEST_CASE:-}" = early-failure ]; then
  mv() { return 73; }
fi
BOOTSTRAP
cat >"$work/bin/in-target" <<'TARGET'
#!/bin/sh
set -eu
# Observe the entry state of each normalizer/modernize call, with no APT or
# services executed by this fixture.
! grep -Fq 'debian12/x86_64/' "$INSTALLER_TARGET_DIR/etc/apt/sources.list" || exit 81
printf '%s\n' "$*" >>"$TEST_WORK/target-calls"
TARGET
chmod 0755 "$work/bin/in-target"
cat >"$work/action.sh" <<'ACTION'
set -eu
. "$TEST_WORK/runtime/bootstrap/common-lib.sh"
if [ "$TEST_CASE" != missing-policy ]; then . "$TEST_WORK/policy/host.env"; fi
case "$TEST_CASE" in
  driver-only|toolkit|unselected)
    installer_cuda_legacy_selected() { [ "$TEST_CASE" = toolkit ]; }
    installer_nvidia_legacy_selected() { [ "$TEST_CASE" != unselected ]; }
    . "$TEST_SOURCE/scripts/late/storage-maintenance.sh"
    finish_target_pkgsel_apt_state
    ;;
  early-hook|early-failure|missing-policy)
    # Source the unchanged hook in the requested d-i shell dialect.
    . "$TEST_SOURCE/hooks/installer/finish-install.d/09-cuda-legacy-cleanup"
    ;;
  late-normalizer)
    . "$TEST_SOURCE/hooks/installer/finish-install.d/95-normalize-apt"
    ;;
  publish-failure)
    mv() { return 73; }
    if installer_cuda_remove_target_source; then exit 91; else exit "$?"; fi
    ;;
  cleanup-failure)
    rm() { return 74; }
    if installer_cuda_remove_target_source; then exit 91; else exit "$?"; fi
    ;;
  filter-io-failure)
    awk() {
      case "${1:-}:${2:-}" in
        -v:origin=*) command awk "$@" "$TEST_WORK/missing-apt-input" ;;
        *) command awk "$@" ;;
      esac
    }
    if installer_cuda_remove_target_source; then exit 91; else exit "$?"; fi
    ;;
  *) installer_cuda_remove_target_source ;;
esac
ACTION
expected=0
case "$fixture_case" in
  sources)
    # Keep the modern archive and similarly named paths. Match exact origins,
    # including old HTTP spellings, rather than deleting NVIDIA wholesale.
    printf 'deb https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64/ /\n' >>"$source"
    printf 'deb %sextra /\n' "$repo" >>"$source"
    printf 'deb http://%s /\n' "${repo#https://}" >>"$source"
    cp "$source" "$source.installer-disabled"
    cp "$source" "$parts/local.list.save"
    printf 'deb %s /\n' "$repo" >"$parts/cuda-legacy-temp.list"
    cat >"$parts/local.sources" <<EOF
Types: deb
URIs: $repo
Suites: /

Types: deb
URIs: https://deb.debian.org/debian
Suites: forky
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: https://other.example.invalid/archive
# A comment may occur between continuation lines of the URI field.
 $repo
Suites: /
Enabled: no
EOF
    cp "$parts/local.sources" "$parts/local.sources.bak"
    cp "$parts/local.sources" "$parts/mixed.list.sources"
    cp "$source" "$parts/mixed.sources.list"
    awk '{ printf "%s\r\n", $0 }' "$parts/local.sources" >"$parts/crlf.sources"
    awk '/^$/ { print " \t"; next } { print }' "$parts/local.sources" >"$parts/spaced.sources"
    cp "$work/unrelated" "$parts/unrelated.list"
    ;;
  missing) rm -f "$source" ;;
  driver-only|toolkit|unselected|early-hook) ;;
  late-normalizer) printf 'deb cdrom:[fixture] /\n' >>"$source" ;;
  early-failure) expected=73; cp "$source" "$work/original" ;;
  missing-policy) expected=1; cp "$source" "$work/original"; rm -f "$work/policy/host.env" ;;
  publish-failure) expected=73; cp "$source" "$work/original" ;;
  cleanup-failure)
    expected=74
    printf 'deb %sextra /\n' "$repo" >"$source"
    cp "$source" "$work/original"
    ;;
  filter-io-failure)
    # With no matching URI, an END exit used as a change flag could mask the
    # real read error. Compare against this image awk's native I/O status.
    printf 'deb %sextra /\n' "$repo" >"$source"
    cp "$source" "$work/original"
    if awk '{ next }' "$work/missing-apt-input" >"$work/io.stdout" 2>"$work/io.stderr"; then
      exit 1
    else
      expected=$?
    fi
    ;;
  symlink)
    expected=1; mv "$source" "$work/foreign"; cp "$work/foreign" "$work/original"
    ln -s "$work/foreign" "$source"
    ;;
  hardlink)
    expected=1; cp "$source" "$work/original"; ln "$source" "$work/foreign"
    ;;
  parts-symlink)
    expected=1; cp "$source" "$work/original"
    rmdir "$parts"; mkdir "$work/foreign-parts"; ln -s "$work/foreign-parts" "$parts"
    ;;
  *) exit 64 ;;
esac
if [ "$fixture_shell" = /bin/busybox ]; then
  set -- "$fixture_shell" sh
else
  set -- "$fixture_shell"
fi
status=0
env -i PATH="$work/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  HOME="$work/home" TMPDIR="$work/tmp" TMP="$work/tmp" TEMP="$work/tmp" \
  LANG=C LC_ALL=C TEST_SOURCE="$source_root" TEST_WORK="$work" TEST_CASE="$fixture_case" \
  INSTALLER_RUNTIME_DIR="$work/runtime" INSTALLER_TARGET_DIR="$target" \
  INSTALLER_ASSUME_TARGET_MOUNTED=1 \
  "$@" -eu "$work/action.sh" >"$work/stdout" 2>"$work/stderr" || status=$?
if [ "$status" -ne "$expected" ]; then
  cat "$work/stdout" "$work/stderr" >&2
  [ ! -f "$work/finish.log" ] || cat "$work/finish.log" >&2
  printf 'FAIL case=%s status=%s expected=%s evidence=%s\n' "$fixture_case" "$status" "$expected" "$work" >&2
  exit 1
fi
if [ "$expected" -ne 0 ]; then
  case "$fixture_case" in
    symlink|hardlink) actual="$work/foreign" ;;
    *) actual="$source" ;;
  esac
  [ "$(cat "$actual")" = "$(cat "$work/original")" ] || exit 1
  if [ "$fixture_case" = cleanup-failure ]; then
    set -- "$target/etc/apt/".cuda-retire.*
    [ "$#" -eq 1 ] && [ -f "$1" ] || exit 1
  fi
elif [ "$fixture_case" = sources ]; then
  for file in "$source" "$source.installer-disabled" "$parts/local.list.save" "$parts/mixed.sources.list"; do
    [ "$(wc -l <"$file")" -eq 3 ] || exit 1
    grep -Fxq "deb ${repo}extra /" "$file" || exit 1
    grep -Fq 'debian13/x86_64/' "$file" || exit 1
  done
  [ ! -s "$parts/cuda-legacy-temp.list" ] || exit 1
  for file in "$parts/local.sources" "$parts/local.sources.bak" "$parts/mixed.list.sources" "$parts/crlf.sources" "$parts/spaced.sources"; do
    ! grep -Fq "$repo" "$file" || exit 1
    grep -Fxq 'URIs: https://other.example.invalid/archive' "$file" || exit 1
    grep -Fxq 'Components: main' "$file" || exit 1
    grep -Fxq 'Enabled: no' "$file" || exit 1
    [ "$(grep -c '^Types:' "$file")" -eq 2 ] || exit 1
    [ "$(grep -c '^URIs:' "$file")" -eq 2 ] || exit 1
  done
  [ "$(cat "$parts/unrelated.list")" = "$(cat "$work/unrelated")" ] || exit 1
elif [ "$fixture_case" = missing ]; then
  [ ! -e "$source" ] || exit 1
else
  [ "$(cat "$source")" = "$(cat "$work/unrelated")" ] || exit 1
fi
if [ "$fixture_case" = late-normalizer ]; then
  [ "$(wc -l <"$work/target-calls")" -eq 3 ] || exit 1
fi
if [ "$expected" -eq 0 ]; then
  # A repeat pass must not recreate a source or change the installed entries.
  env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin HOME="$work/home" \
    TMPDIR="$work/tmp" TMP="$work/tmp" TEMP="$work/tmp" LANG=C LC_ALL=C \
    TEST_SOURCE="$source_root" TEST_WORK="$work" INSTALLER_TARGET_DIR="$target" \
    /bin/sh -eu -c '. "$TEST_WORK/runtime/bootstrap/common-lib.sh"; . "$TEST_WORK/policy/host.env"; installer_cuda_remove_target_source'
  if [ "$fixture_case" != missing ]; then
    mode=$(env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin TEST_SOURCE="$source_root" \
      /bin/sh -eu -c '. "$TEST_SOURCE/scripts/common/lifecycle.sh"; installer_metadata_value "$1" mode' sh "$source")
    case "$fixture_case:$mode" in late-normalizer:600|*:640) ;; *) exit 1 ;; esac
  fi
fi
printf 'CUDA_FINISH_PASS case=%s shell=%s suite=%s\n' "$fixture_case" "$fixture_shell" "$fixture_suite"

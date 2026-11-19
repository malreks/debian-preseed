#!/bin/sh
# Native contract fixture: execute only in a reviewed disposable Debian image.
# Bootstrap, restricted policy loading, normalization, APT source retirement,
# ownership scanning and readiness publication are real. Target APT and the
# chroot boot/package audit are explicit stubs; no installed system is tested.
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
source_root=${1:?authenticated source snapshot required}
fixture_parent=${2:?private fixture parent required}
fixture_case=${3:?case required}
fixture_shell=${4:?shell required}
fixture_suite=${5:?suite required}
fixture_profile=${6:-desktop/btrfs-de-p15s}
[ -f /snapshot/finish-environment-image ] || exit 64
case "$fixture_shell" in /bin/dash|/bin/busybox) ;; *) exit 64 ;; esac
case "$fixture_suite" in forky|trixie) ;; *) exit 64 ;; esac
case "$source_root:$fixture_parent:$fixture_profile" in
  *[!A-Za-z0-9_./:-]*|*'/../'*|*'/./'*|*'//'*) exit 64 ;;
esac
case "$source_root" in /*) ;; *) exit 64 ;; esac
case "$fixture_parent" in /cases/*) ;; *) exit 64 ;; esac
case "$fixture_profile" in desktop/*|server/*) ;; *) exit 64 ;; esac
[ -d "$source_root" ] && [ ! -L "$source_root" ] || exit 64
[ -d "$fixture_parent" ] && [ ! -L "$fixture_parent" ] || exit 64
umask 077
work=$(mktemp -d "$fixture_parent/finish-environment.XXXXXX")
# Debian's validated di.env fixes the mounted target interface at /target.
# This mount exists only in the disposable guest and is owned by this case.
target=/target
runtime=$work/runtime
policy=$work/policy
mounted=0
finish_fixture() {
  fixture_status=$?
  trap - 0
  if [ "$fixture_status" -ne 0 ]; then
    printf 'FAIL case=%s status=%s evidence=%s\n' "$fixture_case" "$fixture_status" "$work" >&2
    for file in "$work/stderr" "$work/installer.log"; do
      [ ! -f "$file" ] || tail -n 18 "$file" >&2
    done
  fi
  if [ "$mounted" -eq 1 ]; then
    umount "$target" || { printf 'fixture target cleanup failed: %s\n' "$target" >&2; exit 125; }
  fi
  exit "$fixture_status"
}
trap finish_fixture 0
mkdir -p "$target" "$runtime/bootstrap" "$runtime/cache/seed/scripts" \
  "$runtime/state/target-assets" "$policy" "$work/bin" "$work/tmp" "$work/home"
while read -r _source point _rest; do
  [ "$point" != "$target" ] || exit 64
done </proc/mounts
mount -t tmpfs -o size=16m,nodev,nosuid,mode=0755 tmpfs "$target"
mounted=1
cp -R "$source_root/scripts/common" "$runtime/cache/seed/scripts/"
cp -R "$source_root/frontends" "$runtime/cache/seed/"
cp "$source_root/scripts/common/lib.sh" "$runtime/bootstrap/common-lib.sh"
cp "$source_root/scripts/common/bootstrap.sh" "$runtime/bootstrap/bootstrap.sh"
cp "$source_root/scripts/common/source.sh" "$runtime/bootstrap/source.sh"
cp "$source_root/repo.env" "$runtime/bootstrap/repo.env"
cp /snapshot/payload.manifest "$runtime/bootstrap/payload.manifest"
cp /snapshot/payload.identity "$runtime/bootstrap/payload.ready"
printf '%s\n' "$source_root" >"$runtime/bootstrap/seed.file"
# Relocate only the fixture's installer-owned destinations, using data from
# the actual di.env. Target policy is the unchanged compiled payload member.
sed -e "s|^DIR_INSTALLER_RUNTIME=.*|DIR_INSTALLER_RUNTIME=\"$runtime\"|" \
  -e "s|^DIR_INSTALLER_ENV=.*|DIR_INSTALLER_ENV=\"$policy\"|" \
  -e "s|^FILE_INSTALLER_LOG=.*|FILE_INSTALLER_LOG=\"$work/installer.log\"|" \
  "$source_root/hooks/installer/di.env" >"$runtime/bootstrap/di.env"
cp "$source_root/catalog/compiled/$fixture_suite/profiles/$fixture_profile.env" "$policy/host.env"
printf "ACCOUNT_USERNAME='fixture'\nACCOUNT_HOME='/home/fixture'\n" >"$policy/account.env"
# Layout state intentionally has no DIR_* values and cannot supply target roots.
secure_boot_mode=$(sed -n "s/^SECURE_BOOT_STATE_MODE='\([^']*\)'$/\1/p" "$policy/host.env")
case "$secure_boot_mode" in direct|luks) ;; *) exit 64 ;; esac
printf "SECURE_BOOT_MODE='%s'\n" "$secure_boot_mode" >"$policy/runtime.env"
printf "INSTALLER_SUITE='%s'\nINSTALLER_HOST_VARIANT='%s'\n" \
  "$fixture_suite" "${fixture_profile%%/*}" >"$runtime/state/context.env"
cp "$source_root/catalog/placeholder-registry.tsv" "$runtime/bootstrap/placeholder-registry.tsv"
cp "$source_root/scripts/common/target-owned-scan.awk" "$runtime/bootstrap/target-owned-scan.awk"
chmod 0600 "$runtime/bootstrap/"* "$policy/"*
: >"$runtime/state/late.done"
mkdir -p "$target/etc/apt/sources.list.d" "$target/var/spool/rsyslog" \
  "$target/home/fixture/.config" "$target/tmp" "$target/var/tmp" "$target/usr/local/share"
printf 'fixture:x:1000:1000:Fixture:/home/fixture:/bin/sh\n' >"$target/etc/passwd"
printf 'preserve account data\n' >"$target/home/fixture/.config/settings"
chmod 0755 "$target/home/fixture" "$target/home/fixture/.config"
chmod 0644 "$target/home/fixture/.config/settings"
chown 1000:1000 "$target/home/fixture" "$target/home/fixture/.config" \
  "$target/home/fixture/.config/settings"
printf 'owned fixture asset\n' >"$target/usr/local/share/fixture.txt"
chmod 0644 "$target/usr/local/share/fixture.txt"
printf '/usr/local/share/fixture.txt\tgenerated\tasset\tlate-command\t0644\n' >"$runtime/state/target-assets/journal.tsv"
case "$fixture_case" in
  chain-app-veth|baseline-app-veth|reject-app-veth-marker)
    cp /snapshot/rendered-app-veth.nft "$target/etc/app-veth.nft"
    chmod 0644 "$target/etc/app-veth.nft"
    printf '/etc/app-veth.nft\thooks/target/etc/app-veth.nft.tmpl\ttemplate\tlate\t0644\n' \
      >>"$runtime/state/target-assets/journal.tsv"
    ;;
esac
printf 'stale tmp content\n' >"$target/tmp/stale"
printf 'stale var tmp content\n' >"$target/var/tmp/stale"
printf 'deb https://deb.debian.org/debian %s main\n' "$fixture_suite" >"$target/etc/apt/sources.list"
printf 'deb https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/ /\n' >>"$target/etc/apt/sources.list"
printf 'tmpfs /tmp tmpfs defaults 0 0\n' >"$target/etc/fstab"
spool_options=$(sed -n "s/^MNT_VAR_SPOOL_RSYSLOG_TMPFS_OPTS='\([^']*\)'$/\1/p" "$policy/host.env")
if grep -Fqx "TMPFS_VAR_SPOOL_RSYSLOG='true'" "$policy/host.env"; then
  [ -n "$spool_options" ]
  printf 'tmpfs /var/spool/rsyslog tmpfs %s 0 0\n' "$spool_options" >>"$target/etc/fstab"
fi
cat >"$work/bin/in-target" <<'APT'
#!/bin/sh
set -eu
! grep -Fq 'debian12/x86_64/' "$FIXTURE_TARGET/etc/apt/sources.list"
case "$*" in
  /usr/local/libexec/apt-repo-local-normalize-sources|\
  'env DEBIAN_FRONTEND=noninteractive APT_LISTCHANGES_FRONTEND=none apt -y modernize-sources') ;;
  *) exit 89 ;;
esac
printf '%s\n' "$*" >>"$FIXTURE_WORK/apt.calls"
APT
cat >"$work/bin/chroot" <<'CHROOT'
#!/bin/sh
set -eu
[ "$1" = "$FIXTURE_TARGET" ] && [ "$2" = /bin/sh ] && [ "$3" = -eu ] && [ "$4" = -c ]
shift 5
[ "$1" = sh ]; shift
[ "$#" -eq 16 ] && [ "$1" = /etc ] && [ "$2" = /boot ] && [ "$3" = /lib ] &&
  [ "$4" = /usr/local/bin ] && [ "$5" = /usr/local/sbin ] &&
  [ "$6" = /usr/local/libexec ] && [ "$7" = /usr/local/lib ] &&
  [ "$8" = /usr/local/share ] && [ "$9" = /usr/lib ] &&
  [ "${10}" = /var/lib/installer-state ] && [ "${14}" = /etc/apparmor.d ]
printf '%s\n' 'mock boot/package audit: all sixteen target arguments supplied' >>"$FIXTURE_WORK/chroot.calls"
CHROOT
chmod 0755 "$work/bin/"*
invoke_hook() {
  hook=$1
  printf 'STEP case=%s hook=%s\n' "$fixture_case" "${hook##*/}"
  if [ "$fixture_shell" = /bin/busybox ]; then
    set -- /bin/busybox sh "$hook"
  else
    set -- "$fixture_shell" "$hook"
  fi
  # No inherited target paths, account settings, policy caches or shell
  # functions. Each hook loads the actual bootstrap and restricted data parser.
  env -i PATH="$work/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    HOME="$work/home" TMPDIR="$work/tmp" TMP="$work/tmp" TEMP="$work/tmp" LANG=C LC_ALL=C \
    INSTALLER_RUNTIME_DIR="$runtime" INSTALLER_SOURCE_ROOT="$source_root" \
    INSTALLER_SUITE="$fixture_suite" FIXTURE_WORK="$work" FIXTURE_TARGET="$target" \
    "$@" >"$work/stdout" 2>"$work/stderr"
}
normalizer=$source_root/hooks/installer/finish-install.d/99-normalize-finish
validator=$source_root/hooks/installer/finish-install.d/94zz-99-validate-target
case "$fixture_case" in
  baseline-normalizer) normalizer=/snapshot/before/99-normalize-finish ;;
  baseline-validator) validator=/snapshot/before/94zz-99-validate-target ;;
  baseline-app-veth)
    cp /snapshot/before/placeholder-registry.tsv "$runtime/bootstrap/placeholder-registry.tsv"
    chmod 0600 "$runtime/bootstrap/placeholder-registry.tsv"
    ;;
  reject-app-veth-marker) printf '__INSTALLER_PATH_DIR_ETC__\n' >>"$target/etc/app-veth.nft" ;;
  missing-host) rm "$policy/host.env" ;;
  invalid-host) printf "DIR_ETC='\$(touch %s)'\nbroken assignment\n" "$work/evaluated" >"$policy/host.env" ;;
  incomplete-host) printf "DIR_ETC='/etc'\n" >"$policy/host.env" ;;
  chain|chain-app-veth|missing-validator-host|invalid-validator-host|incomplete-validator-host) ;;
  *) exit 64 ;;
esac
case "$fixture_case" in
  baseline-validator|missing-validator-host|invalid-validator-host|incomplete-validator-host)
    case "$fixture_case" in
      missing-validator-host) rm "$policy/host.env" ;;
      invalid-validator-host) printf 'invalid assignment\n' >"$policy/host.env" ;;
      incomplete-validator-host) printf "DIR_ETC='/etc'\n" >"$policy/host.env" ;;
    esac
    status=0
    invoke_hook "$validator" || status=$?
    [ "$status" -ne 0 ] && [ ! -e "$work/chroot.calls" ]
    ;;
  baseline-normalizer|missing-host|invalid-host|incomplete-host)
    status=0
    invoke_hook "$normalizer" || status=$?
    [ "$status" -ne 0 ] && [ -f "$target/tmp/stale" ] && [ ! -e "$work/evaluated" ]
    ;;
  chain|chain-app-veth|baseline-app-veth|reject-app-veth-marker)
    invoke_hook "$source_root/hooks/installer/finish-install.d/09-cuda-legacy-cleanup"
    invoke_hook "$normalizer"
    grep -Fq 'completed final target normalization hook' "$work/installer.log"
    [ ! -e "$target/tmp/stale" ] && [ ! -e "$target/var/tmp/stale" ]
    [ "$(ls -ldn "$target/tmp" | cut -c 1-10)" = drwxrwxrwt ]
    [ "$(ls -ldn "$target/home/fixture" | cut -c 1-10)" = drwx------ ]
    [ "$(ls -ldn "$target/home/fixture/.config/settings" | cut -c 1-10)" = -rw------- ]
    [ "$(cat "$target/home/fixture/.config/settings")" = 'preserve account data' ]
    invoke_hook "$source_root/hooks/installer/finish-install.d/95-normalize-apt"
    [ "$(wc -l <"$work/apt.calls")" -eq 3 ]
    case "$fixture_case" in
      baseline-app-veth|reject-app-veth-marker)
        status=0
        invoke_hook "$validator" || status=$?
        [ "$status" -ne 0 ] && [ -s "$work/chroot.calls" ]
        [ ! -e "$runtime/state/target-validated" ] &&
          [ ! -e "$target/var/lib/installer-state/target-validated" ] &&
          [ ! -e "$runtime/state/installation.success" ]
        grep -Fq 'unresolved target marker file=/etc/app-veth.nft' "$work/stderr"
        case "$fixture_case" in
          baseline-app-veth)
            [ "$(grep -c 'fatal: unresolved target marker file=' "$work/stderr")" -eq 12 ]
            printf 'BASELINE_REPRODUCED app-veth final validation markers=12 status=%s\n' "$status"
            ;;
          reject-app-veth-marker) grep -Fq '__INSTALLER_PATH_DIR_ETC__' "$work/stderr" ;;
        esac
        ;;
      *)
        invoke_hook "$validator"
        grep -Fqx state=TARGET_VALIDATED "$runtime/state/target-validated"
        grep -Fqx installation_success=not_yet "$target/var/lib/installer-state/target-validated"
        [ ! -e "$runtime/state/installation.success" ] && [ -s "$work/chroot.calls" ]
        ;;
    esac
    ;;
esac
case "$fixture_case" in
  baseline-normalizer|baseline-validator)
    grep -Fq 'DIR_VAR_LIB_INSTALLER_STATE' "$work/stderr"
    printf 'BASELINE_REPRODUCED case=%s status=%s\n' "$fixture_case" "$status"
    head -n 2 "$work/stderr"
    ;;
  missing-*) grep -Fq 'missing host environment' "$work/stderr" ;;
  invalid-*) [ "$status" -eq 2 ]; grep -Fq 'host profile data was rejected' "$work/stderr" ;;
  incomplete-*) grep -Fq 'missing DIR_VAR_LIB_INSTALLER_STATE' "$work/stderr" ;;
esac
printf 'PASS case=%s shell=%s suite=%s profile=%s\n' \
  "$fixture_case" "$fixture_shell" "$fixture_suite" "$fixture_profile"

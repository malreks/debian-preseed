#!/bin/sh
# Repository transport. POSIX shell; wget-udeb supplies controlled redirects.
# The bootstrap core is embedded by tools/build.py, not maintained twice.
# BEGIN BOOTSTRAP CORE
# BEGIN EMBEDDED LIFECYCLE
#!/bin/sh
# Canonical d-i lifecycle. Embedded in source.sh before the first network fetch.
# Explicit delimiters also permit embedding in a single preseed command.
# Numeric ls is available in busybox-udeb; stat is deliberately not built.
# Only fixed metadata columns are parsed, never the filename or its whitespace.
installer_metadata_value() (
  set -f;
  lc_metadata=$(LC_ALL=C ls -ldn "$1" 2>/dev/null) || exit 1;
  lc_field=$2;
  set -- $lc_metadata;
  [ "$#" -ge 4 ] || exit 1;
  case "$2:$3:$4" in *[!0-9:]*|:*|*:|*::*) exit 1 ;; esac;
  case "$lc_field" in
    uid) printf '%s\n' "$3" ;;
    gid) printf '%s\n' "$4" ;;
    uid_gid) printf '%s:%s\n' "$3" "$4" ;;
    links) printf '%s\n' "$2" ;;
    mode|uid_gid_mode|uid_gid_mode_links)
      lc_mode=$(printf '%s\n' "$1" | awk '
        length($0) < 10 {exit 1}
        { special=0; value=0;
          for (i=2; i<=10; i++) {
            c=substr($0,i,1); bit=(i%3==2 ? 4 : (i%3==0 ? 2 : 1));
            if (c!="-") {
              if (c!="r" && c!="w" && c!="x" && c!="s" && c!="S" && c!="t" && c!="T") exit 1;
              if (c!="S" && c!="T") value+=bit;
              if (c=="s" || c=="S") special+=(i==4 ? 4 : 2);
              if (c=="t" || c=="T") special+=1;
            };
            if (i==4 || i==7) value*=8;
          };
          printf "%o\n", special*512+value;
        }') || exit 1;
      case "$lc_field" in
        mode) printf '%s\n' "$lc_mode" ;;
        uid_gid_mode) printf '%s:%s:%s\n' "$3" "$4" "$lc_mode" ;;
        uid_gid_mode_links) printf '%s:%s:%s:%s\n' "$3" "$4" "$lc_mode" "$2" ;;
      esac ;;
    *) exit 1 ;;
  esac;
);
installer_lifecycle_parent_safe() (
  set -f;
  lc_parent=$1;
  while [ "$lc_parent" != / ]; do
    if [ -e "$lc_parent" ] || [ -L "$lc_parent" ]; then
      [ -d "$lc_parent" ] && [ ! -L "$lc_parent" ] || exit 1;
      # Directory link counts grow with legitimate child directories. The
      # private runtime directories are protected by type, owner and mode;
      # single-link checks belong to regular files, not directory ancestors.
      lc_parent_uid=$(installer_metadata_value "$lc_parent" uid) || exit 1;
      [ "$lc_parent_uid" = 0 ] || [ "$lc_parent_uid" = "$(id -u)" ] || exit 1;
      case "$(installer_metadata_value "$lc_parent" mode)" in
        700|750|755|1700|1750|1755|1770|1775|1777) ;;
        *) exit 1 ;;
      esac;
    fi;
    lc_parent=${lc_parent%/*}; [ -n "$lc_parent" ] || lc_parent=/;
  done;
);
installer_lifecycle_paths() {
  LC_ROOT=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime};
  LC_STATE=$LC_ROOT/state;
  case "$LC_ROOT" in /*) ;; *) return 1 ;; esac;
  case "/${LC_ROOT#/}/" in *'/../'*|*'/./'*|*'//'*) return 1 ;; esac;
  [ "$LC_ROOT" != / ] || return 1;
  installer_lifecycle_parent_safe "$LC_ROOT" || return 1;
  for lc_path in "$LC_ROOT" "$LC_STATE"; do
    if [ -e "$lc_path" ] || [ -L "$lc_path" ]; then
      [ -d "$lc_path" ] && [ ! -L "$lc_path" ] || return 1;
      [ "$(installer_metadata_value "$lc_path" uid)" = "$(id -u)" ] || return 1;
      [ "$(installer_metadata_value "$lc_path" mode)" = 700 ] || return 1;
    fi;
  done;
  (umask 077; mkdir -p "$LC_STATE") || return 1;
  [ "$(installer_metadata_value "$LC_ROOT" uid)" = "$(id -u)" ] || return 1;
  [ "$(installer_metadata_value "$LC_STATE" uid)" = "$(id -u)" ] || return 1;
  [ "$(installer_metadata_value "$LC_ROOT" mode)" = 700 ] || return 1;
  [ "$(installer_metadata_value "$LC_STATE" mode)" = 700 ] || return 1;
};
installer_record_failure() (
  # Atomic first-writer-wins publication, never replaced by cleanup errors.
  set +e; umask 077;
  installer_lifecycle_paths || exit 1;
  lc_status=${1:-1}; lc_component=${2:-unknown}; lc_detail=${3:-unspecified};
  case "$lc_status" in ''|*[!0-9]*|0) lc_status=1 ;; esac;
  lc_component=$(printf '%s' "$lc_component" | tr '\r\n\t' '   ');
  lc_detail=$(printf '%s' "$lc_detail" | tr '\r\n\t' '   ');
  lc_source=${INSTALLER_FAILURE_SOURCE:-unknown};
  lc_line=${INSTALLER_FAILURE_LINE:-unknown};
  lc_operation=${INSTALLER_FAILURE_OPERATION:-unknown};
  lc_source=$(printf '%s' "$lc_source" | tr '\r\n\t' '   ');
  lc_operation=$(printf '%s' "$lc_operation" | tr '\r\n\t' '   ');
  case "$lc_line" in
    ''|*[!A-Za-z0-9_.-]*) lc_line=unknown ;;
  esac;
  rm -f "$LC_STATE/installation.success" "$LC_STATE/target-validated";
  [ ! -e "$LC_STATE/first-failure" ] && [ ! -L "$LC_STATE/first-failure" ] || exit 0;
  lc_tmp=$(mktemp "$LC_STATE/.failure.XXXXXX") || exit 1;
  trap 'rm -f "$lc_tmp"' 0;
  { printf 'format=1\nstate=FATAL\nstatus=%s\n' "$lc_status";
    printf 'phase=%s\ncomponent=%s\nsource=%s\nline=%s\noperation=%s\n' "${INSTALLER_PHASE:-unknown}" "$lc_component" "$lc_source" "$lc_line" "$lc_operation";
    printf 'timestamp=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')";
    printf 'detail=%s\n' "$lc_detail";
  } >"$lc_tmp" || exit 1;
  chmod 0600 "$lc_tmp" || exit 1;
  ln "$lc_tmp" "$LC_STATE/first-failure" 2>/dev/null || [ -f "$LC_STATE/first-failure" ];
);
installer_preserve_failure() (
  set +e; umask 077;
  installer_lifecycle_paths || exit 1;
  lc_target=${INSTALLER_TARGET_DIR:-${TARGET_ROOT:-/target}};
  # /target is the Debian Installer mount-point contract used only while the
  # authenticated installer environment is not available to failure logging.
  # Never write into the installer's uncovered target directory after unmount.
  awk -v p="$lc_target" '$2==p {found=1} END {exit !found}' /proc/mounts || exit 0;
  lc_path=$lc_target/var/log/installer;
  while [ "$lc_path" != / ]; do
    [ ! -L "$lc_path" ] || exit 1;
    lc_path=${lc_path%/*}; [ -n "$lc_path" ] || lc_path=/;
  done;
  mkdir -p "$lc_target/var/log/installer" || exit 1;
  chmod 0700 "$lc_target/var/log/installer" || exit 1;
  for lc_source in "$LC_STATE/first-failure" "${FILE_INSTALLER_LOG:-/tmp/installer.log}" /var/log/syslog; do
    [ -f "$lc_source" ] && [ ! -L "$lc_source" ] || continue;
    lc_tmp=$(mktemp "$lc_target/var/log/installer/.diagnostic.XXXXXX") || exit 1;
    if cp "$lc_source" "$lc_tmp" && chmod 0600 "$lc_tmp"; then
      mv -f "$lc_tmp" "$lc_target/var/log/installer/${lc_source##*/}" || exit 1;
    else rm -f "$lc_tmp"; exit 1; fi;
  done;
);
installer_failure_frontend_prepare() {
  # Use the running cdebconf frontend, including its in-memory template DB.
  # The public Debian shell API is already initialized; it must not exec a
  # second frontend or replace the phase-owned protocol descriptors here.
  db_x_loadtemplatefile "$lf_template" unattended-installer || return 1;
  db_progress STOP || return 1;
  db_clear || return 1;
  db_capb '' || return 1;
  db_settitle "$lf_question" || return 1;
  db_subst "$lf_question" PHASE "$lf_phase" || return 1;
  db_subst "$lf_question" COMPONENT "$lf_component" || return 1;
  db_subst "$lf_question" SOURCE "$lf_source" || return 1;
  db_subst "$lf_question" LINE "$lf_line" || return 1;
  db_subst "$lf_question" OPERATION "$lf_operation" || return 1;
  db_subst "$lf_question" STATUS "$lf_status" || return 1;
  db_fset "$lf_question" seen false || return 1;
  db_input critical "$lf_question" || return 1;
};
installer_failure_frontend() (
  set +e; set +x; set +v; umask 077;
  # FDs 3 and 8 belong to the inherited d-i connection. Never create a new
  # frontend/database writer, guess stdout, or consume a redirected stdin.
  [ -n "${DEBIAN_HAS_FRONTEND:-}" ] && [ -n "${DEBCONF_REDIR:-}" ] || exit 1;
  [ "${INSTALLER_DEBCONF_STDIN_SAVED:-}" = 1 ] || exit 1;
  [ -z "${LC_CHILD_PID:-}" ] || exit 1;
  ( : >&3 <&8 ) 2>/dev/null || exit 1;
  exec 0<&8;
  installer_lifecycle_paths || exit 1;
  case "$LC_STATE" in *[!A-Za-z0-9_./-]*) exit 1 ;; esac;
  # Keep the one-shot claim even after a broken connection or an uncertain
  # reply: nested fatal handlers must not race or retry the same UI mutation.
  lf_dir=$LC_STATE/frontend-error;
  mkdir "$lf_dir" 2>/dev/null || exit 0;
  printf '%s\n' preparing >"$lf_dir/result" || exit 1;
  lf_phase=unknown; lf_component=unknown; lf_source=unknown;
  lf_line=unknown; lf_operation=unknown; lf_status=unknown;
  lf_record=$LC_STATE/first-failure;
  if [ -f "$lf_record" ] && [ ! -L "$lf_record" ] &&
     [ "$(installer_metadata_value "$lf_record" uid_gid_mode_links)" = "$(id -u):$(id -g):600:1" ] &&
     [ "$(wc -c <"$lf_record")" -le 16384 ]; then
    while IFS='=' read -r lf_key lf_value; do
      # Only bounded structured context is public UI data. Raw failure detail,
      # command lines, credentials, URLs and frontend replies never reach GTK.
      case "$lf_key" in phase|component|source|line|operation|status) ;; *) continue ;; esac;
      case "$lf_value" in ''|*://*|*[!A-Za-z0-9_./:+-]*) lf_value=unavailable ;; esac;
      [ "${#lf_value}" -le 240 ] || lf_value=unavailable;
      case "$lf_key" in
        phase) lf_phase=$lf_value ;; component) lf_component=$lf_value ;;
        source) lf_source=$lf_value ;; line) lf_line=$lf_value ;;
        operation) lf_operation=$lf_value ;; status) lf_status=$lf_value ;;
      esac;
    done <"$lf_record";
  fi;
  lf_question=unattended-installer/fatal-error;
  lf_template=$lf_dir/templates;
  # Native Type:error is an acknowledged GTK installer error dialog (also
  # supported by the text frontend). No target GUI program is needed in d-i.
  # Keep explicit delimiters and printf lines: this library is flattened into
  # preseed shell commands before the first authenticated payload fetch.
  printf '%s\n' 'Template: unattended-installer/fatal-error' 'Type: error' 'Description: Unattended installation failed' ' A required installer operation failed. Installation has stopped.' ' .' ' Phase: ${PHASE}' ' Component: ${COMPONENT}' ' Operation: ${OPERATION}' ' Source: ${SOURCE}:${LINE}' ' Status: ${STATUS}' ' .' ' See terminal 4 for detailed diagnostics. Automatic reboot is disabled.' ' Manual recovery is required; Continue only acknowledges this error.' '' >"$lf_template" || exit 1;
  # Immutable Debian confmodule interface, not a target or checkout path.
  [ -r /usr/share/debconf/confmodule ] || exit 1;
  . /usr/share/debconf/confmodule;
  # Setup must not leave a dead frontend looking like an installer hang.
  # Silence library protocol errors: a malformed reply may contain private data.
  installer_run_bounded 15 installer_failure_frontend_prepare >/dev/null 2>&1 || {
    printf '%s\n' unavailable >"$lf_dir/result"; exit 1;
  };
  printf '%s\n' queued >"$lf_dir/result" || exit 1;
  # GO is intentionally interactive. Never dismiss the error on a timer.
  # Acknowledgement cannot resume any installer operation or automatic reboot.
  if db_go >/dev/null 2>&1; then
    printf '%s\n' acknowledged >"$lf_dir/result"; exit 0;
  fi;
  printf '%s\n' unavailable >"$lf_dir/result";
  exit 1;
);
installer_terminal_hold() {
  # A nonzero late_command is NOT terminal: preseed_command may swallow it,
  # and finish-install logs most hook failures then continues toward reboot.
  # Do not return to either caller. SIGSTOP the actual main-menu ancestor too,
  # so killing this leaf cannot restart unattended installation work.
  trap '' HUP INT TERM; trap - 0;
  set +e;
  installer_preserve_failure;
  lc_failure_file=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}/state/first-failure;
  if [ -r "$lc_failure_file" ]; then
    printf '\nINSTALLER TERMINAL FAILURE: no further installation or reboot is permitted.\nDiagnostics: %s and %s\n' "$lc_failure_file" "${FILE_INSTALLER_LOG:-/tmp/installer.log}" >&2;
  else
    printf '\nINSTALLER TERMINAL FAILURE: no further installation or reboot is permitted.\nFailure record unavailable; inspect %s\n' "${FILE_INSTALLER_LOG:-/tmp/installer.log}" >&2;
  fi;
  if [ -r "$lc_failure_file" ]; then
    lc_failure_status=$(sed -n 's/^status=//p' "$lc_failure_file" | sed -n '1p');
    lc_failure_component=$(sed -n 's/^component=//p' "$lc_failure_file" | sed -n '1p');
    lc_failure_source=$(sed -n 's/^source=//p' "$lc_failure_file" | sed -n '1p');
    lc_failure_line=$(sed -n 's/^line=//p' "$lc_failure_file" | sed -n '1p');
    lc_failure_operation=$(sed -n 's/^operation=//p' "$lc_failure_file" | sed -n '1p');
    lc_failure_detail=$(sed -n 's/^detail=//p' "$lc_failure_file" | sed -n '1p');
    lc_failure_summary="status=${lc_failure_status:-unknown} component=${lc_failure_component:-unknown} source=${lc_failure_source:-unknown} line=${lc_failure_line:-unknown} operation=${lc_failure_operation:-unknown} detail=${lc_failure_detail:-unknown}";
    printf 'INSTALLER FAILURE DETAIL: %s\n' "$lc_failure_summary" >&2;
  fi;
  if [ -c /dev/console ] && [ -w /dev/console ]; then
    if [ -r "$lc_failure_file" ]; then
      printf '\nINSTALLER TERMINAL FAILURE. Inspect %s; manual recovery required.\n' "$lc_failure_file" >/dev/console;
    else
      printf '\nINSTALLER TERMINAL FAILURE. Failure record unavailable; inspect %s.\n' "${FILE_INSTALLER_LOG:-/tmp/installer.log}" >/dev/console;
    fi;
    [ -n "${lc_failure_summary:-}" ] && printf 'INSTALLER FAILURE DETAIL: %s\n' "$lc_failure_summary" >/dev/console;
  fi;
  if [ -c /dev/tty4 ] && [ -w /dev/tty4 ]; then
    if [ -r "$lc_failure_file" ]; then
      printf '\nINSTALLER TERMINAL FAILURE. Inspect %s; manual recovery required.\n' "$lc_failure_file" >/dev/tty4;
    else
      printf '\nINSTALLER TERMINAL FAILURE. Failure record unavailable; inspect %s.\n' "${FILE_INSTALLER_LOG:-/tmp/installer.log}" >/dev/tty4;
    fi;
    [ -n "${lc_failure_summary:-}" ] && printf 'INSTALLER FAILURE DETAIL: %s\n' "$lc_failure_summary" >/dev/tty4;
  fi;
  # Present the error before stopping main-menu. Otherwise GTK can remain on
  # its last progress screen forever, with the failure visible only on tty4.
  installer_failure_frontend || printf '%s\n' 'Installer frontend error dialog unavailable; diagnostics remain on tty4.' >&2;
  lc_pid=$$; lc_depth=0;
  while [ "$lc_pid" -gt 1 ] && [ "$lc_depth" -lt 64 ]; do
    lc_name=$(cat "/proc/$lc_pid/comm" 2>/dev/null);
    if [ "$lc_name" = main-menu ]; then kill -STOP "$lc_pid"; break; fi;
    lc_pid=$(awk '/^PPid:/ {print $2}' "/proc/$lc_pid/status" 2>/dev/null);
    case "$lc_pid" in ''|*[!0-9]*) break ;; esac;
    lc_depth=$(expr "$lc_depth" + 1) || break;
  done;
  sync;
  # This is an intentional terminal wait, not a retry loop. No commands that
  # customize the target, run a phase, or reboot occur inside it.
  while :; do sleep 3600; done;
};
installer_lifecycle_now() (
  if [ -r /proc/uptime ]; then
    IFS=' ' read -r lc_now_seconds lc_now_remainder </proc/uptime || exit 1;
    lc_now_seconds=${lc_now_seconds%%.*};
  else
    lc_now_seconds=$(date +%s) || exit 1;
  fi;
  case "$lc_now_seconds" in ''|*[!0-9]*) exit 1 ;; esac;
  printf '%s\n' "$lc_now_seconds";
);
installer_process_zombie() (
  lc_zombie_pid=$1;
  case "$lc_zombie_pid" in ''|*[!0-9]*|0|1) exit 1 ;; esac;
  lc_zombie_state=$(sed -n 's/^State:[[:space:]]*//p' "/proc/$lc_zombie_pid/status" 2>/dev/null) || exit 1;
  case "$lc_zombie_state" in Z*) exit 0 ;; esac;
  exit 1;
);
# Freeze the owned child before enumerating descendants. Frozen parents cannot
# reap/reuse their child PIDs or launch subsequent installer commands. No process
# group, host-wide kill, setsid, Python, or stat applet is needed in busybox-udeb.
installer_stop_tree() (
  # Callers may disable globbing while parsing URLs. The private /proc fallback
  # must still expand its trusted numeric PID pattern. Never inherit noglob here.
  set +f;
  lc_stop_pid=$1; lc_stop_depth=${2:-0};
  case "$lc_stop_depth" in ''|*[!0-9]*) exit 1 ;; esac;
  case "$lc_stop_pid" in ''|*[!0-9]*|0|1) exit 1 ;; esac;
  [ "$lc_stop_depth" -lt 128 ] || exit 1;
  [ -d "/proc/$lc_stop_pid" ] || exit 0;
  installer_process_zombie "$lc_stop_pid" && exit 0;
  kill -STOP "$lc_stop_pid" 2>/dev/null || exit 0;
  lc_children=$(cat "/proc/$lc_stop_pid/task/$lc_stop_pid/children" 2>/dev/null) || {
    # Some kernels omit CONFIG_CHECKPOINT_RESTORE and therefore children.
    lc_children=;
    for lc_proc_status in /proc/[0-9]*/status; do
      lc_proc_parent=$(awk '/^PPid:/ {print $2}' "$lc_proc_status" 2>/dev/null) || continue;
      [ "$lc_proc_parent" = "$lc_stop_pid" ] || continue;
      lc_proc_id=${lc_proc_status%/status}; lc_proc_id=${lc_proc_id##*/};
      lc_children="$lc_children $lc_proc_id";
    done;
  };
  for lc_child in $lc_children; do
    case "$lc_child" in ''|*[!0-9]*) continue ;; esac;
    lc_parent=$(awk '/^PPid:/ {print $2}' "/proc/$lc_child/status" 2>/dev/null);
    [ "$lc_parent" = "$lc_stop_pid" ] || continue;
    lc_stop_next_depth=$(expr "$lc_stop_depth" + 1) || exit 1;
    installer_stop_tree "$lc_child" "$lc_stop_next_depth" || :;
  done;
  kill -KILL "$lc_stop_pid" 2>/dev/null || :;
);

# External commands run as a direct child, with responsive signal traps while
# waiting. Shell child statuses are retained, not replaced by diagnostic output.
# Snapshot stdin in the PARENT before starting an asynchronous list. In ash and
# dash, <&0 on an async command duplicates the /dev/null the shell has already
# installed, not the caller's stdin. d-i uses stdin for cdebconf replies; losing
# it makes confmodule return an empty (illegal) status. FD 9 is launch-local:
# preserve d-i's FDs 3-6, close the extra copy in the child, and let the function
# redirection restore the caller's previous FD 9 on return.
installer_run_supervised() {
  "$@" <&9 9<&- &
  LC_CHILD_PID=$!;
  if wait "$LC_CHILD_PID"; then lc_child_status=0; else lc_child_status=$?; fi;
  LC_CHILD_PID=;
  return "$lc_child_status";
} 9<&0;

# Normalize bounded durations before numeric comparison or child creation.
# test(1) accepts leading zeroes as decimal, while shell arithmetic treats them
# as octal: 0180 passes a range check but raises a fatal ash arithmetic error.
# The bootstrap must not depend on a shell's arithmetic parser at all.
installer_bounded_seconds() (
  lc_seconds=${1-};
  case "$lc_seconds" in ''|*[!0-9]*) exit 125 ;; esac;
  while [ "${lc_seconds#0}" != "$lc_seconds" ]; do lc_seconds=${lc_seconds#0}; done;
  [ -n "$lc_seconds" ] && [ "${#lc_seconds}" -le 3 ] || exit 125;
  [ "$lc_seconds" -ge 1 ] && [ "$lc_seconds" -le 900 ] || exit 125;
  printf '%s\n' "$lc_seconds";
);

# Use only integer sleep and seq, both available in busybox-udeb. Do not rely
# on desktop BusyBox's fractional sleep or a timeout/setsid applet. The finite
# sequence is prepared BEFORE launching the child; failures cannot leak a fetch.
# Traps and counters are private to this one operation's subshell.
installer_run_bounded() (
  lc_limit=$(installer_bounded_seconds "${1-}") || exit 125;
  shift;
  [ "$#" -gt 0 ] || exit 125;
  set -f;
  "$@" <&9 9<&- &
  lc_bounded_pid=$!;
  trap 'installer_stop_tree "$lc_bounded_pid"; wait "$lc_bounded_pid" 2>/dev/null || :; exit 129' HUP;
  trap 'installer_stop_tree "$lc_bounded_pid"; wait "$lc_bounded_pid" 2>/dev/null || :; exit 130' INT;
  trap 'installer_stop_tree "$lc_bounded_pid"; wait "$lc_bounded_pid" 2>/dev/null || :; exit 143' TERM;
  lc_bounded_started=$(installer_lifecycle_now) || exit 125;
  lc_bounded_deadline=$(expr "$lc_bounded_started" + "$lc_limit") || exit 125;
  while :; do
    if ! kill -0 "$lc_bounded_pid" 2>/dev/null; then
      if wait "$lc_bounded_pid"; then lc_bounded_status=0; else lc_bounded_status=$?; fi;
      exit "$lc_bounded_status";
    fi;
    lc_bounded_now=$(installer_lifecycle_now) || exit 125;
    if [ "$lc_bounded_now" -ge "$lc_bounded_deadline" ]; then
      # kill -0 also succeeds for a zombie. Reap a child that completed at the
      # deadline before classifying it as a timeout; only a still-live child is
      # stopped and reported as 124.
      if installer_process_zombie "$lc_bounded_pid"; then
        if wait "$lc_bounded_pid"; then lc_bounded_status=0; else lc_bounded_status=$?; fi;
        exit "$lc_bounded_status";
      fi;
      installer_stop_tree "$lc_bounded_pid";
      if installer_process_zombie "$lc_bounded_pid"; then
        if wait "$lc_bounded_pid"; then lc_bounded_status=0; else lc_bounded_status=$?; fi;
        exit "$lc_bounded_status";
      fi;
      wait "$lc_bounded_pid" 2>/dev/null || :;
      exit 124;
    fi;
    if ! sleep 1; then
      installer_stop_tree "$lc_bounded_pid";
      wait "$lc_bounded_pid" 2>/dev/null || :;
      exit 125;
    fi;
  done;
) 9<&0;

installer_lifecycle_signal() {
  lc_signal_status=$1;
  trap '' HUP INT TERM;
  installer_record_failure "$lc_signal_status" "${INSTALLER_PHASE:-unknown}" 'supervisor received a termination signal' || :;
  if [ -n "${LC_CHILD_PID:-}" ]; then
    installer_stop_tree "$LC_CHILD_PID" || :;
    wait "$LC_CHILD_PID" 2>/dev/null || :;
    LC_CHILD_PID=;
  fi;
  exit "$lc_signal_status";
};

installer_lifecycle_abort() {
  lc_abort_status=${1:-1};
  lc_abort_component=${2:-${INSTALLER_PHASE:-unknown}};
  lc_abort_detail=${3:-mandatory operation failed};
  if [ "$lc_abort_detail" = 'mandatory operation failed' ]; then
    lc_abort_detail="${lc_abort_detail}; status=${lc_abort_status}; source=${INSTALLER_FAILURE_SOURCE:-unknown}; line=${INSTALLER_FAILURE_LINE:-unknown}; operation=${INSTALLER_FAILURE_OPERATION:-unknown}";
  fi;
  installer_record_failure "$lc_abort_status" "$lc_abort_component" "$lc_abort_detail" || :;
  installer_terminal_hold;
};
installer_lifecycle_exit() {
  lc_exit=$1; trap - 0;
  if [ "$lc_exit" -ne 0 ]; then
    installer_lifecycle_abort "$lc_exit" "${INSTALLER_PHASE:-unknown}" "phase exited unsuccessfully; status=${lc_exit}; source=${INSTALLER_FAILURE_SOURCE:-unknown}; line=${INSTALLER_FAILURE_LINE:-unknown}; operation=${INSTALLER_FAILURE_OPERATION:-unknown}";
  fi;
  if [ -e "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}/state/first-failure" ]; then installer_terminal_hold; fi;
  [ "${INSTALLER_LIFECYCLE_COMPLETE:-0}" = 1 ] || installer_lifecycle_abort 125 "${INSTALLER_PHASE:-unknown}" 'phase exited without explicit completion';
};
installer_lifecycle_arm() {
  # main-menu may launch a component before the shell confmodule has redirected
  # protocol stdout onto FD 3. Do this before any repository logger captures it.
  # Never unset DEBIAN_HAS_FRONTEND or start a competing database writer.
  if [ -n "${DEBIAN_HAS_FRONTEND:-}" ] && [ -z "${DEBCONF_REDIR:-}" ]; then
    [ -r /usr/share/debconf/confmodule ] || installer_lifecycle_abort 125 debconf 'shell confmodule is unavailable';
    . /usr/share/debconf/confmodule;
  fi;
  # Keep one phase-owned copy of the frontend reply stream. Target-command
  # wrappers, pipelines and class-helper loops may legitimately replace stdin.
  # FDs 3-6 belong to d-i; FD 7 is used by record readers and FD 9 is launch-local.
  # Never overwrite an unrelated open FD or silently recapture redirected stdin.
  if [ -n "${DEBIAN_HAS_FRONTEND:-}" ]; then
    case "${INSTALLER_DEBCONF_STDIN_SAVED:-}" in
      1)
        ( : <&8 ) 2>/dev/null || installer_lifecycle_abort 125 debconf 'saved frontend reply descriptor is unavailable';
        ;;
      '')
        if ( : <&8 ) 2>/dev/null; then
          installer_lifecycle_abort 125 debconf 'frontend reply descriptor 8 is already in use';
        fi;
        ( : <&0 ) 2>/dev/null || installer_lifecycle_abort 125 debconf 'frontend reply stream is unavailable';
        exec 8<&0;
        INSTALLER_DEBCONF_STDIN_SAVED=1;
        export INSTALLER_DEBCONF_STDIN_SAVED;
        ;;
      *) installer_lifecycle_abort 125 debconf 'invalid saved frontend descriptor state' ;;
    esac;
  fi;
  INSTALLER_PHASE=$1; INSTALLER_LIFECYCLE_ACTIVE=1; INSTALLER_LIFECYCLE_COMPLETE=0;
  export INSTALLER_PHASE INSTALLER_LIFECYCLE_ACTIVE;
  case "$INSTALLER_PHASE" in ''|*[!A-Za-z0-9_.-]*) installer_lifecycle_abort 125 lifecycle 'invalid phase identifier' ;; esac;
  installer_lifecycle_paths || installer_lifecycle_abort 125 lifecycle 'unsafe or unavailable lifecycle state directory';
  trap 'installer_lifecycle_exit "$?"' 0;
  trap 'installer_lifecycle_signal 129' HUP; trap 'installer_lifecycle_signal 130' INT; trap 'installer_lifecycle_signal 143' TERM;
  [ ! -e "$LC_STATE/first-failure" ] && [ ! -L "$LC_STATE/first-failure" ] || installer_terminal_hold;
};
installer_lifecycle_begin() {
  installer_lifecycle_arm "$1";
  # A completed phase is a no-op; an interrupted phase must never be guessed
  # resumable (particularly partman). Both decisions precede target changes.
  if [ -f "$LC_STATE/$INSTALLER_PHASE.done" ] && [ ! -L "$LC_STATE/$INSTALLER_PHASE.done" ]; then
    INSTALLER_LIFECYCLE_COMPLETE=1; return 10;
  fi;
  mkdir "$LC_STATE/$INSTALLER_PHASE.running" 2>/dev/null || installer_lifecycle_abort 125 "$INSTALLER_PHASE" 'interrupted or concurrent invocation';
};
installer_lifecycle_complete() {
  installer_lifecycle_paths || installer_lifecycle_abort 125 lifecycle 'cannot publish completion';
  [ ! -e "$LC_STATE/first-failure" ] || installer_terminal_hold;
  lc_done=$(mktemp "$LC_STATE/.done.XXXXXX") || installer_lifecycle_abort 125 lifecycle 'cannot stage completion';
  printf 'phase=%s\nstate=complete\n' "$INSTALLER_PHASE" >"$lc_done" || installer_lifecycle_abort 125 lifecycle 'cannot write completion';
  chmod 0600 "$lc_done" && mv -f "$lc_done" "$LC_STATE/$INSTALLER_PHASE.done" || installer_lifecycle_abort 125 lifecycle 'cannot publish completion';
  rmdir "$LC_STATE/$INSTALLER_PHASE.running" 2>/dev/null || :;
  INSTALLER_LIFECYCLE_COMPLETE=1;
};
installer_guard_hook() (
  set -eu; umask 077;
  lc_hook=$1; lc_group=$2;
  installer_lifecycle_paths || exit 1;
  case "$LC_ROOT" in *[!A-Za-z0-9_./-]*) exit 1 ;; esac;
  lc_name=${lc_hook##*/}; lc_id=hook-$lc_group-$lc_name;
  case "$lc_id" in *[!A-Za-z0-9_.-]*) exit 1 ;; esac;
  [ -f "$lc_hook" ] && [ ! -L "$lc_hook" ] || exit 1;
  if grep -Fqx '# INSTALLER_GUARDED_HOOK_V1' "$lc_hook"; then exit 0; fi;
  lc_runner=$LC_ROOT/bootstrap/guard-hook.sh;
  [ -x "$lc_runner" ] && [ ! -L "$lc_runner" ] || exit 1;
  lc_backup_dir=$LC_ROOT/bootstrap/supervised/$lc_id;
  lc_backup=$lc_backup_dir/$lc_name;
  mkdir -p "$lc_backup_dir" || exit 1;
  chmod 0700 "$lc_backup_dir" || exit 1;
  if [ -e "$lc_backup" ] || [ -L "$lc_backup" ]; then
    [ -f "$lc_backup" ] && [ ! -L "$lc_backup" ] && cmp -s "$lc_hook" "$lc_backup" || exit 1;
  else
    lc_tmp=$(mktemp "$lc_backup_dir/.original.XXXXXX") || exit 1;
    cp "$lc_hook" "$lc_tmp" && chmod 0700 "$lc_tmp" && mv "$lc_tmp" "$lc_backup" || exit 1;
  fi;
  lc_tmp=$(mktemp "${lc_hook}.guard.XXXXXX") || exit 1;
  trap 'rm -f "$lc_tmp"' 0;
  printf '#!/bin/sh\n# INSTALLER_GUARDED_HOOK_V1\nexec "%s" "%s" "%s" "$@"\n' "$lc_runner" "$lc_id" "$lc_backup" >"$lc_tmp" || exit 1;
  chmod 0755 "$lc_tmp" && mv -f "$lc_tmp" "$lc_hook" || exit 1;
);
# END EMBEDDED LIFECYCLE
source_error() {
  printf '[repository] fatal: %s\n' "$*" >&2;
  if [ -w /dev/tty4 ] && [ -c /dev/tty4 ]; then printf '[repository] fatal: %s\n' "$*" >/dev/tty4; fi;
  if command -v logger >/dev/null 2>&1; then logger -t preseed-repository "fatal: $*" 2>/dev/null || :; fi;
  return 1;
};
source_cmdline_registered_credential() {
  case "${1:-}" in
    wifi_interface|wifi_essid|wifi_security|wifi_cidr|wifi_wep|netcfg/wireless_wpa|wireless_wpa|wifi_wpa|fruux_username|fruux_password|primary_username|primary_user|primary_fullname|primary_password|primary_gpg_passphrase|git_ssh_passphrase|shim_signed_passphrase|dns_upstream_tls_ca_name_custom|root_password|crowdsec_token|crowdsec_enroll_token|crowdsec_attachment_key|urlhaus_authkey|tailscale_authkey|tailscale_auth_key|filen_priv_email|filen_priv_password|filen_priv_2fa_seed|filen_offsec_email|filen_offsec_password|filen_offsec_2fa_seed|telegram_chat_id|telegram_api_key|cf_r2_access_key|cf_r2_secret_key|obs_username|obs_password|ci_github_token|ci_gitlab_token|technitium_username|technitium_password|technitium_web_username|technitium_web_password|technitium_tls_passphrase|technitium_backup_passphrase)
      return 0 ;;
  esac;
  return 1;
};
source_cmdline_secret_key() {
  source_cmdline_registered_credential "${1:-}" && return 1;
  case "${1:-}" in
    # Unknown password/passphrase names are filtered just like unknown token
    # names. Registered account and Wi-Fi keys returned above remain available.
    password|passphrase|*[._/-]password*|*[._/-]passphrase*|*[._/-]psk*)
      return 0 ;;
    crowdsec_token|crowdsec_enroll_token|crowdsec_attachment_key|urlhaus_authkey|tailscale_authkey|tailscale_auth_key|filen_priv_2fa_seed|filen_offsec_2fa_seed|telegram_api_key|cf_r2_access_key|cf_r2_secret_key|ci_github_token|ci_gitlab_token|token|secret|psk|key|credential|*[._/-]token*|*[._/-]secret*|*[._/-]psk*|*[._/-]key*|*[._/-]credential*|*authkey*)
      return 0 ;;
  esac;
  return 1;
};
# Compatibility name retained for the transport entrypoint; unregistered
# secret-looking arguments are silently filtered from the forwarded cmdline.
source_cmdline_reject_secrets() (
  set -f;
  IFS=' ';
  source_cmdline_filtered=;
  for source_cmdline_arg in $1; do
    source_cmdline_key=${source_cmdline_arg%%=*};
    if source_cmdline_secret_key "$source_cmdline_key"; then
      continue;
    fi;
    source_cmdline_filtered="${source_cmdline_filtered:+$source_cmdline_filtered }$source_cmdline_arg";
  done;
  printf '%s\n' "$source_cmdline_filtered";
);
source_cmdline() {
  if [ "${INSTALLER_CMDLINE+x}" = x ]; then
    source_cmdline_reject_secrets "$INSTALLER_CMDLINE";
  else
    source_cmdline_value=$(cat /proc/cmdline 2>/dev/null || :);
    source_cmdline_reject_secrets "$source_cmdline_value";
  fi;
};
source_hash() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum; elif command -v busybox >/dev/null 2>&1; then busybox sha256sum; else source_error 'sha256sum is required in the installer'; return 1; fi;
};
source_monotonic_seconds() (
  IFS=' ' read -r seconds remainder </proc/uptime || exit 1;
  seconds=${seconds%%.*};
  case "$seconds" in ''|*[!0-9]*) exit 1 ;; esac;
  [ "${#seconds}" -le 12 ] || exit 1;
  printf '%s\n' "$seconds";
);
source_effective_url() {
  awk -v initial="$1" 'function join(b,l, a,n,i,out,scheme,host,path,q) { if(l ~ /^[A-Za-z][A-Za-z0-9+.-]*:\/\//) return l; if(l ~ /^[A-Za-z][A-Za-z0-9+.-]*:/) return l; scheme=b; sub(/:.*/,"",scheme); host=b; sub(/^[A-Za-z][A-Za-z0-9+.-]*:\/\//,"",host); sub(/\/.*/,"",host); if(l ~ /^\/\//) return scheme ":" l; sub(/[?#].*/,"",b); if(l ~ /^\//) path=l; else if(l ~ /^\?/) return b l; else {path=b; sub(/^[A-Za-z][A-Za-z0-9+.-]*:\/\/[^\/]+/,"",path); sub(/[^\/]*$/,"",path); path=path l}; q=path; sub(/^[^?#]*/,"",q); sub(/[?#].*/,"",path); n=split(path,a,"/"); out=""; for(i=1;i<=n;i++){if(a[i]=="" || a[i]==".") continue; if(a[i]=="..") sub(/\/[^\/]*$/,"",out); else out=out "/" a[i]}; return scheme "://" host out q } BEGIN {url=initial; count=0} {line=$0; sub(/^[ \t]+/,"",line); if(tolower(line) ~ /^location:/) {sub(/^[^:]*:[ \t]*/,"",line); sub(/\r$/,"",line); sub(/[ \t]+\[following\].*$/,"",line); sub(/[ \t]+$/,"",line); nexturl=join(url,line); if(nexturl != "") url=nexturl; count++}} END {if(count>50) exit 1; print url}' "$2";
};
source_seed_base_from_effective() (
  value=$1;
  value=${value%%\#*}; value=${value%%\?*};
  case "$value" in */*.cfg) value=${value%/*} ;; esac;
  while [ "$value" != / ] && [ "${value%/}" != "$value" ]; do value=${value%/}; done;
  case "$value" in http://*|https://*) printf '%s\n' "$value" ;; *) source_error 'unsupported effective preseed source'; exit 1 ;; esac;
);
source_http_get() (
  set -eu;
  umask 077;
  url=$1; destination=$2; effective=${3:-}; redirect_scope=${4:-repository};
  case "$redirect_scope" in repository|seed|external) ;; *) source_error 'invalid transport redirect scope'; exit 125 ;; esac;
  read_timeout=$(installer_bounded_seconds "${INSTALLER_FETCH_TIMEOUT:-45}") || {
    source_error 'INSTALLER_FETCH_TIMEOUT must be 1 through 900 integer seconds' || :; exit 125;
  };
  wall_timeout=$(installer_bounded_seconds "${INSTALLER_FETCH_WALL_TIMEOUT:-180}") || {
    source_error 'INSTALLER_FETCH_WALL_TIMEOUT must be 1 through 900 integer seconds' || :; exit 125;
  };
  case "$url" in http://*|https://*) ;; *) source_error 'unsupported transport scheme'; exit 1 ;; esac;
  if [ "$redirect_scope" = external ]; then
    case "$url" in https://*) ;; *) source_error 'external downloads require HTTPS'; exit 1 ;; esac;
  fi;
  command -v wget >/dev/null 2>&1 || { source_error 'wget is required in the installer'; exit 1; };
  mkdir -p "$(dirname "$destination")" || exit 1;
  temp=$(mktemp "${destination}.part.XXXXXX") || exit 1; headers=${temp}.headers;
  trap 'rm -f "$temp" "$headers"' 0;
  trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP;
  set -- wget --no-config -S -T "$read_timeout" -O "$temp" --tries=1;
  # Keep the policy independent of the initial scheme: an HTTP URL may
  # redirect to HTTPS, and that HTTPS hop must also skip certificate checks.
  set -- "$@" --no-check-certificate;
  # d-i intentionally delegates HTTP/HTTPS parsing, redirects, and certificate
  # behavior to wget. This keeps url=/preseed/url= usable with LAN HTTP,
  # shorteners, GitHub and lightweight installer images. Payload and manifest
  # digests remain the independent authenticity boundary.
  # One deadline covers every transfer attempt and retry.
  started=$(source_monotonic_seconds) || exit 125;
  deadline=$(expr "$started" + "$wall_timeout") || exit 125;
  attempts=0;
  success=false; fetch_status=1;
  for attempt in 1 2 3; do
    now=$(source_monotonic_seconds) || exit 125;
    remaining=$(expr "$deadline" - "$now") || :;
    if [ "$remaining" -le 0 ]; then fetch_status=124; break; fi;
    attempts=$(expr "$attempts" + 1);
    if installer_run_bounded "$remaining" "$@" "$url" >"$headers" 2>&1; then
      success=true; break;
    else fetch_status=$?; fi;
    # Invalid options, local I/O and supervisor errors do not become valid by
    # retrying. Retry only potentially transient failures.
    case "$fetch_status" in 2|3|5|6|125|126|127|129|130|143) break ;; esac;
    if grep -Eq 'HTTP/[0-9.]+ (401|403|404|410)' "$headers"; then break; fi;
    [ "$attempt" -eq 3 ] || sleep 1;
  done;
  if [ "$success" != true ]; then
    # Never follow an existing diagnostic symlink or lose the downloader's
    # status behind a generic fetch error. The first failure owns the record.
    { printf 'status=%s\nattempts=%s\n' "$fetch_status" "$attempts"; cat "$headers"; } >"$temp";
    chmod 0600 "$temp" && mv -f "$temp" "${destination}.fetch-error" || :;
    source_error "repository HTTP fetch failed status=$fetch_status attempts=$attempts; response details: ${destination}.fetch-error" || :;
    exit "$fetch_status";
  fi;
  resolved=$(source_effective_url "$url" "$headers") || { source_error 'cannot determine the effective preseed URL'; exit 1; };
  chmod 0600 "$temp" && mv -f "$temp" "$destination" || exit 1;
  if [ -n "$effective" ]; then printf '%s\n' "$resolved" >"$effective"; chmod 0600 "$effective"; fi;
);
source_validate_relative() {
  # The payload validator runs before repo.env can be authenticated and
  # sourced. Keep this one space-bearing archive member in the immutable
  # bootstrap protocol; tools/build.py carries the matching allow-list entry.
  # All other paths stay space-free and repository-relative.
  case "${1:-}" in
    'hooks/target/etc/skel-desktop/.config/vivaldi/Local State') ;;
    ''|/*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/@+-]*) source_error 'unsafe repository-relative path'; return 1 ;;
  esac;
  case "/$1/" in */../*|*/./*|*//*) source_error 'repository path contains traversal or empty components'; return 1 ;; esac;
};
source_validate_selector_path() {
  source_selector_name=$1;
  source_selector_value=$2;
  [ -n "$source_selector_value" ] || {
    source_error "${source_selector_name} is unset in authenticated repo.env"; return 1;
  };
  source_validate_relative "$source_selector_value" || {
    source_error "${source_selector_name} is unsafe in authenticated repo.env"; return 1;
  };
};
source_transfer() (
  set -eu;
  base=$1; rel=$2; destination=$3;
  source_validate_relative "$rel" || exit 1;
  case "$base" in
    /*)
      candidate=${base%/}/$rel;
      [ -f "$candidate" ] && [ ! -L "$candidate" ] || { source_error "missing or non-regular repository file: $rel"; exit 1; };
      canonical=$(readlink -f "$candidate") || exit 1; root=$(readlink -f "$base") || exit 1;
      case "$canonical" in "${root%/}/"*) ;; *) source_error 'repository file escapes source root'; exit 1 ;; esac;
      mkdir -p "$(dirname "$destination")" || exit 1; temp=$(mktemp "${destination}.part.XXXXXX") || exit 1;
      trap 'rm -f "$temp"' 0; cp "$candidate" "$temp" && chmod 0600 "$temp" && mv -f "$temp" "$destination" || exit 1 ;;
    http://*|https://*) source_http_get "${base%/}/$rel" "$destination" ;;
    *) source_error 'unsupported repository source'; exit 1 ;;
  esac;
);
source_validate_target_suite() (
  set -eu;
  source_requested_suite=${INSTALLER_SUITE:-};
  case "$source_requested_suite" in forky|trixie) ;; *) source_error 'requested installer suite is unknown'; exit 1 ;; esac;
  case "${1:-}" in /*|http://*|https://*) ;; *) source_error 'unsupported target repository source'; exit 1 ;; esac;
);
source_resolve_seed() (
  set -eu;
  set -f;
  runtime=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}; boot=$runtime/bootstrap;
  installer_lifecycle_paths || { source_error 'unsafe or unavailable installer runtime root'; exit 1; };
  umask 077; mkdir -p "$boot" || exit 1;
  [ "$(installer_metadata_value "$boot" uid)" = "$(id -u)" ] || exit 1;
  [ "$(installer_metadata_value "$boot" mode)" = 700 ] || exit 1;
  if [ -s "$boot/seed.file" ] && [ -s "$boot/seed.url" ]; then source_error 'ambiguous persisted repository source'; exit 1; fi;
  for kind in file url; do
    if [ -s "$boot/seed.$kind" ]; then
      source_persisted_base=$(cat "$boot/seed.$kind");
      source_validate_target_suite "$source_persisted_base" || exit "$?";
      printf '%s\n' "$source_persisted_base";
      exit 0;
    fi;
  done;
  url=; file=;
  source_cmdline_value=$(source_cmdline) || exit "$?";
  for item in $source_cmdline_value; do
    case "$item" in
      url=*|preseed/url=*) value=${item#*=}; [ -z "$url" ] || [ "$url" = "$value" ] || { source_error 'conflicting url= parameters'; exit 1; }; url=$value ;;
      file=*|preseed/file=*) value=${item#*=}; [ -z "$file" ] || [ "$file" = "$value" ] || { source_error 'conflicting file= parameters'; exit 1; }; file=$value ;;
    esac;
  done;
  if [ -z "$url$file" ] && command -v debconf-get >/dev/null 2>&1; then url=$(debconf-get preseed/url 2>/dev/null || :); file=$(debconf-get preseed/file 2>/dev/null || :); fi;
  if [ -z "$url$file" ] && [ -r /var/run/preseed.last_location ]; then url=$(cat /var/run/preseed.last_location); fi;
  [ -z "$url" ] || [ -z "$file" ] || { source_error 'specify either file= or url=, not both'; exit 1; };
  case "$url" in /*) file=$url; url= ;; file://localhost/*) file=/${url#file://localhost/}; url= ;; file:///*) file=${url#file://}; url= ;; esac;
  if [ -n "$file" ]; then
    case "$file" in /*) ;; *) source_error 'file= must name an absolute preseed file'; exit 1 ;; esac;
    [ -f "$file" ] || { source_error 'file= does not name a readable preseed file'; exit 1; };
    case "/$file/" in */../*|*//*) source_error 'local frontend path contains traversal'; exit 1 ;; esac;
    file=$(readlink -f "$file");
    base=${file%/*}; [ -n "$base" ] || base=/;
    printf '%s\n' "$base" >"$boot/seed.file";
  elif [ -n "$url" ]; then
    # d-i gives /./ a special auto-install-root meaning. Preserve it before
    # URL normalization; it never relaxes class/member traversal validation.
    case "$url" in */./*)
      auto_root=${url%%/./*}; auto_leaf=${url#*/./};
      case "$auto_leaf" in */./*) source_error 'multiple auto-install root markers'; exit 1 ;; esac;
      printf '%s\n' "$auto_root" >"$boot/auto-install.root";
      url=$auto_root/$auto_leaf ;;
    esac;
    source_http_get "$url" "$boot/seed.document" "$boot/seed.effective-url" seed || exit "$?";
    resolved=$(cat "$boot/seed.effective-url");
    base=$(source_seed_base_from_effective "$resolved") || exit 1;
    printf '%s\n' "$base" >"$boot/seed.url";
  else source_error 'no repository source: pass file=, preseed/file=, url=, or preseed/url='; exit 1;
  fi;
  source_validate_target_suite "$base" || exit "$?";
  for state in "$boot/seed.file" "$boot/seed.url" "$boot/seed.effective-url"; do [ ! -f "$state" ] || chmod 0600 "$state"; done; printf '%s\n' "$base";
);
# END BOOTSTRAP CORE

# Payload-only helpers stay outside the single-line embedded bootstrap. A
# here-document needs its physical newlines and cannot be flattened into it.
source_validate_repo_env_selectors() {
  source_repo_env_path=$1
  while IFS= read -r source_selector_name || [ -n "$source_selector_name" ]; do
    [ -n "$source_selector_name" ] || continue
    source_selector_value=
    eval "source_selector_value=\${$source_selector_name:-}"
    case "$source_selector_name:$source_selector_value" in
      DIR_REPO_ROOT:.) ;;
      *) source_validate_selector_path "$source_selector_name" "$source_selector_value" || return 1 ;;
    esac
  done <<EOF
$(sed -n 's/^\(DIR_[A-Z0-9_]*\|FILE_[A-Z0-9_]*\)=.*/\1/p' "$source_repo_env_path")
EOF
}

source_normalize_base() (
  value=$1
  case "$value" in file://localhost/*) value=/${value#file://localhost/} ;; file:///*) value=${value#file://} ;; esac
  value=${value%%\#*}; value=${value%%\?*}
  case "$value" in */*.cfg) value=${value%/*} ;; esac
  while [ "$value" != / ] && [ "${value%/}" != "$value" ]; do value=${value%/}; done
  case "$value" in /*|http://*|https://*) ;; *) source_error 'unsupported repository base'; exit 1 ;; esac
  printf '%s\n' "$value"
)

source_verify_manifest() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c "$1"
  else
    busybox sha256sum -c "$1"
  fi
}

source_cache_root() (
  installer_lifecycle_paths || exit 1;
  base=$(source_normalize_base "$1") || exit 1
  key=$(printf '%s' "$base" | source_hash) || exit 1
  printf '%s/cache/seed/%s\n' "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}" "${key%% *}"
)

# One content snapshot per install. A release is built before it is served;
# modifying profiles/assets requires tools/build.py, which updates preseed pins.
source_prepare_payload() (
  set -eu
  umask 077
  base=$1; expected_archive=$2; expected_manifest=$3
  case "$expected_archive$expected_manifest" in *[!a-f0-9]*) source_error 'invalid payload digest'; exit 1 ;; esac
  [ "${#expected_archive}" -eq 64 ] && [ "${#expected_manifest}" -eq 64 ] || exit 1
  runtime=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
  root=$(source_cache_root "$base")
  marker=$runtime/bootstrap/payload.ready
  if [ -r "$marker" ] && [ "$(cat "$marker")" = "$expected_archive $expected_manifest $base" ]; then exit 0; fi
  mkdir -p "$runtime/bootstrap" || exit 1
  work=$(mktemp -d "$runtime/bootstrap/payload.XXXXXX") || exit 1
  trap 'rm -rf "$work"' 0
  trap 'exit 130' INT; trap 'exit 143' TERM
  source_transfer "$base" payload.manifest "$work/payload.manifest" || exit 1
  actual=$(source_hash <"$work/payload.manifest"); [ "${actual%% *}" = "$expected_manifest" ] || { source_error 'payload manifest differs from preseed pin; rebuild and publish atomically'; exit 1; }
  source_transfer "$base" payload.tar.gz "$work/payload.tar.gz" || exit 1
  actual=$(source_hash <"$work/payload.tar.gz"); [ "${actual%% *}" = "$expected_archive" ] || { source_error 'payload archive differs from preseed pin; rebuild and publish atomically'; exit 1; }
  # A bundle must contain regular files only; reject links, devices, directories,
  # duplicate entries and escaping paths BEFORE extraction into a private tree.
  tar -tzf "$work/payload.tar.gz" >"$work/members" || { source_error 'cannot list payload archive'; exit 1; }
  tar -tvzf "$work/payload.tar.gz" >"$work/types" || exit 1
  if grep -q '^[^-]' "$work/types"; then source_error 'payload contains a non-regular archive member'; exit 1; fi
  awk 'NF < 6 || $3 !~ /^[0-9]+$/ || $3 > 16777216 {exit 1} {count++; total += $3; if(count>10000 || total>268435456) exit 1}' "$work/types" || { source_error 'payload exceeds member/expanded-byte limits before extraction'; exit 1; }
  while IFS= read -r path; do source_validate_relative "$path" || exit 1; done <"$work/members"
  sort "$work/members" >"$work/members.sorted"
  sort -u "$work/members" >"$work/members.unique"
  cmp -s "$work/members.sorted" "$work/members.unique" || { source_error 'duplicate payload archive member'; exit 1; }
  # Keep the filename as the complete suffix after the fixed checksum field;
  # a valid payload member may contain spaces (the Vivaldi Local State file).
  awk -F '\t' 'NR==1 {if($0!="format=3") exit 1; next} NF!=3 || $1 !~ /^[0-9]+$/ || $1>16777216 || length($2)!=64 || $2 ~ /[^a-f0-9]/ {exit 1} {count++;total+=$1;if(count>10000 || total>268435456)exit 1; print $3}' "$work/payload.manifest" >"$work/expected" || { source_error 'malformed or excessive versioned payload manifest'; exit 1; }
  awk -F '\t' 'NR>1 {print $2 "  " $3}' "$work/payload.manifest" >"$work/checksums" || exit 1
  while IFS= read -r path; do source_validate_relative "$path" || exit 1; done <"$work/expected"
  sort "$work/expected" >"$work/expected.sorted"
  cmp -s "$work/expected.sorted" "$work/members.sorted" || { source_error 'payload member set differs from manifest'; exit 1; }
  mkdir "$work/tree" || exit 1
  tar -xzf "$work/payload.tar.gz" -C "$work/tree" || { source_error 'cannot extract payload archive'; exit 1; }
  case "${INSTALLER_SUITE:-}" in forky|trixie) ;; *) source_error 'requested suite is unavailable while validating the payload'; exit 1 ;; esac
  payload_suite_policy=$work/tree/catalog/compiled/suite-qualification.tsv
  [ -f "$payload_suite_policy" ] && [ ! -L "$payload_suite_policy" ] || { source_error 'authenticated payload lacks suite qualification metadata'; exit 1; }
  awk -F '\t' -v suite="$INSTALLER_SUITE" '
    NR == 1 { if ($0 != "format\t1") exit 2; next }
    NF != 5 || $1 !~ /^(forky|trixie)$/ || $2 !~ /^(desktop|server)$/ ||
      $3 !~ /^(source-candidate|blocked)$/ || $4 !~ /^[a-z0-9-]+$/ { exit 2 }
    $1 == suite { count++ }
    END { if (count != 2) exit 1 }
  ' "$payload_suite_policy" || { source_error 'payload suite qualification does not match the requested suite'; exit 1; }
  (cd "$work/tree"; source_verify_manifest ../checksums >../verification.log 2>&1) || { source_error 'payload file verification failed'; exit 1; }
  while IFS="$(printf '\t')" read -r size digest path; do
    [ "$size" != format=3 ] || continue
    actual_size=$(wc -c <"$work/tree/$path") || exit 1
    [ "$actual_size" -eq "$size" ] || { source_error 'payload member size differs from pinned manifest'; exit 1; }
  done <"$work/payload.manifest"
  payload_scripts_dir=${DIR_REPO_SCRIPTS:-scripts}
  payload_profiles_dir=${DIR_HOSTS_PROFILES:-hosts/profiles}
  payload_installer_dir=${DIR_HOSTS_INSTALLER:-hosts/installer}
  payload_common_dir=${DIR_SCRIPTS_COMMON:-${payload_scripts_dir}/common}
  [ -s "$work/tree/repo.env" ] && [ -s "$work/tree/${payload_common_dir}/lib.sh" ] || { source_error 'payload lacks installer entry files'; exit 1; }
  [ -f "$work/tree/${payload_profiles_dir}/shared.env" ] &&
    [ -f "$work/tree/${payload_profiles_dir}/desktop/shared-de.env" ] &&
    [ -f "$work/tree/${payload_profiles_dir}/server/shared-srv.env" ] ||
    { source_error 'payload lacks mandatory shared host profile environment'; exit 1; }
  for file in "$work/tree/${payload_scripts_dir}"/*/*.sh "$work/tree/${payload_installer_dir}"/*.env; do
    [ -f "$file" ] || continue
    /bin/sh -n "$file" || { source_error "invalid shell syntax: ${file#"$work/tree/"}"; exit 1; }
  done
  mkdir -p "$(dirname "$root")" || exit 1
  if [ -e "$root" ]; then rm -rf "$root" || exit 1; fi
  mv "$work/tree" "$root" || exit 1
  cp "$work/payload.manifest" "$runtime/bootstrap/payload.manifest" || exit 1
  printf '%s\n' "$expected_archive $expected_manifest $base" >"$marker"
  chmod 0600 "$marker"
)

source_fetch() (
  set -eu
  umask 077
  base=$(source_normalize_base "$1") || exit 1
  rel=$2; destination=$3; mode=${4:-0600}
  source_validate_relative "$rel" || exit 1
  case "$mode" in [0-7][0-7][0-7]|0[0-7][0-7][0-7]) ;; *) source_error 'invalid fetched file mode'; exit 1 ;; esac
  root=$(source_cache_root "$base") || exit 1
  cache=$root/$rel
  # A .tmpl is a source distinction, never an installed filename. Resolve only
  # regular snapshot members; never probe a moving remote source for aliases.
  case "$rel" in
    *.tmpl) ;;
    *)
      if [ -e "$cache.tmpl" ] || [ -L "$cache.tmpl" ]; then
        [ ! -e "$cache" ] && [ ! -L "$cache" ] &&
          [ -f "$cache.tmpl" ] && [ ! -L "$cache.tmpl" ] || {
            source_error "ambiguous or unsafe template source: $rel"; exit 1;
          }
        rel=$rel.tmpl; cache=$cache.tmpl
      fi
      ;;
  esac
  # Resolve an explicit local source only before a snapshot is authenticated.
  # Never probe moving remote aliases or bypass a verified payload.
  if [ ! -e "$cache" ] && [ ! -L "$cache" ] &&
     [ ! -f "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}/bootstrap/payload.ready" ]; then
    case "$base:$rel" in
      /*:*.tmpl) : ;;
      /*:*)
        if [ -e "${base%/}/$rel.tmpl" ] || [ -L "${base%/}/$rel.tmpl" ]; then
          [ ! -e "${base%/}/$rel" ] && [ ! -L "${base%/}/$rel" ] &&
            [ -f "${base%/}/$rel.tmpl" ] && [ ! -L "${base%/}/$rel.tmpl" ] || {
              source_error "ambiguous or unsafe local template: $rel"; exit 1;
            }
          rel=$rel.tmpl; cache=$root/$rel
        fi ;;
    esac
  fi
  [ ! -L "$cache" ] || { source_error "symlinked repository source: $rel"; exit 1; }
  if [ ! -f "$cache" ]; then
    # Once a snapshot is validated, never mix it with a moving remote branch.
    if [ -f "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}/bootstrap/payload.ready" ]; then source_error "file absent from validated payload: $rel"; exit 1; fi
    source_transfer "$base" "$rel" "$cache" || exit 1
  fi
  if [ ! -s "$cache" ]; then
    profile_dir=${DIR_CLASSES_PROFILE:-${DIR_CLASSES:-classes}/class-profile}
    case "$rel" in "$profile_dir"/*.cfg) ;; *) source_error "unexpected empty repository file: $rel"; exit 1 ;; esac
  fi
  [ "$cache" != "$destination" ] || { chmod "$mode" "$destination"; exit 0; }
  mkdir -p "$(dirname "$destination")" || exit 1
  temporary=$(mktemp "${destination}.part.XXXXXX") || exit 1
  trap 'rm -f "$temporary"' 0
  cp "$cache" "$temporary" && chmod "$mode" "$temporary" && mv -f "$temporary" "$destination" || exit 1
)

source_exists() (
  set -eu
  source_validate_relative "$2" || exit 1
  root=$(source_cache_root "$1") || exit 1
  if [ -f "$root/$2" ] || [ -f "$root/$2.tmpl" ]; then
    [ ! -L "$root/$2" ] && [ ! -L "$root/$2.tmpl" ] || exit 1
    [ ! -e "$root/$2" ] || [ ! -e "$root/$2.tmpl" ] || exit 1
    exit 0
  fi
  [ ! -f "${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}/bootstrap/payload.ready" ] || exit 1
  # Never create a logical alias inside the immutable source cache.
  mkdir -p "$(dirname "$root")" || exit 1
  probe=$(mktemp "${root}.exists.XXXXXX") || exit 1
  trap 'rm -f -- "$probe"' 0
  source_fetch "$1" "$2" "$probe" 0600
)

source_bootstrap() (
  set -eu
  base=$1; archive_digest=$2; manifest_digest=$3; requested_suite=${4:-${INSTALLER_SUITE:-}}
  # The generated preseed frontend passes the suite explicitly. Do not rely
  # on an environment exported by an earlier d-i shell: preseed/bootstrap is
  # launched as a separate process and must receive the identity at this
  # boundary before source or payload validation can inspect it.
  case "$requested_suite" in
    forky|trixie) INSTALLER_SUITE=$requested_suite; export INSTALLER_SUITE ;;
    *) source_error 'pinned suite is missing or unsupported'; exit 1 ;;
  esac
  runtime=${INSTALLER_RUNTIME_DIR:-/tmp/install-runtime}
  boot=$runtime/bootstrap
  source_prepare_payload "$base" "$archive_digest" "$manifest_digest" || exit 1
  # The payload is authenticated before repo.env is trusted.  Load its
  # selectors before choosing any further bootstrap source, so a customized
  # repository layout cannot silently fall back to a stale hard-coded path.
  source_fetch "$base" repo.env "$boot/repo.env" 0600 || {
    source_error 'authenticated payload is missing repo.env'; exit 1;
  }
  /bin/sh -n "$boot/repo.env" || {
    source_error 'authenticated repo.env has invalid shell syntax'; exit 1;
  }
  # shellcheck disable=SC1090
  . "$boot/repo.env" || {
    source_error 'cannot load authenticated repo.env'; exit 1;
  }
  source_validate_repo_env_selectors "$boot/repo.env" || exit 1
  source_validate_selector_path DIR_REPO_SCRIPTS "${DIR_REPO_SCRIPTS:-}" || exit 1
  source_validate_selector_path DIR_SCRIPTS_COMMON "${DIR_SCRIPTS_COMMON:-}" || exit 1
  source_validate_selector_path DIR_SCRIPTS_PRESEED "${DIR_SCRIPTS_PRESEED:-}" || exit 1
  source_validate_selector_path FILE_HOOKS_INSTALLER_DI_ENV "${FILE_HOOKS_INSTALLER_DI_ENV:-}" || exit 1
  for pair in FILE_COMMON_SOURCE:source.sh FILE_PRESEED_BOOTSTRAP_ENTRY:preseed-bootstrap-entry.sh FILE_PRESEED_APPLY:preseed-apply.sh FILE_PRESEED_GUARD_HOOK:guard-hook.sh; do
    source_selector=${pair%:*}
    source_rel=
    eval "source_rel=\${$source_selector:-}"
    source_validate_selector_path "$source_selector" "$source_rel" || exit 1
    source_name=${pair##*:}
    source_fetch "$base" "$source_rel" "$boot/$source_name" 0700 || {
      source_error "cannot stage authenticated bootstrap file: $source_rel"; exit 1;
    }
  done
  preseed_apply=$boot/preseed-apply.sh
  [ -f "$preseed_apply" ] && [ ! -L "$preseed_apply" ] && [ -x "$preseed_apply" ] || {
    source_error "authenticated payload did not create executable preseed runner: $preseed_apply"; exit 1;
  }
  "$boot/preseed-bootstrap-entry.sh" prepare-context "${FILE_INSTALLER_LOG:-/tmp/installer.log}" "$base" "$requested_suite" || { source_error "class/profile preflight failed; see ${FILE_INSTALLER_LOG:-/tmp/installer.log} (console 4)"; exit 1; }
  # All includes are local, absolute URIs: preseed.last_location can no longer
  # accidentally anchor them to a shortener, CDN host root or previous include.
  for include_selector in FILE_PRESEED_COMMON FILE_FRAGMENTS_NETWORK FILE_FRAGMENTS_PARTMAN FILE_FRAGMENTS_APT FILE_FRAGMENTS_FINISH; do
    eval "rel=\${$include_selector:-}"
    source_validate_selector_path "$include_selector" "$rel" || exit 1
    destination=$boot/includes/$rel
    source_fetch "$base" "$rel" "$destination" 0600 || {
      source_error "cannot stage authenticated preseed include: $rel"; exit 1;
    }
    printf 'file://%s\n' "$destination"
  done
  # preseed/run is a second-stage include.  Do not publish it until the
  # authenticated payload has staged the runner it names; otherwise d-i can
  # report a misleading "file could not be retrieved" before the real
  # payload/bootstrap diagnostic is visible.
  run_control=$boot/preseed-run.cfg
  run_control_tmp=$(mktemp "${run_control}.XXXXXX") || {
    source_error "cannot stage preseed/run control: $run_control"; exit 1;
  }
  trap 'rm -f "$run_control_tmp"' 0
  printf '%s\n' "d-i preseed/run string file://${preseed_apply}" >"$run_control_tmp" || {
    source_error "cannot write preseed/run control: $run_control"; exit 1;
  }
  chmod 0600 "$run_control_tmp" || {
    source_error "cannot protect preseed/run control: $run_control"; exit 1;
  }
  mv -f "$run_control_tmp" "$run_control" || {
    source_error "cannot publish preseed/run control: $run_control"; exit 1;
  }
  trap - 0
  : >"$boot/preflight.ok"
  printf 'file://%s\n' "$run_control"
)

# External vendor data is NOT part of the immutable repository snapshot. Keep
# this deliberately separate from source_fetch: a missing snapshot member must
# still fail closed. Its HTTPS scheme requirement is independent of the
# installer preseed transport's certificate policy.
source_fetch_external() (
  set -eu
  umask 077
  base=$1; rel=$2; destination=$3; mode=${4:-0600}
  case "$base" in https://*) ;; *) source_error 'external downloads require HTTPS'; exit 1 ;; esac
  source_validate_relative "$rel" || exit 1
  case "$mode" in 0600|0644) ;; *) source_error 'external data must not be executable'; exit 1 ;; esac
  mkdir -p "$(dirname "$destination")"
  scratch=$(mktemp -d "${destination}.external.XXXXXX") || exit 1
  trap 'rm -rf "$scratch"' 0
  trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP
  source_http_get "${base%/}/$rel" "$scratch/data" "" external || exit 1
  [ -s "$scratch/data" ] || { source_error 'empty external download'; exit 1; }
  chmod "$mode" "$scratch/data"
  mv -f "$scratch/data" "$destination"
)

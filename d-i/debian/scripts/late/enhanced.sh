#!/bin/sh
set -eu
printf '[late:enhanced] shared AppArmor/auditd configuration already applied for target=%s\n' "${1:-${TARGET_ROOT}}" >&2

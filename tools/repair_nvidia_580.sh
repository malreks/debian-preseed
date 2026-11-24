#!/bin/sh
# Repair an already-failed install with the package-owned Pika DKMS source.
# Does not download packages, rewrite vendor source, change repositories, load
# modules, or reboot.  Pika 580.196.07 already contains the Linux 7.2+
# compatibility implementation; this tool only asks DKMS to build/install it
# for the explicitly selected target kernel and then verifies the result.
set -eu

fatal() { printf 'fatal: %s\n' "$*" >&2; exit 1; }
usage() {
  printf 'Usage: sh %s TARGET_ROOT KERNEL_RELEASE\n' "$0" >&2
  printf 'Example from the installer: sh %s /target 7.2.4-x64v3-xanmod1\n' "$0" >&2
  exit 2
}
[ "$#" -eq 2 ] || usage
[ "$(id -u)" -eq 0 ] || fatal 'run as root in the installer or installed system'
case $1 in /*) ;; *) fatal 'TARGET_ROOT must be an absolute mounted path (or /)' ;; esac
TARGET=$(CDPATH= cd -- "$1" && pwd -P) || fatal 'target root is unavailable'
KERNEL=$2
case "$KERNEL" in ''|*[!A-Za-z0-9._+-]*) fatal 'invalid kernel release' ;; esac
[ -f "$TARGET/etc/debian_version" ] || fatal 'target is not an installed Debian root'
[ -s "$TARGET/lib/modules/$KERNEL/build/Module.symvers" ] || fatal "prepared $KERNEL headers/Module.symvers missing"
[ -c "$TARGET/dev/null" ] || fatal 'target /dev is not mounted'
[ -r "$TARGET/proc/self/status" ] || fatal 'target /proc is not mounted'
[ -d "$TARGET/sys/class" ] || fatal 'target /sys is not mounted'
[ -x "$TARGET/usr/sbin/dkms" ] || fatal 'packaged DKMS executable is missing'
# Pika's Debian-style package uses module nvidia and /usr/src/nvidia-VERSION.
# Do not replace /usr/sbin/dkms or extract a second patcher here.  If an
# interrupted older installer left its temporary diversion in place, the
# finish-install cleanup hook removes it before normal target operation.
DKMS_PACKAGE=nvidia-kernel-dkms-580
PACKAGE_VERSION=$(chroot "$TARGET" dpkg-query -W '-f=${Version}' "$DKMS_PACKAGE") ||
  fatal "Pika NVIDIA DKMS package is not installed: $DKMS_PACKAGE"
VERSION=${PACKAGE_VERSION#*:}
VERSION=${VERSION%%-*}
case "$VERSION" in 580.*) ;; *) fatal "unexpected DKMS package version: $PACKAGE_VERSION" ;; esac
case "$VERSION" in *[!0-9.]*|'580.') fatal 'invalid NVIDIA DKMS version' ;; esac
printf 'Building the FULL NVIDIA %s module set for %s (not the installer uname).\n' "$VERSION" "$KERNEL"
# Force the compile when repairing a failed package transaction. Every failure
# propagates; ordinary kernel/driver updates use DKMS's own non-forced path.
chroot "$TARGET" /usr/sbin/dkms build -m nvidia -v "$VERSION" -k "$KERNEL" --force
chroot "$TARGET" /usr/sbin/dkms install -m nvidia -v "$VERSION" -k "$KERNEL" --force
chroot "$TARGET" depmod -a "$KERNEL"
for module in nvidia nvidia-modeset nvidia-drm nvidia-uvm; do
  actual=$(chroot "$TARGET" modinfo -k "$KERNEL" -F version "$module")
  [ "$actual" = "$VERSION" ] || fatal "$module version is '$actual', expected '$VERSION'"
  vermagic=$(chroot "$TARGET" modinfo -k "$KERNEL" -F vermagic "$module")
  [ "${vermagic%% *}" = "$KERNEL" ] || fatal "$module kernel identity does not match $KERNEL: $vermagic"
done
# Finish pending package configuration only AFTER the explicit target build.
# This is not a replacement for the installer's remaining pkgsel/late phases.
chroot "$TARGET" /usr/bin/env DEBIAN_FRONTEND=noninteractive dpkg --configure -a
chroot "$TARGET" update-initramfs -u -k "$KERNEL"
STATUS=$(chroot "$TARGET" dpkg-query -W '-f=${Status}' "$DKMS_PACKAGE")
[ "$STATUS" = 'install ok installed' ] || fatal "$DKMS_PACKAGE status: $STATUS"
chroot "$TARGET" /usr/sbin/dkms status -m nvidia -v "$VERSION" -k "$KERNEL"
printf '%s\n' 'NVIDIA package/module repair completed. No GPU runtime test has been performed.'
printf '%s\n' 'For a failed Debian installer: return to its menu and retry package installation.'
printf '%s\n' 'Let the remaining installer/late hooks finish; do not treat this script as installation completion.'

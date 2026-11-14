#!__INSTALLER_PATH_DIR_USR__/bin/perl
# Retain the installed entrypoint while replacing the Sleek text-file daemon.
# The root-owned policy __INSTALLER_PATH_DIR_ETC__/labwc/plans.conf is read by the delegate.
use strict;
use warnings;
@ARGV == 0 or die "usage: labwc-plans.pl\n";
exec { '__INSTALLER_PATH_DIR_USR_LOCAL_LIBEXEC__/labwc-calendar-worker' }
    '__INSTALLER_PATH_DIR_USR_LOCAL_LIBEXEC__/labwc-calendar-worker', '--reminders';
die "labwc-plans: calendar reminder worker unavailable\n";

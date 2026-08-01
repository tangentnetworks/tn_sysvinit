#!/bin/bash
# SPDX-FileCopyrightText: (c) 2026 David Peter, Tangent Networks
# SPDX-License-Identifier: MIT

set -euo pipefail

readonly LOG_FILE="/var/log/boot"
readonly SYS_LOG="/var/log/syslog"

echo "+-------------------------------------------------------------------+"
echo "|     AUTOMATED LOG ANALYSIS & DIAGNOSTIC VERIFICATION TOOL         |"
echo "+-------------------------------------------------------------------+"
echo ""

PASSED=0
FAILED=0

check_ok() {
    echo "  [OK] $*"
    ((PASSED++)) || true
}

check_fail() {
    echo "  [FAIL] $*"
    ((FAILED++)) || true
}

echo "--> Verifying System State..."
if [ "$(cat /proc/1/comm 2> /dev/null)" = "init" ]; then
    check_ok "PID 1 is init (sysvinit)"
else
    check_fail "PID 1 is NOT sysvinit (Running: $(cat /proc/1/comm 2> /dev/null))"
fi

if ! dpkg -l systemd 2> /dev/null | grep -q "^ii"; then
    check_ok "systemd package successfully purged"
else
    check_fail "systemd package is still installed!"
fi

echo ""
echo "--> Verifying Automated Logging Service..."
if service rsyslog status > /dev/null 2>&1 || /etc/init.d/rsyslog status > /dev/null 2>&1; then
    check_ok "rsyslog service is running"
else
    check_fail "rsyslog service is inactive"
fi

if [ -s "$SYS_LOG" ]; then
    check_ok "$SYS_LOG exists and is non-empty"
else
    check_fail "$SYS_LOG missing or zero bytes"
fi

echo ""
echo "--> Verifying Runtime Mount Configurations..."
if grep -qs '[[:space:]]/run[[:space:]]' /etc/fstab; then
    check_ok "/run entry present in /etc/fstab"
else
    check_fail "/run entry missing from /etc/fstab"
fi

if grep -qs '[[:space:]]/run/lock[[:space:]]' /etc/fstab; then
    check_ok "/run/lock entry present in /etc/fstab"
else
    check_fail "/run/lock entry missing from /etc/fstab"
fi

echo ""
echo "--> Verifying Bootclean LSB Headers & Dependencies..."
if [ -f /etc/init.d/checkroot-bootclean.sh ]; then
    if grep -q '^# Required-Start:.*$local_fs' /etc/init.d/checkroot-bootclean.sh; then
        check_ok 'checkroot-bootclean.sh contains correct $local_fs LSB header'
    else
        check_fail 'checkroot-bootclean.sh missing $local_fs in Required-Start header'
    fi
else
    check_fail "/etc/init.d/checkroot-bootclean.sh missing"
fi

if [ -f /etc/init.d/.depend.boot ]; then
    check_ok "insserv dependency cache (.depend.boot) exists"
else
    check_fail "insserv dependency cache missing! Run insserv -v"
fi

echo ""
echo "--> Parsing Log Files for Failure Strings..."
if [ -f "$LOG_FILE" ]; then
    echo "  [OK] Scanning log file: $LOG_FILE"

    # Check for the specific bootclean failure string
    if grep -iq "checkroot-bootclean.*failed" "$LOG_FILE"; then
        check_fail "Found 'checkroot-bootclean.sh ... failed!' in $LOG_FILE"
    else
        check_ok "No checkroot-bootclean failure strings found in boot log"
    fi

    # Check for general failure patterns
    if grep -iq "failed!" "$LOG_FILE"; then
        check_fail "Found general 'failed!' pattern in $LOG_FILE:"
        echo "-------------------------------------------------------------------"
        grep -i "failed!" "$LOG_FILE" | head -n 10
        echo "-------------------------------------------------------------------"
    else
        check_ok "Zero 'failed!' strings detected in $LOG_FILE"
    fi
else
    check_fail "Log file $LOG_FILE does not exist! (Ensure bootlogd is running)"
fi

echo ""
echo "==================================================================="
echo " DIAGNOSTIC SUMMARY: $PASSED PASSED, $FAILED FAILED"
echo "==================================================================="
if [ "$FAILED" -eq 0 ]; then
    echo " RESULT: System boot health is 100% OK!"
else
    echo " RESULT: Errors detected. Run ./tn_sysvinit_autofix.sh to repair."
fi
echo "==================================================================="

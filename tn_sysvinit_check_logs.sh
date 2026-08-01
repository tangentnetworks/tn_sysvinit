#!/bin/bash
# SPDX-FileCopyrightText: (c) 2026 Tangent Networks
# SPDX-License-Identifier: MIT

set -euo pipefail

echo "+-------------------------------------------------------------------+"
echo "|     AUTOMATED LOG ANALYSIS & DIAGNOSTIC VERIFICATION TOOL         |"
echo "+-------------------------------------------------------------------+"

ERRORS=0
WARNINGS=0

info() { echo "  [OK] $*"; }
warn() {
    echo "  [WARN] $*"
    ((WARNINGS++))
}
fail() {
    echo "  [FAIL] $*"
    ((ERRORS++))
}

# System state verification
echo ""
echo "--> Verifying System State..."
PID1=$(ps -p 1 -o comm= 2>/dev/null || echo "unknown")
if [ "$PID1" = "init" ]; then
    info "PID 1 is init (sysvinit)"
else
    fail "PID 1 is $PID1 (expected init)"
fi

if ! dpkg -l systemd 2>/dev/null | grep -q "^ii"; then
    info "systemd package successfully purged"
else
    warn "systemd package is still present"
fi

# rsyslog status check
echo ""
echo "--> Verifying Automated Logging Service..."
if service rsyslog status >/dev/null 2>&1 || /etc/init.d/rsyslog status >/dev/null 2>&1; then
    info "rsyslog service is running"
else
    fail "rsyslog service is NOT running"
fi

if [ -s /var/log/syslog ]; then
    info "/var/log/syslog exists and is non-empty"
else
    warn "/var/log/syslog is missing or empty"
fi

# Mount configuration check
echo ""
echo "--> Verifying Runtime Mount Configurations..."
if grep -qs '[[:space:]]/run[[:space:]]' /etc/fstab; then
    info "/run entry present in /etc/fstab"
else
    fail "Missing /run entry in /etc/fstab"
fi

if grep -qs '[[:space:]]/run/lock[[:space:]]' /etc/fstab; then
    info "/run/lock entry present in /etc/fstab"
else
    fail "Missing /run/lock entry in /etc/fstab"
fi

# Boot clean link check
echo ""
echo "--> Verifying Bootclean Symlinks..."
if ls /etc/rcS.d/S*checkroot-bootclean* >/dev/null 2>&1; then
    info "checkroot-bootclean link found in /etc/rcS.d/"
else
    fail "Missing checkroot-bootclean link in /etc/rcS.d/"
fi

# Automated insserv check
echo ""
echo "--> Verifying insserv Boot Dependency Graph..."
if insserv -d >/tmp/insserv.log 2>&1; then
    info "insserv dependency graph compiled without fatal errors"
else
    fail "insserv dependency check failed:"
    cat /tmp/insserv.log | sed 's/^/      /'
fi

# Automated Log Parsing for Boot Errors
echo ""
echo "--> Parsing Log Files for Failure Strings..."

LOG_FILES=("/var/log/boot" "/var/log/syslog" "/var/log/messages")
FAIL_PATTERNS=(
    "failed!"
    "checkroot-bootclean.sh ... failed"
    "Cleaning up temporary files... /run /run/lock failed"
    "insserv: FATAL"
    "No inittab.d directory found"
)

FOUND_LOG_ERRORS=0
TMP_MATCH=$(mktemp /tmp/tn_pattern_match.XXXXXX)

# Ensure temp file is cleaned up on exit
trap 'rm -f "$TMP_MATCH"' EXIT

for log in "${LOG_FILES[@]}"; do
    if [ -f "$log" ] && [ -s "$log" ]; then
        info "Scanning log file: $log"
        for pattern in "${FAIL_PATTERNS[@]}"; do
            # Sanitize log stream through strings to strip binary NUL bytes & escape sequences
            if strings "$log" 2>/dev/null | grep -iF "$pattern" >"$TMP_MATCH" 2>&1; then
                fail "Found matching error pattern '$pattern' in $log:"
                head -n 5 "$TMP_MATCH" | sed 's/^/      /'
                FOUND_LOG_ERRORS=$((FOUND_LOG_ERRORS + 1))
            fi
        done
    fi
done

rm -f "$TMP_MATCH"

if [ "$FOUND_LOG_ERRORS" -eq 0 ]; then
    info "No boot clean or insserv failure patterns detected in log files!"
fi

# Summary
echo ""
echo "+-------------------------------------------------------------------+"
echo " Automated Analysis Results: $ERRORS Error(s), $WARNINGS Warning(s)"
echo "+-------------------------------------------------------------------+"

if [ "$ERRORS" -gt 0 ]; then
    echo " RESULT: FAILED - Review error items reported above."
    exit 1
else
    echo " RESULT: SUCCESS - System is fully configured, clean, and logged!"
    exit 0
fi

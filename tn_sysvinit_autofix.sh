#!/bin/bash
# SPDX-FileCopyrightText: (c) 2026 David Peter, Tangent Networks
# SPDX-License-Identifier: MIT

set -euo pipefail

readonly LOG_DIR="/var/lib/tn-sysvinit-migrate"
readonly FIX_LOG="${LOG_DIR}/autofix.log"

info() {
    echo "  [OK] $*"
    mkdir -p "$LOG_DIR"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" >>"$FIX_LOG" 2>/dev/null || true
}

warn() {
    echo "  [WARN] $*"
    mkdir -p "$LOG_DIR"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $*" >>"$FIX_LOG" 2>/dev/null || true
}

action() {
    echo "  [FIXING] $*"
    mkdir -p "$LOG_DIR"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ACTION: $*" >>"$FIX_LOG" 2>/dev/null || true
}

banner() {
    echo ""
    echo "  +-------------------------------------------------------------------+"
    echo "  | $1"
    echo "  +-------------------------------------------------------------------+"
    echo ""
}

fix_logging() {
    banner "1. LOGGING SUBSYSTEM INSPECTION"
    local needs_install=0

    if ! dpkg -l rsyslog 2>/dev/null | grep -q "^ii"; then
        warn "rsyslog is not installed."
        needs_install=1
    else
        info "rsyslog package present."
    fi

    if ! dpkg -l bootlogd 2>/dev/null | grep -q "^ii"; then
        warn "bootlogd is not installed."
        needs_install=1
    else
        info "bootlogd package present."
    fi

    if [ "$needs_install" -eq 1 ]; then
        action "Installing missing logging packages (rsyslog, bootlogd)..."
        apt-get update -qq
        apt-get install -y --no-install-recommends rsyslog bootlogd
    fi

    for logfile in /var/log/boot /var/log/syslog; do
        if [ ! -f "$logfile" ]; then
            action "Creating missing log file: $logfile"
            touch "$logfile"
            chmod 640 "$logfile"
        fi
    done

    if [ -f /etc/default/bootlogd ]; then
        if ! grep -qs '^BOOTLOGD_ENABLE=[Yy]' /etc/default/bootlogd; then
            action "Enabling bootlogd in /etc/default/bootlogd..."
            sed -i 's/^BOOTLOGD_ENABLE=.*/BOOTLOGD_ENABLE=Yes/' /etc/default/bootlogd
        else
            info "bootlogd already enabled in /etc/default/bootlogd."
        fi
    fi

    if ! service rsyslog status >/dev/null 2>&1; then
        action "Starting rsyslog service..."
        update-rc.d rsyslog defaults 2>/dev/null || true
        service rsyslog start || /etc/init.d/rsyslog start
    else
        info "rsyslog service actively running."
    fi
}

fix_fstab() {
    banner "2. FSTAB MOUNT INSPECTION"
    local fstab="/etc/fstab"

    if grep -qs '[[:space:]]/run[[:space:]]' "$fstab"; then
        info "/run entry present in /etc/fstab."
    else
        action "Adding /run tmpfs mount to /etc/fstab..."
        echo "tmpfs   /run        tmpfs   nodev,nosuid,size=20%,mode=755    0   0" >>"$fstab"
    fi

    if grep -qs '[[:space:]]/run/lock[[:space:]]' "$fstab"; then
        info "/run/lock entry present in /etc/fstab."
    else
        action "Adding /run/lock tmpfs mount to /etc/fstab..."
        echo "tmpfs   /run/lock   tmpfs   nodev,nosuid,noexec,size=5M       0   0" >>"$fstab"
    fi

    if grep -qs '[[:space:]]/tmp[[:space:]]' "$fstab"; then
        info "/tmp entry present in /etc/fstab."
    else
        action "Adding /tmp tmpfs mount to /etc/fstab..."
        echo "tmpfs   /tmp        tmpfs   nodev,nosuid,mode=1777            0   0" >>"$fstab"
    fi

    mount -a || true
}

fix_configs() {
    banner "3. INIT CONFIGURATION INSPECTION"
    local rcs="/etc/default/rcS"

    if [ -f "$rcs" ]; then
        for var in RAMRUN RAMLOCK RAMTMP; do
            if grep -qs "^${var}=yes" "$rcs"; then
                info "${var}=yes verified in /etc/default/rcS."
            else
                action "Setting ${var}=yes in /etc/default/rcS..."
                if grep -qs "^${var}=" "$rcs"; then
                    sed -i "s/^${var}=.*/${var}=yes/" "$rcs"
                else
                    echo "${var}=yes" >>"$rcs"
                fi
            fi
        done
    fi

    if [ ! -d /etc/inittab.d ]; then
        action "Creating missing /etc/inittab.d/ directory..."
        mkdir -p /etc/inittab.d
    else
        info "/etc/inittab.d/ directory present."
    fi
}

fix_insserv_bootclean() {
    banner "4. SURGICAL LSB HEADER PATCHING & INSSERV REBUILD"

    # Remove obsolete '-bootclean' references from init headers directly
    for s in /etc/init.d/mountall.sh /etc/init.d/checkroot.sh /etc/init.d/checkfs.sh; do
        if [ -f "$s" ] && grep -q "\-bootclean" "$s"; then
            action "Removing stale '-bootclean' dependency from LSB header in $s..."
            sed -i 's/-bootclean//g' "$s"
        fi
    done

    # Ensure checkroot-bootclean and mountall-bootclean provide bootclean
    for s in /etc/init.d/checkroot-bootclean.sh /etc/init.d/mountall-bootclean.sh; do
        if [ -f "$s" ] && ! grep -q "^# Provides:.*bootclean" "$s"; then
            action "Adding 'bootclean' to Provides in $s..."
            sed -i '/^# Provides:/ { /bootclean/! s/$/ bootclean/ }' "$s"
        fi
    done

    # Clear state dependency files to force fresh insserv calculation
    action "Purging stale insserv cache files..."
    rm -f /etc/init.d/.depend.boot /etc/init.d/.depend.start /etc/init.d/.depend.stop

    # Rebuild dependency graph
    action "Rebuilding insserv dependency graph..."
    if insserv -v; then
        info "insserv dependency graph successfully updated without errors!"
    else
        warn "insserv failed, executing dpkg-reconfigure..."
        dpkg-reconfigure -fnoninteractive initscripts || true
    fi
}

clear_bootlog() {
    if [ -f /var/log/boot ]; then
        action "Clearing stale /var/log/boot log buffer..."
        >/var/log/boot
        if service bootlogd status >/dev/null 2>&1; then
            service bootlogd restart || true
        fi
    fi
}

main() {
    banner "TN SYSVINIT AUTOFIX - INSPECT & REPAIR PIPELINE"

    if [ "$(id -u)" -ne 0 ]; then
        echo "Error: Must be run as root." >&2
        exit 1
    fi

    fix_logging
    fix_fstab
    fix_configs
    fix_insserv_bootclean
    clear_bootlog

    banner "AUTOFIX COMPLETE"
    echo "  Execution complete. Re-run ./tn_sysvinit_check_logs.sh to verify log state."
    echo ""
}

main "$@"

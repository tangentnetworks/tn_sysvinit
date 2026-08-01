#!/bin/bash

# SPDX-FileCopyrightText: (c) 2026 David Peter, Tangent Networks
# SPDX-License-Identifier: MIT

# +-------------------------------------------------------------------+
# |  TN SYSVINIT APPLIANCE -- PHASE 1                                 |
# |  PREPARATION SCRIPT                                               |
# |                                                                   |
# |  Detects encryption config, holds critical packages, installs     |
# |  sysvinit. Does NOT reboot. Halts at reboot gate for manual       |
# |  confirmation.                                                    |
# +-------------------------------------------------------------------+

set -euo pipefail

readonly STATE_DIR="/var/lib/tn-sysvinit-migrate"
readonly STATE_FILE="${STATE_DIR}/state.prep"
readonly LOG_FILE="${STATE_DIR}/phase1.log"
readonly CRYPTO_PROFILE="${STATE_DIR}/crypto.profile"

# --------------------------------------------
# Helpers
# --------------------------------------------

info() {
    local msg="$*"
    echo "  [OK] ${msg}"
    mkdir -p "$STATE_DIR"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: ${msg}" >> "$LOG_FILE" 2> /dev/null || true
}

warn() {
    local msg="$*"
    echo "  [!] ${msg}"
    mkdir -p "$STATE_DIR"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: ${msg}" >> "$LOG_FILE" 2> /dev/null || true
}

err() {
    local msg="$*"
    echo "  [FAIL] ${msg}" >&2
    mkdir -p "$STATE_DIR"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: ${msg}" >> "$LOG_FILE" 2> /dev/null || true
}

stage_completed() {
    [ -f "$STATE_FILE" ] && grep -q "^${1}$" "$STATE_FILE"
}

mark_complete() {
    mkdir -p "$STATE_DIR"
    echo "$1" >> "$STATE_FILE"
}

pause_confirm() {
    echo ""
    echo "  +-------------------------------------------------------------+"
    echo "  | $1"
    echo "  +-------------------------------------------------------------+"
    echo ""
    read -p "  Continue? (yes/no): " -r confirm
    [[ $confirm == "yes" ]] || {
        err "Aborted by user"
        return 1
    }
}

banner() {
    echo ""
    echo "  +-------------------------------------------------------------------+"
    echo "  | $1"
    echo "  +-------------------------------------------------------------------+"
    echo ""
}

run_stage() {
    local stage_name="$1"
    local stage_func="$2"

    if stage_completed "$stage_name"; then
        info "Stage $stage_name already completed, skipping"
        return 0
    fi

    echo ""
    echo "  + STAGE: $stage_name"

    if ! "$stage_func"; then
        echo "  + FAILED"
        err "Stage $stage_name FAILED"
        return 1
    fi

    mark_complete "$stage_name"
    echo "  + OK"
    info "Stage $stage_name completed"
}

# --------------------------------------------
# Encryption Detection Engine
# --------------------------------------------

detect_encryption() {
    local crypt_type="none"
    local crypt_devices=""
    local lvm_detected=0
    local luks_detected=0

    # Check for LVM on root
    if dmsetup info / > /dev/null 2>&1 || lsblk -no TYPE / 2> /dev/null | grep -q lvm; then
        lvm_detected=1
        info "LVM detected on root"
    fi

    # Check for LUKS encrypted volumes
    if [ -f /etc/crypttab ]; then
        if grep -qvE '^#|^[[:space:]]*$' /etc/crypttab; then
            luks_detected=1
            crypt_devices=$(grep -vE '^#|^[[:space:]]*$' /etc/crypttab | awk '{print $1}' | tr '\n' ',' | sed 's/,$//')
            info "LUKS devices found: $crypt_devices"
        fi
    fi

    # Check if root device itself is encrypted
    local root_src=$(findmnt -no SOURCE / 2> /dev/null || echo "")
    if [[ $root_src == /dev/mapper/* ]]; then
        luks_detected=1
        info "Root filesystem is encrypted: $root_src"
    fi

    # Determine profile
    if [ $lvm_detected -eq 1 ] && [ $luks_detected -eq 1 ]; then
        crypt_type="lvm_luks"
    elif [ $luks_detected -eq 1 ]; then
        crypt_type="luks"
    elif [ $lvm_detected -eq 1 ]; then
        crypt_type="lvm"
    fi

    mkdir -p "$STATE_DIR"
    cat > "$CRYPTO_PROFILE" << EOF
CRYPTO_TYPE=$crypt_type
LUKS_DETECTED=$luks_detected
LVM_DETECTED=$lvm_detected
CRYPT_DEVICES=$crypt_devices
DETECTED_AT="$(date '+%Y-%m-%d %H:%M:%S')"
EOF

    info "Encryption profile: $crypt_type"
    return 0
}

load_crypto_profile() {
    if [ -f "$CRYPTO_PROFILE" ]; then
        source "$CRYPTO_PROFILE"
    else
        CRYPTO_TYPE="unknown"
        LUKS_DETECTED=0
        LVM_DETECTED=0
        CRYPT_DEVICES=""
    fi
}

# --------------------------------------------
# Stages
# --------------------------------------------

stage_00_verify() {
    info "Checking prerequisites..."
    [ "$(id -u)" -eq 0 ] || {
        err "Must be root"
        return 1
    }
    [ -f /etc/debian_version ] || {
        err "Not Debian"
        return 1
    }
    info "Running on Debian $(cat /etc/debian_version)"

    for tool in apt-get dpkg systemctl update-initramfs; do
        command -v "$tool" > /dev/null || {
            err "Missing: $tool"
            return 1
        }
    done
    info "Required tools present"

    if systemctl is-system-running > /dev/null 2>&1; then
        info "Init system: systemd (confirmed)"
    else
        warn "Init system check inconclusive"
    fi

    return 0
}

stage_10_detect_crypto() {
    banner "ENCRYPTION DETECTION"
    detect_encryption
    load_crypto_profile

    case "$CRYPTO_TYPE" in
        none)
            info "No encryption detected - standard migration"
            ;;
        lvm)
            info "LVM-only setup - will protect LVM tools"
            ;;
        luks)
            info "LUKS encryption detected - will protect cryptsetup"
            ;;
        lvm_luks)
            info "LVM + LUKS detected - protecting both stacks"
            ;;
    esac

    return 0
}

stage_20_hold_critical() {
    banner "PACKAGE HOLD STRATEGY"
    info "Holding packages to prevent accidental removal..."

    # Always hold these
    local always_hold="linux-image-amd64 linux-headers-amd64 initramfs-tools"

    # Conditional holds
    local cond_hold=""
    if [ "$LUKS_DETECTED" -eq 1 ]; then
        cond_hold="cryptsetup cryptsetup-initramfs cryptsetup-bin"
    fi
    if [ "$LVM_DETECTED" -eq 1 ]; then
        cond_hold="$cond_hold lvm2 dmsetup"
    fi

    for pkg in $always_hold $cond_hold; do
        if dpkg -l "$pkg" 2> /dev/null | grep -q "^ii"; then
            apt-mark hold "$pkg" 2> /dev/null || true
            info "Held: $pkg"
        fi
    done

    return 0
}

stage_30_apt_update() {
    info "Updating package lists..."
    apt-get update -qq || return 1
    return 0
}

stage_40_remove_systemd_sysv() {
    banner "REMOVING SYSTEMD-SYV BRIDGE"
    info "Removing systemd-sysv (required before installing sysvinit)..."

    if dpkg -l systemd-sysv 2> /dev/null | grep -q "^ii"; then
        apt-get remove -y --allow-remove-essential systemd-sysv 2>&1 | grep -E 'Removing|^Setting' || true
        info "systemd-sysv removed"
    else
        info "systemd-sysv not installed"
    fi
    return 0
}

stage_50_install_initscripts() {
    banner "INSTALLING BOOT FRAMEWORK"
    info "Installing initscripts..."

    apt-get install -y --no-install-recommends initscripts 2>&1 | grep -E 'Installing|done' || true

    if [ ! -x /etc/init.d/checkroot.sh ] || [ ! -x /etc/init.d/mountkernfs.sh ]; then
        err "Boot scripts missing"
        return 1
    fi
    info "Boot scripts verified"
    return 0
}

stage_60_install_sysvinit() {
    banner "INSTALLING SYSVINIT PACKAGES"
    info "Installing sysvinit core (insserv FATAL warnings are expected)..."

    local pkgs="sysvinit-core sysv-rc insserv startpar orphan-sysvinit-scripts"
    pkgs="$pkgs busybox grub-common psmisc util-linux binutils"

    # Redirect apt-get output to /dev/null and only log errors
    if ! apt-get install -y --no-install-recommends $pkgs > /dev/null 2>&1; then
        err "Failed to install sysvinit packages"
        return 1
    fi

    # Suppress apt-mark output
    apt-mark manual $pkgs > /dev/null 2>&1 || true

    info "Sysvinit packages installed"
    return 0
}

stage_61_install_grub() {
    banner "BOOTLOADER CONFIGURATION"

    if [ "$LUKS_DETECTED" -eq 1 ]; then
        info "Installing BIOS-compatible GRUB (for encrypted systems)..."
        apt-get install -y --no-install-recommends grub-pc grub-pc-bin 2>&1 \
            | grep -E 'Removing|Installing|Setting up|Generating grub' || true
    else
        info "Bootloader already configured"
    fi
    return 0
}

stage_70_fix_boot_deps() {
    banner "FIXING BOOT DEPENDENCIES"
    info "Pre-fixing urandom and checkroot references..."

    # Fix init.d scripts BEFORE running insserv
    for script in /etc/init.d/*; do
        [ -f "$script" ] || continue
        if grep -qE '^# Required-(Start|Stop):.*\burandom\b' "$script" 2> /dev/null; then
            sed -i -E 's/^(# Required-(Start|Stop):.*)\burandom\b[[:space:]]*/\1/' "$script"
        fi
        if grep -qE '^# Required-(Start|Stop):.*\bcheckroot\b' "$script" 2> /dev/null; then
            if [ "$script" != "/etc/init.d/checkroot.sh" ]; then
                sed -i -E 's/^(# Required-(Start|Stop):.*)\bcheckroot\b[[:space:]]*/\1/' "$script"
            fi
        fi
    done

    info "Running insserv to build boot sequence..."
    insserv -d 2>&1 | grep -v "^insserv: FATAL" | grep -E '^insserv|^[^ ]' || true

    info "Boot sequence compiled"
    return 0
}

stage_80_rebuild_initramfs() {
    banner "INITRAMFS RECONSTRUCTION"

    local kernel_ver=$(uname -r)
    info "Current kernel: $kernel_ver"

    if [ "$LUKS_DETECTED" -eq 1 ]; then
        info "Configuring cryptsetup hook..."
        mkdir -p /etc/cryptsetup-initramfs
        if [ ! -f /etc/cryptsetup-initramfs/conf-hook ]; then
            echo 'CRYPTSETUP=y' > /etc/cryptsetup-initramfs/conf-hook
        elif ! grep -q '^CRYPTSETUP=' /etc/cryptsetup-initramfs/conf-hook; then
            echo 'CRYPTSETUP=y' >> /etc/cryptsetup-initramfs/conf-hook
        fi
        info "CRYPTSETUP hook enabled"
    fi

    info "Rebuilding initramfs for all kernels..."
    update-initramfs -u -k all 2>&1 | grep -E '^update-initramfs|Generating' || true

    if [ "$LUKS_DETECTED" -eq 1 ]; then
        info "Verifying cryptroot hook..."
        if command -v lsinitramfs > /dev/null 2>&1; then
            if lsinitramfs "/boot/initrd.img-$kernel_ver" 2> /dev/null | grep -q 'scripts/local-top/cryptroot'; then
                info "cryptroot hook verified in initramfs"
            else
                warn "cryptroot hook NOT found - will diagnose in phase 2"
            fi
        fi
    fi

    return 0
}

stage_90_final_check() {
    banner "PRE-REBOOT VERIFICATION"

    if ! dpkg -l sysvinit-core 2> /dev/null | grep -q "^ii"; then
        err "sysvinit-core not installed"
        return 1
    fi
    info "sysvinit-core installed and ready"

    info "Phase 1 preparation complete"
    return 0
}

# --------------------------------------------
# Main
# --------------------------------------------

main() {
    banner "PHASE 1: PREPARATION"
    echo "  Migration Log: $LOG_FILE"
    echo ""

    run_stage "00_verify" stage_00_verify || return 1
    run_stage "10_detect_crypto" stage_10_detect_crypto || return 1
    run_stage "20_hold_critical" stage_20_hold_critical || return 1
    run_stage "30_apt_update" stage_30_apt_update || return 1
    run_stage "40_remove_systemd_sysv" stage_40_remove_systemd_sysv || return 1
    run_stage "50_install_initscripts" stage_50_install_initscripts || return 1
    run_stage "60_install_sysvinit" stage_60_install_sysvinit || return 1
    run_stage "61_install_grub" stage_61_install_grub || return 1
    run_stage "70_fix_boot_deps" stage_70_fix_boot_deps || return 1
    run_stage "80_rebuild_initramfs" stage_80_rebuild_initramfs || return 1
    run_stage "90_final_check" stage_90_final_check || return 1

    # Reboot gate
    banner "REBOOT REQUIRED"
    echo "  Phase 1 preparation is complete. The system must reboot to switch"
    echo "  from systemd to sysvinit. After reboot, Phase 2 will purge systemd."
    echo ""
    echo "  Encryption Profile: $CRYPTO_TYPE"
    echo ""

    pause_confirm "Reboot now to activate sysvinit?" || return 1

    info "Initiating reboot..."
    sleep 2
    systemctl reboot
}

main "$@"

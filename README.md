# TN Sysvinit Appliance -- Migration Guide

**Debian systemd --> sysvinit Migration Toolkit**

*Version 1.0 | 2026-07-31 | MIT License | © 2026 Tangent Networks*

---

## 🎯 Overview

This toolkit migrates **Debian-based systems from systemd to sysvinit** with full support for **LUKS encryption** and **LVM configurations**. The migration is split into **three phases** to ensure safety, provide recovery options, and maintain data integrity.

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  PHASE 1: PREP  │────>│   REBOOT GATE    │────>│  PHASE 2: MIGRATE│
│  (systemd)      │     │                  │     │  (sysvinit)     │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                                                   │
                                                   ↓
                                            ┌─────────────────┐
                                            │ PHASE 3: VERIFY │
                                            │  (anytime)      │
                                            └─────────────────┘
```

### Key Features

- ✅ **Automatic encryption detection** (LUKS, LVM, LUKS+LVM)
- ✅ **Safe package removal** with simulation before purge
- ✅ **Critical package protection** (kernel, cryptsetup, LVM, initramfs)
- ✅ **Idempotent stages** -- safe to re-run
- ✅ **Non-destructive verification** (Phase 3)
- ✅ **Comprehensive logging** to `/var/lib/tn-sysvinit-migrate/`

---

## 📋 Prerequisites

### Supported Systems

- **Operating System:** Debian (tested on Debian 13/Trixie)
- **Architecture:** amd64 (x86\_64)
- **Init System:** Currently running systemd
- **Package Manager:** apt/dpkg

### Required Privileges

- **Root access** is mandatory -- all scripts must run as root
- The scripts will fail immediately if not run as root

### Disk Space

- Minimum **500MB free** in `/boot` for initramfs rebuilds
- Minimum **2GB free** in `/` for package operations

### Network

- **Internet access** required for package installation (Phase 1)
- No network required for Phase 2 or Phase 3

---

## 💾 Installation

### 1. Download the Scripts

Download all three scripts to a working directory (e.g., `~/sysvinit-migrate/`):

```bash
mkdir -p ~/sysvinit-migrate
cd ~/sysvinit-migrate

# Download the three scripts
wget https://example.com/path/to/tn_sysvinit_prep.sh
wget https://example.com/path/to/tn_sysvinit_migrate.sh
wget https://example.com/path/to/tn_sysvinit_verify.sh

# OR copy them manually from your source
```

### 2. Set Permissions

```bash
chmod +x tn_sysvinit_prep.sh tn_sysvinit_migrate.sh tn_sysvinit_verify.sh
```

### 3. Verify Integrity (Optional)

Check the scripts have valid SPDX headers and MIT license:

```bash
head -5 tn_sysvinit_*.sh
```

Expected output for each:

```
#!/bin/bash
# SPDX-FileCopyrightText: (c) 2026 David Peter, Tangent Networks
# SPDX-License-Identifier: MIT
```

---

## 🚀 Migration Process

---

## Phase 1: Preparation Script (`tn_sysvinit_prep.sh`)

**Runs on:** systemd (before reboot)  
**Purpose:** Prepares the system for migration  
**Duration:** \~2-5 minutes  
**Destructive:** No -- can be safely re-run  
**State file:** `/var/lib/tn-sysvinit-migrate/state.prep`  
**Log file:** `/var/lib/tn-sysvinit-migrate/phase1.log`

### What It Does


| Stage                    | Description                                            | Critical?      |
| ------------------------ | ------------------------------------------------------ | -------------- |
| `00_verify`              | Checks root access, Debian version, required tools     | ✅ Yes          |
| `10_detect_crypto`       | Detects LUKS/LVM configuration, creates crypto.profile | ✅ Yes          |
| `20_hold_critical`       | Places apt holds on essential packages                 | ✅ Yes          |
| `30_apt_update`          | Updates package lists                                  | ⚠️ No          |
| `40_remove_systemd_sysv` | Removes systemd-sysv bridge package                    | ✅ Yes          |
| `50_install_initscripts` | Installs initscripts (checkroot.sh, mountkernfs.sh)    | ✅ Yes          |
| `60_install_sysvinit`    | Installs sysvinit-core and dependencies                | ✅ Yes          |
| `61_install_grub`        | Installs BIOS-compatible GRUB (if LUKS detected)       | ⚠️ Conditional |
| `70_fix_boot_deps`       | Fixes init.d script dependencies, runs insserv         | ✅ Yes          |
| `80_rebuild_initramfs`   | Rebuilds initramfs with cryptroot hook (if needed)     | ✅ Yes          |
| `90_final_check`         | Verifies sysvinit-core is installed                    | ✅ Yes          |


### Encryption Detection

The script automatically detects your storage configuration:


| Configuration     | Detection Method                                | Protected Packages                                 |
| ----------------- | ----------------------------------------------- | -------------------------------------------------- |
| **No encryption** | No LUKS/LVM detected                            | linux-image, linux-headers, initramfs-tools        |
| **LUKS only**     | `/etc/crypttab` entries or `/dev/mapper/*` root | + cryptsetup, cryptsetup-initramfs, cryptsetup-bin |
| **LVM only**      | Active LVM volumes via `dmsetup` or `lsblk`     | + lvm2, dmsetup                                    |
| **LUKS + LVM**    | Both detected                                   | + both stacks                                      |


The detection results are saved to `/var/lib/tn-sysvinit-migrate/crypto.profile`.

### Running Phase 1

```bash
sudo ./tn_sysvinit_prep.sh
```

### Expected Output

```
  +-------------------------------------------------------------------+
  |          TN SYSVINIT APPLIANCE - PHASE 1                           |
  |                    PREPARATION SCRIPT                             |
  +-------------------------------------------------------------------+

  Migration Log: /var/lib/tn-sysvinit-migrate/phase1.log

  + STAGE: 00_verify
  [OK] Running on Debian 13.6
  [OK] Required tools present
  [OK] Init system: systemd (confirmed)
  + OK

  + STAGE: 10_detect_crypto
  +-------------------------------------------------------------------+
  | ENCRYPTION DETECTION                                              |
  +-------------------------------------------------------------------+
  [OK] LUKS encryption detected
  [OK] Encryption profile: luks
  + OK

  + STAGE: 20_hold_critical
  +-------------------------------------------------------------------+
  | PACKAGE HOLD STRATEGY                                             |
  +-------------------------------------------------------------------+
  [OK] Holding packages to prevent accidental removal...
  [OK] Held: linux-image-amd64
  [OK] Held: linux-headers-amd64
  [OK] Held: initramfs-tools
  [OK] Held: cryptsetup
  [OK] Held: cryptsetup-initramfs
  + OK
  ... (additional stages) ...

  +-------------------------------------------------------------------+
  | REBOOT REQUIRED                                                   |
  +-------------------------------------------------------------------+

  Phase 1 preparation is complete. The system must reboot to switch
  from systemd to sysvinit. After reboot, Phase 2 will purge systemd.

  Encryption Profile: luks

  +-------------------------------------------------------------+
  | Reboot now to activate sysvinit?                              |
  +-------------------------------------------------------------+

  Continue? (yes/no):
```

### At the Reboot Prompt

- Type **`yes`** to reboot immediately into sysvinit
- Type **`no`** to cancel and reboot manually later
- **Do NOT skip the reboot** -- Phase 2 requires sysvinit to be running

---

## Phase 2: Migration Script (`tn_sysvinit_migrate.sh`)

**Runs on:** sysvinit (after reboot from Phase 1)  
**Purpose:** Verifies the init switch and safely removes systemd  
**Duration:** \~1-2 minutes  
**Destructive:** Yes -- removes systemd packages  
**State file:** `/var/lib/tn-sysvinit-migrate/state.migration`  
**Log file:** `/var/lib/tn-sysvinit-migrate/phase2.log`  
**Simulation log:** `/var/lib/tn-sysvinit-migrate/purge-simulation.log`

### What It Does


| Stage                 | Description                                                   | Critical? |
| --------------------- | ------------------------------------------------------------- | --------- |
| `00_verify_init`      | Confirms PID 1 is `init` (sysvinit), not systemd              | ✅ Yes     |
| `10_load_crypto`      | Loads encryption profile from Phase 1                         | ✅ Yes     |
| `20_verify_cryptroot` | **Verifies LUKS decryption is working** (if applicable)       | ✅ Yes     |
| `30_purge_simulation` | **Simulates** systemd removal to catch problems               | ✅ Yes     |
| `40_purge_systemd`    | **Actually removes** systemd and related packages             | ✅ Yes     |
| `50_finalize`         | Runs dependency checks, removes orphans, sets apt preferences | ✅ Yes     |
| `60_verify_complete`  | Final verification of migration                               | ✅ Yes     |


### Cryptroot Verification (Key Innovation)

**Old approach (problematic):** Check if `lsinitramfs` can find the cryptroot hook in the initramfs image.

**New approach (pragmatic):** 

- If the system booted successfully to sysvinit with an encrypted root
- Then **cryptroot is provably working**
- No need for tool-based verification

The script checks:

```bash
# Is root mounted from an encrypted device?
root_src=$(findmnt -no SOURCE / 2>/dev/null || echo "")
if [[ "$root_src" == /dev/mapper/* ]]; then
    # Root is encrypted and mounted -> cryptroot works
    info "LUKS decryption provably occurred in initramfs"
fi
```

This is **faster, more reliable, and production-worthy** than parsing initramfs contents.

### Package Removal Safety

Before actually removing systemd, the script **simulates** the purge:

```bash
apt-get -s purge --allow-remove-essential systemd systemd-sysv ...
```

It then checks the simulation output for **critical packages** that must NOT be removed:

- `linux-image-*`, `linux-headers-*`, `linux-modules-*`
- `openssh-server`
- `udev`
- `grub-*`
- `cryptsetup*`, `initramfs-tools`
- `busybox`, `util-linux`, `psmisc`

**If any critical package would be removed, the script FAILS SAFELY** and refuses to proceed.

### Purged Packages

The following systemd-related packages are removed:

- `systemd`
- `systemd-sysv`
- `systemd-cryptsetup`
- `systemd-standalone-sysusers`
- `systemd-timesyncd`
- `dbus-user-session`
- `libnss-systemd`
- `libpam-systemd`

### Running Phase 2

After the system reboots from Phase 1, log in and run:

```bash
sudo ./tn_sysvinit_migrate.sh
```

### Expected Output

```
  +-------------------------------------------------------------------+
  |          TN SYSVINIT APPLIANCE - PHASE 2                           |
  |              MIGRATION SCRIPT                                     |
  +-------------------------------------------------------------------+

  Migration Log: /var/lib/tn-sysvinit-migrate/phase2.log
  Simulation Log: /var/lib/tn-sysvinit-migrate/purge-simulation.log

  + STAGE: 00_verify_init
  +-------------------------------------------------------------------+
  | INIT SYSTEM VERIFICATION                                          |
  +-------------------------------------------------------------------+
  [OK] PID 1: init
  [OK] Running on sysvinit
  [OK] Init target verified: /lib/sysvinit/init
  + OK

  + STAGE: 10_load_crypto
  +-------------------------------------------------------------------+
  | LOADING ENCRYPTION PROFILE                                        |
  +-------------------------------------------------------------------+
  [OK] Profile: luks
  [OK] LUKS: enabled
  + OK

  + STAGE: 20_verify_cryptroot
  +-------------------------------------------------------------------+
  | CRYPTROOT VERIFICATION                                            |
  +-------------------------------------------------------------------+
  [OK] LUKS was configured in Phase 1
  [OK] System booted to sysvinit
  [OK] LUKS decryption provably occurred in initramfs
  + OK

  + STAGE: 30_purge_simulation
  +-------------------------------------------------------------------+
  | SYSTEMD REMOVAL SAFETY CHECK                                      |
  +-------------------------------------------------------------------+
  [OK] Simulating purge to detect problems...
  [OK] Safe to remove 12 systemd-related packages
  + OK

  + STAGE: 40_purge_systemd
  +-------------------------------------------------------------------+
  | PURGING SYSTEMD                                                   |
  +-------------------------------------------------------------------+
  [OK] Removing systemd packages...
  [OK] Systemd purged
  + OK

  + STAGE: 50_finalize
  +-------------------------------------------------------------------+
  | FINALIZING MIGRATION                                              |
  +-------------------------------------------------------------------+
  [OK] Running dependency check...
  [OK] Removing orphaned packages...
  [OK] Creating apt preferences to prevent systemd reinstall...
  + OK

  + STAGE: 60_verify_complete
  +-------------------------------------------------------------------+
  | MIGRATION VERIFICATION                                            |
  +-------------------------------------------------------------------+
  [OK] systemd completely removed
  [OK] PID 1: init
  [OK] Kernel: 6.12.96+deb13-amd64
  [OK] /sbin/init: /lib/sysvinit/init
  + OK

  +-------------------------------------------------------------------+
  | MIGRATION COMPLETE                                                |
  +-------------------------------------------------------------------+

  Sysvinit migration finished successfully.
  Run tn_sysvinit_verify.sh to confirm system health.
```

### After Phase 2 Completes

- **Do NOT reboot again** -- the migration is complete
- The system is now running sysvinit with systemd removed
- Run Phase 3 to verify everything is healthy

---

## Phase 3: Verification Script (`tn_sysvinit_verify.sh`)

**Runs on:** sysvinit (anytime after Phase 2)  
**Purpose:** Non-destructive health check of the migrated system  
**Duration:** \~5-10 seconds  
**Destructive:** No -- read-only checks only  
**Log file:** `/var/lib/tn-sysvinit-migrate/verification-report.txt`

### What It Does

Phase 3 performs **comprehensive, non-destructive checks** to verify the migration was successful. It checks:

#### 1. Init System

- PID 1 is `init` (sysvinit)
- `/sbin/init` symlink points to sysvinit
- systemd package is removed
- sysvinit-core is installed

#### 2. Boot Framework

- Required init.d scripts exist (`checkroot.sh`, `mountkernfs.sh`)
- Runlevel directories exist (`/etc/rc*.d/`)
- `insserv` tool is available

#### 3. Kernel &amp; Initramfs

- Running kernel version
- Initramfs exists for current kernel
- Initramfs contains essential files (`init`, modules)
- GRUB can locate the kernel

#### 4. Encryption (if applicable)

- Loads encryption profile from Phase 1
- Verifies `/etc/crypttab` entries (if LUKS)
- Checks cryptsetup hook configuration
- **Verifies root is mounted from encrypted device**
- Checks LVM devices (if LVM)

#### 5. Critical Packages

- All essential packages are installed
- Kernel image packages are held by apt
- cryptsetup packages are held (if LUKS)
- LVM packages are held (if LVM)

#### 6. Filesystem

- Root (`/`) and boot (`/boot`) mounts are valid
- `fsck` is available for filesystem checks

#### 7. Log Analysis

- Scans Phase 1 and Phase 2 logs for errors
- Reports any warnings or failures

### Running Phase 3

```bash
sudo ./tn_sysvinit_verify.sh
```

Run this **immediately after Phase 2**, and optionally at any time afterward to check system health.

### Expected Output (Healthy System)

```
  +-------------------------------------------------------------------+
  |      SYSVINIT MIGRATION VERIFICATION TOOL                        |
  |                                                           |
  |   Non-destructive system health check (read-only)                |
  +-------------------------------------------------------------------+

  +-------------------------------------------------------------------+
  | INIT SYSTEM                                                       |
  +-------------------------------------------------------------------+
  [OK] PID 1 is sysvinit
  [OK] /sbin/init target: /lib/sysvinit/init
  [OK] systemd package removed
  [OK] sysvinit-core installed

  +-------------------------------------------------------------------+
  | ENCRYPTION CONFIGURATION                                          |
  +-------------------------------------------------------------------+
  [OK] Encryption profile: luks
  [OK] LUKS encryption detected in profile
  [OK] /etc/crypttab contains 1 entries
  [OK] cryptsetup packages held by apt
  [OK] CRYPTSETUP hook enabled in conf-hook
  [OK] Root encrypted via LUKS: /dev/mapper/netdog--vg-root
  [OK] LUKS decryption active (cryptroot working)

  +-------------------------------------------------------------------+
  | CRITICAL PACKAGES                                                 |
  +-------------------------------------------------------------------+
  [OK] initramfs-tools installed
  [OK] busybox installed
  [OK] util-linux installed
  [OK] psmisc installed
  [OK] grub-common installed
  [OK] linux-image packages held
  [OK] 1 kernel image package(s) installed

  +-------------------------------------------------------------------+
  | VERIFICATION SUMMARY                                              |
  +-------------------------------------------------------------------+

  Passed: 28
  Warned: 0
  Failed: 0
  -------------
  Total:  28

  OK SYSTEM HEALTHY - No issues detected

  Detailed report: /var/lib/tn-sysvinit-migrate/verification-report.txt
```

### Verification Summary


| Status            | Meaning                | Action Required                            |
| ----------------- | ---------------------- | ------------------------------------------ |
| OK SYSTEM HEALTHY | All checks passed      | None -- migration successful                |
| Warnings present  | Some checks warned     | Review warnings, but system is functional  |
| FAILED            | Critical checks failed | Review failures and take corrective action |


---

## 📊 Script Comparison


| Feature              | tn\_sysvinit\_prep.sh   | tn\_sysvinit\_migrate.sh | tn\_sysvinit\_verify.sh |
| -------------------- | ----------------------- | ------------------------ | ----------------------- |
| **Phase**            | 1 (Preparation)         | 2 (Migration)            | 3 (Verification)        |
| **Runs on**          | systemd                 | sysvinit                 | sysvinit                |
| **When to run**      | Before reboot           | After reboot             | Anytime after Phase 2   |
| **Destructive**      | No                      | Yes                      | No                      |
| **Reboots system**   | Yes (with confirmation) | No                       | No                      |
| **Idempotent**       | Yes                     | Yes                      | Yes                     |
| **Duration**         | \~2-5 min               | \~1-2 min                | \~5-10 sec              |
| **Requires network** | Yes                     | No                       | No                      |


---

## 📁 State &amp; Log Files

All migration state and logs are stored in `/var/lib/tn-sysvinit-migrate/`:

```
/var/lib/tn-sysvinit-migrate/
├── state.prep              # Phase 1: Completed stage markers
├── state.migration         # Phase 2: Completed stage markers
├── phase1.log              # Phase 1: Detailed execution log
├── phase2.log              # Phase 2: Detailed execution log
├── verification-report.txt # Phase 3: Verification results
├── crypto.profile          # Auto-detected encryption config
└── purge-simulation.log    # Phase 2: apt purge simulation
```

---

## ⚠️ Error Recovery

### If Phase 1 Fails

Phase 1 is **idempotent** -- you can safely re-run it:

```bash
sudo ./tn_sysvinit_prep.sh
```

- It will **skip completed stages** and continue from where it failed
- Check `/var/lib/tn-sysvinit-migrate/phase1.log` for error details

### If Boot Fails After Phase 1

If the system won't boot into sysvinit after Phase 1:

1. **Boot into GRUB recovery mode** (hold Shift during boot)
2. **Select previous kernel** or **recovery mode**
3. **Log in as root**
4. **Check the logs:**
  ```bash
   cat /var/lib/tn-sysvinit-migrate/phase1.log
  ```
5. **Re-run Phase 1** to rebuild initramfs:
  ```bash
   sudo ./tn_sysvinit_prep.sh
  ```
6. **Reboot and try again**

### If Phase 2 Fails

Phase 2 is also **idempotent**:

```bash
sudo ./tn_sysvinit_migrate.sh
```

- Check `/var/lib/tn-sysvinit-migrate/phase2.log` for errors
- The **purge simulation** (stage 30) will catch most problems before any changes are made
- If the simulation fails, it means removing systemd would break your system -- **do not force it**

### If Cryptroot Hook is Missing

If Phase 3 reports that the cryptroot hook is not working:

```bash
# Rebuild initramfs with cryptroot hook
sudo update-initramfs -u -k all

# Verify it was added
lsinitramfs /boot/initrd.img-$(uname -r) 2>/dev/null | grep -q cryptroot

# If still missing, re-run Phase 2
sudo ./tn_sysvinit_migrate.sh
```

### If systemd Keeps Reinstalling

The apt preferences should prevent this, but if systemd gets pulled in:

```bash
# Check current preference
sudo apt-cache policy systemd
# Should show: Pin-Priority: -1

# Manually reset it
sudo apt-get remove --purge systemd*

# Re-apply holds
sudo apt-mark hold cryptsetup cryptsetup-initramfs lvm2
```

---

## 🔍 Troubleshooting

### Q: How do I know if the migration worked?

**Run Phase 3:**

```bash
sudo ./tn_sysvinit_verify.sh
```

If you see `OK SYSTEM HEALTHY`, your migration was successful.

### Q: Can I downgrade back to systemd?

**Not easily.** The migration removes systemd packages and creates apt preferences to prevent reinstall. To restore systemd:

```bash
# 1. Remove apt preferences
sudo rm /etc/apt/preferences.d/00-no-systemd

# 2. Reinstall systemd
sudo apt-get install systemd systemd-sysv

# 3. Reboot (init-switch will happen automatically)
sudo reboot
```

Warning: This is **untested** and may have issues. Only attempt if absolutely necessary.

### Q: What if I have encrypted LVM?

**The toolkit handles this automatically.** If both LVM and LUKS are detected, all phases will protect and verify both stacks.

### Q: What if I use a custom LUKS key file?

Ensure it's referenced in `/etc/crypttab`:

```
vda3_crypt UUID=18f55688-3af4-43bd-918b-68608cab7ac0 /path/to/keyfile luks,discard
```

Phase 1 will automatically include it in the initramfs.

### Q: Can I use this on non-Debian systems?

**No.** The toolkit is specifically for Debian-based systems. It checks for `/etc/debian_version` and uses `apt-get`/`dpkg`.

### Q: Will this work on Ubuntu?

**Maybe, but not officially supported.** Ubuntu has similar structures but may have additional systemd dependencies. Proceed with extreme caution.

---

## 🛡️ Safety Guarantees

The toolkit will **NEVER**:


| Guarantee                    | Implementation                                                             |
| ---------------------------- | -------------------------------------------------------------------------- |
| Remove kernel packages       | Holds `linux-image-*`, `linux-headers-*`                                   |
| Remove cryptsetup            | Holds `cryptsetup*`, `cryptsetup-initramfs` (if LUKS detected)             |
| Remove LVM tools             | Holds `lvm2`, `dmsetup` (if LVM detected)                                  |
| Remove essential boot tools  | Holds `initramfs-tools`, `busybox`, `grub*`, `openssh-server`              |
| Remove without simulation    | Runs `apt-get -s purge` first, fails if critical packages would be removed |
| Proceed without confirmation | Requires explicit `yes` at reboot gate in Phase 1                          |


---

## 🏗️ Architecture Notes

### Why Three Scripts?

A single monolithic script has problems:

1. Cannot verify init switch (PID 1) while running under systemd
2. No recovery option if network is down
3. Reboot loses state
4. No post-reboot diagnostics

**Three-phase approach:**

- Phase 1 runs under systemd, stops before reboot
- Phase 2 runs under sysvinit, can verify init switch
- Phase 3 is non-destructive, can run anytime
- Each phase is independently idempotent

### Why Hold Packages?

`apt-get purge` doesn't check what's really needed. By holding critical packages, we prevent accidental removal.

### Why Fix Boot Dependencies First?

The `insserv` tool builds a dependency graph of init.d scripts. If scripts reference non-existent services (like `urandom`), `insserv` fails fatally. Solution: pre-fix scripts before running `insserv`.

### Why Pragmatic Cryptroot Verification?

**Over-engineering:** Using tools like `lsinitramfs` to verify cryptroot is fragile (tools can have bugs).

**Pragmatism:** If the system booted to sysvinit with encrypted root, cryptroot **must be working**. Just check if root is mounted from `/dev/mapper/*`. This is faster, more reliable, and production-worthy.

---

## 📋 Migration Checklist

- [ ] Download all three scripts to a directory
- [ ] Make scripts executable (`chmod +x`)
- [ ] Verify scripts have MIT license headers
- [ ] Run Phase 1: `sudo ./tn_sysvinit_prep.sh`
- [ ] Confirm reboot at prompt (type `yes`)
- [ ] System reboots into sysvinit
- [ ] Log in after reboot
- [ ] Run Phase 2: `sudo ./tn_sysvinit_migrate.sh`
- [ ] Phase 2 completes successfully
- [ ] Run Phase 3: `sudo ./tn_sysvinit_verify.sh`
- [ ] Verify `OK SYSTEM HEALTHY` message
- [ ] (Optional) Review logs in `/var/lib/tn-sysvinit-migrate/`

---

## 📄 License

```
SPDX-License-Identifier: MIT

Copyright (c) 2026 David Peter, Tangent Networks

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## 📞 Support

For bugs, issues, or improvements:

1. Check the logs in `/var/lib/tn-sysvinit-migrate/`
2. Run Phase 3 to identify specific failures
3. Review the stage that failed in the log file
4. Re-run the specific phase that failed

---

## Author and Attribution

**Author:** David Peter
**Organization:** Tangent Networks
**Web:** [https://tangentnet.top](https://tangentnet.top)
**Email:** [tangent.net@zohomail.in](mailto:tangent.net@zohomail.in)

*End of README.md*

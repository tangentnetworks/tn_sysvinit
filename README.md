# TN Sysvinit Appliance — Migration Guide

**Debian systemd → sysvinit Migration Toolkit**
Version 1.0 | 2026-07-31 | MIT License | © 2026 Tangent Networks

---

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Migration Process](#migration-process)
  - [Phase 1: Preparation](#phase-1-preparation--tn_sysvinit_prepsh)
  - [Phase 2: Migration](#phase-2-migration--tn_sysvinit_migratesh)
  - [Phase 3: Autofix](#phase-3-autofix--tn_sysvinit_autofixsh)
  - [Phase 4: Log Check](#phase-4-log-check--tn_sysvinit_check_logssh)
  - [Phase 5: Verification](#phase-5-verification--tn_sysvinit_verifysh)
- [Script Reference](#script-reference)
- [State and Log Files](#state-and-log-files)
- [Error Recovery](#error-recovery)
- [Troubleshooting](#troubleshooting)
- [Safety Guarantees](#safety-guarantees)
- [Architecture Notes](#architecture-notes)
- [Migration Checklist](#migration-checklist)
- [License](#license)
- [Support](#support)

---

## Overview

This toolkit migrates **Debian-based systems from systemd to sysvinit** with full support for LUKS encryption and LVM configurations. The migration is structured as five sequential phases to ensure safety, provide recovery options at each stage, and maintain data integrity throughout.

```
  PHASE 1: PREP      REBOOT GATE      PHASE 2: MIGRATE
  (systemd)     -->  (manual yes) -->  (sysvinit)
                                             |
                                             v
                                      PHASE 3: AUTOFIX
                                      (repair post-migrate issues)
                                             |
                                             v
                                      PHASE 4: CHECK LOGS
                                      (automated log analysis)
                                             |
                                             v
                                      PHASE 5: VERIFY
                                      (final health check)
```

### Key Features

- Automatic encryption detection (LUKS, LVM, LUKS+LVM)
- Safe package removal with dry-run simulation before purge
- Critical package protection (kernel, cryptsetup, LVM, initramfs)
- Idempotent stages — every script is safe to re-run
- Surgical LSB header patching with insserv dependency graph rebuild
- Automated log scanning for known failure patterns
- Comprehensive logging to `/var/lib/tn-sysvinit-migrate/`

---

## Prerequisites

### Supported Systems

| Requirement       | Details                               |
|-------------------|---------------------------------------|
| Operating System  | Debian (tested on Debian 13 / Trixie) |
| Architecture      | amd64 (x86\_64)                       |
| Init System       | Currently running systemd             |
| Package Manager   | apt / dpkg                            |

### Required Privileges

Root access is mandatory. All scripts check `id -u` at startup and exit immediately if not run as root.

### Disk Space

| Location | Minimum Required                       |
|----------|----------------------------------------|
| `/boot`  | 500 MB free (for initramfs rebuilds)   |
| `/`      | 2 GB free (for package operations)     |

### Network

Internet access is required for Phase 1 only. Phases 2 through 5 are fully offline.

---

## Installation

Clone the repository and make all scripts executable:

```bash
git clone https://github.com/tangentnetworks/tn_sysvinit.git
cd tn_sysvinit
chmod +x *.sh
```

Run the scripts in this order:

```
01. sudo ./tn_sysvinit_prep.sh
02. sudo ./tn_sysvinit_migrate.sh
03. sudo ./tn_sysvinit_autofix.sh
04. sudo ./tn_sysvinit_check_logs.sh
05. sudo ./tn_sysvinit_verify.sh
```

---

## Migration Process

---

### Phase 1: Preparation — `tn_sysvinit_prep.sh`

| Attribute    | Details                                                       |
|--------------|---------------------------------------------------------------|
| Runs on      | systemd (before reboot)                                       |
| Purpose      | Detects encryption, installs sysvinit, rebuilds initramfs     |
| Duration     | 2–5 minutes                                                   |
| Destructive  | No — safe to re-run                                           |
| State file   | `/var/lib/tn-sysvinit-migrate/state.prep`                     |
| Log file     | `/var/lib/tn-sysvinit-migrate/phase1.log`                     |

#### What It Does

| Stage  | Description                                                        | Critical    |
|--------|--------------------------------------------------------------------|-------------|
| `00`   | Checks root access, Debian version, required tools                 | Yes         |
| `10`   | Detects LUKS/LVM configuration, writes `crypto.profile`           | Yes         |
| `20`   | Places apt holds on essential packages                             | Yes         |
| `30`   | Updates package lists                                              | No          |
| `40`   | Removes the `systemd-sysv` bridge package                         | Yes         |
| `50`   | Installs `initscripts` (`checkroot.sh`, `mountkernfs.sh`)         | Yes         |
| `60`   | Installs `sysvinit-core` and dependencies                         | Yes         |
| `61`   | Installs BIOS-compatible GRUB (only if LUKS detected)             | Conditional |
| `70`   | Strips stale `urandom`/`checkroot` LSB header references, runs `insserv` | Yes  |
| `80`   | Rebuilds initramfs with `cryptroot` hook (if LUKS detected)       | Yes         |
| `90`   | Confirms `sysvinit-core` is installed before reboot gate          | Yes         |

#### Encryption Detection

The script automatically identifies your storage configuration and saves the result to `crypto.profile`:

| Configuration | Detection Method                            | Protected Packages                                    |
|---------------|---------------------------------------------|-------------------------------------------------------|
| No encryption | No LUKS/LVM detected                        | `linux-image`, `linux-headers`, `initramfs-tools`     |
| LUKS only     | `/etc/crypttab` entries or `/dev/mapper` root | + `cryptsetup`, `cryptsetup-initramfs`, `cryptsetup-bin` |
| LVM only      | Active LVM via `dmsetup` or `lsblk`        | + `lvm2`, `dmsetup`                                   |
| LUKS + LVM    | Both detected                               | + both stacks                                         |

#### Running Phase 1

```bash
sudo ./tn_sysvinit_prep.sh
```

At the end of Phase 1 you will see a reboot prompt. Type `yes` to reboot immediately, or `no` to reboot manually later. Do not skip the reboot — Phase 2 requires sysvinit to be PID 1.

---

### Phase 2: Migration — `tn_sysvinit_migrate.sh`

| Attribute      | Details                                                    |
|----------------|------------------------------------------------------------|
| Runs on        | sysvinit (after reboot from Phase 1)                       |
| Purpose        | Verifies the init switch, then removes systemd             |
| Duration       | 1–2 minutes                                                |
| Destructive    | Yes — removes systemd packages                             |
| State file     | `/var/lib/tn-sysvinit-migrate/state.migration`             |
| Log file       | `/var/lib/tn-sysvinit-migrate/phase2.log`                  |
| Simulation log | `/var/lib/tn-sysvinit-migrate/purge-simulation.log`        |

#### What It Does

| Stage  | Description                                                      | Critical |
|--------|------------------------------------------------------------------|----------|
| `00`   | Confirms PID 1 is `init`, not `systemd`                          | Yes      |
| `10`   | Loads encryption profile written by Phase 1                      | Yes      |
| `20`   | Verifies LUKS decryption is active (if applicable)               | Yes      |
| `30`   | Simulates the systemd purge with `apt-get -s purge` and checks for forbidden removals | Yes |
| `40`   | Performs the actual systemd purge                                | Yes      |
| `50`   | Runs `apt-get -f install`, removes orphans, writes apt pin to block systemd reinstall | Yes |
| `60`   | Final verification: PID 1, `/sbin/init` target, systemd removal  | Yes      |

#### Cryptroot Verification Approach

Rather than parsing initramfs contents with fragile tooling, the script uses a provability argument: if the system successfully booted to sysvinit with an encrypted root device, then cryptroot decryption must have completed in the initramfs. The check is:

```bash
# Root mounted from an encrypted device means cryptroot is working
root_src=$(findmnt -no SOURCE / 2>/dev/null || echo "")
if [[ "$root_src" == /dev/mapper/* ]]; then
    info "LUKS decryption provably occurred in initramfs"
fi
```

#### Packages Removed

`systemd`, `systemd-sysv`, `systemd-cryptsetup`, `systemd-standalone-sysusers`, `systemd-timesyncd`, `dbus-user-session`, `libnss-systemd`, `libpam-systemd`

Stage 30 simulates this removal first. If the simulation detects that any critical package (`linux-image-*`, `linux-headers-*`, `openssh`, `udev`, `grub-*`, `cryptsetup*`, `initramfs-tools`, `busybox`, `util-linux`, `psmisc`) would be pulled in as a dependency removal, the script aborts before touching anything.

#### Running Phase 2

After rebooting from Phase 1, log in as root and run:

```bash
sudo ./tn_sysvinit_migrate.sh
```

Do not reboot again after Phase 2 completes. The migration is live; systemd is gone.

---

### Phase 3: Autofix — `tn_sysvinit_autofix.sh`

| Attribute  | Details                                                     |
|------------|-------------------------------------------------------------|
| Runs on    | sysvinit (after Phase 2)                                    |
| Purpose    | Inspects and repairs common post-migration configuration issues |
| Duration   | 30–90 seconds                                               |
| Destructive | No — all changes are additive or corrective; nothing is removed |
| Log file   | `/var/lib/tn-sysvinit-migrate/autofix.log`                  |

#### What It Does

The autofix script works through four inspection-and-repair modules in sequence. Each module checks for a known class of post-migration problem and fixes it in-place, logging every action taken.

**1. Logging Subsystem (`fix_logging`)**

Ensures `rsyslog` and `bootlogd` are installed, running, and producing output.

- Installs `rsyslog` and `bootlogd` if either is missing
- Creates `/var/log/boot` and `/var/log/syslog` if absent
- Enables `BOOTLOGD_ENABLE=Yes` in `/etc/default/bootlogd` if not already set
- Starts `rsyslog` via `update-rc.d` and `service` if it is not running

**2. Filesystem Mount Configuration (`fix_fstab`)**

Sysvinit requires `/run`, `/run/lock`, and `/tmp` to be declared as `tmpfs` mounts in `/etc/fstab`. These entries are created by systemd automatically when it is the init system but must be explicit for sysvinit.

- Adds a `tmpfs /run` entry if missing (size 20%, mode 755)
- Adds a `tmpfs /run/lock` entry if missing (size 5 MB, noexec)
- Adds a `tmpfs /tmp` entry if missing (mode 1777)
- Calls `mount -a` to apply any newly added entries immediately

**3. Init Configuration (`fix_configs`)**

Validates `/etc/default/rcS` and the inittab directory.

- Sets `RAMRUN=yes`, `RAMLOCK=yes`, and `RAMTMP=yes` in `/etc/default/rcS` if any are missing or incorrect
- Creates `/etc/inittab.d/` if the directory is absent (required by some init scripts)

**4. LSB Header Patching and insserv Rebuild (`fix_insserv_bootclean`)**

This is the most surgical module. It resolves `insserv` dependency graph failures caused by stale LSB header references that accumulate during migration.

- Strips stale `-bootclean` dependency references from LSB headers in `mountall.sh`, `checkroot.sh`, and `checkfs.sh`
- Adds a `bootclean` entry to the `Provides:` field in `checkroot-bootclean.sh` and `mountall-bootclean.sh` if missing
- Purges stale insserv cache files (`.depend.boot`, `.depend.start`, `.depend.stop`) to force a fresh dependency calculation
- Rebuilds the insserv dependency graph with `insserv -v`; if that fails, falls back to `dpkg-reconfigure initscripts`

After the four modules complete, the script clears `/var/log/boot` and restarts `bootlogd` so that the next boot produces a clean log with no residual entries from migration.

#### Output Markers

The script uses three output prefixes:

| Marker      | Meaning                                        |
|-------------|------------------------------------------------|
| `[OK]`      | Check passed, no action needed                 |
| `[WARN]`    | Anomaly noted, not necessarily blocking        |
| `[FIXING]`  | A corrective action was taken and logged       |

#### Running Phase 3

```bash
sudo ./tn_sysvinit_autofix.sh
```

After it completes, proceed immediately to Phase 4 to confirm the fixes took effect.

---

### Phase 4: Log Check — `tn_sysvinit_check_logs.sh`

| Attribute   | Details                                                  |
|-------------|----------------------------------------------------------|
| Runs on     | sysvinit (after Phase 3)                                 |
| Purpose     | Automated diagnostic verification of system state and log content |
| Duration    | 5–15 seconds                                             |
| Destructive | No — read-only except for a temporary file under `/tmp`  |
| Exit code   | 0 on clean pass, 1 if any errors are found               |

#### What It Does

The script runs five verification passes in sequence, accumulating error and warning counts and reporting a final pass/fail at the end.

**1. System State Verification**

- Confirms PID 1 is `init` (sysvinit); fails if it is anything else
- Checks that the `systemd` package is not present in `dpkg -l`

**2. Logging Service Verification**

- Checks `rsyslog` status via both `service` and `/etc/init.d/rsyslog`
- Confirms `/var/log/syslog` exists and is non-empty

**3. Runtime Mount Verification**

- Confirms `/run` and `/run/lock` entries exist in `/etc/fstab`
- These entries are written by Phase 3; their absence here means autofix did not run or failed

**4. Boot-clean Symlink Verification**

- Confirms `checkroot-bootclean` symlinks exist in `/etc/rcS.d/`
- A missing symlink means insserv failed to register the script during Phase 1 or autofix

**5. insserv Dependency Graph Verification**

- Runs `insserv -d` and checks for fatal errors
- Dumps the insserv output on failure so you can see exactly which dependency is broken

**6. Log File Pattern Scanning**

Scans `/var/log/boot`, `/var/log/syslog`, and `/var/log/messages` for a set of known failure strings:

| Pattern searched                                   | What it indicates                         |
|----------------------------------------------------|-------------------------------------------|
| `failed!`                                          | Generic init.d script failure             |
| `checkroot-bootclean.sh ... failed`                | Boot-clean script not properly linked     |
| `Cleaning up temporary files... /run /run/lock failed` | Missing fstab tmpfs entries           |
| `insserv: FATAL`                                   | Dependency graph calculation error        |
| `No inittab.d directory found`                     | Missing `/etc/inittab.d/` directory       |

Log files are passed through `strings` before pattern matching to strip binary NUL bytes and escape sequences that can accumulate in raw boot logs and cause false negatives.

#### Summary Output

```
+-------------------------------------------------------------------+
 Automated Analysis Results: 0 Error(s), 0 Warning(s)
+-------------------------------------------------------------------+
 RESULT: SUCCESS - System is fully configured, clean, and logged!
```

If any errors are found, the exit code is 1 and the failing checks are listed above the summary. This makes the script suitable for use in automated pipelines or boot-time health checks.

#### Running Phase 4

```bash
sudo ./tn_sysvinit_check_logs.sh
```

A clean exit (code 0) means the system is correctly configured and the log files show no failure patterns. Proceed to Phase 5 for a full package-level verification.

---

### Phase 5: Verification — `tn_sysvinit_verify.sh`

| Attribute  | Details                                                       |
|------------|---------------------------------------------------------------|
| Runs on    | sysvinit (anytime after Phase 2)                             |
| Purpose    | Non-destructive, comprehensive health check of the migration  |
| Duration   | 5–10 seconds                                                  |
| Destructive | No — read-only                                               |
| Log file   | `/var/lib/tn-sysvinit-migrate/verification-report.txt`        |

#### What It Does

Phase 5 performs a broad set of read-only checks across seven categories:

**Init System** — PID 1 is `init`, `/sbin/init` target points to sysvinit, `systemd` package is removed, `sysvinit-core` is installed.

**Boot Framework** — Required init.d scripts exist (`checkroot.sh`, `mountkernfs.sh`), runlevel directories exist under `/etc/rc*.d/`, `insserv` is available.

**Kernel and Initramfs** — Running kernel version, initramfs exists for current kernel, initramfs contains essential files (`init`, modules), GRUB can locate the kernel.

**Encryption** — Loads crypto profile from Phase 1, verifies `/etc/crypttab` entries (if LUKS), checks cryptsetup hook configuration, confirms root is mounted from an encrypted device, checks LVM devices (if LVM).

**Critical Packages** — Essential packages are installed and apt-held where required. Kernel image packages are held. `cryptsetup` packages are held if LUKS was detected. LVM packages are held if LVM was detected.

**Filesystem** — Root (`/`) and boot (`/boot`) mounts are valid, `fsck` is available.

**Log Analysis** — Scans Phase 1 and Phase 2 log files for errors and warnings.

#### Running Phase 5

```bash
sudo ./tn_sysvinit_verify.sh
```

Run this immediately after Phase 2 (or after Phase 4 if you ran autofix and check_logs). It can also be run at any time afterward to check ongoing system health.

#### Verification Summary

| Result           | Meaning                                  | Action Required                           |
|------------------|------------------------------------------|-------------------------------------------|
| SYSTEM HEALTHY   | All checks passed                        | None — migration complete                 |
| Warnings present | Some checks warned                       | Review warnings; system is functional     |
| FAILED           | One or more critical checks failed       | Review failures; re-run relevant phase    |

---

## Script Reference

| Script                        | Phase | Runs On  | Destructive | Network | Idempotent | Duration     |
|-------------------------------|-------|----------|-------------|---------|------------|--------------|
| `tn_sysvinit_prep.sh`         | 1     | systemd  | No          | Yes     | Yes        | 2–5 min      |
| `tn_sysvinit_migrate.sh`      | 2     | sysvinit | Yes         | No      | Yes        | 1–2 min      |
| `tn_sysvinit_autofix.sh`      | 3     | sysvinit | No          | No      | Yes        | 30–90 sec    |
| `tn_sysvinit_check_logs.sh`   | 4     | sysvinit | No          | No      | Yes        | 5–15 sec     |
| `tn_sysvinit_verify.sh`       | 5     | sysvinit | No          | No      | Yes        | 5–10 sec     |

---

## State and Log Files

All migration state and logs are stored in `/var/lib/tn-sysvinit-migrate/`:

```
/var/lib/tn-sysvinit-migrate/
├── state.prep                  # Phase 1: completed stage markers
├── state.migration             # Phase 2: completed stage markers
├── phase1.log                  # Phase 1: detailed execution log
├── phase2.log                  # Phase 2: detailed execution log
├── autofix.log                 # Phase 3: all inspection and repair actions
├── verification-report.txt     # Phase 5: full verification results
├── crypto.profile              # Auto-detected encryption configuration
└── purge-simulation.log        # Phase 2: apt purge dry-run output
```

Phase 4 does not write a persistent log of its own; it reads the logs written by the other phases and writes temporary working files under `/tmp` that are cleaned up on exit.

---

## Error Recovery

### If Phase 1 Fails

Phase 1 is idempotent. Re-run it and it will skip completed stages:

```bash
sudo ./tn_sysvinit_prep.sh
```

Check `/var/lib/tn-sysvinit-migrate/phase1.log` for the specific error.

### If Boot Fails After Phase 1

1. Boot into GRUB recovery mode (hold Shift during boot)
2. Select a previous kernel or recovery entry
3. Log in as root
4. Check the Phase 1 log: `cat /var/lib/tn-sysvinit-migrate/phase1.log`
5. Re-run Phase 1 to rebuild initramfs, then reboot again

### If Phase 2 Fails

Phase 2 is also idempotent. Re-run it; completed stages are skipped:

```bash
sudo ./tn_sysvinit_migrate.sh
```

If Stage 30 (purge simulation) fails, it means removing systemd would break a critical dependency. Do not force the purge. Review `purge-simulation.log` to identify the conflicting package.

### If Phase 3 or Phase 4 Reports Errors

Re-run Phase 3 first to apply any remaining fixes, then re-run Phase 4 to confirm:

```bash
sudo ./tn_sysvinit_autofix.sh
sudo ./tn_sysvinit_check_logs.sh
```

If Phase 4 still reports `insserv: FATAL`, check `/etc/init.d/` for scripts referencing services that no longer exist. The most common culprits after systemd removal are `urandom` and stale `checkroot` cross-references in LSB headers.

### If systemd Gets Reinstalled

The apt pin placed by Phase 2 should prevent this. If it happens:

```bash
# Verify the pin is in place
apt-cache policy systemd   # should show Pin-Priority: -1

# If missing, reinstall the pin
cat > /etc/apt/preferences.d/00-no-systemd <<'EOF'
Package: systemd*
Pin: release *
Pin-Priority: -1
EOF

# Purge systemd again
apt-get remove --purge systemd systemd-sysv
```

---

## Troubleshooting

**How do I know if the migration worked?**
Run `sudo ./tn_sysvinit_verify.sh`. A `SYSTEM HEALTHY` result with zero failures confirms a successful migration.

**Can I downgrade back to systemd?**
Not easily, and it is not officially supported. The migration removes systemd packages and places an apt pin to block reinstall. If you need to reverse: remove `/etc/apt/preferences.d/00-no-systemd`, run `apt-get install systemd systemd-sysv`, and reboot. This path is untested and may produce an inconsistent system state.

**What if I have encrypted LVM?**
The toolkit handles this automatically. If both LVM and LUKS are detected, all phases protect and verify both stacks.

**What if I use a custom LUKS key file?**
Ensure it is referenced correctly in `/etc/crypttab`:
```
vda3_crypt UUID=<uuid> /path/to/keyfile luks,discard
```
Phase 1 will detect the `crypttab` entry and include the key file path in the initramfs rebuild.

**Can I use this on non-Debian systems?**
No. The toolkit checks for `/etc/debian_version` and uses `apt-get`/`dpkg` throughout. Ubuntu may have similar structures but carries additional systemd dependencies that are not accounted for.

**Why does Phase 1 print `insserv: FATAL` warnings during install?**
These are expected during initial sysvinit package installation. Phase 1 Stage 70 (`fix_boot_deps`) explicitly strips the stale LSB header references that cause them and then rebuilds the dependency graph cleanly. If you still see them after Stage 70, run Phase 3 autofix.

---

## Safety Guarantees

The toolkit will never do any of the following:

| Guarantee                               | How It Is Enforced                                                     |
|-----------------------------------------|------------------------------------------------------------------------|
| Remove kernel packages                  | Holds `linux-image-*` and `linux-headers-*` via `apt-mark hold`       |
| Remove cryptsetup (if LUKS)             | Holds `cryptsetup`, `cryptsetup-initramfs`, `cryptsetup-bin`           |
| Remove LVM tools (if LVM)               | Holds `lvm2`, `dmsetup`                                                |
| Remove essential boot tooling           | Holds `initramfs-tools`, `busybox`, `grub*`, `openssh-server`         |
| Purge without safety check              | Runs `apt-get -s purge` and inspects output before any real removal    |
| Proceed through reboot without consent  | Requires explicit `yes` at the reboot gate in Phase 1                  |

---

## Architecture Notes

### Why Five Scripts?

A single monolithic script cannot safely handle this migration because the init switch happens at reboot. Running everything before reboot means you cannot verify PID 1 is `init`. Running everything after means you cannot use `systemctl` for the reboot gate. The five-script structure maps cleanly onto the five logical states of the migration:

- Phase 1 runs under systemd and stops before the point of no return
- Phase 2 runs under sysvinit and performs the destructive purge
- Phase 3 repairs known post-purge configuration drift in a targeted way
- Phase 4 provides machine-readable verification of the repair
- Phase 5 provides a comprehensive human-readable health report

Each phase is independently idempotent, meaning any phase can be re-run after a failure without repeating work that has already succeeded.

### Why Hold Packages?

`apt-get purge` resolves dependency removals automatically. Without holds, a poorly specified dependency in a third-party package could cause it to pull out `cryptsetup` or a kernel module alongside systemd. The hold list is constructed dynamically based on what the encryption detector found, so only what is actually needed on this specific system is held.

### Why Pre-Fix LSB Headers Before Running insserv?

`insserv` builds a strict dependency graph from the `Required-Start` and `Required-Stop` fields in init.d script LSB headers. If any script references a facility (`urandom`, `checkroot`) that is not declared as `Provides` in another script, `insserv` exits fatally. After systemd removal, several of those facility providers disappear. Stripping the references before running `insserv` prevents the fatal exit and allows the dependency graph to be built correctly.

### Why Separate Autofix from Migration?

Keeping Phase 3 separate from Phase 2 means the destructive purge stage (Phase 2) is as small and auditable as possible. It also means autofix can be re-run independently without re-triggering the package removal logic.

---

## Migration Checklist

- [ ] Download all five scripts
- [ ] Make scripts executable with `chmod +x *.sh`
- [ ] Confirm scripts have MIT license headers
- [ ] Run Phase 1: `sudo ./tn_sysvinit_prep.sh`
- [ ] Confirm reboot prompt with `yes`
- [ ] System reboots into sysvinit
- [ ] Log in after reboot
- [ ] Run Phase 2: `sudo ./tn_sysvinit_migrate.sh`
- [ ] Phase 2 completes without errors
- [ ] Run Phase 3: `sudo ./tn_sysvinit_autofix.sh`
- [ ] Run Phase 4: `sudo ./tn_sysvinit_check_logs.sh` — confirm exit code 0
- [ ] Run Phase 5: `sudo ./tn_sysvinit_verify.sh` — confirm SYSTEM HEALTHY
- [ ] Review logs in `/var/lib/tn-sysvinit-migrate/` if any phase reported warnings

---

## License

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

## Support

For bugs, issues, or improvements:

1. Check the logs in `/var/lib/tn-sysvinit-migrate/`
2. Run Phase 5 to identify specific failures
3. Review the stage that failed in the relevant log file
4. Re-run the specific phase that failed

---

**Author:** David Peter
**Organization:** Tangent Networks
**Web:** https://tangentnet.top
**Email:** tangent.net@zohomail.in

---

*End of README.md*

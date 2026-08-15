#!/usr/bin/env bash
# ============================================================
#  Seikabook OS Install - your hardware, its soul.
#  Idea: get Chinese-speaking beginners into the KDE desktop
#        first, then learn - not stuck at the archiso prompt.
#
#  Step 1: install the system (this script) - boot from Arch ISO,
#          ~30 min to a working KDE desktop.
#  Step 2: seika-kernel.sh (optional) - compile the zen+BORE
#          enhanced kernel after first boot.
#
#  Usage: bash install.sh   (archiso only; no complex arguments)
# ============================================================
set -euo pipefail

C_RESET="\e[0m"; C_BLUE="\e[1;34m"; C_GREEN="\e[1;32m"; C_YEL="\e[1;33m"; C_RED="\e[1;31m"
say()  { echo -e "${C_BLUE}[Seikabook]${C_RESET} $*"; }
ok()   { echo -e "${C_GREEN}[ OK ]${C_RESET} $*"; }
warn() { echo -e "${C_YEL}[WARN]${C_RESET} $*"; }
die()  { echo -e "${C_RED}[ERROR]${C_RESET} $*" >&2; exit 1; }

# ────────────────────────────────────────────────────────────
# 0.0 Pipe self-heal: when run as "curl | bash", stdin is a pipe
#     and interactive read/select hit EOF and abort. If stdin is
#     not a tty, re-run ourselves with /dev/tty as stdin.
# ────────────────────────────────────────────────────────────
SELF_URL="https://gitee.com/seikabook/seikabook-os-install/raw/master/install.sh"
if [ ! -t 0 ] && [ -z "${SEIKA_REEXEC:-}" ]; then
    say "Pipe input detected, re-running in interactive (tty) mode..."
    curl -fsSL "$SELF_URL" -o /tmp/seika-install.sh \
        || die "Failed to re-download the script. Use two-step instead: curl -o /tmp/i.sh && bash /tmp/i.sh"
    export SEIKA_REEXEC=1
    exec bash /tmp/seika-install.sh < /dev/tty
fi

# ════════════════════════════════════════════════════════════
# 0.0 Preflight: mirror + locale (must run first)
#     On the local archiso tty, Chinese cannot render (no CJK
#     console font / fbterm removed from repos). Over SSH the
#     client renders Chinese fine, so this only matters for tty.
#     We still set the locale and pick a fast mirror up front.
# ════════════════════════════════════════════════════════════
bench_mirror() {
    say "Benchmarking China mirrors..."
    BEST=""; BEST_T=999
    for entry in \
        "https://mirrors.tuna.tsinghua.edu.cn/archlinux" \
        "https://mirrors.aliyun.com/archlinux" \
        "https://mirrors.ustc.edu.cn/archlinux"; do
        t=$(curl -o /dev/null -s --connect-timeout 8 -w "%{time_total}" \
            "${entry}/core/os/x86_64/core.db" 2>/dev/null || echo 999)
        echo "    $(echo ${t}s)  ${entry}"
        if awk "BEGIN{exit !(${t} < ${BEST_T})}"; then BEST_T=${t}; BEST=${entry}; fi
    done
    [ -n "${BEST}" ] || die "All mirrors unreachable, check your network"
    ok "Fastest mirror: ${BEST} (${BEST_T}s)"
    echo "Server = ${BEST}/\$repo/os/\$arch" > /etc/pacman.d/mirrorlist
}

preflight() {
    # 1) Mirror: benchmark and pick the fastest China mirror early.
    #    Wrapped in a subshell so a network failure only warns, not fatal.
    ( bench_mirror ) 2>/dev/null || true

    # 2) Locale: the INSTALLER runs in a plain English locale so that the
    #    underlying tools (mkswap, mkfs.btrfs, btrfs, ...) print readable
    #    English errors. The TARGET system stays Chinese - that is configured
    #    separately inside arch-chroot (configure_system: /mnt/etc/locale.conf).
    #    We still generate zh_CN on the host so the chroot locale-gen can use it.
    sed -i 's/^#zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen 2>/dev/null || true
    locale-gen >/dev/null 2>&1 || true
    export LANG=C.UTF-8 LC_ALL=C.UTF-8

    # 3) Local console Chinese note (important, avoids wasted effort)
    #    stock archiso cannot show Chinese on the local console:
    #      - fbterm was removed from the Arch official repos (target not found)
    #      - setfont is limited to 256/512 glyph slots, far too few for CJK
    #      - official archinstall also shows boxes on this machine's console
    #    The only reliable way: run this script over an SSH session
    #    (the SSH client renders Chinese fine). Install flow is unaffected.
    if [ -z "${SSH_TTY:-}" ] && [ -t 1 ]; then
        warn "You are on the local console (tty): stock archiso cannot show Chinese here"
        warn "(fbterm was removed from the repos; setfont cannot render CJK either; archinstall is the same)."
        warn "Recommend: connect via SSH and run this script; the SSH client shows Chinese fine."
        warn "Install flow is unaffected; just follow the prompts (English/pinyin keywords work)."
    fi
}
if [ -z "${SEIKA_PREFLIGHT:-}" ]; then
    export SEIKA_PREFLIGHT=1
    preflight
fi

# ════════════════════════════════════════════════════════════
# 0. Basic checks: must be root, should be archiso
# ════════════════════════════════════════════════════════════
[ "$(id -u)" -eq 0 ] || die "Run as root (boot from the Arch ISO first)"

if [ ! -d /run/archiso ] && [ ! -f /etc/arch-release ]; then
    warn "archiso environment not detected. This script is for a FRESH install (run after booting the Arch ISO)."
    warn "If you are already on a running system, stop - use seika-kernel.sh later to tune the kernel."
    read -rp "Confirm you are in the archiso installer? [y/N] " ans
    [[ "${ans,,}" == "y" ]] || exit 1
fi

say "Seikabook OS Install starting - let's look at your machine first."
echo

# ════════════════════════════════════════════════════════════
# 1. Hardware detection
# ════════════════════════════════════════════════════════════
# Classify an NVIDIA GPU (from its `lspci` line) into a driver strategy.
# Default driver is nvidia-dkms (closed-source DKMS) -- supported for Maxwell and
# newer (GMxxx / GPxxx / TU1xx / GA1xx / AD1xx / GB1xx), builds against
# linux-zen-headers via DKMS. Pre-Maxwell (Kepler/Fermi/Tesla) is NOT supported by
# the main driver and needs a legacy AUR driver. Design choice: DETECT + WARN, never
# silently install a driver that cannot run the card. (If a card specifically needs the
# open kernel modules, the user installs nvidia-open-dkms manually -- we do not auto-pick it.)
#   NVIDIA_DKMS_OK=1   -> install nvidia-dkms
#   NVIDIA_DKMS_OK=0   -> legacy / unrecognized -> do NOT auto-install, just warn
#   NVIDIA_LEGACY_PKG  -> suggested AUR driver (empty if generation unrecognized)
classify_nvidia() {
    NVIDIA_DKMS_OK=1
    NVIDIA_LEGACY_PKG=""
    local low="${1,,}"
    case "$low" in
        # Maxwell and newer: closed-source nvidia-dkms covers GMxxx->GB2xx.
        # Match BOTH marketing names and chip codes so a GPU is recognized even if
        # lspci omits the model name.
        #   Maxwell=gm1xx, Pascal=gp1xx, Turing=tu1xx, Ampere=ga1xx,
        #   Ada=ad1xx, Blackwell=gb1xx/gb2xx
        *rtx\ *|*rtx[0-9]*|*geforce\ rtx*|*gtx\ 16*|*gtx16*|*gtx\ 10*|*gtx10*|*gtx\ 9*|*gtx9*|*gtx\ 8*|*gtx8*|*gm1*|*gp1*|*tu1*|*ga1*|*ad1*|*gb1*|*gb2*)
            NVIDIA_DKMS_OK=1 ;;
        # Kepler (GTX 7/6, GK1xx) -> nvidia-470xx-dkms (AUR)
        *gtx\ 7*|*gtx7*|*gtx\ 6*|*gtx6*|*gk1*)
            NVIDIA_DKMS_OK=0; NVIDIA_LEGACY_PKG="nvidia-470xx-dkms" ;;
        # Fermi (GTX 5/4, GF1xx) -> nvidia-390xx-dkms (AUR)
        *gtx\ 5*|*gtx5*|*gtx\ 4*|*gtx4*|*gf1*)
            NVIDIA_DKMS_OK=0; NVIDIA_LEGACY_PKG="nvidia-390xx-dkms" ;;
        # Tesla (G80/GT200/GF100) -> nvidia-340xx-dkms (AUR)
        *g80*|*gt200*|*gf10*)
            NVIDIA_DKMS_OK=0; NVIDIA_LEGACY_PKG="nvidia-340xx-dkms" ;;
        # Unrecognized NVIDIA string: assume it MAY be too old -> do not silently
        # install an unsupported driver; warn and let the user install the right one.
        *)
            NVIDIA_DKMS_OK=0; NVIDIA_LEGACY_PKG="" ;;
    esac
}

detect_hardware() {
    echo
    say "────────── Hardware detection ──────────"
    CPU_VENDOR="$(lscpu 2>/dev/null | awk -F': *' '/^Vendor ID/{print $2; exit}')"
    CPU_MODEL="$(lscpu 2>/dev/null | awk -F': *' '/^Model name/{print $2; exit}')"
    echo "CPU    : ${CPU_MODEL:-unknown} (${CPU_VENDOR:-unknown} / $(nproc) threads)"
    case "${CPU_VENDOR,,}" in
        *amd*) CPU_FAMILY="amd" ;;
        *intel*) CPU_FAMILY="intel" ;;
        *) CPU_FAMILY="unknown" ;;
    esac
    GPU_LINE="$(lspci 2>/dev/null | grep -iE 'VGA|3D controller|Display controller' | head -1 || true)"
    echo "GPU    : ${GPU_LINE:-unknown}"
    case "${GPU_LINE,,}" in
        *nvidia*) GPU_FAMILY="nvidia" ;;
        *advanced\ micro\ devices*) GPU_FAMILY="amd" ;;
        *intel*) GPU_FAMILY="intel" ;;
        *) GPU_FAMILY="unknown" ;;
    esac
    if [ "${GPU_FAMILY}" = "nvidia" ]; then
        classify_nvidia "${GPU_LINE}"
        if [ "${NVIDIA_DKMS_OK}" != "1" ]; then
            if [ -n "${NVIDIA_LEGACY_PKG}" ]; then
                warn "Pre-Maxwell NVIDIA GPU - nvidia-dkms does NOT support it; skipping auto-install."
                warn "After install, install the legacy driver manually from AUR: ${NVIDIA_LEGACY_PKG}"
            else
                warn "Unrecognized NVIDIA GPU - skipping automatic NVIDIA driver install (detect+notify, not silent)."
                warn "If this is Maxwell+ (GTX 9/10/RTX), after install run: paru/yay -S nvidia-dkms nvidia-utils"
            fi
        fi
    fi
    echo "Memory : $(awk '/^MemTotal:/{printf "%.1f GiB\n", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo unknown)"
    echo "Disks  :"
    lsblk -d -o NAME,SIZE,MODEL,TRAN 2>/dev/null | grep -vE 'NAME|loop' | head -6 || true
    if [ -d /sys/firmware/efi ]; then BOOT_MODE="UEFI"; else BOOT_MODE="BIOS"; fi
    echo "Boot   : ${BOOT_MODE}"
    echo "────────── Detection done ──────────"
}

# ════════════════════════════════════════════════════════════
# 2. Suggest kernel/driver plan by hardware
# ════════════════════════════════════════════════════════════
suggest_plan() {
    echo
    say "Your hardware plan:"
    case "${CPU_FAMILY}" in
        amd)    echo "  - CPU: AMD - after install, use seika-kernel.sh to build the zen+BORE kernel" ;;
        intel)  echo "  - CPU: Intel - after install, use seika-kernel.sh to build the zen+BORE kernel" ;;
        *)      echo "  - CPU: unknown vendor - use the official kernel" ;;
    esac
    case "${GPU_FAMILY}" in
        amd)    echo "  - GPU: AMD - amdgpu + Mesa open driver, zero config" ;;
        nvidia)
            if [ "${NVIDIA_DKMS_OK}" = "1" ]; then
                echo "  - GPU: NVIDIA - nvidia-dkms (closed-source DKMS; builds for your zen kernel via linux-zen-headers, NOT nouveau). Covers Maxwell+ (GTX9/10/16, RTX20-50). If your card needs the open kernel modules, install nvidia-open-dkms manually after setup."
            else
                echo "  - GPU: NVIDIA (PRE-MAXWELL) - nvidia-dkms does NOT support this GPU; automatic driver install SKIPPED."
                if [ -n "${NVIDIA_LEGACY_PKG}" ]; then
                    echo "      After install, manually install the legacy driver from AUR: ${NVIDIA_LEGACY_PKG}"
                else
                    echo "      Unrecognized generation - if Maxwell+, after install run: paru/yay -S nvidia-dkms nvidia-utils"
                fi
            fi ;;
        intel)  echo "  - GPU: Intel - i915/xe open driver, zero config" ;;
        *)      echo "  - GPU: unknown - check with lspci after install" ;;
    esac
    echo "  - Kernel: linux-zen + linux-lts dual kernel preinstalled (default boots zen; recover via 'Advanced options' -> linux-lts), enhanced kernel optional later"
    echo "  - Desktop: KDE Plasma (the most beginner-friendly modern desktop)"
}

# ════════════════════════════════════════════════════════════
# 3. Guided questions (beginners just pick)
# ════════════════════════════════════════════════════════════
ask_questions() {
    echo
    say "A few questions - just pick what you like:"
    echo
    PS3="  Desktop environment? [1-4] "
    select DE_CHOICE in "KDE (recommended, beginner-friendly)" "GNOME" "Hyprland (tiling, advanced)" "Headless server (minimal)"; do
        case "${DE_CHOICE}" in
            *KDE*) DESKTOP="kde"; break ;;
            *GNOME*) DESKTOP="gnome"; break ;;
            *Hyprland*) DESKTOP="hyprland"; break ;;
            *Headless*) DESKTOP="headless"; break ;;
            *) echo "  Pick 1-4" ;;
        esac
    done
    read -rp "  Keep Windows dual-boot? [Y/n] " ans
    [[ "${ans,,}" == "n" ]] && KEEP_WINDOWS=0 || KEEP_WINDOWS=1
    read -rp "  Auto-pick fastest China mirror? [Y/n] " ans
    [[ "${ans,,}" == "n" ]] && AUTO_MIRROR=0 || AUTO_MIRROR=1
    read -rp "  Hostname? [default arch] " ans
    HOSTNAME="${ans:-arch}"
    read -rp "  Username? [default seika] " ans
    USER_NAME="${ans:-seika}"
}

# ════════════════════════════════════════════════════════════
# 4. Partition selection (manual, guided per mountpoint)
#    Mountpoints: EFI, / (root), /home (OPTIONAL), swap.
#    Each step pick disk first, then pick [existing partition | free space].
#    /home is OPTIONAL (this is the closed loop):
#      - not selected -> /home is just a directory inside / (the BTRFS @ subvolume)
#      - selected     -> a separate ext4 partition, with a format (y/N) prompt
#    Free space can take a size (e.g. 100G / 512M); empty = all remaining.
# ════════════════════════════════════════════════════════════
PART_EFI_DEV= PART_EFI_TGT= PART_EFI_FMT=1
PART_ROOT_DEV= PART_ROOT_TGT=
PART_HOME_DEV= PART_HOME_TGT= PART_HOME_FMT=0
PART_SWAP_DEV= PART_SWAP_TGT=

pick_disk() {
    # exclude the live-media loop device (archiso airootfs) - never a valid install target
    local disks=($(lsblk -d -rno NAME 2>/dev/null | grep -v '^loop')); local i=1
    [ "${#disks[@]}" -gt 0 ] || die "No installable disks found"
    echo "  Available disks:"
    for d in "${disks[@]}"; do
        local sz tr
        sz=$(lsblk -d -rno SIZE "/dev/$d" 2>/dev/null)
        tr=$(lsblk -d -rno TRAN "/dev/$d" 2>/dev/null)
        echo "    $i) /dev/$d  ${sz}  (${tr:-unknown})"; i=$((i+1))
    done
    while :; do
        # default = 1 (first real disk); Enter just takes it
        read -rp "  Pick disk number (default 1): " n
        [ -z "$n" ] && n=1
        if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#disks[@]}" ]; then
            _DISK="/dev/${disks[$((n-1))]}"; return 0
        fi
        warn "Invalid number"
    done
}

pick_target() {
    # $1=disk(dev)  $2=label(e.g. EFI)
    local dev="$1" label="$2"
    echo "  [${label}] choose target on ${dev}:"
    echo "    0) Free space (script creates a new partition)"
    local plist=($(lsblk -rn -o NAME,PARTN "$dev" | awk '$2!="" {print $1}')); local i=1
    for p in "${plist[@]}"; do
        echo "    $i) /dev/$p  ($(lsblk -dn -o SIZE "/dev/$p"))"; i=$((i+1))
    done
    while :; do
        # default = 0 (free space): the common beginner case is "use the free space
        # Windows left", so Enter just does the expected thing.
        read -rp "  Pick number (0=free space, default 0): " n
        [ -z "$n" ] && n=0
        if [ "$n" = "0" ]; then
            local size
            read -rp "    Free space size (e.g. 100G / 512M, empty = all remaining): " size
            if [ -n "$size" ]; then
                [[ "$size" =~ ^[0-9]+(M|G)$ ]] || { warn "Size must be like 100G or 512M"; continue; }
                size="+${size}"
            else
                size=0
            fi
            _TGT="free:${size}"; return 0
        elif [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#plist[@]}" ]; then
            _TGT="part:/dev/${plist[$((n-1))]}"; return 0
        fi
        warn "Invalid number"
    done
}

manual_partition() {
    say "Manual mode: pick each partition (disk first, then a partition or free space on it)"
    say "/home is optional: skip it and /home stays inside / (BTRFS @); pick it and it becomes a separate ext4 partition."
    say "Step 1/4 - EFI partition"
    pick_disk; PART_EFI_DEV="$_DISK"; pick_target "$_DISK" EFI; PART_EFI_TGT="$_TGT"
    if [[ "$PART_EFI_TGT" == part:* ]]; then
        read -rp "  Format this EFI partition? [y/N] " f
        [[ "${f,,}" == "y" ]] && PART_EFI_FMT=1 || PART_EFI_FMT=0
    fi
    say "Step 2/4 - root / partition (BTRFS, holds the @ subvolume + Timeshift snapshots)"
    pick_disk; PART_ROOT_DEV="$_DISK"; pick_target "$_DISK" ROOT; PART_ROOT_TGT="$_TGT"
    say "Step 3/4 - /home partition (optional; press N to keep /home inside /)"
    read -rp "  Use a separate /home partition? [y/N] " h
    if [[ "${h,,}" == "y" ]]; then
        pick_disk; PART_HOME_DEV="$_DISK"; pick_target "$_DISK" HOME; PART_HOME_TGT="$_TGT"
        if [[ "$PART_HOME_TGT" == part:* ]]; then
            read -rp "  Format this /home partition as ext4? [y/N] " f
            [[ "${f,,}" == "y" ]] && PART_HOME_FMT=1 || PART_HOME_FMT=0
        else
            PART_HOME_FMT=1   # new partition from free space -> always format
        fi
    else
        PART_HOME_DEV=; PART_HOME_TGT=; PART_HOME_FMT=0
        ok "/home will live inside / (BTRFS @), no separate partition"
    fi
    say "Step 4/4 - swap partition"
    pick_disk; PART_SWAP_DEV="$_DISK"; pick_target "$_DISK" SWAP; PART_SWAP_TGT="$_TGT"
}

# Entry point for partitioning: manual mode only (auto/one-click removed - untested).
choose_partition() {
    manual_partition
}

# ════════════════════════════════════════════════════════════
# 5. Partition + format + BTRFS subvolumes
# ════════════════════════════════════════════════════════════
setup_disk() {
    say "Partitioning and mounting per your plan (writing to disk)..."
    # If a previous (interrupted) run left mounts/swaps behind, tear them down first so
    # we can safely reformat the target partitions. A fresh installer only mounts under /mnt.
    swapoff -a 2>/dev/null || true
    umount -R /mnt 2>/dev/null || true
    # $1=disk $2=tgt(part:/dev/xxx | free:+SIZE | free:0) $3=typecode -> prints partition device path
    make_part() {
        local dev="$1" tgt="$2" type="$3"
        if [[ "$tgt" == free:* ]]; then
            local size="${tgt#free:}"
            # Determine the partition NUMBER sgdisk will assign next. sgdisk -n0 uses the
            # LOWEST free number, so we read the on-disk table (sgdisk -p), NOT the kernel
            # cache - this is reliable even immediately after a previous create in the same run.
            # (Using lsblk|tail -1 was racy: the kernel/udev node can lag, so it returned an
            # already-existing partition and every free: target collapsed onto the same device.)
            local newn
            newn=$(sgdisk -p "${dev}" 2>/dev/null | awk '
                /^[ \t]*[0-9]+[ \t]/ { n=$1; used[n]=1; if (n>m) m=n }
                END { i=1; while (i<=m+1) { if (!(i in used)) { print i; exit } i++ } }')
            [ -n "$newn" ] || { echo "ERROR: cannot determine next partition number on ${dev}" >&2; return 1; }
            # Carve from the LARGEST free region's START sector (sgdisk -F prints just the start).
            # We create free: partitions sequentially (/ then /home then swap=rest), each time
            # re-reading the largest free region, so "swap = all remaining" must be created LAST.
            local fs; fs=$(sgdisk -F "${dev}" 2>/dev/null | head -1)
            [ -n "$fs" ] || { echo "ERROR: no free space left on ${dev} to create a partition" >&2; return 1; }
            if [ -z "$size" ] || [ "$size" = "0" ]; then
                sgdisk -n0:"${fs}":0 -t0:"${type}" "${dev}" >/dev/null \
                    || { echo "ERROR: failed to create partition in free space on ${dev}" >&2; return 1; }
            else
                sgdisk -n0:"${fs}":"${size}" -t0:"${type}" "${dev}" >/dev/null \
                    || { echo "ERROR: failed to create ${size} partition in free space on ${dev}" >&2; return 1; }
            fi
            partprobe "${dev}" 2>/dev/null || true
            # Build the device path from the partition number we computed, and wait for the
            # kernel device node to appear (udev can lag behind partprobe).
            local newdev
            case "$dev" in
                *nvme*|*loop*|*mmcblk*) newdev="${dev}p${newn}" ;;
                *) newdev="${dev}${newn}" ;;
            esac
            local i=0
            while [ ! -b "$newdev" ] && [ $i -lt 25 ]; do sleep 0.2; i=$((i+1)); done
            if [ ! -b "$newdev" ]; then
                # Fallback: take the highest partition lsblk currently sees.
                newdev="/dev/$(lsblk -rn -o NAME "${dev}" | tail -1)"
            fi
            [ -b "$newdev" ] || { echo "ERROR: partition ${newdev} not found after creation" >&2; return 1; }
            echo "$newdev"
        else
            echo "${tgt#part:}"
        fi
    }
    # Sanity-check the real layout right after partitioning, so a device-capture
    # mistake (root/home/swap pointing at the wrong partition) is caught BEFORE
    # we pacstrap onto a broken disk.
    verify_layout() {
        echo
        say "Actual partition layout (verify it matches your plan):"
        for d in "$ROOT_PART" "$EFI_PART"; do
            local dsk; dsk=$(lsblk -no PKNAME "$d" 2>/dev/null | head -1)
            [ -n "$dsk" ] && lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS "/dev/${dsk}" 2>/dev/null | sed 's/^/  /' || true
        done
        local bad=0
        local rfs; rfs=$(lsblk -no FSTYPE "$ROOT_PART" 2>/dev/null)
        [ "$rfs" = "btrfs" ] || { warn "ROOT $ROOT_PART is NOT btrfs (detected: '${rfs:-none}')"; bad=1; }
        if [ -n "$PART_HOME_DEV" ]; then
            local hfs; hfs=$(lsblk -no FSTYPE "$HOME_PART" 2>/dev/null)
            [ "$hfs" = "ext4" ] || { warn "/home $HOME_PART is NOT ext4 (detected: '${hfs:-none}')"; bad=1; }
        fi
        if [ -n "$PART_SWAP_DEV" ]; then
            local sfs; sfs=$(lsblk -no FSTYPE "$SWAP_PART" 2>/dev/null)
            [ "$sfs" = "swap" ] || { warn "swap $SWAP_PART is NOT swap (detected: '${sfs:-none}')"; bad=1; }
        fi
        [ "$bad" = "1" ] && { warn "Layout MISMATCH above - do NOT reboot. Re-run after cleaning the target."; return 1; }
        ok "Layout verified: root=btrfs$([ -n "$PART_HOME_DEV" ] && echo ', /home=ext4'), swap present"
    }
    EFI_PART=$(make_part "$PART_EFI_DEV" "$PART_EFI_TGT" ef00)
    [ "$PART_EFI_FMT" = "1" ] && mkfs.fat -F32 "$EFI_PART" >/dev/null && ok "EFI $EFI_PART (FAT32)"

    ROOT_PART=$(make_part "$PART_ROOT_DEV" "$PART_ROOT_TGT" 8300)
    mkfs.btrfs -f "$ROOT_PART" >/dev/null && ok "root $ROOT_PART (BTRFS)"
    mount "$ROOT_PART" /mnt
    btrfs subvolume create /mnt/@ >/dev/null
    if [ -z "$PART_HOME_DEV" ]; then
        # /home stays inside / -> use the @home subvolume (excluded from Timeshift snapshots)
        btrfs subvolume create /mnt/@home >/dev/null
    fi
    umount /mnt

    MOUNT_OPTS="noatime,compress=zstd:1"
    mount -o "${MOUNT_OPTS},subvol=@" "$ROOT_PART" /mnt
    mkdir -p /mnt/boot /mnt/boot/efi /mnt/home
    # /home: snapshots must protect the SYSTEM (/), never user data.
    #  - selected  -> a separate ext4 partition (naturally outside BTRFS, never snapshotted)
    #  - not picked -> the @home subvolume on the same BTRFS; Timeshift exclude_home=true
    #                excludes it, so user data is never snapshotted either.
    if [ -n "$PART_HOME_DEV" ]; then
        HOME_PART=$(make_part "$PART_HOME_DEV" "$PART_HOME_TGT" 8300)
        if [ "$PART_HOME_FMT" = "1" ]; then
            mkfs.ext4 -F "$HOME_PART" >/dev/null && ok "/home $HOME_PART (ext4, formatted)"
        else
            ok "/home $HOME_PART (ext4, existing data kept)"
        fi
        mount -o noatime "$HOME_PART" /mnt/home
    else
        mount -o "${MOUNT_OPTS},subvol=@home" "$ROOT_PART" /mnt/home
        ok "/home is the @home subvolume (same BTRFS disk, excluded from Timeshift snapshots)"
    fi
    # swap is created LAST so "all remaining" really means "whatever is left after / and /home"
    SWAP_PART=$(make_part "$PART_SWAP_DEV" "$PART_SWAP_TGT" 8200)
    mkswap "$SWAP_PART" >/dev/null && swapon "$SWAP_PART" && ok "swap $SWAP_PART"
    mount "$EFI_PART" /mnt/boot/efi
    ok "Mount done (root @ snapshotted by Timeshift; user data /home never snapshotted)"
}

# ════════════════════════════════════════════════════════════
# 6. Mirror benchmark (bench_mirror defined earlier at 0.0,
#    reused by preflight and main)
# ════════════════════════════════════════════════════════════

# ════════════════════════════════════════════════════════════
# 7. pacstrap base system + desktop
# ════════════════════════════════════════════════════════════
install_base() {
    # Note: $( [ ... ] && echo ... || true ) must keep || true --
    # otherwise when the condition is false the substitution exits 1,
    # and under set -e the assignment would abort (classic trap)

    # [multilib] is intentionally NOT enabled by default. The only 32-bit packages we
    # might want (lib32-nvidia-utils for Steam/Proton) are optional, and the Steam setup
    # guide tells the user how to unlock [multilib] + install them after first boot.
    # Keeping it off by default keeps the install simpler and avoids the old
    # "target not found: lib32-nvidia-utils" sync-footgun. (archlinuxcn, by contrast, IS
    # enabled by default -- see setup_archlinuxcn -- because paru needs it to avoid the
    # "can't install paru without the repo" chicken-and-egg.)

    # Phase 1: bootstrap ONLY the base + kernels + system tools. These live in [core]/
    # [extra] and ALWAYS resolve, so this pacstrap is robust. The desktop, NVIDIA and
    # 32-bit (multilib) packages are installed LATER INSIDE the chroot with a fully
    # bootstrapped pacman (see configure_system phase 2) -- that avoids the fragile
    # single-shot pacstrap "target not found" for [multilib] packages.
    PACKAGES="base base-devel linux-zen linux-zen-headers linux-lts linux-lts-headers linux-firmware \
btrfs-progs grub efibootmgr os-prober ntfs-3g timeshift \
networkmanager cronie sudo vim git"

    say "Installing base system + kernels (~3-5 min)..."
    pacstrap -K /mnt ${PACKAGES} 2>&1 | tail -3
    genfstab -U /mnt >> /mnt/etc/fstab
    # [archlinuxcn] is enabled + paru installed later in configure_system(), not here.
    ok "Base system installed"
}

# Enable the archlinuxcn repo and install paru (AUR helper) into the target system.
# WHY: paru lives in archlinuxcn, not [core]/[extra]. If we DON'T pre-enable the repo,
# the user hits a chicken-and-egg trap on first boot: "I need an AUR helper" -> "install
# paru" -> "paru is in archlinuxcn" -> "enable archlinuxcn first" (and paru is prebuilt
# there, so it is just `pacman -S paru` once the repo is on). We break the loop by
# enabling the repo and shipping paru preinstalled.
# BOOTSTRAP: the archlinuxcn db/keyring are signed by a key a fresh pacman keyring does
# NOT yet trust. We add the repo with SigLevel=Optional so the unknown-key signature only
# WARNS (does not block) the keyring install; once archlinuxcn-keyring lands, the key is in
# the keyring, and we lock the repo back to Required DatabaseOptional for proper checks.
setup_archlinuxcn() {
    say "Enabling archlinuxcn repo + installing paru (AUR helper)..."
    if ! grep -q '^\[archlinuxcn\]' /mnt/etc/pacman.conf 2>/dev/null; then
        cat >> /mnt/etc/pacman.conf <<'EOF'

[archlinuxcn]
SigLevel = Optional
Server = https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/$arch
EOF
    fi
    if arch-chroot /mnt bash -c "pacman -Sy --noconfirm && pacman -S --noconfirm archlinuxcn-keyring && pacman -S --noconfirm paru" >/tmp/archlinuxcn.log 2>&1; then
        ok "archlinuxcn enabled + paru installed"
    else
        echo "  ----- archlinuxcn/paru install error -----"; sed 's/^/  /' /tmp/archlinuxcn.log; echo "  -------------------------------------"
        warn "archlinuxcn/paru install failed -- enable it manually after first boot"
    fi
    # Lock the repo to proper signature checking now that its keyring is in place.
    sed -i '/^\[archlinuxcn\]/,/^Server = / s/^SigLevel = Optional/SigLevel = Required DatabaseOptional/' /mnt/etc/pacman.conf
}

# Fallback that runs ONLY when grub-mkconfig could not produce /boot/grub/grub.cfg
# (e.g. a cross-disk btrfs root that grub-probe cannot map). We do NOT replace the
# standard grub-install flow -- we only write a static grub.cfg that locates the root by
# FS UUID, with no dependency on grub-probe device mapping or fragile disk numbering.
# Sets GRUB_OK=1 so the end-of-run "bootloader not installed" warning does not fire.
build_cross_disk_grub() {
    say "grub.cfg missing (cross-disk / unmappable btrfs root?): writing a static grub.cfg fallback"
    local root_uuid efi_uuid efi_disk efi_partno k pkg
    root_uuid=$(blkid -s UUID -o value "${ROOT_PART}" 2>/dev/null)
    efi_uuid=$(blkid -s UUID -o value "${EFI_PART}" 2>/dev/null)
    efi_disk=$(lsblk -no PKNAME "${EFI_PART}" 2>/dev/null | head -1)
    efi_partno=$(lsblk -no PARTN "${EFI_PART}" 2>/dev/null | head -1)
    [ -n "${root_uuid}" ] || { warn "could not read root FS UUID; skipping GRUB fallback"; return 1; }

    # The standard grub-install (run earlier) should have installed grubx64.efi. If it did
    # not (it failed earlier), try once more so the fallback is self-sufficient.
    if [ ! -f /mnt/boot/efi/EFI/GRUB/grubx64.efi ] && [ ! -f /mnt/boot/efi/EFI/archlinux/grubx64.efi ]; then
        arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB 2>/tmp/grub.err \
            && ok "GRUB EFI image installed (fallback)" \
            || { echo "  ----- grub-install error -----"; sed 's/^/  /' /tmp/grub.err; echo "  --------------------------------"; warn "GRUB fallback incomplete; boot the ISO and run grub-install manually"; }
    fi

    # Static grub.cfg: locate the root by FS UUID only -- no device.map, no hardcoded disk
    # numbers, no embedded early config. Works for any UEFI btrfs(@) install.
    local nv=""
    [ "${GPU_FAMILY}" = "nvidia" ] && nv="nvidia_drm.modeset=1 nvidia_drm.fbdev=1"
    {
        echo '# Generated by seikabook-os-install (static grub.cfg fallback)'
        echo "set default=0"
        echo "set timeout=5"
        echo "insmod part_gpt"
        echo "insmod btrfs"
        echo "insmod fat"
        echo "insmod chain"
        echo "insmod linux"
        echo "insmod normal"
        echo "insmod search"
        echo "insmod search_fs_uuid"
        echo "insmod gzio"
        echo "insmod efi_gop"
        echo "search --fs-uuid --no-floppy --set=root ${root_uuid}"
        for k in /mnt/boot/vmlinuz-*; do
            [ -e "$k" ] || continue
            pkg=${k##*/vmlinuz-}
            echo "menuentry 'Arch Linux (${pkg})' --class arch --class gnu-linux --class gnu --class os {"
            echo "    search --fs-uuid --no-floppy --set=root ${root_uuid}"
            echo "    linux /boot/vmlinuz-${pkg} root=UUID=${root_uuid} rw ${nv} rootflags=subvol=@"
            echo "    initrd /boot/initramfs-${pkg}.img"
            echo "}"
            if [ -f "/mnt/boot/initramfs-${pkg}-fallback.img" ]; then
                echo "menuentry 'Arch Linux (${pkg} - fallback)' --class arch --class gnu-linux --class gnu --class os {"
                echo "    search --fs-uuid --no-floppy --set=root ${root_uuid}"
                echo "    linux /boot/vmlinuz-${pkg} root=UUID=${root_uuid} rw ${nv} rootflags=subvol=@"
                echo "    initrd /boot/initramfs-${pkg}-fallback.img"
                echo "}"
            fi
        done
        if [ "${KEEP_WINDOWS}" = "1" ] && [ -n "${efi_uuid}" ]; then
            echo "menuentry 'Windows Boot Manager' --class windows --class os {"
            echo "    insmod fat"
            echo "    insmod chain"
            echo "    search --fs-uuid --no-floppy --set=root ${efi_uuid}"
            echo "    chainloader (\${root})/EFI/Microsoft/Boot/bootmgfw.efi"
            echo "}"
        fi
        echo "menuentry 'UEFI Firmware Settings' {"
        echo "    fwsetup"
        echo "}"
    } > /mnt/boot/grub/grub.cfg
    ok "static grub.cfg written ($(wc -l < /mnt/boot/grub/grub.cfg) lines)"

    # Ensure a GRUB NVRAM entry exists and is first.
    if [ -d /sys/firmware/efi/efivars ] || mount -t efivarfs efivarfs /sys/firmware/efi/efivars 2>/dev/null; then
        if ! efibootmgr 2>/dev/null | grep -q '\* GRUB'; then
            [ -n "${efi_disk}" ] && [ -n "${efi_partno}" ] \
                && efibootmgr -c -d "/dev/${efi_disk}" -p "${efi_partno}" -L GRUB -l '\EFI\GRUB\GRUBX64.EFI' >/dev/null 2>&1 || true
        fi
        local gnum; gnum=$(efibootmgr 2>/dev/null | sed -n 's/^Boot\([0-9A-Fa-f]*\)\* GRUB.*/\1/p' | head -1)
        if [ -n "$gnum" ]; then
            local cur; cur=$(efibootmgr 2>/dev/null | sed -n 's/^BootOrder: //p')
            local new="$gnum"
            for x in $(echo "$cur" | tr ',' ' '); do [ "$x" = "$gnum" ] || new="$new,$x"; done
            efibootmgr -o "$new" >/dev/null 2>&1 || true
            ok "GRUB set as first NVRAM boot entry"
        fi
    fi
    GRUB_OK=1
    return 0
}

# ════════════════════════════════════════════════════════════
# 8. chroot system configuration
# ════════════════════════════════════════════════════════════
configure_system() {
    say "Configuring system (timezone/locale/user/boot/desktop)..."

    # Write benchmark result into the new system (pacstrap does not copy host mirrorlist)
    if [ "${AUTO_MIRROR}" = "1" ] && [ -n "${BEST:-}" ]; then
        echo "Server = ${BEST}/\$repo/os/\$arch" > /mnt/etc/pacman.d/mirrorlist
    fi

    # Phase 2: install desktop + GPU + 32-bit packages INSIDE the chroot with a fully
    # bootstrapped pacman. This is the robust, standard Arch way: the chroot pacman
    # Phase 2 runs inside the chroot with a fully bootstrapped pacman, so all [extra]
    # packages (desktop, nvidia-dkms) resolve reliably. 32-bit (multilib) is opt-in and
    # handled by the user post-boot, so it is intentionally absent here.
    local extra_pkgs=""
    [ "${DESKTOP}" = "kde" ]      && extra_pkgs+=" plasma-meta plasma-login-manager konsole dolphin ark gwenview fcitx5-im fcitx5-chinese-addons fcitx5-configtool noto-fonts noto-fonts-cjk noto-fonts-emoji wqy-microhei"
    [ "${DESKTOP}" = "gnome" ]    && extra_pkgs+=" gnome gnome-extra gdm fcitx5-im fcitx5-chinese-addons noto-fonts noto-fonts-cjk"
    [ "${DESKTOP}" = "hyprland" ] && extra_pkgs+=" hyprland sddm waybar rofi-wayland kitty fcitx5-im fcitx5-chinese-addons noto-fonts noto-fonts-cjk"
    [ "${DESKTOP}" = "headless" ] && extra_pkgs+=" openssh"
    if [ "${GPU_FAMILY}" = "nvidia" ] && [ "${NVIDIA_DKMS_OK}" = "1" ]; then
        extra_pkgs+=" nvidia-dkms nvidia-utils nvidia-settings"
        # 32-bit GL (lib32-nvidia-utils, in [multilib]) is OPTIONAL -- only for
        # Steam/Proton/Wine 32-bit games. Intentionally NOT installed by default: it
        # would force-enable [multilib] and is unrelated to a working desktop. Gamers
        # enable [multilib] + `pacman -S lib32-nvidia-utils` after first boot (the
        # Steam setup guide covers this).
    fi
    if [ -n "${extra_pkgs}" ]; then
        say "Installing desktop + GPU drivers via pacman (chroot, phase 2)..."
        if arch-chroot /mnt bash -c "pacman -Syu --noconfirm && pacman -S --noconfirm ${extra_pkgs}" >/tmp/phase2.log 2>&1; then
            ok "Desktop + GPU packages installed (chroot phase 2)"
        else
            tail -15 /tmp/phase2.log
            die "phase-2 package install failed (desktop/GPU) -- see output above"
        fi
    fi

    # archlinuxcn + paru (AUR helper) -- breaks the "can't install paru without the
    # repo, can't enable the repo without paru" chicken-and-egg for new users.
    setup_archlinuxcn

    arch-chroot /mnt bash -c "
set -e
# timezone
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
hwclock --systohc
# locale
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/^#zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
locale-gen >/dev/null 2>&1
echo 'LANG=zh_CN.UTF-8' > /etc/locale.conf
# hostname
echo '${HOSTNAME}' > /etc/hostname
printf '127.0.0.1 localhost\n::1 localhost\n127.0.1.1 ${HOSTNAME}\n' > /etc/hosts
    # Mirror (chroot also uses benchmark result - written from outside)
    # Input method env vars
printf 'GTK_IM_MODULE=fcitx\nQT_IM_MODULE=fcitx\nXMODIFIERS=@im=fcitx\n' > /etc/environment
" 2>&1 | tail -2

    # root password
    echo
    while :; do
        read -rsp "  Set root password: " PASS1; echo
        read -rsp "  Retype: " PASS2; echo
        [ -n "${PASS1}" ] && [ "${PASS1}" = "${PASS2}" ] && break
        warn "Mismatch or empty, try again"
    done
    echo "root:${PASS1}" | arch-chroot /mnt chpasswd

    # user
    echo
    while :; do
        read -rsp "  Set password for user ${USER_NAME}: " PASS1; echo
        read -rsp "  Retype: " PASS2; echo
        [ -n "${PASS1}" ] && [ "${PASS1}" = "${PASS2}" ] && break
        warn "Mismatch or empty, try again"
    done
    arch-chroot /mnt useradd -m -G wheel -s /bin/bash "${USER_NAME}"
    echo "${USER_NAME}:${PASS1}" | arch-chroot /mnt chpasswd
    echo "%wheel ALL=(ALL:ALL) ALL" > /mnt/etc/sudoers.d/10-wheel
    chmod 440 /mnt/etc/sudoers.d/10-wheel
    ok "User ${USER_NAME} created (added to sudo group)"

    # bootloader
    GRUB_OK=1
    if [ "${BOOT_MODE}" = "UEFI" ]; then
        # Modern layout: the ESP is mounted at /boot/efi; the KERNELS live on the BTRFS
        # root (/boot), NOT on the ESP. So even a tiny 200M ESP is plenty - GRUB only puts
        # grubx64.efi + its modules there. This avoids the old failure where two ~120M
        # initramfs files did not fit on a 200M ESP (and a buggy cleanup loop then deleted
        # the live kernels, leaving GRUB with a Windows-only menu).
        mkdir -p /mnt/boot/efi
        if ! mountpoint -q /mnt/boot/efi; then
            mount "${EFI_PART}" /mnt/boot/efi || die "cannot mount ESP ${EFI_PART} at /mnt/boot/efi -- grub-install needs it"
        fi
        # keep-existing ESP: clear stale Seikabook/Arch GRUB artifacts so a re-run does not
        # accumulate. Windows files (EFI/Microsoft, EFI/Boot, System Volume Information) are
        # NEVER touched. Kernels are not on the ESP in this layout, so nothing to delete here.
        if [ "${PART_EFI_FMT}" != "1" ]; then
            rm -rf /mnt/boot/efi/grub /mnt/boot/efi/EFI/GRUB /mnt/boot/efi/EFI/arch /mnt/boot/efi/EFI/Linux
            FREE=$(df -m /mnt/boot/efi 2>/dev/null | awk 'NR==2{print $4}')
            [ -n "${FREE}" ] && [ "${FREE}" -lt 30 ] && warn "EFI partition only ${FREE}M free; GRUB files may not fit, consider a larger ESP"
        fi
        # efivarfs must be mounted so grub-install can register the boot entry
        [ -d /sys/firmware/efi ] && { [ -d /sys/firmware/efi/efivars ] || \
            mount -t efivarfs efivarfs /sys/firmware/efi/efivars 2>/dev/null \
            || warn "efivarfs not mounted; GRUB NVRAM entry may not be created (add it from the firmware boot menu)"; }
        rm -f /tmp/grub.err
        if arch-chroot /mnt grub-install --target=x86_64-efi \
            --efi-directory=/boot/efi --bootloader-id=GRUB 2>/tmp/grub.err; then
            ok "GRUB UEFI installed"
            # Make GRUB the FIRST NVRAM boot entry, otherwise the firmware may default to
            # Windows Boot Manager and the user never sees the GRUB menu.
            local gnum; gnum=$(efibootmgr 2>/dev/null | sed -n 's/^Boot\([0-9A-Fa-f]*\)\* GRUB.*/\1/p' | head -1)
            if [ -n "$gnum" ]; then
                local cur; cur=$(efibootmgr 2>/dev/null | sed -n 's/^BootOrder: //p')
                local new="$gnum"
                for x in $(echo "$cur" | tr ',' ' '); do
                    [ "$x" = "$gnum" ] || new="$new,$x"
                done
                efibootmgr -o "$new" >/dev/null 2>&1 || true
                ok "GRUB set as the first NVRAM boot entry"
            fi
        else
            echo "  ----- grub-install error -----"; sed 's/^/  /' /tmp/grub.err; echo "  --------------------------------"
            GRUB_OK=0
        fi
    else
        rm -f /tmp/grub.err
        if arch-chroot /mnt grub-install --target=i386-pc "${PART_ROOT_DEV}" 2>/tmp/grub.err; then
            ok "GRUB BIOS installed"
        else
            echo "  ----- grub-install error -----"; sed 's/^/  /' /tmp/grub.err; echo "  --------------------------------"
            GRUB_OK=0
        fi
    fi
    # dual-boot
    if [ "${KEEP_WINDOWS}" = "1" ]; then
        echo 'GRUB_DISABLE_OS_PROBER=false' >> /mnt/etc/default/grub
    fi
    # btrfs root subvolume: the system lives in @ (10_linux handles this automatically)
    # NVIDIA: enable DRM modeset + fbdev so Wayland (and the console) work on the
    # proprietary/open modules. Without modeset=1 a Wayland session will not start.
    if [ "${GPU_FAMILY}" = "nvidia" ] && [ "${NVIDIA_DKMS_OK}" = "1" ]; then
        grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' /mnt/etc/default/grub \
            || echo 'GRUB_CMDLINE_LINUX_DEFAULT=""' >> /mnt/etc/default/grub
        sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 nvidia_drm.modeset=1 nvidia_drm.fbdev=1"/' /mnt/etc/default/grub
    fi
    # default to the FIRST menu entry = linux-zen (highest version, so it sorts first),
    # never linux-lts. 10_linux always puts `Arch Linux` (linux-zen) first; linux-lts
    # lives in the "Advanced options" submenu. Pin it so a rebuild can never silently boot lts.
    echo 'GRUB_DEFAULT=0' >> /mnt/etc/default/grub
    echo 'GRUB_SAVEDEFAULT=false' >> /mnt/etc/default/grub
    # Clean device.map so grub-probe uses its auto-generated mapping (a stale hand-written
    # device.map is the classic cause of "cannot find a GRUB drive for /dev/...").
    rm -f /mnt/boot/grub/device.map
    if [ "${GRUB_OK}" = "1" ]; then
        arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | tail -3
    fi
    # Cross-disk btrfs root (or any unmappable root): grub-mkconfig/grub-probe cannot
    # produce grub.cfg, so build a self-contained GRUB as a fallback. Only triggers when
    # grub.cfg is still missing, so it never interferes with a normal successful install.
    if [ "${BOOT_MODE}" = "UEFI" ] && [ ! -f /mnt/boot/grub/grub.cfg ]; then
        build_cross_disk_grub || warn "cross-disk GRUB fallback failed; the system may not boot"
    fi

    # NVIDIA: early-load the driver modules so they load BEFORE the display manager
    # (and before nouveau could ever appear) - this is what makes the desktop snappy
    # instead of falling back to the slow nouveau / llvmpipe software renderer.
    # nvidia-utils already blacklists nouveau via /usr/lib/modprobe.d, so we only
    # need to pin the nvidia modules into the initramfs and rebuild it.
    if [ "${GPU_FAMILY}" = "nvidia" ] && [ "${NVIDIA_DKMS_OK}" = "1" ]; then
        sed -i 's/^MODULES=(/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm /' /mnt/etc/mkinitcpio.conf
        arch-chroot /mnt mkinitcpio -P 2>&1 | tail -2
        ok "NVIDIA modules added to initramfs (early-load) and initramfs rebuilt"
    fi

    # services - enable from OUTSIDE the chroot with `systemctl --root=/mnt`, which
    # resolves [Install] WantedBy *and* Alias against the target root (verified).
    # Timeshift ships no .timer on Arch, so its scheduling is handled via cron below.
    # All enables are best-effort (guarded) so a single failure can never abort the install.
    enable_svc() { systemctl --root=/mnt enable "$1" >/dev/null 2>&1 || true; }
    enable_svc NetworkManager
    enable_svc cronie
    # Display manager.
    # IMPORTANT: on Arch a DM unit carries `[Install] Alias=display-manager.service`
    # and graphical.target pulls display-manager.service. There is NO
    # "display-manager.target.wants" directory -- symlinking into it enables NOTHING.
    # Enabling correctly must produce /etc/systemd/system/display-manager.service,
    # which `systemctl --root=/mnt enable` does (verified: it honours the Alias).
    #
    # KDE: since Plasma 6.6 the login manager is Plasma Login Manager
    # (pkg plasma-login-manager, unit plasmalogin.service) -- a KDE fork of SDDM that
    # replaces it and is already a plasma-meta dependency. Its greeter runs natively on
    # kwin_wayland (plasma-login-kwin_wayland.service), so the session is Wayland by
    # default and no X11 fallback config is needed. Theming is integrated with Plasma,
    # so there is no external greeter theme to pin.
    local dm=""
    case "${DESKTOP}" in
        kde)      dm="plasmalogin" ;;
        gnome)    dm="gdm" ;;
        hyprland) dm="sddm" ;;
        headless) dm="" ;;
    esac
    if [ -n "${dm}" ]; then
        enable_svc "${dm}.service"
        if [ -L /mnt/etc/systemd/system/display-manager.service ]; then
            ok "Display manager enabled: ${dm}"
        else
            warn "Could not enable ${dm}. After first boot, log in on the text console and run:"
            warn "  systemctl enable ${dm}.service"
        fi
    else
        enable_svc sshd
    fi

    # Timeshift BTRFS mode: root is the @ subvolume, snapshots live on the same disk.
    # Snapshots protect the SYSTEM (/), never user data:
    #  - /home selected  -> separate ext4 partition, naturally outside BTRFS, never snapshotted
    #  - /home not picked -> @home subvolume; exclude_home=true excludes it from snapshots
    ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART" 2>/dev/null || true)
    mkdir -p /mnt/etc/timeshift
    cat > /mnt/etc/timeshift/timeshift.json <<EOF
{
  "backup_device_uuid" : "$ROOT_UUID",
  "backup_device" : "$ROOT_PART",
  "btrfs_mode" : "true",
  "snapshot_type" : "BTRFS",
  "scheduled" : "true",
  "schedule_monthly" : "0",
  "schedule_weekly" : "2",
  "schedule_daily" : "1",
  "schedule_boot" : "0",
  "schedule_hourly" : "0",
  "count_monthly" : "0",
  "count_weekly" : "3",
  "count_daily" : "5",
  "count_boot" : "0",
  "count_hourly" : "0",
  "snapshot_size" : "0",
  "exclude" : [
    "- /var/log/**",
    "- /var/cache/pacman/pkg/**",
    "- /var/tmp/**"
  ],
  "exclude_home" : "true",
  "workspace" : "/var/tmp/timeshift",
  "date_format" : "%Y-%m-%d_%H-%M-%S",
  "prefix" : "",
  "stop_cron" : "false",
  "restart_cron" : "true",
  "nice" : "19",
  "ionice" : "3",
  "run_ionice" : "true"
}
EOF
    # Scheduled snapshots: Timeshift has NO systemd timer on Arch - it runs via cron.
    # Enable cronie and drop Timeshift's standard cron job (--check every 10 min creates
    # the daily/weekly snapshots defined in the json above).
    cat > /mnt/etc/cron.d/timeshift <<'EOF'
*/10 * * * * root /usr/bin/timeshift --check --scripted
EOF
    # Snapshot BEFORE every pacman transaction, so a bad update is always revertible.
    mkdir -p /mnt/etc/pacman.d/hooks
    cat > /mnt/etc/pacman.d/hooks/50-timeshift-pre.hook <<'EOF'
[Trigger]
Operation = Upgrade
Operation = Install
Operation = Remove
Type = Package
Target = *

[Action]
Description = Timeshift: creating snapshot before pacman transaction...
When = PreTransaction
Exec = /usr/bin/timeshift --create --comments "pacman pre-upgrade" --scripted
EOF
    ok "Timeshift (BTRFS mode) configured: scheduled via cronie + pre-upgrade pacman hook"
    ok "Services enabled (NetworkManager, ${dm:-sshd}, cronie)"
}

# ════════════════════════════════════════════════════════════
# 9. Main flow
# ════════════════════════════════════════════════════════════
main() {
    detect_hardware
    suggest_plan
    ask_questions
    choose_partition
    echo
    say "────────── Partition plan review ──────────"
    fmt_t() {
        local d="$1" t="$2"
        if [[ "$t" == free:* ]]; then
            local s="${t#free:}"; [ "$s" = "0" ] && s="all remaining"
            echo "$d free space (${s})"
        else
            echo "${t#part:}"
        fi
    }
    echo "  EFI  : $(fmt_t "$PART_EFI_DEV" "$PART_EFI_TGT")  $([ "$PART_EFI_FMT" = "1" ] && echo '[format]' || echo '[keep, mount only]')"
    echo "  /    : $(fmt_t "$PART_ROOT_DEV" "$PART_ROOT_TGT")"
    if [ -n "$PART_HOME_DEV" ]; then
        echo "  /home: $(fmt_t "$PART_HOME_DEV" "$PART_HOME_TGT") (ext4$([ "$PART_HOME_FMT" = "1" ] && echo ', [format]' || echo ', [keep data]'))"
    else
        echo "  /home: BTRFS @home subvolume (same disk; Timeshift excludes it - user data not snapshotted)"
    fi
    echo "  swap : $(fmt_t "$PART_SWAP_DEV" "$PART_SWAP_TGT")"
    echo "  Boot : ${BOOT_MODE}   Desktop: ${DESKTOP}   Hostname: ${HOSTNAME}   User: ${USER_NAME}"
    echo "  Windows: $([ "${KEEP_WINDOWS}" = "1" ] && echo keep dual-boot || echo none)   Mirror: $([ "${AUTO_MIRROR}" = "1" ] && echo auto-benchmark || echo manual)"
    echo "─────────────────────────────────"
    echo "  WARNING: the above will ERASE data on the selected partitions/disks, and is NOT reversible!"
    read -rp "  Type 'yes' to confirm and start partitioning (case-insensitive): " ans
    [[ "${ans,,}" == "yes" ]] || { say "Cancelled, no changes made"; exit 0; }

    [ "${AUTO_MIRROR}" = "1" ] && bench_mirror
    setup_disk
    verify_layout || die "Partition layout invalid - aborted before installing the base system."
    install_base
    configure_system

    echo
    echo "══════════════════════════════════════════════"
    echo -e "${C_GREEN}[ OK ] Installation complete!${C_RESET}  The system is installed and ready to boot."
    echo "  ── Next steps ──"
    echo "  1. Remove the install media, then reboot:   reboot"
    echo "  2. In GRUB: default = linux-zen kernel; recover via 'Advanced options' -> linux-lts"
    echo "  3. After login, update:   sudo pacman -Syu"
    echo "  4. Snapshots are ON: Timeshift (daily+weekly, and auto before every pacman update)."
    echo "     Manual restore point:   sudo timeshift --create --comments 'first-boot'"
    echo "  5. Snappier kernel?   sudo bash -c \"\$(curl -sSL https://gitee.com/seikabook/seikabook-os-install/raw/master/seika-kernel.sh)\""
    echo "══════════════════════════════════════════════"
    if [ "${GRUB_OK:-1}" = "0" ]; then
        echo
        warn "GRUB bootloader was NOT installed (see error above). The system is fully installed but will NOT boot until you fix it."
        echo "  From the live ISO, chroot and install GRUB manually:"
        echo "    mount -o subvol=@ ${ROOT_PART} /mnt"
        echo "    mount ${EFI_PART} /mnt/boot/efi"
        echo "    [ -d /sys/firmware/efi/efivars ] || mount -t efivarfs efivarfs /sys/firmware/efi/efivars"
        echo "    arch-chroot /mnt"
        if [ "${BOOT_MODE}" = "UEFI" ]; then
            echo "    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB"
        else
            echo "    grub-install --target=i386-pc ${PART_ROOT_DEV}"
        fi
        echo "    grub-mkconfig -o /boot/grub/grub.cfg"
        echo "    exit"
    fi
}

main "$@"

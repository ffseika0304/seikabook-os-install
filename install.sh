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

    # 2) Locale: archiso is already UTF-8; ensure zh_CN is available.
    sed -i 's/^#zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen 2>/dev/null || true
    locale-gen >/dev/null 2>&1 || true
    export LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8

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
    echo "Memory : $(free -h | awk '/^Mem:/{print $2}')"
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
        nvidia) echo "  - GPU: NVIDIA - use nvidia-dkms after install (this script installs open nouveau first so you can boot)" ;;
        intel)  echo "  - GPU: Intel - i915/xe open driver, zero config" ;;
        *)      echo "  - GPU: unknown - check with lspci after install" ;;
    esac
    echo "  - Kernel: official linux + linux-lts dual kernel preinstalled (switch in GRUB), enhanced kernel optional later"
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
    read -rp "  Keep Windows dual-boot? [y/N] " ans
    [[ "${ans,,}" == "y" ]] && KEEP_WINDOWS=1 || KEEP_WINDOWS=0
    read -rp "  Auto-pick fastest China mirror? [Y/n] " ans
    [[ "${ans,,}" == "n" ]] && AUTO_MIRROR=0 || AUTO_MIRROR=1
    read -rp "  Hostname? [default arch] " ans
    HOSTNAME="${ans:-arch}"
    read -rp "  Username? [default seika] " ans
    USER_NAME="${ans:-seika}"
}

# ════════════════════════════════════════════════════════════
# 4. Partition selection (guided: one-click auto / manual per mountpoint)
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
    local disks=($(lsblk -d -rno NAME)); local i=1
    echo "  Available disks:"
    for d in "${disks[@]}"; do
        local sz tr
        sz=$(lsblk -d -rno SIZE "/dev/$d" 2>/dev/null)
        tr=$(lsblk -d -rno TRAN "/dev/$d" 2>/dev/null)
        echo "    $i) /dev/$d  ${sz}  (${tr:-unknown})"; i=$((i+1))
    done
    while :; do
        read -rp "  Pick disk number: " n
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
        read -rp "  Pick number (0=free space): " n
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

oneclick_partition() {
    local ram; ram=$(free -g 2>/dev/null | awk '/^Mem:/{print $2}'); [ -z "$ram" ] && ram=4; [ "$ram" -lt 2 ] && ram=2
    say "One-click mode: pick a disk, auto split EFI(1G)+/(rest, BTRFS @; /home stays inside /)+swap(${ram}G) from free space"
    pick_disk
    PART_EFI_DEV="$_DISK"; PART_EFI_TGT="free:+1G"; PART_EFI_FMT=1
    PART_ROOT_DEV="$_DISK"; PART_ROOT_TGT="free:0"
    PART_SWAP_DEV="$_DISK"; PART_SWAP_TGT="free:+${ram}G"
}

choose_disk() {
    echo
    say "Partition plan: 1) one-click (pick a disk, auto split)   2) manual (per mountpoint, recommended)"
    read -rp "  Choose [1/2, default 2]: " m
    [ "${m:-2}" = "1" ] && oneclick_partition || manual_partition
}

# ════════════════════════════════════════════════════════════
# 5. Partition + format + BTRFS subvolumes
# ════════════════════════════════════════════════════════════
setup_disk() {
    say "Partitioning and mounting per your plan (writing to disk)..."
    # $1=disk $2=tgt(part:/dev/xxx | free:+SIZE | free:0) $3=typecode -> prints partition device path
    make_part() {
        local dev="$1" tgt="$2" type="$3"
        if [[ "$tgt" == free:* ]]; then
            local size="${tgt#free:}"
            sgdisk -n0:0:"${size}" -t0:"${type}" "${dev}" >/dev/null
            partprobe "${dev}"
            local new; new=$(lsblk -rn -o NAME "${dev}" | tail -1)
            echo "/dev/${new}"
        else
            echo "${tgt#part:}"
        fi
    }
    EFI_PART=$(make_part "$PART_EFI_DEV" "$PART_EFI_TGT" ef00)
    [ "$PART_EFI_FMT" = "1" ] && mkfs.fat -F32 "$EFI_PART" >/dev/null && ok "EFI $EFI_PART (FAT32)"

    SWAP_PART=$(make_part "$PART_SWAP_DEV" "$PART_SWAP_TGT" 8200)
    mkswap "$SWAP_PART" >/dev/null && swapon "$SWAP_PART" && ok "swap $SWAP_PART"

    ROOT_PART=$(make_part "$PART_ROOT_DEV" "$PART_ROOT_TGT" 8300)
    mkfs.btrfs -f "$ROOT_PART" >/dev/null && ok "root $ROOT_PART (BTRFS)"
    mount "$ROOT_PART" /mnt
    btrfs subvolume create /mnt/@ >/dev/null
    btrfs subvolume create /mnt/@home >/dev/null
    umount /mnt

    MOUNT_OPTS="noatime,compress=zstd:1"
    mount -o "${MOUNT_OPTS},subvol=@" "$ROOT_PART" /mnt
    mkdir -p /mnt/boot
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
    mount "$EFI_PART" /mnt/boot
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
    PACKAGES="base base-devel linux linux-firmware linux-lts \
btrfs-progs grub efibootmgr os-prober ntfs-3g timeshift grub-btrfs \
networkmanager sudo vim git \
$( [ "${DESKTOP}" = "kde" ] && echo "plasma-meta sddm konsole dolphin ark gwenview \
fcitx5-im fcitx5-chinese-addons fcitx5-configtool \
noto-fonts noto-fonts-cjk noto-fonts-emoji wqy-microhei" || true ) \
$( [ "${DESKTOP}" = "gnome" ] && echo "gnome gnome-extra gdm fcitx5-im fcitx5-chinese-addons \
noto-fonts noto-fonts-cjk" || true ) \
$( [ "${DESKTOP}" = "hyprland" ] && echo "hyprland waybar rofi-wayland kitty \
fcitx5-im fcitx5-chinese-addons noto-fonts noto-fonts-cjk" || true ) \
$( [ "${DESKTOP}" = "headless" ] && echo "openssh cronie" || true )"

    say "Installing base system + desktop (~10-15 min, depends on network)..."
    pacstrap -K /mnt ${PACKAGES} 2>&1 | tail -3
    genfstab -U /mnt >> /mnt/etc/fstab
    ok "Base system installed"
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
    if [ "${BOOT_MODE}" = "UEFI" ]; then
        arch-chroot /mnt grub-install --target=x86_64-efi \
            --efi-directory=/boot --bootloader-id=GRUB >/dev/null 2>&1 \
            && ok "GRUB UEFI installed" || die "GRUB UEFI install failed, system will not boot"
    else
        arch-chroot /mnt grub-install --target=i386-pc "${PART_ROOT_DEV}" >/dev/null 2>&1 \
            && ok "GRUB BIOS installed" || die "GRUB BIOS install failed, system will not boot"
    fi
    # dual-boot
    if [ "${KEEP_WINDOWS}" = "1" ]; then
        echo 'GRUB_DISABLE_OS_PROBER=false' >> /mnt/etc/default/grub
    fi
    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | tail -1

    # services
    arch-chroot /mnt systemctl enable NetworkManager >/dev/null 2>&1
    case "${DESKTOP}" in
        kde) arch-chroot /mnt systemctl enable sddm >/dev/null 2>&1 ;;
        gnome) arch-chroot /mnt systemctl enable gdm >/dev/null 2>&1 ;;
        hyprland) arch-chroot /mnt systemctl enable sddm >/dev/null 2>&1 ;;
        headless) arch-chroot /mnt systemctl enable sshd >/dev/null 2>&1 ;;
    esac

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
    arch-chroot /mnt systemctl enable timeshift.timer >/dev/null 2>&1
    arch-chroot /mnt systemctl enable grub-btrfsd.service >/dev/null 2>&1 || true
    echo 'GRUB_BTRFS_Timeshift=true' >> /mnt/etc/default/grub-btrfs 2>/dev/null || true
    ok "Timeshift (BTRFS mode) configured + scheduled; grub-btrfs enabled"
    ok "Services enabled"
}

# ════════════════════════════════════════════════════════════
# 9. Main flow
# ════════════════════════════════════════════════════════════
main() {
    detect_hardware
    suggest_plan
    ask_questions
    choose_disk
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
    install_base
    configure_system

    echo
    echo "══════════════════════════════════════════════"
    ok "Installation complete!"
    echo "  1. Run 'exit' / 'reboot' (remember to remove the install media)"
    echo "  2. In GRUB: default is the linux kernel; fall back via 'Advanced options' -> linux-lts"
    echo "  3. After login, first thing: sudo pacman -Syu to update"
    echo "  4. Snapshots: Timeshift is preconfigured (BTRFS mode, daily+weekly). Make a restore point:"
    echo "     sudo timeshift --create --comments 'first-boot'"
    echo "  5. Want a snappier desktop? sudo bash -c \"\$(curl -sSL https://gitee.com/seikabook/seikabook-os-install/raw/master/seika-kernel.sh)\""
    echo "══════════════════════════════════════════════"
}

main "$@"

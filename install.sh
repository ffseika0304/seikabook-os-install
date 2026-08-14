#!/usr/bin/env bash
# ============================================================
#  Seikabook OS Install — 你的硬件，它的灵魂。
#  理念：让中文母语的小白先进入 KDE 桌面，再开始学习，
#        而不是卡在 archiso 的黑屏命令行里。
#
#  第一段：装系统（本脚本）—— 从 Arch ISO 启动，约 30 分钟到 KDE 桌面
#  第二段：seika-kernel.sh（可选）—— 进系统后编译 zen+BORE 增强内核
#
#  用法：bash install.sh    （仅限 archiso 环境；不接收复杂参数）
# ============================================================
set -euo pipefail

C_RESET="\e[0m"; C_BLUE="\e[1;34m"; C_GREEN="\e[1;32m"; C_YEL="\e[1;33m"; C_RED="\e[1;31m"
say()  { echo -e "${C_BLUE}[Seikabook]${C_RESET} $*"; }
ok()   { echo -e "${C_GREEN}[ OK ]${C_RESET} $*"; }
warn() { echo -e "${C_YEL}[注意]${C_RESET} $*"; }
die()  { echo -e "${C_RED}[错误]${C_RESET} $*" >&2; exit 1; }

# ────────────────────────────────────────────────────────────
# 0.0 管道自愈：curl | bash 时 stdin 是管道，交互 read/select 会
#     读到 EOF 自断。检测到非终端输入就重新以 /dev/tty 重跑自身。
# ────────────────────────────────────────────────────────────
SELF_URL="https://gitee.com/seikabook/seikabook-os-install/raw/master/install.sh"
if [ ! -t 0 ] && [ -z "${SEIKA_REEXEC:-}" ]; then
    say "检测到管道输入，重新以终端交互方式运行…"
    curl -fsSL "$SELF_URL" -o /tmp/seika-install.sh \
        || die "重新下载安装脚本失败，请改用两步法：curl -o /tmp/i.sh && bash /tmp/i.sh"
    export SEIKA_REEXEC=1
    exec bash /tmp/seika-install.sh < /dev/tty
fi

# ════════════════════════════════════════════════════════════
# 0.0 前期准备：中文显示环境 + 镜像源（必须排在最前）
#     直接在 archiso 本地 tty 跑时默认渲染不了中文，交互会乱码；
#     SSH 连 archiso 由客户端渲染中文，不受影响。本段让本地 tty
#     也能显示中文，并提前配好镜像源以加速后续所有下载。
# ════════════════════════════════════════════════════════════
bench_mirror() {
    say "测速国内镜像源..."
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
    [ -n "${BEST}" ] || die "所有镜像源都不可达，请检查网络"
    ok "最快源: ${BEST} (${BEST_T}s)"
    echo "Server = ${BEST}/\$repo/os/\$arch" > /etc/pacman.d/mirrorlist
}

preflight() {
    # 1) 镜像源：提前测速选最快国内源（保证下载/字体不慢）。
    #    包在子 shell 里，网络不可达时仅警告、不致命退出。
    ( bench_mirror ) 2>/dev/null || true

    # 2) 中文 locale（archiso 默认已是 UTF-8，这里确保 zh_CN 可用并导出）
    sed -i 's/^#zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen 2>/dev/null || true
    locale-gen >/dev/null 2>&1 || true
    export LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8

    # 3) 中文字体 + 控制台中文字体（unifont 供 setfont 在原生 tty 显示中文）
    pacman -Sy --noconfirm --needed wqy-zenhei noto-fonts-cjk unifont >/dev/null 2>&1 || true

    # 4) 物理 tty（非 SSH）用 setfont 加载 unifont，使原生控制台可显示中文；SSH 下跳过
    #    setfont 直接改内核控制台字体，不依赖 framebuffer 终端/fontconfig，比 fbterm 更通用
    if [ -z "${SSH_TTY:-}" ] && [ -t 1 ]; then
        command -v kbd_mode >/dev/null 2>&1 && kbd_mode -u 2>/dev/null || true
        if command -v setfont >/dev/null 2>&1 && setfont unifont 2>/dev/null; then
            ok "已加载 unifont，本地控制台可显示中文"
        else
            warn "加载 unifont 失败，本地控制台中文可能乱码，建议改用 SSH 连接操作（SSH 客户端中文正常）"
        fi
    fi
}
if [ -z "${SEIKA_PREFLIGHT:-}" ]; then
    export SEIKA_PREFLIGHT=1
    preflight
fi

# ════════════════════════════════════════════════════════════
# 0. 基础检查：必须 root、必须 archiso 环境
# ════════════════════════════════════════════════════════════
[ "$(id -u)" -eq 0 ] || die "请以 root 身份运行（从 Arch ISO 启动后执行）"

if [ ! -d /run/archiso ] && [ ! -f /etc/arch-release ]; then
    warn "未检测到 archiso 环境。本脚本用于【全新安装】（从 Arch ISO 启动后运行）。"
    warn "如果你已在运行的系统里，请勿继续——装好后想优化内核请用 seika-kernel.sh。"
    read -rp "确认是在 archiso 安装环境？[y/N] " ans
    [[ "${ans,,}" == "y" ]] || exit 1
fi

say "Seikabook OS Install 启动 —— 先看看你的机器，再决定怎么装。"
echo

# ════════════════════════════════════════════════════════════
# 1. 硬件检测
# ════════════════════════════════════════════════════════════
detect_hardware() {
    echo
    say "────────── 硬件检测 ──────────"
    CPU_VENDOR="$(lscpu 2>/dev/null | awk -F': *' '/^Vendor ID/{print $2; exit}')"
    CPU_MODEL="$(lscpu 2>/dev/null | awk -F': *' '/^Model name/{print $2; exit}')"
    echo "CPU    : ${CPU_MODEL:-未知}（${CPU_VENDOR:-未知} / $(nproc) 线程）"
    case "${CPU_VENDOR,,}" in
        *amd*) CPU_FAMILY="amd" ;;
        *intel*) CPU_FAMILY="intel" ;;
        *) CPU_FAMILY="unknown" ;;
    esac
    GPU_LINE="$(lspci 2>/dev/null | grep -iE 'VGA|3D controller|Display controller' | head -1 || true)"
    echo "GPU    : ${GPU_LINE:-未知}"
    case "${GPU_LINE,,}" in
        *nvidia*) GPU_FAMILY="nvidia" ;;
        *advanced\ micro\ devices*) GPU_FAMILY="amd" ;;
        *intel*) GPU_FAMILY="intel" ;;
        *) GPU_FAMILY="unknown" ;;
    esac
    echo "内存   : $(free -h | awk '/^Mem:/{print $2}')"
    echo "磁盘   :"
    lsblk -d -o NAME,SIZE,MODEL 2>/dev/null | grep -vE 'NAME|loop' | head -6 || true
    if [ -d /sys/firmware/efi ]; then BOOT_MODE="UEFI"; else BOOT_MODE="BIOS"; fi
    echo "引导   : ${BOOT_MODE}"
    echo "────────── 检测完毕 ──────────"
}

# ════════════════════════════════════════════════════════════
# 2. 按硬件给内核/驱动方案
# ════════════════════════════════════════════════════════════
suggest_plan() {
    echo
    say "你的硬件方案："
    case "${CPU_FAMILY}" in
        amd)    echo "  · CPU: AMD → 装好后可用 seika-kernel.sh 编译 zen+BORE 增强内核" ;;
        intel)  echo "  · CPU: Intel → 装好后可用 seika-kernel.sh 编译 zen+BORE 增强内核" ;;
        *)      echo "  · CPU: 未知厂商 → 使用官方内核" ;;
    esac
    case "${GPU_FAMILY}" in
        amd)    echo "  · GPU: AMD → amdgpu + Mesa 开源驱动，零配置" ;;
        nvidia) echo "  · GPU: NVIDIA → 装好后用 nvidia-dkms（本脚本先装开源 nouveau 保证能进桌面）" ;;
        intel)  echo "  · GPU: Intel → i915/xe 开源驱动，零配置" ;;
        *)      echo "  · GPU: 未知 → 装好后用 lspci 再确认" ;;
    esac
    echo "  · 内核: 预装官方 linux + linux-lts 双内核（GRUB 可切换），增强内核后续可选"
    echo "  · 桌面: KDE Plasma（中文用户最友好的现代桌面）"
}

# ════════════════════════════════════════════════════════════
# 3. 引导式问答（小白只做选择题）
# ════════════════════════════════════════════════════════════
ask_questions() {
    echo
    say "几个问题，不用懂，照喜好选："
    echo
    PS3="  桌面环境？[1-4] "
    select DE_CHOICE in "KDE（推荐，中文用户友好）" "GNOME" "Hyprland（平铺窗口，进阶）" "无头服务器（最小化）"; do
        case "${DE_CHOICE}" in
            *KDE*) DESKTOP="kde"; break ;;
            *GNOME*) DESKTOP="gnome"; break ;;
            *Hyprland*) DESKTOP="hyprland"; break ;;
            *无头*) DESKTOP="headless"; break ;;
            *) echo "  选 1-4" ;;
        esac
    done
    read -rp "  保留 Windows 双系统？[y/N] " ans
    [[ "${ans,,}" == "y" ]] && KEEP_WINDOWS=1 || KEEP_WINDOWS=0
    read -rp "  自动测速选择国内最快镜像源？[Y/n] " ans
    [[ "${ans,,}" == "n" ]] && AUTO_MIRROR=0 || AUTO_MIRROR=1
    read -rp "  主机名？[默认 arch] " ans
    HOSTNAME="${ans:-arch}"
    read -rp "  用户名？[默认 seika] " ans
    USER_NAME="${ans:-seika}"
}

# ════════════════════════════════════════════════════════════
# 4. 分区选择（引导式：一键自动 / 手动逐个挂载点指定）
#    挂载点：EFI、/、/home、swap；每步先选硬盘，再选〔现有分区│空闲空间〕
#    空闲空间可指定容量(如 100G/512M)，留空=该盘全部剩余空间
# ════════════════════════════════════════════════════════════
PART_EFI_DEV= PART_EFI_TGT= PART_EFI_FMT=1
PART_ROOT_DEV= PART_ROOT_TGT=
PART_HOME_DEV= PART_HOME_TGT=
PART_SWAP_DEV= PART_SWAP_TGT=
HOME_IS_SUBVOL=0

pick_disk() {
    local disks=($(lsblk -d -rno NAME)); local i=1
    echo "  可用磁盘:"
    for d in "${disks[@]}"; do echo "    $i) /dev/$d"; i=$((i+1)); done
    while :; do
        read -rp "  选择磁盘编号: " n
        if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#disks[@]}" ]; then
            _DISK="/dev/${disks[$((n-1))]}"; return 0
        fi
        warn "无效编号"
    done
}

pick_target() {
    # $1=磁盘(dev)  $2=标签(如 EFI)
    local dev="$1" label="$2"
    echo "  [${label}] 在 ${dev} 上选择目标:"
    echo "    0) 空闲空间（脚本新建分区）"
    local plist=($(lsblk -rn -o NAME,PARTN "$dev" | awk '$2!="" {print $1}')); local i=1
    for p in "${plist[@]}"; do
        echo "    $i) /dev/$p  ($(lsblk -dn -o SIZE "/dev/$p"))"; i=$((i+1))
    done
    while :; do
        read -rp "  选编号(0=空闲空间): " n
        if [ "$n" = "0" ]; then
            local size
            read -rp "    空闲空间用量(如 100G / 512M，留空=全部剩余): " size
            if [ -n "$size" ]; then
                [[ "$size" =~ ^[0-9]+(M|G)$ ]] || { warn "容量格式应为 数字+G/M，如 100G"; continue; }
                size="+${size}"
            else
                size=0
            fi
            _TGT="free:${size}"; return 0
        elif [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#plist[@]}" ]; then
            _TGT="part:/dev/${plist[$((n-1))]}"; return 0
        fi
        warn "无效编号"
    done
}

manual_partition() {
    say "手动模式：逐个挂载点选择（先选硬盘，再选该盘上的分区或空闲空间）"
    say "步骤 1/4 —— EFI 分区"
    pick_disk; PART_EFI_DEV="$_DISK"; pick_target "$_DISK" EFI; PART_EFI_TGT="$_TGT"
    if [[ "$PART_EFI_TGT" == part:* ]]; then
        read -rp "  格式化该 EFI 分区? [y/N] " f
        [[ "${f,,}" == "y" ]] && PART_EFI_FMT=1 || PART_EFI_FMT=0
    fi
    say "步骤 2/4 —— 根 / 分区"
    pick_disk; PART_ROOT_DEV="$_DISK"; pick_target "$_DISK" ROOT; PART_ROOT_TGT="$_TGT"
    say "步骤 3/4 —— /home 分区"
    pick_disk; PART_HOME_DEV="$_DISK"; pick_target "$_DISK" HOME; PART_HOME_TGT="$_TGT"
    say "步骤 4/4 —— swap 分区"
    pick_disk; PART_SWAP_DEV="$_DISK"; pick_target "$_DISK" SWAP; PART_SWAP_TGT="$_TGT"
}

oneclick_partition() {
    local ram; ram=$(free -g 2>/dev/null | awk '/^Mem:/{print $2}'); [ -z "$ram" ] && ram=4; [ "$ram" -lt 2 ] && ram=2
    say "一键模式：选一块盘，自动从空闲空间划分 EFI(1G)+/(剩余)+/home(子卷)+swap(${ram}G)"
    pick_disk
    PART_EFI_DEV="$_DISK"; PART_EFI_TGT="free:+1G"; PART_EFI_FMT=1
    PART_ROOT_DEV="$_DISK"; PART_ROOT_TGT="free:0"
    PART_HOME_DEV="$_DISK"; PART_HOME_TGT="free:0"; HOME_IS_SUBVOL=1
    PART_SWAP_DEV="$_DISK"; PART_SWAP_TGT="free:+${ram}G"
}

choose_disk() {
    echo
    say "分区方案：1) 一键（选一块盘自动划分）   2) 手动（逐个挂载点指定，推荐）"
    read -rp "  选择 [1/2，默认 2]: " m
    [ "${m:-2}" = "1" ] && oneclick_partition || manual_partition
}

# ════════════════════════════════════════════════════════════
# 5. 分区 + 格式化 + BTRFS 子卷
# ════════════════════════════════════════════════════════════
setup_disk() {
    say "按选定结构分区与挂载（将写入磁盘）..."
    # $1=磁盘 $2=tgt(part:/dev/xxx | free:+SIZE | free:0) $3=typecode → 输出分区设备路径
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
    mkfs.btrfs -f "$ROOT_PART" >/dev/null && ok "根 $ROOT_PART (BTRFS)"
    mount "$ROOT_PART" /mnt
    btrfs subvolume create /mnt/@ >/dev/null
    btrfs subvolume create /mnt/@snapshots >/dev/null
    [ "$HOME_IS_SUBVOL" = "1" ] && btrfs subvolume create /mnt/@home >/dev/null
    umount /mnt

    MOUNT_OPTS="noatime,compress=zstd:1"
    mount -o "${MOUNT_OPTS},subvol=@" "$ROOT_PART" /mnt
    mkdir -p /mnt/{home,.snapshots,boot}
    mount -o "${MOUNT_OPTS},subvol=@snapshots" "$ROOT_PART" /mnt/.snapshots
    if [ "$HOME_IS_SUBVOL" = "1" ]; then
        mount -o "${MOUNT_OPTS},subvol=@home" "$ROOT_PART" /mnt/home
    else
        HOME_PART=$(make_part "$PART_HOME_DEV" "$PART_HOME_TGT" 8300)
        mkfs.btrfs -f "$HOME_PART" >/dev/null && ok "/home $HOME_PART (BTRFS)"
        mount -o "${MOUNT_OPTS}" "$HOME_PART" /mnt/home
    fi
    mount "$EFI_PART" /mnt/boot
    ok "挂载完成"
}

# ════════════════════════════════════════════════════════════
# 6. 镜像源测速（bench_mirror 已在上方 0.0 提前定义，供 preflight 与 main 复用）
# ════════════════════════════════════════════════════════════

# ════════════════════════════════════════════════════════════
# 7. pacstrap 基础系统 + 桌面
# ════════════════════════════════════════════════════════════
install_base() {
    # 注意: $( [ ... ] && echo ... || true ) 必须带 || true——
    # 否则条件为假时命令替换退出码=1, 赋值语句在 set -e 下直接退出(经典陷阱)
    PACKAGES="base base-devel linux linux-firmware linux-lts \
btrfs-progs grub efibootmgr os-prober ntfs-3g \
networkmanager sudo vim git \
$( [ "${DESKTOP}" = "kde" ] && echo "plasma-meta sddm konsole dolphin ark gwenview \
fcitx5-im fcitx5-chinese-addons fcitx5-configtool \
noto-fonts noto-fonts-cjk noto-fonts-emoji wqy-microhei" || true ) \
$( [ "${DESKTOP}" = "gnome" ] && echo "gnome gnome-extra gdm fcitx5-im fcitx5-chinese-addons \
noto-fonts noto-fonts-cjk" || true ) \
$( [ "${DESKTOP}" = "hyprland" ] && echo "hyprland waybar rofi-wayland kitty \
fcitx5-im fcitx5-chinese-addons noto-fonts noto-fonts-cjk" || true ) \
$( [ "${DESKTOP}" = "headless" ] && echo "openssh cronie" || true )"

    say "安装基础系统 + 桌面（约 10-15 分钟，取决于网速）..."
    pacstrap -K /mnt ${PACKAGES} 2>&1 | tail -3
    genfstab -U /mnt >> /mnt/etc/fstab
    ok "基础系统安装完成"
}

# ════════════════════════════════════════════════════════════
# 8. chroot 系统配置
# ════════════════════════════════════════════════════════════
configure_system() {
    say "配置系统（时区/语言/用户/引导/桌面服务）..."

    # 测速结果写入新系统（pacstrap 不自动带 host 的 mirrorlist）
    if [ "${AUTO_MIRROR}" = "1" ] && [ -n "${BEST:-}" ]; then
        echo "Server = ${BEST}/\$repo/os/\$arch" > /mnt/etc/pacman.d/mirrorlist
    fi

    arch-chroot /mnt bash -c "
set -e
# 时区
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
hwclock --systohc
# locale
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/^#zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
locale-gen >/dev/null 2>&1
echo 'LANG=zh_CN.UTF-8' > /etc/locale.conf
# 主机名
echo '${HOSTNAME}' > /etc/hostname
printf '127.0.0.1 localhost\n::1 localhost\n127.0.1.1 ${HOSTNAME}\n' > /etc/hosts
# 镜像源（chroot 内也用测速结果——由外部写入）
# 输入法环境变量
printf 'GTK_IM_MODULE=fcitx\nQT_IM_MODULE=fcitx\nXMODIFIERS=@im=fcitx\n' > /etc/environment
" 2>&1 | tail -2

    # root 密码
    echo
    while :; do
        read -rsp "  设置 root 密码: " PASS1; echo
        read -rsp "  再次输入: " PASS2; echo
        [ -n "${PASS1}" ] && [ "${PASS1}" = "${PASS2}" ] && break
        warn "两次输入不一致或为空，重来"
    done
    echo "root:${PASS1}" | arch-chroot /mnt chpasswd

    # 用户
    echo
    while :; do
        read -rsp "  设置用户 ${USER_NAME} 的密码: " PASS1; echo
        read -rsp "  再次输入: " PASS2; echo
        [ -n "${PASS1}" ] && [ "${PASS1}" = "${PASS2}" ] && break
        warn "两次输入不一致或为空，重来"
    done
    arch-chroot /mnt useradd -m -G wheel -s /bin/bash "${USER_NAME}"
    echo "${USER_NAME}:${PASS1}" | arch-chroot /mnt chpasswd
    echo "%wheel ALL=(ALL:ALL) ALL" > /mnt/etc/sudoers.d/10-wheel
    chmod 440 /mnt/etc/sudoers.d/10-wheel
    ok "用户 ${USER_NAME} 创建完成（已加入 sudo 组）"

    # 引导
    if [ "${BOOT_MODE}" = "UEFI" ]; then
        arch-chroot /mnt grub-install --target=x86_64-efi \
            --efi-directory=/boot --bootloader-id=GRUB >/dev/null 2>&1 \
            && ok "GRUB UEFI 安装完成" || die "GRUB UEFI 安装失败，系统将无法引导"
    else
        arch-chroot /mnt grub-install --target=i386-pc "${PART_ROOT_DEV}" >/dev/null 2>&1 \
            && ok "GRUB BIOS 安装完成" || die "GRUB BIOS 安装失败，系统将无法引导"
    fi
    # 双系统
    if [ "${KEEP_WINDOWS}" = "1" ]; then
        echo 'GRUB_DISABLE_OS_PROBER=false' >> /mnt/etc/default/grub
    fi
    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | tail -1

    # 服务
    arch-chroot /mnt systemctl enable NetworkManager >/dev/null 2>&1
    case "${DESKTOP}" in
        kde) arch-chroot /mnt systemctl enable sddm >/dev/null 2>&1 ;;
        gnome) arch-chroot /mnt systemctl enable gdm >/dev/null 2>&1 ;;
        hyprland) arch-chroot /mnt systemctl enable sddm >/dev/null 2>&1 ;;
        headless) arch-chroot /mnt systemctl enable sshd >/dev/null 2>&1 ;;
    esac
    ok "服务已启用"
}

# ════════════════════════════════════════════════════════════
# 9. 主流程
# ════════════════════════════════════════════════════════════
main() {
    detect_hardware
    suggest_plan
    ask_questions
    choose_disk
    echo
    say "────────── 分区结构确认 ──────────"
    fmt_t() {
        local d="$1" t="$2"
        if [[ "$t" == free:* ]]; then
            local s="${t#free:}"; [ "$s" = "0" ] && s="全部剩余"
            echo "$d 空闲空间(${s})"
        else
            echo "${t#part:}"
        fi
    }
    echo "  EFI  : $(fmt_t "$PART_EFI_DEV" "$PART_EFI_TGT")  $([ "$PART_EFI_FMT" = "1" ] && echo '[格式化]' || echo '[保留,仅挂载]')"
    echo "  /    : $(fmt_t "$PART_ROOT_DEV" "$PART_ROOT_TGT")"
    echo "  /home: $([ "$HOME_IS_SUBVOL" = "1" ] && echo '（/ 的 BTRFS 子卷 @home）' || echo "$(fmt_t "$PART_HOME_DEV" "$PART_HOME_TGT")")"
    echo "  swap : $(fmt_t "$PART_SWAP_DEV" "$PART_SWAP_TGT")"
    echo "  引导 : ${BOOT_MODE}   桌面: ${DESKTOP}   主机名: ${HOSTNAME}   用户: ${USER_NAME}"
    echo "  Windows: $([ "${KEEP_WINDOWS}" = "1" ] && echo 保留双系统 || echo 不保留)   镜像源: $([ "${AUTO_MIRROR}" = "1" ] && echo 自动测速 || echo 手动配置)"
    echo "─────────────────────────────────"
    echo "  ⚠️ 以上将【清空所选分区/磁盘上的数据】，且不可逆！"
    read -rp "  输入大写的 YES 确认按此结构分区并格式化: " ans
    [ "$ans" = "YES" ] || { say "已取消，未做任何更改"; exit 0; }

    [ "${AUTO_MIRROR}" = "1" ] && bench_mirror
    setup_disk
    install_base
    configure_system

    echo
    echo "══════════════════════════════════════════════"
    ok "安装完成！"
    echo "  1. 输入 exit / reboot 重启（记得拔掉安装盘）"
    echo "  2. 进 GRUB 后：默认 linux 内核，回退用 Advanced options 选 linux-lts"
    echo "  3. 登录后第一件事：sudo pacman -Syu 更新"
    echo "  4. 想提升桌面响应？sudo bash -c \"\$(curl -sSL https://gitee.com/seikabook/seikabook-os-install/raw/master/seika-kernel.sh)\""
    echo "══════════════════════════════════════════════"
}

main "$@"

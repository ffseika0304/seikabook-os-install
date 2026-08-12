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
# 4. 选择目标磁盘（重点防呆：误清盘是唯一不可逆的事故）
# ════════════════════════════════════════════════════════════
choose_disk() {
    echo
    say "当前磁盘列表（⚠️ 选中后将完全清空该盘）："
    lsblk -d -o NAME,SIZE,MODEL,TRAN | grep -E 'disk' || true
    echo
    read -rp "  输入要安装的磁盘设备名（如 sda，不含 /dev/）: " DISK
    DEV="/dev/${DISK}"
    [ -b "${DEV}" ] || die "设备 ${DEV} 不存在"
    # 已有分区强确认
    if lsblk "${DEV}" -o NAME 2>/dev/null | grep -q "${DISK}[0-9p]"; then
        warn "⚠️ 该磁盘已有分区！安装将【清除所有数据】！"
        warn "数据无价，确认前请三思。"
        read -rp "  输入大写的 YES 确认清空 ${DEV} 并安装: " confirm
        [ "${confirm}" = "YES" ] || die "已取消，未做任何更改"
    fi
    ok "目标磁盘: ${DEV}"
}

# ════════════════════════════════════════════════════════════
# 5. 分区 + 格式化 + BTRFS 子卷
# ════════════════════════════════════════════════════════════
setup_disk() {
    say "分区 ${DEV} ..."
    sgdisk --zap-all "${DEV}" >/dev/null 2>&1 || true
    if [ "${BOOT_MODE}" = "UEFI" ]; then
        sgdisk -n1:0:+1G -t1:ef00 "${DEV}" >/dev/null
        sgdisk -n2:0:0 -t2:8300 "${DEV}" >/dev/null
        EFI_PART="${DEV}1"; ROOT_PART="${DEV}2"
        mkfs.fat -F32 "${EFI_PART}" >/dev/null && ok "EFI 分区 ${EFI_PART} (FAT32)"
    else
        sgdisk -n1:0:+1M -t1:ef02 "${DEV}" >/dev/null
        sgdisk -n2:0:0 -t2:8300 "${DEV}" >/dev/null
        EFI_PART=""; ROOT_PART="${DEV}2"
    fi
    mkfs.btrfs -f "${ROOT_PART}" >/dev/null && ok "根分区 ${ROOT_PART} (BTRFS)"

    say "创建 BTRFS 子卷 @ / @home / @snapshots ..."
    mount "${ROOT_PART}" /mnt
    btrfs subvolume create /mnt/@ >/dev/null
    btrfs subvolume create /mnt/@home >/dev/null
    btrfs subvolume create /mnt/@snapshots >/dev/null
    umount /mnt

    say "挂载子卷..."
    MOUNT_OPTS="noatime,compress=zstd:1"
    mount -o "${MOUNT_OPTS},subvol=@" "${ROOT_PART}" /mnt
    mkdir -p /mnt/{home,.snapshots,boot}
    mount -o "${MOUNT_OPTS},subvol=@home" "${ROOT_PART}" /mnt/home
    mount -o "${MOUNT_OPTS},subvol=@snapshots" "${ROOT_PART}" /mnt/.snapshots
    if [ -n "${EFI_PART}" ]; then
        mount "${EFI_PART}" /mnt/boot
    fi
    ok "子卷挂载完成"
}

# ════════════════════════════════════════════════════════════
# 6. 镜像源测速（清华/阿里/中科大）
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
        arch-chroot /mnt grub-install --target=i386-pc "${DEV}" >/dev/null 2>&1 \
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
    say "────────── 安装计划 ──────────"
    echo "  磁盘     : ${DEV}（将被清空）"
    echo "  引导     : ${BOOT_MODE}"
    echo "  桌面     : ${DESKTOP}"
    echo "  主机名   : ${HOSTNAME}"
    echo "  用户     : ${USER_NAME}"
    echo "  Windows  : $([ "${KEEP_WINDOWS}" = "1" ] && echo 保留双系统 || echo 不保留)"
    echo "  镜像源   : $([ "${AUTO_MIRROR}" = "1" ] && echo 自动测速 || echo 手动配置)"
    echo "─────────────────────────"
    read -rp "  确认无误开始安装？[y/N] " ans
    [[ "${ans,,}" == "y" ]] || { say "已取消"; exit 0; }

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

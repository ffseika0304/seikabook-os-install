#!/usr/bin/env bash
# ============================================================
#  Seikabook OS Install — 你的硬件，它的灵魂。
#  理念：让中文母语的小白先进入 KDE 桌面，再开始学习，
#        而不是卡在 archiso 的黑屏命令行里。
#
#  状态：开发中（骨架版）——硬件检测/引导问答可运行，
#        安装步骤逐步完善中。欢迎提 issue。
# ============================================================
set -euo pipefail

# ── 颜色（小彩色，不用花哨） ──────────────────────────────
C_RESET="\e[0m"; C_BLUE="\e[1;34m"; C_GREEN="\e[1;32m"; C_YEL="\e[1;33m"; C_RED="\e[1;31m"
say()  { echo -e "${C_BLUE}[Seikabook]${C_RESET} $*"; }
ok()   { echo -e "${C_GREEN}[ OK ]${C_RESET} $*"; }
warn() { echo -e "${C_YEL}[注意]${C_RESET} $*"; }
die()  { echo -e "${C_RED}[错误]${C_RESET} $*" >&2; exit 1; }

# ════════════════════════════════════════════════════════════
# 0. 基础检查：必须 root、必须是 Arch 环境
# ════════════════════════════════════════════════════════════
[ "$(id -u)" -eq 0 ] || die "请以 root 身份运行（从 Arch ISO 启动后执行）"

if [ -r /etc/os-release ]; then
    . /etc/os-release
fi
if [ "${ID:-}" != "arch" ] && [ "${ID:-}" != "archlinux" ]; then
    warn "当前环境 ID=${ID:-未知}，本脚本为 Arch Linux 设计。"
    warn "建议：用官方 archiso 启动盘引导后运行（https://archlinux.org/download/）。"
    read -rp "仍要继续吗？[y/N] " ans
    [[ "${ans,,}" == "y" ]] || exit 1
fi

say "Seikabook OS Install 启动 —— 先看看你的机器，再决定怎么装。"

# ════════════════════════════════════════════════════════════
# 1. 硬件检测
# ════════════════════════════════════════════════════════════
detect_hardware() {
    echo
    say "────────── 硬件检测 ──────────"

    # CPU
    CPU_VENDOR="$(lscpu 2>/dev/null | awk -F': *' '/^Vendor ID/{print $2; exit}')"
    CPU_MODEL="$(lscpu 2>/dev/null | awk -F': *' '/^Model name/{print $2; exit}')"
    CPU_SOCKETS="$(lscpu 2>/dev/null | awk -F': *' '/^Socket\(s\)/{print $2}')"
    CPU_CORES="$(nproc)"
    echo "CPU    : ${CPU_MODEL:-未知}"
    echo "         vendor=${CPU_VENDOR:-未知} / 核心数=${CPU_CORES}"
    case "${CPU_VENDOR,,}" in
        *amd*) CPU_FAMILY="amd" ;;
        *intel*) CPU_FAMILY="intel" ;;
        *) CPU_FAMILY="unknown" ;;
    esac

    # GPU（取第一个显卡）
    GPU_LINE="$(lspci 2>/dev/null | grep -iE 'VGA|3D controller|Display controller' | head -1 || true)"
    echo "GPU    : ${GPU_LINE:-未知}"
    case "${GPU_LINE,,}" in
        *nvidia*) GPU_FAMILY="nvidia" ;;
        *advanced\ micro\ devices*) GPU_FAMILY="amd" ;;
        *intel*) GPU_FAMILY="intel" ;;
        *) GPU_FAMILY="unknown" ;;
    esac

    # 内存 / 磁盘
    MEM_TOTAL="$(free -h | awk '/^Mem:/{print $2}')"
    echo "内存   : ${MEM_TOTAL}"
    echo "磁盘   :"
    lsblk -d -o NAME,SIZE,MODEL 2>/dev/null | grep -vE 'NAME|loop' | head -6 || true

    # 引导方式
    if [ -d /sys/firmware/efi ]; then
        BOOT_MODE="UEFI"
        [ -d /sys/firmware/efi/efivars ] || BOOT_MODE="UEFI(efivars 不可读)"
    else
        BOOT_MODE="BIOS/Legacy"
    fi
    echo "引导   : ${BOOT_MODE}"

    # Windows 双系统探测
    if lsblk -o LABEL 2>/dev/null | grep -qiE 'windows|winre|recovery'; then
        HAS_WINDOWS=1
        echo "系统   : 检测到 Windows 分区（将配置双系统 GRUB）"
    else
        HAS_WINDOWS=0
    fi
    echo "────────── 检测完毕 ──────────"
}

# ════════════════════════════════════════════════════════════
# 2. 按硬件给内核/驱动方案（这就是"方法论"的核心）
# ════════════════════════════════════════════════════════════
suggest_plan() {
    echo
    say "根据你的硬件，Seikabook OS 建议如下："
    case "${CPU_FAMILY}" in
        amd)
            echo "  · CPU: AMD → 建议自编译 zen 内核（zen4 微架构 + BORE 调度器）"
            echo "        微架构按代数自动选：Zen4 及以上用 zen4，Zen2/3 用 zen2/zen3"
            echo "        理由：AMD 无大小核，调度最简单，zen+BORE 桌面响应收益最直接"
            ;;
        intel)
            echo "  · CPU: Intel → 建议官方 zen + lts 双内核"
            echo "        12 代+ 大小核优先保证前台任务上 P 核（异构调度策略）"
            ;;
        *) echo "  · CPU: 未知厂商，使用官方默认内核（linux）" ;;
    esac
    case "${GPU_FAMILY}" in
        amd)    echo "  · GPU: AMD → amdgpu + Mesa 全开源，零配置（不折腾就是最优）" ;;
        nvidia) echo "  · GPU: NVIDIA → nvidia-dkms + 对应内核 headers 自动匹配"
                echo "        提示：更新内核后先等 dkms 编译完成再重启（否则可能黑屏）" ;;
        intel)  echo "  · GPU: Intel → i915/xe 开源驱动，零配置" ;;
        *)      echo "  · GPU: 未知 → 装好后用 lspci 再确认" ;;
    esac
    if [ "${BOOT_MODE}" = "UEFI" ]; then
        echo "  · 引导: UEFI → systemd-boot 或 GRUB 均可（推荐 GRUB，双系统兼容好）"
    else
        echo "  · 引导: BIOS → 必须用 GRUB"
    fi
}

# ════════════════════════════════════════════════════════════
# 3. 引导式问答（小白只回答选择题）
# ════════════════════════════════════════════════════════════
ask_questions() {
    echo
    say "接下来几个问题，不用懂，照喜好选："
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
    read -rp "  是否保留 Windows 双系统？[y/N] " ans
    [[ "${ans,,}" == "y" ]] && KEEP_WINDOWS=1 || KEEP_WINDOWS=0
    read -rp "  自动测速选择国内最快镜像源？[Y/n] " ans
    [[ "${ans,,}" == "n" ]] && AUTO_MIRROR=0 || AUTO_MIRROR=1
}

# ════════════════════════════════════════════════════════════
# 4. 汇总与执行
# ════════════════════════════════════════════════════════════
main() {
    detect_hardware
    suggest_plan
    ask_questions

    echo
    say "────────── 你的安装计划 ──────────"
    echo "  桌面     : ${DESKTOP}"
    echo "  Windows  : $([ "${KEEP_WINDOWS}" = "1" ] && echo 保留 || echo 不保留)"
    echo "  镜像源   : $([ "${AUTO_MIRROR}" = "1" ] && echo 自动测速 || echo 手动配置)"
    echo "─────────────────────────────"
    echo
    warn "安装步骤正在开发中（分区 / 基础系统 / 内核 / 桌面 / 中文环境）。"
    warn "当前骨架版仅完成硬件检测与方案建议，不会修改你的磁盘。"
    echo
    say "后续版本将在这里依次执行："
    echo "  1) 磁盘分区（BTRFS：@ / @home / @snapshots）"
    echo "  2) 基础系统（base + 内核 + 固件 + GRUB）"
    echo "  3) 内核方案（${CPU_FAMILY} → 上文建议）"
    echo "  4) 桌面环境（${DESKTOP}）+ 中文环境（fcitx5 / 中文字体）"
    echo "  5) 镜像源 + 快照 + 双系统 GRUB 收尾"
    echo
    ok "检测完成。你的机器信息已展示，方案已给出——"
    ok "安装逻辑写完前，先用这份报告确认硬件没问题。"
}

main "$@"

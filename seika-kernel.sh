#!/usr/bin/env bash
# ============================================================
#  Seikabook OS Kernel — 通用增强内核
#  基于官方 linux-zen 底包 + BORE 调度器（AMD / Intel x86_64 通用）
#
#  理念：内核编译是"学习"的一部分，但脚本替你处理所有坑。
#  用法：sudo bash seika-kernel.sh          （交互确认）
#        sudo bash seika-kernel.sh -y       （跳过确认）
#  产物：linux-zen-seika 独立包，与官方内核共存，GRUB 可自由切换
# ============================================================
set -euo pipefail

C_RESET="\e[0m"; C_BLUE="\e[1;34m"; C_GREEN="\e[1;32m"; C_YEL="\e[1;33m"; C_RED="\e[1;31m"
say()  { echo -e "${C_BLUE}[Seikabook]${C_RESET} $*"; }
ok()   { echo -e "${C_GREEN}[ OK ]${C_RESET} $*"; }
warn() { echo -e "${C_YEL}[注意]${C_RESET} $*"; }
die()  { echo -e "${C_RED}[错误]${C_RESET} $*" >&2; exit 1; }

# 常量
REPO="https://gitee.com/seikabook/seikabook-os-install/raw/master"
MIRROR_KERNEL="https://mirrors.tuna.tsinghua.edu.cn/kernel"
WORK="/tmp/seika-kernel-build"

# ── 0. 参数（防呆：不接收复杂参数） ──────────────────────
ASSUME_YES=0
for a in "$@"; do
    case "$a" in
        -y|--yes) ASSUME_YES=1 ;;
        -h|--help) echo "用法: sudo bash seika-kernel.sh [-y]"; exit 0 ;;
        *) die "未知参数: $a（本脚本不接收复杂参数，防止误操作）" ;;
    esac
done

# ── 1. 基础检查 ──────────────────────────────────────────
[ "$(id -u)" -eq 0 ] || die "请用 root 运行：sudo bash seika-kernel.sh"
command -v pacman >/dev/null || die "未检测到 pacman，请确认在 Arch Linux 上运行"
command -v makepkg >/dev/null || die "缺少 makepkg，请先安装 base-devel：pacman -S base-devel"

# CPU 提示（不限制，只是让用户知道这内核适不适合自己）
# 优先读 /proc/cpuinfo 的 vendor_id：该字段名不受系统 locale 影响。
# （中文环境下 lscpu 输出的是"厂商 ID："而非"Vendor ID:"，且用全角冒号，
#   旧写法 /Vendor ID/ + ASCII 冒号 分隔符会整体匹配不到 → 误判"未知 CPU"）
CPU_VENDOR="$(awk -F': *' '/^vendor_id/{print $2; exit}' /proc/cpuinfo 2>/dev/null)"
# 兜底：个别环境没有 /proc/cpuinfo 时再试 lscpu（兼容中/英厂商标签与全角冒号）
if [ -z "${CPU_VENDOR}" ]; then
    CPU_VENDOR="$(lscpu 2>/dev/null | awk -F'[:：][[:space:]]*' '/Vendor ID|厂商 ID/{print $2; exit}')"
fi
case "${CPU_VENDOR,,}" in
    *amd*|*hygon*) CPU_NOTE="AMD 处理器（${CPU_VENDOR}）→ zen 底包 + BORE 直接受益（桌面响应）" ;;
    *intel*)       CPU_NOTE="Intel 处理器（${CPU_VENDOR}）→ zen 底包 + BORE 同样有效（与架构无关）" ;;
    *) CPU_NOTE="未知 CPU（${CPU_VENDOR:-读不到 vendor_id}）→ BORE 调度器对 AMD/Intel 均有效" ;;
esac

say "Seikabook OS Kernel —— 通用增强内核（linux-zen + BORE）"
echo "  ${CPU_NOTE}"
echo
warn "将在本机现场编译内核（预计 25-40 分钟，期间请保持电源连接）"
warn "产物为独立包 linux-zen-seika，不覆盖现有内核，GRUB 可回退"
[ "${ASSUME_YES}" = "1" ] || { read -rp "继续吗？[y/N] " ans; [[ "${ans,,}" == "y" ]] || exit 0; }

# ── 2. 安装编译依赖 ──────────────────────────────────────
say "安装编译依赖..."
pacman -S --needed --noconfirm base-devel git bc pahole python xxhash \
    libelf openssl cpio zstd xz 2>&1 | tail -2

# ── 3. 获取官方 linux-zen PKGBUILD ───────────────────────
mkdir -p "${WORK}" && cd "${WORK}"
say "获取官方 linux-zen PKGBUILD..."
rm -rf linux-zen
if ! git clone --depth 1 -q \
    https://gitlab.archlinux.org/archlinux/packaging/packages/linux-zen.git; then
    say "gitlab 直连失败，改用 tarball..."
    curl -fsSL --connect-timeout 15 -o lz.tar.gz \
        "https://gitlab.archlinux.org/archlinux/packaging/packages/linux-zen/-/archive/main/linux-zen-main.tar.gz" \
        || die "获取 PKGBUILD 失败（网络问题），可稍后重试"
    tar xzf lz.tar.gz && mv linux-zen-main linux-zen
fi
cd linux-zen

# ── 4. 读版本号，匹配 BORE 补丁 ──────────────────────────
PKGVER="$(. PKGBUILD && echo "${pkgver}")"
# linux-zen 的 pkgver 形如 7.1.8.zen1，末尾 .zenN 只是打包修订号；
# 仓库内置的 BORE 补丁按"内核基础版本"命名（bore-zen-7.1.8.patch），需去掉 .zenN
PKGBASE="${PKGVER%.zen*}"
PATCH_NAME="bore-zen-${PKGBASE}.patch"
say "官方 linux-zen 版本: ${PKGVER}（BORE 补丁基础版本 ${PKGBASE}）"
say "下载 BORE 合并补丁 ${PATCH_NAME}（仓库内置，国内直连）..."
if ! curl -fsSL --connect-timeout 15 -o "${PATCH_NAME}" \
    "${REPO}/files/${PATCH_NAME}"; then
    die "未找到 ${PATCH_NAME}——内核版本 ${PKGVER} 的补丁还没适配。去 https://gitee.com/seikabook/seikabook-os-install/issues 反馈，作者会跟进。"
fi
ok "BORE 补丁就绪（$(wc -c < "${PATCH_NAME}") bytes）"

# ── 5. 定制 PKGBUILD（独立包名 + 省掉文档构建巨包） ───────
say "定制 PKGBUILD：独立包名 linux-zen-seika..."
sed -i 's/^pkgbase=linux-zen$/pkgbase=linux-zen-seika/' PKGBUILD
grep '^pkgbase' PKGBUILD

say "注释 htmldocs 构建（省掉 texlive 巨包）..."
sed -i 's|^  make htmldocs SPHINXOPTS=-QT &|#  make htmldocs SPHINXOPTS=-QT \&|; s|^  wait \$pid_docs$|#  wait \$pid_docs|' PKGBUILD

# ── 6. 手动准备源码（清华镜像加速） + 打 BORE 补丁 ──────
# 内核源码 tarball 按"基础版本"命名（linux-7.1.8.tar.xz），kernel.org 目录是 v7.x（仅主版本号）；
# 旧写法用完整 pkgver(7.1.8.zen1) 拼出 linux-7.1.8.zen1.tar.xz / v7.1.x → 404
KVER_MAJOR="$(echo "${PKGBASE}" | cut -d. -f1)"
SRC_TARBALL="linux-${PKGBASE}.tar.xz"
SRC_URL="${MIRROR_KERNEL}/v${KVER_MAJOR}.x/${SRC_TARBALL}"
say "从清华镜像下载内核源码（${SRC_TARBALL}）..."
if [ ! -f "${SRC_TARBALL}" ]; then
    if curl -fL --connect-timeout 20 --retry 2 -o "${SRC_TARBALL}" "${SRC_URL}"; then
        ok "源码就绪（清华镜像）"
    else
        # 镜像挂了别硬死，makepkg --nobuild 会按 PKGBUILD 自带源再试一次
        warn "清华镜像下载失败，交给 makepkg 自行获取源码（PKGBUILD 自带源）"
    fi
else
    ok "源码已存在，跳过下载"
fi

say "下载 zen 补丁集（GitHub，小文件可等待）..."
if [ ! -f "linux-v${PKGVER}-zen1.patch.zst" ]; then
    curl -fL --connect-timeout 15 --retry 3 -o "linux-v${PKGVER}-zen1.patch.zst" \
        "https://github.com/zen-kernel/zen-kernel/releases/download/v${PKGVER}-zen1/linux-v${PKGVER}-zen1.patch.zst" \
        || warn "zen 补丁下载失败——稍后 makepkg 会自行尝试"
fi

# 解压 + 打 BORE（makepkg --nobuild 只做 prepare，然后手动 patch，再 -e 编译）
# makepkg 禁止 root 运行 → 用 sudo 调用者(SUDO_USER)或 nobody 降权
BUILD_USER="${SUDO_USER:-}"
[ -n "${BUILD_USER}" ] || BUILD_USER="nobody"
BUILD_HOME="${WORK}/home-${BUILD_USER}"
mkdir -p "${BUILD_HOME}"
chown -R "${BUILD_USER}:${BUILD_USER}" "${WORK}" 2>/dev/null || true
chmod 755 "${WORK}" "${WORK}/linux-zen" 2>/dev/null || true

say "解压源码并应用补丁（此步校验哈希，需与官方一致）..."
if ! su "${BUILD_USER}" -s /bin/bash -c \
    "export HOME=${BUILD_HOME}; cd ${WORK}/linux-zen && makepkg --nobuild --skippgpcheck" 2>&1 | tail -3; then
    die "prepare 阶段失败（源码下载或哈希校验问题），请查看上方输出"
fi
ls -d src/linux-* >/dev/null 2>&1 || die "源码未解压成功"

SRC_DIR="$(ls -d src/linux-* | head -1)"
say "打 BORE 补丁到源码树 ${SRC_DIR}..."
cp "${PATCH_NAME}" "${SRC_DIR}/"
if su "${BUILD_USER}" -s /bin/bash -c \
    "export HOME=${BUILD_HOME}; cd ${WORK}/linux-zen/${SRC_DIR} && patch -Np1 --dry-run < ${PATCH_NAME}" >/dev/null 2>&1; then
    su "${BUILD_USER}" -s /bin/bash -c \
        "export HOME=${BUILD_HOME}; cd ${WORK}/linux-zen/${SRC_DIR} && patch -Np1 < ${PATCH_NAME} >/dev/null" \
        && ok "BORE 补丁干净应用"
else
    die "BORE 补丁应用失败（内核版本与补丁不匹配？），请反馈给作者"
fi
su "${BUILD_USER}" -s /bin/bash -c \
    "export HOME=${BUILD_HOME}; cd ${WORK}/linux-zen/${SRC_DIR} && find . -name '*.rej' -delete"
cd "${WORK}/linux-zen"

# ── 7. 编译 ──────────────────────────────────────────────
say "开始编译（-j$(nproc)，预计 25-40 分钟），日志: ${WORK}/build.log"
sleep 2
su "${BUILD_USER}" -s /bin/bash -c \
    "export HOME=${BUILD_HOME}; cd ${WORK}/linux-zen && MAKEFLAGS='-j$(nproc)' makepkg --skippgpcheck --nodeps -e" \
    2>&1 | tee "${WORK}/build.log" | tail -5
[ -n "$(ls linux-zen-seika-*-x86_64.pkg.tar.zst 2>/dev/null)" ] || die "编译失败，请查看 ${WORK}/build.log"

# ── 8. 安装 ──────────────────────────────────────────────
PKG_MAIN="$(ls linux-zen-seika-*-x86_64.pkg.tar.zst 2>/dev/null | grep -v headers | grep -v docs | head -1)"
PKG_HEAD="$(ls linux-zen-seika-headers-*-x86_64.pkg.tar.zst 2>/dev/null | head -1)"
[ -n "${PKG_MAIN}" ] || die "未找到编译产物，请查看 ${WORK}/build.log"
say "安装 ${PKG_MAIN} ..."
pacman -U --noconfirm ${PKG_MAIN} ${PKG_HEAD} 2>&1 | grep -E "Installing|mkinitcpio|error" | head -5

# ── 9. 引导菜单 ──────────────────────────────────────────
if command -v grub-mkconfig >/dev/null && [ -f /boot/grub/grub.cfg ]; then
    grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | tail -2
elif command -v bootctl >/dev/null; then
    bootctl update 2>&1 | tail -2 || true
fi

# ── 10. 完成 ─────────────────────────────────────────────
echo
ok "seikabook 内核安装完成！重启后生效："
echo "  · GRUB 菜单选 'Seikabook OS ... linux-zen-seika' 进入新内核"
echo "  · 验证: uname -r        → 应含 zen-seika"
echo "  · 验证: sysctl kernel.sched_bore → 应为 1（BORE 开启）"
echo "  · 回退: GRUB 选官方 linux-zen / linux 即可（双内核共存）"
echo
say "想调 BORE 参数：sysctl kernel.sched_bore=1（默认开）"
say "内核源码与构建环境保留在 ${WORK}/linux-zen，可二次定制"

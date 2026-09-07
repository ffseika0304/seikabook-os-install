<h1 align="center">Seikabook OS</h1>

<p align="center"><b>你的硬件，它的灵魂</b> —— 帮小白速通 archiso、推开 KDE 大门；让老手快速编译自己的内核，魔改出属于自己的发行版。</p>

<p align="center">🥇 <b>不是发行版，是作者自己用着顺手、分享给同好的社群作品</b> 🥇</p>

<p align="center">
  <a href="#快速开始">安装</a> ·
  <a href="#两段式">使用方式</a> ·
  <a href="#它有什么">特性</a> ·
  <a href="#国内加速">国内加速</a> ·
  <a href="https://github.com/ffseika0304/seikabook-os-install/issues">反馈问题</a>
</p>

<p align="center">
  <a href="https://github.com/ffseika0304/seikabook-os-install"><img src="https://img.shields.io/github/stars/ffseika0304/seikabook-os-install?style=flat-square&logo=github" alt="Stars"></a>
  <a href="https://github.com/ffseika0304/seikabook-os-install/fork"><img src="https://img.shields.io/github/forks/ffseika0304/seikabook-os-install?style=flat-square&logo=github" alt="Forks"></a>
  <a href="https://github.com/ffseika0304/seikabook-os-install/blob/master/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="License"></a>
  <a href="https://img.shields.io/badge/arch-x86__64-blue?style=flat-square&logo=archlinux"><img src="https://img.shields.io/badge/arch-x86__64-blue?style=flat-square&logo=archlinux" alt="Arch x86_64"></a>
  <a href="https://gitee.com/seikabook/seikabook-os-install"><img src="https://img.shields.io/badge/Gitee-%E5%9B%BD%E5%86%85%E5%8A%A0%E9%80%9F-C71D23?style=flat-square&logo=gitee" alt="Gitee 国内加速"></a>
</p>

Seikabook OS 是一个为**个人数字主权**而生的 Arch Linux 增强方案。它的理念只有一句话，但同一套工具同时服务两类人：

> **小白**：先进入 KDE 桌面，再开始折腾 Arch 系统。
> **老手**：在 archiso 的黑屏命令行里，也能快速恢复环境、拿到构建内核的思路。

---

## 它解决什么问题

- 新机器到手，装系统 + 配环境 = 半天起步
- 换台电脑，所有配置要重来一遍
- 不同硬件（AMD / NVIDIA / Intel）需要不同的内核、驱动、调度策略
- 想用 BTRFS 快照、双内核防滚挂，但手动配置太繁琐
- 国内网络环境下，装个软件、拉个镜像都费劲
- 小白被 archiso 黑屏劝退，老手却又每次重配一遍环境

## Highlights

**🥇 硬件感知，自动适配。** 自动识别 CPU / GPU，选型对应内核策略与驱动。NVIDIA 四代分级（Maxwell+ / Kepler / Fermi / Tesla）自动匹配驱动。

**🥇 双内核并行（linux + linux-lts）。** 一个跑性能，一个跑稳定，GRUB 菜单自由切换。可选 `seika-kernel.sh` 现场编译 linux-zen + BORE 增强内核。

**🥇 国内镜像源自动测速。** 清华 / 阿里 / 中科大，取最快。

**🥇 BTRFS + Timeshift 快照。** `@` 根子卷 + `@home` 用户子卷（用户数据默认不进快照，只保系统），滚挂了秒回退。

**🥇 四种桌面选项。** KDE（默认，最友好）/ GNOME / Hyprland / 无头服务器模式。

**🥇 双系统 GRUB 兼容。** 自动识别 Windows（os-prober），保留双启。

**🥇 中文环境开箱即用。** locale / fcitx5 / 中文字体 一键配好，NVIDIA 闭源驱动（nvidia-dkms + 对应内核 headers）自动匹配。

---

## 国内加速

本仓库主源在 GitHub，国内用户走 Gitee 镜像加速：

| 用途 | 链接 |
|---|---|
| 仓库镜像 | `https://gitee.com/seikabook/seikabook-os-install` |
| raw 直链 | `https://gitee.com/seikabook/seikabook-os-install/raw/master/` |
| 一键安装 | `curl -sSL https://gitee.com/seikabook/seikabook-os-install/raw/master/install.sh \| bash` |

---

## 两段式：先能用，再优化

Seikabook OS 把"装机"拆成两步，第一步让你快速见到桌面，第二步才是锦上添花：

**第一段：装系统（install.sh）** —— 从 Arch ISO 启动，引导式分区 + 安装，约 30 分钟到 KDE 桌面。小白到这里就能正常使用了。

**第二段：增强内核（seika-kernel.sh）** —— 进系统后想优化时再跑。
现场编译 `linux-zen + BORE` 调度器（桌面响应性提升，AMD / Intel 通用），带完整日志，产物是独立包，与官方内核共存、GRUB 随时回退。
对老手，这是构建自己内核的脚手架与思路起点；对小白，这是"系统已经能跑之后，再进阶折腾"的入口。

---

## 快速开始

在目标机器上（从 Arch ISO 启动后）：

```bash
curl -sSL https://gitee.com/seikabook/seikabook-os-install/raw/master/install.sh | bash
```

脚本一步步引导你：选桌面 → 选是否保留 Windows 双启 → 引导式分区（EFI / / /home 可选 / swap，空闲空间可自动建分区）→ 设用户。
不需要先查 CPU 型号，不需要手配网络，硬件与镜像源会自动处理。

> **当前状态**：`install.sh` 已在**真实硬件（双盘 / 双启 / 单 EFI）全流程实测通过** ——
> 从 archiso 引导到装出可独立启动的 KDE 系统，含双内核 / fcitx5 / GRUB 引导（含跨盘 EFI）/ Windows 双启项 / Timeshift BTRFS 模式，全程验证 OK。
> 自动分区模式已移除（未实测），手动分区为当前唯一入口。
> `seika-kernel.sh` 增强内核脚本可用。
> 欢迎提 issue 反馈你遇到的硬件和问题 —— 你踩过的坑会沉淀进下一版。

进系统后在 KDE 终端里运行增强内核编译：

```bash
sudo bash -c "$(curl -sSL https://gitee.com/seikabook/seikabook-os-install/raw/master/seika-kernel.sh)"
```

脚本会自动检测当前内核、编译 `linux-zen + BORE`、安装并写入 GRUB；重启后在 GRUB 的 **Advanced options** 里选 zen 内核即可。
任何时候都能回退到官方 `linux` / `linux-lts` —— 增强内核只是多一个选项，不替你换掉默认。

---

## 它有什么

### 硬件支持

| 特性 | 说明 |
|---|---|
| **架构** | **x86_64** |
| **CPU 检测** | 自动识别 AMD / Intel，选型对应 microcode 与内核策略 |
| **NVIDIA 驱动** | 四代分级：Maxwell+ 自动 nvidia-dkms、Kepler 退 nvidia-470xx-dkms、Fermi 退 nvidia-390xx-dkms、Tesla 退 nouveau |
| **AMD / Intel 核显** | 默认集成内核驱动，无需额外操作 |

### 系统特性

| 特性 | 说明 |
|---|---|
| **双内核** | 官方 linux + linux-lts 并行，GRUB 菜单自由切换；可选 zen+BORE 增强内核 |
| **文件系统** | BTRFS（`@` + `@home` 子卷），支持 Timeshift 快照 |
| **分区** | 引导式手动分区（EFI / / /home / swap），空闲空间自动建分区 |
| **镜像源** | 清华 / 阿里 / 中科大 自动测速取最快 |
| **双系统** | 自动识别 Windows（os-prober），保留双启 |
| **桌面** | KDE（默认）/ GNOME / Hyprland / 无头服务器模式 |
| **中文环境** | locale / fcitx5 / 中文字体 一键配好 |

### 仓库结构

```
seikabook-os-install/
├── install.sh               # 安装脚本（975 行）
├── seika-kernel.sh          # 增强内核编译脚本（293 行）
├── files/
│   └── bore-zen-7.1.8.patch # BORE 调度器补丁
├── LICENSE                  # MIT
└── README.md
```

---

## 这不是一个"安装器"

它是一个把"装机经验"固化成可执行脚本的作品。
每次遇到一个新硬件，跑一次脚本，就会得到一个针对它的专属环境。

它可以用于：

- 一台 AMD 工作站
- 一台 Intel + NVIDIA 双显卡笔记本
- 一台无头服务器（LTS 内核 + 最小化服务）
- 一台家里常开的低功耗设备

小白用它快速落地一个能用的桌面；老手用它把环境一键恢复、把内核构建思路跑通。

---

## Star History

<a href="https://www.star-history.com/#ffseika0304/seikabook-os-install&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=ffseika0304/seikabook-os-install&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=ffseika0304/seikabook-os-install&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=ffseika0304/seikabook-os-install&type=Date" />
 </picture>
</a>

---

## License

[MIT](LICENSE)，随便改，随便用。
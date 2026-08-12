# Seikabook OS — 你的硬件，它的灵魂。

一个为**个人数字主权**而生的 Arch Linux 增强方案。

不是发行版，不是开源的通用框架——是作者自己用着顺手、分享给同好的**社群作品**。
它的理念只有一句话：

> **让中文母语的小白先进入 KDE 桌面，再开始学习。
> 而不是卡在 archiso 的黑屏命令行里。**

---

## 它解决什么问题

- 新机器到手，装系统 + 配环境 = 半天起步
- 换台电脑，所有配置要重来一遍
- 不同硬件（AMD / NVIDIA / Intel）需要不同的内核、驱动、调度策略
- 想用 BTRFS 快照、双内核防滚挂，但手动配置太繁琐
- 国内网络环境下，装个软件、拉个镜像都费劲
- 明明是 Arch，却要先背一串 archiso 命令才能见到桌面

Seikabook OS 把这些经验打包进一个脚本，只留一个入口：

```bash
curl -sSL https://gitee.com/seikabook/seikabook-os-install/raw/master/install.sh | bash
```

---

## 它有什么

- **硬件感知**：自动识别 CPU / GPU，选型对应内核策略与驱动
- **通用增强内核（可选）**：`seika-kernel.sh` 一键编译 linux-zen 底包 + BORE 调度器——不预分发任何内核包，在你的机器上现场编译，AMD / Intel 通用
- **双内核并行（zen + lts）**：一个跑性能，一个跑稳定，GRUB 菜单自由切换
- **BTRFS + Timeshift 快照**：@ / @home / @snapshots 结构预置，滚挂了秒回退
- **国内镜像源自动测速**：清华 / 阿里 / 中科大，选最快
- **双系统 GRUB 兼容**：自动识别 Windows，支持调整菜单优先级
- **桌面环境可选**：KDE / GNOME / Hyprland / 无头模式
- **中文环境开箱即用**：locale / fcitx5 / 中文字体 一键配好
- **NVIDIA 闭源驱动支持**：nvidia-dkms + 对应内核 headers 自动匹配

---

## 两段式：先能用，再优化

Seikabook OS 把"装机"拆成两步，第一步让你快速见到桌面，第二步才是锦上添花：

**第一段：装系统（install.sh）** —— 从 Arch ISO 启动，30 分钟到 KDE 桌面

**第二段：增强内核（seika-kernel.sh）** —— 进系统后想优化时再跑，现场编译
`linux-zen + BORE` 调度器（桌面响应性提升，AMD / Intel 通用），
编译过程带完整日志，产物是独立包，与官方内核共存、GRUB 随时回退。

> 内核编译是"学习"的一部分——先让桌面跑起来，再开始折腾。

---

## 一键定制，不是"一个系统"

你可以快速安装，也可以深度定制。
它不限制你，只给你一个干净、可用、知道自己该跑成什么样的起点。
装完你会得到一个 KDE 桌面，而不是一份待办的 Arch 安装教程。

---

## 快速开始

在目标机器上（从 Arch ISO 启动后）：

```bash
curl -sSL https://gitee.com/seikabook/seikabook-os-install/raw/master/install.sh | bash
```

不需要手动分区，不需要先配置网络，不需要查 CPU 型号。
脚本会引导你完成每一步（分区 / 网络 / 桌面选择），并根据你的硬件自动做选择。

> **当前状态**：`install.sh` 主流程 v0.1 完成（分区 → pacstrap → KDE → 中文环境 → 双系统 GRUB），
> 建议先在虚拟机里试跑验证；`seika-kernel.sh` 增强内核脚本可用。
> 欢迎提 issue 反馈你遇到的硬件和问题——你踩过的坑会沉淀进下一版。

---

## 这不是一个"安装器"

它是一个把"装机经验"固化成可执行脚本的作品。
每次遇到一个新硬件，跑一次脚本，就会得到一个针对它的专属环境。

它可以用于：

- 一台 AMD 工作站
- 一台 Intel + NVIDIA 双显卡笔记本
- 一台无头服务器（LTS 内核 + 最小化服务）
- 一台家里常开的低功耗设备（x86_64 / aarch64）

只要它能跑 Arch（x86_64 / aarch64），就能用 Seikabook OS 来规划它的运行方式。

---

## 许可证

[MIT](LICENSE)，随便改，随便用。

## 项目地址

- Gitee（主源）：https://gitee.com/seikabook/seikabook-os-install
- GitHub（镜像）：同步中

---

## 最后的备注

你在别的发行版里花在"排查为什么这个硬件不工作"上的时间，
可以在 Seikabook OS 里，花在你真正想做的事情上。

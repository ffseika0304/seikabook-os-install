<h1 align="center">Seikabook OS</h1>

<p align="center"><b>Your hardware, its soul</b> — get newcomers through archiso and into KDE fast; give veterans a quick path to compiling their own kernel and shaping their own distro.</p>

<p align="center">🥇 <b>Not a distro — a community project the author actually daily-drives and shares with like-minded people</b> 🥇</p>

<p align="center">
  <a href="README.md">简体中文</a> ·
  <b>English</b>
</p>

<p align="center">
  <a href="https://github.com/ffseika0304/seikabook-os-install">GitHub (main)</a> ·
  <a href="https://gitee.com/seikabook/seikabook-os-install">Gitee (China mirror)</a>
</p>

<p align="center">
  <a href="#quick-start">Install</a> ·
  <a href="#two-stages-get-it-working-then-tune-it">Usage</a> ·
  <a href="#whats-inside">Features</a> ·
  <a href="#china-mirror">China mirror</a> ·
  <a href="https://github.com/ffseika0304/seikabook-os-install/issues">Report an issue</a>
</p>

<p align="center">
  <a href="https://github.com/ffseika0304/seikabook-os-install"><img src="https://img.shields.io/github/stars/ffseika0304/seikabook-os-install?style=flat-square&logo=github" alt="GitHub Stars"></a>
  <a href="https://github.com/ffseika0304/seikabook-os-install/fork"><img src="https://img.shields.io/github/forks/ffseika0304/seikabook-os-install?style=flat-square&logo=github" alt="GitHub Forks"></a>
  <a href="https://github.com/ffseika0304/seikabook-os-install/blob/master/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="License"></a>
  <a href="https://archlinux.org"><img src="https://img.shields.io/badge/arch-x86__64-blue?style=flat-square&logo=archlinux" alt="Arch x86_64"></a>
  <a href="https://gitee.com/seikabook/seikabook-os-install"><img src="https://img.shields.io/badge/Gitee-China%20Mirror-C71D23?style=flat-square&logo=gitee" alt="Gitee China Mirror"></a>
</p>

Seikabook OS is an Arch Linux enhancement kit built around **personal digital sovereignty**. The idea fits in one line, but the same toolkit serves two very different people:

> **Newcomers**: land on a working KDE desktop first, then start learning Arch.
> **Veterans**: even from the bare archiso prompt, restore your environment quickly and get a working blueprint for building your own kernel.

---

## What problem it solves

- New machine in hand: OS install + environment setup easily eats half a day
- Switch computers, and every piece of configuration has to be redone
- Different hardware (AMD / NVIDIA / Intel) needs different kernels, drivers and scheduling strategies
- You want BTRFS snapshots and a dual-kernel safety net against a broken rolling update, but configuring it by hand is tedious
- From inside mainland China, installing packages and pulling mirrors is slow and painful
- Newcomers bounce off the archiso black screen; veterans re-configure the same environment over and over

## Highlights

**🥇 Hardware-aware, auto-adapting.** Detects CPU / GPU and picks the matching kernel strategy and drivers. NVIDIA is graded across four generations (Maxwell+ / Kepler / Fermi / Tesla) and matched to the right driver automatically.

**🥇 Dual kernels side by side (linux + linux-lts).** One for performance, one for stability, switchable straight from the GRUB menu. Optionally use `seika-kernel.sh` to build a `linux-zen + BORE` enhanced kernel on the spot.

**🥇 Automatic mirror speed test for China.** Tsinghua / Aliyun / USTC — it picks the fastest.

**🥇 BTRFS + Timeshift snapshots.** `@` root subvolume plus `@home` user subvolume (user data stays out of snapshots by default — only the system is captured), so a broken update is one rollback away.

**🥇 Four desktop options.** KDE (default, friendliest) / GNOME / Hyprland / headless server mode.

**🥇 Dual-boot friendly GRUB.** Detects Windows via os-prober and keeps the dual-boot entry.

**🥇 Chinese locale out of the box.** locale / fcitx5 / CJK fonts configured in one pass, and the proprietary NVIDIA driver (nvidia-dkms plus the matching kernel headers) is wired up automatically.

---

## China mirror

The canonical source lives on GitHub. Users in mainland China can use the Gitee mirror for faster access:

| Purpose | Link |
|---|---|
| Repository mirror | `https://gitee.com/seikabook/seikabook-os-install` |
| Raw file access | `https://gitee.com/seikabook/seikabook-os-install/raw/master/` |
| One-line install | `curl -sSL https://gitee.com/seikabook/seikabook-os-install/raw/master/install.sh \| bash` |

---

## Two stages: get it working, then tune it

Seikabook OS splits "installing a machine" into two stages. The first one puts you in front of a desktop fast; the second one is the icing.

**Stage 1 — install the system (`install.sh`)** — boot the Arch ISO, follow the guided partitioning and installation, and you are on a KDE desktop in roughly 30 minutes. For a newcomer, this is already a fully usable system.

**Stage 2 — enhanced kernel (`seika-kernel.sh`)** — run it later, from inside the installed system, whenever you feel like tuning.
It builds `linux-zen + BORE` (better desktop responsiveness, works on both AMD and Intel) locally with a full log. The result is a standalone package that coexists with the official kernels, and GRUB lets you fall back at any time.
For veterans this is a scaffold and a starting point for building your own kernel; for newcomers it is the "now that the system works, let's go deeper" entry point.

---

## Quick start

On the target machine, after booting the Arch ISO:

```bash
curl -sSL https://gitee.com/seikabook/seikabook-os-install/raw/master/install.sh | bash
```

The script walks you through it: pick a desktop → decide whether to keep Windows dual-boot → guided partitioning (EFI / `/` / optional `/home` / swap, with partitions created automatically in free space) → create your user.
You do not need to look up your CPU model first, and you do not need to configure networking by hand — hardware detection and mirror selection are handled for you.

> **Current status**: `install.sh` has been **verified end to end on real hardware (two disks / dual boot / single EFI)** —
> from the archiso prompt to a standalone bootable KDE system, including dual kernels, fcitx5, GRUB (with a cross-disk EFI setup), the Windows dual-boot entry and Timeshift in BTRFS mode. All verified working.
> Fully automatic partitioning was removed (it was never verified on real hardware); guided manual partitioning is currently the only path.
> `seika-kernel.sh` is available and working.
> Please open an issue with the hardware and problems you run into — the potholes you hit get paved over in the next version.

Once you are in the installed system, build the enhanced kernel from a KDE terminal:

```bash
sudo bash -c "$(curl -sSL https://gitee.com/seikabook/seikabook-os-install/raw/master/seika-kernel.sh)"
```

The script detects your current kernel, compiles `linux-zen + BORE`, installs it and updates GRUB. After a reboot, pick the zen kernel under **Advanced options** in GRUB.
You can fall back to the official `linux` / `linux-lts` at any time — the enhanced kernel is an extra option, not a replacement for your default.

---

## What's inside

### Hardware support

| Feature | Details |
|---|---|
| **Architecture** | **x86_64** |
| **CPU detection** | Detects AMD / Intel and selects the matching microcode and kernel strategy |
| **NVIDIA drivers** | Four-generation grading: Maxwell+ → nvidia-dkms, Kepler → nvidia-470xx-dkms, Fermi → nvidia-390xx-dkms, Tesla → nouveau |
| **AMD / Intel integrated graphics** | Uses the in-kernel drivers by default, nothing extra to do |

### System features

| Feature | Details |
|---|---|
| **Dual kernels** | Official linux + linux-lts side by side, switchable from GRUB; optional zen+BORE enhanced kernel |
| **Filesystem** | BTRFS (`@` + `@home` subvolumes) with Timeshift snapshot support |
| **Partitioning** | Guided manual partitioning (EFI / `/` / `/home` / swap), partitions auto-created in free space |
| **Mirrors** | Tsinghua / Aliyun / USTC, fastest one chosen by speed test |
| **Dual boot** | Detects Windows via os-prober and keeps the dual-boot entry |
| **Desktops** | KDE (default) / GNOME / Hyprland / headless server mode |
| **Chinese locale** | locale / fcitx5 / CJK fonts configured in one pass |

### Repository layout

```
seikabook-os-install/
├── install.sh               # installer (975 lines)
├── seika-kernel.sh          # enhanced-kernel build script (293 lines)
├── files/
│   └── bore-zen-7.1.8.patch # BORE scheduler patch
├── LICENSE                  # MIT
└── README.md
```

---

## This is not "an installer"

It is a project that freezes hands-on install experience into an executable script.
Every time you meet a new piece of hardware, run the script once and you get an environment tailored to it.

It works for:

- An AMD workstation
- An Intel + NVIDIA hybrid-graphics laptop
- A headless server (LTS kernel + minimal services)
- A low-power box that stays on at home

Newcomers use it to land a usable desktop fast; veterans use it to restore an environment in one shot and to get a kernel build pipeline working.

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

[MIT](LICENSE) — modify it and use it however you like.

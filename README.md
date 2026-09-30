# Tick

[English](#english) | [中文](#中文)

---

## English

A minimal macOS countdown timer with menu bar integration.

<p align="center">
  <img src="screenshots/main.png" width="280" alt="Idle State">
  <img src="screenshots/running.png" width="280" alt="Running State">
  <img src="screenshots/alert.png" width="280" alt="Alert Panel">
</p>

### Features

- Circular progress ring with customizable preset timers
- Custom time input (minutes + seconds) with optional note
- Menu bar live countdown — click to quick-start, pause, cancel, or enter custom input with note
- Desktop alert with looping sound on completion (auto-stops after 45s)
- Always-on-top mode, launch at login, keyboard shortcuts, Dock badge
- Repeat last timer with one click
- Preset editor — add, remove, reorder, persist across sessions
- Daily reminders — e.g. bedtime; repeat on chosen weekdays, snooze 5 / 10 min (up to 3 times), manage them all in one window

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| Space | Pause / Resume |
| Esc | Cancel |
| Return | Start |

### Build

```bash
git clone https://github.com/qingchejun/Tick.git
cd Tick
./build.sh
open /Applications/Tick.app
```

Requires macOS 13+ and Xcode Command Line Tools.

### Install

Download `Tick.dmg` from [Releases](https://github.com/qingchejun/Tick/releases), drag `Tick.app` to `/Applications`.

### Daily Reminders

Click the 🌙 button (top toolbar) or **管理提醒…** in the menu bar to open the Reminders window. Add up to 8 reminders, pick the days, and turn them on or off in batches.

- While Tick is running, a reminder shows a full-screen-level alert with a looping sound. It also shows up over full-screen apps.
- If the Mac was asleep at reminder time, the reminder still shows when it wakes within 30 minutes.
- If Tick isn't running, macOS delivers a regular notification instead. Turn on Auto-start to get the full alert after a restart.

### What's New (v2.0)

- **Daily reminders** — repeat on chosen weekdays; snooze 5 / 10 min, up to 3 times; missed reminders show on wake; system notification backup when Tick isn't running
- **Reminders window** — see all reminders at a glance, toggle, batch on/off/delete, edit
- **Chinese UI** — all buttons and prompts are now in Chinese
- **Fixes** — alert now shows over full-screen apps; alert sound can no longer get stuck looping; cancelling no longer plays the completion animation; stricter number input

### What's New (v1.1)

- **Custom presets** — edit, add, remove, reorder preset buttons (up to 5), persisted to disk
- **Repeat last timer** — one-click button to restart previous countdown (main window + menu bar)
- **Menu bar note input** — add notes when quick-starting from menu bar popover
- **Launch at Login** — auto-start toggle in top toolbar
- **Always-on-top persisted** — pin state survives window close/reopen
- **Completion animation** — progress ring flashes green when timer finishes
- **Alert improvements** — button text changed to "Got it" with orange accent color
- **Sound auto-stop** — alert sound stops automatically after 45 seconds
- **Sleep resilience** — timer refreshes immediately after system wake
- **Keyboard hints** — shortcut tips shown below control buttons
- **Return key in text fields** — press Return to start timer from any input field

### License

MIT

---

## 中文

一个简洁的 macOS 倒计时工具，支持菜单栏常驻。

<p align="center">
  <img src="screenshots/main.png" width="280" alt="空闲状态">
  <img src="screenshots/running.png" width="280" alt="运行状态">
  <img src="screenshots/alert.png" width="280" alt="提醒面板">
</p>

### 功能

- 环形进度条 + 可自定义预设时间
- 自定义时长输入（分钟 + 秒）+ 可选备注
- 菜单栏实时倒计时 — 点击图标可快速启动、暂停、取消，支持输入备注
- 倒计时结束弹出桌面提醒，循环提示音（45 秒后自动停止）
- 窗口置顶、开机自启动、键盘快捷键、Dock 角标
- 一键重复上次计时
- 预设编辑器 — 增删改排序，持久化存储
- 每日定时提醒 — 比如睡觉提醒；可选星期几，支持稍后 5 / 10 分钟（最多 3 次），在一个窗口里集中管理

### 快捷键

| 按键 | 功能 |
|------|------|
| 空格 | 暂停 / 继续 |
| Esc | 取消 |
| 回车 | 开始 |

### 构建

```bash
git clone https://github.com/qingchejun/Tick.git
cd Tick
./build.sh
open /Applications/Tick.app
```

需要 macOS 13+ 和 Xcode Command Line Tools。

### 安装

从 [Releases](https://github.com/qingchejun/Tick/releases) 下载 `Tick.dmg`，将 `Tick.app` 拖入 `/Applications`。

### 每日提醒

点主窗口顶部的 🌙 按钮，或菜单栏里的 **管理提醒…**，打开提醒管理窗口。最多添加 8 条提醒，可以选择星期几，并批量开启或关闭。

- Tick 运行时，到点会弹出最高层级的提醒窗口，并循环播放铃声；全屏应用上也能看到。
- 到点时电脑在睡眠，只要 30 分钟内唤醒，仍会补弹提醒。
- Tick 没有运行时，由系统通知兜底。打开开机自启，重启后也能收到完整的弹窗提醒。

### 更新日志 (v2.0)

- **每日提醒** — 可选星期几；稍后 5 / 10 分钟，最多 3 次；睡眠中错过的提醒唤醒后补弹；Tick 未运行时由系统通知兜底
- **提醒管理窗口** — 集中查看所有提醒，单条开关、批量开启 / 关闭 / 删除、编辑
- **中文界面** — 按钮和提示全部改为中文
- **修复** — 全屏应用上也能看到提醒弹窗；提醒音不会再停不下来；取消计时不再误播完成动画；数字输入校验更严格

### 更新日志 (v1.1)

- **自定义预设** — 编辑、添加、删除、排序预设按钮（最多 5 个），持久化存储
- **重复上次计时** — 一键重启上次倒计时（主窗口 + 菜单栏均可）
- **菜单栏备注输入** — 从菜单栏快速启动时可添加备注
- **开机自启动** — 左上角 Auto-start 开关
- **置顶状态持久化** — 关闭窗口后重新打开仍保持置顶
- **完成动画** — 倒计时归零时进度环闪绿
- **提醒优化** — 按钮文案改为 "Got it"，橙色醒目配色
- **声音自动停止** — 提醒音 45 秒后自动停止
- **休眠恢复** — 系统唤醒后立即刷新计时
- **快捷键提示** — 控制按钮下方显示快捷键
- **回车键支持** — 在任意输入框按回车即可开始计时

### 许可证

MIT

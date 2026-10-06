# MacPulse

A quiet, native macOS menu-bar resource monitor. CPU and memory at a glance; a one-minute history when you click.

macOS 14 Sonoma or later · Apple Silicon and Intel · Korean interface · MIT license

## Install

1. Download **MacPulse-1.0.0-universal.zip** from [Releases](https://github.com/seokmogu/macpulse/releases/latest).
2. Unzip and drag **MacPulse.app** into **Applications**.
3. Open MacPulse. Look for **CPU** and **MEM** in your menu bar. There is no Dock icon.

The current release is ad-hoc signed and **not Apple notarized**. A downloaded copy may be blocked on first launch. After verifying this source and the release checksum, use macOS **System Settings → Privacy & Security → Open Anyway** if offered. Do not disable Gatekeeper. You can also build the source locally.

If there is not enough room around a MacBook notch, close an app with a long menu or move menu items with Command-drag. On macOS versions with menu-bar visibility controls, allow MacPulse in System Settings → Menu Bar.

## Use

- **Click** CPU/MEM to open the dark monitor panel; click outside or press Escape to dismiss.
- **Right-click** for Activity Monitor or Quit.
- CPU and memory show the last **60 seconds**, starting with an empty history at launch.
- Down/up speeds follow the current default network interface. Initial samples and interface changes show a dash until a rate is measurable.
- Storage is used/total space on the Data volume, based on free capacity. APFS shared containers and purgeable space can differ from Finder's "available" display.
- Battery shows charge and power-source state. Desktop Macs show no battery.
- The gear opens **1/2/5-second refresh**, **launch at login**, and **Quit**. Launch at login is off until enabled.
- Storage opens the volume in Finder; battery opens macOS battery settings; the footer opens Activity Monitor.

Only built-in system APIs are used. No administrator privileges, telemetry, account, remote API or persistent measurement logs. Preferences are stored locally. GPU, temperature, fan control and per-process monitoring are outside version 1.0.

Memory is estimated as active + inactive + wired + compressed pages, minus purgeable and external/file-backed pages, clamped to physical RAM. It is not memory pressure; it may differ slightly from Activity Monitor. CPU is normalized across all logical cores, from 0–100%. Units use decimal GB/MB/KB.

## Build

Install Xcode Command Line Tools (`xcode-select --install`) with Swift 5.9 or newer.

```sh
swift test
bash scripts/build-app.sh
open dist/MacPulse.app
```

For a universal release:

```sh
bash scripts/package-release.sh
```

For a one-second read-only telemetry sample:

```sh
dist/MacPulse.app/Contents/MacOS/MacPulse --diagnose
```

`--show` opens the panel on launch. No background agents or installers are required. To uninstall, quit MacPulse, disable its login item if enabled, and move the app to Trash.

## Design and engineering

The app follows the [selected visual concept](docs/design-reference.png). See [engineering decisions](docs/engineering.md) and [design QA](design-qa.md). System icons are Apple SF Symbols; charts are rendered with Swift Charts.

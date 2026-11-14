# macIV: Grand Theft Auto IV for macOS (Apple Silicon Native Port)

**GTA IV, native on Apple Silicon.** A build that translates the game's original x86 code
statically to ARM64 and renders directly through **Apple Metal**. Runs fluidly at **100+ FPS** with
native **Retina** and ultrawide resolutions, supports modern game controllers, activates macOS
**Game Mode** automatically, and integrates over 100 physics, timing, and visual fixes from
FusionFix and ZolikaPatch. One command turns your own copy of the game (PC v1.0.8.0) into a
ready-to-play `Grand Theft Auto IV.app`. No Wine, CrossOver, or virtual machines needed.

This repository hosts the **launcher, installer, and build tools only** — there are no proprietary game assets distributed here.

> 💡 **Works directly with Steam Complete Edition or classic v1.0.8.0!**
> You do **not** need to manually downgrade your game. If you point the installer to your modern Steam Complete Edition folder (`v1.2.0.x`), it automatically applies a clean v1.0.8.0 compatibility patch during the build process while preserving all your Complete Edition assets, radio stations, and *Episodes from Liberty City* (*The Lost and Damned* & *The Ballad of Gay Tony*) DLCs.

---

## Quick Install

**You need:** an Apple Silicon Mac (M1, M2, M3, M4 or newer) running macOS 14 (Sonoma) or later with the free Apple Command Line Tools (`xcode-select --install`), and your own copy of **Grand Theft Auto IV for PC (Steam Complete Edition or v1.0.8.0)** — the folder containing `GTAIV.exe`, `pc/`, and `common/`.

### 1. Run the one-liner in Terminal

Open **Terminal** (`Cmd+Space`, type `Terminal`, press Enter), paste this line and press Enter:

```sh
curl -fsSL https://raw.githubusercontent.com/tanmayisdumb/macIV/main/quick-install.sh | bash
```

It automatically finds your game files (Steam install, existing app, or any GTA IV folder in `~/Downloads`), compiles the native Metal engine for your Apple Silicon Mac, configures display preferences, and bakes **Grand Theft Auto IV.app** directly into your Downloads folder.

### 2. Play

When Finder opens, **drag Grand Theft Auto IV into Applications** — or just double-click it to play right away!

---

## 📥 Downloading from Steam on macOS

Because Steam for Mac does not let you install Windows games directly through the Steam GUI, here are the two easiest ways to download your legitimate PC files directly on macOS:

### Option A: Automatic Download via SteamCMD (Recommended)
SteamCMD downloads all base game files and DLC episodes pre-merged with zero manual effort:
```sh
# 1. Install SteamCMD (via Homebrew)
brew install steamcmd

# 2. Download GTA IV Complete Edition Windows files directly to your Mac
steamcmd +@sSteamCmdForcePlatformType windows +login <YOUR_STEAM_USERNAME> +app_update 12210 validate +quit
```
Once finished, run the one-line `quick-install.sh`—it automatically detects the files in `~/Library/Application Support/Steam/steamapps/common/Grand Theft Auto IV`.

### Option B: Manual Steam Console (`download_depot`)
If you download depots manually through the Steam client console (`steam://open/console`):
* Base game: `download_depot 12210 12211`
* Episodes: `download_depot 12210 12212`

> ⚠️ **macOS Finder Merging Warning:** When merging folders with the same name, Finder asks *"Do you want to Replace or Merge?"*. Never click "Replace" or you will accidentally delete essential game files!
>
> `quick-install.sh` automatically detects separate depots sitting in `~/Library/Application Support/Steam/steamapps/content/app_12210/` and merges them during the build process with zero manual moving required.
>
> If you prefer to manually merge them into a single folder, do it safely via Terminal:
> ```sh
> mkdir -p ~/Downloads/GTAIV
> cp -R ~/Library/Application\ Support/Steam/steamapps/content/app_12210/depot_12211/. ~/Downloads/GTAIV/
> cp -R ~/Library/Application\ Support/Steam/steamapps/content/app_12210/depot_12212/. ~/Downloads/GTAIV/
> ```
>
> Your merged folder structure will look like:
> ```text
> GTAIV/
> ├── GTAIV/ (or root)
> │   ├── GTAIV.exe
> │   ├── pc/
> │   └── common/
> ├── TLAD/          (The Lost and Damned)
> └── TBoGT/         (The Ballad of Gay Tony)
> ```

---

## Custom Game Paths & Options

### Using a non-Steam copy or custom folder?
Add the path to your GTA IV folder (the folder containing `GTAIV.exe` and `pc/`) or any `.app` containing the files:

```sh
curl -fsSL https://raw.githubusercontent.com/tanmayisdumb/macIV/main/quick-install.sh | bash -s -- ~/Downloads/"Grand Theft Auto IV"
```

### Prefer a classic disk image?
Add `--dmg` to produce a drag-to-Applications `Grand Theft Auto IV.dmg`:

```sh
curl -fsSL https://raw.githubusercontent.com/tanmayisdumb/macIV/main/quick-install.sh | bash -s -- --dmg
```

### Upgrading?
Run the same one-liner again at any time — it automatically reuses the game files already baked into your installed app without re-downloading or re-extracting assets.

---

## Direct Downloads

| File | Description |
|---|---|
| [`macIV-macos-arm64.tar.gz`](https://raw.githubusercontent.com/tanmayisdumb/macIV/main/macIV-macos-arm64.tar.gz) | Standalone app bundle and runtime kit without game assets |
| [`macIV-macos-arm64.zip`](https://raw.githubusercontent.com/tanmayisdumb/macIV/main/macIV-macos-arm64.zip) | Same standalone app bundle in `.zip` format |
| [`quick-install.sh`](https://raw.githubusercontent.com/tanmayisdumb/macIV/main/quick-install.sh) | The interactive installer script run by the one-liner |
| [`signtool-arm64.tar.gz`](https://raw.githubusercontent.com/tanmayisdumb/macIV/main/signtool-arm64.tar.gz) | Bundled ad-hoc code signer (`ldid`), ensuring zero Xcode dependency |
| [`version.sha`](https://raw.githubusercontent.com/tanmayisdumb/macIV/main/version.sha) | SHA256 checksum of the native launcher binary |

---

## Legal

`macIV` requires the files from your own legally purchased copy of Grand Theft Auto IV. No game assets, textures, or audio files are distributed here.

`macIV` is an independent open-source project and is not affiliated with, sponsored by, or endorsed by Rockstar Games or Take-Two Interactive. Grand Theft Auto and Grand Theft Auto IV are trademarks of Take-Two Interactive Software, Inc.

---

## What's Changed in this Port

The goal of `macIV` is a faithful, high-performance native Mac experience: authentic gameplay, look, and audio, powered by modern Apple Silicon hardware underneath.

### 🗽 Authentic Name and Retina Icon
- **Installed as `Grand Theft Auto IV.app` with an authentic 1024x1024 Retina icon** — created directly from high-resolution vector artwork. The app name on disk, in the menu bar, in Activity Monitor, and in the macOS Dock all match the official title.

### ⚡ Rendering: Direct3D 9 → Apple Metal
- Runs natively on Apple Silicon (`arm64`) through a specialized Metal renderer written specifically for GTA IV.
- Multi-threaded command buffer encoding, geometry read in place from game memory, and multiple frames in flight.
- Zero Rosetta 2 translation overhead, zero Wine translation layers.

### 🏎️ High Frame Rate & ProMotion Support
- **Uncapped Fluid Frame Rates**: Removes the legacy 30/60 FPS limits. Reaches 120+ FPS indoors and 60–100 FPS outdoors on M-series chips.
- **ProMotion Synchronization**: Smooth frame pacing on MacBook Pro 120Hz Liquid Retina XDR displays without tearing or micro-stutters.
- **TAA & MetalFX Upscaling**: Built-in support for Temporal Anti-Aliasing (TAA), SMAA, and Apple MetalFX spatial and temporal upscaling.

### 🛠️ Over 100 Fixes from FusionFix & ZolikaPatch
- **High FPS Physics Fixed**: Fixes motorcycle wheelies, boat buoyancy, vehicle suspension stiffness, and vehicle deformation bugs at frame rates above 30 FPS.
- **Fixed Out-of-the-Box**: Fixes the infamous final mission helicopter climb QTE bug that plagued the PC port on modern multi-core processors.
- **Visual Improvements**: Working searchlights on police helicopters, distant lights in Episodes from Liberty City, corrected vehicle headlights and coronas, fixed mirrors, and realistic water shaders.

### 🎮 Steam Complete Edition & Episodes from Liberty City
- **Zero Manual Downgrading Required**: The installer automatically detects modern Steam Complete Edition (`v1.2.0.x`) and applies a clean v1.0.8.0 compatibility patch on the fly.
- **Includes All DLCs**: Automatically detects and bakes *The Lost and Damned* (`TLAD`) and *The Ballad of Gay Tony* (`TBoGT`) into the standalone app bundle.
- **Complete Edition Script Crash Fixed (`SCRT70`)**: Neutralizes the fatal phone crash (`747217401`) caused by Complete Edition script files calling unregistered multiplayer natives.

### 🎮 Modern Input & Controllers
- **Native Game Controllers**: Out-of-the-box support for PlayStation DualSense / DualShock 4, Xbox Wireless, and Nintendo Switch Pro Controllers via Apple's `GameController.framework`.
- **Full Keyboard & Mouse**: Smooth raw mouse camera tracking without acceleration jumps or cursor drift.

### 📻 Independence FM (Custom User Music)
- **Play Your Own MP3s**: Drop `.mp3` tracks (between 20 seconds and 2 hours long) into:
  `~/Library/Application Support/gtaiv/drive_c/Documents and Settings/Player/My Documents/Rockstar Games/GTA IV/User Music`
- Go to **Pause Menu → Audio → Complete Scan** in-game, and your custom tracks will play on **Independence FM** with authentic DJ banter, radio commentary, and commercial breaks.

### 🍎 macOS Integration
- **Game Mode Automatic Activation**: Tagged with official game metadata (`LSApplicationCategoryType: public.app-category.games`). macOS automatically enables **Game Mode** in fullscreen, prioritizing CPU and GPU cores and doubling Bluetooth sampling rates for wireless controllers.
- **Self-contained bundle**: All game files are baked into `Contents/Resources/GameData/`. Moving the `.app` moves the entire game without leaving scattered dependencies.
- **Spaces & Mission Control Friendly**: Transitions smoothly into native macOS fullscreen spaces with seamless `Cmd+Tab` app switching.

---

## Building from Source

To build `macIV.app` from scratch on macOS:

```sh
# Clone this repository
git clone https://github.com/tanmayisdumb/macIV.git
cd macIV

# Build launcher, download runtime, and package archives
./src/build.sh
```

The build script compiles the native C launcher (`src/macIV.c`), sets up the bundle skeleton, embeds the icon and runtime kit, cleans AppleDouble metadata, ad-hoc codesigns the bundle, and outputs `macIV-macos-arm64.tar.gz` and `macIV-macos-arm64.zip`.

---

## Credits

- **[liberty-pro-max](https://github.com/Awis13/liberty-pro-max)** by [Awis13](https://github.com/Awis13) — Apple Silicon GTA IV static recompilation & Metal engine
- **[x86recomp](https://github.com/JTM-rootstorm/x86recomp)** by [JTM-rootstorm](https://github.com/JTM-rootstorm) — Foundational x86 static binary recompiler
- **[FusionFix](https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix)** by ThirteenAG & contributors — Community physics, timing, and graphics fixes
- **[ZolikaPatch](https://github.com/Zolika1351)** by Zolika1351 — Comprehensive GTA IV engine patches & gameplay fixes
- **[macVC](https://github.com/gtamac/macVC)** by [gtamac](https://github.com/gtamac) — Project inspiration & architecture
- **[Rockstar Games](https://www.rockstargames.com/)** — Original creators of Grand Theft Auto IV
#!/bin/bash
# macIV quick builder for macOS (Apple Silicon).
#
# Transforms your existing copy of Grand Theft Auto IV (PC v1.0.8.0 files)
# into a native Apple Silicon macOS app ("Grand Theft Auto IV.app").
# Renders natively through Metal, supports high refresh rates (120Hz ProMotion),
# ultrawide screens, modern game controllers, and activates macOS Game Mode automatically.
#
# Usage: quick-install.sh [--dmg] [game_files_dir]
#   --dmg            also wrap the app in a drag-to-Applications
#                    "Grand Theft Auto IV.dmg"
#   game_files_dir   optional folder that contains the game files (GTAIV.exe, pc/, common/)
#                    or a .app that contains them (Steam, Wine, CrossOver wrapper).
#                    If omitted, the script auto-detects Steam, existing installs,
#                    or copies in ~/Downloads.
set -euo pipefail

RELEASE_URL="https://raw.githubusercontent.com/tanmayisdumb/macIV/main/macIV-macos-arm64.tar.gz"
SIGNTOOL_URL="https://raw.githubusercontent.com/tanmayisdumb/macIV/main/signtool-arm64.tar.gz"
BUILDER_URL="https://github.com/Awis13/liberty-pro-max/releases/download/v0.4.1-beta/Liberty.Pro.Max.Builder.zip"
BUILDER_SHA256="80cd1bfddc1b899cff6030ab511dca01a05cd736882322cb46ce7ee816d64bb4"
EXPECTED_EXE_SHA256="3d90e7c516fa450ca002e5031e62c0f66b404590f33e6cc9793b0da4fffbfd0f"

DL="$HOME/Downloads"
APP_NAME="Grand Theft Auto IV"
VOLNAME="$APP_NAME"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"

STEAM_SRCS=(
	"$HOME/Library/Application Support/Steam/steamapps/common/Grand Theft Auto IV/GTAIV"
	"$HOME/Library/Application Support/Steam/steamapps/common/Grand Theft Auto IV"
	"$HOME/Library/Application Support/Steam/steamapps/common/grand theft auto iv/GTAIV"
	"$HOME/Library/Application Support/Steam/steamapps/common/grand theft auto iv"
	"$HOME/Library/Application Support/Steam/steamapps/content/app_12210/depot_12211/GTAIV"
	"$HOME/Library/Application Support/Steam/steamapps/content/app_12210/depot_12211"
)

# ---------------------------------------------------------------------------
# Presentation & Styling
# ---------------------------------------------------------------------------
FANCY=no
[ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ] && FANCY=yes || true

if [ "$FANCY" = yes ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 256 ]; then
	# Liberty City Amber & Industrial Steel gradient
	G1=$'\033[38;5;208m'  G2=$'\033[38;5;214m'  G3=$'\033[38;5;220m'
	G4=$'\033[38;5;221m'  G5=$'\033[38;5;222m'  G6=$'\033[38;5;223m'
	G7=$'\033[38;5;224m'
	ACCENT=$'\033[38;5;208m' GOLD=$'\033[38;5;220m'
	GREEN=$'\033[38;5;84m'   RED=$'\033[38;5;203m'
	CYAN=$'\033[38;5;51m'
	BOLD=$'\033[1m' DIM=$'\033[2m' RESET=$'\033[0m'
elif [ "$FANCY" = yes ]; then
	G1=$'\033[91m' G2=$'\033[93m' G3=$'\033[93m'
	G4=$'\033[33m' G5=$'\033[37m' G6=$'\033[37m' G7=$'\033[97m'
	ACCENT=$'\033[93m' GOLD=$'\033[93m'
	GREEN=$'\033[92m'  RED=$'\033[91m'
	CYAN=$'\033[96m'
	BOLD=$'\033[1m' DIM=$'\033[2m' RESET=$'\033[0m'
else
	G1= G2= G3= G4= G5= G6= G7= ACCENT= GOLD= GREEN= RED= CYAN= BOLD= DIM= RESET=
fi

SPIN=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
BAR_WIDTH=24

banner() {
	printf '\n'
	printf '  %s███╗   ███╗  █████╗   ██████╗  ██╗██╗   ██╗%s\n' "$G1" "$RESET"
	printf '  %s████╗ ████║ ██╔══██╗ ██╔════╝  ██║██║   ██║%s\n' "$G2" "$RESET"
	printf '  %s██╔████╔██║ ███████║ ██║       ██║██║   ██║%s\n' "$G3" "$RESET"
	printf '  %s██║╚██╔╝██║ ██╔══██║ ██║       ██║╚██╗ ██╔╝%s\n' "$G4" "$RESET"
	printf '  %s██║ ╚═╝ ██║ ██║  ██║ ╚██████╗  ██║ ╚████╔╝ %s\n' "$G5" "$RESET"
	printf '  %s╚═╝     ╚═╝ ╚═╝  ╚═╝  ╚═════╝  ╚═╝  ╚═══╝  %s\n' "$G6" "$RESET"
	printf '\n'
	printf '  %sGrand Theft Auto IV · Metal · Apple Silicon%s\n' "$DIM" "$RESET"
	printf '\n'
}

STEPS_TOTAL=6
STEP=0
step() {
	STEP=$((STEP + 1))
	printf '\n%s◆%s %s[%d/%d]%s %s\n' "$GOLD" "$RESET" "$BOLD" "$STEP" "$STEPS_TOTAL" "$RESET" "$1"
}
ok()   { printf '  %s✔%s %s\n' "$GREEN" "$RESET" "$1"; }
die() {
	printf '  %s✘ error:%s %s\n' "$RED" "$RESET" "$1" >&2
	shift
	local line
	for line in "$@"; do printf '    %s\n' "$line" >&2; done
	exit 1
}

hsize() {
	awk -v b="${1:-0}" 'BEGIN {
		u[1]="B"; u[2]="KB"; u[3]="MB"; u[4]="GB"; i=1
		while (b >= 1024 && i < 4) { b /= 1024; i++ }
		if (i == 1) printf "%d %s", b, u[i]; else printf "%.1f %s", b, u[i]
	}'
}

file_bytes() { stat -f%z "$1" 2>/dev/null || echo 0; }
du_bytes() {
	local kb
	kb=$(du -sk "$1" 2>/dev/null | awk 'NR==1 {print $1}')
	echo $(( ${kb:-0} * 1024 ))
}

draw_bar() {
	local glyph=$1 label=$2 cur=$3 total=$4
	local pct=0 filled=0 bar='' j=0 tdisp='?'
	if [ "$total" -gt 0 ]; then
		pct=$((cur * 100 / total))
		[ "$pct" -gt 100 ] && pct=100
		tdisp=$(hsize "$total")
	fi
	filled=$((pct * BAR_WIDTH / 100))
	while [ "$j" -lt "$BAR_WIDTH" ]; do
		if [ "$j" -lt "$filled" ]; then bar="${bar}█"; else bar="${bar}░"; fi
		j=$((j + 1))
	done
	printf '\r  %s %s %s%s%s %3d%%  %s%s / %s%s\033[K' \
		"$glyph" "$label" "$GOLD" "$bar" "$RESET" "$pct" \
		"$DIM" "$(hsize "$cur")" "$tdisp" "$RESET"
}

watch_bytes() {
	local pid=$1 label=$2 total=$3
	shift 3
	local i=0 rc=0 cur=0
	printf '\033[?25l'
	while kill -0 "$pid" 2>/dev/null; do
		cur=$("$@" 2>/dev/null || echo 0)
		draw_bar "${CYAN}${SPIN[$((i % 10))]}${RESET}" "$label" "$cur" "$total"
		i=$((i + 1))
		sleep 0.2
	done
	wait "$pid" || rc=$?
	printf '\033[?25h'
	if [ "$rc" -eq 0 ]; then
		if [ "$total" -le 0 ]; then
			total=$("$@" 2>/dev/null || echo 0)
		fi
		draw_bar "${GREEN}✔${RESET}" "$label" "$total" "$total"
		printf '\n'
	else
		printf '\r  %s✘%s %s failed\033[K\n' "$RED" "$RESET" "$label"
	fi
	return "$rc"
}

run_task() {
	local label=$1
	shift
	if [ "$FANCY" = no ]; then
		echo "==> $label"
		"$@"
		return
	fi
	local i=0 rc=0 pid
	"$@" &
	pid=$!
	printf '\033[?25l'
	while kill -0 "$pid" 2>/dev/null; do
		printf '\r  %s%s%s %s\033[K' "$CYAN" "${SPIN[$((i % 10))]}" "$RESET" "$label"
		i=$((i + 1))
		sleep 0.1
	done
	wait "$pid" || rc=$?
	printf '\033[?25h'
	if [ "$rc" -eq 0 ]; then
		printf '\r  %s✔%s %s\033[K\n' "$GREEN" "$RESET" "$label"
	else
		printf '\r  %s✘%s %s failed\033[K\n' "$RED" "$RESET" "$label"
	fi
	return "$rc"
}

# ---------------------------------------------------------------------------
# Options & Compatibility
# ---------------------------------------------------------------------------
WANT_DMG=no
GAME_ARG=""
for arg in "$@"; do
	case "$arg" in
		--dmg) WANT_DMG=yes ;;
		*) GAME_ARG="$arg" ;;
	esac
done

banner

if [ "$(uname -sm)" != "Darwin arm64" ]; then
	die "this installer is for Apple Silicon Macs (arm64) only"
fi

OS_VER="$(sw_vers -productVersion)"
OS_MAJOR="$(echo "$OS_VER" | cut -d. -f1)"
if [ "$OS_MAJOR" -lt 14 ]; then
	die "macIV requires macOS 14 (Sonoma) or newer (you have $OS_VER)"
fi

TMP=""
DEV=""
cleanup() {
	kill $(jobs -p) 2>/dev/null || true
	[ -n "$DEV" ] && hdiutil detach "$DEV" >/dev/null 2>&1 || true
	[ -n "$TMP" ] && rm -rf "$TMP"
	[ "$FANCY" = yes ] && printf '\033[?25h' || true
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Step 1: Locating game files
# ---------------------------------------------------------------------------
step "Locating original GTA IV (v1.0.8.0) game files"

resolve_game_dir() {
	local base="${1%/}" root dir
	for root in "$base" "$base.app"; do
		for dir in \
			"$root" \
			"$root/GTAIV" \
			"$root/depot_12211/GTAIV" \
			"$root/depot_12211" \
			"$root/Contents/Resources/GameData" \
			"$root/Contents/SharedSupport/prefix/drive_c/Program Files (x86)/Steam/steamapps/common/Grand Theft Auto IV/GTAIV" \
			"$root/Contents/SharedSupport/prefix/drive_c/Program Files/Rockstar Games/Grand Theft Auto IV"; do
			if [ -f "$dir/GTAIV.exe" ] && [ -d "$dir/pc" ]; then
				echo "$dir"
				return 0
			fi
		done
	done
	return 1
}

EXISTING_SRC=""
EXISTING_APP=""
for app in "/Applications/$APP_NAME.app" "$HOME/Applications/$APP_NAME.app" \
           "/Applications/Liberty Pro Max.app" "$HOME/Applications/Liberty Pro Max.app"; do
	if [ -d "$app/Contents/Resources/GameData" ] && [ -f "$app/Contents/Resources/GameData/GTAIV.exe" ]; then
		EXISTING_SRC="$app/Contents/Resources/GameData"
		EXISTING_APP="$app"
		break
	fi
done

if [ -n "$GAME_ARG" ]; then
	if ! ASSET_SRC="$(resolve_game_dir "$GAME_ARG")"; then
		die "no valid GTA IV game files (GTAIV.exe and pc/ folder) found in $GAME_ARG" \
			"Pass the folder containing GTAIV.exe and pc/ (or a GTA IV .app wrapper)."
	fi
	ok "Using game files from $ASSET_SRC"
elif [ -n "$EXISTING_SRC" ]; then
	ASSET_SRC="$EXISTING_SRC"
	ok "Using game files from existing install: $EXISTING_APP"
else
	ASSET_SRC=""
	for steam_cand in "${STEAM_SRCS[@]}"; do
		if [ -f "$steam_cand/GTAIV.exe" ] && [ -d "$steam_cand/pc" ]; then
			ASSET_SRC="$steam_cand"
			ok "Using game files from Steam ($steam_cand)"
			break
		fi
	done

	if [ -z "$ASSET_SRC" ]; then
		for cand in "$DL"/*; do
			[ -e "$cand" ] || continue
			[ "$(basename "$cand")" = "$APP_NAME.app" ] && continue
			c_lower="$(basename "$cand" | tr '[:upper:]' '[:lower:]')"
			case "$c_lower" in
				*gta*iv*|*gtaiv*|*gta4*|*gta*4*|*liberty*|*games*|*game*)
					if ASSET_SRC="$(resolve_game_dir "$cand")"; then
						ok "Using game files found in $ASSET_SRC"
						break
					fi
					;;
			esac
		done
	fi

	# Generic fallback: check any folder in ~/Downloads for GTAIV.exe
	if [ -z "$ASSET_SRC" ]; then
		for cand in "$DL"/*; do
			[ -d "$cand" ] || continue
			[ "$(basename "$cand")" = "$APP_NAME.app" ] && continue
			if ASSET_SRC="$(resolve_game_dir "$cand")"; then
				ok "Using game files found in $ASSET_SRC"
				break
			fi
		done
	fi

	if [ -z "$ASSET_SRC" ]; then
		die "GTA IV game files not found" \
			"macIV requires your original GTA IV PC game files (v1.0.8.0)." \
			"Point the installer to your game folder:" \
			"  $0 /path/to/Grand Theft Auto IV" \
			"or place a copy in ~/Downloads with 'GTA IV' in the folder name."
	fi
fi

# ---------------------------------------------------------------------------
# Step 2: Apple Developer Tools check
# ---------------------------------------------------------------------------
step "Checking Apple developer tools"
if ! xcode-select -p >/dev/null 2>&1; then
	printf '  %sXcode Command Line Tools are required for the static recompilation.%s\n' "$GOLD" "$RESET"
	printf '  Triggering installation prompt now...\n'
	xcode-select --install || true
	die "please complete the Apple Command Line Tools installation dialog, then run this installer again"
fi
ok "Apple Command Line Tools ready"

TMP="$(mktemp -d)"
APP="$TMP/$APP_NAME.app"
GDATA="$APP/Contents/Resources/GameData"

# Verify GTAIV.exe checksum and auto-apply clean 1.0.8.0 patch if needed
PATCHED_EXE=""
EXE_SHA="$(shasum -a 256 "$ASSET_SRC/GTAIV.exe" | awk '{print $1}')"
if [ "$EXE_SHA" != "$EXPECTED_EXE_SHA256" ]; then
	printf '\n%s⚠ Notice:%s Non-1.0.8.0 GTAIV.exe detected (%s)\n' "$GOLD" "$RESET" "$EXE_SHA"
	printf '  %sAuto-converting Complete Edition to clean Rockstar v1.0.8.0 via binary delta patch...%s\n' "$CYAN" "$RESET"
	PATCHED_EXE="$TMP/GTAIV_1080.exe"
	PATCH_FILE=""
	for p in "$SCRIPT_DIR/src/ce_to_1080.patch" "$SCRIPT_DIR/ce_to_1080.patch"; do
		if [ -f "$p" ]; then PATCH_FILE="$p"; break; fi
	done
	if [ -z "$PATCH_FILE" ]; then
		PATCH_FILE="$TMP/ce_to_1080.patch"
		curl -fsSL "https://raw.githubusercontent.com/tanmayisdumb/macIV/main/src/ce_to_1080.patch" -o "$PATCH_FILE"
	fi
	/usr/bin/bspatch "$ASSET_SRC/GTAIV.exe" "$PATCHED_EXE" "$PATCH_FILE" || die "Failed to apply Complete Edition compatibility patch"
	chmod +x "$PATCHED_EXE"
	PATCHED_SHA="$(shasum -a 256 "$PATCHED_EXE" | awk '{print $1}')"
	[ "$PATCHED_SHA" = "$EXPECTED_EXE_SHA256" ] || die "Compatibility patch verification failed (got $PATCHED_SHA, expected $EXPECTED_EXE_SHA256)"
	ok "Prepared clean v1.0.8.0 executable (SHA-256: $EXPECTED_EXE_SHA256)"
fi

# ---------------------------------------------------------------------------
# Step 3: Preparing macIV bundle & runtime kit
# ---------------------------------------------------------------------------
step "Preparing macIV bundle & runtime kit"

BUILDER_DIR="/tmp/maciv_builder"
mkdir -p "$BUILDER_DIR"
BUILDER_ZIP="$BUILDER_DIR/Liberty.Pro.Max.Builder.zip"

if [ -f "$SCRIPT_DIR/Liberty.Pro.Max.Builder.zip" ]; then
	cp "$SCRIPT_DIR/Liberty.Pro.Max.Builder.zip" "$BUILDER_ZIP"
fi

if [ ! -f "$BUILDER_ZIP" ]; then
	if [ "$FANCY" = yes ]; then
		DL_TOTAL="$(curl -sIL "$BUILDER_URL" 2>/dev/null \
			| awk 'tolower($1)=="content-length:" {cl=$2} END {printf "%d", cl}' || echo 0)"
		case "$DL_TOTAL" in ''|*[!0-9]*) DL_TOTAL=0 ;; esac
		curl -fsSL -o "$BUILDER_ZIP" "$BUILDER_URL" &
		watch_bytes $! "Liberty.Pro.Max.Builder.zip" "$DL_TOTAL" file_bytes "$BUILDER_ZIP" \
			|| die "download failed — check your connection"
	else
		echo "==> Downloading Liberty Pro Max Builder..."
		curl -fL --progress-bar -o "$BUILDER_ZIP" "$BUILDER_URL"
	fi
fi

ACTUAL_ZIP_SHA="$(shasum -a 256 "$BUILDER_ZIP" | awk '{print $1}')"
if [ "$ACTUAL_ZIP_SHA" != "$BUILDER_SHA256" ]; then
	printf '  %sWarning:%s Checksum mismatch, re-fetching...\n' "$GOLD" "$RESET"
	rm -f "$BUILDER_ZIP"
	rm -rf "$BUILDER_DIR/extracted"
	curl -fsSL -o "$BUILDER_ZIP" "$BUILDER_URL"
fi

BUILDER_APP="$BUILDER_DIR/extracted/Liberty Pro Max Builder.app"
if [ ! -d "$BUILDER_APP" ]; then
	run_task "Extracting builder kit" unzip -q "$BUILDER_ZIP" -d "$BUILDER_DIR/extracted"
fi

# Clean up all AppleDouble resource fork metadata from the builder kit (fixes "unsealed contents present in bundle root" during codesigning)
find "$BUILDER_DIR/extracted" -name "._*" -delete 2>/dev/null || true
xattr -cr "$BUILDER_DIR/extracted" 2>/dev/null || true

# Apply Complete Edition script compatibility patch (prevents SCRT70 / 747217401 when pulling out phone)
MANIFEST="$BUILDER_APP/Contents/Resources/kit/manifest/gtaiv.manifest"
EPISODES_CPP="$BUILDER_APP/Contents/Resources/kit/src/episodes.cpp"

# Restore pristine episodes.cpp from zip if needed to clean up any previously corrupt patch
if [ -f "$BUILDER_ZIP" ] && [ -f "$EPISODES_CPP" ]; then
	unzip -p "$BUILDER_ZIP" "Liberty Pro Max Builder.app/Contents/Resources/kit/src/episodes.cpp" > "$EPISODES_CPP" 2>/dev/null || true
fi

if [ -f "$MANIFEST" ] && ! grep -q "008AE060" "$MANIFEST"; then
	echo "replace 008AE060 RegisterNatives   # the Complete Edition scripts' multiplayer native, answered 0 (SCRT70 without it)" >> "$MANIFEST"
fi

if [ -f "$EPISODES_CPP" ]; then
	python3 - "$EPISODES_CPP" << 'EOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    c = f.read()
if "f_008AE060" not in c:
    c = c.replace('void f_0085A5F0_lifted(Ctx& c);', 'void f_0085A5F0_lifted(Ctx& c);\nvoid f_008AE060_lifted(Ctx& c);')
    hook = '''
void f_008AE060(Ctx& c) {
  constexpr uint32_t kMultiplayerNative = 0x2C89A1F9;
  constexpr gaddr kIsXbox360Version = 0x00B0EA50;
  constexpr gaddr kRegisterNative = 0x00626B40;
  f_008AE060_lifted(c);
  if (!(CallGuest(c, kRegisterNative, {kMultiplayerNative, kIsXbox360Version}) & 0xFF))
    WarnF("gtaiv: natives: %08X not added\\n", kMultiplayerNative);
}

}  // namespace recomp::gen'''
    c = c.replace('}  // namespace recomp::gen', hook)
    with open(path, 'w') as f:
        f.write(c)
EOF
fi

# ---------------------------------------------------------------------------
# Step 4: Translating & compiling native game engine
# ---------------------------------------------------------------------------
step "Translating & compiling native game engine"

BUILD_WORK="$BUILDER_DIR/work"
mkdir -p "$BUILD_WORK"

BUILD_SRC="$ASSET_SRC"
if [ -n "$PATCHED_EXE" ]; then
	BUILD_SRC="$TMP/stage_build"
	mkdir -p "$BUILD_SRC"
	cp "$PATCHED_EXE" "$BUILD_SRC/GTAIV.exe"
	ln -s "$ASSET_SRC/pc" "$BUILD_SRC/pc"
	ln -s "$ASSET_SRC/common" "$BUILD_SRC/common"
	for ep in TLAD TBoGT update; do
		if [ -d "$ASSET_SRC/$ep" ]; then
			ln -s "$ASSET_SRC/$ep" "$BUILD_SRC/$ep"
		elif [ -d "$ASSET_SRC/../$ep" ]; then
			ln -s "$ASSET_SRC/../$ep" "$BUILD_SRC/$ep"
		elif [ -d "$ASSET_SRC/../../depot_12212/$ep" ]; then
			ln -s "$ASSET_SRC/../../depot_12212/$ep" "$BUILD_SRC/$ep"
		elif [ -d "$ASSET_SRC/../depot_12212/$ep" ]; then
			ln -s "$ASSET_SRC/../depot_12212/$ep" "$BUILD_SRC/$ep"
		fi
	done
fi

BUILD_OUTPUT="$TMP/builder.log"
printf '  %sCompiling game code via Apple Clang (this takes ~5-15 min)...%s\n' "$DIM" "$RESET"

compile_engine() {
	BUILDER_WORK="$BUILD_WORK" BUILDER_DEST="$TMP" \
		"$BUILDER_APP/Contents/MacOS/Builder" --build "$BUILD_SRC" > "$BUILD_OUTPUT" 2>&1
}

if [ "$FANCY" = yes ]; then
	compile_engine &
	b_pid=$!
	(
		while kill -0 "$b_pid" 2>/dev/null; do
			find "$BUILD_WORK" -name "._*" -delete 2>/dev/null || true
			sleep 0.5
		done
	) &
	cleaner_pid=$!
	disown "$cleaner_pid" 2>/dev/null || true
	printf '\033[?25l'
	spin_idx=0
	last_line="Initializing translator..."
	while kill -0 "$b_pid" 2>/dev/null; do
		if [ -f "$BUILD_OUTPUT" ]; then
			curr_step="$(grep -E '^step: ' "$BUILD_OUTPUT" | tail -n 1 | sed 's/^step: //' || true)"
			[ -n "$curr_step" ] && last_line="$curr_step"
		fi
		printf '\r  %s%s%s %s\033[K' "$CYAN" "${SPIN[$((spin_idx % 10))]}" "$RESET" "$last_line"
		spin_idx=$((spin_idx + 1))
		sleep 0.2
	done
	wait "$b_pid" || rc=$?
	kill "$cleaner_pid" 2>/dev/null || true
	wait "$cleaner_pid" 2>/dev/null || true
	printf '\033[?25h'
	if [ "${rc:-0}" -ne 0 ]; then
		printf '\r  %s✘%s Build failed\033[K\n' "$RED" "$RESET"
		tail -n 25 "$BUILD_OUTPUT" >&2
		die "engine compilation failed"
	else
		printf '\r  %s✔%s Native Metal engine compiled successfully\033[K\n' "$GREEN" "$RESET"
	fi
else
	echo "==> Compiling native engine..."
	(
		while true; do
			find "$BUILD_WORK" -name "._*" -delete 2>/dev/null || true
			sleep 0.5
		done
	) &
	cleaner_pid=$!
	disown "$cleaner_pid" 2>/dev/null || true
	compile_engine || { kill "$cleaner_pid" 2>/dev/null || true; wait "$cleaner_pid" 2>/dev/null || true; tail -n 25 "$BUILD_OUTPUT"; die "engine compilation failed"; }
	kill "$cleaner_pid" 2>/dev/null || true
	wait "$cleaner_pid" 2>/dev/null || true
fi

BUILT_APP="$TMP/Liberty Pro Max.app"
if [ ! -d "$BUILT_APP" ]; then
	BUILT_APP="/Applications/Liberty Pro Max.app"
fi
[ -d "$BUILT_APP" ] || die "expected built app not found in $TMP or /Applications"

mv "$BUILT_APP" "$APP"

# Inject our native launcher & metadata
RAW_BASE="https://raw.githubusercontent.com/tanmayisdumb/macIV/main"
if [ -f "$SCRIPT_DIR/src/macIV" ]; then
	cp "$SCRIPT_DIR/src/macIV" "$APP/Contents/MacOS/macIV"
else
	MACIV_C="$TMP/macIV.c"
	if [ -f "$SCRIPT_DIR/src/macIV.c" ]; then
		cp "$SCRIPT_DIR/src/macIV.c" "$MACIV_C"
	else
		curl -fsSL "$RAW_BASE/src/macIV.c" -o "$MACIV_C"
	fi
	clang -O3 -arch arm64 -framework CoreFoundation "$MACIV_C" -o "$APP/Contents/MacOS/macIV"
fi

if [ -f "$SCRIPT_DIR/src/macIV.icns" ]; then
	cp "$SCRIPT_DIR/src/macIV.icns" "$APP/Contents/Resources/macIV.icns"
	cp "$SCRIPT_DIR/src/macIV.icns" "$APP/Contents/Resources/AppIcon.icns"
else
	curl -fsSL "$RAW_BASE/src/macIV.icns" -o "$APP/Contents/Resources/macIV.icns" 2>/dev/null || true
	cp "$APP/Contents/Resources/macIV.icns" "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null || true
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable macIV" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string macIV" "$APP/Contents/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile macIV" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :LSApplicationCategoryType string public.app-category.games" "$APP/Contents/Info.plist" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Step 5: Baking game assets into app bundle
# ---------------------------------------------------------------------------
step "Baking game assets into app bundle"

mkdir -p "$GDATA"
bake_files() {
	cp -R "$ASSET_SRC/." "$GDATA/"
	# If Complete Edition DLC folders (TLAD, TBoGT, update) exist in parent directory or sibling depot, include them
	for ep in TLAD TBoGT update; do
		if [ ! -d "$GDATA/$ep" ]; then
			if [ -d "$ASSET_SRC/../$ep" ]; then
				cp -R "$ASSET_SRC/../$ep" "$GDATA/$ep"
			elif [ -d "$ASSET_SRC/../../depot_12212/$ep" ]; then
				cp -R "$ASSET_SRC/../../depot_12212/$ep" "$GDATA/$ep"
			elif [ -d "$ASSET_SRC/../depot_12212/$ep" ]; then
				cp -R "$ASSET_SRC/../depot_12212/$ep" "$GDATA/$ep"
			fi
		fi
	done
	if [ -n "$PATCHED_EXE" ]; then
		[ -f "$GDATA/GTAIV.exe" ] && mv "$GDATA/GTAIV.exe" "$GDATA/GTAIV.exe.original"
		cp "$PATCHED_EXE" "$GDATA/GTAIV.exe"
	fi
}

if [ "$FANCY" = yes ]; then
	BAKE_TOTAL=$(du_bytes "$ASSET_SRC")
	for ep in TLAD TBoGT update; do
		if [ -d "$ASSET_SRC/../$ep" ]; then
			BAKE_TOTAL=$(( BAKE_TOTAL + $(du_bytes "$ASSET_SRC/../$ep") ))
		elif [ -d "$ASSET_SRC/../../depot_12212/$ep" ]; then
			BAKE_TOTAL=$(( BAKE_TOTAL + $(du_bytes "$ASSET_SRC/../../depot_12212/$ep") ))
		elif [ -d "$ASSET_SRC/../depot_12212/$ep" ]; then
			BAKE_TOTAL=$(( BAKE_TOTAL + $(du_bytes "$ASSET_SRC/../depot_12212/$ep") ))
		fi
	done
	bake_files &
	watch_bytes $! "Copying game assets" "$BAKE_TOTAL" du_bytes "$GDATA" \
		|| die "copying the game files failed"
else
	echo "==> Baking game files into the app..."
	bake_files
fi

# Detect Complete Edition episodes
EPISODES_FOUND=()
[ -f "$GDATA/TLAD/setup2.xml" ] && EPISODES_FOUND+=("The Lost and Damned")
[ -f "$GDATA/TBoGT/setup2.xml" ] && EPISODES_FOUND+=("The Ballad of Gay Tony")
if [ ${#EPISODES_FOUND[@]} -gt 0 ]; then
	ok "Complete Edition Episodes detected: ${EPISODES_FOUND[*]}"
fi

# Ensure commandline.txt exists to lift 32-bit texture and memory restrictions
if [ ! -f "$GDATA/commandline.txt" ]; then
	cat << 'EOF' > "$GDATA/commandline.txt"
-norestrictions
-nomemrestrict
-availablevidmem 2047
EOF
fi

# Pre-configure GameFolder and performance defaults
defaults write io.github.awis13.liberty-pro-max GameFolder "$GDATA" 2>/dev/null || true
defaults write io.github.awis13.liberty-pro-max AntiAliasing -int 4 2>/dev/null || true
defaults write io.github.awis13.liberty-pro-max VerticalSync -int 1 2>/dev/null || true
mkdir -p "$HOME/Library/Application Support/gtaiv"

# ---------------------------------------------------------------------------
# Step 6: Signing the app & finalizing
# ---------------------------------------------------------------------------
step "Ad-hoc signing the app bundle"

sign_bundle() {
	find "$APP" -name "._*" -delete 2>/dev/null || true
	xattr -cr "$APP" 2>/dev/null || true

	for fw in "$APP"/Contents/Frameworks/*.dylib; do
		[ -f "$fw" ] && codesign --force --sign - "$fw" 2>/dev/null || true
	done
	codesign --force --sign - "$APP/Contents/MacOS/gtaiv" 2>/dev/null || true
	codesign --force --sign - "$APP/Contents/MacOS/macIV" 2>/dev/null || true
	codesign --force --sign - "$APP" 2>/dev/null || true
	return 0
}

run_task "Ad-hoc signing app bundle" sign_bundle || die "code signing failed"

outro() {
	printf '\n'
	printf '%s✔ Done!%s %s\n' "$GREEN$BOLD" "$RESET" "$1"
	printf '  %s\n' "$2"
	printf '  macOS enables %sGame Mode%s automatically.\n' "$BOLD" "$RESET"
	printf '\n'
	printf '       %s🗽  Welcome to Liberty City  🗽%s\n' "$GOLD" "$RESET"
	printf '       %sfinished in %dm %02ds%s\n' "$DIM" $((SECONDS / 60)) $((SECONDS % 60)) "$RESET"
	printf '\n'
}

mkdir -p "$DL"

if [ "$WANT_DMG" = no ]; then
	rm -rf "$DL/$APP_NAME.app"
	mv "$APP" "$DL/$APP_NAME.app"
	ok "Placed $APP_NAME.app in $DL"
	outro "$DL/$APP_NAME.app is ready." \
		"Drag it into Applications (or double-click it) to play."
	open -R "$DL/$APP_NAME.app"
	exit 0
fi

# Build DMG
STAGE="$TMP/stage"
mkdir -p "$STAGE"
mv "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
TMPDMG="$TMP/rw.dmg"

dmg_create() { hdiutil create -srcfolder "$STAGE" -volname "$VOLNAME" -fs HFS+ -format UDRW "$TMPDMG" >/dev/null; }
run_task "Creating disk image" dmg_create || die "disk image creation failed"

DEV=$(hdiutil attach -readwrite -noverify -noautoopen "$TMPDMG" | grep -E '^/dev/' | awk 'NR==1{print $1}')

osascript >/dev/null 2>&1 <<APPLESCRIPT || true
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {400, 100, 900, 430}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    set position of item "$APP_NAME.app" of container window to {130, 165}
    set position of item "Applications" of container window to {370, 165}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$DEV" >/dev/null 2>&1; DEV=""
rm -f "$DL/$APP_NAME.dmg"
dmg_convert() { hdiutil convert "$TMPDMG" -format UDZO -imagekey zlib-level=9 -o "$DL/$APP_NAME.dmg" >/dev/null; }
run_task "Compressing disk image" dmg_convert || die "compressing disk image failed"

ok "Created $DL/$APP_NAME.dmg"
outro "$DL/$APP_NAME.dmg is ready." \
	"Opening it now — drag Grand Theft Auto IV into Applications."
open "$DL/$APP_NAME.dmg"

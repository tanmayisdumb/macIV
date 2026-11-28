#!/bin/bash
# build.sh - Build script for macIV (Grand Theft Auto IV for Apple Silicon macOS)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

BUILDER_URL="https://github.com/Awis13/liberty-pro-max/releases/download/v0.4.1-beta/Liberty.Pro.Max.Builder.zip"
BUILDER_SHA256="80cd1bfddc1b899cff6030ab511dca01a05cd736882322cb46ce7ee816d64bb4"

echo "==> Building macIV..."

# 1. Compile native launcher
echo "--> Compiling native launcher (macIV)..."
clang -O3 -arch arm64 -mmacosx-version-min=14.0 -Wall -Wextra -framework CoreFoundation -lz "$SCRIPT_DIR/macIV.c" -o "$SCRIPT_DIR/macIV"

# 2. Build Retina icon if not present
ICON_PATH="$SCRIPT_DIR/macIV.icns"
if [ ! -f "$ICON_PATH" ]; then
    echo "--> Generating macIV.icns from vector logo..."
    TMP_ICONSET="$(mktemp -d)/macIV.iconset"
    mkdir -p "$TMP_ICONSET"
    qlmanage -t -s 1024 -o /tmp "$SCRIPT_DIR/gta_iv_logo.svg" >/dev/null 2>&1 || true
    LOGO_PNG="/tmp/gta_iv_logo.svg.png"
    sips -z 16 16     "$LOGO_PNG" --out "$TMP_ICONSET/icon_16x16.png" >/dev/null
    sips -z 32 32     "$LOGO_PNG" --out "$TMP_ICONSET/icon_16x16@2x.png" >/dev/null
    sips -z 32 32     "$LOGO_PNG" --out "$TMP_ICONSET/icon_32x32.png" >/dev/null
    sips -z 64 64     "$LOGO_PNG" --out "$TMP_ICONSET/icon_32x32@2x.png" >/dev/null
    sips -z 128 128   "$LOGO_PNG" --out "$TMP_ICONSET/icon_128x128.png" >/dev/null
    sips -z 256 256   "$LOGO_PNG" --out "$TMP_ICONSET/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "$LOGO_PNG" --out "$TMP_ICONSET/icon_256x256.png" >/dev/null
    sips -z 512 512   "$LOGO_PNG" --out "$TMP_ICONSET/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   "$LOGO_PNG" --out "$TMP_ICONSET/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "$LOGO_PNG" --out "$TMP_ICONSET/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "$TMP_ICONSET" -o "$ICON_PATH"
    rm -rf "$(dirname "$TMP_ICONSET")"
fi

# 3. Fetch runtime & build kit
CACHE_DIR="/tmp/maciv_builder"
mkdir -p "$CACHE_DIR"
ZIP_FILE="$CACHE_DIR/Liberty.Pro.Max.Builder.zip"
if [ ! -f "$ZIP_FILE" ]; then
    echo "--> Downloading Liberty Pro Max runtime kit..."
    curl -fsSL "$BUILDER_URL" -o "$ZIP_FILE"
fi

echo "--> Verifying runtime kit checksum..."
ACTUAL_SHA="$(shasum -a 256 "$ZIP_FILE" | awk '{print $1}')"
if [ "$ACTUAL_SHA" != "$BUILDER_SHA256" ]; then
    echo "Warning: Checksum mismatch ($ACTUAL_SHA vs $BUILDER_SHA256), re-downloading..."
    rm -f "$ZIP_FILE"
    rm -rf "$CACHE_DIR/extracted"
    curl -fsSL "$BUILDER_URL" -o "$ZIP_FILE"
fi

EXTRACT_DIR="$CACHE_DIR/extracted"
if [ ! -d "$EXTRACT_DIR" ]; then
    echo "--> Extracting runtime kit..."
    mkdir -p "$EXTRACT_DIR"
    unzip -q "$ZIP_FILE" -d "$EXTRACT_DIR"
fi
find "$EXTRACT_DIR" -name "._*" -delete 2>/dev/null || true
xattr -cr "$EXTRACT_DIR" 2>/dev/null || true

KIT_SOURCE="$EXTRACT_DIR/Liberty Pro Max Builder.app/Contents/Resources/kit"
APP_TEMPLATE="$KIT_SOURCE/app/Liberty Pro Max.app"

# 4. Prepare bundle skeleton
APP_DIR="$ROOT_DIR/macIV.app"
rm -rf "$APP_DIR"
echo "--> Assembling macIV.app template bundle..."
ditto "$APP_TEMPLATE" "$APP_DIR"

mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources/GameData"
mkdir -p "$APP_DIR/Contents/Resources/kit"

# Copy runtime kit components needed for local building
cp -R "$KIT_SOURCE/bin" "$APP_DIR/Contents/Resources/kit/"
cp -R "$KIT_SOURCE/tools" "$APP_DIR/Contents/Resources/kit/"
cp -R "$KIT_SOURCE/symbols" "$APP_DIR/Contents/Resources/kit/"
cp -R "$KIT_SOURCE/manifest" "$APP_DIR/Contents/Resources/kit/"
cp -R "$KIT_SOURCE/include" "$APP_DIR/Contents/Resources/kit/"
cp -R "$KIT_SOURCE/lib" "$APP_DIR/Contents/Resources/kit/"
cp -R "$KIT_SOURCE/src" "$APP_DIR/Contents/Resources/kit/"
cp "$KIT_SOURCE/recipe.json" "$APP_DIR/Contents/Resources/kit/"

# Apply Complete Edition script & savegame compatibility patches to kit
echo "--> Applying engine compatibility hooks (CE phone fix, savegame CRC32/size bypass)..."
MANIFEST="$APP_DIR/Contents/Resources/kit/manifest/gtaiv.manifest"
EPISODES_CPP="$APP_DIR/Contents/Resources/kit/src/episodes.cpp"
COMMUNITY_CPP="$APP_DIR/Contents/Resources/kit/src/community_fixes.cpp"
LAUNCHER_OPTS_H="$APP_DIR/Contents/Resources/kit/src/launcher_options.h"

if [ -f "$MANIFEST" ]; then
    if ! grep -q "008AE060" "$MANIFEST"; then
        echo "replace 008AE060 RegisterNatives   # the Complete Edition scripts' multiplayer native, answered 0 (SCRT70 without it)" >> "$MANIFEST"
    fi
    if ! grep -q "0061EDB3" "$MANIFEST"; then
        cat << 'EOF' >> "$MANIFEST"
hook 0061EDB3 0061EDB5   # savegame: bypass CRC32 check
hook 0085B189 0085B18B   # savegame: bypass file size check against header
hook 0085B450 0085B453   # savegame: bypass total bytes read check
EOF
    fi
    if ! grep -q "007D8C44" "$MANIFEST"; then
        echo "hook 007D8C44 007D8C4B   # savegame: skip the saved radio state (converted Complete Edition saves)" >> "$MANIFEST"
    fi
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

if [ -f "$LAUNCHER_OPTS_H" ]; then
    python3 - "$LAUNCHER_OPTS_H" << 'EOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    c = f.read()
c = c.replace(
    '{@"Episodes", "GTAIV_EPISODES", @"The episodes, when their folders are in the game\'s", false, true}',
    '{@"Episodes", "GTAIV_EPISODES", @"The episodes, when their folders are in the game\'s", true, true}'
)
c = c.replace('@"PlayerFullDamage", @"Episodes", @"PhoneCheats"', '@"PlayerFullDamage", @"PhoneCheats"')
with open(path, 'w') as f:
    f.write(c)
EOF
fi

if [ -f "$COMMUNITY_CPP" ]; then
    python3 - "$COMMUNITY_CPP" << 'EOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    c = f.read()
if "hook_0061EDB3" not in c:
    hooks = '''
// Savegame compatibility hooks: allow converted (GTASnP), downgraded, or transferred save files
void hook_0061EDB3(Ctx& c) {
  static const bool on = OptionOn("GTAIV_ALLOW_CONVERTED_SAVES", true);
  if (on) {
    CmpFlags<1>(c, 0, 0);
  } else {
    CmpFlags<1>(c, c.ebx & 0xFF, Rd8(c.eax));
  }
}

void hook_0085B189(Ctx& c) {
  static const bool on = OptionOn("GTAIV_ALLOW_CONVERTED_SAVES", true);
  if (on) {
    CmpFlags<1>(c, 1, 0);
  } else {
    CmpFlags<1>(c, c.eax & 0xFF, c.ebx & 0xFF);
  }
}

void hook_0085B450(Ctx& c) {
  static const bool on = OptionOn("GTAIV_ALLOW_CONVERTED_SAVES", true);
  if (on) {
    CmpFlags<4>(c, 0, 0);
  } else {
    CmpFlags<4>(c, c.edx, Rd32(c.eax + 4));
  }
}

}  // namespace recomp::gen'''
    idx = c.rfind('}  // namespace recomp::gen')
    if idx != -1:
        c = c[:idx] + hooks + c[idx+len('}  // namespace recomp::gen'):]
        with open(path, 'w') as f:
            f.write(c)
EOF
    python3 - "$COMMUNITY_CPP" << 'EOF'
import sys
path = sys.argv[1]
with open(path, 'r') as f:
    c = f.read()
if "hook_007D8C44" not in c:
    hooks = '''
// Savegame: the radio block is read and discarded (as with the radio flag clear)
// so converted Complete Edition saves, whose radio state layout differs, load.
void hook_007D8C44(Ctx& c) { CmpFlags<1>(c, 0, 0); }

}  // namespace recomp::gen'''
    idx = c.rfind('}  // namespace recomp::gen')
    if idx != -1:
        c = c[:idx] + hooks + c[idx+len('}  // namespace recomp::gen'):]
        with open(path, 'w') as f:
            f.write(c)
EOF
fi

# Copy Builder app binary for headless / GUI builds
mkdir -p "$APP_DIR/Contents/Resources/builder"
cp "$EXTRACT_DIR/Liberty Pro Max Builder.app/Contents/MacOS/Builder" "$APP_DIR/Contents/Resources/builder/Builder"

# Copy launcher, icon, and utility tools
cp "$SCRIPT_DIR/macIV" "$APP_DIR/Contents/MacOS/macIV"
cp "$ICON_PATH" "$APP_DIR/Contents/Resources/macIV.icns"
if [ -f "$SCRIPT_DIR/ce_to_1080.patch" ]; then
    echo "--> Bundling Complete Edition delta patch & downgrader..."
    cp "$SCRIPT_DIR/ce_to_1080.patch" "$APP_DIR/Contents/Resources/ce_to_1080.patch"
    cp "$SCRIPT_DIR/downgrade.sh" "$APP_DIR/Contents/Resources/downgrade.sh"
fi
if [ -f "$SCRIPT_DIR/fix_save.py" ]; then
    echo "--> Bundling savegame repair tool..."
    cp "$SCRIPT_DIR/fix_save.py" "$APP_DIR/Contents/Resources/fix_save.py"
    chmod +x "$APP_DIR/Contents/Resources/fix_save.py"
elif [ -f "$ROOT_DIR/tools/fix_save.py" ]; then
    echo "--> Bundling savegame repair tool..."
    cp "$ROOT_DIR/tools/fix_save.py" "$APP_DIR/Contents/Resources/fix_save.py"
    chmod +x "$APP_DIR/Contents/Resources/fix_save.py"
fi
if [ -f "$ROOT_DIR/tools/convert_ce_save.py" ]; then
    echo "--> Bundling Complete Edition save converter..."
    cp "$ROOT_DIR/tools/convert_ce_save.py" "$APP_DIR/Contents/Resources/convert_ce_save.py"
    chmod +x "$APP_DIR/Contents/Resources/convert_ce_save.py"
fi
chmod +x "$APP_DIR/Contents/MacOS/macIV"

# 5. Create Info.plist
cat << 'PLIST' > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>Grand Theft Auto IV</string>
	<key>CFBundleExecutable</key>
	<string>macIV</string>
	<key>CFBundleIconFile</key>
	<string>macIV</string>
	<key>CFBundleIdentifier</key>
	<string>com.github.gtamac.macIV</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>macIV</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.4.1</string>
	<key>CFBundleVersion</key>
	<string>0.4.1</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.games</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSSupportsAutomaticGraphicsSwitching</key>
	<true/>
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsArbitraryLoads</key>
		<true/>
	</dict>
</dict>
</plist>
PLIST

# 6. Create PkgInfo
printf "APPL????" > "$APP_DIR/Contents/PkgInfo"

# 7. Clean dot files & sign bundle ad-hoc
echo "--> Cleaning metadata & signing macIV.app bundle..."
find "$APP_DIR" -name "._*" -delete 2>/dev/null || true
xattr -cr "$APP_DIR" 2>/dev/null || true

for fw in "$APP_DIR"/Contents/Frameworks/*.dylib; do
    [ -f "$fw" ] && codesign --force --sign - "$fw" 2>/dev/null || true
done
codesign --force --sign - "$APP_DIR/Contents/MacOS/macIV"
codesign --force --sign - "$APP_DIR"

# 8. Compute version.sha
echo "--> Computing version.sha..."
shasum -a 256 "$APP_DIR/Contents/MacOS/macIV" | awk '{print $1}' > "$ROOT_DIR/version.sha"
cp "$ROOT_DIR/version.sha" "$APP_DIR/Contents/Resources/version.sha"

# 9. Package archives
echo "--> Packaging release archives..."
cd "$ROOT_DIR"
rm -f macIV-macos-arm64.tar.gz macIV-macos-arm64.zip
COPYFILE_DISABLE=1 tar -czf macIV-macos-arm64.tar.gz macIV.app
zip -q -r macIV-macos-arm64.zip macIV.app -x "*.DS_Store"

echo "✔ Build complete!"
ls -lh macIV-macos-arm64.tar.gz macIV-macos-arm64.zip version.sha

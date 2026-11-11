#!/bin/bash
# build.sh - Build script for macIV (Grand Theft Auto IV for Apple Silicon macOS)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

BUILDER_URL="https://github.com/Awis13/liberty-pro-max/releases/download/v0.3.5-beta/Liberty.Pro.Max.Builder.zip"
BUILDER_SHA256="c01c93b58885b0f0fa8a1112757f0cdb7b96e03e0f58e90ddd1cdf9108a76948"

echo "==> Building macIV..."

# 1. Compile native launcher
echo "--> Compiling native launcher (macIV)..."
clang -O3 -arch arm64 -Wall -Wextra -framework CoreFoundation "$SCRIPT_DIR/macIV.c" -o "$SCRIPT_DIR/macIV"

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

# Copy Builder app binary for headless / GUI builds
mkdir -p "$APP_DIR/Contents/Resources/builder"
cp "$EXTRACT_DIR/Liberty Pro Max Builder.app/Contents/MacOS/Builder" "$APP_DIR/Contents/Resources/builder/Builder"

# Copy launcher and icon
cp "$SCRIPT_DIR/macIV" "$APP_DIR/Contents/MacOS/macIV"
cp "$ICON_PATH" "$APP_DIR/Contents/Resources/macIV.icns"
if [ -f "$SCRIPT_DIR/ce_to_1080.patch" ]; then
    echo "--> Bundling Complete Edition delta patch & downgrader..."
    cp "$SCRIPT_DIR/ce_to_1080.patch" "$APP_DIR/Contents/Resources/ce_to_1080.patch"
    cp "$SCRIPT_DIR/downgrade.sh" "$APP_DIR/Contents/Resources/downgrade.sh"
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
	<string>0.3.5</string>
	<key>CFBundleVersion</key>
	<string>0.3.5</string>
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

#!/bin/bash
set -e

echo "🔨 Building Token Island (Release mode)..."
cd "$(dirname "$0")"

swift build -c release

APP_NAME="token_island.app"
DEST_APP="/Applications/$APP_NAME"

echo "📦 Packaging into $APP_NAME..."
mkdir -p "$APP_NAME/Contents/MacOS"
mkdir -p "$APP_NAME/Contents/Resources"

cp .build/release/token_island "$APP_NAME/Contents/MacOS/token_island"

if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$APP_NAME/Contents/Resources/AppIcon.icns"
fi

cat << 'PLIST' > "$APP_NAME/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>token_island</string>
    <key>CFBundleIdentifier</key>
    <string>com.yupi.tokenisland</string>
    <key>CFBundleName</key>
    <string>token_island</string>
    <key>CFBundleDisplayName</key>
    <string>Token Island</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "✍️ Signing app bundle..."
xattr -cr "$APP_NAME"
codesign --force --deep --sign - "$APP_NAME"

echo "🚚 Installing to /Applications..."
pkill -f token_island || true
rm -rf "$DEST_APP"
cp -R "$APP_NAME" "$DEST_APP"

echo "🚀 Launching Token Island..."
open "$DEST_APP"

echo "🎉 Token Island is successfully built and running!"

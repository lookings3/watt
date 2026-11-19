#!/bin/bash
# Builds and opens "Watt Preview.app", a separate app for checking the icon and panel with made-up values.
# It runs alongside Watt, saves no history, and never changes Low Power Mode or the saved language.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
swift build -c release --scratch-path .build
BIN=$(swift build -c release --scratch-path .build --show-bin-path)/Watt
APP="Watt Preview.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Watt"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'P'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.watt.preview</string>
<key>CFBundleName</key><string>Watt Preview</string>
<key>CFBundleExecutable</key><string>Watt</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
P
codesign -s - --force "$APP"
pkill -f "Watt Preview.app/Contents/MacOS/Watt" 2>/dev/null || true
open "$APP"
echo "Opened: $PWD/$APP"

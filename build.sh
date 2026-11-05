#!/bin/bash
# Builds Watt.app.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
swift build -c release --scratch-path .build
BIN=$(swift build -c release --scratch-path .build --show-bin-path)/Watt
rm -rf Watt.app
mkdir -p Watt.app/Contents/MacOS
cp "$BIN" Watt.app/Contents/MacOS/Watt
mkdir -p Watt.app/Contents/Resources
cp Resources/AppIcon.icns Watt.app/Contents/Resources/AppIcon.icns
cat > Watt.app/Contents/Info.plist <<'P'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.watt.menubar</string>
<key>CFBundleName</key><string>Watt</string>
<key>CFBundleExecutable</key><string>Watt</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
P
codesign -s - --force Watt.app
echo "Built: $PWD/Watt.app"

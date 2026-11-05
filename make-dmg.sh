#!/bin/bash
# Builds dist/Watt.dmg.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
./build.sh
rm -rf dist
mkdir -p dist/stage
cp -R Watt.app dist/stage/
ln -s /Applications dist/stage/Applications
hdiutil create -quiet -volname Watt -srcfolder dist/stage -ov -format UDZO dist/Watt.dmg
rm -rf dist/stage
echo "Done: $PWD/dist/Watt.dmg"

#!/bin/bash
# Developer script: quits the app and removes the sudo rule, settings, history, and this source folder.
# --dry-run only prints what would happen.
set -euo pipefail
RULE=/etc/sudoers.d/watt-lowpower
AGENT="$HOME/Library/LaunchAgents/local.watt.menubar.plist"
STORE="$HOME/Library/Application Support/Watt"
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1

# Makes sure this is the project folder before deleting anything.
if [ "$(basename "$DIR")" != "watt" ] || [ ! -f "$DIR/Package.swift" ] || [ ! -f "$DIR/SPEC.md" ]; then
  echo "Stopped: $DIR is not the Watt project folder." >&2
  exit 1
fi

echo "This will remove:"
echo "  - The running Watt app (quit)"
echo "  - sudo rule: $RULE"
echo "  - Launch settings: $AGENT"
echo "  - History: $STORE"
echo "  - Entire folder: $DIR"
[ "$DRY" = 1 ] && { echo "(dry run: nothing was removed)"; exit 0; }

read -r -p "Continue? (y/N) " A
[ "$A" = "y" ] || [ "$A" = "Y" ] || { echo "Cancelled."; exit 0; }

launchctl bootout "gui/$(id -u)/local.watt.menubar" 2>/dev/null || true
rm -f "$AGENT"
rm -rf -- "$STORE"
pkill -x Watt 2>/dev/null || true
sudo rm -f "$RULE"
[ ! -e "$RULE" ] || { echo "Couldn't remove the rule, so the folder was kept." >&2; exit 1; }
cd /
rm -rf -- "$DIR"
echo "Removed. Low Power Mode stays in its current state."

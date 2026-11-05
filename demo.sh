#!/bin/bash
# Demo that cycles through power states every 5 seconds. Ctrl+C restores the normal app.
set -u
DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
LABEL=local.watt.menubar
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
restore() {
  if [ -f "$PLIST" ] && grep -q KeepAlive "$PLIST"; then
    launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null
    launchctl kickstart "gui/$(id -u)/$LABEL" 2>/dev/null
  else
    open "$DIR/Watt.app"
  fi
}
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
pkill -x Watt 2>/dev/null
sleep 0.5
trap 'pkill -x Watt 2>/dev/null; sleep 0.5; restore; echo; echo "Demo ended. The normal app is running again."; exit 0' INT TERM
echo "Demo running. Click the menu bar icon. Press Ctrl+C to stop."
"$DIR/Watt.app/Contents/MacOS/Watt" --demo &
wait $!

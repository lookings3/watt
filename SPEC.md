# Watt specification

A menu bar battery app for Apple silicon MacBooks.

- Target: Apple silicon MacBooks, macOS 14 or later. Developed on an M5 MacBook with macOS 27.
- Distribution: DMG on GitHub Releases, free and not notarized.
- Built with Swift, SwiftUI, and Swift Charts.

## 1. Goal

Work like the macOS battery menu, and add power flow, temperature, and history.

## 2. Features

### 2.1 Menu bar icon

- Shows a battery icon with the level inside it.
- Shows a bolt while charging, and a plug when plugged in but not charging.
- Turns yellow in Low Power Mode.
- Reads Low Power Mode from the system, so changes made outside the app appear immediately.

### 2.2 Low Power Mode switch

- A row below the level bar, with a round leaf icon and a switch. The icon, switch, and level bar turn yellow when it's on.
- Manual only. There's no automatic switching by level or power source.
- Runs `sudo -n /usr/bin/pmset -a lowpowermode 0|1`.
- Uses a sudo rule that allows only those two commands without a password.
- If the rule is missing, the first use explains why and installs it through the macOS administrator prompt. The app never receives or stores the password.
- Cancelling leaves every other feature working.
- On failure, the switch returns to its real state and the panel shows the reason.

### 2.3 Panel information

- The top of the panel is a large level bar with the percentage and remaining time inside it. A Low Power Mode row sits below it.

| Item | Content |
|---|---|
| Status | Charging, plugged in and not charging, or on battery |
| Time | Time until full or empty |
| Temperature | Battery temperature in °C |
| Health | Maximum capacity and cycle count |

### 2.4 History and charts

- Saves level, power, temperature, charging state, and Low Power Mode state every minute.
- Charts level, power, or temperature over 24 hours or 7 days.
- Deletes records after 30 days.

### 2.5 Charge limit

- The app doesn't control charging. It relies on the built-in macOS charge limit.
- The panel has a button that opens the macOS Battery settings.

### 2.6 Power flow

- Sits below the battery information.
- Shows power usage, current, voltage, and charging state at the top.
- Connects charger, Mac, and battery tiles with flat translucent bands. No gradients.
- Each band shows its wattage. There's no flowing animation.
- Band thickness and curves follow the power share. They animate for 0.5 seconds only when values change.
- Only bands charging the battery are green. Battery use and bands to the Mac are neutral.
- A status sentence and the charger's input and rated power appear below.
- If power reads 0 on battery, as it can right after waking, the app shows Measuring and skips that record.

### 2.7 Settings

- The gear icon opens a small settings window.
- Language: System, Korean, or English.
- Open at login.
- Restart automatically: reopens the app after a crash, but not after Quit Watt.
- Both launch options share one user LaunchAgent, removed when both are off.
- Only one copy of the app runs at a time.

### 2.8 Resource use

- Keep resource use minimal.
- Read battery values every 30 seconds, with power source changes applied immediately.
- Don't redraw when values are unchanged.
- Build the panel on open and release it on close.

### 2.9 Language

- Supports English and Korean.
- System mode uses Korean on a Korean Mac and English otherwise.
- The panel applies a language change the next time it opens.

## 3. Out of scope

- Per-app power use (removed to avoid running `top`)
- Notifications
- Controlling charging or forcing discharge (no SMC writes)
- A root helper
- iPhone and iPad battery information
- Automatic Low Power Mode switching

## 4. Install and uninstall

- Install: move `Watt.app` from the DMG to Applications. No Terminal needed.
- History is stored in `~/Library/Application Support/Watt`. An older `data/history.csv` next to the app is copied on first launch.
- The app may leave its storage folder, `/etc/sudoers.d/watt-lowpower`, and `~/Library/LaunchAgents/local.watt.menubar.plist` on the system.
- Completely remove Watt deletes those items, moves the app to the Trash, and quits. It asks for an administrator password if the rule exists. Cancelling removes nothing.
- Dragging the app to the Trash leaves those items. The README lists the manual cleanup commands.
- `uninstall.sh` is for developers and also deletes the source folder.
- After moving the app, turn the launch options on again.

## 5. Verified behavior

| Item | Result |
|---|---|
| Level, power, cycles, capacity | Readable without admin rights |
| Battery temperature | Readable from SMC keys `TB0T` to `TB2T` on M5 |
| `pmset` without root | Rejected |
| Shortcuts for Low Power Mode | Failed, not used |
| `sudo pmset` with the rule | Works. Other `pmset` commands are rejected |

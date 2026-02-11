#!/usr/bin/env bash
set -euo pipefail

disk_name="${1:?usage: configure_dmg_layout.sh <disk-name> <app-item-name> <app-x> <app-y> <apps-x> <apps-y> <window-width> <window-height> <has-background>}"
app_item_name="${2:?usage: configure_dmg_layout.sh <disk-name> <app-item-name> <app-x> <app-y> <apps-x> <apps-y> <window-width> <window-height> <has-background>}"
app_x="${3:?usage: configure_dmg_layout.sh <disk-name> <app-item-name> <app-x> <app-y> <apps-x> <apps-y> <window-width> <window-height> <has-background>}"
app_y="${4:?usage: configure_dmg_layout.sh <disk-name> <app-item-name> <app-x> <app-y> <apps-x> <apps-y> <window-width> <window-height> <has-background>}"
applications_x="${5:?usage: configure_dmg_layout.sh <disk-name> <app-item-name> <app-x> <app-y> <apps-x> <apps-y> <window-width> <window-height> <has-background>}"
applications_y="${6:?usage: configure_dmg_layout.sh <disk-name> <app-item-name> <app-x> <app-y> <apps-x> <apps-y> <window-width> <window-height> <has-background>}"
window_width="${7:?usage: configure_dmg_layout.sh <disk-name> <app-item-name> <app-x> <app-y> <apps-x> <apps-y> <window-width> <window-height> <has-background>}"
window_height="${8:?usage: configure_dmg_layout.sh <disk-name> <app-item-name> <app-x> <app-y> <apps-x> <apps-y> <window-width> <window-height> <has-background>}"
has_background="${9:-false}"

osascript - "$disk_name" "$app_item_name" "$app_x" "$app_y" "$applications_x" "$applications_y" "$window_width" "$window_height" "$has_background" <<'OSA'
on run argv
    set diskName to item 1 of argv
    set appItemName to item 2 of argv
    set appX to (item 3 of argv) as integer
    set appY to (item 4 of argv) as integer
    set applicationsX to (item 5 of argv) as integer
    set applicationsY to (item 6 of argv) as integer
    set windowWidth to (item 7 of argv) as integer
    set windowHeight to (item 8 of argv) as integer
    set hasBackground to item 9 of argv
    set leftEdge to 120
    set topEdge to 120

    tell application "Finder"
        tell disk diskName
            open
            delay 0.6

            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set bounds of container window to {leftEdge, topEdge, leftEdge + windowWidth, topEdge + windowHeight}

            set iconOptions to the icon view options of container window
            set arrangement of iconOptions to not arranged
            set icon size of iconOptions to 104
            set text size of iconOptions to 12

            if hasBackground is "true" then
                set background picture of iconOptions to file ".background:background.png"
            end if

            set position of item appItemName of container window to {appX, appY}
            set position of item "Applications" of container window to {applicationsX, applicationsY}
            update without registering applications
            delay 0.8
            close
            open
            delay 0.4
        end tell
    end tell
end run
OSA

#!/usr/bin/env bash
set -euo pipefail
eval "$(gnome-keyring-daemon --start --components=secrets)"
check_window() {
 local binary=$1 log=$2
 "$binary" > "$log" 2>&1 &
 local app_pid=$!
 trap 'kill "$app_pid" 2>/dev/null || true' RETURN
 local found=0
 for attempt in {1..25}; do
  kill -0 "$app_pid"
  if xdotool search --onlyvisible --name 'OpenWrt Studio' >/dev/null; then found=1; break; fi
  sleep 1
 done
 [[ $found = 1 ]]
 sleep 5
 kill -0 "$app_pid"
 if grep -E 'Unhandled Exception|Failed to load dynamic library|error while loading shared libraries' "$log"; then return 1; fi
 xwd -root -silent | convert xwd:- "$log.png"
 kill "$app_pid"
 wait "$app_pid" || true
 trap - RETURN
}
mkdir -p checks
check_window "$PWD/build/linux/x64/release/bundle/openwrt-studio" "$PWD/checks/native-startup.log"
appimage=$(find release -maxdepth 1 -name '*.AppImage' -print -quit)
chmod +x "$appimage"
(cd build && "../$appimage" --appimage-extract >/dev/null)
check_window "$PWD/build/squashfs-root/AppRun" "$PWD/checks/appimage-startup.log"

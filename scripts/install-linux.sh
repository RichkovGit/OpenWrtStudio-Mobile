#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
prefix=${1:-"$HOME/.local"}
[[ -x ./openwrt-studio && -d ./data && -d ./lib ]]
target="$prefix/lib/openwrt-studio"
mkdir -p "$target" "$prefix/bin" "$prefix/share/applications" "$prefix/share/icons/hicolor/256x256/apps"
cp -a ./openwrt-studio ./data ./lib "$target/"
# Resolve paths before writing desktop entries; support spaces in the install prefix.
target=$(cd "$target" && pwd)
ln -sfn "$target/openwrt-studio" "$prefix/bin/openwrt-studio"
cp ./openwrt-studio.png "$prefix/share/icons/hicolor/256x256/apps/openwrt-studio.png"
python3 - "$target" "$prefix" <<'PY'
import sys
from pathlib import Path
root,prefix=map(Path,sys.argv[1:])
source=Path('openwrt-studio.desktop').read_text()
exe=str(root/'openwrt-studio').replace('\\','\\\\').replace('"','\\"').replace('`','\\`').replace('$','\\$')
source=source.replace('Exec=openwrt-studio',f'Exec="{exe}"').replace('Icon=openwrt-studio','Icon='+str(prefix.resolve()/'share/icons/hicolor/256x256/apps/openwrt-studio.png'))
(prefix/'share/applications/openwrt-studio.desktop').write_text(source)
PY
printf 'Installed: %s\nRun: %s\n' "$target" "$prefix/bin/openwrt-studio"

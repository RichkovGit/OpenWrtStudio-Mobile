#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob
cd "$(dirname "$0")/.."
bundle=build/linux/x64/release/bundle
[[ -x "$bundle/openwrt-studio" ]]
version=$(sed -n 's/^version: \([^+]*\).*/\1/p' pubspec.yaml)
mkdir -p release
folder="OpenWrtStudio-${version}-linux-x86_64"
rm -rf "release/$folder"
mkdir -p "release/$folder"
cp -a "$bundle/." "release/$folder/"
cp LINUX_INSTALL.md packaging/linux/openwrt-studio.desktop packaging/linux/openwrt-studio.png scripts/install-linux.sh "release/$folder/"
tar -czf "release/$folder.tar.gz" -C release "$folder"
# linuxdeploy and its GTK plugin are supplied by the build job or the developer.
if [[ -n "${LINUXDEPLOY:-}" ]]; then
 appdir=build/AppDir
 rm -rf "$appdir"
 mkdir -p "$appdir/usr/bin"
 cp -a "$bundle/." "$appdir/usr/bin/"
 args=(--appdir "$appdir" --executable "$appdir/usr/bin/openwrt-studio" --desktop-file packaging/linux/openwrt-studio.desktop --icon-file packaging/linux/openwrt-studio.png --plugin gtk --output appimage)
 while IFS= read -r lib; do args+=(--library "$lib"); done < <(find "$bundle/lib" -type f -name '*.so')
 export APPIMAGE_EXTRACT_AND_RUN=1 DEPLOY_GTK_VERSION=3
 export OUTPUT="$(pwd)/release/OpenWrtStudio-${version}-x86_64.AppImage"
 "$LINUXDEPLOY" "${args[@]}"
 [[ -s "$OUTPUT" ]]
fi
(cd release && sha256sum ./*.tar.gz ./*.AppImage 2>/dev/null > SHA256SUMS.txt)

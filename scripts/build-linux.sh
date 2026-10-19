#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Keep the mobile application/services and generate only the standard Flutter Linux runner.
if [[ ! -f linux/CMakeLists.txt ]]; then
 runner_source=$(mktemp -d)
 trap 'rm -rf "$runner_source"' EXIT
 flutter create --platforms=linux --org org.openwrtstudio --project-name luci_mobile --no-pub "$runner_source/luci_mobile"
 cp -a "$runner_source/luci_mobile/linux" ./linux
 rm -rf "$runner_source"
 trap - EXIT
fi
python3 - <<'PY'
from pathlib import Path
p=Path('linux/CMakeLists.txt');s=p.read_text();s=s.replace('set(BINARY_NAME "luci_mobile")','set(BINARY_NAME "openwrt-studio")').replace('set(APPLICATION_ID "org.openwrtstudio.luci_mobile")','set(APPLICATION_ID "org.openwrtstudio.Studio")');p.write_text(s)
p=Path('linux/runner/my_application.cc');s=p.read_text().replace('"luci_mobile"','"OpenWrt Studio"');p.write_text(s)
PY
flutter pub get
flutter build linux --release

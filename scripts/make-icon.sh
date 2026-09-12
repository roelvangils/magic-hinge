#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
xcode_version="$(xcodebuild -version | sed -n 's/^Xcode //p')"
if (( ${xcode_version%%.*} < 27 )); then
  print -u2 'Magic Hinge icons require Xcode 27 or later. Select it with xcode-select or DEVELOPER_DIR.'
  exit 1
fi
mkdir -p build/composer-compiled
minimum="$(python3 -c 'import json; print(json.load(open("release.json"))["minimumSystemVersion"])')"
# actool preserves native light/dark Liquid Glass layers and supplies the legacy ICNS.
xcrun actool 'assets/Magic Hinge.icon' --compile build/composer-compiled \
  --platform macosx --minimum-deployment-target "$minimum" --app-icon 'Magic Hinge' \
  --output-partial-info-plist build/composer-compiled/partial-info.plist \
  --output-format human-readable-text
cp 'build/composer-compiled/Magic Hinge.icns' build/AppIcon.icns

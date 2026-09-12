#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build/composer-compiled
minimum="$(python3 -c 'import json; print(json.load(open("release.json"))["minimumSystemVersion"])')"
# actool preserves native light/dark Liquid Glass layers and supplies the legacy ICNS.
xcrun actool 'assets/Magic Hinge.icon' --compile build/composer-compiled \
  --platform macosx --minimum-deployment-target "$minimum" --app-icon 'Magic Hinge' \
  --output-partial-info-plist build/composer-compiled/partial-info.plist \
  --output-format human-readable-text
cp 'build/composer-compiled/Magic Hinge.icns' build/AppIcon.icns

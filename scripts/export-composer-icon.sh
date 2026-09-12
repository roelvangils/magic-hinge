#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
composer_tool="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}/../Applications/Icon Composer.app/Contents/Executables/ictool"
mkdir -p assets/icon-previews
for appearance in Default Dark; do
  label=Light
  [[ "$appearance" == Dark ]] && label=Dark
  "$composer_tool" 'assets/Magic Hinge.icon' --export-image \
    --output-file "assets/icon-previews/Magic-Hinge-${label}.png" \
    --platform macOS --rendition "$appearance" \
    --width 1024 --height 1024 --scale 1 --design-generation 27
done

cp assets/icon-previews/Magic-Hinge-Light.png assets/AppIcon.png
cp assets/icon-previews/Magic-Hinge-Dark.png assets/AppIcon-Dark.png
sips -z 256 256 assets/AppIcon.png --out website/assets/icon-light.png >/dev/null
sips -z 256 256 assets/AppIcon-Dark.png --out website/assets/icon-dark.png >/dev/null
cp website/assets/icon-light.png website/assets/icon.png

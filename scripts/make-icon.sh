#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build/AppIcon.iconset
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" assets/AppIcon.png --out "build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" assets/AppIcon.png --out "build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns

#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mode="${1:-development}"
case "$mode" in
  development|debug) configuration=debug; mode=development ;;
  release) configuration=release; mode=development ;;
  distribution) configuration=release ;;
  *) print -u2 'Usage: scripts/build-app.sh [development|debug|release|distribution]'; exit 2 ;;
esac
mkdir -p build
# A fresh scratch directory for distribution prevents stale modules and bundled resources.
if [[ "$mode" == distribution ]]; then
  scratch="$(mktemp -d "$PWD/build/release-swift.XXXXXX")"
else
  scratch="$PWD/.build"
fi
swift build --scratch-path "$scratch" -c "$configuration" --arch arm64 --disable-automatic-resolution \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks
bin_dir="$(swift build --scratch-path "$scratch" -c "$configuration" --arch arm64 --show-bin-path)"
scripts/make-icon.sh
# Assemble a new bundle each time; replace the old output only after verification.
staging="$(mktemp -d "$PWD/build/app-stage.XXXXXX")"
app="$staging/Magic Hinge.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$bin_dir/MagicHinge" "$app/Contents/MacOS/MagicHinge"
for name in MagicHinge_DuoCore MagicHinge_DuoGraphics MagicHinge_DuoSimulation MagicHinge_MagicHinge PermissionFlow_PermissionFlow; do
  ditto "$bin_dir/$name.bundle" "$app/Contents/Resources/$name.bundle"
done
# SwiftPM can retain obsolete copied resources in incremental development products.
python3 - "$app" <<'PYCODE'
from pathlib import Path
import sys
for name in ('DuoNight.jpg', 'DesertWallpaper.jpg'):
    for obsolete in Path(sys.argv[1]).rglob(name): obsolete.unlink()
PYCODE
sparkle="$scratch/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
ditto "$sparkle" "$app/Contents/Frameworks/Sparkle.framework"
cp build/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
permission_resources="$app/Contents/Resources/PermissionFlow_PermissionFlow.bundle"
if [[ -d "$permission_resources/Contents/Resources" ]]; then
  permission_resources="$permission_resources/Contents/Resources"
fi
ditto resources/PermissionFlow/nl.lproj "$permission_resources/nl.lproj"
for language in en nl; do
  mkdir -p "$app/Contents/Resources/$language.lproj"
  cp "Sources/MagicHinge/Resources/$language.lproj/InfoPlist.strings" "$app/Contents/Resources/$language.lproj/InfoPlist.strings"
done
python3 scripts/package-metadata.py "$app" "$mode"
identity=-
if [[ "$mode" == distribution ]]; then
  identity="$(python3 -c 'import json; print(json.load(open("release.json"))["signingIdentity"])')"
fi
# Sign inside-out; preserve framework symlinks and use the normal Developer ID requirement.
python3 scripts/sign-bundle.py "$app" "$identity"
python3 scripts/verify-bundle.py "$app" "$mode"
output="${MAGIC_HINGE_APP_OUTPUT:-$PWD/build/Magic Hinge.app}"
python3 - "$app" "$output" <<'PY'
from pathlib import Path
import shutil, sys
source, target = map(Path, sys.argv[1:])
if target.exists():
    # Never delete arbitrary directories passed as an output path.
    assert target.suffix == '.app' and (target/'Contents/Info.plist').is_file()
    shutil.rmtree(target)
target.parent.mkdir(parents=True, exist_ok=True)
shutil.move(str(source), str(target))
PY
print "Built: $output"

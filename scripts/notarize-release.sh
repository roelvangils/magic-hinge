#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
app="${1:-$PWD/build/Magic Hinge.app}"
python3 scripts/verify-bundle.py "$app" distribution
version="$(python3 -c 'import json; print(json.load(open("release.json"))["version"])')"
identity="$(python3 -c 'import json; print(json.load(open("release.json"))["signingIdentity"])')"
mkdir -p build/distribution
archive="$PWD/build/distribution/Magic-Hinge-$version.zip"
dmg="$PWD/build/distribution/Magic-Hinge-$version.dmg"
# Never modify a finalized artifact after producing its update signature/checksum.
[[ ! -e "$dmg" ]] || { print -u2 'DMG already exists. Preserve it and use a new build directory for another candidate.'; exit 1; }
ditto -c -k --keepParent "$app" "$archive"
python3 scripts/notarize.py "$archive"
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
staging="$(mktemp -d "$PWD/build/dmg-stage.XXXXXX")"
ditto "$app" "$staging/Magic Hinge.app"
ln -s /Applications "$staging/Applications"
cp build/AppIcon.icns "$staging/.VolumeIcon.icns"
SetFile -a C "$staging"
hdiutil create -volname 'Magic Hinge' -srcfolder "$staging" -format UDZO -ov "$dmg"
codesign --force --sign "$identity" --timestamp "$dmg"
python3 scripts/notarize.py "$dmg"
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
codesign --verify --strict "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
python3 scripts/release-metadata.py "$dmg"

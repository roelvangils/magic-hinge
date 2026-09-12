#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build/verification
python3 scripts/fetch-apple-models.py
swift package resolve
# Asset tests are mandatory here, while ordinary CI stays independent of Apple downloads.
DUO_APPLE_MODELS="$PWD/build/apple-models" swift test 2>&1 | tee build/verification/tests.log
python3 scripts/check-localization.py
python3 scripts/check-source.py
python3 scripts/check-website.py
scripts/build-app.sh release

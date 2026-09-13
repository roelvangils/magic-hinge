#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
[[ $# == 1 && -d "$1" ]] || { print -u2 'Usage: scripts/upload-sentry-symbols.sh build/symbols/UUID/MagicHinge.dSYM'; exit 2; }
command -v sentry-cli >/dev/null || { print -u2 'Install sentry-cli from Sentry before uploading symbols.'; exit 2; }
# Authentication belongs in local configuration or the environment, never logs.
: "${SENTRY_ORG:=eleven-ways}"
: "${SENTRY_PROJECT:=magic-hinge}"
export SENTRY_ORG SENTRY_PROJECT
sentry-cli debug-files upload --wait "$1"

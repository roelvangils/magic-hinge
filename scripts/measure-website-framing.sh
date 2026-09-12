#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build
swiftc -O scripts/measure-website-framing.swift -o build/measure-website-framing
build/measure-website-framing

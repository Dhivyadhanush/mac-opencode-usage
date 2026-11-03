#!/bin/bash
# Regenerates Resources/AppIcon.icns from Resources/icon.swift. Run after
# changing the artwork; the .icns is committed so build.sh needs no toolchain.
set -euo pipefail
cd "$(dirname "$0")"

rm -rf build/AppIcon.iconset
swift Resources/icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"

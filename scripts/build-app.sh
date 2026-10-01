#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
app="$PWD/.build/Tonk Town.app"
mkdir -p "$app/Contents/MacOS"
cp .build/debug/TonkTown "$app/Contents/MacOS/TonkTown"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "$app"

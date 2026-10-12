#!/bin/bash
# Export the macOS and Windows debug builds from this Mac.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"

mkdir -p "$ROOT/build/macos" "$ROOT/build/windows"
"$GODOT" --headless --path "$ROOT" --export-debug "macOS" "$ROOT/build/macos/Leaf Me Alone.zip"
"$GODOT" --headless --path "$ROOT" --export-debug "Windows Desktop" "$ROOT/build/windows/Leaf Me Alone.exe"
echo "Exported to $ROOT/build"

#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/CodexIsland.app"
# Only stop the exact executable staged by this project.
PID_LIST=$(pgrep -f "^$APP/Contents/MacOS/CodexIsland( |$)" || true)
if [ -n "$PID_LIST" ]; then kill $PID_LIST; fi
swift build --package-path "$ROOT" --product CodexIsland
BIN=$(swift build --package-path "$ROOT" --show-bin-path)
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/CodexIsland" "$APP/Contents/MacOS/CodexIsland"
/usr/bin/python3 -I - "$APP/Contents/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump({'CFBundlePackageType':'APPL','CFBundleExecutable':'CodexIsland','CFBundleIdentifier':'local.codex-island.monitor','CFBundleName':'Codex Island','CFBundleShortVersionString':'0.0.1','CFBundleVersion':'1','LSMinimumSystemVersion':'14.0','NSPrincipalClass':'NSApplication','LSUIElement':True,'NSHighResolutionCapable':True},f)
PY
codesign --force --sign - "$APP"
open -n "$APP"
if [ "${1:-}" = "--verify" ]; then
    sleep 3
    pgrep -fl "^$APP/Contents/MacOS/CodexIsland( |$)"
fi

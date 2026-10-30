#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION=0.0.1
ARCH="$(uname -m)"
OUT="$ROOT/dist/release-$ARCH"
APP="$OUT/CodexIsland.app"
swift build --package-path "$ROOT" -c release --product CodexIsland -Xswiftc -debug-prefix-map -Xswiftc "$ROOT=/src/codexedu"
BIN=$(swift build --package-path "$ROOT" -c release --show-bin-path)
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/CodexIsland" "$APP/Contents/MacOS/CodexIsland"
strip -S "$APP/Contents/MacOS/CodexIsland"
python3 -I - "$APP/Contents/Info.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1],'wb') as f:
 plistlib.dump({'CFBundlePackageType':'APPL','CFBundleExecutable':'CodexIsland','CFBundleIdentifier':'local.codex-island.monitor','CFBundleName':'Codex Island','CFBundleShortVersionString':'0.0.1','CFBundleVersion':'1','LSMinimumSystemVersion':'14.0','NSPrincipalClass':'NSApplication','LSUIElement':True,'NSHighResolutionCapable':True},f)
PY
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
ln -s /Applications "$OUT/Applications" 2>/dev/null || true
hdiutil create -volname "Codex Island $VERSION" -srcfolder "$OUT" -ov -format UDZO "$ROOT/dist/codexedu-$VERSION-macos-$ARCH.dmg"

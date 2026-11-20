#!/usr/bin/env bash
# Builds build/FellowshipDesktop.app (release, ad-hoc signed) from the Swift package.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/FellowshipDesktop.app"
VERSION="$(cat "$ROOT/VERSION")"

cd "$ROOT"
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/FellowshipDesktop"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/sprites"
cp "$BIN" "$APP/Contents/MacOS/FellowshipDesktop"
cp "$ROOT"/Sprites/*.svg "$APP/Contents/Resources/sprites/"
cp "$ROOT/Sprites/LICENSE" "$APP/Contents/Resources/sprites/LICENSE"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Fellowship Desktop</string>
  <key>CFBundleDisplayName</key><string>Fellowship Desktop</string>
  <key>CFBundleIdentifier</key><string>local.fellowship-desktop</string>
  <key>CFBundleExecutable</key><string>FellowshipDesktop</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

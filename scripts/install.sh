#!/usr/bin/env bash
# Builds the app, puts it in ~/Applications and starts it. Touches nothing else.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="$HOME/Applications/FellowshipDesktop.app"

"$ROOT/scripts/build-app.sh"

pkill -x FellowshipDesktop 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$TARGET"
cp -R "$ROOT/build/FellowshipDesktop.app" "$TARGET"
open "$TARGET"

echo "Installed $TARGET"
echo "To let the pet follow Claude Code, run: $ROOT/scripts/install-hooks.sh"

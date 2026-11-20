#!/usr/bin/env bash
# Adds (or with --remove, takes out) the Fellowship Desktop hooks in ~/.claude/settings.json.
# Backs the file up first and leaves every other setting and hook as it was. Safe to run twice.
set -euo pipefail

SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
COMMAND='"$HOME/Applications/FellowshipDesktop.app/Contents/MacOS/FellowshipDesktop" hook'
MODE="${1:-install}"

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
BACKUP="$SETTINGS.fellowship-backup-$(date +%Y%m%d-%H%M%S)"
cp "$SETTINGS" "$BACKUP"

/usr/bin/python3 -I - "$SETTINGS" "$COMMAND" "$MODE" <<'PY'
import json, sys

path, command, mode = sys.argv[1:4]
MARK = "FellowshipDesktop.app/Contents/MacOS/FellowshipDesktop"
EVENTS = {
    "SessionStart": None,
    "UserPromptSubmit": None,
    "PreToolUse": "*",
    "PostToolUse": "*",
    "PermissionRequest": "*",
    "Notification": None,
    "Stop": None,
    "SessionEnd": None,
}

with open(path) as f:
    settings = json.load(f)
hooks = settings.setdefault("hooks", {})

for event in list(hooks):
    groups = []
    for group in hooks[event]:
        kept = [h for h in group.get("hooks", []) if MARK not in h.get("command", "")]
        if kept:
            groups.append({**group, "hooks": kept})
    if groups:
        hooks[event] = groups
    else:
        del hooks[event]

if mode != "--remove":
    for event, matcher in EVENTS.items():
        group = {"hooks": [{"type": "command", "command": command, "timeout": 5}]}
        if matcher is not None:
            group = {"matcher": matcher, **group}
        hooks.setdefault(event, []).append(group)

if not hooks:
    del settings["hooks"]

with open(path, "w") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY

if [ "$MODE" = "--remove" ]; then
  echo "Removed Fellowship Desktop hooks from $SETTINGS (backup: $BACKUP)"
else
  echo "Added Fellowship Desktop hooks to $SETTINGS (backup: $BACKUP)"
  echo "Claude Code picks them up live; sessions started before may need a restart."
fi

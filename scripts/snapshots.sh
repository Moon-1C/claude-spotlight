#!/usr/bin/env bash
# Regenerate UX screenshots via the app's own self-render (cacheDisplay) — no Screen Recording
# permission needed. Writes panel.png, panel-answer.png, settings.png into <outdir>.
#   ./scripts/snapshots.sh [outdir] ["query"]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-docs/screenshots}"
QUERY="${2:-the report I worked on recently}"
swift build
pkill -f '.build/debug/cspot-ui' 2>/dev/null || true
sleep 1
mkdir -p "$OUT"
./.build/debug/cspot-ui --snapshot "$OUT" --ask --demo "$QUERY" >/tmp/cspot-snap.log 2>&1 &
for i in $(seq 1 70); do sleep 1; [ -f "$OUT/settings.png" ] && break; done
pkill -f '.build/debug/cspot-ui' 2>/dev/null || true
echo "wrote: $OUT/{panel,panel-answer,settings}.png"

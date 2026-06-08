#!/usr/bin/env bash
# Report the signing/permission posture of the installed claude-spotlight.app.
set -euo pipefail
APP="${APP:-/Applications/claude-spotlight.app}"
BUNDLE_ID="com.moon1c.claude-spotlight"

[ -d "$APP" ] || { echo "✗ not installed: $APP  (run scripts/make-app.sh)"; exit 1; }

echo "App:        $APP"
codesign -dvv "$APP" 2>&1 | grep -E 'Identifier=|Signature=|TeamIdentifier=' | sed 's/^/  /'

echo "Designated requirement:"
req=$(codesign -d -r- "$APP" 2>&1 | grep designated || true)
echo "  $req"
if echo "$req" | grep -q cdhash; then
  echo "  ⚠ cdhash-based → Accessibility grant resets on every rebuild."
  echo "    Fix: create a self-signed 'claude-spotlight Self-Signed' cert and re-run:"
  echo "      SIGN_IDENTITY='claude-spotlight Self-Signed' ./scripts/make-app.sh"
else
  echo "  ✓ identifier/cert-based → grants persist across rebuilds."
fi

echo "Code-signing identities available:"
security find-identity -v -p codesigning 2>/dev/null | sed 's/^/  /' | head -5

echo "Reset a stale grant with, e.g.:  tccutil reset Accessibility $BUNDLE_ID"

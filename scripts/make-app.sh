#!/usr/bin/env bash
# Build claude-spotlight.app from the SwiftPM release binary — no Xcode.
#   ./scripts/make-app.sh
#       → ad-hoc sign (Automation grants persist by bundle id; Accessibility re-toggles per rebuild)
#   SIGN_IDENTITY='claude-spotlight Self-Signed' ./scripts/make-app.sh
#       → stable self-signed identity (ALL grants, incl. Accessibility, persist across rebuilds)
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="com.moon1c.claude-spotlight"            # NEVER change — every TCC grant keys on this
APP="${APP:-/Applications/claude-spotlight.app}"   # FIXED path — TCC also keys on the on-disk path
EXE="cspot-ui"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"                # '-' = ad-hoc
CONTENTS="$APP/Contents"

echo "→ swift build -c release --product $EXE"
swift build -c release --product "$EXE"
BIN=".build/release/${EXE}"; [ -x "$BIN" ] || { echo "missing $BIN"; exit 1; }

echo "→ assembling $APP"
rm -rf "$APP"; mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
install -m 0755 "$BIN" "$CONTENTS/MacOS/${EXE}"
[ -f dist/AppIcon.icns ] && cp dist/AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>claude-spotlight</string>
  <key>CFBundleDisplayName</key><string>Claude Spotlight</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key><string>${EXE}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleScriptEnabled</key><true/>
  <!-- Automation (osascript/System Events context reads + write actions). REQUIRED. -->
  <key>NSAppleEventsUsageDescription</key>
  <string>claude-spotlight reads the app you're in and performs actions you confirm.</string>
  <!-- EventKit macOS 14+: the legacy NSCalendarsUsageDescription is ignored by the full-access API. -->
  <key>NSCalendarsFullAccessUsageDescription</key>
  <string>claude-spotlight surfaces and (on confirm) adds your calendar events.</string>
  <key>NSRemindersFullAccessUsageDescription</key>
  <string>claude-spotlight adds reminders you confirm.</string>
  <!-- Accessibility & Full Disk Access have NO usage string — they are pure System Settings toggles. -->
</dict></plist>
PLIST

plutil -lint "$CONTENTS/Info.plist"

echo "→ signing ($SIGN_IDENTITY)"
codesign --force --options runtime --identifier "$BUNDLE_ID" -s "$SIGN_IDENTITY" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "→ designated requirement (cdhash = re-grant Accessibility per build; identifier = stable):"
codesign -d -r- "$APP" 2>&1 | grep designated || true
echo "✓ $APP"

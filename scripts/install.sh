#!/bin/bash
# Whisky Claude — end-to-end installer.
# 1. Build Release
# 2. Codesign with stable self-signed identity if present (else ad-hoc fallback)
# 3. Copy to /Applications/Whisky Claude.app
# 4. Install pet-event helper + Claude Code hooks
# 5. Register as a Login Item
# Idempotent — safe to re-run.

INSTALLER_VERSION="1.2.1"

set -euo pipefail
cd "$(dirname "$0")/.."

echo "Whisky Claude installer v${INSTALLER_VERSION}"

PROJECT="WhiskyClaude.xcodeproj"
SCHEME="WhiskyClaude"
TARGET_NAME="Whisky Claude"          # display name with space
SOURCE_APP="build/Build/Products/Release/WhiskyClaude.app"
RENAMED_APP="build/Build/Products/Release/${TARGET_NAME}.app"
INSTALL_PATH="/Applications/${TARGET_NAME}.app"

echo "→ generating Release build"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
    -derivedDataPath build \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
    clean build | tail -5

if [ ! -d "$SOURCE_APP" ]; then
    echo "✗ build output missing at $SOURCE_APP" >&2
    exit 1
fi

# Rename the product on disk so /Applications/Whisky Claude.app matches the
# display name. We work on a copy so we don't disturb the build output Xcode
# might re-touch on the next incremental build.
rm -rf "$RENAMED_APP"
cp -R "$SOURCE_APP" "$RENAMED_APP"

echo "→ codesign"
# Use stable self-signed identity if present so the binary's designated
# requirement (and therefore TCC grants like Accessibility) survive reinstalls.
# Falls back to ad-hoc if the cert was removed from the keychain.
SIGN_ID="Ahmad Sharaf Code Signing"
if security find-certificate -c "$SIGN_ID" ~/Library/Keychains/login.keychain-db >/dev/null 2>&1; then
    codesign --force --deep --sign "$SIGN_ID" "$RENAMED_APP"
else
    echo "  (cert '$SIGN_ID' not found — falling back to ad-hoc; TCC grants will reset)"
    codesign --force --deep --sign - "$RENAMED_APP"
fi

echo "→ installing to /Applications"
# Quit the running instance, if any.
osascript -e "tell application \"${TARGET_NAME}\" to quit" 2>/dev/null || true
osascript -e "tell application \"WhiskyClaude\" to quit" 2>/dev/null || true
sleep 0.5

# If the previously-installed binary was signed with a DIFFERENT identity
# (e.g. ad-hoc → stable cert, or rotating certs), stale TCC grants keyed to
# the old designated requirement will silently fail at runtime — the WORST
# case is SFSpeechRecognizer infinite-looping on permission denial, which
# starves the SoundPlayer + file-watcher off the main queue and the user
# perceives the app as "broken" with no error. So: compare DRs, reset only
# when they differ, otherwise let grants persist (the whole point of the
# stable cert).
NEW_DR=$(codesign -d -r- "$RENAMED_APP" 2>&1 | sed -n 's/^designated => //p')
OLD_DR=""
if [ -d "$INSTALL_PATH" ]; then
    OLD_DR=$(codesign -d -r- "$INSTALL_PATH" 2>&1 | sed -n 's/^designated => //p')
fi
if [ -n "$OLD_DR" ] && [ "$OLD_DR" != "$NEW_DR" ]; then
    echo "→ signing identity changed — resetting TCC grants so they re-bind"
    BUNDLE_ID=$(plutil -extract CFBundleIdentifier raw "$RENAMED_APP/Contents/Info.plist" 2>/dev/null || echo "com.ahmadsharaf.WhiskyClaude")
    for service in Accessibility AppleEvents Microphone SpeechRecognition ScreenCapture InputMonitoring AudioCapture; do
        tccutil reset "$service" "$BUNDLE_ID" >/dev/null 2>&1 || true
    done
    echo "  (you'll be prompted once for each permission on first launch — grants will persist after that)"
fi

rm -rf "$INSTALL_PATH"
cp -R "$RENAMED_APP" "$INSTALL_PATH"

# Clean up build artifacts so they don't appear in Spotlight as duplicate
# copies of the app. The /Applications copy is the only one users should see.
rm -rf "$SOURCE_APP" "$RENAMED_APP"

echo "→ installing pet-event helper"
mkdir -p ~/.claude/scripts
HELPER_DEST="$HOME/.claude/scripts/wc-event.sh"
FOUNDATION_SRC="$HOME/Desktop/projects/force-ai-foundation/ops/wc-event.sh"
# force-ai-foundation (ops/install.sh) canonically owns this helper when it's
# present on the machine — its copy logs safe metadata only, rotates at ~1MB,
# and carries a "# claude-hook:" header that foundation's own
# dead-gate-detect.sh depends on. Whichever installer ran LAST used to win
# silently here; that already caused one regression (an older foundation copy
# overwrote a fixed one and grew to 240MB of full tool payloads). Detect
# ownership by CONTENT (the header, which survives even if foundation isn't
# checked out on this machine) OR by the foundation repo's own path (covers a
# foundation checkout whose installer hasn't run yet) — either signal means
# foundation owns it, so we skip and leave it alone. Only a standalone install
# (no foundation anywhere in the picture) gets the bundled copy below.
if { [ -f "$HELPER_DEST" ] && grep -q '^# claude-hook:' "$HELPER_DEST" 2>/dev/null; } || [ -f "$FOUNDATION_SRC" ]; then
    echo "  force-ai-foundation owns wc-event.sh — leaving $HELPER_DEST untouched"
else
    cp scripts/dot-claude/wc-event.sh "$HELPER_DEST"
    chmod +x "$HELPER_DEST"
fi

echo "→ wiring Claude Code hooks"
scripts/install-hooks.sh

echo "→ launching"
open "$INSTALL_PATH"

echo "→ registering Login Item"
osascript <<EOF
tell application "System Events"
    if not (exists login item "${TARGET_NAME}") then
        make login item at end with properties {path:"${INSTALL_PATH}", hidden:false}
    end if
end tell
EOF

cat <<EOF

✓ Installed.
  App:        ${INSTALL_PATH}
  Helper:     ${HOME}/.claude/scripts/wc-event.sh
  Hooks:      ${HOME}/.claude/settings.json (Stop/Notification/PreToolUse/UserPromptSubmit)
  Login Item: registered, will auto-launch each login

Uninstall:    ./scripts/uninstall.sh
EOF

#!/bin/bash
# One-line installer for Mac:
#   curl -fsSL https://raw.githubusercontent.com/Senekw/focus-lock/main/get.sh | bash
set -e
DEST="${FOCUSLOCK_DEST:-/Applications}"
TMP="$(mktemp -d)"
echo "Downloading Focus Lock..."
curl -fsSL -o "$TMP/FocusLock-Mac.zip" https://github.com/Senekw/focus-lock/releases/latest/download/FocusLock-Mac.zip
ditto -x -k "$TMP/FocusLock-Mac.zip" "$TMP"
rm -rf "$DEST/Focus Lock.app"
cp -R "$TMP/Focus Lock.app" "$DEST/"
xattr -dr com.apple.quarantine "$DEST/Focus Lock.app" 2>/dev/null || true
rm -rf "$TMP"
echo "Installed to $DEST/Focus Lock.app"
if [ -z "$FOCUSLOCK_NO_OPEN" ]; then
  open "$DEST/Focus Lock.app"
  echo "Focus Lock is open. Click \"Finish setup\" and type your Mac password."
fi

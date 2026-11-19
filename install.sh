#!/bin/bash
# Installs the Focus Lock root daemon + user agent. Must run as root.
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"            # .../Focus Lock.app/Contents/Resources
APP="$(cd "$SRC/../.." && pwd)"
D="/Library/Application Support/FocusLock"
DL=com.focuslock.daemon; AL=com.focuslock.agent
BIN="$D/Focus Lock.app/Contents/MacOS/FocusLock"
mkdir -p "$D"
rm -rf "$D/Focus Lock.app"
cp -R "$APP" "$D/Focus Lock.app"
cp "$SRC/blocklist.txt" "$SRC/blocked.html" "$D/"
chown -R root:wheel "$D"; chmod -R go-w "$D"; chmod -R a+rX "$D"
mkdir -p /Users/Shared/FocusLock; chmod 777 /Users/Shared/FocusLock
plist() { cat > "$1" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$2</string>
<key>ProgramArguments</key><array><string>$BIN</string><string>$3</string></array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
</dict></plist>
P
chown root:wheel "$1"; chmod 644 "$1"; }
plist /Library/LaunchDaemons/$DL.plist $DL --daemon
plist /Library/LaunchAgents/$AL.plist $AL --agent
U=$(stat -f %u /dev/console)
# remove pre-rename services if present
launchctl bootout system/com.seangplee.focuslock.daemon 2>/dev/null || true
launchctl bootout gui/$U/com.seangplee.focuslock.agent 2>/dev/null || true
rm -f /Library/LaunchDaemons/com.seangplee.focuslock.daemon.plist /Library/LaunchAgents/com.seangplee.focuslock.agent.plist
launchctl bootout system/$DL 2>/dev/null || true
launchctl bootstrap system /Library/LaunchDaemons/$DL.plist
launchctl bootout gui/$U/$AL 2>/dev/null || true
echo installed

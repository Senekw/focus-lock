#!/bin/bash
# Removes Focus Lock completely. Run: sudo bash uninstall.sh
launchctl bootout system/com.focuslock.daemon 2>/dev/null
launchctl bootout gui/$(stat -f %u /dev/console)/com.focuslock.agent 2>/dev/null
launchctl bootout system/com.seangplee.focuslock.daemon 2>/dev/null
launchctl bootout gui/$(stat -f %u /dev/console)/com.seangplee.focuslock.agent 2>/dev/null
rm -f /Library/LaunchDaemons/com.seangplee.focuslock.daemon.plist /Library/LaunchAgents/com.seangplee.focuslock.agent.plist
rm -f /Library/LaunchDaemons/com.focuslock.daemon.plist /Library/LaunchAgents/com.focuslock.agent.plist
rm -rf "/Library/Application Support/FocusLock" /Users/Shared/FocusLock
sed -i '' '/^# >>> FocusLock/,/^# <<< FocusLock/d' /etc/hosts
dscacheutil -flushcache; killall -HUP mDNSResponder
echo removed

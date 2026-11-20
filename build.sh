#!/bin/bash
set -e
cd "$(dirname "$0")"
VERSION="${FL_VERSION:-$(cat VERSION)}"
A="build/Focus Lock.app"; rm -rf build; mkdir -p "$A/Contents/MacOS" "$A/Contents/Resources" build/icon.iconset
for arch in arm64 x86_64; do
  swiftc -O -parse-as-library -target $arch-apple-macos13.0 main.swift -o build/FocusLock-$arch
done
lipo -create build/FocusLock-arm64 build/FocusLock-x86_64 -output "$A/Contents/MacOS/FocusLock"
swiftc icon.swift -o build/mkicon && build/mkicon build/icon.iconset && iconutil -c icns build/icon.iconset -o "$A/Contents/Resources/AppIcon.icns"
LIST=blocklist.txt; [ -f blocklist.local.txt ] && [ -z "$RELEASE" ] && LIST=blocklist.local.txt
cp install.sh blocked.html "$A/Contents/Resources/"; cp "$LIST" "$A/Contents/Resources/blocklist.txt"
cat > "$A/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Focus Lock</string>
<key>CFBundleDisplayName</key><string>Focus Lock</string>
<key>CFBundleIdentifier</key><string>com.focuslock.app</string>
<key>CFBundleExecutable</key><string>FocusLock</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppleEventsUsageDescription</key><string>Focus Lock closes blocked sites in your browser while you are locked in.</string>
</dict></plist>
P
codesign --force -s - "$A"
if [ -n "$RELEASE" ]; then
  (cd build && ditto -c -k --keepParent "Focus Lock.app" FocusLock-Mac.zip)
  mkdir -p build/FocusLock-Windows && cp windows/*.ps1 windows/*.cmd blocklist.txt build/FocusLock-Windows/ && rm -f build/FocusLock-Windows/get.ps1 && printf '%s' "$VERSION" > build/FocusLock-Windows/version.txt
  (cd build && zip -qr FocusLock-Windows.zip FocusLock-Windows)
fi
echo "built: $A v$VERSION (blocklist: $LIST)"

#!/bin/bash
# Builds PriceBar.app from the Swift package, and puts it in build/.
#
# A menu bar app needs an app bundle with an Info.plist: without one, macOS
# has no bundle identifier to attach a notification to, and no LSUIElement to
# keep the app out of the Dock.

set -euo pipefail
cd "$(dirname "$0")"

# Use Xcode's toolchain when it is installed, so that the build is the same
# one Xcode runs. Command Line Tools alone cannot compile #Preview macros.
if [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

APP_NAME="PriceBar"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
CONFIG="${1:-release}"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"

BINARY="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"

echo "==> Packaging $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>dev.pricebar.app</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <!-- Lives in the menu bar: no Dock icon, no app switcher entry. -->
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>PriceBar</string>
</dict>
</plist>
PLIST

# An ad-hoc signature is enough for the app to run, and for macOS to let it
# post notifications.
echo "==> Signing (ad hoc)"
codesign --force --deep --sign - "$APP"

echo "==> Done: $APP"
echo "    open $APP"

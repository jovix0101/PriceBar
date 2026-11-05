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

# The version written into the bundle. A release build passes its tag in, so
# that the About box and the release agree; a build from a working copy gets
# the same default every time.
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

# A release build is made for both kinds of Mac, so that one download runs on
# an Intel one too. A working copy is built for this Mac alone: twice the wait
# for a binary only this Mac will run.
ARCH_FLAGS=""
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    ARCH_FLAGS="--arch arm64 --arch x86_64"
fi

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG" $ARCH_FLAGS

BINARY="$(swift build -c "$CONFIG" $ARCH_FLAGS --show-bin-path)/$APP_NAME"

echo "==> Packaging $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"
# Drawn by Icon/make-icon.swift; run it again after changing the drawing.
cp Icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
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

# A disk image, for handing the app to someone: it opens as a window with the
# app in it, beside a shortcut to Applications, which is what a download of a
# menu bar tool should be. Built here rather than only in CI so that a working
# copy can be tried the way a download will be.
echo "==> Making a disk image"
DMG="$BUILD_DIR/$APP_NAME.dmg"
STAGE="$BUILD_DIR/dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

echo "==> Done: $APP"
echo "    open $APP"
echo "    open $DMG"

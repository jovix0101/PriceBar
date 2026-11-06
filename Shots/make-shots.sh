#!/bin/bash
# Draws the four settings pages into docs/ as the screenshots the product
# page shows.
#
# The pages belong to the app, so this builds them: a throwaway Swift package
# in a temp directory reaches the app's sources by symlink, carries the
# renderer as its own main.swift, and is packed into a .app before it runs —
# the page about launching at login only says the right thing from inside a
# bundle.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

# Same toolchain the app is built with, so the pages match what ships.
if [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/Sources/App"
ln -s "$ROOT/Sources/PriceBarCore" "$WORK/Sources/PriceBarCore"
for file in "$ROOT"/Sources/PriceBar/*.swift; do
    case "$(basename "$file")" in
        # The app's own entry point; the renderer takes its place.
        main.swift) continue ;;
    esac
    ln -s "$file" "$WORK/Sources/App/$(basename "$file")"
done
cp "$ROOT/Shots/make-shots.swift" "$WORK/Sources/App/main.swift"

cat > "$WORK/Package.swift" <<'EOF'
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Shots",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PriceBarCore", path: "Sources/PriceBarCore"),
        .executableTarget(name: "App", dependencies: ["PriceBarCore"], path: "Sources/App"),
    ]
)
EOF

swift build --package-path "$WORK" -c release 2>&1 | tail -1

APP="$WORK/Shots.app"
mkdir -p "$APP/Contents/MacOS"
cp "$WORK/.build/release/App" "$APP/Contents/MacOS/Shots"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Shots</string>
    <key>CFBundleIdentifier</key><string>dev.pricebar.shots</string>
    <key>CFBundleName</key><string>Shots</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict>
</plist>
EOF

echo "==> Drawing the settings pages"
"$APP/Contents/MacOS/Shots" "$ROOT/docs"
echo "==> Done: docs/settings-general.png, docs/settings-menubar.png, docs/settings-panel.png, docs/settings-source.png"

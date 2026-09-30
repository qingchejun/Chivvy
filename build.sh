#!/bin/bash
set -e

cd "$(dirname "$0")"

ARCH="${1:-arm64}"
SOURCES=$(find Sources/Tick -name "*.swift")
SDK=$(xcrun --show-sdk-path)

if [ "$ARCH" = "universal" ]; then
    echo "Building Tick (Universal)..."

    swiftc $SOURCES -o Tick_arm64 -sdk "$SDK" \
        -target arm64-apple-macosx13.0 \
        -framework SwiftUI -framework AppKit -framework UserNotifications -framework Speech -framework AVFoundation -framework Carbon -O

    swiftc $SOURCES -o Tick_x86_64 -sdk "$SDK" \
        -target x86_64-apple-macosx13.0 \
        -framework SwiftUI -framework AppKit -framework UserNotifications -framework Speech -framework AVFoundation -framework Carbon -O

    lipo -create Tick_arm64 Tick_x86_64 -output Tick_binary
    rm -f Tick_arm64 Tick_x86_64
else
    echo "Building Tick ($ARCH)..."

    swiftc $SOURCES -o Tick_binary -sdk "$SDK" \
        -target "${ARCH}-apple-macosx13.0" \
        -framework SwiftUI -framework AppKit -framework UserNotifications -framework Speech -framework AVFoundation -framework Carbon -O
fi

APP="/Applications/Tick.app"
APP_DIR="$APP/Contents/MacOS"
RES_DIR="$APP/Contents/Resources"
mkdir -p "$APP_DIR" "$RES_DIR"

cp Tick_binary "$APP_DIR/Tick"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [ -f AppIcon.icns ]; then
    cp AppIcon.icns "$RES_DIR/AppIcon.icns"
fi

rm -f Tick_binary

echo "Build complete: $APP"
echo "Run: open /Applications/Tick.app"

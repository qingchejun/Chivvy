#!/bin/bash
set -e

cd "$(dirname "$0")"

ARCH="${1:-arm64}"
SOURCES=$(find Sources/Chivvy -name "*.swift")
SDK=$(xcrun --show-sdk-path)

if [ "$ARCH" = "universal" ]; then
    echo "Building Chivvy (Universal)..."

    swiftc $SOURCES -o Chivvy_arm64 -sdk "$SDK" \
        -target arm64-apple-macosx13.0 \
        -framework SwiftUI -framework AppKit -framework UserNotifications -framework Speech -framework AVFoundation -framework Carbon -O

    swiftc $SOURCES -o Chivvy_x86_64 -sdk "$SDK" \
        -target x86_64-apple-macosx13.0 \
        -framework SwiftUI -framework AppKit -framework UserNotifications -framework Speech -framework AVFoundation -framework Carbon -O

    lipo -create Chivvy_arm64 Chivvy_x86_64 -output Chivvy_binary
    rm -f Chivvy_arm64 Chivvy_x86_64
else
    echo "Building Chivvy ($ARCH)..."

    swiftc $SOURCES -o Chivvy_binary -sdk "$SDK" \
        -target "${ARCH}-apple-macosx13.0" \
        -framework SwiftUI -framework AppKit -framework UserNotifications -framework Speech -framework AVFoundation -framework Carbon -O
fi

APP="/Applications/Chivvy.app"
APP_DIR="$APP/Contents/MacOS"
RES_DIR="$APP/Contents/Resources"
mkdir -p "$APP_DIR" "$RES_DIR"

cp Chivvy_binary "$APP_DIR/Chivvy"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [ -f AppIcon.icns ]; then
    cp AppIcon.icns "$RES_DIR/AppIcon.icns"
fi

rm -f Chivvy_binary

# Sign with the bundle identifier (the linker's ad-hoc signature would use "Chivvy_binary")
codesign --force -s - --identifier com.qingche.Tick "$APP"

echo "Build complete: $APP"
echo "Run: open /Applications/Chivvy.app"

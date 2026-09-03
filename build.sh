#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="ClaudeBar"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "==> Cleaning old build..."
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
SOURCES=(
    "$PROJECT_DIR/Sources/Models.swift"
    "$PROJECT_DIR/Sources/TokenStatsScanner.swift"
    "$PROJECT_DIR/Sources/UsageCacheStore.swift"
    "$PROJECT_DIR/Sources/ClaudeUsageService.swift"
    "$PROJECT_DIR/Sources/SettingsManager.swift"
    "$PROJECT_DIR/Sources/PopoverView.swift"
    "$PROJECT_DIR/Sources/NotchIsland.swift"
    "$PROJECT_DIR/Sources/AppDelegate.swift"
    "$PROJECT_DIR/Sources/main.swift"
)

BUILD_UNIVERSAL=false
DO_INSTALL=false

for arg in "$@"; do
    case "$arg" in
        --universal)
            BUILD_UNIVERSAL=true
            ;;
        --install|-i)
            DO_INSTALL=true
            ;;
    esac
done

if [ "$BUILD_UNIVERSAL" = true ]; then
    echo "==> Compiling Universal 2 Binary (arm64 + x86_64, macOS 12.0+)..."
    mkdir -p "$BUILD_DIR/arm64" "$BUILD_DIR/x86_64"
    swiftc -O -target arm64-apple-macos12.0 -parse-as-library "${SOURCES[@]}" -o "$BUILD_DIR/arm64/$APP_NAME"
    swiftc -O -target x86_64-apple-macos12.0 -parse-as-library "${SOURCES[@]}" -o "$BUILD_DIR/x86_64/$APP_NAME"
    lipo -create -output "$MACOS_DIR/$APP_NAME" "$BUILD_DIR/arm64/$APP_NAME" "$BUILD_DIR/x86_64/$APP_NAME"
    rm -rf "$BUILD_DIR/arm64" "$BUILD_DIR/x86_64"
else
    ARCH="$(uname -m)"
    TARGET="${ARCH}-apple-macos12.0"
    echo "==> Compiling Swift sources (target: $TARGET)..."
    swiftc -O \
        -target "$TARGET" \
        -parse-as-library \
        "${SOURCES[@]}" \
        -o "$MACOS_DIR/$APP_NAME"
fi

chmod +x "$MACOS_DIR/$APP_NAME"

echo "==> Copying resources & plist..."
cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
GIT_COMMIT="$(git -C "$PROJECT_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
if ! git -C "$PROJECT_DIR" diff --quiet -- 2>/dev/null; then
    GIT_COMMIT="${GIT_COMMIT}-dirty"
fi
/usr/libexec/PlistBuddy -c "Set :ClaudeBarGitCommit $GIT_COMMIT" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Resources/"* "$RESOURCES_DIR/" 2>/dev/null || true

echo "==> Ad-hoc signing app bundle..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true

echo "==> Build succeeded: $APP_BUNDLE"

# Install to ~/Applications or /Applications if argument provided
if [ "$DO_INSTALL" = true ]; then
    TARGET_DIR="/Applications"
    if [ ! -w "$TARGET_DIR" ]; then
        TARGET_DIR="$HOME/Applications"
        mkdir -p "$TARGET_DIR"
    fi
    echo "==> Installing to $TARGET_DIR/$APP_NAME.app..."
    # Kill running instance if exists
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 0.5
    rm -rf "$TARGET_DIR/$APP_NAME.app"
    cp -R "$APP_BUNDLE" "$TARGET_DIR/"
    touch "$TARGET_DIR/$APP_NAME.app"
    
    # Register with LaunchServices to ensure Finder/Launchpad displays the new icon immediately
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$TARGET_DIR/$APP_NAME.app" 2>/dev/null || true
    
    echo "==> Installation complete: $TARGET_DIR/$APP_NAME.app"
fi

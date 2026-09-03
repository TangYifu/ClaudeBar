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

echo "==> Compiling Swift sources..."
SOURCES=(
    "$PROJECT_DIR/Sources/Models.swift"
    "$PROJECT_DIR/Sources/ClaudeUsageService.swift"
    "$PROJECT_DIR/Sources/SettingsManager.swift"
    "$PROJECT_DIR/Sources/PopoverView.swift"
    "$PROJECT_DIR/Sources/AppDelegate.swift"
    "$PROJECT_DIR/Sources/main.swift"
)

swiftc -O \
    -parse-as-library \
    "${SOURCES[@]}" \
    -o "$MACOS_DIR/$APP_NAME"

chmod +x "$MACOS_DIR/$APP_NAME"

echo "==> Copying resources & plist..."
cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Resources/"* "$RESOURCES_DIR/" 2>/dev/null || true

echo "==> Ad-hoc signing app bundle..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true

echo "==> Build succeeded: $APP_BUNDLE"

# Install to ~/Applications or /Applications if argument provided
if [ "$1" == "--install" ] || [ "$1" == "-i" ]; then
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

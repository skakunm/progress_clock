#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="ProgressClock"
BUILD="$DIR/build/$APP.app"
DEST="/Applications/$APP.app"

if [ ! -d "$BUILD" ]; then
    echo "Error: $BUILD not found. Run ./build.sh first."
    exit 1
fi

# Show what's currently installed
if [ -d "$DEST" ]; then
    CURRENT_VER=$(defaults read "$DEST/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "unknown")
    NEW_VER=$(defaults read "$BUILD/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "unknown")
    echo "Replacing $APP $CURRENT_VER → $NEW_VER in /Applications"
    read -r -p "Continue? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }
fi

# Kill any running instance
pkill -x "$APP" 2>/dev/null || true

echo "Installing to /Applications..."
cp -r "$BUILD" "/Applications/"

echo ""
echo "Launching..."
open "$DEST"
echo ""
echo "Done. To start at login: System Settings → General → Login Items → add $DEST"

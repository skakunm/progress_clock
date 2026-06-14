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

# Kill any running instance
pkill -x "$APP" 2>/dev/null || true

echo "Installing to /Applications..."
cp -r "$BUILD" "/Applications/"

echo ""
echo "Done. Launch with:"
echo "  open \"$DEST\""
echo ""
echo "To start at login: System Settings › General › Login Items › add $DEST"

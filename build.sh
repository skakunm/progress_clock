#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="ProgressClock"
BUILD="$DIR/build/$APP.app/Contents"

echo "Cleaning..."
rm -rf "$DIR/build/$APP.app"

echo "Creating bundle structure..."
mkdir -p "$BUILD/MacOS"
mkdir -p "$BUILD/Resources"

echo "Compiling Swift..."
swiftc \
  -swift-version 5 \
  -framework AppKit \
  -framework Foundation \
  -O \
  -o "$BUILD/MacOS/$APP" \
  "$DIR/src/main.swift"

echo "Copying Info.plist..."
cp "$DIR/Info.plist" "$BUILD/Info.plist"

echo ""
echo "Build complete: build/$APP.app"
echo "Run with:  open build/$APP.app"

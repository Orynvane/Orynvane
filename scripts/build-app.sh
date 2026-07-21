#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP_DIR="$PROJECT_DIR/dist/Orynvane.app"
CONTENTS_DIR="$APP_DIR/Contents"
BUILD_CONFIGURATION=${CONFIGURATION:-release}

cd "$PROJECT_DIR"
swift build -c "$BUILD_CONFIGURATION" --product Orynvane
BIN_DIR=$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)

mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$PROJECT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$BIN_DIR/Orynvane" "$CONTENTS_DIR/MacOS/Orynvane"
chmod 755 "$CONTENTS_DIR/MacOS/Orynvane"
codesign --force --sign - --timestamp=none "$APP_DIR"

echo "$APP_DIR"

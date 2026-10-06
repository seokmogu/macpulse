#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
VERSION=${VERSION:-1.0.0}
DEST=${OUTPUT_DIR:-"$ROOT/dist"}
APP="$DEST/MacPulse.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ "${1:-}" == "--universal" ]]; then
  swift build --build-system native -c release --triple arm64-apple-macosx14.0
  swift build --build-system native -c release --triple x86_64-apple-macosx14.0
  ARM_BIN=$(swift build --build-system native -c release --triple arm64-apple-macosx14.0 --show-bin-path)
  INTEL_BIN=$(swift build --build-system native -c release --triple x86_64-apple-macosx14.0 --show-bin-path)
  lipo -create "$ARM_BIN/MacPulse" "$INTEL_BIN/MacPulse" -output "$APP/Contents/MacOS/MacPulse"
else
  swift build --build-system native -c release
  BIN_DIR=$(swift build --build-system native -c release --show-bin-path)
  cp "$BIN_DIR/MacPulse" "$APP/Contents/MacOS/MacPulse"
fi
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MacPulse</string>
<key>CFBundleIdentifier</key><string>com.seokmogu.macpulse</string>
<key>CFBundleName</key><string>MacPulse</string>
<key>CFBundleDisplayName</key><string>MacPulse</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 MacPulse contributors</string>
</dict></plist>
PLIST
swift scripts/generate-icon.swift "$DEST/AppIcon.iconset"
iconutil -c icns "$DEST/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built $APP"

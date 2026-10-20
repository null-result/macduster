#!/bin/zsh
# Compila con swiftc y empaqueta build/MacDuster.app (no requiere Xcode ni SwiftPM).
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build
APP=$OUT/MacDuster.app
rm -rf "$OUT" && mkdir -p "$OUT" "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -wmo -parse-as-library -module-name MacDusterCore \
  -emit-module -emit-module-path "$OUT/MacDusterCore.swiftmodule" -c Sources/MacDusterCore/*.swift -o "$OUT/MacDusterCore.o"
swiftc -O -parse-as-library -I "$OUT" "$OUT/MacDusterCore.o" Sources/MacDuster/*.swift -o "$APP/Contents/MacOS/MacDuster"

cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>MacDuster</string>
  <key>CFBundleIdentifier</key><string>dev.local.macduster</string>
  <key>CFBundleExecutable</key><string>MacDuster</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>MacDuster necesita controlar System Events para gestionar los elementos de inicio de sesión.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null
echo "OK: $APP"

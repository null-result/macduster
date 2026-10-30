#!/bin/zsh
# Compila con swiftc y empaqueta build/MacDuster.app (no requiere Xcode ni SwiftPM).
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build
APP=$OUT/MacDuster.app
rm -rf "$OUT" && mkdir -p "$OUT" "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Binario universal (Intel + Apple Silicon): se compila cada arquitectura y se unen con lipo.
for ARCH in x86_64 arm64; do
  swiftc -O -wmo -parse-as-library -target "$ARCH-apple-macos12.0" -module-name MacDusterCore \
    -emit-module -emit-module-path "$OUT/MacDusterCore-$ARCH.swiftmodule" -c Sources/MacDusterCore/**/*.swift -o "$OUT/MacDusterCore-$ARCH.o"
  cp "$OUT/MacDusterCore-$ARCH.swiftmodule" "$OUT/MacDusterCore.swiftmodule"
  swiftc -O -parse-as-library -target "$ARCH-apple-macos12.0" -I "$OUT" "$OUT/MacDusterCore-$ARCH.o" Sources/MacDuster/*.swift -o "$OUT/MacDuster-$ARCH"
done
lipo -create "$OUT/MacDuster-x86_64" "$OUT/MacDuster-arm64" -output "$APP/Contents/MacOS/MacDuster"
rm -f "$OUT"/MacDuster-x86_64 "$OUT"/MacDuster-arm64 "$OUT"/MacDusterCore-*

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
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>MacDuster necesita controlar System Events para gestionar los elementos de inicio de sesión.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null
echo "OK: $APP"

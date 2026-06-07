#!/bin/bash
# StatusAppBar'ı release modda derleyip çalıştırılabilir bir .app paketine koyar.
set -euo pipefail

cd "$(dirname "$0")"

echo "▸ Release derleniyor..."
swift build -c release

APP="StatusAppBar.app"
BIN=".build/release/StatusAppBar"

echo "▸ .app paketi hazırlanıyor..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/StatusAppBar"
cp Info.plist "$APP/Contents/Info.plist"

# Ad-hoc imza (Gatekeeper/IOKit erişimi için yerel çalıştırmada yeterli).
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "✓ Hazır: $APP"
echo "  Çalıştır:  open $APP"

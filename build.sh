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

# İkon (varsa) — Notification Center ikonsuz bundle'ları sevmiyor.
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/"
fi

# İmza. Keychain'de bir Apple Development kimliği varsa onu kullan
# (kararlı Team ID, her derlemede değişmeyen cdhash); yoksa ad-hoc'a düş.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"')
if [ -n "$IDENTITY" ]; then
  echo "▸ İmzalanıyor: $IDENTITY"
  codesign --force --sign "$IDENTITY" "$APP" 2>/dev/null || \
    codesign --force --sign - "$APP" 2>/dev/null || true
else
  codesign --force --sign - "$APP" 2>/dev/null || true
fi

echo "✓ Hazır: $APP"
echo "  Çalıştır:  open $APP"

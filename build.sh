#!/bin/bash
# Build notecu.app hanya dengan Command Line Tools (tanpa membuka Xcode).
# Pakai:  ./build.sh          -> build saja
#         ./build.sh run      -> build lalu jalankan dari folder build
#         ./build.sh install  -> build, pasang ke /Applications, lalu jalankan
set -euo pipefail
cd "$(dirname "$0")"

APP="build/notecu.app"
ARCH="$(uname -m)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

echo "→ Compile ($ARCH)…"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

xcrun swiftc \
  -O \
  -parse-as-library \
  -swift-version 5 \
  -sdk "$SDK" \
  -target "$ARCH-apple-macos14.0" \
  -o "$APP/Contents/MacOS/notecu" \
  Sources/*.swift

cp Info.plist "$APP/Contents/Info.plist"

# Terjemahan (Resources/en.lproj, id.lproj, …)
for lproj in Resources/*.lproj; do
  if [[ -d "$lproj" ]]; then cp -R "$lproj" "$APP/Contents/Resources/"; fi
done

# Ikon: Resources/AppIcon.png (1024px) -> AppIcon.icns dengan alat bawaan macOS.
if [[ -f Resources/AppIcon.png ]]; then
  echo "→ Ikon…"
  ICONSET="build/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
fi

echo "→ Codesign (ad-hoc)…"
codesign --force --sign - "$APP"

echo "✓ Selesai: $(pwd)/$APP"

case "${1:-}" in
  run)
    pkill -x notecu 2>/dev/null || true
    open "$APP"
    ;;
  install)
    pkill -x notecu 2>/dev/null || true
    sleep 0.5
    rm -rf /Applications/notecu.app
    cp -R "$APP" /Applications/
    echo "✓ Terpasang di /Applications/notecu.app"
    open /Applications/notecu.app
    ;;
esac

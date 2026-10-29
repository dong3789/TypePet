#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"

sign_app() {
  local target="$1"
  local ident
  ident="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' | head -1)"
  if [[ -n "$ident" ]]; then
    codesign --force --sign "$ident" --timestamp=none "$target"
  else
    codesign --force --sign - "$target"
  fi
}
swift "$ROOT/generate.swift" "$ROOT/Resources"

ICONDIR="$ROOT/build/AppIcon.iconset"
rm -rf "$ICONDIR"
mkdir -p "$ICONDIR" "$ROOT/build"
SRC="$ROOT/Resources/icon-source.png"
sips -z 16 16 "$SRC" --out "$ICONDIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$SRC" --out "$ICONDIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$SRC" --out "$ICONDIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$SRC" --out "$ICONDIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$SRC" --out "$ICONDIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$SRC" --out "$ICONDIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$SRC" --out "$ICONDIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$SRC" --out "$ICONDIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$SRC" --out "$ICONDIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$SRC" --out "$ICONDIR/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONDIR" -o "$ROOT/Resources/AppIcon.icns"

SDK="$(xcrun --sdk macosx --show-sdk-path)"
xcrun --sdk macosx swiftc -O -target arm64-apple-macos13.0 -sdk "$SDK" -parse-as-library \
  -framework AppKit -framework CoreGraphics -framework QuartzCore \
  -framework ServiceManagement -framework ImageIO \
  -o "$ROOT/build/TypePet-bin" \
  "$ROOT/src/TypePet.swift" "$ROOT/src/Editor.swift" "$ROOT/src/Updater.swift"

VER="$(tr -d '[:space:]' < "$ROOT/VERSION")"
APP="$ROOT/build/TypePet.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/build/TypePet-bin" "$APP/Contents/MacOS/TypePet"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VER" "$APP/Contents/Info.plist"
cp -R "$ROOT/Resources/builtin" "$APP/Contents/Resources/builtin"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
xattr -cr "$APP" || true
sign_app "$APP"

if [[ -n "${TYPEPET_STAGE:-}" ]]; then
  rm -rf "$TYPEPET_STAGE"
  mkdir -p "$(dirname "$TYPEPET_STAGE")"
  cp -R "$APP" "$TYPEPET_STAGE"
  echo "staged $TYPEPET_STAGE"
fi

if [[ "${TYPEPET_INSTALL:-1}" == "1" ]]; then
  rm -rf /Applications/TypePet.app
  cp -R "$APP" /Applications/TypePet.app
  xattr -cr /Applications/TypePet.app || true
  echo "installed /Applications/TypePet.app"
fi

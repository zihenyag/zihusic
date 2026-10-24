#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="zihusic"
BUNDLE_ID="com.local.zihusic"
MIN_SYSTEM_VERSION="14.0"
APP_VERSION="${APP_VERSION:-0.4.0}"
CONFIGURATION="${CONFIGURATION:-release}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_SOURCE="$ROOT_DIR/Sources/ZihuMusic/Icon/icon.png"
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
ICON_FILE="$APP_RESOURCES/AppIcon.icns"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -x "ZihuMusic" >/dev/null 2>&1 || true

swift build --package-path "$ROOT_DIR" -c "$CONFIGURATION"
BUILD_BINARY="$(swift build --package-path "$ROOT_DIR" -c "$CONFIGURATION" --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE" "$DIST_DIR/ZihuMusic.app"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [[ -f "$ICON_SOURCE" ]] && command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"
  sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"
  rm -rf "$ICONSET_DIR"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_VERSION</string>
  <key>NSLocalNetworkUsageDescription</key>
  <string>发现并连接同一网络上的 AirPlay 扬声器。</string>
  <key>NSBonjourServices</key>
  <array>
    <string>_airplay._tcp</string>
    <string>_raop._tcp</string>
  </array>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$APP_BUNDLE" >/dev/null 2>&1 || true
fi

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign "$CODE_SIGN_IDENTITY" "$APP_BUNDLE"
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

install_app() {
  local destination="/Applications/$APP_NAME.app"
  local staging
  local backup
  if [[ -e "$destination" ]]; then
    if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist")" != "$BUNDLE_ID" ]]; then
      echo "Refusing to replace a different application at $destination" >&2
      return 1
    fi
    backup="$(mktemp -d "$DIST_DIR/installed-backup.XXXXXX")"
    /usr/bin/ditto "$destination" "$backup/$APP_NAME.app"
    echo "Previous installed app saved to $backup/$APP_NAME.app"
  fi
  staging="$(mktemp -d "/Applications/.$APP_NAME-install.XXXXXX")"
  /usr/bin/ditto "$APP_BUNDLE" "$staging/$APP_NAME.app"
  if [[ -e "$destination" ]]; then mv "$destination" "$staging/previous.app"; fi
  if ! mv "$staging/$APP_NAME.app" "$destination"; then
    if [[ -e "$staging/previous.app" ]]; then mv "$staging/previous.app" "$destination"; fi
    return 1
  fi
  rm -rf "$staging"
  codesign --verify --deep --strict --verbose=2 "$destination"
  /usr/bin/open -n "$destination"
}

case "$MODE" in
  run)
    open_app
    ;;
  --package|package)
    echo "Packaged $APP_BUNDLE ($APP_VERSION)"
    ;;
  --install|install)
    install_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--package|--install|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac

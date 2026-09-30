#!/usr/bin/env bash
# Builds a self-contained native Meltorama.app and an installable zip in dist/.
# Requires Xcode or Apple's command line tools. No downloaded dependencies.
#
# Usage: scripts/build-macos.sh [--debug] [--universal] [--launch]
# Set MELTORAMA_SIGN_IDENTITY to a Developer ID identity for distribution signing.
set -euo pipefail
if [[ "${1:-}" == "--help" ]]; then awk 'NR==1{next} /^#/{sub(/^# ?/, ""); print; next} {exit}' "$0"; exit 0; fi
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"
CONFIG=release
LAUNCH=false
ARCH_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --debug) CONFIG=debug ;;
    --universal) ARCH_ARGS=(--arch arm64 --arch x86_64) ;;
    --launch) LAUNCH=true ;;
    *) echo "!! unknown option: $arg" >&2; exit 1 ;;
  esac
done
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/meltorama-clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
echo "==> Checking shared shaders"
python3 scripts/sync-macos-shaders.py --check
echo "==> Building native Mac application ($CONFIG)"
swift build --package-path macos --configuration "$CONFIG" --disable-sandbox ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"}
BIN_DIR="$(swift build --package-path macos --configuration "$CONFIG" --show-bin-path ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"})"
APP_DIR="$REPO_DIR/dist/Meltorama.app"
mkdir -p dist
STAGE_DIR="$(mktemp -d "$REPO_DIR/dist/meltorama-stage.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
mkdir -p "$STAGE_DIR/Meltorama.app/Contents/MacOS" "$STAGE_DIR/Meltorama.app/Contents/Resources"
cp "$BIN_DIR/Meltorama" "$STAGE_DIR/Meltorama.app/Contents/MacOS/"
cp -R "$BIN_DIR/Meltorama_MeltoramaMac.bundle" "$STAGE_DIR/Meltorama.app/Contents/Resources/"
VERSION="$(sed -nE 's/^[[:space:]]*versionName[[:space:]]*=[[:space:]]*"([^"]*)".*$/\1/p' app/build.gradle.kts | head -n 1)"
BUILD_NUMBER="$(sed -nE 's/^[[:space:]]*versionCode[[:space:]]*=[[:space:]]*([0-9]*).*$/\1/p' app/build.gradle.kts | head -n 1)"
sed -e "s/VERSION/$VERSION/g" -e "s/BUILD_NUMBER/$BUILD_NUMBER/g" macos/Info.plist > "$STAGE_DIR/Meltorama.app/Contents/Info.plist"
cp LICENSE macos/THIRD_PARTY_NOTICES.txt "$STAGE_DIR/Meltorama.app/Contents/Resources/"
swift scripts/generate-macos-icon.swift "$STAGE_DIR/AppIcon.iconset"
iconutil -c icns "$STAGE_DIR/AppIcon.iconset" -o "$STAGE_DIR/Meltorama.app/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$STAGE_DIR/Meltorama.app/Contents/PkgInfo"
SIGN_IDENTITY="${MELTORAMA_SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$STAGE_DIR/Meltorama.app"
else
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$STAGE_DIR/Meltorama.app"
fi
codesign --verify --strict "$STAGE_DIR/Meltorama.app"
rm -rf "$APP_DIR"
mv "$STAGE_DIR/Meltorama.app" "$APP_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "dist/meltorama-macos-$VERSION.zip"
shasum -a 256 "dist/meltorama-macos-$VERSION.zip" > "dist/meltorama-macos-$VERSION.zip.sha256"
echo "-- app: $APP_DIR"
echo "-- zip: $REPO_DIR/dist/meltorama-macos-$VERSION.zip"
if $LAUNCH; then open "$APP_DIR"; fi

#!/bin/bash
# Builds build/Dockinator.app and build/Dockinator.dmg.
#   ./scripts/build-app.sh            build only
#   ./scripts/build-app.sh install    also copy to ~/Applications and launch
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.1.0}"
APP=build/Dockinator.app

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# One build per arch, merged: `--arch a --arch b` needs full Xcode.
bins=()
for arch in arm64 x86_64; do
  swift build -c release --triple "$arch-apple-macosx13.0" --scratch-path ".build/$arch"
  bins+=("$(swift build -c release --triple "$arch-apple-macosx13.0" --scratch-path ".build/$arch" --show-bin-path)/Dockinator")
done
lipo -create "${bins[@]}" -output "$APP/Contents/MacOS/Dockinator"

swift scripts/make-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Dockinator</string>
  <key>CFBundleDisplayName</key><string>Dockinator</string>
  <key>CFBundleIdentifier</key><string>io.github.baukebrenninkmeijer.dockinator</string>
  <key>CFBundleExecutable</key><string>Dockinator</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
EOF

# An ad-hoc signature changes every build, so macOS drops the Accessibility grant.
# A stable identity keeps it: SIGN_ID, else "Dockinator Local" (scripts/make-signing-cert.sh).
if [[ -z "${SIGN_ID:-}" ]] && security find-certificate -c "Dockinator Local" >/dev/null 2>&1; then
  SIGN_ID="Dockinator Local"
fi
codesign --force --deep --sign "${SIGN_ID:--}" "$APP"
echo "signed with ${SIGN_ID:-ad-hoc}"

mkdir -p build/dmg
cp -R "$APP" build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -volname Dockinator -srcfolder build/dmg -ov -format UDZO build/Dockinator.dmg >/dev/null
rm -rf build/dmg
echo "built $APP and build/Dockinator.dmg (v$VERSION)"

if [[ "${1:-}" == "install" ]]; then
  pkill -x Dockinator || true  # not running is fine
  rm -rf ~/Applications/Dockinator.app
  mkdir -p ~/Applications
  cp -R "$APP" ~/Applications/
  open ~/Applications/Dockinator.app
  echo "installed to ~/Applications/Dockinator.app"
fi

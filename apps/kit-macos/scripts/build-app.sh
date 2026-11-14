#!/bin/bash
# Builds build/LongoKit.app (Longo Mouse, Display, Keys, Shot and Share as modules of one app) and an installer disk image
# build/LongoKit.dmg.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/LongoKit.app
DMG=build/LongoKit.dmg
BUNDLE_ID=com.longokit.kit

# Universal binary so the app runs on both Apple Silicon and Intel Macs.
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/LongoKit"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LongoKit"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns Support/Logo.png Support/LogoLight.png "$APP/Contents/Resources/"
# Support/Fonts links to brand/fonts; copy the files, not the link.
cp -RL Support/Fonts "$APP/Contents/Resources/Fonts"
# Small marks for the sidebar and title bar.
cp -R Support/Marks "$APP/Contents/Resources/Marks"
# Each module's own images, in a folder named after it (the modules' resourceFolder).
for module in Mouse Display Keys Shot Share; do
    mkdir -p "$APP/Contents/Resources/$module"
    cp -L "Support/$module/Logo.png" "Support/$module/LogoLight.png" "$APP/Contents/Resources/$module/"
done

# The shared LongoKit identity (apps/mouse-macos/scripts/make-signing-identity.sh) keeps permissions across rebuilds.
# Without it the build is ad-hoc signed and macOS sees every build as a new app.
IDENTITY="LongoKit Local Signing"
if security find-identity -p codesigning | grep -q "$IDENTITY"; then
    codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
else
    echo "warning: \"$IDENTITY\" not found; signing ad-hoc (permissions reset on every rebuild)" >&2
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
fi

# Disk image: a designed installer window with the app next to an Applications shortcut (scripts/dmg).
# dmgbuild lays out the window without driving Finder; it's installed into a local virtualenv on first use.
rm -f "$DMG"
VENV=build/.dmgvenv
if [ ! -x "$VENV/bin/dmgbuild" ]; then
    python3 -m venv "$VENV" && "$VENV/bin/pip" install --quiet dmgbuild || true
fi
if [ -x "$VENV/bin/dmgbuild" ]; then
    tiffutil -cathidpicheck Support/dmg/background.png Support/dmg/background@2x.png -out build/dmg-background.tiff 2>/dev/null
    "$VENV/bin/dmgbuild" -s scripts/dmg/settings.py \
        -D app="$APP" -D background=build/dmg-background.tiff -D volume_icon=Support/AppIcon.icns \
        "LongoKit" "$DMG" >/dev/null
else
    echo "warning: dmgbuild unavailable; building a plain disk image" >&2
    STAGE="$(mktemp -d)"
    trap 'rm -rf "$STAGE"' EXIT
    cp -R "$APP" "$STAGE/LongoKit.app"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "LongoKit" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
fi

echo "Built $APP"
echo "Built $DMG"

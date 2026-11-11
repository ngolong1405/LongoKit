#!/bin/bash
# Renders scripts/dmg/background.html into Support/dmg/background.png (1x) and background@2x.png (Retina)
# with headless Google Chrome. Run it after changing the background design, and commit the PNGs.
set -euo pipefail
cd "$(dirname "$0")/../.."

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PAGE="file://$PWD/scripts/dmg/background.html"
mkdir -p Support/dmg

render() { # scale, output
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
        --force-device-scale-factor="$1" --window-size=660,484 --virtual-time-budget=2000 \
        --screenshot="$PWD/$2" "$PAGE" >/dev/null 2>&1
}
render 1 Support/dmg/background.png
render 2 Support/dmg/background@2x.png
echo "Rendered Support/dmg/background.png and background@2x.png"

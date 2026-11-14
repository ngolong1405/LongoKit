#!/bin/bash
# Renders the LongoKit Trinity icons from brand/icons/icons.html into brand/icons/<icon>-<theme>.png (1024×1024)
# with headless Chrome. Run after changing the design, then scripts/apply-icons.sh copies them into the apps.
set -euo pipefail
cd "$(dirname "$0")"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for icon in mouse display keys shot share kit; do
    for theme in dark light; do
        "$CHROME" --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 \
            --window-size=1024,1024 --virtual-time-budget=1500 \
            --screenshot="$PWD/$icon-$theme.png" "file://$PWD/icons.html?icon=$icon&theme=$theme" >/dev/null 2>&1
    done
done
echo "Rendered brand/icons/{mouse,display,keys,shot,share,kit}-{dark,light}.png"

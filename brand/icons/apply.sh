#!/bin/bash
# Copies the rendered Trinity icons into the apps and the brand logos:
#   <app>/Support/Logo.png, LogoLight.png (in-app logo, 512 px) and AppIcon.icns (Dock / Finder).
set -euo pipefail
cd "$(dirname "$0")/../.."

icns() { # source png, output icns
    local work; work="$(mktemp -d)"
    mkdir -p "$work/AppIcon.iconset"
    for size in 16 32 128 256 512; do
        sips -z $size $size "$1" --out "$work/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
        sips -z $((size * 2)) $((size * 2)) "$1" --out "$work/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$work/AppIcon.iconset" -o "$2"
    rm -rf "$work"
}

apply() { # icon name, app folder
    sips -z 512 512 "brand/icons/$1-dark.png" --out "apps/$2/Support/Logo.png" >/dev/null
    sips -z 512 512 "brand/icons/$1-light.png" --out "apps/$2/Support/LogoLight.png" >/dev/null
    icns "brand/icons/$1-dark.png" "apps/$2/Support/AppIcon.icns"
}

apply mouse mouse-macos
apply display display-macos
# The LongoKit mark (website header, favicon, Longo Mouse's installer) is the mouse icon.
sips -z 512 512 brand/icons/mouse-dark.png --out brand/logo/logo-dark.png >/dev/null
sips -z 512 512 brand/icons/mouse-light.png --out brand/logo/logo-light.png >/dev/null
sips -z 256 256 brand/icons/mouse-dark.png --out website/public/favicon.png >/dev/null
echo "Applied the Trinity icons to the apps, brand/logo and the favicon"

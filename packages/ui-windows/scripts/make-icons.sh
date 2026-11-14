#!/bin/sh
# Builds each Windows app's .ico (16 to 256 px, PNG frames) from the brand icons. Run on a Mac (it uses sips).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for app in display shot mouse share kit; do
    for size in 16 20 24 32 40 48 64 128 256; do
        sips -Z "$size" "$root/brand/icons/$app-dark.png" --out "$work/$app-$size.png" >/dev/null
    done
    python3 "$here/pack-ico.py" "$root/packages/ui-windows/Icons/$app.ico" "$work"/$app-*.png
done

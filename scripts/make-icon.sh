#!/usr/bin/env bash
# Renders Resources/AppIcon.svg to Resources/AppIcon.icns (and a 1024px PNG preview).
set -euo pipefail
cd "$(dirname "$0")/.."

BROWSER="${AJAR_BROWSER:-/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge}"
[[ -x "$BROWSER" ]] || BROWSER="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
printf '<html><body style="margin:0;background:transparent">%s</body></html>' "$(cat Resources/AppIcon.svg)" > "$WORK/icon.html"
"$BROWSER" --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 \
  --window-size=1024,1024 --screenshot="$WORK/icon_1024.png" "file://$WORK/icon.html" >/dev/null 2>&1

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size "$WORK/icon_1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double "$WORK/icon_1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
cp "$WORK/icon_1024.png" Resources/AppIcon.png
echo "Wrote Resources/AppIcon.icns and Resources/AppIcon.png"

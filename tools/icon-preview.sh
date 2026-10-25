#!/bin/bash
# Render an .icon at the sizes that decide one.
#
#   ./tools/icon-preview.sh /tmp/shellhand-icon [path/to/Some.icon]
#
# An Icon Composer bundle cannot be judged by looking at its SVG: the squircle,
# the gradient, the shadow and the specular highlight are added by macOS when
# the icon is composited. So this compiles the bundle with ictool, puts the
# result in a stub app, and asks NSWorkspace for that app's icon — which is the
# image Finder and the Dock will draw.
#
# It writes PNGs at 16 through 512 and a contact sheet with the small sizes at
# true scale on both a light and a dark ground, because 16pt is where an icon
# fails and nothing else tells you that it has.
#
# Nothing here touches the user's host list, keychain or known_hosts; it builds
# a throwaway bundle under the directory it is given.
set -euo pipefail

OUT="${1:?usage: icon-preview.sh <output-dir> [icon-bundle]}"
ICON="${2:-Shellhand/Resources/Shellhand.icon}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

[ -d "$ICON" ] || { echo "no icon bundle at $ICON" >&2; exit 1; }
NAME="$(basename "$ICON" .icon)"
mkdir -p "$OUT"

# The renderer is built once and kept, like the spike servers.
RENDERER="$OUT/rendericon"
if [ ! -x "$RENDERER" ] || [ "$(dirname "$0")/RenderIcon.swift" -nt "$RENDERER" ]; then
  xcrun swiftc -O "$(dirname "$0")/RenderIcon.swift" -o "$RENDERER"
fi

STUB="$OUT/$NAME.app"
rm -rf "$STUB"
mkdir -p "$STUB/Contents/Resources" "$STUB/Contents/MacOS"

xcrun ictool --compile "$STUB/Contents/Resources" \
  --platform macosx --minimum-deployment-target 26.0 \
  --app-icon "$NAME" \
  --output-partial-info-plist "$OUT/$NAME-partial.plist" \
  "$ICON" > "$OUT/$NAME-compile.plist"
if grep -q "actool.errors" "$OUT/$NAME-compile.plist"; then
  cat "$OUT/$NAME-compile.plist" >&2
  exit 1
fi

cat > "$STUB/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>$NAME</string>
<key>CFBundleIdentifier</key><string>com.shellhand.icon-preview.$NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleExecutable</key><string>$NAME</string>
<key>CFBundleIconName</key><string>$NAME</string>
</dict></plist>
PLIST
printf '#!/bin/bash\n' > "$STUB/Contents/MacOS/$NAME"
chmod +x "$STUB/Contents/MacOS/$NAME"
touch "$STUB"

"$RENDERER" "$STUB" "$OUT" "$NAME"
echo "wrote $OUT/$NAME-{16,32,64,128,256,512}.png, $OUT/$NAME-sheet.png and $OUT/$NAME-loupe.png"

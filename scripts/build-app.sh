#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
help=$(swift build --help)
debug_flag=-debug-info-format
if [[ "$help" == *'  --debug-info-format '* ]]; then debug_flag=--debug-info-format; fi
./scripts/swift.sh build -c "$configuration" --product ChatScribe "$debug_flag" none
bin=$(./scripts/swift.sh build -c "$configuration" "$debug_flag" none --show-bin-path | tail -1)
app="dist/聊迹.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/ChatScribe" "$app/Contents/MacOS/ChatScribe"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.liaoji.chatscribe</string>
<key>CFBundleName</key><string>聊迹</string>
<key>CFBundleDisplayName</key><string>聊迹</string>
<key>CFBundleExecutable</key><string>ChatScribe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.6.0</string>
<key>CFBundleVersion</key><string>8</string>
<key>CFBundleLocalizations</key><array><string>zh-Hans</string><string>zh-Hant</string><string>ja</string><string>en</string><string>ko</string></array>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 聊迹. MIT License.</string>
<key>CFBundleDocumentTypes</key><array><dict>
<key>CFBundleTypeName</key><string>聊迹项目</string>
<key>CFBundleTypeRole</key><string>Editor</string>
<key>LSHandlerRank</key><string>Owner</string>
<key>LSItemContentTypes</key><array><string>com.liaoji.project</string></array>
</dict></array>
<key>UTExportedTypeDeclarations</key><array><dict>
<key>UTTypeIdentifier</key><string>com.liaoji.project</string>
<key>UTTypeDescription</key><string>聊迹完整项目</string>
<key>UTTypeConformsTo</key><array><string>public.json</string></array>
<key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>liaoji</string></array></dict>
</dict></array>
</dict></plist>
PLIST
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
for resource in "$bin"/*.bundle; do
  if [[ -d "$resource" ]]; then /usr/bin/ditto "$resource" "$app/Contents/Resources/$(basename "$resource")"; fi
done
codesign --force --deep --sign - "$app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "dist/Liaoji-macOS-$(uname -m).zip"
printf '%s\n' "$PWD/$app"

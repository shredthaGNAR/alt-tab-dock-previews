#!/usr/bin/env bash
# Builds a universal (Apple silicon + Intel) Release AltTab.app, signs it ad-hoc, and packages it into a drag-to-install DMG.
# Run from the repository root: scripts/make_dmg.sh
# Output: dist/AltTab-Dock-Previews.dmg

set -euo pipefail

appName="AltTab"
dmgName="AltTab-Dock-Previews"
volumeName="AltTab Dock Previews"
derivedData="${DERIVED_DATA:-../DerivedData-release}"
distDir="dist"
appPath="$derivedData/Build/Products/Release/$appName.app"
dmgPath="$distDir/$dmgName.dmg"
buildLog="$distDir/build.log"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)"

mkdir -p "$distDir"

echo "Building $appName $version (Release, arm64 + x86_64). This takes a few minutes…"
if ! xcodebuild -workspace alt-tab-macos.xcworkspace -scheme Release -configuration Release \
    -derivedDataPath "$derivedData" \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" \
    OTHER_CODE_SIGN_FLAGS="--options runtime" \
    build >"$buildLog" 2>&1; then
  grep -E "error:" "$buildLog" | sort -u | head -20 || true
  echo "Build failed. Full log: $buildLog"
  exit 1
fi

echo "Architectures: $(lipo -archs "$appPath/Contents/MacOS/$appName")"
if ! codesign --verify --deep --strict "$appPath" 2>/dev/null; then
  echo "Warning: codesign --verify reported a problem with $appPath"
fi

staging="$(mktemp -d)/$dmgName"
mkdir -p "$staging"
ditto "$appPath" "$staging/$appName.app"
ln -s /Applications "$staging/Applications"
cat >"$staging/READ ME FIRST.txt" <<'EOF'
AltTab Dock Previews
====================

Install
1. Quit DockAltTab and any other copy of AltTab.
2. Drag AltTab into the Applications folder. If you already have AltTab there, choose Replace.
3. Open AltTab from Applications.

First launch
This build isn't notarized by Apple, so macOS blocks it the first time.
- macOS 15 Sequoia or later: when macOS says it can't verify AltTab, click Done. Then open
  System Settings > Privacy & Security, scroll down, click "Open Anyway" next to AltTab, and confirm.
- macOS 14 Sonoma or earlier: Control-click AltTab in Applications, choose Open, then click Open.

Permissions
AltTab asks for Accessibility and Screen Recording. Allow both, then relaunch AltTab if asked.
If AltTab was in the Accessibility list before, remove the old entry with the minus (-) button first.

Settings
AltTab settings > Controls > Additional controls... > Dock previews

Website: https://shredthagnar.github.io/alt-tab-dock-previews
Source:  https://github.com/shredthaGNAR/alt-tab-dock-previews
EOF

rm -f "$dmgPath"
hdiutil create -volname "$volumeName" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$dmgPath" >/dev/null
rm -rf "$(dirname "$staging")"

echo "Created $dmgPath ($(du -h "$dmgPath" | cut -f1 | xargs))"
echo "SHA-256: $(shasum -a 256 "$dmgPath" | cut -d' ' -f1)"

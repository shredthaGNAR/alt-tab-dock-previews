# AltTab with built-in Dock previews

Website: https://shredthagnar.github.io/alt-tab-dock-previews

This is [steventheworker's scriptable AltTab fork](https://github.com/steventheworker/alt-tab-macos) with [DockAltTab](https://github.com/steventheworker/DockAltTab) built in. Hovering a running app's Dock icon shows its windows in the AltTab panel, anchored to the icon. You no longer need to run DockAltTab alongside AltTab.

## What changed

- `src/logic/dock-previews/` adds the Dock hover and click handling, ported from DockAltTab's macOS/Windows modes and rewritten in Swift.
  - `DockPreviews.swift`: the event tap, hover logic and Windows-style Dock clicks.
  - `DockGeometry.swift`: the Dock layout, hit-testing of Dock icons, and holding the Dock's auto-hide.
  - `DockAltTabActions.swift`: show, hide, window preview, window counts, deminimize and reposition. These were previously only reachable over AppleScript.
- The AppleScript commands (`showApp`, `hide`, `thumbnailPreview`, `countAllWindowStats`, …) now call the same shared code, so the standalone DockAltTab and other scripts keep working.
- Settings are under **Controls → Additional controls… → Dock previews**:
  - Show windows when hovering an app in the Dock
  - Clicking an active app in the Dock hides it
  - Keep an auto-hiding Dock visible while previewing
- The full-size window preview on hover follows AltTab's own **Preview selected window** setting.

Fixes compared with running the two apps together:
- Hovering an app with nothing to show no longer crashes AltTab.
- The "pointer moved to another icon" check on Dock clicks now works.
- Window counts are read directly instead of being polled over AppleScript.

## Download

Get `AltTab-Dock-Previews.dmg` from the [latest release](https://github.com/shredthaGNAR/alt-tab-dock-previews/releases/latest), open it and drag AltTab into Applications. It runs on Apple silicon and Intel Macs with macOS 12 or later.

The app isn't notarized, so macOS blocks it the first time you open it:
- **macOS 15 Sequoia or later:** click Done on the warning, then go to System Settings → Privacy & Security and click **Open Anyway** next to AltTab.
- **macOS 14 Sonoma or earlier:** Control-click AltTab in Applications and choose Open.

To make the DMG yourself, run `scripts/make_dmg.sh` from the repository root. It writes `dist/AltTab-Dock-Previews.dmg`.

Update checks go to this fork's own feed (`appcast.xml` on the website) rather than DockAltTab's, so installing doesn't pull in an update that removes the Dock previews.

## Build

```bash
git clone -b dock-previews https://github.com/shredthaGNAR/alt-tab-dock-previews.git
cd alt-tab-dock-previews
xcodebuild -workspace alt-tab-macos.xcworkspace -scheme Debug -configuration Debug -derivedDataPath ../DerivedData CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" build
```

The app is built at `../DerivedData/Build/Products/Debug/AltTab.app`. Quit DockAltTab before running it. It needs Accessibility and Screen Recording permissions. With ad-hoc signing (`CODE_SIGN_IDENTITY="-"`), macOS asks for these again after every rebuild.

## Known limitations

- The Dock's magnification ends as soon as the pointer leaves the Dock; this is macOS behaviour.
- With "Clicking an active app in the Dock hides it" on, you can't drag Dock icons of apps that have open windows. DockAltTab behaves the same way.
- DockAltTab's Ubuntu mode (click to preview), its preview-gap setting, and its Finder and Firefox picture-in-picture focus workarounds are not ported.

Licensed under GPL-3.0, like AltTab and DockAltTab (see `LICENCE.md`).

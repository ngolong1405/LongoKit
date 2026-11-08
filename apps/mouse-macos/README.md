# Longo Mouse for macOS


Remap every mouse button and gesture, and tune the scroll wheel, separately for each mouse.

- **Buttons:** click, double click, hold, click + drag, and click + scroll on any extra button. Actions include Mission Control, Spaces, Launchpad, back/forward, keyboard shortcuts, and media keys.
- **Listen for a button:** press a mouse button to add it; buttons already set up are highlighted.
- **Scrolling:** natural or classic direction for mice only (the trackpad keeps its setting), smooth animated scrolling, custom speed (hold ⌥ for slower, ⌘ for faster).
- **Per mouse:** each mouse can have its own buttons and scroll settings, switched automatically when you use it.
- **Menu bar popover** for quick toggles, light and dark themes, and English and Vietnamese.

## Build

Run from this folder (`apps/mouse-macos`). Requires the Xcode command line tools (Swift 5.9+).

```sh
./scripts/build-app.sh        # build/LongoMouse.app and build/LongoMouse.dmg (universal)
swift build && .build/debug/LongoMouse --selftest   # engine self-test
```

Optional: `./scripts/make-signing-identity.sh` creates a local signing certificate so macOS keeps the
Accessibility and Input Monitoring permissions across rebuilds.

On first launch, grant **Accessibility** and **Input Monitoring** in System Settings › Privacy & Security.

## Layout

- `Sources/LongoMouse/`: the app (SwiftUI + AppKit). `MouseEngine` holds the event tap and gesture logic, and `AppModel` holds the settings.
- `Support/`: Info.plist, icons, and bundled fonts (Space Grotesk, Geist, JetBrains Mono; SIL Open Font License).
- `scripts/`: build and signing helpers.

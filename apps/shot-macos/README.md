# Longo Shot for macOS

Screenshots and text from the screen in one shortcut: saved to your folder and on the clipboard, ready to paste.
A menu bar app that waits quietly in the background.

- **Capture an area, a window or the whole screen** (⌥⇧1, ⌥⇧2, ⌥⇧3). While dragging an area, Space switches to
  picking a window and Esc cancels. Windows are captured with their shadow.
- **Copy text from the screen** (⌥⇧4): drag over text and it's read on this Mac with Apple's Vision (English and
  Vietnamese, with its marks) and copied.
- **After each capture** the PNG is saved to the folder you choose (`~/Downloads` by default) and copied to the
  clipboard as an image and a file. Turn saving off to keep captures on the clipboard only. A preview in the corner can
  be dragged into another app, copied, or shown in Finder.
- **Your own shortcuts** for every action, recorded in the Shortcuts tab. They work in every app without any
  permission; the app warns when macOS or another app already uses one.
- **Runs in the background:** closing the window keeps the shortcuts working; the menu bar icon can be hidden
  (⌥⇧0 opens the settings again).
- Screen recording is coming next.

## Build

Run from this folder (`apps/shot-macos`). Requires macOS 14 and the Xcode command line tools (Swift 5.9+).

```sh
./scripts/build-app.sh                                   # build/LongoShot.app and build/LongoShot.dmg
swift build && .build/debug/LongoShot --selftest         # shortcuts, settings, file names, PNG output, OCR
.build/debug/LongoShot --snapshot <dir>                  # renders the UI to PNGs
```

It shares the LongoKit signing identity with Longo Mouse (`apps/mouse-macos/scripts/make-signing-identity.sh`), so
the Screen Recording permission stays granted across rebuilds. The UI comes from [`packages/ui-macos`](../../packages/ui-macos).

## Notes

- Captures need **Screen Recording** (System Settings › Privacy & Security › Screen & System Audio Recording). Like
  every screenshot app, macOS asks again from time to time whether it may keep recording the screen.
- The app's own windows (selection overlay, preview, menu) are left out of every capture.
- Nothing leaves the Mac: text recognition runs on-device.

## License

Source-available under the [LongoKit License](../../LICENSE.md): build and use it yourself; don't redistribute or sell it.

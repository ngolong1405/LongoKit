# Longo Shot for macOS

Screenshots, screen recordings and text from the screen in one shortcut: drawn on, saved to your folder and on the
clipboard, ready to paste. A menu bar app that waits quietly in the background.

- **Capture an area or a window** (⌥⇧1): drag an area, or click the window under the pointer (it lights up); a
  double-click takes the whole screen. **Capture the full screen** with ⌥⇧2.
- **Draw right after capturing:** the capture stays in place with a toolbar: arrows, pen, boxes and highlights in eight
  colors and three sizes, with undo. ↩ or ⌘C saves and copies it, Esc only copies it, ✕ throws it away.
- **Copy text from the screen** (⌥⇧3): drag over text and it's read on this Mac with Apple's Vision (English and
  Vietnamese, with its marks) and copied.
- **Record the screen** (⌥⇧4): drag an area and adjust it, then Start (or double-click for the whole screen, Space for a
  window). An optional 3-2-1 countdown, a bar with the time, Pause and Stop, the Mac's sound and the microphone,
  pointer and clicks. Pauses leave no gap; the result is an MP4.
- **After each capture** the PNG is saved to the folder you choose (`~/Downloads` by default) and copied to the
  clipboard as an image and a file. Turn saving off to keep captures on the clipboard only. A preview in the corner can
  be dragged into another app or drawn on.
- **Recent** in the menu: the last 10 captures and recordings, to preview, copy again or drag into another app.
- **Your own shortcuts** for every action, recorded in the Shortcuts tab. They work in every app without any
  permission; the app warns when macOS or another app already uses one.
- **Runs in the background:** closing the window keeps the shortcuts working; the menu bar icon can be hidden
  (⌥⇧0 opens the settings again). macOS's own sounds mark captures and recordings, never into the recording.

## Build

Run from this folder (`apps/shot-macos`). Requires macOS 14 and the Xcode command line tools (Swift 5.9+).

```sh
./scripts/build-app.sh                                   # build/LongoShot.app and build/LongoShot.dmg
swift build && .build/debug/LongoShot --selftest         # shortcuts, settings, files, OCR, drawing, Recent
.build/debug/LongoShot --draw-test                       # the in-place drawing toolbar, on screen
open -n build/LongoShot.app --args --record-test <file.mp4>   # a real 2 s recording with a pause (needs Screen Recording)
.build/debug/LongoShot --snapshot <dir>                  # renders the UI to PNGs
```

It shares the LongoKit signing identity with Longo Mouse (`apps/mouse-macos/scripts/make-signing-identity.sh`), so
the Screen Recording permission stays granted across rebuilds. The UI comes from [`packages/ui-macos`](../../packages/ui-macos).

## Notes

- Captures and recordings need **Screen Recording** (System Settings › Privacy & Security › Screen & System Audio
  Recording); the microphone asks for Microphone access the first time it's turned on. Like every screenshot app,
  macOS asks again from time to time whether it may keep recording the screen.
- The app's own windows (selection overlay, toolbars, recording bar, preview, menu) are left out of every capture.
- Nothing leaves the Mac: text recognition runs on-device.

## License

Source-available under the [LongoKit License](../../LICENSE.md): build and use it yourself; don't redistribute or sell it.

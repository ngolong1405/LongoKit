# Longo Display for macOS

Brightness for every display on your Mac: external monitors over DDC/CI, software dimming for the rest, and Sync
with the built-in display.

- **Per-display brightness** from the menu bar or the app: built-in and Apple displays natively, external monitors
  over DDC/CI (Apple Silicon), anything else with software (gamma) dimming.
- **Brightness keys** change the display under the pointer, with an on-screen indicator (needs Accessibility).
- **Sync mode**: external displays follow the built-in display (which follows ambient light), each within its own
  minimum and maximum.
- **Extra dimming** below the lowest brightness, for late nights.
- **Presets** (0 / 25 / 50 / 75 / 100 %) for every display at once, and settings remembered per display.

## Build

Run from this folder (`apps/display-macos`). Requires the Xcode command line tools (Swift 5.9+).

```sh
./scripts/build-app.sh                                   # build/LongoDisplay.app and build/LongoDisplay.dmg
swift build && .build/debug/LongoDisplay --selftest      # DDC packets, Sync math, coalescing
.build/debug/LongoDisplay --diagnose                     # how this Mac's displays are seen (for bug reports)
.build/debug/LongoDisplay --snapshot <dir>               # renders the UI to PNGs
```

It shares the LongoKit signing identity with Longo Mouse (`apps/mouse-macos/scripts/make-signing-identity.sh`).
The UI comes from [`packages/ui-macos`](../../packages/ui-macos).

## Notes

- DDC/CI uses private macOS APIs, so the app ships outside the App Store. It doesn't work through DisplayLink docks,
  some USB-C hubs, the HDMI port of the M1 Mac mini, or TVs; those displays fall back to software dimming.
- Intel Macs get software dimming for external displays for now.
- Quitting restores the displays' normal colors (software dimming is undone).

## License

Source-available under the [LongoKit License](../../LICENSE.md): build and use it yourself; don't redistribute or sell it.

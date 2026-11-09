# Longo Keys for macOS

Keyboard remapping for every keyboard on your Mac, without drivers.

- **Per-keyboard remaps**: click a key on the keyboard picture to choose what it sends; a one-click ⌘ ↔ ⌥ swap for
  Windows keyboards. Uses macOS's own key tables (`UserKeyMapping`, like `hidutil`): no permission needed, and it
  works in password fields.
- **Caps Lock**: unchanged, Esc, Control, or **Hyper**: tap for Esc, hold for ⌃⌥⇧⌘.
- **Hyper layer**: Hyper + H J K L for arrows, U / O for Home / End, Space for the next input source, any key to open
  an app or send a recorded shortcut; other keys go out with ⌃⌥⇧⌘ for app shortcuts. Needs Accessibility.
- **Safety**: every change asks to be kept and undoes itself after 15 seconds without an answer; changes that would
  leave a keyboard without Esc, Return, ⌘, ⌃, ⌥ or K are refused; ⌃⌥⌘K pauses everything from any app; keys go back
  to normal when the app quits, and tables left by a crash are cleared at the next launch.

## Build

Run from this folder (`apps/keys-macos`). Requires the Xcode command line tools (Swift 5.9+).

```sh
./scripts/build-app.sh                               # build/LongoKeys.app and build/LongoKeys.dmg
swift build && .build/debug/LongoKeys --selftest     # key tables, safety rules, the Hyper key
.build/debug/LongoKeys --diagnose                    # keyboards and their current key tables
.build/debug/LongoKeys --snapshot <dir>              # renders the UI to PNGs
```

It shares the LongoKit signing identity with Longo Mouse (`apps/mouse-macos/scripts/make-signing-identity.sh`).
The UI comes from [`packages/ui-macos`](../../packages/ui-macos).

## Notes

- In password fields macOS turns on Secure Input and hides keystrokes from event taps: there the Hyper key waits
  until the field loses focus. Remapped keys keep working.
- Key tables are matched to keyboards by vendor, product and location, and applied again whenever a keyboard
  connects (macOS forgets them on reconnect and restart).

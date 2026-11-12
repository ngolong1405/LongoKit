# LongoKit for macOS

Longo Mouse, Display, Keys and Shot in one menu bar app. Each is a module you turn on or off: a module that's off isn't
loaded, takes no memory and asks for no permissions. One process instead of four saves the memory every SwiftUI app
pays just to run.

- **One window:** the modules down a sidebar, each with its own tabs, as in its own app. Language, appearance, start at
  login and the menu bar icon are set once, on the General page.
- **One menu bar icon:** click for a strip to pick a module and its quick controls; double-click for the window;
  right-click for Settings, each module's on/off, About and Quit. Shot's timer takes the icon over while it records.
- **One on/off per module,** wherever it shows: the module's own switch, the General page, the right-click menu, the
  sidebar's light. Off stops it at once; from the next launch it isn't loaded at all.
- **From the separate apps:** the first time a module runs here, it starts from its own app's settings. While a
  module's own app is open, the module waits, so nothing acts twice; **Run Here** quits that app and takes over.

## Build

Run from this folder (`apps/kit-macos`). Requires macOS 14 and the Xcode command line tools (Swift 5.9+).

```sh
./scripts/build-app.sh                                   # build/LongoKit.app
swift build && .build/debug/LongoKit --selftest          # modules on and off, shared settings, settings import, drawing
.build/debug/LongoKit --snapshot /tmp/kit                # every page and menu, in both languages and appearances
```

## Layout

- `Sources/LongoKit/`: the app: `Suite` runs the modules and holds the shared settings, `KitWindow` and `KitMenu` show
  them. Each module comes from its app's `Longo<App>Kit` library (`apps/<app>-macos`) through `LongoModule`.
- `Support/`: Info.plist, the icon, the fonts, and links to each module's `Support` for its images.
- `scripts/build-app.sh`: builds and signs the app.

# LongoKit brand

- `icons/`: the LongoKit Trinity app icons (LongoMouse, LongoDisplay, LongoKeys) on dark and light tiles.
  Edit `icons/icons.html`, run `icons/render.sh`, then `icons/apply.sh` to update the apps, logos and favicon.
- `logo/`: the LongoKit mark (the LongoMouse icon) on dark (`logo-dark.png`) and light (`logo-light.png`) tiles.
- `fonts/`: Space Grotesk (display), Geist (UI), JetBrains Mono (code/keys), each with its SIL Open Font License.
- `tokens.css`: color, font, and radius tokens as CSS variables (`--lk-*`), light and dark.

The macOS app keeps its own copies in `apps/mouse-macos/Support` because the app bundle needs them. When a
color changes, update `tokens.css` and `Theme` in `packages/ui-macos/Sources/LongoKitUI/Components.swift`.

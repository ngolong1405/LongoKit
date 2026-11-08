# LongoKit brand

- `logo/`: app logo on dark (`logo-dark.png`) and light (`logo-light.png`) backgrounds.
- `fonts/`: Space Grotesk (display), Geist (UI), JetBrains Mono (code/keys), each with its SIL Open Font License.
- `tokens.css`: color, font, and radius tokens as CSS variables (`--lk-*`), light and dark.

The macOS app keeps its own copies in `apps/mouse-macos/Support` because the app bundle needs them. When a
color changes, update `tokens.css` and `Theme` in `apps/mouse-macos/Sources/LongoMouse/Components.swift`.

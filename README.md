# LongoKit

Tools for customizing mice, keyboards, and displays on macOS and Windows, by Long Ngô.

| App | Folder | Platform | Status |
|---|---|---|---|
| **Longo Mouse** | [`apps/mouse-macos`](apps/mouse-macos) | macOS 13+ | In progress |
| Longo Mouse | `apps/mouse-windows` | Windows | Planned |
| Longo Keys | `apps/keys-macos`, `apps/keys-windows` | macOS, Windows | Planned |
| Longo Display | `apps/display-macos`, `apps/display-windows` | macOS, Windows | Planned |
| Website | [`website`](website) | Web (Astro) | Placeholder |

## Repository layout

```
apps/<product>-<platform>/   one app each, building on its own (its own README, scripts, and CI workflow)
packages/                    code shared by several apps, e.g. the SwiftUI design system (added when a second app needs it)
brand/                       logos, fonts, and color tokens shared by the apps and the website
website/                     the LongoKit landing page
.github/workflows/           one workflow per app, triggered only by changes in that app's folder
```

## Conventions

- **Folders:** `apps/<product>-<platform>`, lowercase, e.g. `mouse-macos`, `keys-windows`.
- **Commits:** start with the area they touch, e.g. `mouse-macos: add smooth scrolling`, `website: hero section`, `repo: CI`.
- **Releases:** tag per app, `mouse-macos/v0.2.0`, so each app ships on its own schedule.
- **Shared code** moves into `packages/` only once a second app uses it; until then it stays in the app.

Each app's README has its build steps.

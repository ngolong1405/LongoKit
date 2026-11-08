# LongoKit

Tools for customizing mice, keyboards, and displays on macOS and Windows, by Long Ngô.

| App | Folder | Platform | Status |
|---|---|---|---|
| **Longo Mouse** | [`apps/mouse-macos`](apps/mouse-macos) | macOS 13+ | In progress |
| Longo Mouse | `apps/mouse-windows` | Windows | Planned |
| Longo Keys | `apps/keys-macos`, `apps/keys-windows` | macOS, Windows | Planned |
| Longo Display | `apps/display-macos`, `apps/display-windows` | macOS, Windows | Planned |

## Repository layout

```
apps/        one folder per app and platform, each building on its own
packages/    code shared by several apps (e.g. the SwiftUI design system), added once a second app needs it
brand/       logos, icons and design tokens shared by the apps and the website
website/     the LongoKit landing page
```

Each app has its own README with build steps.

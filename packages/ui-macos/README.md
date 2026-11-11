# LongoKitUI

The SwiftUI design system shared by the LongoKit macOS apps: color tokens (`Theme`), fonts, panels, switches,
sliders, segmented controls, chips, buttons, rows, the slim scroll view, dropdowns, and the `L()` localization helper.

Each app is a module (`LongoModule`) in a `Longo<App>Kit` library, plus a small target holding `@main`. At launch it:
- sets `Resource.developmentSupport` to its `Support` folder so `swift run` finds resources,
- calls `prepare()` on its module, which shares the module's Vietnamese table with this package's controls and
  registers the fonts it ships in `Contents/Resources/Fonts`.

Inside a module, `L()` reads the module's own table first, so two modules in one app can word a string differently.

The LongoKit app (`apps/kit-macos`) runs several modules in one process through `LongoModule.host`, which hands back a
`HostedModule`: the module's window page and menu, its language and appearance, and its state. Inside it,
`\.isHosted` is true, so a module leaves the app-wide settings and About to LongoKit.

Colors match `brand/tokens.css`; change both together.

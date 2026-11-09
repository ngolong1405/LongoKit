# LongoKitUI

The SwiftUI design system shared by the LongoKit macOS apps: color tokens (`Theme`), fonts, panels, switches,
sliders, segmented controls, chips, buttons, rows, the slim scroll view, dropdowns, and the `L()` localization helper.

Each app:
- ships the fonts in its bundle (`Contents/Resources/Fonts`) and calls `Fonts.register()` at launch,
- sets `Localizer.vietnamese` to its own string table,
- sets `Resource.developmentSupport` to its `Support` folder so `swift run` finds resources.

Colors match `brand/tokens.css`; change both together.

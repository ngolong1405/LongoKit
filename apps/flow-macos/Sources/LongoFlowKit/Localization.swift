import LongoKitUI

// This module's own words come first. These shadow LongoKitUI's `L` here, so a string can read differently in this
// module than in another one running in the same app.

func L(_ english: String) -> String {
    LongoKitUI.L(english, in: Vietnamese.strings)
}

func L(_ english: String, _ arguments: CVarArg...) -> String {
    String(format: L(english), arguments: arguments)
}

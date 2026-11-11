import LongoKitUI

// LongoKit's own words come first. These shadow LongoKitUI's `L` here, so the app's pages read its own table.

func L(_ english: String) -> String {
    LongoKitUI.L(english, in: Vietnamese.strings)
}

func L(_ english: String, _ arguments: CVarArg...) -> String {
    String(format: L(english), arguments: arguments)
}

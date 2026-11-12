import AppKit
import LongoKitUI
import SwiftUI

/// Reading a capture's text, for the window: the language to read it as, the lines read, and the text as it'll be
/// copied (which can be edited).
@MainActor
final class TextReading: ObservableObject {
    /// "auto": any script, Vietnamese marks kept on Latin lines; otherwise one of Vision's language codes.
    @Published var language: String {
        didSet {
            guard language != oldValue else { return }
            remember(language)
            read()
        }
    }
    /// Lines joined into one paragraph, for text broken across lines (a column, a caption).
    @Published var joinsLines = false {
        didSet { text = composed }
    }
    @Published private(set) var lines: [String] = []
    @Published var text = ""
    @Published private(set) var isReading = false

    let image: CGImage
    private let vietnameseFirst: Bool
    private let remember: (String) -> Void
    private var reading: Task<Void, Never>?

    init(_ image: CGImage, language: String, vietnameseFirst: Bool, remember: @escaping (String) -> Void = { _ in }) {
        self.image = image
        self.language = language
        self.vietnameseFirst = vietnameseFirst
        self.remember = remember
        read()
    }

    /// Reads the picture again, as `language`.
    func read() {
        reading?.cancel()
        isReading = true
        let image = image, language = language, vietnameseFirst = vietnameseFirst
        reading = Task { [weak self] in
            let lines = language == "auto"
                ? (try? await TextRecognizer.lines(in: image, vietnameseFirst: vietnameseFirst)) ?? []
                : (try? await TextRecognizer.lines(in: image, language: language)) ?? []
            guard let self, !Task.isCancelled else { return }
            self.lines = lines
            self.text = self.composed
            self.isReading = false
        }
    }

    private var composed: String {
        lines.joined(separator: joinsLines ? " " : "\n")
    }

    /// The languages to choose from: Automatic first, then Vision's, by their names.
    static var choices: [(code: String, name: String)] {
        let locale = Locale(identifier: Localizer.language == .vietnamese ? "vi" : "en")
        let named = TextRecognizer.languages.map { code -> (String, String) in
            // Vision's "vi-VT" isn't a locale; its language is.
            let identifier = code == "vi-VT" ? "vi" : code
            return (code, locale.localizedString(forIdentifier: identifier) ?? code)
        }
        return [("auto", L("Automatic (any script)"))] + named.sorted { $0.1.localizedCompare($1.1) == .orderedAscending }
    }
}

/// The text read from a capture (⌥⇧3), in a window like iShot's: the picture, the language, the text to check or
/// edit, and Copy (⌘↩). Esc closes it without copying. It looks like LongoKit's other windows and follows the app's
/// appearance.
@MainActor
enum TextWindow {
    private static var windows: [NSWindow] = []

    static func open(_ reading: TextReading, scale: CGFloat, on screen: NSScreen?, copied: @escaping (String) -> Void) {
        let size = CGSize(width: 900, height: 540)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        let view = TextWindowView(reading: reading, scale: scale) { [weak window] text in
            if let text { copied(text) }
            window?.close()
        }
        let host = NSHostingController(rootView: view)
        host.sizingOptions = []
        window.contentViewController = host
        // The title is drawn in the header, next to the window's buttons.
        window.title = L("Picture to Text")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.setContentSize(size)
        window.contentMinSize = CGSize(width: 760, height: 440)
        // Centered on the screen the text was taken from.
        let visible = (screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        window.setFrameOrigin(CGPoint(x: visible.midX - window.frame.width / 2, y: visible.midY - window.frame.height / 2))
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { note in
            MainActor.assumeIsolated { windows.removeAll { $0 === note.object as? NSWindow } }
        }
        windows.append(window)
        // Over other apps' windows and in front even if macOS doesn't bring a menu bar app forward at once.
        window.level = .floating
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

struct TextWindowView: View {
    @ObservedObject var reading: TextReading
    let scale: CGFloat
    /// The text to copy, or nil to close without copying.
    let finish: (String?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            HStack(alignment: .top, spacing: 14) {
                picture
                textCard.frame(width: 420)
            }
            .padding(16)
            .frame(maxHeight: .infinity)
            Hairline()
            footer
        }
        .background(LinearGradient(colors: [Theme.canvasTop, Theme.canvas], startPoint: .top, endPoint: .bottom))
        .ignoresSafeArea()
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.accentGradient)
                Image(systemName: "text.viewfinder").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: 26, height: 26)
            .shadow(color: Theme.solar.opacity(0.35), radius: 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(L("Picture to Text")).font(.ui(13, .semibold)).foregroundStyle(Theme.text)
                Text(status).font(.ui(11)).foregroundStyle(Theme.textMuted).lineLimit(1)
            }
            Spacer(minLength: 12)
            Text(L("Read as")).font(.ui(11)).foregroundStyle(Theme.textMuted)
            LanguageMenu(selection: $reading.language)
        }
        // Clear of the window's buttons on the left.
        .padding(.leading, 84)
        .padding(.trailing, 16)
        .frame(height: 52)
        .background(Theme.chrome)
    }

    private var status: String {
        if reading.isReading { return L("Reading…") }
        let lines = reading.lines.count == 1 ? L("1 line") : L("%d lines", reading.lines.count)
        return lines + " · " + L("%d characters", reading.text.count)
    }

    // MARK: Picture

    /// The capture, fitted into its side, never larger than on screen, with its size.
    private var picture: some View {
        let width = CGFloat(reading.image.width) / scale, height = CGFloat(reading.image.height) / scale
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return GeometryReader { geometry in
            let factor = min(1, geometry.size.width / max(width, 1), geometry.size.height / max(height, 1))
            Image(decorative: reading.image, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: width * factor, height: height * factor)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.hairline))
                .shadow(color: Theme.cardShadow, radius: 10, y: 3)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .padding(18)
        .padding(.bottom, 14)
        .background(shape.fill(Theme.well))
        .overlay(shape.strokeBorder(Theme.hairline))
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 5) {
                Image(systemName: "photo").font(.system(size: 9, weight: .semibold))
                Text("\(Int(width.rounded())) × \(Int(height.rounded()))").font(.mono(10))
            }
            .foregroundStyle(Theme.textMuted)
            .padding(10)
        }
        .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Text

    private var textCard: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "text.alignleft").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.violet)
                Text(L("Text")).font(.ui(12, .semibold)).foregroundStyle(Theme.text)
                Spacer()
                CheckChip(L("Join lines"), isOn: reading.joinsLines, help: L("Lines run into one paragraph, for text broken across lines")) {
                    reading.joinsLines.toggle()
                }
                .disabled(reading.lines.count < 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Hairline()
            ZStack {
                TextEditor(text: $reading.text)
                    .font(.ui(14))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.text)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                    .opacity(reading.isReading ? 0.3 : 1)
                if reading.isReading {
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(L("Reading…")).font(.ui(11)).foregroundStyle(Theme.textMuted)
                    }
                } else if reading.lines.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "text.magnifyingglass").font(.system(size: 22)).foregroundStyle(Theme.textFaint)
                        Text(L("No text found")).font(.ui(13, .medium)).foregroundStyle(Theme.textSecondary)
                        Text(L("Try another language, a larger area, or text with more contrast."))
                            .font(.ui(11)).foregroundStyle(Theme.textMuted).multilineTextAlignment(.center)
                    }
                    .padding(28)
                    .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(shape.fill(Theme.island).shadow(color: Theme.cardShadow, radius: 8, y: 2))
        .overlay(shape.strokeBorder(Theme.hairline))
        .frame(maxHeight: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "pencil").font(.system(size: 10, weight: .semibold))
                Text(L("Edit the text before copying")).font(.ui(11))
            }
            .foregroundStyle(Theme.textFaint)
            Spacer()
            Button { finish(nil) } label: { Keyed(L("Close"), key: "esc") }
                .buttonStyle(.ghost)
                .keyboardShortcut(.cancelAction)
            Button { finish(reading.text) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc").font(.system(size: 11, weight: .semibold))
                    Keyed(L("Copy"), key: "⌘↩", light: true)
                }
            }
            .buttonStyle(.primary)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(reading.text.isEmpty)
            .opacity(reading.text.isEmpty ? 0.5 : 1)
            .help(L("Copy the text and close"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.chrome)
    }
}

/// A button's word and its key, the key quieter.
private struct Keyed: View {
    let title: String
    let key: String
    var light = false

    init(_ title: String, key: String, light: Bool = false) {
        self.title = title
        self.key = key
        self.light = light
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Text(key).font(.mono(10)).opacity(light ? 0.75 : 0.5)
        }
    }
}

/// The language to read as: the current one in a pill, the choices in a popover with a search field (Vision knows
/// some thirty, too many for a plain list).
private struct LanguageMenu: View {
    @Binding var selection: String
    @State private var open = false
    @State private var hovering = false
    @State private var search = ""
    @FocusState private var searching: Bool

    private var choices: [(code: String, name: String)] { TextReading.choices }

    private var name: String {
        choices.first { $0.code == selection }?.name ?? selection
    }

    private var found: [(code: String, name: String)] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return choices }
        return choices.filter {
            $0.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || $0.code.range(of: query, options: .caseInsensitive) != nil
        }
    }

    var body: some View {
        let shape = Capsule()
        Button { open.toggle() } label: {
            HStack(spacing: 7) {
                Image(systemName: selection == "auto" ? "sparkles" : "globe")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.solar)
                Text(name).font(.ui(12, .medium)).foregroundStyle(Theme.text).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(shape.fill(hovering || open ? Theme.hover : Theme.tint(0.04)))
            .overlay(shape.strokeBorder(open ? Theme.solar.opacity(0.6) : Theme.tint(0.1)))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .popover(isPresented: $open, arrowEdge: .bottom) { list }
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                TextField(L("Search languages"), text: $search)
                    .textFieldStyle(.plain)
                    .font(.ui(12))
                    .focused($searching)
                    .onSubmit { if let first = found.first { pick(first.code) } }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.well))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.hairline))
            .padding(8)
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(found, id: \.code) { choice in
                        LanguageRow(name: choice.name, detail: choice.code == "auto" ? L("Vietnamese marks kept on Latin text") : nil,
                                    symbol: choice.code == "auto" ? "sparkles" : nil, selected: choice.code == selection) {
                            pick(choice.code)
                        }
                        if choice.code == "auto" && found.count > 1 { Hairline().padding(.vertical, 3) }
                    }
                    if found.isEmpty {
                        Text(L("No languages match")).font(.ui(11)).foregroundStyle(Theme.textMuted)
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                    }
                }
                .padding(6)
            }
            .frame(height: 300)
        }
        .frame(width: 270)
        .background(Theme.popoverTop)
        .onAppear {
            search = ""
            searching = true
        }
    }

    private func pick(_ code: String) {
        open = false
        selection = code
    }
}

private struct LanguageRow: View {
    let name: String
    var detail: String?
    var symbol: String?
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(Theme.solar).frame(width: 16)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.ui(12, selected ? .semibold : .medium))
                        .foregroundStyle(selected ? Theme.solar : Theme.text).lineLimit(1)
                    if let detail { Text(detail).font(.ui(10)).foregroundStyle(Theme.textMuted).lineLimit(1) }
                }
                Spacer(minLength: 6)
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.solar)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? Theme.tint(0.06) : hovering ? Theme.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

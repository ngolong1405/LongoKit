import LongoKitUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - General

struct GeneralTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            SettingsGroup(L("Status")) {
                PowerRow(name: AppInfo.name, isOn: model.isEnabled,
                         help: model.isEnabled ? L("Devices nearby can find this Mac and send it files; you can send to them.")
                             : L("Off: this Mac can't be found and takes no files.")) {
                    model.isEnabled.toggle()
                }
            }
            ProblemBanner()
            SettingsGroup(L("This Mac")) {
                CompactRow(L("Device name"), help: L("What others see when they look for this Mac.")) {
                    CommitField(text: model.alias, width: 200) { model.alias = $0 }
                }
                CompactRow(L("Save to"), help: (model.folder.path as NSString).abbreviatingWithTildeInPath) {
                    HStack(spacing: 6) {
                        Button(L("Change…"), action: pickFolder).buttonStyle(GhostButtonStyle(compact: true))
                        Button { NSWorkspace.shared.open(model.folder) } label: { Image(systemName: "folder") }
                            .buttonStyle(GhostButtonStyle(compact: true))
                            .help(L("Open the folder"))
                    }
                }
            }
            SettingsGroup(L("Receiving")) {
                CompactRow(L("Require a PIN"), help: L("Senders type it before their files are offered to you.")) {
                    HStack(spacing: 10) {
                        if let pin = model.pin {
                            CommitField(text: pin, width: 80) { model.pin = $0 }
                        }
                        DSSwitch(isOn: model.pin != nil) {
                            model.pin = model.pin == nil ? String(Int.random(in: 1000...9999)) : nil
                        }
                    }
                }
            }
            SettingsGroup(L("Trusted devices")) {
                if model.trusted.isEmpty {
                    CompactRow(L("None yet"), help: L("Turn on Always accept in a device's chat, and its files come in without asking.")) { EmptyView() }
                }
                ForEach(model.trusted, id: \.fingerprint) { device in
                    CompactRow(device.alias) {
                        Button(L("Forget")) { model.forget(device) }.buttonStyle(GhostButtonStyle(compact: true))
                    }
                }
            }
            AppBehaviorRows(language: $model.language, appearance: $model.appearance, startAtLogin: model.startAtLogin,
                            setStartAtLogin: model.setStartAtLogin, showMenuBarIcon: $model.showMenuBarIcon,
                            menuBarHelp: L("Devices nearby and sending from the menu bar."))
            Text(L("Works with LocalSend on phones, Windows and Linux, on the same Wi-Fi or network."))
                .font(.ui(11))
                .foregroundStyle(Theme.textFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = model.folder
        panel.prompt = L("Choose")
        panel.message = L("Save received files to")
        if panel.runModal() == .OK, let url = panel.url { model.folder = url }
    }
}

/// Why it can't receive, when something's wrong.
struct ProblemBanner: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let problem = model.problem {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
                Text(problem.hasPrefix("Port") ? L(problem, ShareProtocol.port) : L(problem, model.problemDetail))
                    .font(.ui(12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.amber.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.amber.opacity(0.4)))
        }
    }
}

/// A text box whose text is taken on Return or when it's left, not at every key.
struct CommitField: View {
    let text: String
    var width: CGFloat = 200
    var placeholder = ""
    let commit: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool
    @Environment(\.rendersFlat) private var rendersFlat

    var body: some View {
        // Snapshots can't draw a text field (an AppKit view): its text stands in.
        if rendersFlat {
            Text(text.isEmpty ? placeholder : text)
                .font(.ui(13))
                .foregroundStyle(text.isEmpty ? Theme.textFaint : Theme.text)
                .padding(.horizontal, 9)
                .frame(width: width, height: 28, alignment: .leading)
                .recessed(radius: 8)
        } else {
            field
        }
    }

    private var field: some View {
        TextField(placeholder, text: $draft)
            .textFieldStyle(.plain)
            .font(.ui(13))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 9)
            .frame(width: width, height: 28)
            .recessed(radius: 8)
            .focused($focused)
            .onAppear { draft = text }
            .onChange(of: text) { draft = $0 }
            .onSubmit { commit(draft) }
            .onChange(of: focused) { if !$0 && draft != text { commit(draft) } }
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovered ? Theme.text : Theme.textMuted)
                .frame(width: 28, height: 28)
                .background(Circle().fill(hovered ? Theme.tint(0.1) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
    }
}

struct DeviceBadge: View {
    let info: DeviceInfo
    let size: CGFloat

    var body: some View {
        Image(systemName: Pretty.symbol(info))
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(Theme.violetLight)
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.tint(0.08)))
    }
}

struct EmptyDevices: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(!model.isEnabled ? L("Longo Share is off.") : model.isScanning ? L("Looking for devices…") : L("No devices found yet."))
                .font(.ui(13, .medium))
                .foregroundStyle(Theme.text)
            Text(L("Open LocalSend or Longo Share on the other device, on the same Wi-Fi."))
                .font(.ui(11.5))
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
    }
}

// MARK: - About

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 10) {
                AppLogo(size: 72)
                Text(AppInfo.name).font(.display(22, .bold)).foregroundStyle(Theme.text)
                Chip("v\(AppInfo.version) beta", tone: .solar)
                Text(L("Files and text between your devices nearby: Macs, Windows PCs, phones. Works with LocalSend."))
                    .font(.ui(12))
                    .foregroundStyle(Theme.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            .frame(maxWidth: .infinity)
            .panel(padding: 24)
            VStack(spacing: 0) {
                LinkRow(symbol: "chevron.left.forwardslash.chevron.right", title: "GitHub", detail: "ngolong1405/LongoKit", url: AppInfo.repo)
                Hairline()
                LinkRow(symbol: "doc.text", title: L("License"), detail: "Source-available", url: AppInfo.license)
            }
            .panel(padding: 0)
            Text(L("Part of LongoKit · Crafted by %@", AppInfo.author)).font(.mono(10)).foregroundStyle(Theme.textFaint)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}

private struct LinkRow: View {
    let symbol: String
    let title: String
    let detail: String
    let url: URL

    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).foregroundStyle(Theme.violet).frame(width: 22)
                Text(title).font(.ui(13, .medium)).foregroundStyle(Theme.text)
                Spacer()
                Text(detail).font(.mono(11)).foregroundStyle(Theme.textMuted)
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.textFaint)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Showing things

enum Pretty {
    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func symbol(_ info: DeviceInfo) -> String {
        switch info.deviceType {
        case "mobile": return "iphone"
        case "tablet": return "ipad"
        case "web": return "globe"
        case "headless", "server": return "server.rack"
        default: return info.deviceModel == "Windows" || info.deviceModel == "Linux" ? "pc" : "laptopcomputer"
        }
    }

    static func fileSymbol(_ type: String) -> String {
        if type.hasPrefix("image/") { return "photo" }
        if type.hasPrefix("video/") { return "film" }
        if type.hasPrefix("audio/") { return "waveform" }
        if type.hasPrefix("text/") { return "doc.text" }
        return "doc"
    }

    static func shorten(_ text: String, _ length: Int) -> String {
        let line = text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return line.count <= length ? line : String(line.prefix(length - 1)) + "…"
    }
}

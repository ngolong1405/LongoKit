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

// MARK: - Devices

struct DevicesTab: View {
    @EnvironmentObject private var model: AppModel
    @State private var address = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: L("NEARBY DEVICES (%d)", model.peers.count))
                Spacer()
                Button { Task { await model.refresh() } } label: {
                    Label(model.isScanning ? L("Looking…") : L("Look Again"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(GhostButtonStyle(compact: true))
                .disabled(!model.isEnabled || model.isScanning)
            }
            ActivityView()
            VStack(spacing: 8) {
                ForEach(model.peers) { peer in PeerRow(peer: peer, compact: false) }
                if model.peers.isEmpty { EmptyDevices() }
            }
            .panel(padding: 10)

            HStack(spacing: 12) {
                Image(systemName: "network").foregroundStyle(Theme.violet).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Add by address")).font(.ui(13, .medium)).foregroundStyle(Theme.text)
                    Text(L("Not in the list? Type its IP address, as LocalSend shows it.")).font(.ui(11)).foregroundStyle(Theme.textMuted)
                }
                Spacer()
                CommitField(text: address, width: 150, placeholder: "192.168.1.20") { typed in
                    Task { await model.connect(typed) }
                }
            }
            .panel(padding: 14)
            .disabled(!model.isEnabled)

            SectionLabel(text: L("TRUSTED DEVICES"))
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.trusted, id: \.fingerprint) { device in
                    HStack {
                        Image(systemName: "checkmark.shield.fill").foregroundStyle(Theme.emerald)
                        Text(device.alias).font(.ui(13, .medium)).foregroundStyle(Theme.text)
                        Spacer()
                        Button(L("Forget")) { model.forget(device) }.buttonStyle(GhostButtonStyle(compact: true))
                    }
                }
                if model.trusted.isEmpty {
                    Text(L("None. Turn on Always accept when a device sends you files, and its files come in without asking."))
                        .font(.ui(12))
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .panel(padding: 14)
            Text(L("This Mac: %@ · %@", model.alias, "\(model.address):\(ShareProtocol.port)"))
                .font(.mono(10))
                .foregroundStyle(Theme.textFaint)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}

/// A device: what it is, and sending to it. Files dropped on it are sent; a click picks some.
struct PeerRow: View {
    @EnvironmentObject private var model: AppModel
    let peer: Peer
    let compact: Bool
    @State private var hovered = false
    @State private var targeted = false
    @Environment(\.rendersFlat) private var rendersFlat

    var body: some View {
        let busy = model.current != nil
        let lit = (hovered || targeted) && !busy
        HStack(spacing: 12) {
            DeviceBadge(info: peer.info, size: compact ? 32 : 38)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(peer.info.alias).font(.ui(13, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    if model.isTrusted(peer) { Chip(L("Trusted"), tone: .emerald) }
                }
                Text([peer.info.deviceModel, peer.address].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.ui(11))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if compact {
                IconButton(symbol: "text.bubble", help: L("Send text")) { Panels.sendText(to: peer, model: model) }
                IconButton(symbol: "paperplane.fill", help: L("Send files")) { pickFiles() }
            } else {
                Button { Panels.sendText(to: peer, model: model) } label: { Label(L("Text"), systemImage: "text.bubble") }
                    .buttonStyle(GhostButtonStyle(compact: true))
                Button { pickFiles() } label: { Label(L("Send Files"), systemImage: "paperplane.fill") }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(lit ? Theme.hover : Theme.tint(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(lit ? Theme.violet : Theme.hairline))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { if !busy { pickFiles() } }
        .modifier(DropFiles(enabled: !rendersFlat, targeted: $targeted) { urls in
            if !busy { model.send(urls, to: peer) }
        })
        .opacity(busy ? 0.55 : 1)
        .help(L("Click to pick files, or drop them here"))
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = L("Send")
        panel.message = L("Send to %@", peer.info.alias)
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { model.send(panel.urls, to: peer) }
    }

    static func urls(from providers: [NSItemProvider], done: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { done(urls) }
    }
}

/// Files dropped from Finder (left out of snapshots, which can't draw a drop target).
private struct DropFiles: ViewModifier {
    let enabled: Bool
    @Binding var targeted: Bool
    let dropped: ([URL]) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                PeerRow.urls(from: providers, done: dropped)
                return true
            }
        } else {
            content
        }
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

/// The transfer under way, or how the last one went.
struct ActivityView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if let transfer = model.current {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: transfer.sending ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                        .foregroundStyle(transfer.sending ? Theme.solar : Theme.emerald)
                    Text(transfer.sending ? L("Sending to %@", transfer.device)
                         : transfer.device.isEmpty ? L("Receiving") : L("Receiving from %@", transfer.device))
                        .font(.ui(12.5, .semibold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Button(L("Cancel"), action: model.cancel).buttonStyle(GhostButtonStyle(compact: true))
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.tint(0.1))
                        Capsule().fill(Theme.accentGradient).frame(width: max(6, geometry.size.width * transfer.fraction))
                    }
                }
                .frame(height: 6)
                Text("\(Pretty.size(transfer.done)) / \(Pretty.size(transfer.total)) · \(Int(transfer.fraction * 100))%")
                    .font(.mono(10.5))
                    .foregroundStyle(Theme.textMuted)
            }
            .panel(padding: 12)
        } else if let notice = model.notice {
            HStack(spacing: 8) {
                Image(systemName: notice.good ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(notice.good ? Theme.emerald : Theme.amber)
                Text(notice.device.isEmpty ? L(notice.text) : L(notice.text, notice.device))
                    .font(.ui(12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

// MARK: - History

struct HistoryTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: L("HISTORY (%d)", model.history.count))
                Spacer()
                if !model.history.isEmpty {
                    Button { model.clearHistory() } label: { Label(L("Clear"), systemImage: "trash") }
                        .buttonStyle(GhostButtonStyle(compact: true))
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(model.history.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Hairline().padding(.vertical, 10) }
                    HistoryRow(item: item)
                }
                if model.history.isEmpty {
                    Text(L("Nothing sent or received yet.")).font(.ui(12)).foregroundStyle(Theme.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .panel(padding: 14)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}

private struct HistoryRow: View {
    @EnvironmentObject private var model: AppModel
    let item: HistoryItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.sent ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(item.sent ? Theme.solar : Theme.emerald)
            VStack(alignment: .leading, spacing: 2) {
                Text(what).font(.ui(13, .medium)).foregroundStyle(Theme.text).lineLimit(1)
                Text("\(item.sent ? L("To %@", item.device) : L("From %@", item.device)) · \(item.time.formatted(date: .abbreviated, time: .shortened))")
                    .font(.ui(11))
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
            if let text = item.text {
                IconButton(symbol: "doc.on.doc", help: L("Copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            } else if !item.sent {
                IconButton(symbol: "magnifyingglass", help: L("Show in Finder")) { reveal() }
            }
        }
    }

    private var what: String {
        if let text = item.text { return "“\(Pretty.shorten(text, 60))”" }
        if item.files.isEmpty { return L("Files") }
        if item.files.count == 1 { return item.files[0] }
        return L("%@ and %d more", item.files[0], item.files.count - 1)
    }

    private func reveal() {
        let folder = URL(fileURLWithPath: item.folder ?? model.folder.path)
        let files = item.files.map { folder.appendingPathComponent($0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        if files.isEmpty { NSWorkspace.shared.open(folder) } else { NSWorkspace.shared.activateFileViewerSelecting(files) }
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

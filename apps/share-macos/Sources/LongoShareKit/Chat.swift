import LongoKitUI
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// The Devices page: the devices down the left, and a chat with the one picked, where files and text come and go.
struct DevicesTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            DeviceList().frame(width: 232)
            Rectangle().fill(Theme.hairline).frame(width: 1)
            Group {
                if let contact = model.contact(model.selected) {
                    ChatView(contact: contact).id(contact.id)
                } else {
                    NoChat()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 580)
    }
}

// MARK: - The list

private struct DeviceList: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SectionLabel(text: model.isScanning ? L("LOOKING…") : L("DEVICES"))
                Spacer()
                IconButton(symbol: "arrow.clockwise", help: L("Look Again")) { Task { await model.refresh() } }
                    .disabled(!model.isEnabled || model.isScanning)
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            Scrolling {
                VStack(spacing: 2) {
                    ForEach(model.contacts) { contact in DeviceListRow(contact: contact) }
                    if model.contacts.isEmpty { EmptyDevices().padding(.top, 4) }
                }
                .padding(.horizontal, 8)
            }
            Hairline()
            VStack(alignment: .leading, spacing: 6) {
                CommitField(text: "", width: 214, placeholder: L("Add by IP address")) { typed in
                    Task { await model.connect(typed) }
                }
                if let failed = model.lastAddressFailed {
                    Text(L("Nothing answered at %@.", failed)).font(.ui(10.5)).foregroundStyle(Theme.amber)
                }
            }
            .padding(9)
            .disabled(!model.isEnabled)
        }
    }
}

private struct DeviceListRow: View {
    @EnvironmentObject private var model: AppModel
    let contact: Contact
    @State private var hovered = false
    @State private var targeted = false
    @Environment(\.rendersFlat) private var rendersFlat

    var body: some View {
        let isSelected = model.selected == contact.id
        HStack(spacing: 10) {
            DeviceBadge(info: contact.info, size: 34)
                .overlay(alignment: .bottomTrailing) {
                    Circle().fill(contact.isOnline ? Theme.emerald : Theme.textFaint)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().strokeBorder(Theme.canvas, lineWidth: 2))
                }
                .opacity(contact.isOnline ? 1 : 0.6)
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.info.alias).font(.ui(12.5, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text(subtitle).font(.ui(11)).foregroundStyle(Theme.textMuted).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let unread = contact.conversation?.unread, unread > 0 {
                Text("\(unread)").font(.mono(10, .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 6).frame(minWidth: 18, minHeight: 18)
                    .background(Capsule().fill(Theme.solar))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isSelected ? Theme.hover : hovered || targeted ? Theme.tint(0.05) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(targeted ? Theme.violet : .clear))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { model.selected = contact.id }
        .modifier(DropFiles(enabled: !rendersFlat && contact.isOnline, targeted: $targeted) { urls in
            if let peer = contact.peer { model.send(urls, to: peer) }
        })
    }

    private var subtitle: String {
        if let last = contact.conversation?.items.last { return Preview.line(last) }
        return contact.isOnline ? (contact.info.deviceModel ?? "") : L("Not nearby")
    }
}

private struct NoChat: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 30)).foregroundStyle(Theme.textFaint)
            Text(model.contacts.isEmpty ? L("No devices yet") : L("Pick a device"))
                .font(.display(15, .semibold)).foregroundStyle(Theme.text)
            Text(L("Open LocalSend or Longo Share on the other device, on the same Wi-Fi."))
                .font(.ui(12)).foregroundStyle(Theme.textMuted).multilineTextAlignment(.center).frame(maxWidth: 300)
            ProblemBanner().frame(maxWidth: 360)
        }
        .padding(24)
    }
}

// MARK: - A chat

private struct ChatView: View {
    @EnvironmentObject private var model: AppModel
    let contact: Contact
    @State private var draft = ""
    @State private var targeted = false
    @Environment(\.rendersFlat) private var rendersFlat

    var body: some View {
        let items = contact.conversation?.items ?? []
        VStack(spacing: 0) {
            header
            Hairline()
            ScrollViewReader { reader in
                Scrolling(bottom: true) {
                    LazyVStack(spacing: 12) {
                        if items.isEmpty { empty }
                        ForEach(items) { item in
                            Bubble(item: item, contact: contact).id(item.id)
                        }
                    }
                    .padding(16)
                }
                .onAppear { if let last = items.last { reader.scrollTo(last.id, anchor: .bottom) } }
                .onChange(of: items.count) { _ in
                    if let last = items.last { withAnimation(Motion.quick) { reader.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            Hairline()
            composer
        }
        .overlay {
            if targeted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.violet, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.violet.opacity(0.08)))
                    .overlay(Label(L("Drop to send to %@", contact.info.alias), systemImage: "arrow.down.doc")
                        .font(.ui(13, .semibold)).foregroundStyle(Theme.violetLight))
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .modifier(DropFiles(enabled: !rendersFlat && contact.isOnline, targeted: $targeted) { urls in
            if let peer = contact.peer { model.send(urls, to: peer) }
        })
    }

    private var header: some View {
        HStack(spacing: 10) {
            DeviceBadge(info: contact.info, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(contact.info.alias).font(.ui(13.5, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text(contact.peer.map { [contact.info.deviceModel, $0.address].compactMap { $0 }.joined(separator: " · ") } ?? L("Not nearby"))
                    .font(.ui(11)).foregroundStyle(contact.isOnline ? Theme.textMuted : Theme.amber).lineLimit(1)
            }
            Spacer()
            if !contact.info.fingerprint.isEmpty {
                let trusted = model.isTrusted(contact.info)
                Button { model.setTrusted(contact.info, !trusted) } label: {
                    Label(L("Always accept"), systemImage: trusted ? "checkmark.shield.fill" : "shield")
                        .font(.ui(11, .medium))
                        .foregroundStyle(trusted ? Theme.emerald : Theme.textMuted)
                        .padding(.horizontal, 9).frame(height: 26)
                        .background(Capsule().fill(trusted ? Theme.emerald.opacity(0.12) : Theme.tint(0.05)))
                }
                .buttonStyle(.plain)
                .help(trusted ? L("Files from this device come in without asking. Click to ask again.")
                      : L("Take files from this device without asking."))
            }
            if !(contact.conversation?.items.isEmpty ?? true) {
                IconButton(symbol: "trash", help: L("Clear this chat")) { model.clear(contact.id) }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "paperplane").font(.system(size: 26)).foregroundStyle(Theme.textFaint)
            Text(contact.isOnline ? L("Drop files here, or type a message, to send them to %@.", contact.info.alias)
                 : L("%@ isn't on this network now.", contact.info.alias))
                .font(.ui(12)).foregroundStyle(Theme.textMuted).multilineTextAlignment(.center).frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            IconButton(symbol: "paperclip", help: L("Send files")) { pickFiles() }
            Group {
                if rendersFlat {
                    Text(draft.isEmpty ? L("Message %@", contact.info.alias) : draft)
                        .foregroundStyle(draft.isEmpty ? Theme.textFaint : Theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField(L("Message %@", contact.info.alias), text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .onSubmit(sendDraft)
                }
            }
            .font(.ui(13))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.tint(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.hairline))
            Button(action: sendDraft) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AnyShapeStyle(Theme.tint(0.15)) : AnyShapeStyle(Theme.accentGradient)))
            }
            .buttonStyle(.plain)
            .help(L("Send"))
        }
        .padding(10)
        .disabled(!contact.isOnline || !model.isEnabled)
        .opacity(contact.isOnline ? 1 : 0.5)
    }

    private func sendDraft() {
        guard let peer = contact.peer, !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.send(text: draft, to: peer)
        draft = ""
    }

    private func pickFiles() {
        guard let peer = contact.peer else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = L("Send")
        panel.message = L("Send to %@", contact.info.alias)
        if panel.runModal() == .OK { model.send(panel.urls, to: peer) }
    }
}

// MARK: - A message

private struct Bubble: View {
    @EnvironmentObject private var model: AppModel
    let item: ChatItem
    let contact: Contact

    var body: some View {
        HStack {
            if item.sent { Spacer(minLength: 60) }
            VStack(alignment: item.sent ? .trailing : .leading, spacing: 4) {
                if let text = item.text { textBubble(text) } else { FilesBubble(item: item, contact: contact) }
                footer
            }
            if !item.sent { Spacer(minLength: 60) }
        }
    }

    private func textBubble(_ text: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Text(Preview.linked(text))
            .font(.ui(13))
            .foregroundStyle(item.sent ? Color.white : Theme.text)
            .tint(item.sent ? .white : Theme.violetLight)
            .textSelection(.enabled)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(shape.fill(item.sent ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.tint(0.08))))
            .opacity(item.state == .failed || item.state == .declined ? 0.6 : 1)
            .contextMenu {
                Button(L("Copy")) { Preview.copy(text) }
            }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(item.time.formatted(date: Calendar.current.isDateInToday(item.time) ? .omitted : .abbreviated, time: .shortened))
            if let text = item.text, !item.sent {
                Button(L("Copy")) { Preview.copy(text) }.buttonStyle(.plain).foregroundStyle(Theme.violetLight)
            }
            if item.text != nil, item.sent { Image(systemName: Preview.symbol(item.state)).foregroundStyle(Preview.color(item.state)) }
            if item.text != nil, item.sent, item.state == .declined || item.state == .failed {
                Text(Preview.status(item, contact: contact.info.alias)).foregroundStyle(Theme.amber)
            }
        }
        .font(.ui(10))
        .foregroundStyle(Theme.textFaint)
        .padding(.horizontal, 4)
    }
}

private struct FilesBubble: View {
    @EnvironmentObject private var model: AppModel
    let item: ChatItem
    let contact: Contact
    @State private var always = false
    @State private var pin = ""

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            if let big = bigPreview {
                Thumbnail(path: big, fallback: Preview.fileSymbol(item.files[0].name), large: true)
                    .onTapGesture { NSWorkspace.shared.open(URL(fileURLWithPath: big)) }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(item.files.prefix(5).enumerated()), id: \.offset) { _, file in
                    HStack(spacing: 8) {
                        if bigPreview == nil, let path = file.path {
                            Thumbnail(path: path, fallback: Preview.fileSymbol(file.name), large: false)
                        } else {
                            Image(systemName: Preview.fileSymbol(file.name)).foregroundStyle(Theme.violetLight).frame(width: 16)
                        }
                        Text(file.name).font(.ui(12.5)).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(Pretty.size(file.size)).font(.mono(10)).foregroundStyle(Theme.textMuted)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { if item.state == .done, let path = file.path { NSWorkspace.shared.open(URL(fileURLWithPath: path)) } }
                }
                if item.files.count > 5 {
                    Text(L("and %d more", item.files.count - 5)).font(.ui(11)).foregroundStyle(Theme.textMuted)
                }
            }
            if item.state == .transferring {
                ProgressBar(fraction: item.fraction)
            }
            HStack(spacing: 6) {
                Image(systemName: Preview.symbol(item.state)).foregroundStyle(Preview.color(item.state))
                Text(Preview.status(item, contact: contact.info.alias)).foregroundStyle(Theme.textMuted)
                Spacer(minLength: 8)
                actions
            }
            .font(.ui(11))
            if item.state == .asking { asking }
            if item.state == .pin { pinRow }
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .background(shape.fill(Theme.island))
        .overlay(shape.strokeBorder(item.state == .asking || item.state == .pin ? Theme.violet : item.sent ? Theme.solar.opacity(0.35) : Theme.hairline))
    }

    /// One picture or video on this Mac: shown big.
    private var bigPreview: String? {
        guard item.files.count == 1, let path = item.files[0].path, FileManager.default.fileExists(atPath: path),
              let type = UTType(filenameExtension: (path as NSString).pathExtension),
              type.conforms(to: .image) || type.conforms(to: .movie) else { return nil }
        return path
    }

    @ViewBuilder private var actions: some View {
        switch item.state {
        case .transferring, .waiting:
            Button(L("Cancel")) { model.cancel(item.id) }.buttonStyle(GhostButtonStyle(compact: true))
        case .done where !item.sent:
            Button { reveal() } label: { Label(L("Show in Finder"), systemImage: "magnifyingglass") }
                .buttonStyle(GhostButtonStyle(compact: true))
        default:
            EmptyView()
        }
    }

    private var asking: some View {
        VStack(alignment: .leading, spacing: 10) {
            Hairline()
            HStack(spacing: 8) {
                DSCheckbox(isOn: always) { always.toggle() }
                Text(L("Always accept from %@", contact.info.alias)).font(.ui(11.5)).foregroundStyle(Theme.textSecondary)
                    .onTapGesture { always.toggle() }
            }
            HStack(spacing: 8) {
                Spacer()
                Button(L("Decline")) { model.answer(item.id, accept: false) }.buttonStyle(GhostButtonStyle(compact: true))
                Button { model.answer(item.id, accept: true, always: always) } label: { Label(L("Accept"), systemImage: "arrow.down") }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
            }
        }
    }

    private var pinRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Hairline()
            Text(L("%@ asks for a PIN. It's shown on that device.", contact.info.alias)).font(.ui(11.5)).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                TextField("PIN", text: $pin)
                    .textFieldStyle(.plain)
                    .font(.mono(13))
                    .padding(.horizontal, 9)
                    .frame(width: 100, height: 28)
                    .recessed(radius: 8)
                    .onSubmit { model.answerPin(item.id, pin) }
                Spacer()
                Button(L("Cancel")) { model.answerPin(item.id, nil) }.buttonStyle(GhostButtonStyle(compact: true))
                Button(L("Send")) { model.answerPin(item.id, pin) }.buttonStyle(PrimaryButtonStyle(compact: true))
            }
        }
    }

    private func reveal() {
        let urls = item.files.compactMap { $0.path.map(URL.init(fileURLWithPath:)) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        if urls.isEmpty { NSWorkspace.shared.open(model.folder) } else { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }
}

/// A scroll view; laid out in place for snapshots, which can't draw one's content (the end shown, for a chat).
private struct Scrolling<Content: View>: View {
    var bottom = false
    @ViewBuilder let content: Content
    @Environment(\.rendersFlat) private var rendersFlat

    var body: some View {
        if rendersFlat {
            // Clear space takes the height it's given; the content hangs from its top (or bottom) and is cut there.
            Color.clear
                .overlay(alignment: bottom ? .bottom : .top) { VStack(spacing: 0) { content }.fixedSize(horizontal: false, vertical: true) }
                .clipped()
        } else {
            ScrollView { content }
        }
    }
}

/// A file's Quick Look thumbnail: pictures, videos, PDFs, documents. Its icon until it's made, or if it can't be.
private struct Thumbnail: View {
    let path: String
    let fallback: String
    let large: Bool
    @State private var image: NSImage?
    @Environment(\.displayScale) private var scale

    var body: some View {
        Group {
            if let image {
                if large {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 296, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            } else {
                Image(systemName: fallback).foregroundStyle(Theme.violetLight)
                    .frame(width: large ? 296 : 30, height: large ? 120 : 30)
                    .background(RoundedRectangle(cornerRadius: large ? 10 : 6, style: .continuous).fill(Theme.tint(0.05)))
            }
        }
        .task(id: path) { image = await Thumbnails.image(path, size: large ? CGSize(width: 296, height: 220) : CGSize(width: 30, height: 30), scale: scale) }
    }
}

enum Thumbnails {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(_ path: String, size: CGSize, scale: CGFloat) async -> NSImage? {
        let key = "\(path)|\(Int(size.width))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let request = QLThumbnailGenerator.Request(fileAt: URL(fileURLWithPath: path), size: size, scale: scale, representationTypes: .thumbnail)
        guard let image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.tint(0.1))
                Capsule().fill(Theme.accentGradient).frame(width: max(6, geometry.size.width * fraction))
            }
        }
        .frame(height: 5)
    }
}

/// Files dropped from Finder (left out of snapshots, which can't draw a drop target).
struct DropFiles: ViewModifier {
    let enabled: Bool
    @Binding var targeted: Bool
    let dropped: ([URL]) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                Preview.urls(from: providers, done: dropped)
                return true
            }
        } else {
            content
        }
    }
}

// MARK: - Words for messages

enum Preview {
    /// A message in one line, for the device list.
    static func line(_ item: ChatItem) -> String {
        let arrow = item.sent ? L("You: ") : ""
        if let text = item.text { return arrow + Pretty.shorten(text, 40) }
        if item.state == .asking { return L("Wants to send you files") }
        if item.files.count == 1 { return arrow + item.files[0].name }
        return arrow + L("%d files", item.files.count)
    }

    static func status(_ item: ChatItem, contact: String) -> String {
        let total = Pretty.size(item.total)
        switch item.state {
        case .asking: return item.files.count == 1 ? L("1 file · %@", total) : L("%d files · %@", item.files.count, total)
        case .waiting: return L("Waiting for %@…", contact)
        case .pin: return L("PIN needed")
        case .transferring:
            return "\(item.sent ? L("Sending") : L("Receiving")) · \(Pretty.size(item.done)) / \(total)"
        case .done:
            if item.sent { return item.files.count == 1 ? L("Sent · %@", total) : L("%d files sent · %@", item.files.count, total) }
            let folder = item.files.first?.path.map { URL(fileURLWithPath: $0).deletingLastPathComponent().lastPathComponent } ?? ""
            return L("Saved to %@", folder)
        case .declined: return item.sent ? L("%@ declined", contact) : L("Declined")
        case .failed: return L("Didn't go through")
        case .cancelled: return L("Cancelled")
        }
    }

    static func symbol(_ state: ChatState) -> String {
        switch state {
        case .asking: return "arrow.down.circle"
        case .waiting: return "clock"
        case .pin: return "lock"
        case .transferring: return "arrow.up.arrow.down"
        case .done: return "checkmark.circle.fill"
        case .declined: return "xmark.circle"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "minus.circle"
        }
    }

    static func color(_ state: ChatState) -> Color {
        switch state {
        case .done: return Theme.emerald
        case .declined, .failed: return Theme.amber
        case .asking, .pin, .transferring: return Theme.violetLight
        case .waiting, .cancelled: return Theme.textFaint
        }
    }

    static func fileSymbol(_ name: String) -> String {
        let type = UTType(filenameExtension: (name as NSString).pathExtension)
        if type?.conforms(to: .image) == true { return "photo" }
        if type?.conforms(to: .movie) == true { return "film" }
        if type?.conforms(to: .audio) == true { return "waveform" }
        if type?.conforms(to: .pdf) == true { return "doc.richtext" }
        if type?.conforms(to: .text) == true { return "doc.text" }
        if type?.conforms(to: .archive) == true { return "doc.zipper" }
        return "doc"
    }

    /// Text with its links clickable.
    static func linked(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return result }
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = match.url, let range = Range(match.range, in: text),
                  let start = AttributedString.Index(range.lowerBound, within: result),
                  let end = AttributedString.Index(range.upperBound, within: result) else { continue }
            result[start..<end].link = url
            result[start..<end].underlineStyle = .single
        }
        return result
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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

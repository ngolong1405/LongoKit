import AppKit
import LongoKitUI
import SwiftUI

/// Longo Share's small windows: files coming in, a message, a PIN or some text to type. Each floats above other
/// apps' windows, as it may come up while the person is in one.
@MainActor
enum Panels {
    /// Hooks the model's questions up to these windows.
    static func attach(to model: AppModel) {
        model.ask = { transfer in await incoming(transfer, model: model) }
        model.askPin = { peer in
            await ask(title: L("PIN for %@", peer.info.alias), message: L("%@ asks for a PIN. It's shown on that device.", peer.info.alias),
                      initial: "", action: L("Send"), model: model)
        }
        model.showMessage = { peer, text in message(from: peer, text: text, model: model) }
    }

    // MARK: - Files coming in

    static func incoming(_ transfer: IncomingTransfer, model: AppModel) async -> (accept: Bool, always: Bool) {
        await withCheckedContinuation { continuation in
            var answered = false
            var panel: NSPanel?
            let answer = { (accept: Bool, always: Bool) in
                guard !answered else { return }
                answered = true
                panel?.close()
                continuation.resume(returning: (accept, always))
            }
            panel = show(IncomingView(transfer: transfer, answer: answer), title: L("Files from %@", transfer.from.info.alias), model: model) {
                answer(false, false)
            }
        }
    }

    // MARK: - A message

    static func message(from peer: Peer, text: String, model: AppModel) {
        var panel: NSPanel?
        panel = show(MessageView(from: peer, text: text) { panel?.close() }, title: L("Message from %@", peer.info.alias), model: model) {}
    }

    // MARK: - Typing something

    static func sendText(to peer: Peer, model: AppModel) {
        let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
        Task {
            if let text = await ask(title: L("Send Text to %@", peer.info.alias), message: nil, initial: clipboard, action: L("Send"),
                                    multiline: true, model: model), !text.isEmpty {
                model.send(text: text, to: peer)
            }
        }
    }

    static func addByAddress(model: AppModel) {
        Task {
            if let address = await ask(title: L("Add a Device"),
                                       message: L("Its IP address, as LocalSend shows it (192.168.1.20). Both devices must be on the same network."),
                                       initial: "", action: L("Add"), model: model) {
                await model.connect(address)
            }
        }
    }

    /// A window with a box to type in; nil when it's closed.
    static func ask(title: String, message: String?, initial: String, action: String, multiline: Bool = false, model: AppModel) async -> String? {
        await withCheckedContinuation { continuation in
            var answered = false
            var panel: NSPanel?
            let answer = { (text: String?) in
                guard !answered else { return }
                answered = true
                panel?.close()
                continuation.resume(returning: text)
            }
            panel = show(PromptView(title: title, message: message, initial: initial, action: action, multiline: multiline, answer: answer),
                         title: title, model: model) { answer(nil) }
        }
    }

    // MARK: - The window

    private final class Delegate: NSObject, NSWindowDelegate {
        let closed: () -> Void
        init(closed: @escaping () -> Void) { self.closed = closed }
        func windowWillClose(_ notification: Notification) { closed() }
    }

    private static var delegates: [ObjectIdentifier: Delegate] = [:]

    @discardableResult
    private static func show<V: View>(_ view: V, title: String, model: AppModel, closed: @escaping () -> Void) -> NSPanel {
        let content = view
            .environmentObject(model)
            .padding(20)
            .frame(width: 440)
            .background(LinearGradient(colors: [Theme.popoverTop, Theme.popoverBottom], startPoint: .top, endPoint: .bottom))
        let host = NSHostingController(rootView: content)
        let panel = NSPanel(contentViewController: host)
        panel.styleMask = [.titled, .closable, .fullSizeContentView]
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.title = title
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.appearance = model.appearance.nsAppearance
        let key = ObjectIdentifier(panel)
        let delegate = Delegate { [weak panel] in
            closed()
            if let panel { delegates[ObjectIdentifier(panel)] = nil }
        }
        delegates[key] = delegate
        panel.delegate = delegate
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        return panel
    }
}

struct IncomingView: View {
    let transfer: IncomingTransfer
    let answer: (Bool, Bool) -> Void
    @State private var always = false

    var body: some View {
        let files = transfer.files
        let total = files.reduce(Int64(0)) { $0 + $1.size }
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                DeviceBadge(info: transfer.from.info, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(transfer.from.info.alias).font(.display(15, .semibold)).foregroundStyle(Theme.text)
                    Text(files.count == 1 ? L("wants to send you a file · %@", Pretty.size(total))
                         : L("wants to send you %d files · %@", files.count, Pretty.size(total)))
                        .font(.ui(11.5))
                        .foregroundStyle(Theme.textMuted)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(files.prefix(5)) { file in
                    HStack(spacing: 8) {
                        Image(systemName: Pretty.fileSymbol(file.fileType)).foregroundStyle(Theme.violetLight).frame(width: 16)
                        Text(file.fileName).font(.ui(12.5)).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(Pretty.size(file.size)).font(.mono(10.5)).foregroundStyle(Theme.textMuted)
                    }
                }
                if files.count > 5 {
                    Text(L("and %d more", files.count - 5)).font(.ui(11.5)).foregroundStyle(Theme.textMuted)
                }
            }
            .padding(12)
            .recessed(radius: 10)
            CompactRow(L("Always accept from this device"), help: L("Its files come in without asking from now on.")) {
                DSSwitch(isOn: $always)
            }
            HStack(spacing: 8) {
                Spacer()
                Button(L("Decline")) { answer(false, false) }
                    .buttonStyle(.ghost)
                    .keyboardShortcut(.cancelAction)
                Button { answer(true, always) } label: { Label(L("Accept"), systemImage: "arrow.down.circle") }
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

struct MessageView: View {
    let from: Peer
    let text: String
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                DeviceBadge(info: from.info, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(from.info.alias).font(.display(15, .semibold)).foregroundStyle(Theme.text)
                    Text(L("sent you a message")).font(.ui(11.5)).foregroundStyle(Theme.textMuted)
                }
            }
            ScrollView {
                Text(text)
                    .font(.ui(14))
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 240)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .recessed(radius: 10)
            HStack(spacing: 8) {
                Spacer()
                if let link = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), ["http", "https"].contains(link.scheme ?? "") {
                    Button {
                        NSWorkspace.shared.open(link)
                        close()
                    } label: { Label(L("Open Link"), systemImage: "safari") }
                        .buttonStyle(.ghost)
                }
                Button(L("Close"), action: close).buttonStyle(.ghost).keyboardShortcut(.cancelAction)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    close()
                } label: { Label(L("Copy"), systemImage: "doc.on.doc") }
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

struct PromptView: View {
    let title: String
    let message: String?
    let initial: String
    let action: String
    let multiline: Bool
    let answer: (String?) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.display(15, .semibold)).foregroundStyle(Theme.text)
            if let message {
                Text(message).font(.ui(12)).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            }
            Group {
                if multiline {
                    TextEditor(text: $text)
                        .font(.ui(13))
                        .scrollContentBackground(.hidden)
                        .frame(height: 140)
                } else {
                    TextField("", text: $text)
                        .textFieldStyle(.plain)
                        .font(.ui(13))
                        .frame(height: 28)
                        .onSubmit { answer(text) }
                }
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 9)
            .padding(.vertical, multiline ? 8 : 0)
            .recessed(radius: 8)
            .focused($focused)
            HStack(spacing: 8) {
                if multiline {
                    Text(L("⌘↩ to send")).font(.mono(10)).foregroundStyle(Theme.textFaint)
                }
                Spacer()
                Button(L("Cancel")) { answer(nil) }.buttonStyle(.ghost).keyboardShortcut(.cancelAction)
                Button(action) { answer(text) }
                    .buttonStyle(.primary)
                    .keyboardShortcut(multiline ? KeyboardShortcut(.return, modifiers: .command) : .defaultAction)
            }
        }
        .onAppear {
            text = initial
            focused = true
        }
    }
}

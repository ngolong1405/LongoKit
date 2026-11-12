import AppKit
import Combine
import SwiftUI

/// One LongoKit app as a part a host can run: its own small app, or one app holding several modules.
public protocol LongoModule {
    /// Short, stable id: "mouse", "display", "keys", "shot".
    static var id: String { get }
    /// The module's name inside a host, like "Mouse".
    static var title: String { get }
    /// The stand-alone app's bundle id: where its settings live, and the copy a host must not run beside.
    static var bundleIdentifier: String { get }
    /// The module's translations, read before the shared table.
    static var vietnamese: [String: String] { get }
    /// Folder under Contents/Resources holding the module's own images; empty in its stand-alone app, where they sit
    /// at the top.
    static var resourceFolder: String { get set }
    /// Once at launch, after `Resource.developmentSupport`. The default shares the module's translations with
    /// LongoKitUI's controls and registers the fonts (`prepareShared`); a module with more to do at launch adds to it.
    static func prepare()
    /// Starts the module inside a host app, keeping its settings in `defaults`. Not `live`, it touches nothing on the
    /// Mac (for self-tests and snapshots).
    @MainActor static func host(defaults: UserDefaults, live: Bool) -> any HostedModule
}

public extension LongoModule {
    static func prepare() {
        prepareShared()
    }

    /// The module's translations for LongoKitUI's controls, and the fonts.
    static func prepareShared() {
        Localizer.register(vietnamese)
        Fonts.register()
    }

    /// One of the module's own images, such as "Logo.png".
    static func image(_ name: String) -> NSImage? {
        Resource.image(resourceFolder + name)
    }
}

/// A module running inside a host app: its page in the host's window, its menu, and the settings the host keeps the
/// same in every module.
@MainActor
public protocol HostedModule: AnyObject {
    /// Tabs, page and footer, shown beside the host's sidebar.
    var panel: AnyView { get }
    /// The module's menu bar popover.
    var menu: AnyView { get }
    /// Fires just after anything the host shows about the module may have changed.
    var changes: AnyPublisher<Void, Never> { get }
    var language: AppLanguage { get set }
    var appearance: AppAppearance { get set }
    /// The module's switch: on or off, as the person set it.
    var isOn: Bool { get }
    /// On and working; on but not running means something holds it back, like a missing permission.
    var isRunning: Bool { get }
    /// Turns the module's switch on or off (turning on may ask for a permission).
    func setRunning(_ on: Bool)
    /// What the menu bar should show instead of the host's icon, like a recording's timer; nil otherwise.
    var menuBarImage: NSImage? { get }
    /// Work quitting would cut short, like a recording under way.
    var isBusy: Bool { get }
    /// Called once just before the app quits; `done` runs when the module has finished up.
    func prepareToQuit(_ done: @escaping () -> Void)
}

private struct HostedKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// True inside an app hosting several modules: the module leaves app-wide settings and About to the host.
    var isHosted: Bool {
        get { self[HostedKey.self] }
        set { self[HostedKey.self] = newValue }
    }
}

private struct RendersFlatKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// For snapshots: scroll views lay their content out in place, which ImageRenderer can draw.
    var rendersFlat: Bool {
        get { self[RendersFlatKey.self] }
        set { self[RendersFlatKey.self] = newValue }
    }
}

/// What every module's model has, so `ModelHost` can keep it in step with the host.
@MainActor
public protocol HostableModel: ObservableObject {
    var language: AppLanguage { get set }
    var appearance: AppAppearance { get set }
}

/// A module inside a host app, around its model: the model goes into the module's own views as their environment
/// object, with `\.isHosted` on. Each module only says what's its own.
@MainActor
public final class ModelHost<Model: HostableModel>: HostedModule where Model.ObjectWillChangePublisher == ObservableObjectPublisher {
    public let model: Model
    private let makePanel: () -> AnyView
    private let makeMenu: () -> AnyView
    private let on: (Model) -> Bool
    private let running: (Model) -> Bool
    private let switchRunning: (Model, Bool) -> Void
    private let image: (Model) -> NSImage?
    private let busy: (Model) -> Bool
    private let finish: (Model, @escaping () -> Void) -> Void

    public init<Panel: View, Menu: View>(
        model: Model,
        @ViewBuilder panel: @escaping () -> Panel,
        @ViewBuilder menu: @escaping () -> Menu,
        isOn: ((Model) -> Bool)? = nil,
        isRunning: @escaping (Model) -> Bool = { _ in true },
        setRunning: @escaping (Model, Bool) -> Void = { _, _ in },
        menuBarImage: @escaping (Model) -> NSImage? = { _ in nil },
        isBusy: @escaping (Model) -> Bool = { _ in false },
        prepareToQuit: @escaping (Model, @escaping () -> Void) -> Void = { _, done in done() }
    ) {
        self.model = model
        makePanel = { AnyView(Hosted(model: model, content: panel)) }
        makeMenu = { AnyView(Hosted(model: model, content: menu)) }
        on = isOn ?? isRunning
        running = isRunning
        switchRunning = setRunning
        image = menuBarImage
        busy = isBusy
        finish = prepareToQuit
    }

    public var panel: AnyView { makePanel() }
    public var menu: AnyView { makeMenu() }

    public var changes: AnyPublisher<Void, Never> {
        // objectWillChange fires before the change; deliver it once the new values are in.
        model.objectWillChange.receive(on: DispatchQueue.main).map { _ in }.eraseToAnyPublisher()
    }

    public var language: AppLanguage {
        get { model.language }
        set { if model.language != newValue { model.language = newValue } }
    }

    public var appearance: AppAppearance {
        get { model.appearance }
        set { if model.appearance != newValue { model.appearance = newValue } }
    }

    public var isOn: Bool { on(model) }
    public var isRunning: Bool { running(model) }
    public func setRunning(_ on: Bool) { switchRunning(model, on) }
    public var menuBarImage: NSImage? { image(model) }
    public var isBusy: Bool { busy(model) }

    public func prepareToQuit(_ done: @escaping () -> Void) {
        finish(model, done)
    }
}

/// A module's view with its model, hosted, and rebuilt when the language changes so all L() strings update.
private struct Hosted<Model: HostableModel, Content: View>: View {
    @ObservedObject var model: Model
    let content: () -> Content

    var body: some View {
        content()
            .environmentObject(model)
            .environment(\.isHosted, true)
            .id(model.language)
    }
}

import LongoKitUI
import SwiftUI

/// Quick controls from the menu bar: status, Caps Lock for every keyboard, the Hyper cheat sheet.
struct MenuPopover: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Hairline()

            VStack(alignment: .leading, spacing: 8) {
                Text(L("Caps Lock on all keyboards")).font(.ui(12, .medium)).foregroundStyle(Theme.text)
                Segmented(options: CapsMode.allCases,
                          selection: Binding(get: { model.shared.caps }, set: { mode in model.change(nil) { $0.caps = mode } }),
                          title: { $0.title }, stretch: true)
                Text(model.shared.caps.detail).font(.ui(11)).foregroundStyle(Theme.textMuted)
            }
            .disabled(!model.isEnabled)
            .opacity(model.isEnabled ? 1 : 0.45)

            if model.usesHyper {
                Hairline()
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Hyper layer")).font(.ui(12, .medium)).foregroundStyle(Theme.text)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 4) {
                        ForEach(model.hyper) { binding in
                            HStack(spacing: 6) {
                                Text(binding.trigger == .space ? "Space" : binding.trigger.name)
                                    .font(.mono(10, .bold)).foregroundStyle(Theme.solar)
                                    .frame(minWidth: 18)
                                    .padding(.horizontal, 4)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(Theme.tint(0.08)))
                                Text(binding.action.title).font(.ui(11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                            }
                        }
                    }
                }
            }

            if model.secureInput {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").foregroundStyle(Theme.amber)
                    Text(L("A password field is active: Hyper waits until you leave it."))
                        .font(.ui(11)).foregroundStyle(Theme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Hairline()
            MenuFooter { if !MainWindowRef.show(module: KeysModule.id) { openWindow(id: "main") } }
        }
        .padding(14)
        .popoverFrame(width: 360)
        .id(model.language)
    }

    private var header: some View {
        HStack(spacing: 10) {
            AppLogo(size: 38).padding(-3)
                .saturation(model.isEnabled ? 1 : 0)
                .opacity(model.isEnabled ? 1 : 0.75)
            VStack(alignment: .leading, spacing: 2) {
                Text(AppInfo.name).font(.display(14, .semibold)).foregroundStyle(Theme.text)
                PowerLabel(isOn: model.isEnabled)
            }
            Spacer(minLength: 4)
            ThemeSwitcher(selection: $model.appearance)
            AppPowerButton(name: AppInfo.name, isOn: model.isEnabled, shortcut: "⌃⌥⌘K") { model.isEnabled.toggle() }
        }
    }
}

import LongoKitUI
import SwiftUI

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 10) {
                AppLogo(size: 72)
                Text(AppInfo.name).font(.display(22, .bold)).foregroundStyle(Theme.text)
                Chip("v\(AppInfo.version) beta", tone: .solar)
                Text(L("Remap keys for each keyboard, turn Caps Lock into Esc and Hyper, and give Hyper a layer of arrows, apps and shortcuts."))
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

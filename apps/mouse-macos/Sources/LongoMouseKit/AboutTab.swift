import LongoKitUI
import SwiftUI

struct AboutTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            Hero(update: model.availableUpdate)
            if let update = model.availableUpdate {
                UpdateAvailableCard(update: update)
            } else {
                SoftwareUpdatesCard()
            }
            CommunityCard()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}

private struct Hero: View {
    let update: AppUpdate?

    var body: some View {
        VStack(spacing: 0) {
            AppLogo(size: 120)
                .shadow(color: Theme.magenta.opacity(0.25), radius: 24, y: 6)
            Text(AppInfo.name)
                .font(.display(24, .semibold))
                .tracking(-0.45)
                .foregroundStyle(Theme.text)
            Text(AppInfo.tagline)
                .font(.ui(13))
                .foregroundStyle(Theme.textMuted)
                .padding(.top, 2)
            HStack(spacing: 8) {
                Chip(L("Version %@ (Build %@)", AppInfo.version, AppInfo.build))
                if let update {
                    Chip("Update Available: v\(update.version)", tone: .solar, dot: true)
                }
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

private struct SoftwareUpdatesCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                GlyphTile {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.violet)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(L("Software Updates")).font(.display(14, .semibold)).foregroundStyle(Theme.text)
                        Chip.soon
                    }
                    Text(L("Not checked yet · Stable Channel")).font(.ui(11)).foregroundStyle(Theme.textMuted)
                }
                Spacer()
                Button(L("Check for Updates"), action: model.checkForUpdates).buttonStyle(.ghost)
            }
            Hairline()
            AutoUpdateRow()
            if let notes = AppInfo.releaseNotesURL {
                Link("View Release Notes (v\(AppInfo.version)) ↗", destination: notes)
                    .font(.ui(11))
                    .foregroundStyle(Theme.violet)
            }
        }
        .panel()
    }
}

/// Shown when an update feed reports a newer version.
private struct UpdateAvailableCard: View {
    @EnvironmentObject private var model: AppModel
    let update: AppUpdate

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                GlyphTile(tint: Theme.solar) {
                    Image(systemName: "arrow.down.circle").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.solarLight)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(L("A new version is available")).font(.display(14, .semibold)).foregroundStyle(Theme.text)
                        Chip("v\(update.version)", tone: .solar)
                    }
                    Text("\(AppInfo.name) \(update.version) is ready to install. You're on \(AppInfo.version).")
                        .font(.ui(11))
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer(minLength: 12)
                Button(L("Later"), action: model.dismissUpdate).buttonStyle(.ghost)
                Button(L("Install")) {
                    if let url = update.notesURL { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: L("Release Highlights"))
                ForEach(update.highlights, id: \.self) { line in
                    Text("• \(line)").font(.ui(12)).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .recessed(radius: 10)

            Hairline()
            AutoUpdateRow()
        }
        .panel()
    }
}

private struct AutoUpdateRow: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        SettingRow(title: L("Automatically check for and download updates"),
                   detail: L("Update Channel: Stable Releases")) {
            DSSwitch(isOn: $model.autoCheckUpdates)
        }
    }
}

private struct CommunityCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(AppInfo.communityTitle).font(.display(14, .semibold)).foregroundStyle(Theme.text)
                        Chip(AppInfo.license)
                    }
                    Text(AppInfo.communityBlurb).font(.ui(11)).foregroundStyle(Theme.textMuted)
                }
                Spacer()
                if let sponsor = AppInfo.sponsorURL {
                    Button {
                        NSWorkspace.shared.open(sponsor)
                    } label: {
                        Label(AppInfo.sponsorTitle, systemImage: "heart.fill")
                    }
                    .buttonStyle(GhostButtonStyle(tint: Brand.sun))
                }
            }

            if !AppInfo.links.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                    ForEach(AppInfo.links) { LinkTile(link: $0) }
                }
            }

            Hairline()

            HStack {
                (Text(L("Crafted with care by ")) + Text(AppInfo.author).foregroundColor(Theme.text))
                    .font(.ui(11))
                    .foregroundStyle(Theme.textMuted)
                Spacer()
                Text(SystemInfo.summary).font(.mono(10)).foregroundStyle(Theme.textFaint)
            }
        }
        .panel()
    }
}

private struct LinkTile: View {
    let link: AppLink

    var body: some View {
        Button {
            NSWorkspace.shared.open(link.url)
        } label: {
            HStack {
                Text(link.title).font(.ui(12)).foregroundStyle(Theme.text)
                Spacer()
                Text("\(link.detail) ↗").font(.ui(11)).foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .recessed()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

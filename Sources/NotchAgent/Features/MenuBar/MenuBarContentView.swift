import SwiftUI

/// Popover content for the menu bar item: provider summary + quick controls.
struct MenuBarContentView: View {
    @Environment(UsageStore.self) private var store
    @Environment(PreferencesStore.self) private var preferences
    @Environment(WindowRouter.self) private var router

    var body: some View {
        @Bindable var preferences = preferences

        VStack(alignment: .leading, spacing: 10) {
            ForEach(ProviderID.allCases) { provider in
                providerRow(provider)
            }

            Divider()

            Picker("Favorite", selection: $preferences.settings.favoriteProvider) {
                Text("Auto (most recent)").tag(ProviderID?.none)
                ForEach(ProviderID.allCases) { provider in
                    Text(provider.displayName).tag(ProviderID?.some(provider))
                }
            }
            .font(.system(size: 11))

            if !store.recentErrors.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 3) {
                    Text("RECENT ERRORS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    ForEach(store.recentErrors) { event in
                        Text(event.message)
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                Button(store.isPaused ? "Resume" : "Pause") {
                    store.isPaused.toggle()
                    store.record(UsageEvent(
                        kind: .info,
                        message: store.isPaused ? "Refresh paused" : "Refresh resumed"
                    ))
                }
                Button("Refresh") {
                    AppEnvironment.shared.scheduler.refreshNow()
                }
                Spacer()
                Button("Dashboard") { router.openDashboard() }
                Button("Settings") { router.openSettings() }
            }
            .controlSize(.small)

            HStack {
                Spacer()
                Button("Quit NotchAgent") {
                    NSApp.terminate(nil)
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 320)
        .preferredColorScheme(preferences.settings.themeMode.colorScheme)
    }

    private func providerRow(_ provider: ProviderID) -> some View {
        let snapshot = store.snapshots[provider]
        return HStack(spacing: 8) {
            Image(systemName: provider.symbolName)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 14)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(provider.displayName)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(detail(for: snapshot))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            AttentionDot(level: store.attention(for: provider))
        }
    }

    private func detail(for snapshot: UsageSnapshot?) -> String {
        guard let snapshot else { return "waiting…" }
        guard snapshot.health.isUsable else { return snapshot.health.badgeText }

        var parts: [String] = []
        if let percent = snapshot.session?.usedPercent {
            parts.append("5h: \(Int((100 - percent).rounded()))% left")
        } else if let tokens = snapshot.session?.tokens.total, tokens > 0 {
            parts.append("session \(Format.tokens(tokens))")
        }
        if let percent = snapshot.weekly?.usedPercent {
            parts.append("wk: \(Int((100 - percent).rounded()))% left")
        } else if let tokens = snapshot.weekly?.tokens.total, tokens > 0 {
            parts.append("week \(Format.tokens(tokens))")
        }
        if parts.isEmpty {
            parts.append(snapshot.note ?? "no recent usage")
        }
        return parts.joined(separator: " · ")
    }
}

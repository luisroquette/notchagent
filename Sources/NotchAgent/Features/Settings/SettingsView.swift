import SwiftUI

struct SettingsView: View {
    @Environment(PreferencesStore.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences

        Form {
            Section {
                Picker("Appearance", selection: $preferences.settings.themeMode) {
                    ForEach(ThemeMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Launch at login", isOn: Binding(
                    get: { LoginItem.isEnabled },
                    set: { LoginItem.setEnabled($0) }
                ))
                .disabled(!LoginItem.isAvailable)
                Toggle("Quota alerts as system notifications", isOn: $preferences.settings.notificationsEnabled)
                    .disabled(!NotificationService.isAvailable)
            } header: {
                Text("General")
            } footer: {
                if !BundleContext.isBundledApp {
                    Text("Launch at login and notifications require the packaged app — build it with Scripts/make-app.sh.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Refresh") {
                Picker("Interval", selection: $preferences.settings.refreshIntervalSeconds) {
                    Text("30s").tag(30.0)
                    Text("1 min").tag(60.0)
                    Text("2 min").tag(120.0)
                    Text("5 min").tag(300.0)
                }
            }

            Section("Alerts") {
                LabeledContent("Warning at \(Int(preferences.settings.warningThresholdPercent))%") {
                    Slider(value: $preferences.settings.warningThresholdPercent, in: 40...95, step: 5)
                        .frame(width: 180)
                }
                LabeledContent("Critical at \(Int(preferences.settings.criticalThresholdPercent))%") {
                    Slider(value: $preferences.settings.criticalThresholdPercent, in: 60...100, step: 5)
                        .frame(width: 180)
                }
            }

            Section("Notch overlay") {
                Toggle("Show notch overlay", isOn: $preferences.settings.notchOverlayEnabled)
                Toggle("Floating pill on displays without a notch", isOn: $preferences.settings.fallbackPillEnabled)
                Toggle("Clawd runner (dino-game mascot in the bar)", isOn: $preferences.settings.runnerEnabled)
                Picker("Favorite provider", selection: $preferences.settings.favoriteProvider) {
                    Text("Auto (most recent)").tag(ProviderID?.none)
                    ForEach(ProviderID.allCases) { provider in
                        Text(provider.displayName).tag(ProviderID?.some(provider))
                    }
                }
            }

            Section {
                Toggle("Read real quota from the Anthropic API", isOn: $preferences.settings.claudeQuotaProbeEnabled)
                budgetField(
                    "Session budget (tokens)",
                    value: $preferences.settings.claudeSessionTokenBudget
                )
                budgetField(
                    "Weekly budget (tokens)",
                    value: $preferences.settings.claudeWeeklyTokenBudget
                )
            } header: {
                Text("Claude Code quota")
            } footer: {
                Text("The API probe sends a 1-token request using your local Claude Code OAuth token and reads the official 5h/7d utilization headers (macOS will ask for Keychain access once). The token never leaves this Mac except toward api.anthropic.com. Budgets below are only used as fallback when the probe is off or no token is found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onChange(of: preferences.settings.notchOverlayEnabled) {
            AppEnvironment.shared.notchController?.rebuild()
        }
        .onChange(of: preferences.settings.fallbackPillEnabled) {
            AppEnvironment.shared.notchController?.rebuild()
        }
        .onChange(of: preferences.settings.themeMode) {
            AppEnvironment.shared.applyThemeMode()
        }
    }

    private func budgetField(_ label: String, value: Binding<Int?>) -> some View {
        LabeledContent(label) {
            TextField(
                "none",
                text: Binding(
                    get: { value.wrappedValue.map(String.init) ?? "" },
                    set: { text in
                        value.wrappedValue = Int(text.filter(\.isNumber))
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 140)
            .multilineTextAlignment(.trailing)
        }
    }
}

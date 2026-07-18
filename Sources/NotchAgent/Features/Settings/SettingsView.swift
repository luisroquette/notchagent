import SwiftUI
import AgentMeterCore

struct SettingsView: View {
    @Environment(PreferencesStore.self) private var preferences
    @EnvironmentObject private var spending: SubscriptionStore

    var body: some View {
        @Bindable var preferences = preferences
        let pt = preferences.settings.interfaceLanguage == .ptBR

        Form {
            Section {
                Picker(pt ? "Idioma" : "Language", selection: $preferences.settings.interfaceLanguage) {
                    ForEach(InterfaceLanguage.allCases, id: \.self) { language in
                        Text(language.label).tag(language)
                    }
                }
                Picker(pt ? "Aparência" : "Appearance", selection: $preferences.settings.themeMode) {
                    ForEach(ThemeMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Toggle(pt ? "Abrir ao iniciar sessão" : "Launch at login", isOn: Binding(
                    get: { LoginItem.isEnabled },
                    set: { LoginItem.setEnabled($0) }
                ))
                .disabled(!LoginItem.isAvailable)
                Toggle(pt ? "Alertas de quota como notificações" : "Quota alerts as system notifications", isOn: $preferences.settings.notificationsEnabled)
                    .disabled(!NotificationService.isAvailable)
            } header: {
                Text(pt ? "Geral" : "General")
            } footer: {
                if !BundleContext.isBundledApp {
                    Text(pt ? "Início automático e notificações exigem o app empacotado." : "Launch at login and notifications require the packaged app — build it with Scripts/make-app.sh.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(pt ? "Atualização" : "Refresh") {
                Picker(pt ? "Intervalo" : "Interval", selection: $preferences.settings.refreshIntervalSeconds) {
                    Text("30s").tag(30.0)
                    Text("1 min").tag(60.0)
                    Text("2 min").tag(120.0)
                    Text("5 min").tag(300.0)
                }
            }

            Section(pt ? "Alertas" : "Alerts") {
                LabeledContent(pt ? "Aviso em \(Int(preferences.settings.warningThresholdPercent))%" : "Warning at \(Int(preferences.settings.warningThresholdPercent))%") {
                    Slider(value: $preferences.settings.warningThresholdPercent, in: 40...95, step: 5)
                        .frame(width: 180)
                }
                LabeledContent(pt ? "Crítico em \(Int(preferences.settings.criticalThresholdPercent))%" : "Critical at \(Int(preferences.settings.criticalThresholdPercent))%") {
                    Slider(value: $preferences.settings.criticalThresholdPercent, in: 60...100, step: 5)
                        .frame(width: 180)
                }
            }

            Section(pt ? "Notch" : "Notch overlay") {
                Toggle(pt ? "Mostrar painel no notch" : "Show notch overlay", isOn: $preferences.settings.notchOverlayEnabled)
                Toggle(pt ? "Pílula flutuante em telas sem notch" : "Floating pill on displays without a notch", isOn: $preferences.settings.fallbackPillEnabled)
                Toggle("Clawd runner (dino-game mascot in the bar)", isOn: $preferences.settings.runnerEnabled)
                Picker("Favorite provider", selection: $preferences.settings.favoriteProvider) {
                    Text("Auto (most recent)").tag(ProviderID?.none)
                    ForEach(ProviderID.allCases) { provider in
                        Text(provider.displayName).tag(ProviderID?.some(provider))
                    }
                }
            }

            Section(pt ? "Custos" : "Costs") {
                Picker(pt ? "Moeda exibida" : "Display currency", selection: Binding(
                    get: { spending.displayCurrency },
                    set: { spending.setDisplayCurrency($0) }
                )) {
                    Text("BRL").tag(SpendDisplayCurrency.brl)
                    Text("USD").tag(SpendDisplayCurrency.usd)
                }
                if spending.displayCurrency == .usd {
                    TextField(pt ? "BRL por USD" : "BRL per USD", text: Binding(
                        get: { spending.brlPerUSD.map { NSDecimalNumber(decimal: $0).stringValue } ?? "" },
                        set: { spending.setBRLPerUSD(BRLFormat.decimal($0)) }
                    ))
                    Text("Use a rate you choose. No exchange-rate service is contacted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(pt ? "Gerenciar gastos e orçamento" : "Manage costs and budget") {
                    AppEnvironment.shared.router.openSpending()
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
                Text(pt ? "Quota do Claude Code" : "Claude Code quota")
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
        .onChange(of: preferences.settings.refreshIntervalSeconds) {
            // Restart so the new cadence applies now, not after the old sleep.
            AppEnvironment.shared.scheduler.restart()
        }
        .onChange(of: preferences.settings.warningThresholdPercent) { _, warning in
            if preferences.settings.criticalThresholdPercent < warning + 5 {
                preferences.settings.criticalThresholdPercent = min(100, warning + 5)
            }
        }
        .onChange(of: preferences.settings.criticalThresholdPercent) { _, critical in
            if preferences.settings.warningThresholdPercent > critical - 5 {
                preferences.settings.warningThresholdPercent = max(40, critical - 5)
            }
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

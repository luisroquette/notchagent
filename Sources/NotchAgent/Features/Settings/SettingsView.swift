import SwiftUI
import AgentMeterCore
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

struct SettingsView: View {
    private enum SettingsSection: String, CaseIterable, Identifiable {
        case general
        case apiAccounts

        var id: String { rawValue }
    }

    @Environment(PreferencesStore.self) private var preferences
    @EnvironmentObject private var spending: SubscriptionStore
    @State private var selectedSection: SettingsSection = .general

    var body: some View {
        @Bindable var preferences = preferences
        let pt = preferences.settings.interfaceLanguage == .ptBR

        Form {
            Picker(pt ? "Seção" : "Section", selection: $selectedSection) {
                Text(pt ? "Geral" : "General").tag(SettingsSection.general)
                Text(pt ? "Contas de API" : "API accounts").tag(SettingsSection.apiAccounts)
            }
            .pickerStyle(.segmented)

            if selectedSection == .general {
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
                LabeledContent(pt ? "USD → BRL" : "USD → BRL") {
                    Text(brlRateText(spending.brlPerUSD))
                        .monospacedDigit()
                }
                Text(pt ? "Cotação PTAX de venda do Banco Central, atualizada automaticamente a cada 6 horas." : "Banco Central PTAX selling rate, refreshed automatically every 6 hours.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            } else {
                APIAccountsSettingsSection()
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

    private func brlRateText(_ rate: Decimal?) -> String {
        guard let rate else { return "Atualizando…" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "BRL"
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.minimumFractionDigits = 4
        formatter.maximumFractionDigits = 4
        return formatter.string(from: rate as NSDecimalNumber) ?? rate.description
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

private struct APIAccountsSettingsSection: View {
    private struct PortalLoginRequest: Identifiable {
        let account: APIAccount
        var id: UUID { account.id }
    }

    @Environment(PreferencesStore.self) private var preferences
    @Environment(UsageStore.self) private var usageStore
    @State private var pendingCredentials: [UUID: String] = [:]
    @State private var credentialStatus: String?
    @State private var diagnosticStatus: String?
    @State private var portalLoginRequest: PortalLoginRequest?

    var body: some View {
        @Bindable var preferences = preferences
        let pt = preferences.settings.interfaceLanguage == .ptBR
        let subscriptionIndices = preferences.settings.apiAccounts.indices.filter {
            preferences.settings.apiAccounts[$0].service.isSubscriptionService
        }
        let apiIndices = preferences.settings.apiAccounts.indices.filter {
            !preferences.settings.apiAccounts[$0].service.isSubscriptionService
        }

        Group {
            Section {
                if subscriptionIndices.isEmpty {
                    Text(pt ? "Nenhuma assinatura conectada." : "No connected subscriptions.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(subscriptionIndices.enumerated()), id: \.element) { offset, index in
                    accountEditor(index: index, portuguese: pt, showsServicePicker: false)
                    if offset < subscriptionIndices.count - 1 { Divider() }
                }
            } header: {
                Text(pt ? "Assinaturas conectadas" : "Connected subscriptions")
            } footer: {
                Text(pt
                    ? "Assinaturas web são planos recorrentes e nunca entram no consumo das APIs."
                    : "Web subscriptions are recurring plans and never count as API usage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(pt ? "Monitorar consumo externo" : "Monitor external usage", isOn: $preferences.settings.apiAccountMonitoringEnabled)
                if preferences.settings.apiAccountMonitoringEnabled {
                    ForEach(Array(apiIndices.enumerated()), id: \.element) { offset, index in
                        accountEditor(index: index, portuguese: pt)
                        if offset < apiIndices.count - 1 { Divider() }
                    }
                    Button {
                        preferences.settings.apiAccounts.append(APIAccount(service: .openAI))
                    } label: {
                        Label(pt ? "Adicionar conta" : "Add account", systemImage: "plus")
                    }
                    if !apiIndices.isEmpty {
                        Divider()
                        Button(pt ? "Salvar chaves no Keychain" : "Save keys to Keychain") {
                            saveCredentials(
                                for: apiIndices.map { preferences.settings.apiAccounts[$0] },
                                portuguese: pt
                            )
                        }
                        if let credentialStatus {
                            Text(credentialStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(pt ? "Contas de API" : "API accounts")
            } footer: {
                Text(pt
                    ? "Use + para adicionar quantas contas quiser, inclusive do mesmo serviço. Cada chave fica isolada no Keychain."
                    : "Use + to add as many accounts as needed, including multiple accounts from the same service. Each key stays isolated in Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    exportSanitizedDiagnostic(portuguese: pt)
                } label: {
                    Label(
                        pt ? "Exportar diagnóstico seguro" : "Export safe diagnostic",
                        systemImage: "square.and.arrow.up"
                    )
                }
                if let diagnosticStatus {
                    Text(diagnosticStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(pt ? "Segurança e diagnóstico" : "Security and diagnostics")
            } footer: {
                Text(pt
                    ? "O arquivo contém apenas serviços, estados, fontes e janelas. Não inclui chaves, cookies, nomes, IDs, valores financeiros ou mensagens dos portais."
                    : "The file contains only services, states, sources, and windows. It excludes keys, cookies, names, IDs, financial values, and portal messages.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            preferences.settings.migrateLegacyAPIAccountsIfNeeded()
            preferences.settings.normalizeAPIAccountLabels()
            preferences.settings.ensureWebSubscriptionAccountsIfNeeded()
            preferences.settings.ensureAnthropicAPIAccountIfNeeded()
        }
        #if os(macOS)
        .sheet(item: $portalLoginRequest) { request in
            APIAccountPortalConnectionSheet(account: request.account, portuguese: pt)
        }
        #endif
    }

    @ViewBuilder
    private func accountEditor(
        index: Int,
        portuguese: Bool,
        showsServicePicker: Bool = true
    ) -> some View {
        @Bindable var preferences = preferences
        let account = preferences.settings.apiAccounts[index]
        if showsServicePicker {
            Picker(portuguese ? "Serviço" : "Service", selection: serviceBinding(for: index)) {
                ForEach(APIServiceID.addableCases) { service in
                    Text(service.displayName).tag(service)
                }
            }
        }
        TextField(portuguese ? "Nome da conta" : "Account name", text: $preferences.settings.apiAccounts[index].label)
            .textFieldStyle(.roundedBorder)
        TextField(portuguese ? "Plano mensal (R$) — opcional" : "Monthly plan (BRL) — optional", text: Binding(
            get: {
                preferences.settings.apiAccounts[index].monthlyPlanBRL
                    .map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
            },
            set: { preferences.settings.apiAccounts[index].monthlyPlanBRL = BRLFormat.decimal($0) }
        ))
        .textFieldStyle(.roundedBorder)
        Toggle(portuguese ? "Monitorar esta conta" : "Monitor this account", isOn: $preferences.settings.apiAccounts[index].enabled)
        if account.service.isSubscriptionService {
            #if os(macOS)
            portalStatusView(account: account, portuguese: portuguese)
            Button {
                portalLoginRequest = PortalLoginRequest(account: account)
            } label: {
                Label(
                    portalButtonTitle(account: account, portuguese: portuguese),
                    systemImage: "person.crop.circle.badge.plus"
                )
            }
            Text(portuguese
                ? subscriptionHelp(for: account.service, portuguese: true)
                : subscriptionHelp(for: account.service, portuguese: false))
                .font(.caption)
                .foregroundStyle(.secondary)
            #else
            Text("Anthropic Console monitoring is available on macOS only.")
                .font(.caption)
                .foregroundStyle(.secondary)
            #endif
        } else {
            SecureField(account.service.credentialPlaceholder, text: credentialBinding(account.id))
                .textFieldStyle(.roundedBorder)
            if account.service == .anthropicAPI {
                Text(portuguese
                    ? "Na Individual Org, conecte o portal abaixo. A Admin API Key é opcional e funciona apenas em organizações compatíveis. Nenhuma chamada de modelo é executada."
                    : "For an Individual Org, connect the portal below. The Admin API Key is optional and only works for compatible organizations. No model call is made.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link(
                    portuguese ? "Abrir custos no Claude Console" : "Open costs in Claude Console",
                    destination: URL(string: "https://platform.claude.com/cost")!
                )
            }
            if account.service.supportsPortalConnection {
                #if os(macOS)
                portalStatusView(account: account, portuguese: portuguese)
                Button {
                    portalLoginRequest = PortalLoginRequest(account: account)
                } label: {
                    Label(
                        portalButtonTitle(account: account, portuguese: portuguese),
                        systemImage: "person.crop.circle.badge.plus"
                    )
                }
                Text(portuguese
                    ? portalConnectionHelp(for: account.service, portuguese: true)
                    : portalConnectionHelp(for: account.service, portuguese: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #endif
            }
            if account.service == .gemini {
                Text(portuguese
                    ? "Conexão automática pelo gcloud Application Default Credentials. O token acima é apenas um fallback opcional; o Notch renova o acesso e faz somente leituras de quota."
                    : "Automatic connection through gcloud Application Default Credentials. The token above is only an optional fallback; Notch renews access and only reads quota data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        if let label = account.service.identifierLabel {
            TextField(label, text: $preferences.settings.apiAccounts[index].identifier)
                .textFieldStyle(.roundedBorder)
        }
        HStack {
            Spacer()
            Button(portuguese ? "Remover configuração" : "Remove configuration", role: .destructive) {
                _ = APIAccountCredentialStore.save("", for: account)
                preferences.settings.apiAccounts.remove(at: index)
                pendingCredentials[account.id] = nil
            }
        }
    }

    private func credentialBinding(_ accountID: UUID) -> Binding<String> {
        Binding(
            get: { pendingCredentials[accountID, default: ""] },
            set: { pendingCredentials[accountID] = $0 }
        )
    }

    @ViewBuilder
    private func portalStatusView(account: APIAccount, portuguese: Bool) -> some View {
        let status = portalStatus(account: account, portuguese: portuguese)
        Label(status.text, systemImage: status.symbol)
            .font(.caption)
            .foregroundStyle(status.color)
    }

    private func portalStatus(
        account: APIAccount,
        portuguese: Bool
    ) -> (text: String, symbol: String, color: Color) {
        guard let usage = usageStore.snapshots[.apiAccounts]?.accountUsage?
            .first(where: { $0.accountID == account.id })
        else {
            return (
                portuguese ? "Sessão ainda não verificada" : "Session not verified yet",
                "clock",
                .secondary
            )
        }
        let origins = usage.origins ?? APIAccountFieldOrigins()
        let hasPortalReading = [
            origins.spend,
            origins.balance,
            origins.recharge,
            origins.plan,
            origins.quota,
        ].contains(.officialPortal)
        if hasPortalReading {
            return (
                portuguese ? "Conectado ao portal oficial" : "Connected to official portal",
                "checkmark.circle.fill",
                .green
            )
        }
        if usage.readStatus == .needsLogin || usage.readStatus == .unavailable {
            return (
                portuguese ? "Sessão expirada ou inválida" : "Session expired or invalid",
                "exclamationmark.circle.fill",
                .red
            )
        }
        return (
            portuguese ? "Portal sem leitura recente" : "No recent portal reading",
            "exclamationmark.circle",
            .orange
        )
    }

    private func portalButtonTitle(account: APIAccount, portuguese: Bool) -> String {
        let usage = usageStore.snapshots[.apiAccounts]?.accountUsage?
            .first(where: { $0.accountID == account.id })
        let origins = usage?.origins ?? APIAccountFieldOrigins()
        let connected = [
            origins.spend,
            origins.balance,
            origins.recharge,
            origins.plan,
            origins.quota,
        ].contains(.officialPortal)
        if connected {
            return portuguese ? "Reabrir conexão" : "Reopen connection"
        }
        return portuguese ? "Reconectar conta" : "Reconnect account"
    }

    private func portalConnectionHelp(for service: APIServiceID, portuguese: Bool) -> String {
        if service == .anthropicAPI {
            return portuguese
                ? "O login isolado lê o custo do mês-calendário atual exibido pelo Claude Console. A Anthropic não oferece Admin API para Individual Org."
                : "The isolated login reads the current calendar month's cost shown by Claude Console. Anthropic does not offer the Admin API to Individual Orgs."
        }
        if service == .openAI {
            return portuguese
                ? "A Admin Key lê o gasto mensal; o login isolado lê o saldo pré-pago que a API oficial não fornece."
                : "The Admin Key reads monthly spend; the isolated login reads prepaid balance, which the official API does not provide."
        }
        if service == .gemini {
            return portuguese
                ? "O gcloud lê quotas; o login isolado lê o gasto real dos últimos 28 dias, janela oficial do Google AI Studio."
                : "gcloud reads quotas; the isolated login reads real last-28-day spend from Google AI Studio."
        }
        if service == .openRouter {
            return portuguese
                ? "A chave lê o saldo; o login isolado lê o gasto total da conta nos últimos 30 dias."
                : "The key reads balance; the isolated login reads total account spend for the last 30 days."
        }
        if service == .twitterAPI {
            return portuguese
                ? "A chave lê o saldo; o login isolado lê o consumo dos últimos 30 dias mostrado pelo painel."
                : "The key reads balance; the isolated login reads the last-30-day consumption shown by the dashboard."
        }
        if service == .xTwitter || service == .xTwitterAccount1 || service == .xTwitterAccount2 {
            return portuguese
                ? "O Bearer Token lê apenas Posts; conecte este perfil para mostrar gasto dos últimos 30 dias e saldo em R$."
                : "The Bearer Token reads Posts only; connect this profile to show last-30-day spend and balance in BRL."
        }
        return portuguese
            ? "A chave lê o saldo; o login isolado lê os totais que a API não fornece."
            : "The key reads balance; the isolated login reads totals the API does not provide."
    }

    private func subscriptionHelp(for service: APIServiceID, portuguese: Bool) -> String {
        switch service {
        case .anthropicConsole:
            return portuguese
                ? "Lê plano, próxima cobrança e créditos adicionais no site Claude; não cria organização API."
                : "Reads plan, upcoming charge, and extra credits from Claude; it does not create an API organization."
        case .chatGPTSubscription:
            return portuguese
                ? "Lê o plano mensal diretamente no site ChatGPT; não usa nem altera o faturamento da API OpenAI."
                : "Reads the monthly plan directly from ChatGPT; it never uses or changes OpenAI API billing."
        case .googleSubscription:
            return portuguese
                ? "Lê a assinatura Google AI/Gemini em payments.google.com; não entra no custo da API Gemini."
                : "Reads the Google AI/Gemini subscription from payments.google.com; it does not count as Gemini API cost."
        case .firecrawlSubscription:
            return portuguese
                ? "Lê plano, preço e renovação em Firecrawl Dashboard → Billing; os créditos continuam vindo da API."
                : "Reads plan, price, and renewal from Firecrawl Dashboard → Billing; credits continue to come from the API."
        default:
            return ""
        }
    }

    private func serviceBinding(for index: Int) -> Binding<APIServiceID> {
        Binding(
            get: { preferences.settings.apiAccounts[index].service },
            set: { service in
                guard preferences.settings.apiAccounts[index].service != service else { return }
                preferences.settings.apiAccounts[index].service = service
                preferences.settings.apiAccounts[index].identifier = ""
                pendingCredentials[preferences.settings.apiAccounts[index].id] = nil
            }
        )
    }

    private func saveCredentials(for accounts: [APIAccount], portuguese: Bool) {
        let entries = accounts.compactMap { account -> (APIAccount, String)? in
            let value = pendingCredentials[account.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : (account, value)
        }
        guard !entries.isEmpty else {
            credentialStatus = portuguese ? "Nenhuma chave nova para salvar." : "No new keys to save."
            return
        }
        let savedIDs = Set(entries.compactMap { account, value in
            APIAccountCredentialStore.save(value, for: account) ? account.id : nil
        })
        for index in preferences.settings.apiAccounts.indices where savedIDs.contains(preferences.settings.apiAccounts[index].id) {
            preferences.settings.apiAccounts[index].credentialService = preferences.settings.apiAccounts[index].service
            preferences.settings.apiAccounts[index].credentialRevision = .now
            pendingCredentials[preferences.settings.apiAccounts[index].id] = nil
        }
        credentialStatus = savedIDs.count == entries.count
            ? (portuguese ? "Chaves salvas no Keychain." : "Keys saved in Keychain.")
            : (portuguese ? "Algumas chaves não puderam ser salvas; mantenha os campos preenchidos e tente novamente." : "Some keys could not be saved; keep those fields filled and try again.")
    }

    private func exportSanitizedDiagnostic(portuguese: Bool) {
        #if os(macOS)
        let report = SanitizedDiagnosticExporter.report(
            settings: preferences.settings,
            snapshots: usageStore.snapshots,
            refreshStates: usageStore.refreshStates
        )
        do {
            let data = try SanitizedDiagnosticExporter.data(report)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "NotchAgent-diagnostico.json"
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
            diagnosticStatus = portuguese
                ? "Diagnóstico exportado sem credenciais."
                : "Diagnostic exported without credentials."
        } catch {
            diagnosticStatus = portuguese
                ? "Falha ao exportar o diagnóstico."
                : "Failed to export diagnostic."
        }
        #endif
    }
}

#if os(macOS)
private struct APIAccountPortalConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let account: APIAccount
    let portuguese: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(portuguese ? "Conectar conta" : "Connect account")
                        .font(.headline)
                    Text(account.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(portuguese ? "Concluído" : "Done") {
                    AppEnvironment.shared.scheduler.refreshNow()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            Text(instructions)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            APIAccountPortalLoginView(account: account)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack {
                Spacer()
                Button(portuguese ? "Desconectar conta" : "Disconnect account", role: .destructive) {
                    Task { @MainActor in
                        await APIAccountPortalSession.disconnect(accountID: account.id)
                        AppEnvironment.shared.scheduler.refreshNow()
                        dismiss()
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 760, minHeight: 620)
    }

    private var instructions: String {
        switch account.service {
        case .gemini:
            return portuguese
                ? "Entre com a conta Google deste projeto e selecione “28 dias” na página Gasto. O Notch lerá somente o custo total renderizado."
                : "Sign in with this project's Google account and select “28 days” on the Spend page. Notch reads only the rendered total cost."
        case .deepSeek:
            return portuguese
                ? "Entre na DeepSeek Platform. O Notch lerá gasto dos últimos 30 dias e saldo; cookies ficam somente no perfil desta conta."
                : "Sign in to DeepSeek Platform. Notch will read last-30-day spend and balance; cookies stay only in this account profile."
        case .anthropicConsole:
            return portuguese
                ? "Entre na sua conta Claude atual. O Notch lerá plano, limites e créditos adicionais em Settings → Usage; cookies ficam somente neste perfil."
                : "Sign in to your current Claude account. Notch reads plan, limits, and extra credits from Settings → Usage; cookies stay only in this profile."
        case .chatGPTSubscription:
            return portuguese
                ? "Entre no ChatGPT e abra Settings → Billing. O Notch lerá somente nome e valor recorrente do plano."
                : "Sign in to ChatGPT and open Settings → Billing. Notch reads only the recurring plan name and amount."
        case .googleSubscription:
            return portuguese
                ? "Entre na conta Google pagadora. O Notch lerá somente a cobrança Google AI/Gemini mais recente em Atividade."
                : "Sign in to the paying Google account. Notch reads only the latest Google AI/Gemini charge under Activity."
        case .firecrawlSubscription:
            return portuguese
                ? "Entre na conta Firecrawl pagadora. O Notch lerá somente plano, preço recorrente e data de renovação na página Billing."
                : "Sign in to the paying Firecrawl account. Notch reads only the plan, recurring price, and renewal date from Billing."
        case .openRouter:
            return portuguese
                ? "Entre no OpenRouter. Mantenha Activity em “Past 1 Month”; o Notch lerá apenas Total spend e o saldo continuará vindo da API oficial."
                : "Sign in to OpenRouter. Keep Activity on “Past 1 Month”; Notch will read only Total spend, while balance continues to come from the official API."
        case .twitterAPI:
            return portuguese
                ? "Entre no twitterapi.io. O Notch lerá o consumo dos últimos 30 dias; o saldo continuará vindo da API oficial."
                : "Sign in to twitterapi.io. Notch will read the last-30-day consumption; balance continues to come from the official API."
        case .xTwitter, .xTwitterAccount1, .xTwitterAccount2:
            return portuguese
                ? "Entre no X Developer Console deste perfil. O Notch mostrará gasto dos últimos 30 dias e saldo em R$; a sessão fica isolada das outras contas X."
                : "Sign in to this profile's X Developer Console. Notch will show last-30-day spend and balance in BRL; the session stays isolated from other X accounts."
        default:
            return portuguese
                ? "Entre no portal. A sessão fica isolada nesta conta e somente neste Mac."
                : "Sign in to the portal. The session stays isolated to this account and only on this Mac."
        }
    }
}
#endif

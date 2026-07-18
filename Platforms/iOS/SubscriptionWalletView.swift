import AgentMeterCore
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import UIKit

struct SubscriptionWalletView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: SubscriptionStore
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.portuguese.rawValue
    @State private var isPresentingNewSubscription = false
    @State private var alertsEnabled = false
    @State private var editingSubscription: AISubscription?
    @State private var importPreview: SubscriptionImportPreview?
    @State private var importError: String?
    @State private var isPresentingImporter = false
    @State private var isExportingImportTemplate = false
    @State private var isUpdatingAlerts = false
    @State private var isUpdatingCloud = false
    @State private var renewalToConfirm: AISubscription?
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        ZStack {
            Image("MarketOrbit")
                .resizable()
                .scaledToFill()
                .scaleEffect(1.18)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            Color.black.opacity(0.14)
                .ignoresSafeArea()
            LinearGradient(
                colors: [.clear, .black.opacity(0.42), .black.opacity(0.92), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    marketNavigation
                    marketBalance
                    marketPlans
                    marketActions
                    marketSystems
                    marketHistory
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
            .scrollIndicators(.hidden)
        }
        .font(AgentMeterTypography.regular(17))
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isPresentingNewSubscription) {
            SubscriptionEditorView()
                .environmentObject(store)
        }
        .sheet(item: $editingSubscription) { subscription in
            SubscriptionEditorView(subscription: subscription)
                .environmentObject(store)
        }
        .sheet(item: $importPreview) { preview in
            SubscriptionImportReviewView(preview: preview)
                .environmentObject(store)
        }
        .fileImporter(
            isPresented: $isPresentingImporter,
            allowedContentTypes: [.commaSeparatedText, .json],
            allowsMultipleSelection: false,
            onCompletion: loadImport
        )
        .fileExporter(
            isPresented: $isExportingImportTemplate,
            document: SubscriptionCSVTemplateDocument(),
            contentType: .commaSeparatedText,
            defaultFilename: "agentmeter-assinaturas"
        ) { _ in }
        .alert("Não foi possível importar", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .confirmationDialog(
            "Confirmar cobrança?",
            isPresented: Binding(
                get: { renewalToConfirm != nil },
                set: { if !$0 { renewalToConfirm = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Confirmar cobrança") {
                guard let subscription = renewalToConfirm else { return }
                confirmRenewal(for: subscription)
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            if let subscription = renewalToConfirm {
                Text("Registrar \(brl(subscription.cycleTotalBRL)) de \(subscription.provider.displayName) e avançar a próxima renovação.")
            }
        }
        .task {
            await refreshNotificationStatus()
        }
    }

    private var marketNavigation: some View {
        HStack {
            Button(action: dismiss.callAsFunction) {
                Image(systemName: "arrow.left")
                    .font(AgentMeterTypography.fixedBold(17))
                    .frame(width: 42, height: 42)
                    .background(AgentMeterTheme.elevatedSurface, in: Circle())
                    .overlay { Circle().stroke(AgentMeterTheme.border, lineWidth: 1) }
            }
            .accessibilityLabel("Voltar")

            Spacer()
            Text("AGENTMETER")
                .font(AgentMeterTypography.fixedBold(13))
                .tracking(2.6)
            Spacer()

            Menu {
                Button("Importar assinaturas") { isPresentingImporter = true }
                Button("Adicionar plano") { isPresentingNewSubscription = true }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(AgentMeterTypography.fixedBold(16))
                    .frame(width: 42, height: 42)
            }
            .accessibilityLabel("Ações da carteira")
        }
        .padding(.top, 12)
        .padding(.bottom, 50)
    }

    private var marketBalance: some View {
        VStack(spacing: 10) {
            Text("TOTAL MENSAL")
                .missionMicro(color: AgentMeterTheme.mutedInk)
            Text(brl(store.summary.monthlyTotalBRL))
                .font(AgentMeterTypography.bold(46, relativeTo: .largeTitle))
                .tracking(0.96)
                .monospacedDigit()
                .minimumScaleFactor(0.65)
            WalletTelemetry(activeCount: store.summary.activeCount)
                .frame(height: 128)
                .padding(.top, 12)
            Text(activePlansTitle.uppercased())
                .missionMicro(color: AgentMeterTheme.spectral)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 56)
    }

    @ViewBuilder
    private var marketPlans: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SEUS PLANOS")
                .missionMicro(color: AgentMeterTheme.mutedInk)
                .padding(.horizontal, 8)
                .padding(.bottom, 14)

            if store.subscriptions.isEmpty {
                Text("NENHUM PLANO CONFIGURADO")
                    .missionBody(color: AgentMeterTheme.mutedInk)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .overlay(alignment: .top) { Rectangle().fill(AgentMeterTheme.border).frame(height: 1) }
                    .overlay(alignment: .bottom) { Rectangle().fill(AgentMeterTheme.border).frame(height: 1) }
            } else {
                VStack(spacing: 0) {
                    ForEach(store.subscriptions) { subscription in
                        Button { editingSubscription = subscription } label: {
                            marketPlanRow(subscription)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("subscription-row-\(subscription.provider.rawValue)")

                        if subscription.needsRenewalAttention() {
                            Button { renewalToConfirm = subscription } label: {
                                Label("CONFIRMAR COBRANÇA", systemImage: "checkmark.circle.fill")
                                    .font(AgentMeterTypography.fixedBold(12))
                                    .tracking(1)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(AgentMeterTheme.spectral)
                            .accessibilityIdentifier("confirm-renewal-\(subscription.provider.rawValue)")
                        }
                    }
                }
                .overlay(alignment: .top) { Rectangle().fill(AgentMeterTheme.border).frame(height: 1) }
            }
        }
    }

    private func marketPlanRow(_ subscription: AISubscription) -> some View {
        HStack(spacing: 16) {
            Text(providerCode(subscription.provider))
                .font(AgentMeterTypography.fixedBold(12))
                .frame(width: 40, height: 40)
                .background(AgentMeterTheme.elevatedSurface, in: Circle())
                .overlay { Circle().stroke(AgentMeterTheme.border, lineWidth: 1) }
            VStack(alignment: .leading, spacing: 4) {
                Text(subscription.provider.displayName.uppercased())
                    .font(AgentMeterTypography.fixedBold(13))
                    .tracking(1.17)
                Text(subscription.planName.uppercased())
                    .missionMicro(color: AgentMeterTheme.mutedInk)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(brl(subscription.cycleTotalBRL))
                    .font(AgentMeterTypography.telemetry(14, relativeTo: .body))
                    .foregroundStyle(AgentMeterTheme.spectral)
                Text(subscription.nextRenewalDate.formatted(date: .abbreviated, time: .omitted).uppercased())
                    .missionMicro(color: AgentMeterTheme.mutedInk)
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 82)
        .overlay(alignment: .bottom) { Rectangle().fill(AgentMeterTheme.border).frame(height: 1) }
    }

    private var marketActions: some View {
        HStack(spacing: 12) {
            Button { isPresentingNewSubscription = true } label: {
                Label("NOVO PLANO", systemImage: "plus")
            }
            .buttonStyle(AgentMeterSecondaryButtonStyle())
            Button { isPresentingImporter = true } label: {
                Label("IMPORTAR", systemImage: "arrow.down.doc")
            }
            .buttonStyle(AgentMeterSecondaryButtonStyle())
        }
        .padding(.top, 32)
        .padding(.bottom, 52)
    }

    private var marketSystems: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SISTEMAS")
                .missionMicro(color: AgentMeterTheme.mutedInk)
                .padding(.horizontal, 8)
                .padding(.bottom, 14)
            Button { isExportingImportTemplate = true } label: {
                systemRow(title: "BAIXAR MODELO CSV", detail: "IMPORTAÇÃO EM LOTE", symbol: "arrow.down.doc", color: AgentMeterTheme.signal)
            }
            .buttonStyle(.plain)
            Button {
                Task {
                    isUpdatingCloud = true
                    if store.isCloudSyncEnabled { await store.syncNow() } else { await store.setCloudSyncEnabled(true) }
                    isUpdatingCloud = false
                }
            } label: {
                systemRow(title: cloudActionTitle, detail: cloudStatus, symbol: cloudStatusSymbol, color: cloudStatusColor)
            }
            .buttonStyle(.plain)
            .disabled(isUpdatingCloud)
        }
        .overlay(alignment: .top) { Rectangle().fill(AgentMeterTheme.border).frame(height: 1) }
    }

    @ViewBuilder
    private var marketHistory: some View {
        if !store.history.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("HISTÓRICO")
                    .missionMicro(color: AgentMeterTheme.mutedInk)
                    .padding(.horizontal, 8)
                    .padding(.top, 48)
                    .padding(.bottom, 14)
                ForEach(store.history.prefix(4)) { event in
                    HStack {
                        Text(historyTitle(event).uppercased())
                            .missionMicro(color: AgentMeterTheme.spectral)
                        Spacer()
                        Text(brl(event.amountBRL))
                            .font(AgentMeterTypography.telemetry(13, relativeTo: .caption))
                    }
                    .padding(.horizontal, 8)
                    .frame(minHeight: 46)
                    .overlay(alignment: .bottom) { Rectangle().fill(AgentMeterTheme.border).frame(height: 1) }
                }
            }
        }
    }

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: AgentMeterTheme.Space.md) {
                HStack {
                    Text("TOTAL EM ÓRBITA")
                        .missionMicro()
                    Spacer()
                    Text(activePlansTitle.uppercased())
                        .missionMicro(color: AgentMeterTheme.mutedInk)
                }

                Text(brl(store.summary.monthlyTotalBRL))
                    .font(AgentMeterTypography.bold(42, relativeTo: .largeTitle))
                    .tracking(0.96)
                    .monospacedDigit()

                WalletTelemetry(activeCount: store.summary.activeCount)
                    .frame(height: 72)

                HStack(alignment: .firstTextBaseline, spacing: AgentMeterTheme.Space.md) {
                    walletMetric("PROJEÇÃO ANUAL", value: brl(store.summary.projectedAnnualBRL))
                    Text("DADOS INFORMADOS POR VOCÊ")
                        .missionMicro(color: AgentMeterTheme.mutedInk)
                }
            }
            .padding(.top, AgentMeterTheme.Space.md)
            .padding(.bottom, AgentMeterTheme.Space.sm)
            .listRowInsets(EdgeInsets(top: 14, leading: 24, bottom: 12, trailing: 24))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if !store.summary.upcomingRenewals.isEmpty {
                Label("Há uma cobrança próxima", systemImage: "bell.badge.fill")
                    .font(AgentMeterTypography.bold(16, relativeTo: .subheadline))
                    .foregroundStyle(AgentMeterTheme.warning)
                    .listRowBackground(AgentMeterTheme.warning.opacity(0.08))
                    .listRowSeparatorTint(AgentMeterTheme.border)
            }
        } header: {
            technicalHeader("MISSION // WALLET")
        }
    }

    private var emptySection: some View {
        Section {
            VStack(spacing: AgentMeterTheme.Space.md) {
                AgentMeterOrbitMark(progress: 0.08)
                Text("Nenhuma assinatura cadastrada")
                    .font(AgentMeterTypography.bold(20, relativeTo: .headline))
                Text("Adicione seus planos para acompanhar custos e renovações.")
                    .font(AgentMeterTypography.regular(17, relativeTo: .subheadline))
                    .foregroundStyle(AgentMeterTheme.mutedInk)
                    .multilineTextAlignment(.center)
                Button {
                    isPresentingNewSubscription = true
                } label: {
                    Label("Adicionar assinatura", systemImage: "plus")
                }
                .buttonStyle(AgentMeterPrimaryButtonStyle())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AgentMeterTheme.Space.xl)
            .listRowBackground(AgentMeterTheme.surface)
            .listRowSeparator(.hidden)
        } header: {
            technicalHeader("Seus planos")
        }
    }

    private var subscriptionsSection: some View {
        Section {
            ForEach(store.subscriptions) { subscription in
                VStack(spacing: 0) {
                    Button {
                        editingSubscription = subscription
                    } label: {
                        subscriptionRow(subscription)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("subscription-row-\(subscription.provider.rawValue)")

                    if subscription.needsRenewalAttention() {
                        Button {
                            renewalToConfirm = subscription
                        } label: {
                            Label("Confirmar cobrança", systemImage: "checkmark.circle.fill")
                                .font(AgentMeterTypography.bold(15, relativeTo: .subheadline))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AgentMeterTheme.nominal)
                        .accessibilityIdentifier("confirm-renewal-\(subscription.provider.rawValue)")
                    }
                }
                .listRowBackground(AgentMeterTheme.surface)
                .listRowSeparatorTint(AgentMeterTheme.border)
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        renewalToConfirm = subscription
                    } label: {
                        Label("Confirmar cobrança", systemImage: "checkmark.circle.fill")
                    }
                    .tint(AgentMeterTheme.nominal)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        store.remove(id: subscription.id)
                        RenewalNotificationScheduler.cancel(id: subscription.id)
                    } label: {
                        Label("Excluir", systemImage: "trash")
                    }
                }
            }
        } header: {
            technicalHeader("Seus planos")
        }
    }

    private func confirmRenewal(for subscription: AISubscription) {
        guard let renewed = store.confirmRenewal(id: subscription.id) else { return }
        Task { await RenewalNotificationScheduler.schedule(renewed) }
    }

    private var systemsSection: some View {
        Section {
            Button {
                isExportingImportTemplate = true
            } label: {
                systemRow(
                    title: "Baixar modelo CSV",
                    detail: "Preencha e importe suas assinaturas em lote",
                    symbol: "document.badge.arrow.down",
                    color: AgentMeterTheme.signal
                )
            }
            .buttonStyle(.plain)
            .listRowBackground(AgentMeterTheme.surface)
            .listRowSeparatorTint(AgentMeterTheme.border)

            if notificationStatus == .denied {
                Button(action: openNotificationSettings) {
                    systemRow(
                        title: "Alertas bloqueados",
                        detail: "Abra Ajustes para permitir lembretes de renovação",
                        symbol: "bell.slash.fill",
                        color: AgentMeterTheme.critical
                    )
                }
                .buttonStyle(.plain)
                .listRowBackground(AgentMeterTheme.surface)
                .listRowSeparatorTint(AgentMeterTheme.border)
            } else {
                Button {
                    Task { await requestRenewalAlerts() }
                } label: {
                    systemRow(
                        title: isUpdatingAlerts ? "Ativando alertas…" : (alertsEnabled ? "Alertas ativados" : "Ativar alertas de renovação"),
                        detail: alertsEnabled ? "Renovações monitoradas neste aparelho" : "Receba avisos antes das cobranças",
                        symbol: alertsEnabled ? "bell.fill" : "bell",
                        color: alertsEnabled ? AgentMeterTheme.nominal : AgentMeterTheme.signal
                    )
                }
                .buttonStyle(.plain)
                .disabled(alertsEnabled || isUpdatingAlerts)
                .listRowBackground(AgentMeterTheme.surface)
                .listRowSeparatorTint(AgentMeterTheme.border)
            }

            Button {
                Task {
                    isUpdatingCloud = true
                    if store.isCloudSyncEnabled {
                        await store.syncNow()
                    } else {
                        await store.setCloudSyncEnabled(true)
                    }
                    isUpdatingCloud = false
                }
            } label: {
                systemRow(
                    title: cloudActionTitle,
                    detail: cloudStatus,
                    symbol: cloudStatusSymbol,
                    color: cloudStatusColor
                )
            }
            .buttonStyle(.plain)
            .disabled(isUpdatingCloud)
            .listRowBackground(AgentMeterTheme.surface)
            .listRowSeparatorTint(AgentMeterTheme.border)

            if store.isCloudSyncEnabled {
                Button {
                    Task {
                        isUpdatingCloud = true
                        await store.setCloudSyncEnabled(false)
                        isUpdatingCloud = false
                    }
                } label: {
                    systemRow(
                        title: "Desativar sincronização iCloud",
                        detail: "Manter os dados somente neste aparelho",
                        symbol: "icloud.slash",
                        color: AgentMeterTheme.mutedInk
                    )
                }
                .buttonStyle(.plain)
                .disabled(isUpdatingCloud)
                .listRowBackground(AgentMeterTheme.surface)
                .listRowSeparatorTint(AgentMeterTheme.border)
            }
        } header: {
            technicalHeader("Sistemas")
        } footer: {
            Text("Seus dados ficam neste aparelho. O iCloud é opcional.")
                .foregroundStyle(AgentMeterTheme.mutedInk)
        }
    }

    private var historySection: some View {
        Section {
            LabeledContent("Confirmado neste mês", value: brl(store.history.totalRenewed(in: .now)))
                .font(AgentMeterTypography.bold(16, relativeTo: .subheadline))
                .listRowBackground(AgentMeterTheme.surface)

            ForEach(store.history.prefix(8)) { event in
                HStack(spacing: AgentMeterTheme.Space.sm) {
                    Image(systemName: historySymbol(event.kind))
                        .foregroundStyle(historyColor(event.kind))
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: AgentMeterTheme.Space.xxs) {
                        Text(historyTitle(event))
                            .font(AgentMeterTypography.bold(16, relativeTo: .subheadline))
                        Text(event.occurredAt, style: .date)
                            .font(AgentMeterTypography.regular(13, relativeTo: .caption))
                            .foregroundStyle(AgentMeterTheme.mutedInk)
                    }
                    Spacer()
                    Text(brl(event.amountBRL))
                        .font(AgentMeterTypography.telemetry(14, relativeTo: .subheadline))
                        .foregroundStyle(AgentMeterTheme.mutedInk)
                }
                .frame(minHeight: 52)
                .listRowBackground(AgentMeterTheme.surface)
                .listRowSeparatorTint(AgentMeterTheme.border)
            }
        } header: {
            technicalHeader("Histórico")
        } footer: {
            Text("Eventos dos últimos 24 meses neste aparelho.")
                .foregroundStyle(AgentMeterTheme.mutedInk)
        }
    }

    private var cloudStatus: LocalizedStringKey {
        switch store.cloudSyncState {
        case .localOnly: "Somente neste aparelho"
        case .syncing: "Sincronizando…"
        case .synced: "Sincronizado com iCloud"
        case .waitingToRetry: "Aguardando conexão para sincronizar"
        case .unavailable: "Entre no iCloud para sincronizar"
        case .failed: "Não foi possível sincronizar"
        }
    }

    private var cloudActionTitle: LocalizedStringKey {
        if isUpdatingCloud { return "Atualizando iCloud…" }
        guard store.isCloudSyncEnabled else { return "Sincronizar com iCloud" }
        switch store.cloudSyncState {
        case .waitingToRetry, .unavailable, .failed: return "Tentar sincronizar iCloud"
        default: return "Sincronizar agora"
        }
    }

    private var cloudStatusSymbol: String {
        switch store.cloudSyncState {
        case .synced: "checkmark.icloud.fill"
        case .waitingToRetry: "clock.arrow.circlepath"
        case .unavailable, .failed: "exclamationmark.icloud"
        default: "arrow.triangle.2.circlepath.icloud"
        }
    }

    private var cloudStatusColor: Color {
        switch store.cloudSyncState {
        case .unavailable, .failed, .waitingToRetry: AgentMeterTheme.warning
        case .synced: AgentMeterTheme.nominal
        default: AgentMeterTheme.signal
        }
    }

    private func subscriptionRow(_ subscription: AISubscription) -> some View {
        HStack(spacing: AgentMeterTheme.Space.sm) {
            AgentMeterProviderBadge(provider: subscription.provider, active: subscription.isActive)
            VStack(alignment: .leading, spacing: AgentMeterTheme.Space.xxs) {
                Text(subscription.provider.displayName)
                    .font(AgentMeterTypography.bold(18, relativeTo: .headline))
                    .foregroundStyle(.primary)
                Text(subscription.planName)
                    .font(AgentMeterTypography.regular(16, relativeTo: .subheadline))
                    .foregroundStyle(AgentMeterTheme.mutedInk)
                Text(subscription.nextRenewalDate, style: .date)
                    .font(AgentMeterTypography.telemetry(13, relativeTo: .caption))
                    .foregroundStyle(subscription.needsRenewalAttention() ? AgentMeterTheme.warning : AgentMeterTheme.mutedInk)
            }
            Spacer(minLength: AgentMeterTheme.Space.xs)
            VStack(alignment: .trailing, spacing: AgentMeterTheme.Space.xxs) {
                Text(brl(subscription.cycleTotalBRL))
                    .font(AgentMeterTypography.telemetry(16, relativeTo: .subheadline))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(localized(subscription.billingCycle == .monthly ? "Mensal" : "Anual"))
                    .font(AgentMeterTypography.regular(12, relativeTo: .caption2))
                    .foregroundStyle(AgentMeterTheme.mutedInk)
            }
            Image(systemName: "chevron.right")
                .font(AgentMeterTypography.fixedBold(13))
                .foregroundStyle(AgentMeterTheme.mutedInk)
        }
        .frame(minHeight: 68)
        .contentShape(Rectangle())
    }

    private func historyTitle(_ event: SubscriptionHistoryEvent) -> String {
        let action: String
        switch event.kind {
        case .imported: action = localized("Importado")
        case .priceChanged: action = localized("Preço atualizado")
        case .renewalConfirmed: action = localized("Cobrança confirmada")
        case .cancelled: action = localized("Cancelado")
        }
        return "\(event.provider.displayName) · \(action)"
    }

    private func providerCode(_ provider: AgentMeterProvider) -> String {
        switch provider {
        case .claude: "CL"
        case .chatGPT: "AI"
        case .gemini: "GM"
        }
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .portuguese
    }

    private var activePlansTitle: String {
        if store.summary.activeCount == 1 { return localized("1 plano ativo") }
        return String(
            format: localized("%lld planos ativos"),
            locale: language.locale,
            Int64(store.summary.activeCount)
        )
    }

    private func localized(_ key: String) -> String {
        language.localized(key)
    }

    private func historySymbol(_ kind: SubscriptionHistoryKind) -> String {
        switch kind {
        case .imported: "square.and.arrow.down"
        case .priceChanged: "tag.fill"
        case .renewalConfirmed: "checkmark.circle.fill"
        case .cancelled: "xmark.circle.fill"
        }
    }

    private func historyColor(_ kind: SubscriptionHistoryKind) -> Color {
        switch kind {
        case .renewalConfirmed: AgentMeterTheme.nominal
        case .cancelled: AgentMeterTheme.critical
        case .priceChanged: AgentMeterTheme.warning
        case .imported: AgentMeterTheme.signal
        }
    }

    private func systemRow(
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        symbol: String,
        color: Color
    ) -> some View {
        HStack(spacing: AgentMeterTheme.Space.sm) {
            Image(systemName: symbol)
                .font(AgentMeterTypography.fixedBold(17))
                .foregroundStyle(color)
                .frame(width: 34, height: 34)
                .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: AgentMeterTheme.Space.xxs) {
                Text(title)
                    .font(AgentMeterTypography.bold(16, relativeTo: .subheadline))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(AgentMeterTypography.regular(13, relativeTo: .caption))
                    .foregroundStyle(AgentMeterTheme.mutedInk)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(AgentMeterTypography.fixedBold(13))
                .foregroundStyle(AgentMeterTheme.mutedInk)
        }
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }

    private func walletMetric(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: AgentMeterTheme.Space.xxs) {
            Text(title)
                .font(AgentMeterTypography.fixedRegular(12))
                .textCase(.uppercase)
                .tracking(0.9)
                .foregroundStyle(AgentMeterTheme.mutedInk)
            Text(value)
                .font(AgentMeterTypography.telemetry(20, relativeTo: .title3))
                .foregroundStyle(AgentMeterTheme.spectral)
                .lineLimit(1)
                .minimumScaleFactor(0.66)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func technicalHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(AgentMeterTypography.fixedBold(12))
            .textCase(.uppercase)
            .tracking(1.15)
            .foregroundStyle(AgentMeterTheme.mutedInk)
    }

    private func loadImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let format: SubscriptionImportFormat = url.pathExtension.lowercased() == "json" ? .json : .csv
            importPreview = SubscriptionImportParser.preview(data: data, format: format, existing: store.subscriptions)
        } catch {
            importError = "Não foi possível ler o arquivo. Verifique se ele é um CSV ou JSON válido e tente novamente."
        }
    }

    private func requestRenewalAlerts() async {
        isUpdatingAlerts = true
        alertsEnabled = await RenewalNotificationScheduler.requestAuthorizationAndSchedule(store.subscriptions)
        await refreshNotificationStatus()
        isUpdatingAlerts = false
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await RenewalNotificationScheduler.authorizationStatus()
        alertsEnabled = notificationStatus == .authorized
    }

    private func openNotificationSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsURL)
    }
}

private struct WalletTelemetry: View {
    let activeCount: Int

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<12, id: \.self) { index in
                    let amount = CGFloat(((index * 19 + activeCount * 13) % 46) + 18) / 64
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle()
                            .fill(AgentMeterTheme.spectral.opacity(index == 8 ? 0.92 : 0.34))
                            .frame(width: 1, height: proxy.size.height * amount)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(AgentMeterTheme.border.opacity(0.65)).frame(height: 1)
            }
        }
        .accessibilityLabel("Telemetria dos custos cadastrados")
    }
}

private struct SubscriptionCSVTemplateDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    init() {}

    init(configuration: ReadConfiguration) throws {}

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: SubscriptionImportTemplate.data)
    }
}

private struct SubscriptionImportReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: SubscriptionStore
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.portuguese.rawValue

    let preview: SubscriptionImportPreview
    @State private var importedCount: Int?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Prontos para importar", value: "\(preview.subscriptions.count)")
                    if preview.duplicateCount > 0 {
                        LabeledContent("Duplicados ignorados", value: "\(preview.duplicateCount)")
                    }
                    if !preview.issues.isEmpty {
                        LabeledContent("Linhas com erro", value: "\(preview.issues.count)")
                    }
                } footer: {
                    Text("Nada será alterado até você confirmar.")
                }

                if !preview.subscriptions.isEmpty {
                    Section("Assinaturas") {
                        ForEach(preview.subscriptions) { subscription in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(subscription.provider.displayName) · \(subscription.planName)")
                                Text("\(brl(subscription.cycleTotalBRL)) · \(localized(subscription.billingCycle == .monthly ? "Mensal" : "Anual"))")
                                    .font(.subheadline)
                                    .foregroundStyle(AgentMeterTheme.mutedInk)
                            }
                        }
                    }
                }

                if preview.subscriptions.isEmpty, !preview.issues.isEmpty {
                    VStack(alignment: .leading, spacing: AgentMeterTheme.Space.xs) {
                        Label("Nenhuma assinatura pôde ser importada", systemImage: "exclamationmark.triangle.fill")
                            .font(AgentMeterTypography.bold(16, relativeTo: .subheadline))
                            .foregroundStyle(AgentMeterTheme.warning)
                        Text("Corrija as linhas abaixo ou baixe o modelo CSV para recomeçar.")
                            .font(AgentMeterTypography.regular(14, relativeTo: .footnote))
                            .foregroundStyle(AgentMeterTheme.mutedInk)
                    }
                    .listRowBackground(AgentMeterTheme.warning.opacity(0.08))
                }

                if !preview.issues.isEmpty {
                    Section("Linhas não importadas") {
                        ForEach(preview.issues) { issue in
                            Text(issue.line > 0 ? "Linha \(issue.line): \(issue.message)" : issue.message)
                                .foregroundStyle(AgentMeterTheme.warning)
                        }
                    }
                }
            }
            .navigationTitle("Revisar importação")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importar") {
                        let count = store.importSubscriptions(preview.subscriptions)
                        importedCount = count
                        if count > 0 {
                            Task { await RenewalNotificationScheduler.scheduleAll(store.subscriptions) }
                        }
                    }
                    .disabled(preview.subscriptions.isEmpty || importedCount != nil)
                }
            }
            .alert("Importação concluída", isPresented: Binding(
                get: { importedCount != nil },
                set: { if !$0 { importedCount = nil } }
            )) {
                Button("Concluído") { dismiss() }
            } message: {
                Text("\(importedCount ?? 0) assinatura(s) adicionada(s).")
            }
        }
    }

    private func localized(_ key: String) -> String {
        (AppLanguage(rawValue: languageCode) ?? .portuguese).localized(key)
    }
}

/// The first-plan path intentionally omits advanced tax and reminder settings.
/// Those remain editable later in the full subscription editor.
struct QuickSubscriptionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: SubscriptionStore

    @State private var provider: AgentMeterProvider
    @State private var planName = ""
    @State private var price = ""
    @State private var cycle = BillingCycle.monthly
    @State private var renewalDate = Date()

    init(initialProvider: AgentMeterProvider = .claude) {
        _provider = State(initialValue: initialProvider)
    }

    private var parsedPrice: Decimal? {
        Decimal(
            string: price.replacingOccurrences(of: ",", with: "."),
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private var canSave: Bool {
        !planName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (parsedPrice ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Adicione o essencial agora. Impostos e alertas podem ser ajustados depois.")
                        .foregroundStyle(AgentMeterTheme.mutedInk)
                }

                Section("Serviço") {
                    Picker("Provedor", selection: $provider) {
                        ForEach(AgentMeterProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField("Nome do plano", text: $planName)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("quick-plan-name")
                }

                Section("Cobrança") {
                    LabeledContent("Preço") {
                        TextField("R$ 0,00", text: $price)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("quick-price")
                    }
                    Picker("Ciclo", selection: $cycle) {
                        Text("Mensal").tag(BillingCycle.monthly)
                        Text("Anual").tag(BillingCycle.yearly)
                    }
                    DatePicker("Próxima renovação", selection: $renewalDate, displayedComponents: .date)
                }
            }
            .navigationTitle("Seu primeiro plano")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Agora não") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Começar") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                        .accessibilityIdentifier("quick-save")
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func save() {
        guard let parsedPrice else { return }
        let subscription = AISubscription(
            provider: provider,
            planName: planName,
            basePriceBRL: parsedPrice,
            billingCycle: cycle,
            nextRenewalDate: renewalDate
        )
        store.add(subscription)
        Task { await RenewalNotificationScheduler.schedule(subscription) }
        dismiss()
    }
}

struct SubscriptionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: SubscriptionStore
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.portuguese.rawValue
    @State private var provider = AgentMeterProvider.claude
    @State private var planName = ""
    @State private var price = ""
    @State private var tax = "0"
    @State private var cycle = BillingCycle.monthly
    @State private var renewalDate = Date()
    @State private var reminderDays = 3
    private let existingSubscription: AISubscription?

    init(subscription: AISubscription? = nil, initialProvider: AgentMeterProvider? = nil) {
        existingSubscription = subscription
        _provider = State(initialValue: subscription?.provider ?? initialProvider ?? .claude)
        _planName = State(initialValue: subscription?.planName ?? "")
        _price = State(initialValue: subscription.map { NSDecimalNumber(decimal: $0.basePriceBRL).stringValue } ?? "")
        _tax = State(initialValue: subscription.map { NSDecimalNumber(decimal: $0.taxPercentage).stringValue } ?? "0")
        _cycle = State(initialValue: subscription?.billingCycle ?? .monthly)
        _renewalDate = State(initialValue: subscription?.nextRenewalDate ?? Date())
        _reminderDays = State(initialValue: subscription?.reminderDaysBefore ?? 3)
    }

    private var parsedPrice: Decimal? { decimal(price) }
    private var canSave: Bool {
        (parsedPrice ?? 0) > 0 && !planName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: AgentMeterTheme.Space.sm) {
                        AgentMeterProviderBadge(provider: provider)
                        VStack(alignment: .leading, spacing: AgentMeterTheme.Space.xxs) {
                            Text(existingSubscription == nil ? "Nova assinatura" : "Editar assinatura")
                                .font(AgentMeterTypography.bold(20, relativeTo: .headline))
                            Text("Valores informados por você")
                                .font(AgentMeterTypography.regular(13, relativeTo: .caption))
                                .foregroundStyle(AgentMeterTheme.mutedInk)
                        }
                    }
                }
                .listRowBackground(AgentMeterTheme.surface)

                Section {
                    Picker("Provedor", selection: $provider) {
                        ForEach(AgentMeterProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField(
                        "",
                        text: $planName,
                        prompt: Text("Nome do plano").foregroundColor(AgentMeterTheme.mutedInk)
                    )
                        .textInputAutocapitalization(.words)
                } header: {
                    technicalHeader("Plano")
                }
                .listRowBackground(AgentMeterTheme.surface)

                Section {
                    LabeledContent("Preço") {
                        TextField(
                            "",
                            text: $price,
                            prompt: Text("R$ 0,00").foregroundColor(AgentMeterTheme.mutedInk)
                        )
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Impostos") {
                        HStack(spacing: AgentMeterTheme.Space.xxs) {
                            TextField("0", text: $tax)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("%")
                                .foregroundStyle(AgentMeterTheme.mutedInk)
                        }
                    }
                    Picker("Ciclo", selection: $cycle) {
                        Text("Mensal").tag(BillingCycle.monthly)
                        Text("Anual").tag(BillingCycle.yearly)
                    }
                    DatePicker("Próxima renovação", selection: $renewalDate, displayedComponents: .date)
                    Stepper(reminderTitle, value: $reminderDays, in: 0...30)
                } header: {
                    technicalHeader("Cobrança")
                }
                .listRowBackground(AgentMeterTheme.surface)

                Section {
                    Label {
                        Text("Os valores são informados por você. O AgentMeter não estima nem altera preços automaticamente.")
                    } icon: {
                        Image(systemName: "checkmark.shield")
                            .foregroundStyle(AgentMeterTheme.nominal)
                    }
                    .font(AgentMeterTypography.regular(13, relativeTo: .footnote))
                    .foregroundStyle(AgentMeterTheme.mutedInk)
                }
                .listRowBackground(AgentMeterTheme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(AgentMeterTheme.background)
            .navigationTitle(existingSubscription == nil ? "Nova assinatura" : "Editar assinatura")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AgentMeterTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tint(AgentMeterTheme.signal)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
        .font(AgentMeterTypography.regular(17))
        .presentationDragIndicator(.visible)
    }

    private func technicalHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(AgentMeterTypography.fixedBold(12))
            .textCase(.uppercase)
            .tracking(1.15)
            .foregroundStyle(AgentMeterTheme.mutedInk)
    }

    private func save() {
        guard let parsedPrice else { return }
        let subscription = AISubscription(
            id: existingSubscription?.id ?? UUID(),
            provider: provider,
            planName: planName,
            basePriceBRL: parsedPrice,
            taxPercentage: decimal(tax) ?? 0,
            billingCycle: cycle,
            nextRenewalDate: renewalDate,
            reminderDaysBefore: reminderDays
        )
        if existingSubscription == nil {
            store.add(subscription)
        } else {
            store.update(subscription)
        }
        Task { await RenewalNotificationScheduler.schedule(subscription) }
        dismiss()
    }

    private func decimal(_ value: String) -> Decimal? {
        Decimal(string: value.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX"))
    }

    private var reminderTitle: String {
        let language = AppLanguage(rawValue: languageCode) ?? .portuguese
        return String(
            format: language.localized("Alertar %lld dias antes"),
            locale: language.locale,
            Int64(reminderDays)
        )
    }
}

func brl(_ value: Decimal) -> String {
    NSDecimalNumber(decimal: value).doubleValue.formatted(
        .currency(code: "BRL").locale(AppLanguage.selected.locale)
    )
}

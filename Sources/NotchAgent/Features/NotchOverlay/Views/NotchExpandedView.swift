import SwiftUI
import AgentMeterCore
import UniformTypeIdentifiers

/// Expanded gauge panel: stick-style pager with NOW / BURN / RHYTHM pages.
struct NotchExpandedView: View {
    @Environment(UsageStore.self) private var store
    @Environment(NotchViewModel.self) private var viewModel
    @Environment(WindowRouter.self) private var router
    @EnvironmentObject private var spending: SubscriptionStore

    @State private var rhythmToday = false
    @State private var apiDashboardVisible = false
    @State private var selectedAPIAccount: UUID?
    @State private var draggedAPIAccountID: UUID?
    @State private var dropTargetAPIAccountID: UUID?
    @State private var hoveredAPIAccountID: UUID?

    var body: some View {
        @Bindable var viewModel = viewModel

        TimelineView(.periodic(from: .now, by: 30)) { _ in
            VStack(spacing: 10) {
                header
                coralRule
                if let incident = store.activeIncident {
                    incidentLine(incident)
                }
                ZStack {
                    Group {
                        switch viewModel.expandedPage {
                        case 1: burnPage
                        case 2: rhythmPage
                        case 3: modelsPage
                        case 4: gptModelsPage
                        case 5: apiAccountsPage
                        default: nowPage
                        }
                    }
                    .id(viewModel.expandedPage)
                    .transition(.asymmetric(
                        insertion: .move(edge: viewModel.pageDirection).combined(with: .opacity),
                        removal: .move(edge: viewModel.pageDirection == .trailing ? .leading : .trailing)
                            .combined(with: .opacity)
                    ))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                footer
                // The dino-game strip doubles as the panel's ground line;
                // difficulty tracks the real session gauge.
                if store.settings.runnerEnabled {
                    let game = store.runnerGame
                    NotchRunnerView(
                        usedPercent: game.used,
                        isGameOver: game.gameOver,
                        resetsAt: game.resetsAt,
                        obstacleTint: game.obstacleTint
                    )
                    .frame(height: 26)
                    .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, viewModel.geometry.hasNotch ? viewModel.geometry.topInset + 6 : 12)
            .padding(.bottom, 12)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            PixelGlyph(distress: distress)
                .frame(width: 22, height: 18)
            Text("NOTCHAGENT")
                .font(Theme.label(11))
                .kerning(2)
                .foregroundStyle(Theme.coral)
            Spacer()
            if store.isPaused {
                StatusPill(text: "Paused", color: Theme.warning)
            }
            Button {
                router.openSpending()
            } label: {
                GaugeLabel(text: "PAGO " + spending.format(spending.monthlySpend.paidBRL, compact: true), color: Theme.coral, size: 8)
            }
            .buttonStyle(.plain)
            .help("Gasto confirmado neste mês")
            if !apiRows.isEmpty {
                Button { viewModel.goToPage(5) } label: {
                    GaugeLabel(text: "APIs \(apiRows.count)", color: Theme.ok, size: 8)
                }
                .buttonStyle(.plain)
                .help("Abrir custo e quota das APIs")
            }
            GaugeLabel(text: updatedText, color: Theme.textFaint, size: 8)
            Button {
                viewModel.togglePin()
            } label: {
                Image(systemName: viewModel.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(viewModel.isPinned ? Theme.coral : Theme.textDim)
                    .padding(5)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.surfaceRaised))
            }
            .buttonStyle(.plain)
            .help(viewModel.isPinned ? "Unpin and close panel" : "Keep panel open")
            Button {
                viewModel.collapseNow()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textDim)
                    .padding(5)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.surfaceRaised))
            }
            .buttonStyle(.plain)
            .help("Close panel")
        }
    }

    /// The mascot sweats as the busiest window drains.
    private var distress: Double {
        let worstUsed = ProviderID.allCases
            .compactMap { GaugeMetric.from(store.snapshots[$0])?.used }
            .max() ?? 0
        return worstUsed / 100
    }

    private var updatedText: String {
        let lastSuccess = store.refreshStates.values
            .compactMap { state -> Date? in
                if case .success(let date) = state { date } else { nil }
            }
            .max()
        guard let lastSuccess else { return "waiting…" }
        return "updated \(Format.relative(lastSuccess))"
    }

    private var coralRule: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Theme.coral, Theme.coral.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 2)
    }

    private func incidentLine(_ incident: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 8))
                .foregroundStyle(Theme.warning)
            Text("Anthropic incident: \(incident)")
                .font(Theme.body(9.5, weight: .semibold))
                .foregroundStyle(Theme.warning)
                .lineLimit(1)
            Spacer()
        }
    }

    // MARK: Pages

    /// Claude Code and Codex always keep equal, detailed cards. A temporary
    /// quota-probe failure must not collapse Claude into a status strip.
    private var nowPage: some View {
        let cardProviders: [ProviderID] = [.claudeCode, .codex]
        let stripProviders = ProviderID.allCases.filter { !cardProviders.contains($0) }

        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                ForEach(cardProviders) { provider in
                    ProviderCardView(
                        snapshot: store.snapshots[provider],
                        provider: provider,
                        attention: store.attention(for: provider),
                        refreshState: store.refreshStates[provider] ?? .idle,
                        burn: store.burnProjection(for: provider)
                    )
                }
            }
            .frame(maxHeight: .infinity)
            ForEach(stripProviders) { provider in
                providerStrip(provider)
            }
        }
    }

    private func providerStrip(_ provider: ProviderID) -> some View {
        let snapshot = store.snapshots[provider]
        return HStack(spacing: 8) {
            Image(systemName: provider.symbolName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.textDim)
            GaugeLabel(text: provider.shortName, color: Theme.textSecondary, size: 9)
            if let health = snapshot?.health {
                StatusPill(text: health.badgeText, color: health == .ok ? Theme.ok : Theme.textDim)
            }
            if let note = snapshot?.note {
                Text(note)
                    .font(Theme.body(9))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.surface.opacity(0.7))
        )
    }

    // MARK: API Accounts

    private var apiUsage: [APIAccountUsage] {
        (store.snapshots[.apiAccounts]?.accountUsage ?? [])
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    private var apiRows: [APIAccountDashboardRow] {
        let configuredAccounts = store.settings.apiAccounts.isEmpty
            ? store.settings.monitoredAPIServices.map { service in
                APIAccount(
                    service: service,
                    identifier: store.settings.apiAccountIdentifiers[service] ?? "",
                    keychainAccount: service.rawValue
                )
            }
            : store.settings.apiAccounts
        let configured = configuredAccounts.filter {
            $0.enabled && !$0.service.isSubscriptionService
        }
        return configured.map { account in
            APIAccountDashboardRow(account: account, usage: apiUsage.first { $0.accountID == account.id })
        }
    }

    private var connectedSubscriptionRows: [APIAccountDashboardRow] {
        let configuredAccounts = store.settings.apiAccounts.isEmpty
            ? [] : store.settings.apiAccounts
        return configuredAccounts
            .filter { $0.enabled && $0.service.isSubscriptionService }
            .map { account in
                APIAccountDashboardRow(
                    account: account,
                    usage: apiUsage.first { $0.accountID == account.id }
                )
            }
    }

    private var apiAccountsExcludedFromTotal: Set<UUID> {
        APIAccountBilling.excludedFromTotal(apiUsage)
    }

    private var totalKnownAPISpendBRL: String? {
        let excluded = apiAccountsExcludedFromTotal
        let spends = apiUsage.compactMap { usage -> Double? in
            guard !excluded.contains(usage.accountID) else { return nil }
            return usage.rolling30DaySpendUSD
        }
        guard !spends.isEmpty else { return nil }
        return brlText(fromUSD: spends.reduce(0, +))
    }

    private var totalMonthlyPlanBRL: String? {
        let dedicatedSubscriptionServices = Set(connectedSubscriptionRows.map(\.account.service))
        let apiPlanRows = apiRows.filter { row in
            if row.account.service == .firecrawl {
                return !dedicatedSubscriptionServices.contains(.firecrawlSubscription)
            }
            return true
        }
        let plans = (connectedSubscriptionRows + apiPlanRows)
            .compactMap { monthlyPlanBRL(for: $0.account, usage: $0.usage) }
        guard !plans.isEmpty else { return nil }
        return brlValueText(plans.reduce(0, +))
    }

    private var apiAccountsPage: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    GaugeLabel(text: "APIs · consumo e saldo", color: Theme.textSecondary, size: 9.5)
                    Text(apiDashboardHeadline)
                        .font(Theme.body(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    if let totalMonthlyPlanBRL {
                        GaugeLabel(text: "ASSINATURAS / MÊS", color: Theme.textDim, size: 8)
                        Text(totalMonthlyPlanBRL)
                            .font(Theme.numeral(13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if let totalKnownAPISpendBRL {
                        GaugeLabel(
                            text: apiUsage.contains { $0.spendPeriod == .rolling28Days }
                                ? "TOTAL 30D · GOOGLE 28D À PARTE"
                                : "CONSUMIDO 30 DIAS",
                            color: Theme.textDim,
                            size: 8
                        )
                        Text(totalKnownAPISpendBRL)
                            .font(Theme.numeral(16))
                            .foregroundStyle(Theme.coral)
                    }
                }
                .help(
                    "ASSINATURAS/MÊS soma planos fixos. TOTAL 30D soma só contas com "
                    + "janela de 30 dias corridos oficial — contas com mês-calendário "
                    + "(ex: Anthropic API), 28 dias (Google) ou billing compartilhado "
                    + "com outra conta ficam de fora, mesmo com valor próprio no card."
                )
                Button {
                    AppEnvironment.shared.scheduler.refreshNow()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(6)
                        .background(Circle().fill(Theme.surfaceRaised))
                }
                .buttonStyle(.plain)
                .disabled(apiIsRefreshing)
                .help("Atualizar leituras de API agora")
                .accessibilityLabel("Atualizar leituras de API agora")
            }
            GaugeLabel(
                text: apiIsRefreshing
                    ? "ATUALIZANDO LEITURAS"
                    : "\(apiRefreshCaption) · PERÍODO \(apiSpendWindowCaption)",
                color: Theme.textFaint,
                size: 8
            )

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 7) {
                    if !connectedSubscriptionRows.isEmpty {
                        dashboardSectionLabel(
                            title: "ASSINATURAS CONECTADAS",
                            subtitle: "não contam como consumo de API"
                        )
                        ForEach(connectedSubscriptionRows) { row in
                            apiAccountRow(row)
                        }
                        dashboardSectionLabel(
                            title: "CONTAS DE API",
                            subtitle: "uso, saldo e quotas"
                        )
                    }
                    if !apiRows.contains(where: { $0.account.service == .anthropicAPI }) {
                        anthropicAPIPlaceholder
                    }
                    ForEach(Array(apiRows.enumerated()), id: \.element.id) { index, row in
                        apiAccountRow(row)
                            .onDrop(
                                of: [UTType.plainText],
                                delegate: APIAccountCardDropDelegate(
                                    targetID: row.id,
                                    draggedID: $draggedAPIAccountID,
                                    dropTargetID: $dropTargetAPIAccountID,
                                    move: moveAPIAccount
                                )
                            )
                            .opacity(apiDashboardVisible ? 1 : 0)
                            .offset(y: apiDashboardVisible ? 0 : 8)
                            .animation(.spring(duration: 0.35, bounce: 0.16).delay(min(Double(index) * 0.025, 0.2)), value: apiDashboardVisible)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .onAppear { apiDashboardVisible = true }
        .onDisappear { apiDashboardVisible = false }
    }

    private func dashboardSectionLabel(title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            GaugeLabel(text: title, color: Theme.textSecondary, size: 8.5)
            Spacer()
            GaugeLabel(text: subtitle.uppercased(), color: Theme.textFaint, size: 7.5)
        }
        .padding(.horizontal, 3)
        .padding(.top, 3)
    }

    private var anthropicAPIPlaceholder: some View {
        Button {
            router.openSettings()
        } label: {
            HStack(spacing: 9) {
                APIServiceLogo(service: .anthropicConsole)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Anthropic API")
                        .font(Theme.body(10.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Nenhuma organização API conectada")
                        .font(Theme.body(8.5))
                        .foregroundStyle(Theme.textFaint)
                }
                Spacer()
                StatusPill(text: "NÃO CONFIGURADA", color: Theme.textDim)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.surface.opacity(0.58))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Theme.textDim.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Anthropic API, não configurada")
        .accessibilityHint("Abre os ajustes")
    }

    private func apiAccountRow(_ row: APIAccountDashboardRow) -> some View {
        let account = row.account
        let usage = row.usage
        let selected = selectedAPIAccount == account.id
        let refreshState = store.accountRefreshState(account.id)
        return Button {
            if isXService(account.service),
               monthlySpendUSD(for: usage) == nil,
               balanceUSD(for: usage) == nil {
                router.openSettings()
                return
            }
            withAnimation(.spring(duration: 0.28, bounce: 0.18)) {
                selectedAPIAccount = selected ? nil : account.id
            }
        } label: {
            VStack(alignment: .leading, spacing: selected ? 8 : 0) {
                HStack(spacing: 9) {
                    APIServiceLogo(service: account.service)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(account.label)
                            .font(Theme.body(13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text(selected ? (usage?.summary ?? pendingSummary(for: account)) : accountSubtitle(usage, account: account))
                            .font(Theme.body(10.5))
                            .foregroundStyle(Theme.textFaint)
                            .lineLimit(selected ? 3 : 1)
                        GaugeLabel(
                            text: accountRefreshCaption(refreshState),
                            color: accountRefreshColor(refreshState),
                            size: 7.5
                        )
                        .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    accountValue(usage, account: account)
                    Group {
                        if case .refreshing = refreshState {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(Theme.textDim)
                        }
                    }
                    .frame(width: 20, height: 32)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        AppEnvironment.shared.scheduler.refreshAPIAccount(account.id)
                    }
                    .help("Atualizar apenas \(account.label)")
                    .accessibilityLabel("Atualizar apenas \(account.label)")
                    .accessibilityAddTraits(.isButton)
                    Image(systemName: selected ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.textFaint)
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(dropTargetAPIAccountID == account.id ? Theme.coral : Theme.textDim)
                        .frame(width: 22, height: 44)
                        .contentShape(Rectangle())
                        .opacity(
                            hoveredAPIAccountID == account.id || draggedAPIAccountID != nil
                                ? 0.9
                                : 0.32
                        )
                        .onDrag {
                            draggedAPIAccountID = account.id
                            return NSItemProvider(object: account.id.uuidString as NSString)
                        } preview: {
                            HStack(spacing: 8) {
                                APIServiceLogo(service: account.service)
                                Text(account.label)
                                    .font(Theme.body(10, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            .padding(.horizontal, 14)
                            .frame(width: 260, height: 48, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Theme.surfaceRaised)
                                    .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
                            )
                        }
                        .help("Arraste para reorganizar")
                        .accessibilityLabel("Reorganizar \(account.label)")
                }
                if selected {
                    financialSourceDetails(account: account, usage: usage)
                    if !(usage?.verificationFindings?.isEmpty ?? true) {
                        GaugeLabel(
                            text: "DIVERGÊNCIA ENTRE FONTES OFICIAIS",
                            color: Theme.warning,
                            size: 8.5
                        )
                    }
                    if apiAccountsExcludedFromTotal.contains(account.id) {
                        GaugeLabel(
                            text: "MESMA CONTA DE BILLING · FORA DO TOTAL 30D",
                            color: Theme.warning,
                            size: 8.5
                        )
                    }
                    rechargeDetail(usage)
                    cycleDetail(usage)
                    if let reset = usage?.resetsAt {
                        GaugeLabel(text: "RESETA EM \(Format.countdown(to: reset))", color: Theme.textDim, size: 8.5)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: selected ? 108 : 72, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? Theme.surfaceRaised : Theme.surface.opacity(0.82))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                dropTargetAPIAccountID == account.id
                                    ? Theme.coral.opacity(0.85)
                                    : (hasMeasuredValue(usage) ? Theme.ok : Theme.textDim).opacity(selected ? 0.7 : 0.24),
                                lineWidth: dropTargetAPIAccountID == account.id ? 1.5 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(dropTargetAPIAccountID == account.id ? 1.008 : 1)
        .animation(.spring(duration: 0.22, bounce: 0.12), value: dropTargetAPIAccountID)
        .onHover { hovering in
            if hovering {
                hoveredAPIAccountID = account.id
            } else if hoveredAPIAccountID == account.id {
                hoveredAPIAccountID = nil
            }
        }
        .accessibilityLabel("\(account.label), \(usage?.summary ?? pendingSummary(for: account))")
        .accessibilityHint(
            isXService(account.service) && monthlySpendUSD(for: usage) == nil && balanceUSD(for: usage) == nil
                ? "Abre Settings para conectar o Console X"
                : "Expande os detalhes da conta"
        )
    }

    private func moveAPIAccount(_ sourceID: UUID, _ targetID: UUID) {
        let current = store.preferences.settings.apiAccounts
        let reordered = APIAccountOrdering.moving(current, sourceID: sourceID, targetID: targetID)
        guard reordered.map(\.id) != current.map(\.id) else { return }
        withAnimation(.spring(duration: 0.26, bounce: 0.14)) {
            store.preferences.settings.apiAccounts = reordered
        }
    }

    private var apiDashboardHeadline: String {
        guard !apiRows.isEmpty else { return "Configure uma conta de API" }
        var seenFinancialScopes = Set<String>()
        let financial = apiRows.filter { row in
            guard monthlySpendUSD(for: row.usage) != nil
                    || balanceUSD(for: row.usage) != nil
                    || row.usage?.monthlySpendBRL != nil
                    || row.usage?.monthlyPlanBRL != nil
                    || row.usage?.balanceBRL != nil
            else { return false }
            guard let scope = row.usage?.billingScopeID else { return true }
            return seenFinancialScopes.insert(scope).inserted
        }.count
        let anthropic = apiRows.contains { $0.account.service == .anthropicAPI }
            ? ""
            : " · Anthropic não configurada"
        return "\(apiRows.count) contas API · \(financial) em R$\(anthropic)"
    }

    private func monthlySpendUSD(for usage: APIAccountUsage?) -> Double? {
        financialSummary(for: usage).consumedUSD
    }

    private var apiSpendWindowCaption: String {
        let bounds = apiUsage.compactMap { usage -> (Date, Date)? in
            guard usage.spendPeriod == .rolling30Days,
                  let start = usage.spendWindowStart,
                  let end = usage.spendWindowEnd
            else { return nil }
            return (start, end)
        }
        let fallback = APIAccountSpendWindow.rolling30Days()
        let start = bounds.map(\.0).min() ?? fallback.start
        let end = bounds.map(\.1).max() ?? fallback.end
        return "\(shortUTCDate(start))–\(shortUTCDate(end)) UTC"
    }

    private func shortUTCDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: date)
    }

    private func balanceUSD(for usage: APIAccountUsage?) -> Double? {
        financialSummary(for: usage).remainingUSD
    }

    private func financialSummary(for usage: APIAccountUsage?) -> APIAccountFinancialSummary {
        APIAccountFinancialSummary(usage: usage)
    }

    private func accountSubtitle(_ usage: APIAccountUsage?, account: APIAccount) -> String {
        if !(usage?.verificationFindings?.isEmpty ?? true) {
            return "Divergência entre API e portal acima da tolerância"
        }
        if let usage,
           let status = usage.readStatus,
           status != .updated,
           status != .partial {
            return usage.summary
        }
        let financial = financialSummary(for: usage)
        if account.service == .gemini, let usage, financial.consumedUSD == nil {
            return usage.usedPercent == nil
                ? "Google Cloud conectado · sem atividade de quota recente"
                : "Quota oficial do Google Cloud"
        }
        if let plan = monthlyPlanBRL(for: account, usage: usage) {
            let name = usage?.planName.map { "Plano \($0)" } ?? "Plano mensal"
            let seats = usage?.seatCount.map { " · \($0) licenças" } ?? ""
            return account.service.isSubscriptionService
                ? "\(name)\(seats) · assinatura \(brlValueText(plan))/mês"
                : "\(name)\(seats) · custo recorrente \(brlValueText(plan))/mês"
        }
        if account.service == .xTwitter || account.service == .xTwitterAccount1 || account.service == .xTwitterAccount2,
           monthlySpendUSD(for: usage) != nil {
            return "Consumo da API · recargas não são gasto"
        }
        if isXService(account.service), monthlySpendUSD(for: usage) == nil, balanceUSD(for: usage) == nil {
            return "Conecte o Console X em Settings para ver valores em R$"
        }
        if isSharedXProject(usage) {
            return financial.consumedUSD != nil || financial.remainingUSD != nil
                ? "Projeto X compartilhado · financeiro contado uma vez"
                : "Quota compartilhada do mesmo projeto X"
        }
        if financial.isComplete {
            return financial.spendPeriod == .currentCalendarMonth
                ? "Consumido no mês atual · restante agora"
                : "Consumido nos últimos \(financial.consumedDays ?? 30) dias · restante agora"
        }
        if financial.consumedUSD != nil {
            if account.service == .gemini {
                return "Janela oficial de 28 dias do Google AI Studio"
            }
            if financial.spendPeriod == .currentCalendarMonth {
                return "Custo do mês-calendário atual · saldo não informado"
            }
            return "Consumo real de \(financial.consumedDays ?? 30) dias · saldo não informado pela API"
        }
        if financial.remainingUSD != nil {
            return "Saldo medido · consumo não informado pela API"
        }
        if usage?.cycleUsed != nil { return "Quota de créditos do ciclo atual" }
        return pendingSummary(for: account)
    }

    @ViewBuilder
    private func accountValue(_ usage: APIAccountUsage?, account: APIAccount) -> some View {
        let finance = APIAccountFinancePresentation(
            account: account,
            usage: usage,
            brlPerUSD: spending.brlPerUSD
        )
        HStack(spacing: 8) {
            financialMetric(
                label: finance.spendLabel,
                metric: finance.spend,
                color: Theme.coral
            )
            metricDivider
            financialMetric(
                label: "SALDO ATUAL",
                metric: finance.balance,
                color: Theme.ok
            )
            metricDivider
            financialMetric(
                label: account.service.isSubscriptionService ? "ASSINATURA MENSAL" : "PLANO MENSAL",
                metric: finance.plan,
                color: Theme.textSecondary
            )
        }
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Theme.textDim.opacity(0.2))
            .frame(width: 1, height: 40)
    }

    private func financialMetric(
        label: String,
        metric: APIAccountMoneyPresentation,
        color: Color
    ) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            GaugeLabel(text: label, color: Theme.textDim, size: 8)
                .lineLimit(1)
            Text(metric.amountBRL.map(brlValueText) ?? "—")
                .font(Theme.numeral(14))
                .monospacedDigit()
                .foregroundStyle(metric.amountBRL == nil ? Theme.textDim : color)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            GaugeLabel(
                text: metric.confidence.label,
                color: metric.confidence == .derived ? Theme.caution : Theme.textFaint,
                size: 7
            )
            .lineLimit(1)
        }
        .frame(width: 108, alignment: .trailing)
        .accessibilityElement(children: .combine)
    }

    private func financialSourceDetails(account: APIAccount, usage: APIAccountUsage?) -> some View {
        let finance = APIAccountFinancePresentation(
            account: account,
            usage: usage,
            brlPerUSD: spending.brlPerUSD
        )
        return HStack(spacing: 8) {
            GaugeLabel(text: "GASTO: \(finance.spend.confidence.label)", color: Theme.textDim, size: 8)
            GaugeLabel(text: "SALDO: \(finance.balance.confidence.label)", color: Theme.textDim, size: 8)
            GaugeLabel(text: "PLANO: \(finance.plan.confidence.label)", color: Theme.textDim, size: 8)
        }
    }

    @ViewBuilder
    private func rechargeDetail(_ usage: APIAccountUsage?) -> some View {
        if let recharge = usage?.rechargeBRL {
            GaugeLabel(text: "RECARGAS NO PERÍODO \(brlValueText(recharge))", color: Theme.textSecondary, size: 8.5)
        } else if let recharge = usage?.rechargeUSD,
                  let converted = brlText(fromUSD: recharge) {
            GaugeLabel(text: "RECARGAS NO PERÍODO \(converted)", color: Theme.textSecondary, size: 8.5)
        }
    }

    private func readStatusLabel(_ status: APIAccountReadStatus?) -> String {
        switch status {
        case .updated: "ATUALIZADO"
        case .partial: "PARCIAL"
        case .needsCredential: "SEM CREDENCIAL"
        case .needsLogin: "RECONECTAR"
        case .unavailable: "ERRO DE LEITURA"
        case .stale: "DESATUALIZADO"
        case nil: "SEM LEITURA"
        }
    }

    private func accountRefreshCaption(_ state: RefreshState) -> String {
        switch state {
        case .idle:
            "AGUARDANDO"
        case .refreshing:
            "ATUALIZANDO"
        case .success(let date):
            "ATUALIZADO \(Format.relative(date))"
        case .stale(let date):
            "DESATUALIZADO \(Format.relative(date))"
        case .failure(_, let error):
            "ERRO · \(error)"
        }
    }

    private func accountRefreshColor(_ state: RefreshState) -> Color {
        switch state {
        case .success:
            Theme.ok
        case .refreshing:
            Theme.caution
        case .stale:
            Theme.warning
        case .failure:
            Theme.coral
        case .idle:
            Theme.textDim
        }
    }

    private func isXService(_ service: APIServiceID) -> Bool {
        service == .xTwitter || service == .xTwitterAccount1 || service == .xTwitterAccount2
    }

    private func isSharedXProject(_ usage: APIAccountUsage?) -> Bool {
        guard let usage,
              usage.service == .xTwitter || usage.service == .xTwitterAccount1 || usage.service == .xTwitterAccount2,
              let scope = usage.billingScopeID
        else { return false }
        return apiUsage.filter { $0.billingScopeID == scope }.count > 1
    }

    private func monthlyPlanBRL(for account: APIAccount, usage: APIAccountUsage?) -> Decimal? {
        if let official = usage?.monthlyPlanBRL { return official }
        if let configured = account.monthlyPlanBRL { return configured }
        guard let usd = usage?.monthlyPlanUSD, let rate = spending.brlPerUSD else { return nil }
        return Decimal(usd) * rate
    }

    private func hasMeasuredValue(_ usage: APIAccountUsage?) -> Bool {
        usage?.monetaryUSD != nil
            || usage?.monthlySpendUSD != nil
            || usage?.monthlySpendBRL != nil
            || usage?.balanceUSD != nil
            || usage?.monthlyPlanUSD != nil
            || usage?.monthlyPlanBRL != nil
            || usage?.balanceBRL != nil
            || usage?.cycleUsed != nil
    }

    private func brlValueText(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "BRL"
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.maximumFractionDigits = value >= 100 ? 0 : 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "R$ —"
    }

    private func brlText(fromUSD amountUSD: Double) -> String? {
        guard let rate = spending.brlPerUSD else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "BRL"
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.maximumFractionDigits = amountUSD * NSDecimalNumber(decimal: rate).doubleValue >= 100 ? 0 : 2
        formatter.minimumFractionDigits = 2
        let value = Decimal(amountUSD) * rate
        return formatter.string(from: value as NSDecimalNumber)
    }

    private func moneyLabel(for account: APIAccountUsage?) -> String {
        switch account?.monetaryKind {
        case .spend: "GASTO"
        case .balance: "SALDO"
        case .remaining: "RESTANTE"
        case nil: "VALOR"
        }
    }

    @ViewBuilder
    private func cycleDetail(_ usage: APIAccountUsage?) -> some View {
        if let balance = usage?.balanceBRL {
            GaugeLabel(
                text: "CRÉDITOS DE USO \(brlValueText(balance))",
                color: balance >= 0 ? Theme.ok : Theme.coral,
                size: 8.5
            )
        } else if let used = usage?.cycleUsed, let limit = usage?.cycleLimit, let unit = usage?.cycleUnit {
            let remaining = usage?.cycleRemaining ?? max(limit - used, 0)
            let overage = usage?.cycleOverage ?? 0
            HStack(spacing: 8) {
                GaugeLabel(text: "CONSUMIDO \(cycleAmountText(used, unit: unit))", color: Theme.coral, size: 8.5)
                GaugeLabel(
                    text: overage > 0
                        ? "EXCEDENTE \(cycleAmountText(overage, unit: unit))"
                        : "SALDO \(cycleAmountText(remaining, unit: unit))",
                    color: overage > 0 ? Theme.coral : Theme.ok,
                    size: 8.5
                )
            }
        } else if usage?.monetaryKind == .balance {
            GaugeLabel(text: "CONSUMO DESDE A RECARGA: API NÃO INFORMOU", color: Theme.textDim, size: 8.5)
        } else if usage?.monetaryKind == .spend {
            GaugeLabel(text: "GASTO NO PERÍODO INFORMADO PELA API", color: Theme.coral, size: 8.5)
        } else if usage == nil {
            GaugeLabel(text: "AGUARDANDO ENDPOINT OU ESCOPO DE LEITURA", color: Theme.textDim, size: 8.5)
        }
    }

    private func compactAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.maximumFractionDigits = 0
        return formatter.string(from: value as NSNumber) ?? String(Int(value.rounded()))
    }

    private func cycleAmountText(_ value: Double, unit: String) -> String {
        if unit.uppercased() == "USD", let brl = brlText(fromUSD: value) {
            return brl
        }
        return "\(compactAmount(value)) \(unit.uppercased())"
    }

    private func pendingSummary(for account: APIAccount) -> String {
        switch account.service {
        case .xTwitter, .xTwitterAccount1, .xTwitterAccount2:
            "X: salve o Bearer Token e conecte o Developer Console para ler quota, gasto e saldo"
        case .twitterAPI:
            "twitterapi.io: salve a chave e conecte a conta para ler saldo e gasto"
        case .gemini:
            "Google: login gcloud ausente ou sem autorização para Cloud Monitoring"
        case .anthropicConsole:
            "Claude: conecte sua conta atual para ler plano, limites e créditos"
        case .chatGPTSubscription:
            "ChatGPT: conecte sua conta e abra Settings → Billing"
        case .googleSubscription:
            "Google AI: conecte a conta pagadora em Assinaturas e serviços"
        case .firecrawlSubscription:
            "Firecrawl: conecte a conta pagadora e abra Billing"
        case .anthropicAPI:
            "Anthropic API: conecte o Claude Console para ler o custo do mês atual"
        default:
            APIAccountCredentialStore.key(for: account) == nil
                ? "Chave de leitura ausente ou associada a outro serviço"
                : "Aguardando resposta da API"
        }
    }

    private var apiIsRefreshing: Bool {
        guard let state = store.refreshStates[.apiAccounts] else { return false }
        if case .refreshing = state { return true }
        return false
    }

    private var apiRefreshCaption: String {
        guard let state = store.refreshStates[.apiAccounts] else { return "AGUARDANDO PRIMEIRA LEITURA" }
        switch state {
        case .success(let date):
            return "ATUALIZADO \(Format.relative(date))"
        case .stale(let date):
            return "DESATUALIZADO \(Format.relative(date))"
        case .failure:
            return "ÚLTIMA LEITURA FALHOU"
        case .idle:
            return "AGUARDANDO PRIMEIRA LEITURA"
        case .refreshing:
            return "ATUALIZANDO LEITURAS"
        }
    }

    private func riskColor(_ used: Double) -> Color {
        Theme.riskTint(
            used: used,
            projectedToRunOut: false,
            warningAt: store.settings.warningThresholdPercent,
            criticalAt: store.settings.criticalThresholdPercent
        )
    }

    /// Answers ONE question: "will I run out before the reset?"
    private var burnPage: some View {
        let focus = viewModel.focusProvider
        let snapshot = store.snapshots[focus]
        let session = snapshot?.session
        let end = session?.resetsAt ?? Date()
        let start = session?.startedAt ?? end.addingTimeInterval(-5 * 3600)
        let samples = store.percentHistory[focus] ?? []
        let projection = store.burnProjection(for: focus)
        let used = session?.usedPercent
        let verdict = burnVerdict(projection: projection, hasSamples: !samples.isEmpty)
        let dominantModel = snapshot?.quotaStatus != nil
            ? session?.modelTokens.flatMap { ModelProjection.dominantModel(modelTokens: $0) }
            : nil
        let alternates = dominantModel.map { model in
            ModelProjection.alternates(dominantModel: model, sessionTokens: session?.tokens ?? .zero)
        } ?? []
        let dominantModelShortName = dominantModel.map(ModelProjection.shortName(for:))

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    GaugeLabel(text: "BURN · WILL THE 5H SESSION LAST?", color: Theme.textSecondary, size: 9)
                    if let used {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("\(Int((100 - used).rounded()))%")
                                .font(Theme.numeral(24))
                                .monospacedDigit()
                                .foregroundStyle(Theme.riskTint(
                                    used: used,
                                    projectedToRunOut: projection?.exhaustsAt != nil,
                                    warningAt: store.settings.warningThresholdPercent,
                                    criticalAt: store.settings.criticalThresholdPercent
                                ))
                            GaugeLabel(text: "LEFT", color: Theme.textDim, size: 8)
                            if let resets = session?.resetsAt {
                                GaugeLabel(
                                    text: "· RESETS \(Format.time(resets)) · IN \(Format.countdown(to: resets))",
                                    color: Theme.textFaint,
                                    size: 8
                                )
                            }
                        }
                    }
                }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(burnProviders) { provider in
                        selectorChip(provider.shortName, active: provider == focus) {
                            viewModel.focusProvider = provider
                        }
                    }
                }
            }

            Text(verdict.text)
                .font(Theme.body(11.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(verdict.color)
                .lineLimit(1)

            BurnChartView(
                samples: samples,
                projection: projection,
                windowStart: start,
                windowEnd: end,
                dominantModelShortName: dominantModelShortName,
                alternates: alternates
            )
            .frame(maxHeight: .infinity)

            GaugeLabel(
                text: "SOLID = REAL USAGE · DOTTED = PROJECTION AT CURRENT PACE",
                color: Theme.textFaint,
                size: 7
            )
        }
    }

    private func burnVerdict(
        projection: BurnRate.Projection?,
        hasSamples: Bool
    ) -> (text: String, color: Color) {
        if let text = BurnRate.verdict(projection) {
            return (text, projection?.exhaustsAt != nil ? Theme.warning : Theme.caution)
        }
        if hasSamples {
            return ("No burn right now — safe until the reset.", Theme.ok)
        }
        return ("Collecting samples — verdict appears after a few minutes of use.", Theme.textDim)
    }

    private var burnProviders: [ProviderID] {
        let withSamples = ProviderID.allCases.filter { !(store.percentHistory[$0] ?? []).isEmpty }
        return withSamples.isEmpty ? [.claudeCode] : withSamples
    }

    /// Answers ONE question: "when do I burn the most?"
    private var rhythmPage: some View {
        let totals = rhythmTotals
        let total = totals.reduce(0, +)
        let peak = totals.enumerated().max { $0.element < $1.element }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    GaugeLabel(text: "RHYTHM · WHEN DO YOU BURN THE MOST?", color: Theme.textSecondary, size: 9)
                    if let peak, peak.element > 0 {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("\(peak.offset)h")
                                .font(Theme.numeral(24))
                                .monospacedDigit()
                                .foregroundStyle(Theme.coral)
                            GaugeLabel(text: "PEAK HOUR", color: Theme.textDim, size: 8)
                            GaugeLabel(
                                text: "· \(Format.tokens(total)) TOKENS \(rhythmToday ? "TODAY" : "IN 7 DAYS")",
                                color: Theme.textFaint,
                                size: 8
                            )
                        }
                    } else {
                        Text("No activity recorded \(rhythmToday ? "today" : "this week") yet.")
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textDim)
                    }
                }
                Spacer()
                HStack(spacing: 6) {
                    selectorChip("Today", active: rhythmToday) { rhythmToday = true }
                    selectorChip("7 days", active: !rhythmToday) { rhythmToday = false }
                }
            }
            RhythmChartView(totals: totals)
                .frame(maxHeight: .infinity)
            GaugeLabel(text: "TOKENS BURNED PER LOCAL HOUR · WHITE = CURRENT HOUR", color: Theme.textFaint, size: 7)
        }
    }

    private var rhythmTotals: [Int] {
        var totals = [Int](repeating: 0, count: 24)
        let dayStart = Date().flooredToDay
        for snapshot in store.snapshots.values {
            for entry in snapshot.weekly?.hourlyTotals ?? [] {
                if rhythmToday && entry.hour < dayStart { continue }
                totals[Calendar.current.component(.hour, from: entry.hour)] += entry.tokens
            }
        }
        return totals
    }

    // MARK: Models page

    private static let modelFamilies: [(key: String, name: String)] = [
        ("haiku", "Haiku"), ("sonnet", "Sonnet"), ("opus", "Opus"), ("fable", "Fable"),
    ]

    private var modelsPage: some View {
        let snapshot = store.snapshots[.claudeCode]
        let health = snapshot?.modelHealth ?? []
        let breakdown = snapshot?.modelBreakdown ?? []
        // Fable 5 is metered separately from the shared Haiku/Sonnet/Opus
        // pool the headline gauge shows — its own % only lives here.
        let fableQuota = snapshot?.weekly?.namedQuotas?.first { $0.name == "Claude Fable 5" }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                GaugeLabel(text: "CLAUDE MODELS", color: Theme.textSecondary, size: 9)
                Spacer()
                GaugeLabel(text: "LIVE PROBE · 1 MODEL / CYCLE", color: Theme.textFaint, size: 7)
            }
            HStack(spacing: 10) {
                ForEach(Self.modelFamilies, id: \.key) { family in
                    modelCard(
                        family: family,
                        health: health.first { $0.model.contains(family.key) },
                        usage: familyUsage(family.key, breakdown: breakdown),
                        quota: family.key == "fable" ? fableQuota : nil
                    )
                }
            }
            .frame(maxHeight: .infinity)
            GaugeLabel(
                text: health.isEmpty
                    ? "ENABLE THE API PROBE IN SETTINGS FOR LIVE STATUS"
                    : "USAGE FROM LOCAL TRANSCRIPTS · LAST 7 DAYS",
                color: Theme.textFaint,
                size: 7.5
            )
        }
    }

    private func familyUsage(_ key: String, breakdown: [ModelUsage]) -> (tokens: Int, cost: Double)? {
        let matches = breakdown.filter { $0.model.contains(key) }
        guard !matches.isEmpty else { return nil }
        return (matches.reduce(0) { $0 + $1.tokens }, matches.reduce(0) { $0 + $1.costUSD })
    }

    private func modelCard(
        family: (key: String, name: String),
        health: ModelHealth?,
        usage: (tokens: Int, cost: Double)?,
        quota: NamedQuota? = nil
    ) -> some View {
        VStack(spacing: 7) {
            PixelGlyph(
                tint: health?.status == .error ? Theme.textDim : Theme.coral,
                distress: health?.status == .limited ? 0.7 : 0
            )
            .frame(width: 46, height: 36)
            Text(family.name)
                .font(Theme.body(12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            modelStatusPill(health)
            if let quota {
                GaugeLabel(
                    text: "\(Int(max(0, 100 - quota.usedPercent).rounded()))% WEEKLY LEFT",
                    color: riskColor(quota.usedPercent),
                    size: 7.5
                )
            }
            if let usage {
                GaugeLabel(
                    text: "\(Format.tokens(usage.tokens))\(usage.cost >= 0.01 ? " · ~" + Format.usd(usage.cost) : "")",
                    color: Theme.textDim,
                    size: 7.5
                )
            } else {
                GaugeLabel(text: "NO RECENT USE", color: Theme.textFaint, size: 7.5)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surface)
        )
    }

    @ViewBuilder
    private func modelStatusPill(_ health: ModelHealth?) -> some View {
        switch health?.status {
        case .ok:
            StatusPill(
                text: health?.latencyMs.map { String(format: "OK %.1fs", Double($0) / 1000) } ?? "OK",
                color: Theme.ok
            )
        case .limited:
            StatusPill(text: "Limited", color: Theme.caution)
        case .error:
            StatusPill(text: "Error", color: Theme.danger)
        case nil:
            StatusPill(text: "N/D", color: Theme.textDim)
        }
    }

    // MARK: OpenAI models page

    /// Per-model usage AND per-model quota from Codex rollouts. OpenAI reports
    /// some models' weekly cap separately from the account-wide aggregate
    /// (e.g. "GPT-5.3-Codex-Spark") — the headline gauge always shows the
    /// aggregate, this page is where the per-model number lives.
    private var gptModelsPage: some View {
        let snapshot = store.snapshots[.codex]
        let breakdown = snapshot?.modelBreakdown ?? []
        let namedQuotas = snapshot?.weekly?.namedQuotas ?? []
        let totalTokens = max(breakdown.reduce(0) { $0 + $1.tokens }, 1)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    GaugeLabel(text: "OPENAI MODELS · WHERE DO CODEX TOKENS GO?", color: Theme.textSecondary, size: 9)
                    if let top = breakdown.first {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(top.model)
                                .font(Theme.numeral(19))
                                .foregroundStyle(Theme.coral)
                                .lineLimit(1)
                            GaugeLabel(
                                text: "TOP MODEL · \(Int(Double(top.tokens) / Double(totalTokens) * 100))% OF TOKENS",
                                color: Theme.textDim,
                                size: 8
                            )
                        }
                    } else {
                        Text("No Codex sessions in the last 7 days.")
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textDim)
                    }
                }
                Spacer()
                if let note = snapshot?.note {
                    StatusPill(text: note, color: Theme.textSecondary)
                }
            }

            if !namedQuotas.isEmpty {
                GaugeLabel(text: "WEEKLY QUOTA BY MODEL", color: Theme.textSecondary, size: 8)
                VStack(spacing: 6) {
                    ForEach(namedQuotas) { quota in
                        namedQuotaRow(quota)
                    }
                }
            }

            VStack(spacing: 6) {
                ForEach(breakdown.prefix(5)) { usage in
                    modelUsageRow(usage, share: Double(usage.tokens) / Double(totalTokens))
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            GaugeLabel(
                text: "LAST 7 DAYS · LOCAL ROLLOUTS",
                color: Theme.textFaint,
                size: 7
            )
        }
    }

    /// A quota scoped to one model, separate from the provider's headline
    /// aggregate — e.g. Codex's per-model weekly cap or Claude's Fable 5 pool.
    private func namedQuotaRow(_ quota: NamedQuota) -> some View {
        let remaining = max(0, 100 - quota.usedPercent)
        return HStack(spacing: 10) {
            Text(quota.name)
                .font(Theme.body(11, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)
            SegmentedMeter(percent: remaining, segments: 16, tint: riskColor(quota.usedPercent), height: 6)
            Text("\(Int(remaining.rounded()))% left")
                .font(Theme.body(9.5))
                .monospacedDigit()
                .foregroundStyle(Theme.textDim)
                .frame(width: 118, alignment: .trailing)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.surface)
        )
    }

    private func modelUsageRow(_ usage: ModelUsage, share: Double) -> some View {
        HStack(spacing: 10) {
            Text(usage.model)
                .font(Theme.body(11, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)
            SegmentedMeter(percent: share * 100, segments: 16, tint: Theme.coral.opacity(0.9), height: 6)
            Text("\(Format.tokens(usage.tokens))\(usage.costUSD >= 0.01 ? " · ~" + Format.usd(usage.costUSD) : "")")
                .font(Theme.body(9.5))
                .monospacedDigit()
                .foregroundStyle(Theme.textDim)
                .frame(width: 118, alignment: .trailing)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.surface)
        )
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            actionChip("arrow.clockwise", "Refresh") {
                AppEnvironment.shared.scheduler.refreshNow()
            }
            actionChip(store.isPaused ? "play.fill" : "pause.fill", store.isPaused ? "Resume" : "Pause") {
                store.isPaused.toggle()
            }
            Spacer()
            PagerDots(
                page: Binding(
                    get: { viewModel.expandedPage },
                    set: { viewModel.goToPage($0) }
                ),
                count: NotchViewModel.pageCount
            )
            Spacer()
            actionChip("chart.bar.xaxis", "Dashboard") {
                router.openDashboard()
            }
            actionChip("gearshape", "Settings") {
                router.openSettings()
            }
        }
    }

    private func selectorChip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.body(9.5, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(active ? Theme.coral : Theme.surfaceRaised))
                .foregroundStyle(active ? Color.black.opacity(0.85) : Theme.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private func actionChip(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
                    .font(Theme.body(10, weight: .medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(Theme.surfaceRaised))
            .foregroundStyle(Theme.textSecondary)
        }
        .buttonStyle(.plain)
    }
}

private struct APIAccountCardDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggedID: UUID?
    @Binding var dropTargetID: UUID?
    let move: (UUID, UUID) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggedID != nil
    }

    func dropEntered(info: DropInfo) {
        guard let draggedID, draggedID != targetID else { return }
        dropTargetID = targetID
        move(draggedID, targetID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if dropTargetID == targetID {
            dropTargetID = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        dropTargetID = nil
        return true
    }
}

/// Brand mark fetched from Logo.dev's image CDN. The publishable token stays
/// in the macOS Keychain, never in preferences, snapshots, or source code.
private struct APIServiceLogo: View {
    let service: APIServiceID
    @State private var failedToLoad = false

    private var url: URL? {
        guard !failedToLoad,
              let token = APIAccountCredentialStore.key(for: "logo-dev-brand-assets")
        else { return nil }
        var components = URLComponents(string: "https://img.logo.dev/\(service.logoDomain)")
        components?.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "format", value: "png"),
            URLQueryItem(name: "size", value: "64"),
            URLQueryItem(name: "fallback", value: "404"),
        ]
        return components?.url
    }

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(2)
                    case .failure:
                        monogram
                            .onAppear { failedToLoad = true }
                    default:
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
            } else {
                monogram
            }
        }
        .frame(width: 18, height: 18)
        .background(Circle().fill(Theme.surfaceRaised))
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var monogram: some View {
        Text(service.logoMonogram)
            .font(Theme.label(6.5))
            .foregroundStyle(Theme.textDim)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .padding(2)
    }
}

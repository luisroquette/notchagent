import AgentMeterCore
import SwiftUI

struct MobileRootView: View {
    @EnvironmentObject private var subscriptions: SubscriptionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.portuguese.rawValue
    @State private var providerForNewPlan: AgentMeterProvider?
    @State private var isPresentingNewSubscription = false
    @State private var isShowingWallet = false

    private var activeSubscriptions: [AISubscription] {
        subscriptions.subscriptions.filter(\.isActive)
    }

    private var configuredProviders: [AgentMeterProvider] {
        AgentMeterProvider.allCases.filter { provider in
            activeSubscriptions.contains { $0.provider == provider }
        }
    }

    private var nextSubscription: AISubscription? {
        activeSubscriptions.min { $0.nextRenewalDate < $1.nextRenewalDate }
    }

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .portuguese
    }

    private var coverageProgress: Double {
        Double(configuredProviders.count) / Double(AgentMeterProvider.allCases.count)
    }

    var body: some View {
        NavigationStack {
            AgentMeterHomeView(
                selectedLanguage: selectedLanguage,
                addSubscription: { isPresentingNewSubscription = true },
                addProvider: { providerForNewPlan = $0 },
                openWallet: { isShowingWallet = true }
            )
            .environmentObject(subscriptions)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                commandBar
            }
            .navigationDestination(isPresented: $isShowingWallet) {
                SubscriptionWalletView()
            }
            .sheet(isPresented: $isPresentingNewSubscription) {
                QuickSubscriptionEditorView()
                    .environmentObject(subscriptions)
            }
            .sheet(item: $providerForNewPlan) { provider in
                QuickSubscriptionEditorView(initialProvider: provider)
                    .environmentObject(subscriptions)
            }
            .task {
                await subscriptions.syncIfEnabled()
            }
        }
        .tint(AgentMeterTheme.signal)
        .font(AgentMeterTypography.regular(17))
        .environment(\.locale, selectedLanguage.locale)
        .preferredColorScheme(.dark)
    }

    private var missionBackground: some View {
        AgentMeterTheme.background
            .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: AgentMeterTheme.Space.sm) {
            AgentMeterBrandMark(compact: true)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: AgentMeterTheme.Space.xs)
            languageMenu
            Button {
                isPresentingNewSubscription = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(AgentMeterTheme.signal)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Adicionar assinatura")
        }
        .padding(.leading, AgentMeterTheme.Space.xs)
        .padding(.trailing, 0)
        .frame(minHeight: 64)
    }

    private var languageMenu: some View {
        Menu {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    languageCode = language.rawValue
                } label: {
                    HStack {
                        Text("\(language.countryCode) · \(language.nativeName)")
                        if language == selectedLanguage {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    LanguageFlagView(language: selectedLanguage)
                        .scaleEffect(0.78)
                } else {
                    HStack(spacing: 6) {
                        LanguageFlagView(language: selectedLanguage)
                            .scaleEffect(0.78)
                        Text(selectedLanguage.countryCode)
                            .font(AgentMeterTypography.fixedBold(12))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(.horizontal, 8)
            .frame(minWidth: 62, minHeight: 44)
        }
        .accessibilityLabel("Selecionar idioma")
    }

    private var nextDebitHero: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibleNextDebitHero
            } else {
                standardNextDebitHero
            }
        }
    }

    private var standardNextDebitHero: some View {
        Button {
            if nextSubscription == nil {
                isPresentingNewSubscription = true
            } else {
                isShowingWallet = true
            }
        } label: {
            VStack(alignment: .leading, spacing: AgentMeterTheme.Space.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text(nextSubscription == nil ? "Seu próximo plano" : "Próxima cobrança")
                        .font(AgentMeterTypography.fixedBold(12))
                        .textCase(.uppercase)
                        .tracking(1.1)
                        .foregroundStyle(Color.black.opacity(0.56))
                    Spacer()
                    Text(nextSubscription == nil ? "PENDENTE" : boardingDate)
                        .font(AgentMeterTypography.fixedTelemetry(12))
                        .foregroundStyle(Color.black.opacity(0.68))
                }

                if let nextSubscription {
                    Text(brl(nextSubscription.cycleTotalBRL))
                        .font(AgentMeterTypography.telemetry(44, relativeTo: .largeTitle))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .foregroundStyle(.black)
                    Text("\(nextSubscription.provider.displayName) · \(nextSubscription.planName)")
                        .font(AgentMeterTypography.bold(19, relativeTo: .headline))
                        .foregroundStyle(.black)
                    Text("Renova em \(renewalDescription(nextSubscription))")
                        .font(AgentMeterTypography.regular(15, relativeTo: .subheadline))
                        .foregroundStyle(Color.black.opacity(0.64))
                } else {
                    Text("Adicione um plano para acompanhar a próxima cobrança.")
                        .font(AgentMeterTypography.regular(19, relativeTo: .title3))
                        .foregroundStyle(.black)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: AgentMeterTheme.Space.xs) {
                    Rectangle().fill(AgentMeterTheme.nominal).frame(width: 7, height: 7)
                    Text("Informado por você")
                        .font(AgentMeterTypography.fixedRegular(11))
                        .textCase(.uppercase)
                        .tracking(0.7)
                        .foregroundStyle(Color.black.opacity(0.62))
                    Spacer()
                    Text(nextSubscription == nil ? "Adicionar" : "Detalhes")
                        .font(AgentMeterTypography.fixedBold(11))
                        .textCase(.uppercase)
                        .tracking(0.7)
                        .foregroundStyle(.white)
                        .padding(.horizontal, AgentMeterTheme.Space.sm)
                        .frame(minHeight: 44)
                        .background(.black)
                }
                .padding(.top, AgentMeterTheme.Space.xs)
            }
            .padding(AgentMeterTheme.Space.lg)
            .frame(maxWidth: .infinity, minHeight: 264, alignment: .leading)
            .background(Color(red: 0.941, green: 0.941, blue: 0.980))
            .overlay {
                Rectangle().stroke(Color.black.opacity(0.24), lineWidth: 0.75)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var nextDebitVisualField: some View {
        GeometryReader { proxy in
            ZStack {
                RadialGradient(
                    colors: [AgentMeterTheme.ice.opacity(0.30), AgentMeterTheme.deepOcean.opacity(0.24), .clear],
                    center: .topTrailing,
                    startRadius: 5,
                    endRadius: proxy.size.width * 0.88
                )
                Circle()
                    .fill(AgentMeterTheme.ice.opacity(0.11))
                    .frame(width: proxy.size.width * 0.78, height: proxy.size.width * 0.78)
                    .blur(radius: 2)
                    .offset(x: proxy.size.width * 0.32, y: -proxy.size.width * 0.31)
                Circle()
                    .stroke(AgentMeterTheme.ice.opacity(0.34), lineWidth: 1)
                    .frame(width: proxy.size.width * 0.48, height: proxy.size.width * 0.48)
                    .offset(x: proxy.size.width * 0.31, y: -proxy.size.width * 0.25)
                Circle()
                    .stroke(AgentMeterTheme.ice.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [2, 6]))
                    .frame(width: proxy.size.width * 0.69, height: proxy.size.width * 0.69)
                    .offset(x: proxy.size.width * 0.30, y: -proxy.size.width * 0.26)
                Capsule()
                    .fill(AgentMeterTheme.ice.opacity(0.18))
                    .frame(width: 42, height: 8)
                    .rotationEffect(.degrees(-34))
                    .offset(x: proxy.size.width * 0.10, y: -proxy.size.width * 0.02)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .accessibilityHidden(true)
    }

    private var monthlySnapshot: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibleMonthlySnapshot
            } else {
                standardMonthlySnapshot
            }
        }
    }

    private var standardMonthlySnapshot: some View {
        HStack(alignment: .top, spacing: AgentMeterTheme.Space.md) {
            snapshotMetric(
                title: "Total mensal",
                value: brl(subscriptions.summary.monthlyTotalBRL),
                detail: "Todos os planos ativos"
            )
            snapshotMetric(
                title: "Configurados",
                value: "\(configuredProviders.count) de \(AgentMeterProvider.allCases.count)",
                detail: "Provedores com plano"
            )
        }
        .padding(.vertical, AgentMeterTheme.Space.md)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AgentMeterTheme.border.opacity(0.72)).frame(height: 0.75)
        }
        .accessibilityElement(children: .contain)
    }

    private var accessibleNextDebitHero: some View {
        Button {
            if nextSubscription == nil {
                isPresentingNewSubscription = true
            } else {
                isShowingWallet = true
            }
        } label: {
            VStack(alignment: .leading, spacing: AgentMeterTheme.Space.md) {
                Text(nextSubscription == nil ? "Seu próximo plano" : "Próxima cobrança")
                    .font(AgentMeterTypography.bold(28, relativeTo: .title))
                    .foregroundStyle(.primary)

                if let nextSubscription {
                    Text(brl(nextSubscription.cycleTotalBRL))
                        .font(AgentMeterTypography.telemetry(30, relativeTo: .title))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text("\(nextSubscription.provider.displayName) · \(nextSubscription.planName)")
                        .font(AgentMeterTypography.bold(21, relativeTo: .headline))
                        .foregroundStyle(.primary)
                    Text("Próxima renovação · \(boardingDate)")
                        .font(AgentMeterTypography.regular(18, relativeTo: .body))
                        .foregroundStyle(AgentMeterTheme.mutedInk)
                } else {
                    Text("Adicione um plano para acompanhar a próxima cobrança.")
                        .font(AgentMeterTypography.regular(20, relativeTo: .body))
                        .foregroundStyle(.primary)
                }

                Divider().overlay(AgentMeterTheme.border)
                Text("Informado por você")
                    .font(AgentMeterTypography.regular(17, relativeTo: .body))
                    .foregroundStyle(AgentMeterTheme.mutedInk)
                Label(nextSubscription == nil ? "Adicionar plano" : "Ver detalhes", systemImage: "arrow.right")
                    .font(AgentMeterTypography.bold(18, relativeTo: .headline))
                    .foregroundStyle(AgentMeterTheme.signal)
            }
            .padding(AgentMeterTheme.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AgentMeterTheme.border.opacity(0.55)).frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
    }

    private var accessibleMonthlySnapshot: some View {
        VStack(alignment: .leading, spacing: AgentMeterTheme.Space.md) {
            snapshotMetric(
                title: "Total mensal",
                value: brl(subscriptions.summary.monthlyTotalBRL),
                detail: "Todos os planos ativos"
            )
            Divider().overlay(AgentMeterTheme.border)
            snapshotMetric(
                title: "Configurados",
                value: "\(configuredProviders.count) de \(AgentMeterProvider.allCases.count)",
                detail: "Provedores com plano"
            )
        }
        .padding(.horizontal, AgentMeterTheme.Space.md)
        .padding(.vertical, AgentMeterTheme.Space.xl)
    }

    private func snapshotMetric(title: LocalizedStringKey, value: String, detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: AgentMeterTheme.Space.xxs) {
            Text(title)
                .font(AgentMeterTypography.regular(14, relativeTo: .caption))
                .foregroundStyle(AgentMeterTheme.mutedInk)
            Text(value)
                .font(AgentMeterTypography.telemetry(20, relativeTo: .headline))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(detail)
                .font(AgentMeterTypography.regular(13, relativeTo: .caption2))
                .foregroundStyle(AgentMeterTheme.mutedInk)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heroOverview: some View {
        VStack(alignment: .leading, spacing: AgentMeterTheme.Space.md) {
            VStack(alignment: .leading, spacing: AgentMeterTheme.Space.xxs) {
                Text("Custo mensal")
                    .font(AgentMeterTypography.fixedBold(10))
                    .textCase(.uppercase)
                    .tracking(1.5)
                    .foregroundStyle(AgentMeterTheme.mutedInk)
                Text(brl(subscriptions.summary.monthlyTotalBRL))
                    .font(AgentMeterTypography.fixedTelemetry(dynamicTypeSize.isAccessibilitySize ? 46 : 52))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            HStack(spacing: AgentMeterTheme.Space.xs) {
                Rectangle()
                    .fill(nextSubscription == nil ? AgentMeterTheme.warning : AgentMeterTheme.nominal)
                    .frame(width: 7, height: 7)
                Text(nextEventLine)
                    .font(AgentMeterTypography.fixedTelemetry(dynamicTypeSize.isAccessibilitySize ? 15 : 11))
                    .textCase(.uppercase)
                    .tracking(0.25)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .foregroundStyle(.primary.opacity(0.82))
            }
            .padding(.vertical, AgentMeterTheme.Space.xs)
            .padding(.horizontal, AgentMeterTheme.Space.sm)
            .overlay {
                Rectangle().stroke(AgentMeterTheme.border.opacity(0.7), lineWidth: 0.75)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, AgentMeterTheme.Space.md)
        .padding(.top, AgentMeterTheme.Space.xxl)
        .padding(.bottom, AgentMeterTheme.Space.xl)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AgentMeterTheme.border.opacity(0.55)).frame(height: 0.5)
        }
    }

    private var telemetryManifest: some View {
        VStack(spacing: AgentMeterTheme.Space.md) {
            HStack(alignment: .top) {
                telemetryStatus(
                    title: "Sistema",
                    value: "\(configuredProviders.count)/\(AgentMeterProvider.allCases.count) provedores",
                    alignment: .leading
                ) {
                    AgentMeterPixelCompanion(
                        tint: activeSubscriptions.isEmpty ? AgentMeterTheme.warning : AgentMeterTheme.nominal,
                        distress: activeSubscriptions.isEmpty ? 0.8 : 0
                    )
                    .frame(width: 16, height: 12)
                }
                Spacer(minLength: AgentMeterTheme.Space.md)
                telemetryStatus(
                    title: "Dados",
                    value: subscriptions.isCloudSyncEnabled ? "iCloud ativo" : "Local",
                    alignment: .trailing
                ) {
                    Rectangle()
                        .fill(AgentMeterTheme.nominal)
                        .frame(width: 7, height: 7)
                }
            }

            VStack(spacing: 6) {
                AgentMeterSegmentedGauge(
                    value: configuredProviders.count,
                    total: AgentMeterProvider.allCases.count,
                    tint: AgentMeterTheme.nominal,
                    height: 5,
                    spacing: 4
                )
                HStack {
                    Text(activeSubscriptions.isEmpty ? "Configuração pendente" : "Operacional")
                        .foregroundStyle(activeSubscriptions.isEmpty ? AgentMeterTheme.warning : AgentMeterTheme.nominal)
                    Spacer()
                    Text("Informado por você")
                        .foregroundStyle(AgentMeterTheme.mutedInk)
                }
                .font(AgentMeterTypography.fixedBold(9))
                .textCase(.uppercase)
                .tracking(0.65)
            }
        }
        .padding(.horizontal, AgentMeterTheme.Space.md)
        .padding(.vertical, AgentMeterTheme.Space.xl)
    }

    private func telemetryStatus<Indicator: View>(
        title: LocalizedStringKey,
        value: String,
        alignment: HorizontalAlignment,
        @ViewBuilder indicator: () -> Indicator
    ) -> some View {
        VStack(alignment: alignment, spacing: AgentMeterTheme.Space.xxs) {
            Text(title)
                .font(AgentMeterTypography.fixedBold(9))
                .textCase(.uppercase)
                .tracking(1.1)
                .foregroundStyle(AgentMeterTheme.mutedInk)
            HStack(spacing: AgentMeterTheme.Space.xs) {
                if alignment == .trailing {
                    Text(value)
                }
                indicator()
                if alignment == .leading {
                    Text(value)
                }
            }
            .font(AgentMeterTypography.fixedTelemetry(12))
            .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .combine)
    }

    private var boardingPass: some View {
        Button {
            if nextSubscription == nil {
                isPresentingNewSubscription = true
            } else {
                isShowingWallet = true
            }
        } label: {
            HStack(spacing: AgentMeterTheme.Space.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Próximo faturamento")
                        .font(AgentMeterTypography.fixedBold(10))
                        .textCase(.uppercase)
                        .tracking(1.0)
                        .foregroundStyle(Color.black.opacity(0.56))
                    Text(boardingDate)
                        .font(AgentMeterTypography.fixedBold(30))
                        .foregroundStyle(.black)
                    Text(nextSubscription.map { "\($0.provider.displayName) · \($0.planName)" } ?? localized("Nenhuma renovação programada"))
                        .font(AgentMeterTypography.fixedTelemetry(11))
                        .foregroundStyle(Color.black.opacity(0.68))
                        .lineLimit(1)
                }
                Spacer(minLength: AgentMeterTheme.Space.xs)
                Text(nextSubscription == nil ? "Adicionar" : "Ver detalhes")
                    .font(AgentMeterTypography.fixedBold(11))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(.white)
                    .padding(.horizontal, AgentMeterTheme.Space.sm)
                    .frame(minHeight: 44)
                    .background(Color.black)
            }
            .padding(AgentMeterTheme.Space.md)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .background(Color(red: 0.941, green: 0.941, blue: 0.980))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AgentMeterTheme.Space.md)
        .padding(.bottom, AgentMeterTheme.Space.xxl)
        .accessibilityElement(children: .combine)
    }

    private var providerManifest: some View {
        VStack(alignment: .leading, spacing: AgentMeterTheme.Space.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Seus provedores")
                    .font(AgentMeterTypography.bold(22, relativeTo: .title2))
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(configuredProviders.count)/\(AgentMeterProvider.allCases.count)")
                    .font(AgentMeterTypography.telemetry(14, relativeTo: .caption))
                    .foregroundStyle(AgentMeterTheme.ice)
            }

            VStack(spacing: 0) {
                ForEach(Array(AgentMeterProvider.allCases.enumerated()), id: \.element.id) { index, provider in
                    if index > 0 {
                        Divider().overlay(AgentMeterTheme.border).padding(.leading, 56)
                    }
                    providerManifestRow(provider)
                }
            }
            .overlay(alignment: .top) { Rectangle().fill(AgentMeterTheme.border).frame(height: 0.75) }
            .overlay(alignment: .bottom) { Rectangle().fill(AgentMeterTheme.border).frame(height: 0.75) }
        }
    }

    private func providerManifestRow(_ provider: AgentMeterProvider) -> some View {
        let plans = activeSubscriptions.filter { $0.provider == provider }
        let monthly = plans.reduce(Decimal.zero) { $0 + $1.monthlyEquivalentBRL }
        let active = !plans.isEmpty

        return Button {
            if active {
                isShowingWallet = true
            } else {
                providerForNewPlan = provider
            }
        } label: {
            HStack(spacing: AgentMeterTheme.Space.sm) {
                AgentMeterProviderBadge(provider: provider, active: active, size: 40)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: AgentMeterTheme.Space.xs) {
                        Text(provider.displayName)
                            .font(AgentMeterTypography.bold(18, relativeTo: .headline))
                        Circle()
                            .fill(active ? AgentMeterTheme.nominal : AgentMeterTheme.mutedInk.opacity(0.5))
                            .frame(width: 7, height: 7)
                    }
                    Text(active ? plans.first?.planName ?? localized("Assinatura ativa") : localized("Não configurado"))
                        .font(AgentMeterTypography.regular(14, relativeTo: .caption))
                        .foregroundStyle(AgentMeterTheme.mutedInk)
                        .lineLimit(1)
                }

                Spacer(minLength: AgentMeterTheme.Space.xs)

                if active {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(brl(monthly))
                            .font(AgentMeterTypography.telemetry(15, relativeTo: .subheadline))
                        Text("Ativo")
                            .font(AgentMeterTypography.regular(13, relativeTo: .caption))
                            .foregroundStyle(AgentMeterTheme.nominal)
                    }
                } else {
                    Text("Adicionar plano")
                        .font(AgentMeterTypography.bold(14, relativeTo: .caption))
                        .foregroundStyle(AgentMeterTheme.signal)
                        .padding(.horizontal, AgentMeterTheme.Space.xs)
                        .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, AgentMeterTheme.Space.xs)
            .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 96 : 78)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(active ? "Abre a carteira de assinaturas" : "Adiciona um plano deste provedor")
    }

    private var nextEventLine: String {
        guard let nextSubscription else {
            return localized("Próxima renovação · não programada")
        }
        return localized("Próxima renovação") + " · " + nextSubscription.provider.displayName + " · " + renewalDescription(nextSubscription)
    }

    private var boardingDate: String {
        guard let nextSubscription else { return "— —" }
        let formatter = DateFormatter()
        formatter.locale = selectedLanguage.locale
        formatter.dateFormat = "dd MMM"
        return formatter.string(from: nextSubscription.nextRenewalDate).uppercased(with: selectedLanguage.locale)
    }

    private var missionDeck: some View {
        VStack(spacing: 0) {
            if dynamicTypeSize.isAccessibilitySize {
                accessibleMissionSummary
                    .padding(AgentMeterTheme.Space.md)
            } else {
                orbitInstrument
                    .padding(.horizontal, AgentMeterTheme.Space.md)
                    .padding(.vertical, AgentMeterTheme.Space.md)
                telemetryStrip
            }
        }
        .background {
            AgentMeterTheme.hull
                .overlay {
                    RadialGradient(
                        colors: [Color.white.opacity(0.05), .clear],
                        center: .top,
                        startRadius: 0,
                        endRadius: 270
                    )
                }
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.18)).frame(height: 0.75)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.18)).frame(height: 0.75)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: configuredProviders.count)
        .accessibilityElement(children: .contain)
    }

    private var orbitInstrument: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width - 52, 230)
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    .frame(width: diameter, height: diameter)
                Circle()
                    .trim(from: 0, to: max(0.025, coverageProgress))
                    .stroke(AgentMeterTheme.signal, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: diameter, height: diameter)
                    .rotationEffect(.degrees(-90))
                Circle()
                    .stroke(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
                    .frame(width: diameter * 0.64, height: diameter * 0.64)
                Rectangle()
                    .fill(Color.white.opacity(0.32))
                    .frame(width: 1, height: diameter * 0.28)
                    .offset(y: -diameter * 0.36)
                Rectangle()
                    .fill(Color.white.opacity(0.32))
                    .frame(width: diameter * 0.28, height: 1)
                    .offset(x: diameter * 0.36)

                VStack(spacing: AgentMeterTheme.Space.xxs) {
                    Text("Cobertura da missão")
                        .font(AgentMeterTypography.fixedBold(12))
                        .textCase(.uppercase)
                        .tracking(1.15)
                        .foregroundStyle(Color.white.opacity(0.64))
                    Text("\(configuredProviders.count)/\(AgentMeterProvider.allCases.count)")
                        .font(AgentMeterTypography.telemetry(46, relativeTo: .largeTitle))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text("provedores ativos")
                        .font(AgentMeterTypography.regular(13, relativeTo: .caption))
                        .foregroundStyle(Color.white.opacity(0.62))
                    AgentMeterSegmentedGauge(
                        value: configuredProviders.count,
                        total: AgentMeterProvider.allCases.count
                    )
                    .frame(width: 54)
                    .padding(.top, 2)
                }

                orbitNode(.claude, diameter: diameter, x: 0, y: -diameter * 0.50)
                orbitNode(.chatGPT, diameter: diameter, x: -diameter * 0.44, y: diameter * 0.28)
                orbitNode(.gemini, diameter: diameter, x: diameter * 0.44, y: diameter * 0.28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 276)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cobertura da missão")
        .accessibilityValue("\(configuredProviders.count) de \(AgentMeterProvider.allCases.count) provedores ativos")
        .accessibilityHint("Limites oficiais ainda não importados")
    }

    private func orbitNode(_ provider: AgentMeterProvider, diameter: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        let active = configuredProviders.contains(provider)
        return VStack(spacing: 3) {
            AgentMeterProviderBadge(provider: provider, active: active)
            Text(provider.displayName)
                .font(AgentMeterTypography.fixedBold(12))
                .foregroundStyle(active ? Color.white : Color.white.opacity(0.46))
                .lineLimit(1)
        }
        .offset(x: x, y: y)
    }

    private var accessibleMissionSummary: some View {
        VStack(alignment: .leading, spacing: AgentMeterTheme.Space.md) {
            Text("Cobertura da missão")
                .font(AgentMeterTypography.fixedBold(20))
                .foregroundStyle(.white)
            Text("\(configuredProviders.count) de \(AgentMeterProvider.allCases.count) provedores ativos")
                .font(AgentMeterTypography.fixedTelemetry(30))
                .foregroundStyle(.white)
            Text("Limites oficiais ainda não importados")
                .font(AgentMeterTypography.fixedRegular(17))
                .foregroundStyle(Color.white.opacity(0.72))
            accessibleTelemetryRow("Próxima cobrança", value: nextSubscription.map(renewalDescription) ?? localized("Não programada"))
            Divider().overlay(Color.white.opacity(0.12))
            accessibleTelemetryRow("Custo mensal", value: brl(subscriptions.summary.monthlyTotalBRL))
            Divider().overlay(Color.white.opacity(0.12))
            accessibleTelemetryRow("Fonte dos valores", value: localized("Informado por você"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func accessibleTelemetryRow(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: AgentMeterTheme.Space.xxs) {
            Text(title)
                .font(AgentMeterTypography.fixedRegular(12))
                .textCase(.uppercase)
                .tracking(0.9)
                .foregroundStyle(Color.white.opacity(0.58))
            Text(value)
                .font(AgentMeterTypography.fixedTelemetry(17))
                .foregroundStyle(.white)
        }
    }

    private var telemetryStrip: some View {
        HStack(alignment: .top, spacing: 0) {
            telemetryCell("Próxima cobrança", value: nextSubscription.map(renewalDescription) ?? localized("Não programada"))
            telemetryDivider
            telemetryCell("Custo mensal", value: brl(subscriptions.summary.monthlyTotalBRL))
            telemetryDivider
            telemetryCell("Fonte dos valores", value: localized("Informado por você"))
        }
        .padding(.horizontal, AgentMeterTheme.Space.xs)
        .background(Color.white.opacity(0.025))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 0.75)
        }
    }

    private var telemetryDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.14))
            .frame(width: 1, height: 48)
            .padding(.horizontal, AgentMeterTheme.Space.xs)
            .padding(.vertical, AgentMeterTheme.Space.sm)
    }

    private func telemetryCell(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: AgentMeterTheme.Space.xxs) {
            Text(title)
                .font(AgentMeterTypography.fixedRegular(11))
                .textCase(.uppercase)
                .tracking(0.55)
                .foregroundStyle(Color.white.opacity(0.55))
                .lineLimit(2)
                .frame(height: 28, alignment: .topLeading)
            Text(value)
                .font(AgentMeterTypography.telemetry(12, relativeTo: .caption))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.58)
        }
        .padding(.vertical, AgentMeterTheme.Space.sm)
        .frame(minHeight: 68)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var eventRail: some View {
        Button {
            if nextSubscription == nil {
                isPresentingNewSubscription = true
            } else {
                isShowingWallet = true
            }
        } label: {
            HStack(spacing: AgentMeterTheme.Space.md) {
                VStack(alignment: .leading, spacing: AgentMeterTheme.Space.xxs) {
                    Text("Próximo evento")
                        .font(AgentMeterTypography.fixedBold(11))
                        .textCase(.uppercase)
                        .tracking(1.0)
                        .foregroundStyle(AgentMeterTheme.warning)
                    Text(nextSubscription.map { "\($0.provider.displayName) · \($0.planName)" } ?? localized("Nenhuma renovação programada"))
                        .font(AgentMeterTypography.bold(18, relativeTo: .headline))
                        .foregroundStyle(.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    if dynamicTypeSize.isAccessibilitySize {
                        Text(nextSubscription.map(renewalDescription) ?? localized("Adicione seu primeiro plano para receber lembretes."))
                            .font(AgentMeterTypography.regular(16, relativeTo: .subheadline))
                            .foregroundStyle(nextSubscription?.needsRenewalAttention() == true ? AgentMeterTheme.warning : AgentMeterTheme.mutedInk)
                    }
                }
                Spacer(minLength: 0)
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(nextSubscription.map(renewalDescription) ?? localized("Adicionar"))
                        .font(AgentMeterTypography.telemetry(12, relativeTo: .caption))
                        .foregroundStyle(nextSubscription?.needsRenewalAttention() == true ? AgentMeterTheme.warning : Color.primary)
                        .padding(.horizontal, AgentMeterTheme.Space.xs)
                        .frame(minHeight: 28)
                        .overlay {
                            RoundedRectangle(cornerRadius: AgentMeterTheme.Radius.control)
                                .stroke(AgentMeterTheme.border, lineWidth: 0.75)
                        }
                }
                Image(systemName: "chevron.right")
                    .font(AgentMeterTypography.fixedBold(13))
                    .foregroundStyle(AgentMeterTheme.mutedInk)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .agentMeterPanel(padding: AgentMeterTheme.Space.md)
        .accessibilityElement(children: .combine)
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: AgentMeterTheme.Space.sm) {
            AgentMeterSectionHeader(title: "Provedores")
            VStack(spacing: 0) {
                ForEach(Array(AgentMeterProvider.allCases.enumerated()), id: \.element.id) { index, provider in
                    if index > 0 {
                        Divider()
                            .overlay(AgentMeterTheme.border)
                            .padding(.leading, 66)
                    }
                    providerRow(provider)
                }
            }
            .background(AgentMeterTheme.surface, in: RoundedRectangle(cornerRadius: AgentMeterTheme.Radius.panel, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AgentMeterTheme.Radius.panel, style: .continuous)
                    .stroke(AgentMeterTheme.border, lineWidth: 0.75)
            }
        }
    }

    private func providerRow(_ provider: AgentMeterProvider) -> some View {
        let plans = activeSubscriptions.filter { $0.provider == provider }
        let monthly = plans.reduce(Decimal.zero) { $0 + $1.monthlyEquivalentBRL }
        let active = !plans.isEmpty

        return Button {
            if active {
                isShowingWallet = true
            } else {
                providerForNewPlan = provider
            }
        } label: {
            HStack(spacing: AgentMeterTheme.Space.sm) {
                AgentMeterProviderBadge(provider: provider, active: active, size: 36)
                VStack(alignment: .leading, spacing: AgentMeterTheme.Space.xxs) {
                    Text(provider.displayName)
                        .font(AgentMeterTypography.bold(18, relativeTo: .headline))
                        .foregroundStyle(.primary)
                    Text(active ? "Assinatura ativa" : "Não configurado")
                        .font(AgentMeterTypography.regular(15, relativeTo: .caption))
                        .foregroundStyle(AgentMeterTheme.mutedInk)
                }
                Spacer(minLength: AgentMeterTheme.Space.xs)
                VStack(alignment: .trailing, spacing: AgentMeterTheme.Space.xxs) {
                    Text(active ? brl(monthly) : localized("Configurar"))
                        .font(AgentMeterTypography.telemetry(16, relativeTo: .subheadline))
                        .foregroundStyle(active ? Color.primary : AgentMeterTheme.signal)
                        .lineLimit(1)
                    if active {
                        HStack(spacing: 5) {
                            Rectangle()
                                .fill(AgentMeterTheme.nominal)
                                .frame(width: 6, height: 6)
                            Text("Ativo")
                                .font(AgentMeterTypography.fixedRegular(12))
                                .foregroundStyle(AgentMeterTheme.nominal)
                        }
                    }
                }
                Image(systemName: "chevron.right")
                    .font(AgentMeterTypography.fixedBold(13))
                    .foregroundStyle(AgentMeterTheme.mutedInk)
            }
            .padding(.horizontal, AgentMeterTheme.Space.md)
            .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 88 : 68)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(active ? "Abre a carteira de assinaturas" : "Adiciona um plano deste provedor")
    }

    private var trustSection: some View {
        HStack(alignment: .top, spacing: AgentMeterTheme.Space.sm) {
            Image(systemName: "lock.shield")
                .foregroundStyle(AgentMeterTheme.nominal)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: AgentMeterTheme.Space.xxs) {
                Text("Privado por padrão")
                    .font(AgentMeterTypography.bold(16, relativeTo: .subheadline))
                Text("Seus dados ficam neste aparelho. O iCloud é opcional.")
                    .font(AgentMeterTypography.regular(13, relativeTo: .caption))
                    .foregroundStyle(AgentMeterTheme.mutedInk)
            }
        }
        .padding(.vertical, AgentMeterTheme.Space.md)
        .overlay(alignment: .top) {
            Rectangle().fill(AgentMeterTheme.border.opacity(0.72)).frame(height: 0.75)
        }
        .accessibilityElement(children: .combine)
    }

    private var commandBar: some View {
        HStack(spacing: AgentMeterTheme.Space.md) {
            Label("VISÃO GERAL", systemImage: "house.fill")
                .font(AgentMeterTypography.fixedBold(11))
                .tracking(1.17)
                .foregroundStyle(AgentMeterTheme.spectral)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .accessibilityLabel("Visão geral")
            Button {
                isShowingWallet = true
            } label: {
                Label("CARTEIRA", systemImage: "arrow.right")
                    .font(AgentMeterTypography.fixedBold(11))
                    .tracking(1.17)
                    .foregroundStyle(AgentMeterTheme.spectral)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Carteira")
            .accessibilityIdentifier("tab-wallet")
        }
        .padding(.horizontal, 24)
        .overlay(alignment: .top) {
            Rectangle().fill(AgentMeterTheme.border.opacity(0.55)).frame(height: 1)
        }
        .background(Color.black.opacity(0.94))
    }

    private func renewalDescription(_ subscription: AISubscription) -> String {
        let days = subscription.daysUntilRenewal()
        if days == 0 { return localized("Renova hoje") }
        if days == 1 { return localized("Renova amanhã") }
        if days > 1 {
            return String(
                format: selectedLanguage.localized("Renova em %lld dias"),
                locale: selectedLanguage.locale,
                Int64(days)
            )
        }
        return subscription.nextRenewalDate.formatted(date: .abbreviated, time: .omitted)
    }

    private func localized(_ key: String) -> String {
        selectedLanguage.localized(key)
    }
}

#Preview {
    MobileRootView()
        .environmentObject(SubscriptionStore())
}

import AgentMeterCore
import SwiftUI

/// A cinematic mission log. The screens are scenes, not a collection of cards.
struct AgentMeterHomeView: View {
    @EnvironmentObject private var subscriptions: SubscriptionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showArcade = false

    let selectedLanguage: AppLanguage
    let addSubscription: () -> Void
    let addProvider: (AgentMeterProvider) -> Void
    let openWallet: () -> Void

    private var activeSubscriptions: [AISubscription] {
        subscriptions.subscriptions.filter(\.isActive)
    }

    private var nextSubscription: AISubscription? {
        activeSubscriptions.min { $0.nextRenewalDate < $1.nextRenewalDate }
    }

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                missionHero
                renewalScene
                providersScene
                missionFooter
            }
        }
        .scrollIndicators(.hidden)
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showArcade) {
            MissionArcadeView()
        }
    }

    private var missionHero: some View {
        ZStack(alignment: .bottomLeading) {
            MissionField(planetOffset: CGSize(width: 150, height: -150), seed: 7)
            LinearGradient(
                colors: [.black.opacity(0.06), .black.opacity(0.64), .black],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("AGENTMETER")
                        .font(AgentMeterTypography.fixedBold(13))
                        .tracking(1.17)
                    Spacer()
                    Text("MISSION // 01")
                        .font(AgentMeterTypography.fixedRegular(10))
                        .tracking(1)
                        .foregroundStyle(AgentMeterTheme.mutedInk)
                        .onLongPressGesture(minimumDuration: 1.4) { showArcade = true }
                }

                Spacer(minLength: 46)

                Text(activeSubscriptions.isEmpty ? "INICIE\nSUA MISSÃO" : "SEU CUSTO\nEM ÓRBITA")
                    .font(AgentMeterTypography.bold(46, relativeTo: .largeTitle))
                    .tracking(0.96)
                    .lineSpacing(-5)
                    .minimumScaleFactor(0.64)
                    .accessibilityAddTraits(.isHeader)

                if activeSubscriptions.isEmpty {
                    Text("ADICIONE UM PLANO PARA MONITORAR CUSTOS E RENOVAÇÕES.")
                        .missionBody()
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("PROJEÇÃO MENSAL")
                            .missionMicro()
                        Text(brl(subscriptions.summary.monthlyTotalBRL))
                            .font(AgentMeterTypography.bold(42, relativeTo: .title))
                            .tracking(0.96)
                            .monospacedDigit()
                        Text(activePlansLabel)
                            .missionBody(color: AgentMeterTheme.mutedInk)
                    }
                }

                Button(action: activeSubscriptions.isEmpty ? addSubscription : openWallet) {
                    Label(activeSubscriptions.isEmpty ? "ADICIONAR PLANO" : "ABRIR CARTEIRA", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(MissionGhostButtonStyle())
                .accessibilityIdentifier("home-add-subscription")
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 40)
        }
        .frame(minHeight: 620)
        .accessibilityElement(children: .contain)
    }

    private var renewalScene: some View {
        ZStack(alignment: .bottomLeading) {
            MissionField(planetOffset: CGSize(width: -165, height: -125), seed: 29, reverse: true)
            LinearGradient(colors: [.black.opacity(0.12), .black.opacity(0.72), .black], startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 16) {
                Text("MISSION // 02")
                    .missionMicro()
                Spacer()
                Text("PRÓXIMA\nCOBRANÇA")
                    .font(AgentMeterTypography.bold(39, relativeTo: .title))
                    .tracking(0.96)
                    .lineSpacing(-4)

                if let nextSubscription {
                    Text(brl(nextSubscription.cycleTotalBRL))
                        .font(AgentMeterTypography.bold(38, relativeTo: .title))
                        .tracking(0.96)
                        .monospacedDigit()
                    Text("\(nextSubscription.provider.displayName.uppercased()) // \(nextSubscription.planName.uppercased())")
                        .missionBody()
                    Text(renewalDescription(nextSubscription).uppercased())
                        .missionMicro(color: AgentMeterTheme.mutedInk)
                } else {
                    Text("NENHUMA COBRANÇA PROGRAMADA.")
                        .missionBody()
                }

                Button(action: nextSubscription == nil ? addSubscription : openWallet) {
                    Label(nextSubscription == nil ? "CONFIGURAR PLANO" : "VER RENOVAÇÕES", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(MissionGhostButtonStyle())
            }
            .padding(24)
            .padding(.bottom, 42)
        }
        .frame(minHeight: 560)
    }

    private var providersScene: some View {
        ZStack(alignment: .bottomLeading) {
            MissionField(planetOffset: CGSize(width: 170, height: -240), seed: 51)
            LinearGradient(colors: [.black.opacity(0.22), .black.opacity(0.78), .black], startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 0) {
                Text("MISSION // 03")
                    .missionMicro()
                    .padding(.bottom, 18)
                Text("SERVIÇOS\nEM VOO")
                    .font(AgentMeterTypography.bold(39, relativeTo: .title))
                    .tracking(0.96)
                    .lineSpacing(-4)
                    .padding(.bottom, 30)

                ForEach(Array(AgentMeterProvider.allCases.enumerated()), id: \.element.id) { index, provider in
                    if index > 0 { Rectangle().fill(AgentMeterTheme.border.opacity(0.5)).frame(height: 1) }
                    providerRow(provider)
                }
                Spacer(minLength: 28)
            }
            .padding(24)
            .padding(.top, 38)
        }
        .frame(minHeight: 590)
    }

    private func providerRow(_ provider: AgentMeterProvider) -> some View {
        let plans = activeSubscriptions.filter { $0.provider == provider }
        let configured = !plans.isEmpty
        let amount = plans.reduce(Decimal.zero) { $0 + $1.monthlyEquivalentBRL }

        return Button {
            configured ? openWallet() : addProvider(provider)
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Text(String(format: "%02d", providerIndex(provider)))
                    .font(AgentMeterTypography.fixedRegular(11))
                    .tracking(1)
                    .foregroundStyle(AgentMeterTheme.mutedInk)
                VStack(alignment: .leading, spacing: 5) {
                    Text(provider.displayName.uppercased())
                        .font(AgentMeterTypography.fixedBold(15))
                        .tracking(1.17)
                    Text(configured ? plans.first?.planName.uppercased() ?? "ATIVO" : "NÃO CONFIGURADO")
                        .missionMicro(color: AgentMeterTheme.mutedInk)
                }
                Spacer()
                Text(configured ? brl(amount) : "+")
                    .font(AgentMeterTypography.fixedBold(16))
                    .tracking(0.96)
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .contentShape(Rectangle())
        }
        .buttonStyle(MissionRowButtonStyle())
        .accessibilityIdentifier("provider-\(provider.rawValue)")
    }

    private var missionFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rectangle().fill(AgentMeterTheme.border.opacity(0.5)).frame(height: 1)
            Text("DADOS PRIVADOS NESTE APARELHO. ICLOUD É OPCIONAL.")
                .missionMicro(color: AgentMeterTheme.mutedInk)
            Text("AGENTMETER // FLIGHT SYSTEM")
                .missionMicro(color: AgentMeterTheme.spectral.opacity(0.38))
        }
        .padding(24)
        .padding(.bottom, 116)
        .background(Color.black)
    }

    private var activePlansLabel: String {
        activeSubscriptions.count == 1 ? "1 PLANO ATIVO" : "\(activeSubscriptions.count) PLANOS ATIVOS"
    }

    private func providerIndex(_ provider: AgentMeterProvider) -> Int {
        (AgentMeterProvider.allCases.firstIndex(of: provider) ?? 0) + 1
    }

    private func renewalDescription(_ subscription: AISubscription) -> String {
        let days = subscription.daysUntilRenewal()
        if days == 0 { return selectedLanguage.localized("Renova hoje") }
        if days == 1 { return selectedLanguage.localized("Renova amanhã") }
        if days > 1 {
            return String(format: selectedLanguage.localized("Renova em %lld dias"), locale: selectedLanguage.locale, Int64(days))
        }
        return subscription.nextRenewalDate.formatted(date: .abbreviated, time: .omitted)
    }
}

struct MissionField: View {
    let planetOffset: CGSize
    let seed: Int
    var reverse = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                ForEach(0..<42, id: \.self) { index in
                    Circle()
                        .fill(AgentMeterTheme.spectral.opacity(index.isMultiple(of: 5) ? 0.72 : 0.28))
                        .frame(width: index.isMultiple(of: 7) ? 2 : 1, height: index.isMultiple(of: 7) ? 2 : 1)
                        .position(
                            x: CGFloat((index * 53 + seed * 17) % 100) / 100 * proxy.size.width,
                            y: CGFloat((index * 31 + seed * 11) % 100) / 100 * proxy.size.height
                        )
                }
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [AgentMeterTheme.spectral.opacity(0.30), AgentMeterTheme.spectral.opacity(0.06), .clear],
                            center: reverse ? .bottomTrailing : .topLeading,
                            startRadius: 1,
                            endRadius: proxy.size.width * 0.56
                        )
                    )
                    .frame(width: proxy.size.width * 1.08, height: proxy.size.width * 1.08)
                    .offset(planetOffset)
                    .blur(radius: 1)
                Circle()
                    .stroke(AgentMeterTheme.spectral.opacity(0.18), lineWidth: 1)
                    .frame(width: proxy.size.width * 0.88, height: proxy.size.width * 0.88)
                    .offset(planetOffset)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct MissionGhostButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AgentMeterTypography.fixedBold(13))
            .tracking(1.17)
            .foregroundStyle(AgentMeterTheme.spectral)
            .background(AgentMeterTheme.spectral.opacity(configuration.isPressed ? 0.20 : 0.10), in: Capsule())
            .overlay { Capsule().stroke(AgentMeterTheme.border, lineWidth: 1) }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private struct MissionRowButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(AgentMeterTheme.spectral)
            .opacity(configuration.isPressed ? 0.58 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.99 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct MissionArcadeView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var altitude = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Text("ARCADE // LANDER")
                    .font(AgentMeterTypography.fixedBold(17))
                    .tracking(1.17)
                Text("▲")
                    .font(AgentMeterTypography.fixedBold(80))
                    .offset(y: CGFloat(-altitude))
                Text("ALTITUDE \(max(0, 120 - altitude))")
                    .missionMicro()
                Button("THRUST") { altitude = min(120, altitude + 20) }
                    .buttonStyle(MissionGhostButtonStyle())
                Button("ENCERRAR") { dismiss() }
                    .font(AgentMeterTypography.fixedRegular(12))
                    .tracking(1)
                    .foregroundStyle(AgentMeterTheme.mutedInk)
            }
            .foregroundStyle(AgentMeterTheme.spectral)
            .padding(24)
        }
    }
}

extension View {
    func missionMicro(color: Color = AgentMeterTheme.spectral) -> some View {
        font(AgentMeterTypography.fixedRegular(11))
            .tracking(1)
            .foregroundStyle(color)
    }

    func missionBody(color: Color = AgentMeterTheme.spectral) -> some View {
        font(AgentMeterTypography.regular(16, relativeTo: .body))
            .tracking(0.96)
            .foregroundStyle(color)
    }
}

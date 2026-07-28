import AgentMeterCore
import SwiftUI

/// Compact control center: one purpose per tab, without a dashboard crammed
/// into the menu bar popover.
struct MenuBarContentView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case overview, costs, settings
        var id: Self { self }
        var icon: String {
            switch self {
            case .overview: "gauge.with.dots.needle.33percent"
            case .costs: "brazilianrealsign.circle"
            case .settings: "slider.horizontal.3"
            }
        }
        var label: String {
            switch self {
            case .overview: "Agora"
            case .costs: "Gastos"
            case .settings: "Ajustes"
            }
        }
    }

    @Environment(UsageStore.self) private var store
    @Environment(PreferencesStore.self) private var preferences
    @Environment(WindowRouter.self) private var router
    @EnvironmentObject private var spending: SubscriptionStore
    @State private var selectedTab: Tab = .overview

    var body: some View {
        @Bindable var preferences = preferences

        VStack(alignment: .leading, spacing: 14) {
            header
            tabPicker
            tabContent(preferences: $preferences)
            Divider()
            HStack {
                Button("Sair") { NSApp.terminate(nil) }
                    .foregroundStyle(.secondary)
                Spacer()
                Button(selectedTab == .costs ? "Abrir gastos" : "Dashboard") {
                    selectedTab == .costs ? router.openSpending() : router.openDashboard()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 340)
        .preferredColorScheme(preferences.settings.themeMode.colorScheme)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundStyle(.orange)
                .font(.system(size: 14, weight: .semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text("NOTCHAGENT").font(.system(size: 11, weight: .bold, design: .rounded)).tracking(1.4)
                Text("Controle de capacidade e custo").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if store.isPaused { Text("PAUSADO").font(.caption2.bold()).foregroundStyle(.orange) }
        }
    }

    private var tabPicker: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Label(tab.label, systemImage: tab.icon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(selectedTab == tab ? .orange : .gray)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func tabContent(preferences: Bindable<PreferencesStore>) -> some View {
        switch selectedTab {
        case .overview: overview
        case .costs: costs
        case .settings: settings(preferences: preferences)
        }
    }

    private var overview: some View {
        VStack(spacing: 8) {
            ForEach(ProviderID.allCases) { provider in providerRow(provider) }
            HStack {
                Button("Atualizar", systemImage: "arrow.clockwise") { AppEnvironment.shared.scheduler.refreshNow() }
                Spacer()
                Button(store.isPaused ? "Retomar" : "Pausar", systemImage: store.isPaused ? "play.fill" : "pause.fill") {
                    store.isPaused.toggle()
                }
            }
            .controlSize(.small)
        }
    }

    private var costs: some View {
        let estimate = EstimatedCostLayers.fromSnapshots(store.snapshots)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                costMetric("PAGO · MÊS", spending.format(spending.monthlySpend.paidBRL))
                Divider().frame(height: 34).padding(.horizontal, 12)
                costMetric("EST. · 7D", spending.formatEstimatedUSD(estimate.totalUSD))
            }
            if let budget = spending.monthlyBudgetStatus {
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text("ORÇAMENTO").font(.caption2.bold()).foregroundStyle(.secondary); Spacer(); Text("\(Int(budget.projectedPercent.rounded()))%") .font(.caption.bold()) }
                    ProgressView(value: min(budget.projectedPercent, 100), total: 100).tint(budget.level == .normal ? .green : budget.level == .warning ? .orange : .red)
                }
            } else {
                Text("Defina um orçamento para receber alertas.").font(.caption).foregroundStyle(.secondary)
            }
            Button("Gerenciar gastos e orçamento", systemImage: "arrow.up.right.square") { router.openSpending() }
                .controlSize(.small)
        }
    }

    private func settings(preferences: Bindable<PreferencesStore>) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Toggle("Alertas do sistema", isOn: preferences.settings.notificationsEnabled)
            Picker("Aparência", selection: preferences.settings.themeMode) {
                ForEach(ThemeMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Picker("Idioma", selection: preferences.settings.interfaceLanguage) {
                ForEach(InterfaceLanguage.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Button("Abrir todos os ajustes", systemImage: "gearshape") { router.openSettings() }
                .controlSize(.small)
        }
    }

    private func providerRow(_ provider: ProviderID) -> some View {
        let snapshot = store.snapshots[provider]
        return HStack(spacing: 9) {
            Image(systemName: provider.symbolName).frame(width: 16).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(provider.displayName).font(.subheadline.weight(.semibold))
                Text(detail(for: snapshot)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            AttentionDot(level: store.attention(for: provider))
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func costMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2.bold()).foregroundStyle(.secondary)
            Text(value).font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit()
        }
    }

    private func detail(for snapshot: UsageSnapshot?) -> String {
        guard let snapshot else { return "Aguardando dados" }
        guard snapshot.health.isUsable else { return snapshot.health.badgeText }
        if let metric = GaugeMetric.from(snapshot) { return "\(Int(metric.remaining.rounded()))% restante" }
        return snapshot.note ?? "Sem limite disponível"
    }
}

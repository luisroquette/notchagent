import AgentMeterCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SpendingView: View {
    @Environment(UsageStore.self) private var usageStore
    @EnvironmentObject private var store: SubscriptionStore
    @State private var showingPlanEditor = false
    @State private var showingExpenseEditor = false
    @State private var showingInvoiceImporter = false
    @State private var invoicePreview: InvoiceImportPreview?

    var body: some View {
        List {
            Section("Gasto no mês") {
                TextField("Orçamento mensal em R$", text: Binding(
                    get: { store.monthlyBudgetBRL.map { NSDecimalNumber(decimal: $0).stringValue } ?? "" },
                    set: { store.setMonthlyBudgetBRL(BRLFormat.decimal($0)) }
                ))
                Picker("Moeda", selection: Binding(
                    get: { store.displayCurrency },
                    set: { store.setDisplayCurrency($0) }
                )) {
                    Text("BRL").tag(SpendDisplayCurrency.brl)
                    Text("USD").tag(SpendDisplayCurrency.usd)
                }
                if store.displayCurrency == .usd {
                    TextField("Cotação: R$ por US$", text: Binding(
                        get: { store.brlPerUSD.map { NSDecimalNumber(decimal: $0).stringValue } ?? "" },
                        set: { store.setBRLPerUSD(BRLFormat.decimal($0)) }
                    ))
                    Text("Conversão manual; não consultamos cotação externa.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    metric("Pago", store.monthlySpend.paidBRL)
                    Spacer()
                    metric("Previsto", store.monthlySpend.forecastPlanBRL)
                    Spacer()
                    estimateMetric
                }
                .padding(.vertical, 6)
                if let budget = store.monthlyBudgetStatus {
                    VStack(alignment: .leading, spacing: 5) {
                        ProgressView(value: min(budget.projectedPercent, 100), total: 100)
                            .tint(budgetColor(budget.level))
                        Text("Previsão de fechamento: \(store.format(budget.projectedBRL)) / \(store.format(budget.budgetBRL)) · \(Int(budget.projectedPercent.rounded()))%")
                            .font(.caption)
                            .foregroundStyle(budgetColor(budget.level))
                    }
                }
                Text("Pago = cobrança confirmada. Previsto = próxima renovação. Estimado = tokens locais; não é cobrança.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Planos") {
                if store.subscriptions.isEmpty {
                    Text("Nenhum plano cadastrado.").foregroundStyle(.secondary)
                }
                ForEach(store.subscriptions) { plan in
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(plan.provider.displayName) · \(plan.planName)")
                            Text("Próxima renovação: \(plan.nextRenewalDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(store.format(plan.cycleTotalBRL)).monospacedDigit()
                        Button("Confirmar") { _ = store.confirmRenewal(id: plan.id) }
                            .controlSize(.small)
                    }
                }
                Button("Adicionar plano", systemImage: "plus") { showingPlanEditor = true }
            }

            Section("Chamadas extras e créditos") {
                let currentExpenses = store.expenses.filter {
                    Calendar.current.isDate($0.incurredAt, equalTo: .now, toGranularity: .month)
                }
                if currentExpenses.isEmpty {
                    Text("Nenhum gasto extra neste mês.").foregroundStyle(.secondary)
                }
                ForEach(currentExpenses) { expense in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(expense.title.isEmpty ? expense.kind.label : expense.title)
                            Text("\(expense.provider.displayName) · \(expense.source.label)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(store.format(expense.amountBRL)).monospacedDigit()
                        Button(role: .destructive) { store.removeExpense(id: expense.id) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button("Adicionar gasto extra", systemImage: "plus") { showingExpenseEditor = true }
            }

            Section("Conciliação") {
                let estimates = EstimatedCostLayers.fromSnapshots(usageStore.snapshots)
                let reconciliation = CostReconciliation.currentMonth(expenses: store.expenses, estimates: estimates)
                if reconciliation.isEmpty {
                    Text("Importe uma fatura CSV ou gere uso local para comparar.").foregroundStyle(.secondary)
                }
                ForEach(reconciliation) { row in
                    HStack {
                        Text(row.provider.displayName)
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("Oficial: \(store.format(row.officialBRL))")
                            Text("Local: \(store.formatEstimatedUSD(row.estimatedUSD))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Importar fatura CSV", systemImage: "square.and.arrow.down") { showingInvoiceImporter = true }
                Text("CSV: date, provider, amount_brl, description. A comparação só é aproximada: sessões web e desktop podem não existir nos arquivos locais.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Histórico mensal") {
                let rows = FinancialHistory.monthlyPayments(history: store.history, expenses: store.expenses)
                if rows.isEmpty {
                    Text("O histórico começa após confirmar cobranças ou importar faturas.").foregroundStyle(.secondary)
                }
                ForEach(rows) { row in
                    HStack {
                        Text(row.month.formatted(.dateTime.month(.abbreviated).year()))
                        Text(row.provider.displayName).foregroundStyle(.secondary)
                        Spacer()
                        Text(store.format(row.amountBRL)).monospacedDigit()
                    }
                }
                Button("Exportar CSV", systemImage: "square.and.arrow.up") { exportHistory(rows) }
            }
        }
        .navigationTitle("Gastos")
        .frame(minWidth: 560, minHeight: 500)
        .sheet(isPresented: $showingPlanEditor) { PlanEditor(store: store) }
        .sheet(isPresented: $showingExpenseEditor) { ExpenseEditor(store: store) }
        .fileImporter(isPresented: $showingInvoiceImporter, allowedContentTypes: [.commaSeparatedText], allowsMultipleSelection: false) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return }
            invoicePreview = InvoiceImportParser.preview(data: data)
        }
        .alert("Importar fatura", isPresented: Binding(get: { invoicePreview != nil }, set: { if !$0 { invoicePreview = nil } })) {
            Button("Cancelar", role: .cancel) { invoicePreview = nil }
            Button("Importar") {
                if let invoicePreview { store.addExpenses(invoicePreview.expenses) }
                invoicePreview = nil
            }
        } message: {
            Text("\(invoicePreview?.expenses.count ?? 0) lançamento(s) oficial(is). \(invoicePreview?.issues.count ?? 0) linha(s) ignorada(s).")
        }
    }

    private func metric(_ title: String, _ amount: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(.caption2.bold()).foregroundStyle(.secondary)
            Text(store.format(amount)).font(.title3.bold()).monospacedDigit()
        }
    }

    private var estimateMetric: some View {
        let estimate = EstimatedCostLayers.fromSnapshots(usageStore.snapshots)
        return VStack(alignment: .leading, spacing: 3) {
            Text("ESTIMADO · 7D").font(.caption2.bold()).foregroundStyle(.secondary)
            Text(store.formatEstimatedUSD(estimate.totalUSD)).font(.title3.bold()).monospacedDigit()
        }
    }

    private func budgetColor(_ level: MonthlyBudgetLevel) -> Color {
        switch level { case .normal: .secondary; case .warning: .orange; case .critical, .exceeded: .red }
    }

    private func exportHistory(_ rows: [MonthlyProviderSpend]) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "notchagent-historico-mensal.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? FinancialHistory.csv(rows).data(using: .utf8)?.write(to: url, options: .atomic)
    }
}

private struct PlanEditor: View {
    @Environment(\.dismiss) private var dismiss
    let store: SubscriptionStore
    @State private var provider: AgentMeterProvider = .claude
    @State private var name = ""
    @State private var amount = ""
    @State private var renewal = Date()

    var body: some View {
        Form {
            Picker("Fornecedor", selection: $provider) { ForEach(AgentMeterProvider.allCases) { Text($0.displayName).tag($0) } }
            TextField("Plano", text: $name)
            TextField("Valor em R$", text: $amount)
            DatePicker("Próxima renovação", selection: $renewal, displayedComponents: .date)
            HStack { Spacer(); Button("Cancelar") { dismiss() }; Button("Salvar") {
                guard let value = BRLFormat.decimal(amount), value > 0 else { return }
                store.add(AISubscription(provider: provider, planName: name, basePriceBRL: value, nextRenewalDate: renewal))
                dismiss()
            }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || BRLFormat.decimal(amount) == nil) }
        }
        .padding().frame(width: 390)
    }
}

private struct ExpenseEditor: View {
    @Environment(\.dismiss) private var dismiss
    let store: SubscriptionStore
    @State private var provider: AgentMeterProvider = .claude
    @State private var title = ""
    @State private var amount = ""
    @State private var kind: AIExpense.Kind = .usageCredits
    @State private var source: AIExpense.Source = .manual

    var body: some View {
        Form {
            Picker("Fornecedor", selection: $provider) { ForEach(AgentMeterProvider.allCases) { Text($0.displayName).tag($0) } }
            TextField("Descrição", text: $title)
            TextField("Valor em R$", text: $amount)
            Picker("Tipo", selection: $kind) { ForEach(AIExpense.Kind.allCases, id: \.self) { Text($0.label).tag($0) } }
            Picker("Origem", selection: $source) { ForEach(AIExpense.Source.allCases, id: \.self) { Text($0.label).tag($0) } }
            HStack { Spacer(); Button("Cancelar") { dismiss() }; Button("Salvar") {
                guard let value = BRLFormat.decimal(amount), value > 0 else { return }
                store.addExpense(AIExpense(provider: provider, title: title, amountBRL: value, kind: kind, source: source))
                dismiss()
            }.disabled(BRLFormat.decimal(amount) == nil) }
        }
        .padding().frame(width: 390)
    }
}

private extension AIExpense.Kind {
    var label: String { switch self { case .apiUsage: "Uso de API"; case .usageCredits: "Créditos de uso"; case .tokenPurchase: "Compra de tokens"; case .other: "Outro" } }
}

private extension AIExpense.Source {
    var label: String { switch self { case .manual: "Informado manualmente"; case .officialInvoice: "Fatura oficial"; case .localEstimate: "Estimativa local" } }
}

enum BRLFormat {
    static func string(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "BRL"
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: amount as NSDecimalNumber) ?? "R$ 0,00"
    }

    static func decimal(_ input: String) -> Decimal? {
        let trimmed = input
            .replacingOccurrences(of: "R$", with: "")
            .replacingOccurrences(of: " ", with: "")
        let normalized: String
        if trimmed.contains(",") {
            // Brazilian input: 1.234,56. A plain dot remains a decimal separator.
            normalized = trimmed.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else {
            normalized = trimmed
        }
        return Decimal(string: normalized)
    }
}

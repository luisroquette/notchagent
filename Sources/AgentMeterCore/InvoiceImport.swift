import Foundation

public struct InvoiceImportPreview: Equatable, Sendable {
    public var expenses: [AIExpense]
    public var issues: [SubscriptionImportIssue]

    public init(expenses: [AIExpense], issues: [SubscriptionImportIssue]) {
        self.expenses = expenses
        self.issues = issues
    }
}

/// Imports a deliberately small, auditable format:
/// date,provider,amount_brl,description
public enum InvoiceImportParser {
    public static let template = "date,provider,amount_brl,description\n"

    public static func preview(data: Data) -> InvoiceImportPreview {
        guard let text = String(data: data, encoding: .utf8) else {
            return .init(expenses: [], issues: [.init(line: 0, message: "Não foi possível ler o CSV em UTF-8.")])
        }
        let rows = text.split(whereSeparator: \.isNewline).map(String.init)
        guard let header = rows.first else { return .init(expenses: [], issues: [.init(line: 0, message: "O CSV está vazio.")]) }
        let fields = header.split(separator: ",").map { normalize(String($0)) }
        let required = ["date", "provider", "amountbrl"]
        guard required.allSatisfy(fields.contains) else {
            return .init(expenses: [], issues: [.init(line: 1, message: "Cabeçalhos obrigatórios: date, provider, amount_brl, description.")])
        }

        var expenses: [AIExpense] = []
        var issues: [SubscriptionImportIssue] = []
        for (offset, raw) in rows.dropFirst().enumerated() {
            let line = offset + 2
            let values = raw.split(separator: ",", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard !values.allSatisfy(\.isEmpty) else { continue }
            let row = Dictionary(zip(fields, values), uniquingKeysWith: { first, _ in first })
            guard let provider = provider(row["provider"]) else { issues.append(.init(line: line, message: "Provedor inválido.")); continue }
            guard let amount = decimal(row["amountbrl"]), amount > 0 else { issues.append(.init(line: line, message: "amount_brl deve ser maior que zero.")); continue }
            guard let date = date(row["date"]) else { issues.append(.init(line: line, message: "Data inválida; use AAAA-MM-DD.")); continue }
            expenses.append(.init(provider: provider, title: row["description"] ?? "Fatura importada", amountBRL: amount, kind: .apiUsage, source: .officialInvoice, incurredAt: date))
        }
        return .init(expenses: expenses, issues: issues)
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
    private static func provider(_ text: String?) -> AgentMeterProvider? {
        switch text?.lowercased().replacingOccurrences(of: " ", with: "") {
        case "claude": .claude
        case "chatgpt", "openai", "codex": .chatGPT
        case "gemini", "google": .gemini
        default: nil
        }
    }
    private static func decimal(_ text: String?) -> Decimal? {
        guard var text else { return nil }
        text = text.replacingOccurrences(of: "R$", with: "").replacingOccurrences(of: " ", with: "")
        if text.contains(",") { text = text.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
        return Decimal(string: text)
    }
    private static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }
}

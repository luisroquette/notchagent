import Foundation

public enum SubscriptionImportFormat: Sendable {
    case csv
    case json
}

/// A ready-to-fill CSV that is valid when left empty and never imports sample
/// subscriptions by accident.
public enum SubscriptionImportTemplate {
    public static let filename = "agentmeter-assinaturas.csv"
    public static let csv = "provider,plan,price,cycle,renewal_date,tax,reminder_days\n"

    public static var data: Data { Data(csv.utf8) }
}

public struct SubscriptionImportIssue: Identifiable, Equatable, Sendable {
    public let line: Int
    public let message: String

    public var id: String { "\(line)-\(message)" }

    public init(line: Int, message: String) {
        self.line = line
        self.message = message
    }
}

public struct SubscriptionImportPreview: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let subscriptions: [AISubscription]
    public let issues: [SubscriptionImportIssue]
    public let duplicateCount: Int

    public init(
        id: UUID = UUID(),
        subscriptions: [AISubscription],
        issues: [SubscriptionImportIssue],
        duplicateCount: Int
    ) {
        self.id = id
        self.subscriptions = subscriptions
        self.issues = issues
        self.duplicateCount = duplicateCount
    }
}

public enum SubscriptionImportParser {
    public static func preview(
        data: Data,
        format: SubscriptionImportFormat,
        existing: [AISubscription]
    ) -> SubscriptionImportPreview {
        let rows: [RawSubscription]
        let initialIssues: [SubscriptionImportIssue]

        switch format {
        case .csv:
            (rows, initialIssues) = parseCSV(data: data)
        case .json:
            (rows, initialIssues) = parseJSON(data: data)
        }

        var subscriptions: [AISubscription] = []
        var issues = initialIssues
        var keys = Set(existing.filter(\.isActive).map(duplicateKey))
        var duplicates = 0

        for row in rows {
            switch subscription(from: row) {
            case .success(let subscription):
                let key = duplicateKey(subscription)
                guard keys.insert(key).inserted else {
                    duplicates += 1
                    continue
                }
                subscriptions.append(subscription)
            case .failure(let error):
                issues.append(SubscriptionImportIssue(line: row.line, message: error.message))
            }
        }

        return SubscriptionImportPreview(
            subscriptions: subscriptions,
            issues: issues.sorted { $0.line < $1.line },
            duplicateCount: duplicates
        )
    }

    public static func duplicateKey(_ subscription: AISubscription) -> String {
        "\(subscription.provider.rawValue)|\(subscription.planName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(subscription.billingCycle.rawValue)"
    }

    private struct RawSubscription {
        let line: Int
        let values: [String: String]
    }

    private struct ParseFailure: Error {
        let message: String
    }

    private static func parseJSON(data: Data) -> ([RawSubscription], [SubscriptionImportIssue]) {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let entries = object as? [[String: Any]] else {
            return ([], [SubscriptionImportIssue(line: 0, message: "O JSON deve conter uma lista de assinaturas.")])
        }

        return (entries.enumerated().map { index, entry in
            RawSubscription(
                line: index + 1,
                values: Dictionary(entry.compactMap { key, value in
                    guard let value = value as? String ?? (value as? NSNumber)?.stringValue else { return nil }
                    return (normalizedHeader(key), value)
                }, uniquingKeysWith: { first, _ in first })
            )
        }, [])
    }

    private static func parseCSV(data: Data) -> ([RawSubscription], [SubscriptionImportIssue]) {
        guard let text = String(data: data, encoding: .utf8) else {
            return ([], [SubscriptionImportIssue(line: 0, message: "Não foi possível ler o CSV em UTF-8.")])
        }
        let records = csvRecords(text)
        guard let header = records.first else {
            return ([], [SubscriptionImportIssue(line: 0, message: "O CSV está vazio.")])
        }

        let headers = header.map(normalizedHeader)
        let required = ["provider", "plan", "price", "cycle", "renewaldate"]
        let missing = required.filter { !headers.contains($0) }
        guard missing.isEmpty else {
            return ([], [SubscriptionImportIssue(line: 1, message: "Cabeçalhos obrigatórios: provider, plan, price, cycle, renewal_date.")])
        }

        return (records.dropFirst().enumerated().compactMap { index, fields in
            guard fields.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return nil }
            let values = Dictionary(zip(headers, fields).map { ($0, $1) }, uniquingKeysWith: { first, _ in first })
            return RawSubscription(line: index + 2, values: values)
        }, [])
    }

    private static func subscription(from row: RawSubscription) -> Result<AISubscription, ParseFailure> {
        let values = row.values
        guard let provider = provider(values["provider"]) else { return .failure(ParseFailure(message: "Provedor inválido. Use Claude, ChatGPT ou Gemini.")) }
        guard let plan = value("plan", in: values) ?? value("planname", in: values), !plan.isEmpty else { return .failure(ParseFailure(message: "Nome do plano é obrigatório.")) }
        guard let price = decimal(values["price"]), price > 0 else { return .failure(ParseFailure(message: "Preço deve ser maior que zero.")) }
        guard let cycle = billingCycle(values["cycle"] ?? values["billingcycle"]) else { return .failure(ParseFailure(message: "Ciclo inválido. Use monthly ou yearly.")) }
        guard let renewalDate = date(values["renewaldate"] ?? values["nextrenewaldate"]) else { return .failure(ParseFailure(message: "Data de renovação inválida. Use AAAA-MM-DD.")) }

        let tax = decimal(values["tax"] ?? values["taxpercentage"]) ?? 0
        guard tax >= 0 else { return .failure(ParseFailure(message: "Impostos não podem ser negativos.")) }
        let reminder = Int(values["reminderdays"] ?? values["reminderdaysbefore"] ?? "3") ?? 3

        return .success(AISubscription(
            provider: provider,
            planName: plan,
            basePriceBRL: price,
            taxPercentage: tax,
            billingCycle: cycle,
            nextRenewalDate: renewalDate,
            reminderDaysBefore: max(0, reminder)
        ))
    }

    private static func provider(_ value: String?) -> AgentMeterProvider? {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: " ", with: "") {
        case "claude": .claude
        case "chatgpt", "openai": .chatGPT
        case "gemini", "google": .gemini
        default: nil
        }
    }

    private static func billingCycle(_ value: String?) -> BillingCycle? {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "monthly", "mensal": .monthly
        case "yearly", "annual", "anual": .yearly
        default: nil
        }
    }

    private static func decimal(_ value: String?) -> Decimal? {
        guard var value else { return nil }
        value = value.replacingOccurrences(of: "R$", with: "")
            .replacingOccurrences(of: " ", with: "")
        if value.contains(",") && value.contains(".") {
            value = value.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else {
            value = value.replacingOccurrences(of: ",", with: ".")
        }
        return Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: value) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func value(_ key: String, in values: [String: String]) -> String? {
        values[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedHeader(_ header: String) -> String {
        header.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    private static func csvRecords(_ text: String) -> [[String]] {
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var quoted = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if character == "\"" {
                let next = text.index(after: index)
                if quoted && next < text.endIndex && text[next] == "\"" {
                    field.append("\"")
                    index = next
                } else {
                    quoted.toggle()
                }
            } else if character == "," && !quoted {
                record.append(field)
                field = ""
            } else if (character == "\n" || character == "\r") && !quoted {
                if character == "\r", text.index(after: index) < text.endIndex, text[text.index(after: index)] == "\n" {
                    index = text.index(after: index)
                }
                record.append(field)
                records.append(record)
                record = []
                field = ""
            } else {
                field.append(character)
            }
            index = text.index(after: index)
        }

        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            records.append(record)
        }
        return records
    }
}

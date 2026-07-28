import Foundation

/// Retrieves the official USD/BRL PTAX closing quote from Banco Central do
/// Brasil. The source is daily, so callers cache it instead of polling it on
/// each API-monitor refresh.
actor BRLExchangeRateService {
    static let shared = BRLExchangeRateService()

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .current
        return calendar
    }()

    func latestUSDToBRL(now: Date = .now, session: URLSession = .shared) async -> Decimal? {
        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now),
                  let url = quoteURL(for: date) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let quote = Self.usdSaleQuote(data: data)
            else { continue }
            return quote
        }
        return nil
    }

    private func quoteURL(for date: Date) -> URL? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "MM-dd-yyyy"
        var components = URLComponents(string: "https://olinda.bcb.gov.br/olinda/servico/PTAX/versao/v1/odata/CotacaoDolarDia(dataCotacao=@dataCotacao)")
        components?.queryItems = [
            URLQueryItem(name: "@dataCotacao", value: "'\(formatter.string(from: date))'"),
            URLQueryItem(name: "$format", value: "json"),
        ]
        return components?.url
    }

    static func usdSaleQuote(data: Data) -> Decimal? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let quote = (root["value"] as? [[String: Any]])?.first,
              let value = quote["cotacaoVenda"] as? Double,
              value > 0
        else { return nil }
        return Decimal(value)
    }
}

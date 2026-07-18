import Foundation

public enum AgentMeterProduct {
    public static let brandName = "AgentMeter"
    public static let mobileName = "AgentMeter: AI Control"
    public static let macName = "AgentMeter: NotchAgent"
    public static let windowsName = "AgentMeter: Desktop Bar"
}

public enum AgentMeterProvider: String, CaseIterable, Codable, Sendable, Identifiable {
    case claude
    case chatGPT = "chatgpt"
    case gemini

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .chatGPT: "ChatGPT"
        case .gemini: "Gemini"
        }
    }
}

public enum MetricSource: String, Codable, Sendable {
    case manual
    case officialImport
    case macSync
}

public struct MetricProvenance: Codable, Sendable, Equatable {
    public var source: MetricSource
    public var capturedAt: Date
    public var confidence: Double

    public init(source: MetricSource, capturedAt: Date, confidence: Double) {
        self.source = source
        self.capturedAt = capturedAt
        self.confidence = min(max(confidence, 0), 1)
    }
}

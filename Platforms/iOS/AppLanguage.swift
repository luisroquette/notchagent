import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case portuguese = "pt-BR"
    case english = "en"

    static let storageKey = "agentmeter.language"

    var id: String { rawValue }

    var countryCode: String {
        switch self {
        case .portuguese: "BR"
        case .english: "US"
        }
    }

    var nativeName: String {
        switch self {
        case .portuguese: "Português"
        case .english: "English"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }

    func localized(_ key: String) -> String {
        guard self != .portuguese,
              let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return key
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static var selected: AppLanguage {
        let saved = UserDefaults.standard.string(forKey: storageKey) ?? AppLanguage.portuguese.rawValue
        return AppLanguage(rawValue: saved) ?? .portuguese
    }
}

struct LanguageFlagView: View {
    let language: AppLanguage

    var body: some View {
        Group {
            switch language {
            case .portuguese:
                ZStack {
                    Color(red: 0.00, green: 0.61, blue: 0.29)
                    Rectangle()
                        .fill(Color(red: 1.00, green: 0.87, blue: 0.00))
                        .frame(width: 14, height: 14)
                        .rotationEffect(.degrees(45))
                    Circle()
                        .fill(Color(red: 0.00, green: 0.16, blue: 0.49))
                        .frame(width: 8, height: 8)
                }
            case .english:
                GeometryReader { proxy in
                    ZStack(alignment: .topLeading) {
                        VStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { index in
                                (index.isMultiple(of: 2) ? Color.red : Color.white)
                                    .frame(height: proxy.size.height / 7)
                            }
                        }
                        Color(red: 0.05, green: 0.18, blue: 0.43)
                            .frame(width: proxy.size.width * 0.45, height: proxy.size.height * 0.57)
                    }
                }
            }
        }
        .frame(width: 28, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}

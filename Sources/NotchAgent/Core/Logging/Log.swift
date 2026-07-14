import os

/// Central logging categories. Inspect with Console.app or:
/// `log stream --predicate 'subsystem == "br.com.lfrprojects.notchagent"' --level debug`
enum Log {
    static let subsystem = "br.com.lfrprojects.notchagent"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let notch = Logger(subsystem: subsystem, category: "notch")
    static let refresh = Logger(subsystem: subsystem, category: "refresh")
    static let providers = Logger(subsystem: subsystem, category: "providers")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}

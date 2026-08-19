import Foundation

/// Resolves bundled assets across BOTH packaging worlds:
/// - the installed .app (make-app copies Resources into Bundle.main)
/// - a bare `swift run` / `swift test` (SwiftPM puts declared resources
///   into Bundle.module, under the copied directory's path)
///
/// REGRESSÃO: the mascots only ever loaded from Bundle.main, so every
/// `swift run` session silently fell back to procedural placeholders —
/// the "broken mascot" users saw for a whole debugging day.
enum AssetBundle {
    static func url(forResource name: String, withExtension ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        if let url = Bundle.module.url(forResource: name, withExtension: ext) {
            return url
        }
        // SwiftPM .copy("Resources/Mascots") nests the files under the
        // copied directory's own name inside the module bundle.
        if let url = Bundle.module.url(forResource: "Resources/\(name)", withExtension: ext) {
            return url
        }
        return nil
    }
}

import XCTest
@testable import NotchAgent

/// REGRESSÃO: os sprites só carregavam de Bundle.main, então qualquer
/// `swift run` (sem o .app empacotado) caía nos placeholders procedurais
/// — o "mascote quebrado" que os usuários viam. O helper precisa resolver
/// os 5 assets no ambiente SwiftPM (Bundle.module) e no .app instalado.
final class AssetBundleTests: XCTestCase {
    func testEveryMascotSpriteResolves() {
        for name in ["claude-fable", "claude-haiku", "claude-opus", "claude-sonnet", "openai-glyph"] {
            let url = AssetBundle.url(forResource: "Mascots/\(name)", withExtension: "png")
            XCTAssertNotNil(url, "\(name) must resolve from the SwiftPM module bundle")
            guard let url else { continue }
            let image = NSImage(contentsOf: url)
            XCTAssertNotNil(image, "\(name) must decode as an image")
            XCTAssertGreaterThan(image?.size.width ?? 0, 0, "\(name) must have real dimensions")
        }
    }
}

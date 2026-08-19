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

    // REGRESSÃO: o PNG do glyph foi extraído do mockup com LIXO — letras
    // pixeladas no topo e um fragmento solto à direita. O asset deve ser
    // um único nó: exatamente um blob visível (o knot), sem fragmentos.
    func testOpenAIGlyphContainsOnlyTheKnot() {
        guard let url = AssetBundle.url(forResource: "Mascots/openai-glyph", withExtension: "png"),
              let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            XCTFail("glyph must load")
            return
        }
        let width = cg.width
        let height = cg.height
        guard let data = cg.dataProvider?.data, let ptr = CFDataGetBytePtr(data) else {
            XCTFail("glyph pixels must be readable")
            return
        }
        let bytesPerRow = cg.bytesPerRow
        let alphaOffset = cg.bitmapInfo.contains(.byteOrder32Little) ? 3 : 0
        let bytesPerPixel = cg.bitsPerPixel / 8

        func alpha(_ x: Int, _ y: Int) -> Int {
            Int(ptr[y * bytesPerRow + x * bytesPerPixel + alphaOffset])
        }

        // True connected-component count (4-connected flood fill) — the
        // knot's rings have many row-runs; only connectivity proves
        // there is one glyph and no scattered fragments.
        var visited = [Bool](repeating: false, count: width * height)
        var total = 0
        var blobs = 0
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                guard !visited[idx] else { continue }
                visited[idx] = true
                guard alpha(x, y) > 60 else { continue }
                var size = 0
                var stack = [(x, y)]
                while let (cx, cy) = stack.popLast() {
                    size += 1
                    for (nx, ny) in [(cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)] {
                        guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                        let nidx = ny * width + nx
                        guard !visited[nidx] else { continue }
                        visited[nidx] = true
                        if alpha(nx, ny) > 60 { stack.append((nx, ny)) }
                    }
                }
                if size >= 4 {
                    blobs += 1
                    total += size
                }
            }
        }
        XCTAssertGreaterThanOrEqual(total, 300, "the knot must keep its pixel mass")
        XCTAssertEqual(blobs, 1, "glyph must be one connected knot, not scattered fragments")
    }
}

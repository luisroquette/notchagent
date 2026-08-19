import XCTest
@testable import NotchAgent

final class PuppetMotionTests: XCTestCase {
    func testEveryGestureHasAParameterSet() {
        for gesture in MascotGesture.allCases {
            let p = PuppetMotion.parameters(for: gesture)
            XCTAssertGreaterThan(p.scaleY, 0)
            XCTAssertGreaterThanOrEqual(p.duration, 0)
        }
    }

    func testInactiveGesturesAreStill() {
        let none = PuppetMotion.parameters(for: .none)
        let ignored = PuppetMotion.parameters(for: .ignored)
        XCTAssertEqual(none.scaleY, 1)
        XCTAssertEqual(none.rotationDegrees, 0)
        XCTAssertEqual(none.offsetY, 0)
        XCTAssertEqual(ignored.scaleY, 1)
        XCTAssertEqual(ignored.rotationDegrees, 0)
        XCTAssertEqual(ignored.offsetY, 0)
    }

    func testActiveGesturesMove() {
        let hop = PuppetMotion.parameters(for: .hop)
        XCTAssertNotEqual(hop.offsetY, 0)
        let tilt = PuppetMotion.parameters(for: .tilt)
        XCTAssertNotEqual(tilt.rotationDegrees, 0)
        let stretch = PuppetMotion.parameters(for: .stretch)
        XCTAssertNotEqual(stretch.scaleY, 1)
    }

    func testEveryReactiveGestureIsVisible() {
        // REGRESSÃO 19/08: blink (squash 12%) e nod (3pt) eram invisíveis
        // no card de 48pt — o mascote reagia e ninguém via. Toda reação
        // tem que mover acima do limiar de percepção.
        for gesture in MascotGesture.allCases
        where gesture != .none && gesture != .ignored {
            let p = PuppetMotion.parameters(for: gesture)
            let moved = abs(p.offsetY) >= 4
                || abs(p.rotationDegrees) >= 5
                || abs(p.scaleY - 1) >= 0.09
            XCTAssertTrue(moved, "\(gesture.rawValue) is invisible — reaction wasted")
        }
    }
}

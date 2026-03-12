import AppKit
import XCTest
@testable import CodexToolbar

final class StatusMenuContentViewTests: XCTestCase {
    func testDarkScreenshotPaletteUsesLightActionText() throws {
        let palette = StatusMenuPalette.forScreenshotAppearance(.dark)
        let actionTextColor = try XCTUnwrap(palette.actionTextColor.usingColorSpace(.deviceRGB))

        XCTAssertEqual(actionTextColor.redComponent, 0.94, accuracy: 0.01)
        XCTAssertEqual(actionTextColor.greenComponent, 0.95, accuracy: 0.01)
        XCTAssertEqual(actionTextColor.blueComponent, 0.97, accuracy: 0.01)
        XCTAssertEqual(actionTextColor.alphaComponent, 1.0, accuracy: 0.01)
    }

    func testLightScreenshotPaletteUsesDarkActionText() throws {
        let palette = StatusMenuPalette.forScreenshotAppearance(.light)
        let actionTextColor = try XCTUnwrap(palette.actionTextColor.usingColorSpace(.deviceRGB))

        XCTAssertEqual(actionTextColor.redComponent, 0.13, accuracy: 0.01)
        XCTAssertEqual(actionTextColor.greenComponent, 0.13, accuracy: 0.01)
        XCTAssertEqual(actionTextColor.blueComponent, 0.15, accuracy: 0.01)
        XCTAssertEqual(actionTextColor.alphaComponent, 1.0, accuracy: 0.01)
    }
}

import AppKit
import SwiftUI
import XCTest
@testable import CodexToolbar

final class StatusMenuContentViewTests: XCTestCase {
    func testLightScreenshotPaletteUsesSofterRenderedDividerColor() throws {
        let palette = StatusMenuPalette.forAppearance(.light, colorScheme: .light)
        let renderedDividerColor = try XCTUnwrap(palette.renderedDividerColor.usingColorSpace(.deviceRGB))

        XCTAssertEqual(renderedDividerColor.redComponent, 0.88, accuracy: 0.01)
        XCTAssertEqual(renderedDividerColor.greenComponent, 0.89, accuracy: 0.01)
        XCTAssertEqual(renderedDividerColor.blueComponent, 0.92, accuracy: 0.01)
        XCTAssertEqual(renderedDividerColor.alphaComponent, 1.0, accuracy: 0.01)
    }

    func testDarkScreenshotPaletteUsesSofterRenderedDividerColor() throws {
        let palette = StatusMenuPalette.forAppearance(.dark, colorScheme: .dark)
        let renderedDividerColor = try XCTUnwrap(palette.renderedDividerColor.usingColorSpace(.deviceRGB))

        XCTAssertEqual(renderedDividerColor.redComponent, 0.20, accuracy: 0.01)
        XCTAssertEqual(renderedDividerColor.greenComponent, 0.22, accuracy: 0.01)
        XCTAssertEqual(renderedDividerColor.blueComponent, 0.25, accuracy: 0.01)
        XCTAssertEqual(renderedDividerColor.alphaComponent, 1.0, accuracy: 0.01)
    }

    func testDarkScreenshotPaletteUsesLightActionText() throws {
        let palette = StatusMenuPalette.forAppearance(.dark, colorScheme: .light)
        let actionTextColor = try XCTUnwrap(palette.actionTextColor.usingColorSpace(.deviceRGB))

        XCTAssertEqual(actionTextColor.redComponent, 0.94, accuracy: 0.01)
        XCTAssertEqual(actionTextColor.greenComponent, 0.95, accuracy: 0.01)
        XCTAssertEqual(actionTextColor.blueComponent, 0.97, accuracy: 0.01)
        XCTAssertEqual(actionTextColor.alphaComponent, 1.0, accuracy: 0.01)
    }

    func testLightScreenshotPaletteUsesStableNeutralStatusItemGlyphColor() throws {
        let palette = StatusMenuPalette.forAppearance(.light, colorScheme: .light)
        let glyphColor = try XCTUnwrap(palette.statusItemGlyphColor.usingColorSpace(.deviceRGB))
        let warningFillColor = try XCTUnwrap(palette.fillColor(for: .warning).usingColorSpace(.deviceRGB))
        let criticalFillColor = try XCTUnwrap(palette.fillColor(for: .critical).usingColorSpace(.deviceRGB))

        XCTAssertEqual(glyphColor.redComponent, 0.27, accuracy: 0.01)
        XCTAssertEqual(glyphColor.greenComponent, 0.27, accuracy: 0.01)
        XCTAssertEqual(glyphColor.blueComponent, 0.29, accuracy: 0.01)
        XCTAssertEqual(glyphColor.alphaComponent, 1.0, accuracy: 0.01)
        XCTAssertFalse(glyphColor.isEqual(warningFillColor))
        XCTAssertFalse(glyphColor.isEqual(criticalFillColor))
        XCTAssertTrue(palette.fillColor(for: .critical).isEqual(palette.fillColor(for: .exhausted)))
    }

    func testDarkScreenshotPaletteUsesStableNeutralStatusItemGlyphColor() throws {
        let palette = StatusMenuPalette.forAppearance(.dark, colorScheme: .dark)
        let glyphColor = try XCTUnwrap(palette.statusItemGlyphColor.usingColorSpace(.deviceRGB))
        let warningFillColor = try XCTUnwrap(palette.fillColor(for: .warning).usingColorSpace(.deviceRGB))
        let criticalFillColor = try XCTUnwrap(palette.fillColor(for: .critical).usingColorSpace(.deviceRGB))

        XCTAssertEqual(glyphColor.redComponent, 0.86, accuracy: 0.01)
        XCTAssertEqual(glyphColor.greenComponent, 0.89, accuracy: 0.01)
        XCTAssertEqual(glyphColor.blueComponent, 0.93, accuracy: 0.01)
        XCTAssertEqual(glyphColor.alphaComponent, 1.0, accuracy: 0.01)
        XCTAssertFalse(glyphColor.isEqual(warningFillColor))
        XCTAssertFalse(glyphColor.isEqual(criticalFillColor))
        XCTAssertTrue(palette.fillColor(for: .critical).isEqual(palette.fillColor(for: .exhausted)))
    }

    func testLightScreenshotPaletteUsesDarkActionText() throws {
        let palette = StatusMenuPalette.forAppearance(.light, colorScheme: .dark)
        let actionTextColor = try XCTUnwrap(palette.actionTextColor.usingColorSpace(.deviceRGB))

        XCTAssertEqual(actionTextColor.redComponent, 0.13, accuracy: 0.01)
        XCTAssertEqual(actionTextColor.greenComponent, 0.13, accuracy: 0.01)
        XCTAssertEqual(actionTextColor.blueComponent, 0.15, accuracy: 0.01)
        XCTAssertEqual(actionTextColor.alphaComponent, 1.0, accuracy: 0.01)
    }

    func testLiveLightPaletteUsesStableNeutralActionHighlight() throws {
        let palette = StatusMenuPalette.forAppearance(nil, colorScheme: .light)
        let actionHighlightColor = try XCTUnwrap(palette.actionHighlightColor.usingColorSpace(.deviceRGB))

        XCTAssertEqual(actionHighlightColor.redComponent, 0.0, accuracy: 0.01)
        XCTAssertEqual(actionHighlightColor.greenComponent, 0.0, accuracy: 0.01)
        XCTAssertEqual(actionHighlightColor.blueComponent, 0.0, accuracy: 0.01)
        XCTAssertEqual(actionHighlightColor.alphaComponent, 0.12, accuracy: 0.01)
    }

    func testLiveLightPaletteUsesStableNeutralDividerColor() throws {
        let palette = StatusMenuPalette.forAppearance(nil, colorScheme: .light)
        let dividerColor = try XCTUnwrap(palette.renderedDividerColor.usingColorSpace(.deviceRGB))

        XCTAssertEqual(dividerColor.redComponent, 0.86, accuracy: 0.01)
        XCTAssertEqual(dividerColor.greenComponent, 0.86, accuracy: 0.01)
        XCTAssertEqual(dividerColor.blueComponent, 0.86, accuracy: 0.01)
        XCTAssertEqual(dividerColor.alphaComponent, 1.0, accuracy: 0.01)
    }

    func testLiveDarkPaletteUsesStableNeutralActionHighlight() throws {
        let palette = StatusMenuPalette.forAppearance(nil, colorScheme: .dark)
        let actionHighlightColor = try XCTUnwrap(palette.actionHighlightColor.usingColorSpace(.deviceRGB))

        XCTAssertEqual(actionHighlightColor.redComponent, 1.0, accuracy: 0.01)
        XCTAssertEqual(actionHighlightColor.greenComponent, 1.0, accuracy: 0.01)
        XCTAssertEqual(actionHighlightColor.blueComponent, 1.0, accuracy: 0.01)
        XCTAssertEqual(actionHighlightColor.alphaComponent, 0.12, accuracy: 0.01)
    }

    func testLiveDarkPaletteUsesStableNeutralDividerColor() throws {
        let palette = StatusMenuPalette.forAppearance(nil, colorScheme: .dark)
        let dividerColor = try XCTUnwrap(palette.renderedDividerColor.usingColorSpace(.deviceRGB))

        XCTAssertEqual(dividerColor.redComponent, 0.20, accuracy: 0.01)
        XCTAssertEqual(dividerColor.greenComponent, 0.20, accuracy: 0.01)
        XCTAssertEqual(dividerColor.blueComponent, 0.20, accuracy: 0.01)
        XCTAssertEqual(dividerColor.alphaComponent, 1.0, accuracy: 0.01)
    }
}

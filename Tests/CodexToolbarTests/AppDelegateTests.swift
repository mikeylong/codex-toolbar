import AppKit
import XCTest
@testable import CodexToolbar

@MainActor
final class AppDelegateTests: XCTestCase {
    func testContextMenuIncludesDisabledVersionItemAboveQuit() {
        let delegate = AppDelegate()

        let menu = delegate.makeContextMenu()

        XCTAssertEqual(menu.items.count, 5)
        XCTAssertEqual(menu.items[0].title, "Refresh now")
        XCTAssertTrue(
            menu.items[1].title == "Launch at login" ||
            menu.items[1].title == "Disable launch at login"
        )
        XCTAssertTrue(menu.items[2].isSeparatorItem)
        XCTAssertEqual(menu.items[3].title, "Version \(AppVersion.current)")
        XCTAssertFalse(menu.items[3].isEnabled)
        XCTAssertEqual(menu.items[4].title, "Quit")
    }
}

import XCTest
@testable import CodexToolbar

@MainActor
final class ToolbarPreferencesTests: XCTestCase {
    func testCreditsVisibilityDefaultsToHidden() {
        let defaults = Self.makeDefaults()
        let preferences = ToolbarPreferences(defaults: defaults)

        XCTAssertFalse(preferences.isCreditsVisible)
    }

    func testCreditsVisibilitySetRoundTrips() {
        let defaults = Self.makeDefaults()
        let preferences = ToolbarPreferences(defaults: defaults)

        preferences.setCreditsVisible(true)
        XCTAssertTrue(preferences.isCreditsVisible)

        preferences.setCreditsVisible(false)
        XCTAssertFalse(preferences.isCreditsVisible)
    }

    func testCreditsVisibilityToggleFlipsStoredValue() {
        let defaults = Self.makeDefaults()
        let preferences = ToolbarPreferences(defaults: defaults)

        preferences.toggleCreditsVisibility()
        XCTAssertTrue(preferences.isCreditsVisible)

        preferences.toggleCreditsVisibility()
        XCTAssertFalse(preferences.isCreditsVisible)
    }

    func testGitUpdateRepositoryConfigurationRoundTrips() {
        let defaults = Self.makeDefaults()
        let preferences = ToolbarPreferences(defaults: defaults)
        let configuration = GitUpdateRepositoryConfiguration(
            repositoryRoot: "/tmp/codextoolbar",
            remoteName: "origin",
            branchName: "main"
        )

        preferences.setGitUpdateRepositoryConfiguration(configuration)

        XCTAssertEqual(preferences.gitUpdateRepositoryConfiguration(), configuration)
    }

    func testGitUpdateRepositoryConfigurationReturnsNilWhenIncomplete() {
        let defaults = Self.makeDefaults()
        defaults.set("/tmp/codextoolbar", forKey: "gitUpdate.repositoryRoot")
        defaults.set("origin", forKey: "gitUpdate.remoteName")
        let preferences = ToolbarPreferences(defaults: defaults)

        XCTAssertNil(preferences.gitUpdateRepositoryConfiguration())
    }

    func testGitUpdateRepositoryConfigurationClearsAllKeys() {
        let defaults = Self.makeDefaults()
        let preferences = ToolbarPreferences(defaults: defaults)
        preferences.setGitUpdateRepositoryConfiguration(
            GitUpdateRepositoryConfiguration(
                repositoryRoot: "/tmp/codextoolbar",
                remoteName: "origin",
                branchName: "main"
            )
        )

        preferences.setGitUpdateRepositoryConfiguration(nil)

        XCTAssertNil(preferences.gitUpdateRepositoryConfiguration())
        XCTAssertNil(defaults.object(forKey: "gitUpdate.repositoryRoot"))
        XCTAssertNil(defaults.object(forKey: "gitUpdate.remoteName"))
        XCTAssertNil(defaults.object(forKey: "gitUpdate.branchName"))
    }

    private static func makeDefaults() -> UserDefaults {
        let suiteName = "ToolbarPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

import AppKit
import XCTest
@testable import CodexToolbar

@MainActor
final class AppDelegateTests: XCTestCase {
    func testCodexContextMenuShowsOpenCodexWhenInstalledAppExists() {
        let delegate = makeDelegate(
            installedApplicationURL: URL(fileURLWithPath: "/Applications/Codex.app"),
            preferences: ToolbarPreferences(defaults: Self.makeDefaults())
        )

        XCTAssertTrue(delegate.makeContextMenu(provider: .codex).items.contains { $0.title == "Open Codex" })
        XCTAssertFalse(delegate.makeContextMenu(provider: .claude).items.contains { $0.title == "Open Codex" })
    }

    func testContextMenuHidesOpenCodexWhenInstalledAppIsMissing() {
        let delegate = makeDelegate(
            installedApplicationURL: nil,
            preferences: ToolbarPreferences(defaults: Self.makeDefaults())
        )

        XCTAssertFalse(delegate.makeContextMenu().items.contains { $0.title == "Open Codex" })
    }

    func testOpenCodexMenuActionOpensAppAndClosesPopover() async throws {
        let fakeProvider = FakeCodexDesktopAppProvider(installedApplicationURL: URL(fileURLWithPath: "/Applications/Codex.app"))
        let delegate = makeDelegate(
            store: makeNormalStore(),
            codexDesktopAppProvider: fakeProvider,
            preferences: ToolbarPreferences(defaults: Self.makeDefaults())
        )
        let closeExpectation = expectation(description: "popover closed")
        delegate.popoverCloseHandler = {
            closeExpectation.fulfill()
        }

        let menu = delegate.makeContextMenu()
        let item = try XCTUnwrap(menu.items.first { $0.title == "Open Codex" })
        let target = try XCTUnwrap(item.target as? NSObject)
        let action = try XCTUnwrap(item.action)
        target.perform(action)

        await fulfillment(of: [closeExpectation], timeout: 1)
        XCTAssertEqual(fakeProvider.openCallCount, 1)
    }

    func testUsageDestinationsRemainAvailableWithoutInstalledApp() {
        let delegate = makeDelegate(
            installedApplicationURL: nil,
            preferences: ToolbarPreferences(defaults: Self.makeDefaults())
        )
        XCTAssertEqual(delegate.makeStatusMenuContentView(provider: .codex).provider.usageURL.absoluteString,
                       "https://chatgpt.com/settings/usage")
        XCTAssertEqual(delegate.makeStatusMenuContentView(provider: .claude).provider.usageURL.absoluteString,
                       "https://claude.ai/settings/usage")
    }

    func testFirstLaunchAsksForProvidersOnceAndPersistsBoth() {
        let preferences = ToolbarPreferences(defaults: Self.makeDefaults())
        let runtime = FakeAppRuntimeController()
        runtime.providerChoice = .both
        let delegate = makeDelegate(installedApplicationURL: nil, preferences: preferences, appRuntime: runtime)

        XCTAssertTrue(delegate.configureProviderSelectionIfNeeded())
        XCTAssertEqual(preferences.usageProviderSelection, .both)
        XCTAssertEqual(delegate.enabledProviders, [.codex, .claude])
        XCTAssertEqual(runtime.providerChoiceCallCount, 1)
        XCTAssertNil(runtime.previousProviderChoices[0])
        XCTAssertTrue(delegate.configureProviderSelectionIfNeeded())
        XCTAssertEqual(runtime.providerChoiceCallCount, 1)

        let nextLaunch = makeDelegate(installedApplicationURL: nil, preferences: preferences, appRuntime: runtime)
        XCTAssertTrue(nextLaunch.configureProviderSelectionIfNeeded())
        XCTAssertEqual(runtime.providerChoiceCallCount, 1)
        XCTAssertEqual(nextLaunch.enabledProviders, [.codex, .claude])
    }

    func testCancellingFirstLaunchDoesNotPersistASelection() {
        let preferences = ToolbarPreferences(defaults: Self.makeDefaults())
        let runtime = FakeAppRuntimeController()
        let delegate = makeDelegate(installedApplicationURL: nil, preferences: preferences, appRuntime: runtime)

        XCTAssertFalse(delegate.configureProviderSelectionIfNeeded())
        XCTAssertNil(preferences.usageProviderSelection)
        XCTAssertEqual(runtime.providerChoiceCallCount, 1)
    }

    func testExistingClaudeSelectionBypassesFirstLaunchPrompt() {
        let preferences = ToolbarPreferences(defaults: Self.makeDefaults())
        preferences.setUsageProviderSelection(.claude)
        let runtime = FakeAppRuntimeController()
        runtime.providerChoice = .codex
        let delegate = makeDelegate(installedApplicationURL: nil, preferences: preferences, appRuntime: runtime)

        XCTAssertTrue(delegate.configureProviderSelectionIfNeeded())
        XCTAssertEqual(delegate.enabledProviders, [.claude])
        XCTAssertEqual(preferences.usageProviderSelection, .claude)
        XCTAssertEqual(runtime.providerChoiceCallCount, 0)
    }

    func testScreenshotsSelectTheirProviderWithoutPromptingOrPersistingSelection() {
        for (scenario, provider) in [(ScreenshotScenario.normal, UsageProvider.codex), (.claude, .claude)] {
            let preferences = ToolbarPreferences(defaults: Self.makeDefaults())
            let runtime = FakeAppRuntimeController()
            runtime.providerChoice = .both
            let configuration = ScreenshotLaunchConfiguration(
                scenario: scenario, appearance: .light, outputDirectory: nil,
                shouldCapturePopover: true, shouldCaptureStatusItem: false, shouldOpenPopover: true,
                visibleSupplementalFamilyIDs: nil
            )
            let delegate = makeDelegate(installedApplicationURL: nil, preferences: preferences,
                                        screenshotConfiguration: configuration, appRuntime: runtime)

            XCTAssertTrue(delegate.configureProviderSelectionIfNeeded())
            XCTAssertEqual(runtime.providerChoiceCallCount, 0)
            XCTAssertNil(preferences.usageProviderSelection)
            XCTAssertEqual(delegate.enabledProviders, [provider])
        }
    }

    func testStartupDiagnosticsUsesCodexWithoutChangingSavedClaudeSelection() {
        let preferences = ToolbarPreferences(defaults: Self.makeDefaults())
        preferences.setUsageProviderSelection(.claude)
        let runtime = FakeAppRuntimeController()
        runtime.providerChoice = .both
        let diagnostics = StartupDiagnosticsConfiguration(
            outputPath: FileManager.default.temporaryDirectory.appendingPathComponent("codextoolbar-test-diagnostics.json").path,
            terminateAfterFirstReport: true
        )
        let delegate = makeDelegate(installedApplicationURL: nil, preferences: preferences,
                                    startupDiagnosticsConfiguration: diagnostics, appRuntime: runtime)

        XCTAssertTrue(delegate.configureProviderSelectionIfNeeded())
        XCTAssertEqual(delegate.enabledProviders, [.codex])
        XCTAssertEqual(runtime.providerChoiceCallCount, 0)
        XCTAssertEqual(preferences.usageProviderSelection, .claude)
    }

    func testSwitchingToBothStartsClaudeWhileEarlierCodexStartIsStillPending() async {
        let preferences = ToolbarPreferences(defaults: Self.makeDefaults())
        preferences.setUsageProviderSelection(.codex)
        let snapshotGate = DelegateSnapshotGate()
        let codexClient = FakeStatusItemRateLimitClient(snapshotGate: snapshotGate)
        let codexStore = RateLimitStore(client: codexClient, refreshDelayNanosecondsProvider: { 3_600_000_000_000 })
        let claudeClient = DelegateClaudeUsageClient()
        let claudeStore = ClaudeUsageStore(client: claudeClient)
        let delegate = makeDelegate(
            store: codexStore, claudeUsageStore: claudeStore,
            codexDesktopAppProvider: FakeCodexDesktopAppProvider(installedApplicationURL: nil), preferences: preferences
        )
        delegate.synchronizeProviderLifecycle()
        for _ in 0..<100 {
            if await snapshotGate.isWaiting { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        let codexStarted = await snapshotGate.isWaiting
        XCTAssertTrue(codexStarted)

        preferences.setUsageProviderSelection(.both)
        delegate.synchronizeProviderLifecycle()
        for _ in 0..<100 {
            if await claudeClient.callCount > 0 { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        let claudeReads = await claudeClient.callCount
        let codexStillPending = await snapshotGate.isWaiting
        XCTAssertEqual(claudeReads, 1, "Claude startup must not wait for the earlier Codex lifecycle task")
        XCTAssertTrue(codexStillPending)

        // Let every pending lifecycle operation unwind without leaving timers or
        // a suspended snapshot behind, even if either assertion above fails.
        preferences.setUsageProviderSelection(.claude)
        await snapshotGate.release()
        await codexStore.stop()
        await claudeStore.stop()
    }

    func testBothProvidersHaveSeparatePopoverContent() {
        let preferences = ToolbarPreferences(defaults: Self.makeDefaults())
        preferences.setUsageProviderSelection(.both)
        let claudeStore = ClaudeUsageStore(client: DelegateClaudeUsageClient())
        let delegate = makeDelegate(installedApplicationURL: nil, preferences: preferences, claudeUsageStore: claudeStore)

        let codexView = delegate.makeStatusMenuContentView(provider: .codex)
        let claudeView = delegate.makeStatusMenuContentView(provider: .claude)
        XCTAssertEqual(delegate.enabledProviders, [.codex, .claude])
        XCTAssertTrue(codexView.displaysCodexContent)
        XCTAssertFalse(codexView.displaysClaudeContent)
        XCTAssertNil(codexView.claudeUsageStore)
        XCTAssertFalse(claudeView.displaysCodexContent)
        XCTAssertTrue(claudeView.displaysClaudeContent)
        XCTAssertTrue(claudeView.claudeUsageStore === claudeStore)
        XCTAssertEqual(codexView.panelTitle, "Codex usage")
        XCTAssertEqual(claudeView.panelTitle, "Claude usage")
    }

    func testClaudeOnlyPopoverExcludesCodexActionsCreditsAndAPIUsage() {
        let preferences = ToolbarPreferences(defaults: Self.makeDefaults())
        preferences.setUsageProviderSelection(.claude)
        preferences.setCreditsVisible(true)
        preferences.setOpenAIUsageVisible(true)
        let delegate = makeDelegate(installedApplicationURL: URL(fileURLWithPath: "/Applications/Codex.app"),
                                    preferences: preferences)

        let view = delegate.makeStatusMenuContentView(provider: .claude)
        XCTAssertEqual(delegate.enabledProviders, [.claude])
        XCTAssertFalse(view.displaysCodexContent)
        XCTAssertTrue(view.displaysClaudeContent)
        XCTAssertFalse(view.showsCredits)
        XCTAssertFalse(view.showsOpenAIUsage)
        let size = delegate.popoverContentSize(for: .claude)
        XCTAssertEqual(size.width, 352)
        XCTAssertGreaterThan(size.height, 0)
        XCTAssertLessThanOrEqual(size.height, StatusMenuContentView.maximumPopoverHeight)
    }

    func testClaudeContextMenuExcludesCodexSettingsAndCarriesProviderForRefresh() throws {
        let preferences = ToolbarPreferences(defaults: Self.makeDefaults())
        preferences.setUsageProviderSelection(.both)
        let delegate = makeDelegate(installedApplicationURL: nil, preferences: preferences)
        let claudeMenu = delegate.makeContextMenu(provider: .claude)
        let titles = claudeMenu.items.map(\.title)
        XCTAssertTrue(titles.contains("Choose providers…"))
        XCTAssertFalse(titles.contains("Show Claude usage"))
        for excluded in ["Show credits", "Show API usage", "Show GPT-5.3-Codex-Spark",
                         "Configure OpenAI admin key…", "Remove OpenAI admin key"] {
            XCTAssertFalse(titles.contains(excluded))
        }
        XCTAssertEqual(try XCTUnwrap(claudeMenu.items.first { $0.title == "Refresh now" }).representedObject as? String, "claude")
        let codexMenu = delegate.makeContextMenu(provider: .codex)
        XCTAssertEqual(try XCTUnwrap(codexMenu.items.first { $0.title == "Refresh now" }).representedObject as? String, "codex")
    }

    func testCancellingProviderChooserKeepsExistingSelection() throws {
        let preferences = ToolbarPreferences(defaults: Self.makeDefaults())
        preferences.setUsageProviderSelection(.both)
        let runtime = FakeAppRuntimeController()
        let delegate = makeDelegate(installedApplicationURL: nil, preferences: preferences, appRuntime: runtime)
        let item = try XCTUnwrap(delegate.makeContextMenu(provider: .claude).items.first { $0.title == "Choose providers…" })
        let target = try XCTUnwrap(item.target as? NSObject)

        target.perform(try XCTUnwrap(item.action))

        XCTAssertEqual(runtime.providerChoiceCallCount, 1)
        XCTAssertEqual(runtime.previousProviderChoices, [.both])
        XCTAssertEqual(preferences.usageProviderSelection, .both)
        XCTAssertEqual(delegate.enabledProviders, [.codex, .claude])
    }

    func testManualRefreshIsIndependentForEachProvider() async {
        let preferences = ToolbarPreferences(defaults: Self.makeDefaults())
        preferences.setUsageProviderSelection(.both)
        preferences.setOpenAIUsageVisible(true)
        let claudeClient = DelegateClaudeUsageClient()
        let codexClient = FakeStatusItemRateLimitClient()
        let apiClient = FakeOpenAIUsageClient()
        let delegate = makeDelegate(
            store: RateLimitStore(client: codexClient, liveUpdatesEnabled: false),
            openAIUsageStore: makeOpenAIUsageStore(isEnabled: true, adminKey: "test-key", client: apiClient),
            claudeUsageStore: ClaudeUsageStore(client: claudeClient),
            codexDesktopAppProvider: FakeCodexDesktopAppProvider(installedApplicationURL: nil), preferences: preferences
        )

        await delegate.refreshUsage(for: .codex)
        let claudeCountAfterCodex = await claudeClient.callCount
        XCTAssertEqual(claudeCountAfterCodex, 0)
        XCTAssertEqual(codexClient.loadSnapshotCallCount, 1)
        XCTAssertEqual(apiClient.costsCallCount, 1)

        await delegate.refreshUsage(for: .claude)
        let claudeCountAfterClaude = await claudeClient.callCount
        XCTAssertEqual(claudeCountAfterClaude, 1)
        XCTAssertEqual(codexClient.loadSnapshotCallCount, 1)
        XCTAssertEqual(apiClient.costsCallCount, 1)
    }

    func testClaudeRefreshMenuActionDispatchesToClaudeInsteadOfCodex() async throws {
        let preferences = ToolbarPreferences(defaults: Self.makeDefaults())
        preferences.setUsageProviderSelection(.both)
        let claudeClient = DelegateClaudeUsageClient()
        let codexClient = FakeStatusItemRateLimitClient()
        let delegate = makeDelegate(
            store: RateLimitStore(client: codexClient, liveUpdatesEnabled: false),
            claudeUsageStore: ClaudeUsageStore(client: claudeClient),
            codexDesktopAppProvider: FakeCodexDesktopAppProvider(installedApplicationURL: nil), preferences: preferences
        )
        let item = try XCTUnwrap(delegate.makeContextMenu(provider: .claude).items.first { $0.title == "Refresh now" })
        let target = try XCTUnwrap(item.target as? NSObject)
        target.perform(try XCTUnwrap(item.action), with: item)
        try await Task.sleep(nanoseconds: 50_000_000)

        let claudeCount = await claudeClient.callCount
        XCTAssertEqual(claudeCount, 1)
        XCTAssertEqual(codexClient.loadSnapshotCallCount, 0)
    }

    func testManualRefreshDoesNotRunDisabledProvider() async {
        let preferences = ToolbarPreferences(defaults: Self.makeDefaults())
        preferences.setUsageProviderSelection(.claude)
        let codexClient = FakeStatusItemRateLimitClient()
        let delegate = makeDelegate(
            store: RateLimitStore(client: codexClient, liveUpdatesEnabled: false),
            codexDesktopAppProvider: FakeCodexDesktopAppProvider(installedApplicationURL: nil), preferences: preferences
        )
        await delegate.refreshUsage(for: .codex)
        XCTAssertEqual(codexClient.loadSnapshotCallCount, 0)
    }

    func testContextMenuIncludesSupplementalFamilyToggleAndDisabledVersionItemAboveQuit() {
        let delegate = makeDelegate(
            installedApplicationURL: nil,
            preferences: ToolbarPreferences(defaults: Self.makeDefaults())
        )

        let menu = delegate.makeContextMenu()

        XCTAssertEqual(menu.items.count, 12)
        XCTAssertEqual(menu.items[0].title, "Refresh now")
        XCTAssertTrue(
            menu.items[1].title == "Launch at login" ||
            menu.items[1].title == "Disable launch at login"
        )
        XCTAssertEqual(menu.items[2].title, "Show GPT-5.3-Codex-Spark")
        XCTAssertEqual(menu.items[2].state, NSControl.StateValue.off)
        XCTAssertEqual(menu.items[3].title, "Show credits")
        XCTAssertEqual(menu.items[3].state, NSControl.StateValue.off)
        XCTAssertEqual(menu.items[4].title, "Show API usage")
        XCTAssertEqual(menu.items[4].state, NSControl.StateValue.off)
        XCTAssertEqual(menu.items[5].title, "Choose providers…")
        XCTAssertTrue(menu.items[6].isSeparatorItem)
        XCTAssertEqual(menu.items[7].title, "Configure OpenAI admin key…")
        XCTAssertEqual(menu.items[8].title, "Remove OpenAI admin key")
        XCTAssertFalse(menu.items[8].isEnabled)
        XCTAssertTrue(menu.items[9].isSeparatorItem)
        XCTAssertEqual(menu.items[10].title, "Version \(AppVersion.current)")
        XCTAssertFalse(menu.items[10].isEnabled)
        XCTAssertEqual(menu.items[11].title, "Quit")
    }

    func testContextMenuShowsUpdateItemsAboveVersionWhenUpdateIsAvailable() {
        let preferences = ToolbarPreferences(defaults: Self.makeDefaults())
        let gitUpdateController = makeGitUpdateController(
            preferences: preferences,
            state: .updateAvailable("v0.1.4", .installFromGitCheckout)
        )
        let delegate = makeDelegate(
            store: makeNormalStore(),
            codexDesktopAppProvider: FakeCodexDesktopAppProvider(installedApplicationURL: nil),
            preferences: preferences,
            gitUpdateController: gitUpdateController
        )

        let menu = delegate.makeContextMenu()

        XCTAssertEqual(menu.items.count, 14)
        XCTAssertEqual(menu.items[10].title, "Update available: v0.1.4")
        XCTAssertFalse(menu.items[10].isEnabled)
        XCTAssertEqual(menu.items[11].title, "Install update")
        XCTAssertTrue(menu.items[11].isEnabled)
        XCTAssertEqual(menu.items[12].title, "Version \(AppVersion.current)")
        XCTAssertEqual(menu.items[13].title, "Quit")
    }

    func testContextMenuShowsDownloadUpdateForReleaseBasedInstall() {
        let preferences = ToolbarPreferences(defaults: Self.makeDefaults())
        let gitUpdateController = makeGitUpdateController(
            preferences: preferences,
            state: .updateAvailable(
                "v0.1.4",
                .downloadRelease(URL(string: "https://github.com/mikeylong/codex-toolbar/releases/latest")!)
            )
        )
        let delegate = makeDelegate(
            store: makeNormalStore(),
            codexDesktopAppProvider: FakeCodexDesktopAppProvider(installedApplicationURL: nil),
            preferences: preferences,
            gitUpdateController: gitUpdateController
        )

        let menu = delegate.makeContextMenu()

        XCTAssertEqual(menu.items[10].title, "Update available: v0.1.4")
        XCTAssertEqual(menu.items[11].title, "Download update")
    }

    func testContextMenuSupplementalFamilyToggleReflectsEnabledPreference() {
        let defaults = Self.makeDefaults()
        defaults.set(true, forKey: "visibleSupplementalFamily.codex_bengalfox")
        let delegate = makeDelegate(
            installedApplicationURL: nil,
            preferences: ToolbarPreferences(defaults: defaults)
        )

        let menu = delegate.makeContextMenu()

        XCTAssertEqual(menu.items[2].state, NSControl.StateValue.on)
    }

    func testContextMenuCreditsToggleReflectsEnabledPreference() {
        let defaults = Self.makeDefaults()
        defaults.set(true, forKey: "showCredits")
        let delegate = makeDelegate(
            installedApplicationURL: nil,
            preferences: ToolbarPreferences(defaults: defaults)
        )

        let menu = delegate.makeContextMenu()

        XCTAssertEqual(menu.items[3].title, "Show credits")
        XCTAssertEqual(menu.items[3].state, NSControl.StateValue.on)
    }

    func testContextMenuOpenAIUsageToggleReflectsEnabledPreference() {
        let defaults = Self.makeDefaults()
        defaults.set(true, forKey: "showOpenAIUsage")
        let delegate = makeDelegate(
            installedApplicationURL: nil,
            preferences: ToolbarPreferences(defaults: defaults)
        )

        let menu = delegate.makeContextMenu()

        XCTAssertEqual(menu.items[4].title, "Show API usage")
        XCTAssertEqual(menu.items[4].state, NSControl.StateValue.on)
    }

    func testContextMenuCreditsToggleFlipsPreference() throws {
        let defaults = Self.makeDefaults()
        let preferences = ToolbarPreferences(defaults: defaults)
        let delegate = makeDelegate(
            installedApplicationURL: nil,
            preferences: preferences
        )
        let menu = delegate.makeContextMenu()
        let showCreditsItem = try XCTUnwrap(menu.items.first { $0.title == "Show credits" })
        let target = try XCTUnwrap(showCreditsItem.target as? NSObject)

        XCTAssertFalse(preferences.isCreditsVisible)

        target.perform(try XCTUnwrap(showCreditsItem.action))

        XCTAssertTrue(preferences.isCreditsVisible)
    }

    func testContextMenuOpenAIUsageToggleFlipsPreferenceAndStartsStore() async throws {
        let defaults = Self.makeDefaults()
        let preferences = ToolbarPreferences(defaults: defaults)
        let client = FakeOpenAIUsageClient()
        client.costBuckets = [
            try XCTUnwrap(makeOpenAICostBucket(amount: "1.50"))
        ]
        client.usageBuckets = [
            try XCTUnwrap(makeOpenAIUsageBucket(requests: 4, input: 80, output: 20))
        ]
        let usageStore = makeOpenAIUsageStore(
            isEnabled: true,
            adminKey: "sk-admin-123",
            client: client
        )
        let delegate = makeDelegate(
            installedApplicationURL: nil,
            preferences: preferences,
            openAIUsageStore: usageStore
        )
        let menu = delegate.makeContextMenu()
        let showOpenAIUsageItem = try XCTUnwrap(menu.items.first { $0.title == "Show API usage" })
        let target = try XCTUnwrap(showOpenAIUsageItem.target as? NSObject)

        XCTAssertFalse(preferences.isOpenAIUsageVisible)

        target.perform(try XCTUnwrap(showOpenAIUsageItem.action))
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(preferences.isOpenAIUsageVisible)
        XCTAssertEqual(client.costsCallCount, 1)
        XCTAssertEqual(client.usageCallCount, 1)
    }

    func testContextMenuIncludesOpenAIUsageActionsByDefault() {
        let delegate = makeDelegate(
            installedApplicationURL: nil,
            preferences: ToolbarPreferences(defaults: Self.makeDefaults())
        )

        let menu = delegate.makeContextMenu()

        XCTAssertEqual(menu.items.count, 12)
        XCTAssertTrue(menu.items[6].isSeparatorItem)
        XCTAssertEqual(menu.items[7].title, "Configure OpenAI admin key…")
        XCTAssertEqual(menu.items[8].title, "Remove OpenAI admin key")
        XCTAssertFalse(menu.items[8].isEnabled)
        XCTAssertTrue(menu.items[9].isSeparatorItem)
    }

    func testContextMenuOpenAIUsageActionsEnableWhenAdminKeyExists() {
        let preferences = ToolbarPreferences(defaults: Self.makeDefaults())
        let delegate = makeDelegate(
            installedApplicationURL: nil,
            preferences: preferences,
            openAIUsageStore: makeOpenAIUsageStore(isEnabled: true, adminKey: "sk-admin-123")
        )

        let menu = delegate.makeContextMenu()

        XCTAssertTrue(menu.items[8].isEnabled)
    }

    func testRefreshNowSkipsOpenAIUsageWhenAPIUsageIsHidden() async throws {
        let preferences = ToolbarPreferences(defaults: Self.makeDefaults())
        let rateLimitClient = FakeStatusItemRateLimitClient()
        let rateLimitStore = RateLimitStore(
            client: rateLimitClient,
            refreshDelayNanosecondsProvider: { 1_000_000_000 },
            liveUpdatesEnabled: false
        )
        let openAIClient = FakeOpenAIUsageClient()
        openAIClient.costBuckets = [
            try XCTUnwrap(makeOpenAICostBucket(amount: "1.50"))
        ]
        openAIClient.usageBuckets = [
            try XCTUnwrap(makeOpenAIUsageBucket(requests: 4, input: 80, output: 20))
        ]
        let openAIUsageStore = makeOpenAIUsageStore(
            isEnabled: true,
            adminKey: "sk-admin-123",
            client: openAIClient
        )
        let gitUpdateTooling = CountingGitUpdateTooling(latestReleaseTag: "v0.1.10")
        let gitUpdateController = makeGitUpdateController(
            preferences: preferences,
            tooling: gitUpdateTooling,
            currentVersionProvider: { "0.1.9" }
        )
        let delegate = makeDelegate(
            store: rateLimitStore,
            openAIUsageStore: openAIUsageStore,
            codexDesktopAppProvider: FakeCodexDesktopAppProvider(installedApplicationURL: nil),
            preferences: preferences,
            gitUpdateController: gitUpdateController
        )
        let menu = delegate.makeContextMenu()
        let refreshItem = try XCTUnwrap(menu.items.first { $0.title == "Refresh now" })
        let target = try XCTUnwrap(refreshItem.target as? NSObject)

        target.perform(try XCTUnwrap(refreshItem.action), with: refreshItem)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(rateLimitClient.loadSnapshotCallCount, 1)
        XCTAssertEqual(openAIClient.costsCallCount, 0)
        XCTAssertEqual(openAIClient.usageCallCount, 0)
        XCTAssertEqual(gitUpdateController.menuState, .updateAvailable(
            "v0.1.10",
            .downloadRelease(URL(string: "https://github.com/mikeylong/codex-toolbar/releases/latest")!)
        ))
    }

    func testRefreshNowRefreshesAllSubsystemsTogetherWhenAPIUsageIsVisible() async throws {
        let defaults = Self.makeDefaults()
        defaults.set(true, forKey: "showOpenAIUsage")
        let preferences = ToolbarPreferences(defaults: defaults)
        let rateLimitClient = FakeStatusItemRateLimitClient()
        let rateLimitStore = RateLimitStore(
            client: rateLimitClient,
            refreshDelayNanosecondsProvider: { 1_000_000_000 },
            liveUpdatesEnabled: false
        )
        let openAIClient = FakeOpenAIUsageClient()
        openAIClient.costBuckets = [
            try XCTUnwrap(makeOpenAICostBucket(amount: "1.50"))
        ]
        openAIClient.usageBuckets = [
            try XCTUnwrap(makeOpenAIUsageBucket(requests: 4, input: 80, output: 20))
        ]
        let openAIUsageStore = makeOpenAIUsageStore(
            isEnabled: true,
            adminKey: "sk-admin-123",
            client: openAIClient
        )
        let gitUpdateTooling = CountingGitUpdateTooling(latestReleaseTag: "v0.1.10")
        let gitUpdateController = makeGitUpdateController(
            preferences: preferences,
            tooling: gitUpdateTooling,
            currentVersionProvider: { "0.1.9" }
        )
        let delegate = makeDelegate(
            store: rateLimitStore,
            openAIUsageStore: openAIUsageStore,
            codexDesktopAppProvider: FakeCodexDesktopAppProvider(installedApplicationURL: nil),
            preferences: preferences,
            gitUpdateController: gitUpdateController
        )
        let menu = delegate.makeContextMenu()
        let refreshItem = try XCTUnwrap(menu.items.first { $0.title == "Refresh now" })
        let target = try XCTUnwrap(refreshItem.target as? NSObject)

        target.perform(try XCTUnwrap(refreshItem.action), with: refreshItem)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(rateLimitClient.loadSnapshotCallCount, 1)
        XCTAssertEqual(openAIClient.costsCallCount, 1)
        XCTAssertEqual(openAIClient.usageCallCount, 1)
        XCTAssertEqual(gitUpdateController.menuState, .updateAvailable(
            "v0.1.10",
            .downloadRelease(URL(string: "https://github.com/mikeylong/codex-toolbar/releases/latest")!)
        ))
    }

    func testConfigureOpenAIAdminKeyActionStoresKeyAndRefreshesUsageStore() async throws {
        let runtime = FakeAppRuntimeController()
        runtime.promptedSecret = "sk-admin-123"
        let client = FakeOpenAIUsageClient()
        let usageStore = makeOpenAIUsageStore(
            isEnabled: true,
            adminKey: nil,
            client: client
        )
        let delegate = makeDelegate(
            installedApplicationURL: nil,
            preferences: ToolbarPreferences(defaults: Self.makeDefaults()),
            openAIUsageStore: usageStore,
            appRuntime: runtime
        )
        let menu = delegate.makeContextMenu()
        let item = try XCTUnwrap(menu.items.first { $0.title == "Configure OpenAI admin key…" })
        let target = try XCTUnwrap(item.target as? NSObject)

        target.perform(try XCTUnwrap(item.action))
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(runtime.promptCallCount, 1)
        XCTAssertTrue(usageStore.hasConfiguredAdminKey)
        XCTAssertEqual(client.costsCallCount, 0)
        XCTAssertEqual(client.usageCallCount, 0)
    }

    func testRemoveOpenAIAdminKeyActionClearsStoredKey() throws {
        let usageStore = makeOpenAIUsageStore(isEnabled: true, adminKey: "sk-admin-123")
        let delegate = makeDelegate(
            installedApplicationURL: nil,
            preferences: ToolbarPreferences(defaults: Self.makeDefaults()),
            openAIUsageStore: usageStore
        )
        let menu = delegate.makeContextMenu()
        let item = try XCTUnwrap(menu.items.first { $0.title == "Remove OpenAI admin key" })
        let target = try XCTUnwrap(item.target as? NSObject)

        target.perform(try XCTUnwrap(item.action))

        XCTAssertFalse(usageStore.hasConfiguredAdminKey)
        XCTAssertEqual(
            usageStore.viewData?.statusMessage,
            "Configure an OpenAI admin key to view organization API usage."
        )
    }

    func testStatusMenuContentHidesSupplementalSectionsWhenPreferenceIsOff() {
        let defaults = Self.makeDefaults()
        let delegate = makeDelegate(
            store: makeSparkStore(),
            codexDesktopAppProvider: FakeCodexDesktopAppProvider(installedApplicationURL: nil),
            preferences: ToolbarPreferences(defaults: defaults)
        )

        let view = delegate.makeStatusMenuContentView()

        XCTAssertEqual(view.visibleSupplementalFamilyIDs, [])
        XCTAssertFalse(view.showsCredits)
        XCTAssertFalse(view.showsOpenAIUsage)
    }

    func testStatusMenuContentShowsCreditsWhenPreferenceIsOn() {
        let defaults = Self.makeDefaults()
        defaults.set(true, forKey: "showCredits")
        let delegate = makeDelegate(
            store: makeSparkStore(),
            codexDesktopAppProvider: FakeCodexDesktopAppProvider(installedApplicationURL: nil),
            preferences: ToolbarPreferences(defaults: defaults)
        )

        let view = delegate.makeStatusMenuContentView()

        XCTAssertTrue(view.showsCredits)
    }

    func testStatusMenuContentHidesOpenAIUsageByDefault() {
        let delegate = makeDelegate(
            store: makeSparkStore(),
            codexDesktopAppProvider: FakeCodexDesktopAppProvider(installedApplicationURL: nil),
            preferences: ToolbarPreferences(defaults: Self.makeDefaults())
        )

        let view = delegate.makeStatusMenuContentView()

        XCTAssertTrue(view.openAIUsageStore.isEnabled)
        XCTAssertFalse(view.showsOpenAIUsage)
    }

    func testStatusMenuContentShowsOpenAIUsageWhenPreferenceIsOn() {
        let defaults = Self.makeDefaults()
        defaults.set(true, forKey: "showOpenAIUsage")
        let delegate = makeDelegate(
            store: makeSparkStore(),
            codexDesktopAppProvider: FakeCodexDesktopAppProvider(installedApplicationURL: nil),
            preferences: ToolbarPreferences(defaults: defaults)
        )

        let view = delegate.makeStatusMenuContentView()

        XCTAssertTrue(view.showsOpenAIUsage)
    }

    func testStatusMenuContentShowsSupplementalSectionsWhenScreenshotOverrideIsEnabled() {
        let defaults = Self.makeDefaults()
        let screenshotConfiguration = ScreenshotLaunchConfiguration(
            scenario: .spark,
            appearance: .light,
            outputDirectory: nil,
            shouldCapturePopover: true,
            shouldCaptureStatusItem: false,
            shouldOpenPopover: true,
            visibleSupplementalFamilyIDs: ["codex_bengalfox"]
        )
        let delegate = makeDelegate(
            store: makeSparkStore(),
            codexDesktopAppProvider: FakeCodexDesktopAppProvider(installedApplicationURL: nil),
            preferences: ToolbarPreferences(defaults: defaults),
            screenshotConfiguration: screenshotConfiguration
        )

        let view = delegate.makeStatusMenuContentView()

        XCTAssertEqual(view.visibleSupplementalFamilyIDs, ["codex_bengalfox"])
    }

    func testPopoverContentSizeExpandsWhenOpenAIUsageIsVisible() {
        let defaults = Self.makeDefaults()
        let preferences = ToolbarPreferences(defaults: defaults)
        let delegate = makeDelegate(
            installedApplicationURL: nil,
            preferences: preferences
        )
        let compactSize = delegate.popoverContentSize
        preferences.setOpenAIUsageVisible(true)
        let expandedSize = delegate.popoverContentSize

        XCTAssertEqual(expandedSize.width, compactSize.width)
        XCTAssertGreaterThan(expandedSize.height, compactSize.height)
        XCTAssertLessThanOrEqual(expandedSize.height, StatusMenuContentView.maximumPopoverHeight)
    }

    func testPopoverContentSizeStaysCompactWhenOpenAIUsageIsHidden() {
        let delegate = makeDelegate(
            installedApplicationURL: nil,
            preferences: ToolbarPreferences(defaults: Self.makeDefaults())
        )

        XCTAssertEqual(delegate.popoverContentSize.width, 352)
        XCTAssertGreaterThan(delegate.popoverContentSize.height, 0)
        XCTAssertLessThan(delegate.popoverContentSize.height, 300)
    }

    func testClaudePopoverFitsThreeWindowsAndCapsLongerContent() {
        func size(windows: [ClaudeUsageWindow]) -> NSSize {
            let store = ClaudeUsageStore(
                client: DelegateClaudeUsageClient(),
                initialSnapshot: ClaudeUsageSnapshot(windows: windows),
                initialLastUpdated: ScreenshotScenario.claude.lastUpdated,
                liveUpdatesEnabled: false
            )
            let delegate = makeDelegate(
                installedApplicationURL: nil,
                preferences: ToolbarPreferences(defaults: Self.makeDefaults()),
                claudeUsageStore: store
            )
            return delegate.popoverContentSize(for: .claude)
        }
        let windows = ScreenshotScenario.claude.claudeUsageSnapshot!.windows
        let singleSize = size(windows: Array(windows.prefix(1)))
        let threeWindowSize = size(windows: windows)
        XCTAssertGreaterThan(threeWindowSize.height, singleSize.height)
        XCTAssertGreaterThan(threeWindowSize.height, 390, "The old fixed height clipped the model's percentages and reset")
        XCTAssertLessThan(threeWindowSize.height, StatusMenuContentView.maximumPopoverHeight)

        let manyWindows = (0..<12).map { index in
            ClaudeUsageWindow(id: "model-\(index)", title: "Weekly (Model \(index))", usedPercent: 10,
                              resetDescription: "Resets Mar 11 at 1pm (America/Los_Angeles)")
        }
        XCTAssertEqual(size(windows: manyWindows).height, StatusMenuContentView.maximumPopoverHeight)
    }

    func testReadyStatusItemImageKeepsGlyphTintStableWhileBarColorChanges() throws {
        let palette = StatusMenuPalette.forAppearance(.light, colorScheme: .light)
        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))

        let warningImage = AppDelegate.readyStatusItemImage(
            bar: .init(remainingPercent: 18, progressState: .warning),
            appearance: appearance,
            glyphColor: palette.statusItemGlyphColor,
            trackColor: palette.trackColor(for: .warning),
            fillColor: palette.fillColor(for: .warning)
        )
        let criticalImage = AppDelegate.readyStatusItemImage(
            bar: .init(remainingPercent: 8, progressState: .critical),
            appearance: appearance,
            glyphColor: palette.statusItemGlyphColor,
            trackColor: palette.trackColor(for: .critical),
            fillColor: palette.fillColor(for: .critical)
        )

        let glyphRegion = NSRect(x: 0, y: 0, width: 16, height: 16)
        let barRegion = NSRect(x: 20, y: 0, width: 44, height: 16)

        XCTAssertEqual(try pixelData(for: warningImage, in: glyphRegion), try pixelData(for: criticalImage, in: glyphRegion))
        XCTAssertNotEqual(try pixelData(for: warningImage, in: barRegion), try pixelData(for: criticalImage, in: barRegion))
    }

    func testReadyStatusItemImageAppliesGlyphTintWithoutFlatteningTransparency() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let glyphColor = NSColor(calibratedRed: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
        let image = AppDelegate.readyStatusItemImage(
            bar: .init(remainingPercent: 50, progressState: .normal),
            appearance: appearance,
            glyphColor: glyphColor,
            trackColor: NSColor(calibratedWhite: 0.2, alpha: 1.0),
            fillColor: NSColor(calibratedWhite: 0.6, alpha: 1.0)
        )
        let bitmap = try renderedBitmap(for: image)
        var transparentPixelCount = 0
        var tintedPixelCount = 0

        for y in 0..<16 {
            for x in 0..<16 {
                let color = try XCTUnwrap(
                    bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                )

                if color.alphaComponent < 0.05 {
                    transparentPixelCount += 1
                }

                if
                    color.alphaComponent > 0.2,
                    color.redComponent > 0.7,
                    color.greenComponent < 0.3,
                    color.blueComponent < 0.3
                {
                    tintedPixelCount += 1
                }
            }
        }

        XCTAssertGreaterThan(transparentPixelCount, 0)
        XCTAssertGreaterThan(tintedPixelCount, 0)
    }

    func testUpdateStatusItemButtonSetsReadyTooltipWithoutChangingAccessibilityLabel() throws {
        let store = RateLimitStore(
            client: FakeStatusItemRateLimitClient(),
            initialState: .ready,
            initialCards: [
                RateLimitCardViewData(
                    window: CodexRateLimitWindow(resetsAt: 1_741_731_200, usedPercent: 50, windowDurationMins: 10_080),
                    familyId: "codex"
                )
            ],
            initialStatusMessage: "Rate limits remaining",
            liveUpdatesEnabled: false
        )
        let delegate = makeDelegate(
            store: store,
            codexDesktopAppProvider: FakeCodexDesktopAppProvider(installedApplicationURL: nil),
            preferences: ToolbarPreferences(defaults: Self.makeDefaults())
        )
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        let button = try XCTUnwrap(statusItem.button)

        delegate.updateStatusItemButton(button)

        XCTAssertEqual(button.toolTip, "Codex · 50% remaining")
        XCTAssertEqual(button.title, "")
        XCTAssertEqual(button.accessibilityLabel(), "Codex toolbar. Weekly limit status open. 50% remaining.")
    }

    func testUpdateStatusItemButtonSetsErrorTooltipForTextPresentation() throws {
        let store = RateLimitStore(
            client: FakeStatusItemRateLimitClient(),
            initialState: .error("Codex CLI not found."),
            initialCards: [],
            initialStatusMessage: "Codex CLI not found.",
            liveUpdatesEnabled: false
        )
        let delegate = makeDelegate(
            store: store,
            codexDesktopAppProvider: FakeCodexDesktopAppProvider(installedApplicationURL: nil),
            preferences: ToolbarPreferences(defaults: Self.makeDefaults())
        )
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        let button = try XCTUnwrap(statusItem.button)

        delegate.updateStatusItemButton(button)

        XCTAssertEqual(button.toolTip, "Codex · Codex CLI not found.")
        XCTAssertEqual(button.title, "!")
        XCTAssertEqual(button.accessibilityLabel(), "Codex toolbar. Codex CLI not found.")
    }

    func testHandleInstallUpdateResultTerminatesImmediatelyAfterDetachedUpdaterStarts() {
        let runtime = FakeAppRuntimeController()
        let delegate = makeDelegate(
            installedApplicationURL: nil,
            preferences: ToolbarPreferences(defaults: Self.makeDefaults()),
            appRuntime: runtime
        )

        delegate.handleInstallUpdateResult(.started)

        XCTAssertEqual(runtime.terminateCallCount, 1)
        XCTAssertEqual(runtime.notifications.count, 0)
    }

    func testHandleInstallUpdateResultNotifiesOnPreflightFailureWithoutTerminating() {
        let runtime = FakeAppRuntimeController()
        let delegate = makeDelegate(
            installedApplicationURL: nil,
            preferences: ToolbarPreferences(defaults: Self.makeDefaults()),
            appRuntime: runtime
        )

        delegate.handleInstallUpdateResult(.failed("Refusing to update from a dirty git worktree."))

        XCTAssertEqual(runtime.terminateCallCount, 0)
        XCTAssertEqual(runtime.notifications.count, 1)
        XCTAssertEqual(runtime.notifications[0].title, "CodexToolbar update failed")
        XCTAssertEqual(runtime.notifications[0].body, "Refusing to update from a dirty git worktree.")
    }

    func testHandleInstallUpdateResultOpensReleasePageWithoutTerminating() throws {
        let runtime = FakeAppRuntimeController()
        let delegate = makeDelegate(
            installedApplicationURL: nil,
            preferences: ToolbarPreferences(defaults: Self.makeDefaults()),
            appRuntime: runtime
        )
        let releaseURL = try XCTUnwrap(URL(string: "https://github.com/mikeylong/codex-toolbar/releases/latest"))

        delegate.handleInstallUpdateResult(.openReleasePage(releaseURL))

        XCTAssertEqual(runtime.terminateCallCount, 0)
        XCTAssertEqual(runtime.openedURLs, [releaseURL])
        XCTAssertEqual(runtime.notifications.count, 0)
    }

    private func makeDelegate(
        installedApplicationURL: URL?,
        preferences: ToolbarPreferences,
        screenshotConfiguration: ScreenshotLaunchConfiguration? = nil,
        startupDiagnosticsConfiguration: StartupDiagnosticsConfiguration? = nil,
        openAIUsageStore: OpenAIUsageStore? = nil,
        claudeUsageStore: ClaudeUsageStore? = nil,
        appRuntime: any AppRuntimeControlling = FakeAppRuntimeController()
    ) -> AppDelegate {
        makeDelegate(
            store: makeNormalStore(),
            openAIUsageStore: openAIUsageStore ?? makeOpenAIUsageStore(isEnabled: true),
            claudeUsageStore: claudeUsageStore ?? ClaudeUsageStore(client: DelegateClaudeUsageClient()),
            codexDesktopAppProvider: FakeCodexDesktopAppProvider(installedApplicationURL: installedApplicationURL),
            preferences: preferences,
            screenshotConfiguration: screenshotConfiguration,
            startupDiagnosticsConfiguration: startupDiagnosticsConfiguration,
            appRuntime: appRuntime
        )
    }

    private func makeDelegate(
        store: RateLimitStore,
        openAIUsageStore: OpenAIUsageStore? = nil,
        claudeUsageStore: ClaudeUsageStore? = nil,
        codexDesktopAppProvider: any CodexDesktopAppProviding,
        preferences: ToolbarPreferences,
        screenshotConfiguration: ScreenshotLaunchConfiguration? = nil,
        startupDiagnosticsConfiguration: StartupDiagnosticsConfiguration? = nil,
        gitUpdateController: GitUpdateController? = nil,
        appRuntime: any AppRuntimeControlling = FakeAppRuntimeController()
    ) -> AppDelegate {
        AppDelegate(
            store: store,
            openAIUsageStore: openAIUsageStore ?? makeOpenAIUsageStore(isEnabled: true),
            claudeUsageStore: claudeUsageStore ?? ClaudeUsageStore(client: DelegateClaudeUsageClient()),
            loginItemController: LoginItemController(service: FakeLoginItemService()),
            gitUpdateController: gitUpdateController ?? makeGitUpdateController(preferences: preferences),
            codexDesktopAppProvider: codexDesktopAppProvider,
            preferences: preferences,
            maintenanceLaunchConfiguration: nil,
            screenshotConfiguration: screenshotConfiguration,
            startupDiagnosticsConfiguration: startupDiagnosticsConfiguration,
            appRuntime: appRuntime
        )
    }

    private func makeGitUpdateController(
        preferences: ToolbarPreferences,
        tooling: any GitUpdateTooling = FakeGitUpdateTooling(),
        currentVersionProvider: @escaping @Sendable () -> String = { AppVersion.current },
        state: GitUpdateState = .upToDate
    ) -> GitUpdateController {
        let controller = GitUpdateController(
            service: GitUpdateService(tooling: tooling),
            preferences: preferences,
            currentVersionProvider: currentVersionProvider,
            refreshDelayNanosecondsProvider: { 1_000_000_000 }
        )
        controller.state = state
        return controller
    }

    private func makeSparkStore() -> RateLimitStore {
        RateLimitStore.makeShared(
            arguments: ["CodexToolbar", "--screenshot-scenario", "spark"],
            environment: [:]
        )
    }

    private func makeNormalStore() -> RateLimitStore {
        RateLimitStore.makeShared(
            arguments: ["CodexToolbar", "--screenshot-scenario", "normal"],
            environment: [:]
        )
    }

    private func makeOpenAIUsageStore(
        isEnabled: Bool,
        adminKey: String? = nil,
        client: FakeOpenAIUsageClient = FakeOpenAIUsageClient()
    ) -> OpenAIUsageStore {
        OpenAIUsageStore(
            client: client,
            adminKeyStore: FakeOpenAIAdminKeyStore(initialKey: adminKey),
            nowProvider: { Date(timeIntervalSince1970: 1_711_929_600) },
            isEnabled: isEnabled
        )
    }

    private static func makeDefaults() -> UserDefaults {
        let suiteName = "AppDelegateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeOpenAICostBucket(amount: String) throws -> OpenAICostBucket {
        try JSONDecoder().decode(
            OpenAICostBucket.self,
            from: Data(
                """
                {
                  "object": "bucket",
                  "start_time": 1711929600,
                  "end_time": 1712016000,
                  "results": [
                    {
                      "object": "organization.costs.result",
                      "amount": {
                        "value": \(amount),
                        "currency": "USD"
                      }
                    }
                  ]
                }
                """.utf8
            )
        )
    }

    private func makeOpenAIUsageBucket(requests: Int, input: Int, output: Int) throws -> OpenAICompletionsUsageBucket {
        try JSONDecoder().decode(
            OpenAICompletionsUsageBucket.self,
            from: Data(
                """
                {
                  "object": "bucket",
                  "start_time": 1711929600,
                  "end_time": 1712016000,
                  "results": [
                    {
                      "object": "organization.usage.completions.result",
                      "input_tokens": \(input),
                      "output_tokens": \(output),
                      "num_model_requests": \(requests)
                    }
                  ]
                }
                """.utf8
            )
        )
    }

    private func pixelData(for image: NSImage, in region: NSRect) throws -> Data {
        let bitmap = try renderedBitmap(for: image)

        var bytes: [UInt8] = []
        for y in Int(region.minY)..<Int(region.maxY) {
            for x in Int(region.minX)..<Int(region.maxX) {
                let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                bytes.append(UInt8((color.redComponent * 255).rounded()))
                bytes.append(UInt8((color.greenComponent * 255).rounded()))
                bytes.append(UInt8((color.blueComponent * 255).rounded()))
                bytes.append(UInt8((color.alphaComponent * 255).rounded()))
            }
        }

        return Data(bytes)
    }

    private func renderedBitmap(for image: NSImage) throws -> NSBitmapImageRep {
        let pixelsWide = Int(image.size.width)
        let pixelsHigh = Int(image.size.height)
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelsWide,
                pixelsHigh: pixelsHigh,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )

        bitmap.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()

        return bitmap
    }
}

@MainActor
private final class FakeCodexDesktopAppProvider: CodexDesktopAppProviding {
    let installedApplicationURL: URL?
    private(set) var openCallCount = 0

    init(installedApplicationURL: URL?) {
        self.installedApplicationURL = installedApplicationURL
    }

    func openCodex() async throws {
        openCallCount += 1
    }
}

private final class FakeOpenAIAdminKeyStore: @unchecked Sendable, OpenAIAdminKeyStore {
    private(set) var storedKey: String?

    init(initialKey: String?) {
        storedKey = initialKey
    }

    func readAdminKey() throws -> String? {
        storedKey
    }

    func writeAdminKey(_ key: String) throws {
        storedKey = key
    }

    func removeAdminKey() throws {
        storedKey = nil
    }
}

private final class FakeOpenAIUsageClient: @unchecked Sendable, OpenAIUsageClient {
    var costBuckets: [OpenAICostBucket] = []
    var usageBuckets: [OpenAICompletionsUsageBucket] = []
    var costsError: Error?
    var usageError: Error?
    private(set) var costsCallCount = 0
    private(set) var usageCallCount = 0

    func readCosts(
        adminKey: String,
        startTime: Int64,
        endTime: Int64,
        limit: Int
    ) async throws -> [OpenAICostBucket] {
        costsCallCount += 1
        if let costsError {
            throw costsError
        }
        return costBuckets
    }

    func readCompletionsUsage(
        adminKey: String,
        startTime: Int64,
        endTime: Int64,
        limit: Int
    ) async throws -> [OpenAICompletionsUsageBucket] {
        usageCallCount += 1
        if let usageError {
            throw usageError
        }
        return usageBuckets
    }
}

@MainActor
private struct FakeLoginItemService: LoginItemService {
    var status: LoginItemRegistrationStatus { .notRegistered }

    func register() throws {}
    func unregister() throws {}
}

private final class FakeStatusItemRateLimitClient: @unchecked Sendable, CodexRateLimitClient {
    private(set) var loadSnapshotCallCount = 0
    private let snapshotGate: DelegateSnapshotGate?

    init(snapshotGate: DelegateSnapshotGate? = nil) {
        self.snapshotGate = snapshotGate
    }

    func events() -> AsyncStream<CodexAppServerEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func connect() async throws {}
    func disconnect() async {}

    func readAccount(refreshToken: Bool) async throws -> GetAccountResponse {
        GetAccountResponse(account: .apiKey, requiresOpenaiAuth: false)
    }

    func readRateLimits() async throws -> GetAccountRateLimitsResponse {
        Self.sampleRateLimits
    }

    func readLoginStatus() async throws -> CodexLoginStatus {
        .loggedIn
    }

    func loadSnapshot(refreshToken: Bool) async throws -> (GetAccountResponse, GetAccountRateLimitsResponse) {
        loadSnapshotCallCount += 1
        await snapshotGate?.wait()
        return (try await readAccount(refreshToken: refreshToken), try await readRateLimits())
    }

    private static let sampleRateLimits = GetAccountRateLimitsResponse(
        rateLimits: CodexRateLimitsSnapshot(
            credits: nil,
            limitId: "codex",
            limitName: "Codex",
            planType: .plus,
            primary: CodexRateLimitWindow(
                resetsAt: 1_711_998_000,
                usedPercent: 25,
                windowDurationMins: 10_080
            ),
            secondary: nil
        ),
        rateLimitsByLimitId: nil
    )
}

private actor DelegateSnapshotGate {
    private var opened = false
    private var continuations: [CheckedContinuation<Void, Never>] = []
    var isWaiting: Bool { !continuations.isEmpty }

    func wait() async {
        guard !opened else { return }
        await withCheckedContinuation { continuations.append($0) }
    }

    func release() {
        opened = true
        let waiting = continuations
        continuations.removeAll()
        waiting.forEach { $0.resume() }
    }
}

private struct FakeGitUpdateTooling: GitUpdateTooling {
    func runGit(
        arguments: [String],
        repositoryURL: URL,
        timeoutNanoseconds: UInt64
    ) async throws -> GitCommandResult {
        GitCommandResult(exitStatus: 0, stdout: "", stderr: "")
    }

    func launchDetachedUpdate(configuration: GitUpdateRepositoryConfiguration) throws {}

    func fetchLatestReleaseTag(
        repositorySlug: String,
        timeoutNanoseconds: UInt64
    ) async throws -> String? {
        nil
    }
}

private final class CountingGitUpdateTooling: @unchecked Sendable, GitUpdateTooling {
    private let queue = DispatchQueue(label: "AppDelegateTests.CountingGitUpdateTooling")
    private(set) var fetchLatestReleaseTagCallCount = 0
    var latestReleaseTag: String?

    init(latestReleaseTag: String? = nil) {
        self.latestReleaseTag = latestReleaseTag
    }

    func runGit(
        arguments: [String],
        repositoryURL: URL,
        timeoutNanoseconds: UInt64
    ) async throws -> GitCommandResult {
        GitCommandResult(exitStatus: 0, stdout: "", stderr: "")
    }

    func launchDetachedUpdate(configuration: GitUpdateRepositoryConfiguration) throws {}

    func fetchLatestReleaseTag(
        repositorySlug: String,
        timeoutNanoseconds: UInt64
    ) async throws -> String? {
        queue.sync {
            fetchLatestReleaseTagCallCount += 1
            return latestReleaseTag
        }
    }
}

@MainActor
private final class FakeAppRuntimeController: AppRuntimeControlling {
    struct Notification: Equatable {
        let title: String
        let body: String
    }

    private(set) var terminateCallCount = 0
    private(set) var notifications: [Notification] = []
    private(set) var openedURLs: [URL] = []
    var promptedSecret: String?
    private(set) var promptCallCount = 0
    var providerChoice: UsageProviderSelection?
    private(set) var providerChoiceCallCount = 0
    private(set) var previousProviderChoices: [UsageProviderSelection?] = []

    func terminate() {
        terminateCallCount += 1
    }

    func postNotification(title: String, body: String) {
        notifications.append(Notification(title: title, body: body))
    }

    func openURL(_ url: URL) throws {
        openedURLs.append(url)
    }

    func promptForSecret(title: String, message: String) -> String? {
        promptCallCount += 1
        return promptedSecret
    }

    func chooseUsageProviders(current: UsageProviderSelection?) -> UsageProviderSelection? {
        providerChoiceCallCount += 1
        previousProviderChoices.append(current)
        return providerChoice
    }
}

private actor DelegateClaudeUsageClient: ClaudeUsageClient {
    private(set) var callCount = 0

    func readUsage() async throws -> ClaudeUsageSnapshot {
        callCount += 1
        return ClaudeUsageSnapshot(windows: [
            ClaudeUsageWindow(id: "weekly", title: "Weekly", usedPercent: 63,
                              resetDescription: "Resets Nov 17 at 1pm (America/Los_Angeles)")
        ])
    }
}

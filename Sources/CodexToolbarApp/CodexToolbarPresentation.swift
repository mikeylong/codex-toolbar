import ToolbarCore

extension ToolbarPresentation {
    static let codexToolbar = ToolbarPresentation(
        appName: "CodexToolbar",
        panelTitle: "Codex usage status",
        statusItemAccessibilityLabel: "Codex toolbar",
        fallbackImageAccessibilityLabel: "Codex",
        connectingStatusMessage: "Connecting to Codex…",
        signInRequiredMessage: "Sign in to Codex to view rate limits.",
        noDataMessage: "No rate-limit data available.",
        disconnectedMessage: "Disconnected from Codex.",
        unableToLoadMessage: "Unable to load Codex rate limits.",
        connectDebugDetail: "Connecting to Codex app-server",
        validStartupErrorMessages: [
            "Codex CLI not found.",
            "Sign in to Codex to view rate limits.",
            "No rate-limit data available."
        ]
    )
}

import ToolbarCore

extension ToolbarPresentation {
    static let quotaBar = ToolbarPresentation(
        appName: "QuotaBar",
        panelTitle: "QuotaBar usage status",
        statusItemAccessibilityLabel: "QuotaBar",
        fallbackImageAccessibilityLabel: "QuotaBar",
        connectingStatusMessage: "Loading usage windows…",
        signInRequiredMessage: "Sign in to continue.",
        noDataMessage: "No usage data available.",
        disconnectedMessage: "Disconnected from live sync.",
        unableToLoadMessage: "Unable to load usage windows.",
        connectDebugDetail: "Loading usage windows",
        validStartupErrorMessages: [
            QuotaBarReleaseGate.unavailableMessage,
            "No usage data available."
        ]
    )
}

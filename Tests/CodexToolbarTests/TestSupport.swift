import ToolbarCore

extension ToolbarPresentation {
    static let testPresentation = ToolbarPresentation(
        appName: "TestToolbar",
        panelTitle: "Test status",
        statusItemAccessibilityLabel: "Test toolbar",
        fallbackImageAccessibilityLabel: "Test",
        connectingStatusMessage: "Connecting…",
        signInRequiredMessage: "Sign in required.",
        noDataMessage: "No data available.",
        disconnectedMessage: "Disconnected.",
        unableToLoadMessage: "Unable to load data.",
        connectDebugDetail: "Connecting",
        validStartupErrorMessages: [
            "No data available.",
            "Sign in required.",
            "Client unavailable."
        ]
    )
}

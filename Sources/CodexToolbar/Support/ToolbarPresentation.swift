import Foundation

package struct ToolbarPresentation: Equatable, Sendable {
    package let appName: String
    package let panelTitle: String
    package let statusItemAccessibilityLabel: String
    package let fallbackImageAccessibilityLabel: String
    package let connectingStatusMessage: String
    package let signInRequiredMessage: String
    package let noDataMessage: String
    package let disconnectedMessage: String
    package let unableToLoadMessage: String
    package let connectDebugDetail: String?
    package let validStartupErrorMessages: Set<String>

    package init(
        appName: String,
        panelTitle: String,
        statusItemAccessibilityLabel: String,
        fallbackImageAccessibilityLabel: String,
        connectingStatusMessage: String,
        signInRequiredMessage: String,
        noDataMessage: String,
        disconnectedMessage: String,
        unableToLoadMessage: String,
        connectDebugDetail: String?,
        validStartupErrorMessages: Set<String>
    ) {
        self.appName = appName
        self.panelTitle = panelTitle
        self.statusItemAccessibilityLabel = statusItemAccessibilityLabel
        self.fallbackImageAccessibilityLabel = fallbackImageAccessibilityLabel
        self.connectingStatusMessage = connectingStatusMessage
        self.signInRequiredMessage = signInRequiredMessage
        self.noDataMessage = noDataMessage
        self.disconnectedMessage = disconnectedMessage
        self.unableToLoadMessage = unableToLoadMessage
        self.connectDebugDetail = connectDebugDetail
        self.validStartupErrorMessages = validStartupErrorMessages
    }
}

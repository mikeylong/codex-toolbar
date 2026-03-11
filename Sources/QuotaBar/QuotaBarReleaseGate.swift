enum QuotaBarReleaseGate {
    // Keep release disabled until QuotaBar has a documented, App-Store-safe live data source.
    static let liveSyncAvailable = false
    static let unavailableMessage = "Live account sync is unavailable because this build does not yet have an App-Store-safe live data source."
    static let reviewMessage = "Use the Demo scenario menu to preview QuotaBar."
}

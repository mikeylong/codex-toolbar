import Foundation

@MainActor
final class ToolbarPreferences {
    static let shared = ToolbarPreferences()

    private enum Keys {
        static let visibleSupplementalFamilyPrefix = "visibleSupplementalFamily."
        static let showCredits = "showCredits"
        static let showOpenAIUsage = "showOpenAIUsage"
        static let gitUpdateRepositoryRoot = "gitUpdate.repositoryRoot"
        static let gitUpdateRemoteName = "gitUpdate.remoteName"
        static let gitUpdateBranchName = "gitUpdate.branchName"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isSupplementalFamilyVisible(_ family: SupplementalLimitFamily) -> Bool {
        guard family.isUserToggleable else {
            return true
        }

        let key = visibilityKey(for: family.limitId)
        if defaults.object(forKey: key) == nil {
            return false
        }

        return defaults.bool(forKey: key)
    }

    func setSupplementalFamilyVisible(_ isVisible: Bool, for family: SupplementalLimitFamily) {
        defaults.set(isVisible, forKey: visibilityKey(for: family.limitId))
    }

    func toggleSupplementalFamilyVisibility(_ family: SupplementalLimitFamily) {
        setSupplementalFamilyVisible(!isSupplementalFamilyVisible(family), for: family)
    }

    func visibleSupplementalFamilyIDs(
        from families: [SupplementalLimitFamily] = GetAccountRateLimitsResponse.supportedSupplementalFamilies
    ) -> Set<String> {
        Set(
            families.compactMap { family in
                if family.isUserToggleable {
                    return isSupplementalFamilyVisible(family) ? family.limitId : nil
                }

                return family.limitId
            }
        )
    }

    var isCreditsVisible: Bool {
        if defaults.object(forKey: Keys.showCredits) == nil {
            return false
        }

        return defaults.bool(forKey: Keys.showCredits)
    }

    func setCreditsVisible(_ isVisible: Bool) {
        defaults.set(isVisible, forKey: Keys.showCredits)
    }

    func toggleCreditsVisibility() {
        setCreditsVisible(!isCreditsVisible)
    }

    var isOpenAIUsageVisible: Bool {
        if defaults.object(forKey: Keys.showOpenAIUsage) == nil {
            return false
        }

        return defaults.bool(forKey: Keys.showOpenAIUsage)
    }

    func setOpenAIUsageVisible(_ isVisible: Bool) {
        defaults.set(isVisible, forKey: Keys.showOpenAIUsage)
    }

    func toggleOpenAIUsageVisibility() {
        setOpenAIUsageVisible(!isOpenAIUsageVisible)
    }

    func gitUpdateRepositoryConfiguration() -> GitUpdateRepositoryConfiguration? {
        guard
            let repositoryRoot = defaults.string(forKey: Keys.gitUpdateRepositoryRoot)?.nonEmpty,
            let remoteName = defaults.string(forKey: Keys.gitUpdateRemoteName)?.nonEmpty,
            let branchName = defaults.string(forKey: Keys.gitUpdateBranchName)?.nonEmpty
        else {
            return nil
        }

        return GitUpdateRepositoryConfiguration(
            repositoryRoot: repositoryRoot,
            remoteName: remoteName,
            branchName: branchName
        )
    }

    func setGitUpdateRepositoryConfiguration(_ configuration: GitUpdateRepositoryConfiguration?) {
        guard let configuration else {
            defaults.removeObject(forKey: Keys.gitUpdateRepositoryRoot)
            defaults.removeObject(forKey: Keys.gitUpdateRemoteName)
            defaults.removeObject(forKey: Keys.gitUpdateBranchName)
            return
        }

        defaults.set(configuration.repositoryRoot, forKey: Keys.gitUpdateRepositoryRoot)
        defaults.set(configuration.remoteName, forKey: Keys.gitUpdateRemoteName)
        defaults.set(configuration.branchName, forKey: Keys.gitUpdateBranchName)
    }

    private func visibilityKey(for limitId: String) -> String {
        Keys.visibleSupplementalFamilyPrefix + limitId
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

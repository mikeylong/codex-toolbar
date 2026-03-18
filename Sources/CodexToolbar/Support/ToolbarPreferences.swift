import Foundation

@MainActor
final class ToolbarPreferences {
    static let shared = ToolbarPreferences()

    private enum Keys {
        static let visibleSupplementalFamilyPrefix = "visibleSupplementalFamily."
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

    private func visibilityKey(for limitId: String) -> String {
        Keys.visibleSupplementalFamilyPrefix + limitId
    }
}

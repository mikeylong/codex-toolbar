import AppKit
import Foundation

struct CodexDesktopAppLocator {
    private let bundleCandidates: [String]
    private let fileManager: FileManager

    init(
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path,
        fileManager: FileManager = .default,
        bundleCandidates: [String]? = nil
    ) {
        self.bundleCandidates = bundleCandidates ?? Self.appBundleCandidates(homeDirectory: homeDirectory)
        self.fileManager = fileManager
    }

    func installedApplicationURL() -> URL? {
        bundleCandidates.first { candidate in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: candidate, isDirectory: &isDirectory) && isDirectory.boolValue
        }.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static func appBundleCandidates(homeDirectory: String) -> [String] {
        let candidates = [
            "/Applications/Codex.app",
            URL(fileURLWithPath: homeDirectory).appendingPathComponent("Applications/Codex.app").path
        ]

        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }
}

@MainActor
protocol WorkspaceApplicationOpening {
    func openApplication(at url: URL, configuration: NSWorkspace.OpenConfiguration) async throws
}

struct SharedWorkspaceApplicationOpener: WorkspaceApplicationOpening {
    func openApplication(at url: URL, configuration: NSWorkspace.OpenConfiguration) async throws {
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}

@MainActor
protocol CodexDesktopAppProviding {
    var installedApplicationURL: URL? { get }
    func openCodex() async throws
}

enum CodexDesktopAppError: LocalizedError, Equatable {
    case notFound

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Codex.app was not found."
        }
    }
}

@MainActor
final class CodexDesktopAppController: CodexDesktopAppProviding {
    private let locator: CodexDesktopAppLocator
    private let workspace: any WorkspaceApplicationOpening

    init(
        locator: CodexDesktopAppLocator = CodexDesktopAppLocator(),
        workspace: any WorkspaceApplicationOpening = SharedWorkspaceApplicationOpener()
    ) {
        self.locator = locator
        self.workspace = workspace
    }

    var installedApplicationURL: URL? {
        locator.installedApplicationURL()
    }

    func openCodex() async throws {
        guard let applicationURL = installedApplicationURL else {
            throw CodexDesktopAppError.notFound
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false

        try await workspace.openApplication(at: applicationURL, configuration: configuration)
    }
}

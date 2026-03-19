import Foundation
import Observation

enum NotificationAppleScriptBuilder {
    static func script(title: String, body: String) -> String {
        "display notification \"\(escape(body))\" with title \"\(escape(title))\""
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

struct GitUpdateRepositoryConfiguration: Equatable, Sendable {
    let repositoryRoot: String
    let remoteName: String
    let branchName: String

    var repositoryURL: URL {
        URL(fileURLWithPath: repositoryRoot, isDirectory: true)
    }
}

enum GitUpdateState: Equatable, Sendable {
    case checking
    case upToDate
    case updateAvailable(String)
    case unsupported(String)

    var latestTag: String? {
        guard case let .updateAvailable(tag) = self else {
            return nil
        }

        return tag
    }
}

enum GitUpdateInstallResult: Equatable, Sendable {
    case started
    case failed(String)
}

protocol GitUpdateTooling: Sendable {
    func runGit(
        arguments: [String],
        repositoryURL: URL,
        timeoutNanoseconds: UInt64
    ) async throws -> GitCommandResult
    func launchDetachedUpdate(configuration: GitUpdateRepositoryConfiguration) throws
}

struct GitCommandResult: Equatable, Sendable {
    let exitStatus: Int32
    let stdout: String
    let stderr: String
}

struct GitUpdateService: Sendable {
    private let tooling: any GitUpdateTooling

    init(tooling: any GitUpdateTooling = LiveGitUpdateTooling()) {
        self.tooling = tooling
    }

    func checkForUpdates(
        currentVersion: String,
        configuration: GitUpdateRepositoryConfiguration?
    ) async -> GitUpdateState {
        guard let configuration else {
            return .unsupported("Git checkout metadata is unavailable.")
        }

        let repositoryURL = configuration.repositoryURL
        guard Self.isDirectory(at: repositoryURL) else {
            return .unsupported("Saved git checkout is unavailable.")
        }

        guard let installedVersion = GitReleaseVersion(versionString: currentVersion) else {
            return .unsupported("Installed app version is invalid.")
        }

        do {
            let fetchResult = try await tooling.runGit(
                arguments: ["fetch", "--tags", "--quiet", configuration.remoteName],
                repositoryURL: repositoryURL,
                timeoutNanoseconds: 15_000_000_000
            )

            guard fetchResult.exitStatus == 0 else {
                return .unsupported(fetchResult.stderr.nonEmpty ?? "Unable to fetch release tags.")
            }

            let tagResult = try await tooling.runGit(
                arguments: ["for-each-ref", "--format=%(objecttype) %(refname:strip=2)", "refs/tags"],
                repositoryURL: repositoryURL,
                timeoutNanoseconds: 5_000_000_000
            )

            guard tagResult.exitStatus == 0 else {
                return .unsupported(tagResult.stderr.nonEmpty ?? "Unable to enumerate release tags.")
            }

            let releaseVersions = annotatedReleaseVersions(from: tagResult.stdout)
            guard let latestVersion = releaseVersions.max() else {
                return .unsupported("No annotated release tags found.")
            }

            if latestVersion > installedVersion {
                return .updateAvailable(latestVersion.tagName)
            }

            return .upToDate
        } catch {
            return .unsupported(error.localizedDescription)
        }
    }

    func installUpdate(configuration: GitUpdateRepositoryConfiguration?) async -> GitUpdateInstallResult {
        guard let configuration else {
            return .failed("Git checkout metadata is unavailable.")
        }

        let repositoryURL = configuration.repositoryURL
        guard Self.isDirectory(at: repositoryURL) else {
            return .failed("Saved git checkout is unavailable.")
        }

        let installScriptURL = repositoryURL.appendingPathComponent("scripts/install_app.sh")
        guard FileManager.default.isExecutableFile(atPath: installScriptURL.path) else {
            return .failed("Install script is unavailable.")
        }

        do {
            let statusResult = try await tooling.runGit(
                arguments: ["status", "--porcelain"],
                repositoryURL: repositoryURL,
                timeoutNanoseconds: 5_000_000_000
            )

            guard statusResult.exitStatus == 0 else {
                return .failed(statusResult.stderr.nonEmpty ?? "Unable to inspect git worktree state.")
            }

            guard statusResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failed("Refusing to update from a dirty git worktree.")
            }

            try tooling.launchDetachedUpdate(configuration: configuration)
            return .started
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func annotatedReleaseVersions(from rawOutput: String) -> [GitReleaseVersion] {
        rawOutput
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> GitReleaseVersion? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    return nil
                }

                let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                guard parts.count == 2, parts[0] == "tag" else {
                    return nil
                }

                return GitReleaseVersion(tagName: String(parts[1]))
            }
    }

    private static func isDirectory(at url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}

@MainActor
@Observable
final class GitUpdateController {
    static let shared = GitUpdateController()

    var state: GitUpdateState = .checking

    private let service: GitUpdateService
    private let preferences: ToolbarPreferences
    private let currentVersionProvider: @Sendable () -> String
    private let refreshDelayNanosecondsProvider: @Sendable () -> UInt64

    private var started = false
    private var lastResolvedState: GitUpdateState?
    private var refreshLoopTask: Task<Void, Never>?
    private var refreshTask: Task<GitUpdateState, Never>?

    init(
        service: GitUpdateService = GitUpdateService(),
        preferences: ToolbarPreferences = .shared,
        currentVersionProvider: @escaping @Sendable () -> String = { AppVersion.current },
        refreshDelayNanosecondsProvider: @escaping @Sendable () -> UInt64 = { RateLimitStore.defaultRefreshDelayNanoseconds() }
    ) {
        self.service = service
        self.preferences = preferences
        self.currentVersionProvider = currentVersionProvider
        self.refreshDelayNanosecondsProvider = refreshDelayNanosecondsProvider
    }

    func start() {
        guard !started else { return }
        started = true

        Task { [weak self] in
            await self?.refreshNow()
        }

        refreshLoopTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: refreshDelayNanosecondsProvider())
                guard !Task.isCancelled else { return }
                await refreshNow()
            }
        }
    }

    func refreshNow() async {
        if let refreshTask {
            let result = await refreshTask.value
            apply(result)
            return
        }

        if lastResolvedState == nil {
            state = .checking
        }

        let configuration = preferences.gitUpdateRepositoryConfiguration()
        let currentVersion = currentVersionProvider()
        let task = Task { [service] in
            await service.checkForUpdates(currentVersion: currentVersion, configuration: configuration)
        }
        refreshTask = task

        let result = await task.value
        apply(result)
        refreshTask = nil
    }

    func installUpdate() async -> GitUpdateInstallResult {
        guard case .updateAvailable = menuState else {
            return .failed("No update is currently available.")
        }

        return await service.installUpdate(configuration: preferences.gitUpdateRepositoryConfiguration())
    }

    var menuState: GitUpdateState {
        if case .checking = state, let lastResolvedState {
            return lastResolvedState
        }

        return state
    }

    private func apply(_ result: GitUpdateState) {
        state = result

        if case .checking = result {
            return
        }

        lastResolvedState = result
    }
}

private struct GitReleaseVersion: Comparable, Equatable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int
    let tagName: String

    init?(tagName: String) {
        guard let version = GitReleaseVersion(versionString: tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName) else {
            return nil
        }

        self = GitReleaseVersion(
            major: version.major,
            minor: version.minor,
            patch: version.patch,
            tagName: tagName
        )
    }

    init?(versionString: String) {
        let parts = versionString.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2]) else {
            return nil
        }

        self.major = major
        self.minor = minor
        self.patch = patch
        tagName = "v\(major).\(minor).\(patch)"
    }

    private init(major: Int, minor: Int, patch: Int, tagName: String) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.tagName = tagName
    }

    static func < (lhs: GitReleaseVersion, rhs: GitReleaseVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }

        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }

        return lhs.patch < rhs.patch
    }
}

struct GitUpdateDetachedCommandBuilder {
    let logPath: String
    let installedAppPath: String
    let updateFailureTitle: String

    init(
        logPath: String = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("codextoolbar-update.log")
            .path,
        installedAppPath: String = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Applications/CodexToolbar.app")
            .path,
        updateFailureTitle: String = "CodexToolbar update failed"
    ) {
        self.logPath = logPath
        self.installedAppPath = installedAppPath
        self.updateFailureTitle = updateFailureTitle
    }

    func command(for configuration: GitUpdateRepositoryConfiguration) -> String {
        """
        set -euo pipefail
        exec </dev/null >\(shellQuoted(logPath)) 2>&1
        cd \(shellQuoted(configuration.repositoryRoot))
        if [[ -n "$(git status --porcelain)" ]]; then
          \(failureShellCommand(reason: "Refusing update from a dirty git worktree."))
          exit 1
        fi
        if ! git pull --ff-only \(shellQuoted(configuration.remoteName)) \(shellQuoted(configuration.branchName)); then
          \(failureShellCommand(reason: "Failed to fast-forward \(configuration.remoteName)/\(configuration.branchName)."))
          exit 1
        fi
        if ! ./scripts/install_app.sh; then
          \(failureShellCommand(reason: "Failed to install CodexToolbar update."))
          exit 1
        fi
        """
    }

    private func failureShellCommand(reason: String) -> String {
        """
        if [[ -d \(shellQuoted(installedAppPath)) ]]; then
          open \(shellQuoted(installedAppPath)) >/dev/null 2>&1 || true
        fi
        /usr/bin/osascript -e \(shellQuoted(
            NotificationAppleScriptBuilder.script(
                title: updateFailureTitle,
                body: "\(reason) See log: \(logPath)"
            )
        )) >/dev/null 2>&1 || true
        """
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

struct LiveGitUpdateTooling: GitUpdateTooling {
    private let commandBuilder: GitUpdateDetachedCommandBuilder

    init(commandBuilder: GitUpdateDetachedCommandBuilder = GitUpdateDetachedCommandBuilder()) {
        self.commandBuilder = commandBuilder
    }

    func runGit(
        arguments: [String],
        repositoryURL: URL,
        timeoutNanoseconds: UInt64
    ) async throws -> GitCommandResult {
        try await runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["git"] + arguments,
            repositoryURL: repositoryURL,
            timeoutNanoseconds: timeoutNanoseconds
        )
    }

    func launchDetachedUpdate(configuration: GitUpdateRepositoryConfiguration) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.currentDirectoryURL = configuration.repositoryURL
        process.arguments = [
            "nohup",
            "/bin/zsh",
            "-lc",
            commandBuilder.command(for: configuration)
        ]
        try process.run()
    }

    private func runProcess(
        executableURL: URL,
        arguments: [String],
        repositoryURL: URL,
        timeoutNanoseconds: UInt64
    ) async throws -> GitCommandResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = repositoryURL

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let waitTask = Task.detached(priority: .utility) { () -> Int32 in
            process.waitUntilExit()
            return process.terminationStatus
        }

        let firstCompletion = await withTaskGroup(of: (Bool, Int32).self, returning: (Bool, Int32).self) { group in
            group.addTask {
                (false, await waitTask.value)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return (true, 0)
            }

            let first = await group.next() ?? (true, 0)
            group.cancelAll()
            return first
        }

        if firstCompletion.0 {
            if process.isRunning {
                process.terminate()
            }
            _ = await waitTask.value
            throw GitUpdateToolingError.timedOut
        }

        return GitCommandResult(
            exitStatus: firstCompletion.1,
            stdout: String(decoding: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }
}

private enum GitUpdateToolingError: LocalizedError {
    case timedOut

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "Git update command timed out."
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

import Foundation
import XCTest
@testable import CodexToolbar

final class GitUpdateServiceTests: XCTestCase {
    func testCheckForUpdatesReturnsUnsupportedWhenNoAnnotatedReleaseTagsExist() async throws {
        let repositoryURL = try makeTemporaryRepository()
        let tooling = RecordingGitUpdateTooling()
        tooling.setResult(
            GitCommandResult(exitStatus: 0, stdout: "", stderr: ""),
            for: ["fetch", "--tags", "--quiet", "origin"]
        )
        tooling.setResult(
            GitCommandResult(exitStatus: 0, stdout: "commit v0.1.4\n", stderr: ""),
            for: ["for-each-ref", "--format=%(objecttype) %(refname:strip=2)", "refs/tags"]
        )

        let state = await GitUpdateService(tooling: tooling).checkForUpdates(
            currentVersion: "0.1.3",
            configuration: makeConfiguration(repositoryURL: repositoryURL)
        )

        XCTAssertEqual(state, .unsupported("No annotated release tags found."))
    }

    func testCheckForUpdatesReturnsUpToDateWhenLatestTagMatchesInstalledVersion() async throws {
        let repositoryURL = try makeTemporaryRepository()
        let tooling = RecordingGitUpdateTooling()
        tooling.setResult(
            GitCommandResult(exitStatus: 0, stdout: "", stderr: ""),
            for: ["fetch", "--tags", "--quiet", "origin"]
        )
        tooling.setResult(
            GitCommandResult(exitStatus: 0, stdout: "tag v0.1.3\n", stderr: ""),
            for: ["for-each-ref", "--format=%(objecttype) %(refname:strip=2)", "refs/tags"]
        )

        let state = await GitUpdateService(tooling: tooling).checkForUpdates(
            currentVersion: "0.1.3",
            configuration: makeConfiguration(repositoryURL: repositoryURL)
        )

        XCTAssertEqual(state, .upToDate)
    }

    func testCheckForUpdatesReturnsUpdateAvailableWhenNewerTagExists() async throws {
        let repositoryURL = try makeTemporaryRepository()
        let tooling = RecordingGitUpdateTooling()
        tooling.setResult(
            GitCommandResult(exitStatus: 0, stdout: "", stderr: ""),
            for: ["fetch", "--tags", "--quiet", "origin"]
        )
        tooling.setResult(
            GitCommandResult(exitStatus: 0, stdout: "tag v0.1.4\ntag v0.1.3\n", stderr: ""),
            for: ["for-each-ref", "--format=%(objecttype) %(refname:strip=2)", "refs/tags"]
        )

        let state = await GitUpdateService(tooling: tooling).checkForUpdates(
            currentVersion: "0.1.3",
            configuration: makeConfiguration(repositoryURL: repositoryURL)
        )

        XCTAssertEqual(state, .updateAvailable("v0.1.4"))
    }

    func testCheckForUpdatesIgnoresMalformedAndLightweightTags() async throws {
        let repositoryURL = try makeTemporaryRepository()
        let tooling = RecordingGitUpdateTooling()
        tooling.setResult(
            GitCommandResult(exitStatus: 0, stdout: "", stderr: ""),
            for: ["fetch", "--tags", "--quiet", "origin"]
        )
        tooling.setResult(
            GitCommandResult(
                exitStatus: 0,
                stdout: "tag v0.1.2\ncommit v0.9.9\ntag latest\ntag v0.1.4\n",
                stderr: ""
            ),
            for: ["for-each-ref", "--format=%(objecttype) %(refname:strip=2)", "refs/tags"]
        )

        let state = await GitUpdateService(tooling: tooling).checkForUpdates(
            currentVersion: "0.1.3",
            configuration: makeConfiguration(repositoryURL: repositoryURL)
        )

        XCTAssertEqual(state, .updateAvailable("v0.1.4"))
    }

    func testInstallUpdateRejectsDirtyWorktree() async throws {
        let repositoryURL = try makeTemporaryRepository(withInstallScript: true)
        let tooling = RecordingGitUpdateTooling()
        tooling.setResult(
            GitCommandResult(exitStatus: 0, stdout: " M Sources/CodexToolbar/App/CodexToolbarApp.swift\n", stderr: ""),
            for: ["status", "--porcelain"]
        )

        let result = await GitUpdateService(tooling: tooling).installUpdate(
            configuration: makeConfiguration(repositoryURL: repositoryURL)
        )

        XCTAssertEqual(result, .failed("Refusing to update from a dirty git worktree."))
        XCTAssertNil(tooling.launchedConfiguration)
    }

    func testInstallUpdateLaunchesDetachedInstallFromConfiguredRepository() async throws {
        let repositoryURL = try makeTemporaryRepository(withInstallScript: true)
        let tooling = RecordingGitUpdateTooling()
        tooling.setResult(
            GitCommandResult(exitStatus: 0, stdout: "", stderr: ""),
            for: ["status", "--porcelain"]
        )
        let configuration = makeConfiguration(repositoryURL: repositoryURL)

        let result = await GitUpdateService(tooling: tooling).installUpdate(configuration: configuration)

        XCTAssertEqual(result, .started)
        XCTAssertEqual(tooling.launchedConfiguration, configuration)
    }

    private func makeConfiguration(repositoryURL: URL) -> GitUpdateRepositoryConfiguration {
        GitUpdateRepositoryConfiguration(
            repositoryRoot: repositoryURL.path,
            remoteName: "origin",
            branchName: "main"
        )
    }

    private func makeTemporaryRepository(withInstallScript: Bool = false) throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexToolbarTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        if withInstallScript {
            let scriptsURL = rootURL.appendingPathComponent("scripts", isDirectory: true)
            try FileManager.default.createDirectory(at: scriptsURL, withIntermediateDirectories: true)
            let installScriptURL = scriptsURL.appendingPathComponent("install_app.sh")
            try Data("#!/bin/zsh\n".utf8).write(to: installScriptURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installScriptURL.path)
        }

        return rootURL
    }
}

private final class RecordingGitUpdateTooling: @unchecked Sendable, GitUpdateTooling {
    private let queue = DispatchQueue(label: "GitUpdateServiceTests.RecordingGitUpdateTooling")
    private var results: [String: GitCommandResult] = [:]
    private(set) var launchedConfiguration: GitUpdateRepositoryConfiguration?

    func setResult(_ result: GitCommandResult, for arguments: [String]) {
        queue.sync {
            results[key(for: arguments)] = result
        }
    }

    func runGit(
        arguments: [String],
        repositoryURL: URL,
        timeoutNanoseconds: UInt64
    ) async throws -> GitCommandResult {
        queue.sync {
            results[key(for: arguments)] ?? GitCommandResult(exitStatus: 1, stdout: "", stderr: "Unexpected git command.")
        }
    }

    func launchDetachedUpdate(configuration: GitUpdateRepositoryConfiguration) throws {
        queue.sync {
            launchedConfiguration = configuration
        }
    }

    private func key(for arguments: [String]) -> String {
        arguments.joined(separator: "\u{1F}")
    }
}

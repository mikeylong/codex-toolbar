import Darwin
import XCTest
@testable import CodexToolbar

@MainActor
final class ClaudeCLIUsageClientTests: XCTestCase {
    func testProbeArgumentsOnlyRunLocalUsageWithNoToolsOrPersistence() {
        XCTAssertEqual(Array(ClaudeCLIUsageClient.arguments.prefix(4)), ["-p", "/usage", "--output-format", "json"])
        XCTAssertTrue(ClaudeCLIUsageClient.arguments.contains("--no-session-persistence"))
        XCTAssertTrue(ClaudeCLIUsageClient.arguments.contains("--strict-mcp-config"))
        let toolsIndex = ClaudeCLIUsageClient.arguments.firstIndex(of: "--tools")!
        XCTAssertEqual(ClaudeCLIUsageClient.arguments[toolsIndex + 1], "")
    }

    func testDiscoveryHandlesMenuBarAppPathAndDeduplicates() {
        let candidates = ClaudeCLIUsageClient.executableCandidates(environmentPath: "/usr/bin:/bin:/usr/bin",
                                                                   homeDirectory: "/Users/example")
        XCTAssertEqual(candidates.filter { $0 == "/usr/bin/claude" }.count, 1)
        XCTAssertTrue(candidates.contains("/Users/example/.local/bin/claude"))
        XCTAssertTrue(candidates.contains("/opt/homebrew/bin/claude"))
    }

    func testAuthenticationPreflightDistinguishesLogoutFromUnavailableStatus() throws {
        XCTAssertThrowsError(try ClaudeCLIUsageClient.validateAuthentication(Data(#"{"loggedIn":false,"authMethod":"none"}"#.utf8), exitStatus: 1)) {
            XCTAssertEqual($0 as? ClaudeUsageError, .notAuthenticated)
        }
        XCTAssertThrowsError(try ClaudeCLIUsageClient.validateAuthentication(Data("permission denied".utf8), exitStatus: 1)) {
            XCTAssertEqual($0 as? ClaudeUsageError, .unsupportedResponse)
        }
        XCTAssertThrowsError(try ClaudeCLIUsageClient.validateAuthentication(Data(#"{"loggedIn":true,"authMethod":"api_key"}"#.utf8), exitStatus: 0)) {
            XCTAssertEqual($0 as? ClaudeUsageError, .notSubscription)
        }
        XCTAssertNoThrow(try ClaudeCLIUsageClient.validateAuthentication(Data(#"{"loggedIn":true,"authMethod":"claude.ai"}"#.utf8), exitStatus: 0))
    }

    func testRunnerReadsBothPipesAndExitStatus() throws {
        let result = try runShell("printf success; printf diagnostic >&2; exit 7")
        XCTAssertEqual(String(decoding: result.stdout, as: UTF8.self), "success")
        XCTAssertEqual(String(decoding: result.stderr, as: UTF8.self), "diagnostic")
        XCTAssertEqual(result.exitStatus, 7)
    }

    func testTimeoutKillsAndReapsChildIgnoringTermination() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("pid")
        let started = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try runShell("trap '' TERM; echo $$ > \"$1\"; while :; do :; done",
                                         extraArguments: [pidFile.path], timeout: 0.15)) {
            XCTAssertEqual($0 as? ClaudeUsageError, .timedOut)
        }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 2)
        try assertReaped(pidFile)
    }

    func testOutputLimitTerminatesAndReapsFloodingChild() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("pid")
        XCTAssertThrowsError(try runShell("echo $$ > \"$1\"; while :; do printf '0123456789abcdef'; done",
                                         extraArguments: [pidFile.path], outputLimit: 4096)) {
            XCTAssertEqual($0 as? ClaudeUsageError, .outputLimitExceeded)
        }
        try assertReaped(pidFile)
    }

    func testClosedPipesDoNotPreventTimeoutAndReaping() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("pid")
        let started = ProcessInfo.processInfo.systemUptime
        XCTAssertThrowsError(try runShell("echo $$ > \"$1\"; exec 1>&- 2>&-; trap '' TERM; while :; do :; done",
                                         extraArguments: [pidFile.path], timeout: 0.15)) {
            XCTAssertEqual($0 as? ClaudeUsageError, .timedOut)
        }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 2)
        try assertReaped(pidFile)
    }

    func testCancellationStopsAndReapsRunningChild() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("pid")
        let runner = ClaudeUsageProcessRunner()
        let task = Task.detached {
            try runner.run(executable: URL(fileURLWithPath: "/bin/sh"),
                           arguments: ["-c", "trap '' TERM; echo $$ > \"$1\"; while :; do :; done", "probe", pidFile.path],
                           environment: ["PATH": "/usr/bin:/bin"], directory: directory, timeout: 10, outputLimit: 4096)
        }
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: pidFile.path) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        runner.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
        catch { XCTFail("Unexpected error: \(error)") }
        try assertReaped(pidFile)
    }

    func testClientUsesIsolatedDirectoryAndDoesNotRetainReportInsights() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("fake-claude")
        let report = """
        #!/bin/sh
        test "$DISABLE_AUTOUPDATER" = 1 || exit 8
        if test "$1" = auth; then
          printf '%s' '{"loggedIn":true,"authMethod":"claude.ai"}'
          exit 0
        fi
        printf '%s' '{"type":"result","local_command":"usage","subtype":"success","is_error":false,"num_turns":0,"duration_api_ms":0,"total_cost_usd":0,"result":"Current session: 12% used\\n\\nWhat’s contributing to your usage?\\nPrivate project insight"}'
        """
        try report.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let working = directory.appendingPathComponent("probe", isDirectory: true)
        let client = ClaudeCLIUsageClient(executableURL: script, workingDirectory: working)
        let snapshot = try await client.readUsage()
        XCTAssertEqual(snapshot.windows.map(\.usedPercent), [12])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: working.path), [])
    }

    func testSynchronousTerminationReapsAuthChildWithoutActorResumption() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("fake-claude")
        let working = directory.appendingPathComponent("probe", isDirectory: true)
        try """
        #!/bin/sh
        if test "$1" = auth; then
          trap '' TERM
          echo $$ > auth-pid
          while :; do :; done
        fi
        echo unexpected > usage-started
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let client = ClaudeCLIUsageClient(executableURL: script, workingDirectory: working)
        let request = Task { try await client.readUsage() }
        let pidFile = working.appendingPathComponent("auth-pid")
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: pidFile.path) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let started = ProcessInfo.processInfo.systemUptime
        XCTAssertTrue(client.cancelForTermination())
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 1.2)
        // Assert before yielding the main actor. Process cleanup must not depend
        // on the suspended request or an AppKit-loop task getting to resume.
        try assertReaped(pidFile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: working.appendingPathComponent("usage-started").path))
        do { _ = try await request.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
        catch { XCTFail("Unexpected error: \(error)") }
        do { _ = try await client.readUsage(); XCTFail("Shutdown client must not launch again") }
        catch is CancellationError { }
        catch { XCTFail("Unexpected error: \(error)") }
    }

    func testTerminationBeforeWorkerStartsPreventsSpawn() throws {
        let runner = ClaudeUsageProcessRunner()
        runner.cancel()
        XCTAssertTrue(runner.waitUntilStopped(deadline: Date(timeIntervalSinceNow: 0.01)))
        XCTAssertThrowsError(try runner.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "exit 99"],
                                           environment: [:], directory: FileManager.default.temporaryDirectory,
                                           timeout: 2, outputLimit: 4096)) {
            XCTAssertTrue($0 is CancellationError)
        }
    }

    func testLiveClaudeUsageWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["CODEX_TOOLBAR_LIVE_CLAUDE_USAGE"] == "1" else {
            throw XCTSkip("Set CODEX_TOOLBAR_LIVE_CLAUDE_USAGE=1 to verify the signed-in local CLI.")
        }
        let snapshot = try await ClaudeCLIUsageClient().readUsage()
        XCTAssertFalse(snapshot.windows.isEmpty)
        for window in snapshot.windows {
            XCTAssertTrue((0...100).contains(window.usedPercent))
            print("Claude quota: \(window.title): \(window.usedPercent)% used; \(window.resetDescription ?? "reset unavailable")")
        }
    }

    private func runShell(_ script: String, extraArguments: [String] = [], timeout: TimeInterval = 2,
                          outputLimit: Int = 4096) throws -> ClaudeUsageProcessResult {
        try ClaudeUsageProcessRunner().run(executable: URL(fileURLWithPath: "/bin/sh"),
                                          arguments: ["-c", script, "probe"] + extraArguments,
                                          environment: ["PATH": "/usr/bin:/bin"],
                                          directory: FileManager.default.temporaryDirectory,
                                          timeout: timeout, outputLimit: outputLimit)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("codextoolbar-claude-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.resolvingSymlinksInPath()
    }

    private func assertReaped(_ pidFile: URL) throws {
        let pid = try XCTUnwrap(Int32(String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertEqual(kill(pid, 0), -1)
        XCTAssertEqual(errno, ESRCH)
        var status: Int32 = 0
        XCTAssertEqual(waitpid(pid, &status, WNOHANG), -1)
        XCTAssertEqual(errno, ECHILD)
    }
}

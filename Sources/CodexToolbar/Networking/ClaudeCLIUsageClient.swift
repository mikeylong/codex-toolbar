import Darwin
import Foundation

protocol ClaudeUsageClient: Sendable {
    func readUsage() async throws -> ClaudeUsageSnapshot
    /// Synchronously stop owned processes before AppKit terminates its run loop.
    /// False means cleanup has not completed within the bounded wait.
    nonisolated func cancelForTermination() -> Bool
}

extension ClaudeUsageClient {
    nonisolated func cancelForTermination() -> Bool { true }
}

actor ClaudeCLIUsageClient: ClaudeUsageClient {
    private let executableURL: URL?
    private let workingDirectory: URL
    private let timeout: TimeInterval
    private let outputLimit: Int
    private nonisolated let termination = ClaudeUsageTerminationController()

    init(
        executableURL: URL? = nil,
        workingDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexToolbar/ClaudeUsageProbe", isDirectory: true),
        timeout: TimeInterval = 30,
        outputLimit: Int = 1_048_576
    ) {
        self.executableURL = executableURL
        self.workingDirectory = workingDirectory
        self.timeout = timeout
        self.outputLimit = outputLimit
    }

    func readUsage() async throws -> ClaudeUsageSnapshot {
        try Task.checkCancellation()
        guard !termination.isClosing else { throw CancellationError() }
        let executable = try executableURL ?? Self.locateCLI()
        // This directory contains no project source. Never follow an existing redirect
        // into a user's project when Claude initializes its local command context.
        guard workingDirectory.standardizedFileURL.path == workingDirectory.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw ClaudeUsageError.launchFailed
        }
        do {
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch { throw ClaudeUsageError.launchFailed }
        var environment = ProcessInfo.processInfo.environment
        environment["DISABLE_AUTOUPDATER"] = "1"
        environment["PATH"] = executable.deletingLastPathComponent().path + ":" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        let auth = try await runCommand(executable: executable, arguments: ["auth", "status"], environment: environment)
        try Self.validateAuthentication(auth.stdout, exitStatus: auth.exitStatus)
        try Task.checkCancellation()
        let result = try await runCommand(executable: executable, arguments: Self.arguments, environment: environment)
        try Task.checkCancellation()
        if result.exitStatus != 0 {
            let diagnostic = String(decoding: result.stderr, as: UTF8.self) + String(decoding: result.stdout, as: UTF8.self)
            throw ClaudeUsageParser.reportsAuthenticationFailure(diagnostic) ? ClaudeUsageError.notAuthenticated : .commandFailed
        }
        // Decode only in memory. /usage also contains private project insights; the
        // app retains only quota windows and never logs the CLI payload.
        return try ClaudeUsageParser.parse(result.stdout)
    }

    private func runCommand(executable: URL, arguments: [String], environment: [String: String]) async throws -> ClaudeUsageProcessResult {
        let runner = ClaudeUsageProcessRunner()
        try termination.register(runner)
        let termination = termination
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .utility) {
                defer { termination.unregister(runner) }
                return try runner.run(executable: executable, arguments: arguments, environment: environment,
                               directory: self.workingDirectory, timeout: self.timeout, outputLimit: self.outputLimit)
            }.value
        } onCancel: {
            runner.cancel()
        }
    }

    nonisolated func cancelForTermination() -> Bool {
        termination.cancelAndWait(timeout: 1)
    }

    nonisolated static func validateAuthentication(_ data: Data, exitStatus: Int32) throws {
        struct AuthStatus: Decodable {
            let loggedIn: Bool
            let authMethod: String?
        }
        guard let auth = try? JSONDecoder().decode(AuthStatus.self, from: data) else {
            throw ClaudeUsageError.unsupportedResponse
        }
        guard auth.loggedIn else { throw ClaudeUsageError.notAuthenticated }
        guard exitStatus == 0 else { throw ClaudeUsageError.commandFailed }
        switch auth.authMethod {
        case "claude.ai", "oauth_token": break
        case "api_key", "api_key_helper", "third_party": throw ClaudeUsageError.notSubscription
        default: throw ClaudeUsageError.unsupportedResponse
        }
    }

    nonisolated static let arguments = [
        "-p", "/usage", "--output-format", "json", "--no-session-persistence",
        "--tools", "", "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}",
        "--setting-sources", "", "--settings", "{\"disableAllHooks\":true,\"remoteControlAtStartup\":false}",
        "--max-budget-usd", "0.000001"
    ]

    nonisolated static func executableCandidates(environmentPath: String, homeDirectory: String) -> [String] {
        let paths = environmentPath.split(separator: ":").map { "\($0)/claude" } + [
            "\(homeDirectory)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"
        ]
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }

    private nonisolated static func locateCLI() throws -> URL {
        guard let executable = executableCandidates(environmentPath: ProcessInfo.processInfo.environment["PATH"] ?? "",
                                                    homeDirectory: FileManager.default.homeDirectoryForCurrentUser.path)
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw ClaudeUsageError.cliNotFound
        }
        return URL(fileURLWithPath: executable)
    }
}

/// Closing and registering are atomic: shutdown cannot miss a worker between the
/// auth and usage commands, or between scheduling a worker and its first spawn.
private final class ClaudeUsageTerminationController: @unchecked Sendable {
    private let lock = NSLock()
    private var closing = false
    private var runners: [ObjectIdentifier: ClaudeUsageProcessRunner] = [:]

    var isClosing: Bool { lock.withLock { closing } }

    func register(_ runner: ClaudeUsageProcessRunner) throws {
        try lock.withLock {
            guard !closing else { throw CancellationError() }
            runners[ObjectIdentifier(runner)] = runner
        }
    }

    func unregister(_ runner: ClaudeUsageProcessRunner) {
        _ = lock.withLock { runners.removeValue(forKey: ObjectIdentifier(runner)) }
    }

    func cancelAndWait(timeout: TimeInterval) -> Bool {
        let active = lock.withLock {
            closing = true
            return Array(runners.values)
        }
        active.forEach { $0.cancel() }
        let deadline = Date(timeIntervalSinceNow: timeout)
        return active.allSatisfy { $0.waitUntilStopped(deadline: deadline) }
    }
}

struct ClaudeUsageProcessResult: Sendable {
    let stdout: Data
    let stderr: Data
    let exitStatus: Int32
}

/// Runs only the local usage command. A private process group lets timeout and
/// cancellation stop descendants without touching other Claude sessions.
final class ClaudeUsageProcessRunner: @unchecked Sendable {
    private let condition = NSCondition()
    private var cancelled = false
    private var running = false

    func cancel() { condition.withLock { cancelled = true } }
    private var isCancelled: Bool { condition.withLock { cancelled } }

    func waitUntilStopped(deadline: Date) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        while running {
            if !condition.wait(until: deadline) { return !running }
        }
        // A pending worker is safe too: cancel() and the run-entry check use this
        // same lock, so it cannot spawn after cancellation returned success.
        return true
    }

    func run(executable: URL, arguments: [String], environment: [String: String], directory: URL,
             timeout: TimeInterval, outputLimit: Int) throws -> ClaudeUsageProcessResult {
        try condition.withLock {
            if cancelled { throw CancellationError() }
            running = true
        }
        defer {
            // Declared before process/descriptor defers: signal completion only
            // after the child has been killed/reaped and all handles are closed.
            condition.withLock {
                running = false
                condition.broadcast()
            }
        }
        var stdoutPipe: [Int32] = [0, 0]
        var stderrPipe: [Int32] = [0, 0]
        guard pipe(&stdoutPipe) == 0 else { throw ClaudeUsageError.launchFailed }
        defer { stdoutPipe.filter { $0 >= 0 }.forEach { close($0) } }
        guard pipe(&stderrPipe) == 0 else { throw ClaudeUsageError.launchFailed }
        defer { stderrPipe.filter { $0 >= 0 }.forEach { close($0) } }
        guard fcntl(stdoutPipe[0], F_SETFL, O_NONBLOCK) == 0,
              fcntl(stderrPipe[0], F_SETFL, O_NONBLOCK) == 0 else { throw ClaudeUsageError.launchFailed }

        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { throw ClaudeUsageError.launchFailed }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawnattr_init(&attributes) == 0 else { throw ClaudeUsageError.launchFailed }
        defer { posix_spawnattr_destroy(&attributes) }
        let setupResults = [
            posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0),
            posix_spawn_file_actions_adddup2(&actions, stdoutPipe[1], STDOUT_FILENO),
            posix_spawn_file_actions_adddup2(&actions, stderrPipe[1], STDERR_FILENO),
            posix_spawn_file_actions_addchdir_np(&actions, directory.path),
            posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)),
            posix_spawnattr_setpgroup(&attributes, 0)
        ]
        guard setupResults.allSatisfy({ $0 == 0 }) else { throw ClaudeUsageError.launchFailed }
        let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        let envp = environment.keys.sorted().map { strdup("\($0)=\(environment[$0]!)") } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        var pid: pid_t = 0
        let spawnResult = argv.withUnsafeBufferPointer { args in
            envp.withUnsafeBufferPointer { env in
                posix_spawn(&pid, executable.path, &actions, &attributes,
                            UnsafeMutablePointer(mutating: args.baseAddress!), UnsafeMutablePointer(mutating: env.baseAddress!))
            }
        }
        guard spawnResult == 0 else { throw ClaudeUsageError.launchFailed }
        close(stdoutPipe[1]); stdoutPipe[1] = -1
        close(stderrPipe[1]); stderrPipe[1] = -1

        var reaped = false
        defer {
            // Also remove a descendant that outlived the main command. The child was
            // atomically placed in this group by posix_spawn, never a shared group.
            kill(-pid, SIGKILL)
            if !reaped {
                var status: Int32 = 0
                while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
            }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + max(0, timeout)
        var stdout = Data()
        var stderr = Data()
        var status: Int32 = 0
        var failure: Error?
        var terminationDeadline: TimeInterval?
        while true {
            let now = ProcessInfo.processInfo.systemUptime
            if failure == nil {
                if isCancelled { failure = CancellationError() }
                else if now >= deadline { failure = ClaudeUsageError.timedOut }
            }
            if failure != nil && terminationDeadline == nil {
                kill(-pid, SIGTERM)
                terminationDeadline = now + 0.2
            }
            if let terminationDeadline, now >= terminationDeadline { kill(-pid, SIGKILL) }

            do {
                try drain(stdoutPipe[0], into: &stdout, totalOtherBytes: stderr.count, limit: outputLimit)
                try drain(stderrPipe[0], into: &stderr, totalOtherBytes: stdout.count, limit: outputLimit)
            } catch { if failure == nil { failure = error } }

            let waitResult = waitpid(pid, &status, WNOHANG)
            if waitResult == pid {
                reaped = true
                // Remaining bytes are already in nonblocking pipes. Descendants
                // holding an open pipe cannot keep the command alive here.
                if failure == nil {
                    try drain(stdoutPipe[0], into: &stdout, totalOtherBytes: stderr.count, limit: outputLimit)
                    try drain(stderrPipe[0], into: &stderr, totalOtherBytes: stdout.count, limit: outputLimit)
                }
                break
            }
            if waitResult < 0 && errno != EINTR { throw ClaudeUsageError.commandFailed }
            var descriptors = [pollfd(fd: stdoutPipe[0], events: Int16(POLLIN), revents: 0),
                               pollfd(fd: stderrPipe[0], events: Int16(POLLIN), revents: 0)]
            _ = poll(&descriptors, nfds_t(descriptors.count), 20)
            if descriptors.contains(where: { $0.revents & Int16(POLLHUP) != 0 }) {
                // EOF remains immediately ready for poll. A child can close its
                // output and stay alive, so don't spin while waiting to reap it.
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
        if let failure { throw failure }
        let exitStatus: Int32 = status & 0x7f == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
        return ClaudeUsageProcessResult(stdout: stdout, stderr: stderr, exitStatus: exitStatus)
    }

    private func drain(_ descriptor: Int32, into data: inout Data, totalOtherBytes: Int, limit: Int) throws {
        var buffer = [UInt8](repeating: 0, count: 8192)
        // Limit each drain pass too, so a child continuously writing cannot starve
        // cancellation or timeout processing even with a large output allowance.
        for _ in 0..<16 {
            let count = read(descriptor, &buffer, buffer.count)
            if count > 0 {
                guard data.count + count + totalOtherBytes <= limit else { throw ClaudeUsageError.outputLimitExceeded }
                data.append(contentsOf: buffer.prefix(count))
            } else if count == 0 || errno == EAGAIN || errno == EWOULDBLOCK { return }
            else if errno != EINTR { throw ClaudeUsageError.commandFailed }
        }
    }
}

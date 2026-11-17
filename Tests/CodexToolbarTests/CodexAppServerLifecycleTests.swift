import Darwin
import Foundation
import XCTest
@testable import CodexToolbar

final class CodexAppServerLifecycleTests: XCTestCase {
    @MainActor
    func testCancelledSubscriptionRenewsAndOldProcessExitCannotDisconnectReplacement() async throws {
        let fixture = try DelayedCodexServerFixture()
        defer { fixture.cleanUp() }
        let client = CodexAppServerClient(executablePath: fixture.executable.path)
        let log = CodexLifecycleEventLog()
        let watchdog = Task {
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            fixture.releaseAllGates()
            await client.disconnect()
        }
        defer { watchdog.cancel() }

        do {
            let firstEvents = client.events()
            let firstConsumer = Task {
                for await event in firstEvents { await log.record(event) }
            }
            defer { firstConsumer.cancel() }
            fixture.phase("Connecting first child")
            try await client.connect()
            fixture.phase("Waiting for first update")
            try await Self.waitUntil { await log.usedPercentages.contains(10) }
            firstConsumer.cancel()
            await firstConsumer.value
            await client.disconnect()
            fixture.phase("Waiting for first termination handler")
            try await Self.waitUntil { fixture.exists("first-stopping") }

            let secondEvents = client.events()
            let secondConsumer = Task {
                for await event in secondEvents { await log.record(event) }
            }
            defer { secondConsumer.cancel() }
            fixture.phase("Connecting second child")
            try await client.connect()
            fixture.phase("Waiting for second update")
            try await Self.waitUntil { await log.usedPercentages.contains(20) }

            // Hold a request in the new connection while the old child exits.
            // Its termination and final stdout callbacks must not clear the new
            // pipes, fail the pending response, or publish a stale update.
            let read = Task { try await client.readAccount(refreshToken: false) }
            fixture.phase("Waiting for second read")
            try await Self.waitUntil { fixture.exists("second-reading") }
            fixture.release("allow-first-exit")
            fixture.phase("Waiting for first child exit")
            try await Self.waitUntil { !fixture.processIsRunning(number: 1) }
            try await Task.sleep(for: .milliseconds(100))
            fixture.release("allow-second-response")
            fixture.phase("Waiting for second response")
            let account = try await read.value

            XCTAssertEqual(account.account, .chatgpt(email: "fixture@example.com", planType: .pro))
            let percentages = await log.usedPercentages
            let disconnects = await log.disconnectCount
            XCTAssertFalse(percentages.contains(99))
            XCTAssertEqual(disconnects, 0)
            await client.disconnect()
            fixture.phase("Waiting for second child exit")
            try await Self.waitUntil { !fixture.processIsRunning(number: 2) }
        } catch {
            let failure = "Codex lifecycle regression failed: \(String(reflecting: error)).\n\(fixture.diagnostics())"
            fixture.releaseAllGates()
            await client.disconnect()
            XCTFail(failure)
        }
    }

    private static func waitUntil(
        _ condition: @escaping @Sendable () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw LifecycleTestError.timedOut
    }
}

private enum LifecycleTestError: Error {
    case timedOut
}

private actor CodexLifecycleEventLog {
    private(set) var usedPercentages: [Int] = []
    private(set) var disconnectCount = 0

    func record(_ event: CodexAppServerEvent) {
        switch event {
        case let .rateLimitsUpdated(response):
            if let usedPercent = response.rateLimits.primary?.usedPercent { usedPercentages.append(usedPercent) }
        case .disconnected:
            disconnectCount += 1
        case .stderr:
            break
        }
    }
}

private struct DelayedCodexServerFixture: Sendable {
    let directory: URL
    let executable: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("codex-lifecycle-\(UUID().uuidString)")
        executable = directory.appendingPathComponent("codex")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = #"""
        #!/usr/bin/env python3
        import json, os, signal, sys, time
        from pathlib import Path
        root = Path(__file__).parent
        counter = root / 'counter'
        number = int(counter.read_text()) + 1 if counter.exists() else 1
        counter.write_text(str(number))
        (root / ('pid-' + str(number))).write_text(str(os.getpid()))
        sys.stderr = open(root / ('stderr-' + str(number)), 'w', buffering=1)
        requests = open(root / ('requests-' + str(number)), 'w', buffering=1)
        def wait_for(name):
            deadline = time.monotonic() + 10
            while not (root / name).exists() and time.monotonic() < deadline:
                time.sleep(0.01)
        def update(used):
            (root / ('updates-' + str(number))).write_text(str(used))
            print(json.dumps({'method': 'account/rateLimits/updated', 'params': {'rateLimits': {
                'primary': {'usedPercent': used, 'windowDurationMins': 300}
            }}}), flush=True)
        def terminate(signum, frame):
            if number == 1:
                (root / 'first-stopping').touch()
                wait_for('allow-first-exit')
                update(99)
            sys.exit(0)
        signal.signal(signal.SIGTERM, terminate)
        for line in sys.stdin:
            requests.write(line)
            message = json.loads(line)
            method = message.get('method')
            if method == 'initialize':
                print(json.dumps({'id': message['id'], 'result': {'userAgent': 'fixture'}}), flush=True)
            elif method == 'initialized':
                update(number * 10)
            elif method == 'account/read':
                if number == 2:
                    (root / 'second-reading').touch()
                    wait_for('allow-second-response')
                print(json.dumps({'id': message['id'], 'result': {
                    'account': {'type': 'chatgpt', 'email': 'fixture@example.com', 'planType': 'pro'},
                    'requiresOpenaiAuth': False
                }}), flush=True)
        """#
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }

    func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
    }

    func release(_ name: String) {
        FileManager.default.createFile(atPath: directory.appendingPathComponent(name).path, contents: Data())
    }

    func releaseAllGates() {
        release("allow-first-exit")
        release("allow-second-response")
    }

    func phase(_ description: String) {
        FileManager.default.createFile(atPath: directory.appendingPathComponent("phase").path, contents: Data(description.utf8))
    }

    func diagnostics() -> String {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0 != "codex" }.sorted().map { name in
            let data = FileManager.default.contents(atPath: directory.appendingPathComponent(name).path) ?? Data()
            return "\(name): \(String(decoding: data, as: UTF8.self))"
        }.joined(separator: "\n")
    }

    func processIsRunning(number: Int) -> Bool {
        guard let pid = processID(number: number) else { return false }
        return kill(pid, 0) == 0
    }

    func cleanUp() {
        releaseAllGates()
        for number in 1...2 {
            if let pid = processID(number: number), pid > 1, pid != getpid() { kill(pid, SIGKILL) }
        }
        try? FileManager.default.removeItem(at: directory)
    }

    private func processID(number: Int) -> pid_t? {
        let path = directory.appendingPathComponent("pid-\(number)").path
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

import Foundation

protocol CodexRateLimitClient: Sendable {
    func events() -> AsyncStream<CodexAppServerEvent>
    func connect() async throws
    func disconnect() async
    func readAccount() async throws -> GetAccountResponse
    func readRateLimits() async throws -> GetAccountRateLimitsResponse
    func loadSnapshot() async throws -> (GetAccountResponse, GetAccountRateLimitsResponse)
}

enum CodexAppServerEvent: Sendable {
    case rateLimitsUpdated(GetAccountRateLimitsResponse)
    case disconnected(String?)
    case stderr(String)
}

enum CodexAppServerError: LocalizedError, Sendable, Equatable {
    case codexCLINotFound
    case invalidResponse
    case serverError(String)
    case transportClosed

    var errorDescription: String? {
        switch self {
        case .codexCLINotFound:
            return "Codex CLI was not found in PATH."
        case .invalidResponse:
            return "Codex app-server returned an invalid response."
        case let .serverError(message):
            return message
        case .transportClosed:
            return "Codex app-server connection closed."
        }
    }
}

actor CodexAppServerClient: CodexRateLimitClient {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let eventStream: AsyncStream<CodexAppServerEvent>
    private let eventContinuation: AsyncStream<CodexAppServerEvent>.Continuation

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var pendingResponses: [String: CheckedContinuation<Data, Error>] = [:]
    private var stdoutTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private var idCounter = 0
    private var isConnected = false

    init() {
        var continuation: AsyncStream<CodexAppServerEvent>.Continuation!
        eventStream = AsyncStream { streamContinuation in
            continuation = streamContinuation
        }
        eventContinuation = continuation
    }

    nonisolated func events() -> AsyncStream<CodexAppServerEvent> {
        eventStream
    }

    func connect() async throws {
        if isConnected {
            return
        }

        let codexPath = try Self.locateCodexCLI()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server", "--listen", "stdio://"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.terminationHandler = { [weak self] terminatedProcess in
            Task {
                await self?.handleTermination(status: terminatedProcess.terminationStatus)
            }
        }

        try process.run()

        self.process = process
        stdinHandle = stdinPipe.fileHandleForWriting
        isConnected = true

        stdoutTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
                    await self.handleStdoutLine(String(line))
                }
            } catch {
                await self.finishPendingResponses(with: CodexAppServerError.transportClosed)
            }
        }

        stderrTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await line in stderrPipe.fileHandleForReading.bytes.lines {
                    self.eventContinuation.yield(.stderr(String(line)))
                }
            } catch {
                self.eventContinuation.yield(.stderr("Failed to read Codex app-server stderr."))
            }
        }

        try await sendInitializeHandshake()
    }

    func disconnect() async {
        stdoutTask?.cancel()
        stderrTask?.cancel()
        stdoutTask = nil
        stderrTask = nil

        if let process, process.isRunning {
            process.terminate()
        }

        process = nil
        stdinHandle = nil
        isConnected = false
        finishPendingResponses(with: CodexAppServerError.transportClosed)
    }

    func readAccount() async throws -> GetAccountResponse {
        try await request(
            method: "account/read",
            params: AccountReadParams(refreshToken: false),
            responseType: GetAccountResponse.self
        )
    }

    func readRateLimits() async throws -> GetAccountRateLimitsResponse {
        try await request(
            method: "account/rateLimits/read",
            params: JSONNull(),
            responseType: GetAccountRateLimitsResponse.self
        )
    }

    func loadSnapshot() async throws -> (GetAccountResponse, GetAccountRateLimitsResponse) {
        let codexPath = try Self.locateCodexCLI()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server", "--listen", "stdio://"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
            }
        }

        let requests: [Data] = try [
            encoder.encode(JSONRPCRequest(
                id: "1",
                method: "initialize",
                params: InitializeParams(
                    clientInfo: ClientInfo(name: "CodexToolbar", version: "0.1.0"),
                    capabilities: InitializeCapabilities(experimentalApi: true, optOutNotificationMethods: nil)
                )
            )),
            encoder.encode(JSONRPCNotification(method: "initialized", params: Optional<JSONNull>.none)),
            encoder.encode(JSONRPCRequest(id: "2", method: "account/read", params: AccountReadParams(refreshToken: false))),
            encoder.encode(JSONRPCRequest(id: "3", method: "account/rateLimits/read", params: JSONNull()))
        ]

        for payload in requests {
            var line = payload
            line.append(0x0A)
            try stdinPipe.fileHandleForWriting.write(contentsOf: line)
        }

        var account: GetAccountResponse?
        var rateLimits: GetAccountRateLimitsResponse?
        let deadline = Date().addingTimeInterval(5)

        for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
            guard let data = String(line).data(using: .utf8) else { continue }
            guard
                let jsonObject = try? JSONSerialization.jsonObject(with: data),
                let message = jsonObject as? [String: Any],
                let id = message["id"] as? String,
                let result = message["result"]
            else {
                if Date() > deadline { break }
                continue
            }

            let resultData = try JSONSerialization.data(withJSONObject: result)

            switch id {
            case "2":
                account = try decoder.decode(GetAccountResponse.self, from: resultData)
            case "3":
                rateLimits = try decoder.decode(GetAccountRateLimitsResponse.self, from: resultData)
            default:
                break
            }

            if let account, let rateLimits {
                return (account, rateLimits)
            }

            if Date() > deadline {
                break
            }
        }

        let stderr = try? String(decoding: stderrPipe.fileHandleForReading.readToEnd() ?? Data(), as: UTF8.self)
        throw CodexAppServerError.serverError(stderr?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Timed out reading Codex rate limits.")
    }

    private func sendInitializeHandshake() async throws {
        let params = InitializeParams(
            clientInfo: ClientInfo(name: "CodexToolbar", version: "0.1.0"),
            capabilities: InitializeCapabilities(experimentalApi: true, optOutNotificationMethods: nil)
        )

        _ = try await request(method: "initialize", params: params, responseType: InitializeResponse.self)
        try await sendNotification(method: "initialized", params: nil as JSONNull?)
    }

    private func request<Params: Encodable, Response: Decodable>(
        method: String,
        params: Params,
        responseType: Response.Type
    ) async throws -> Response {
        let id = nextID()
        let request = JSONRPCRequest(id: id, method: method, params: params)
        let payload = try encoder.encode(request)

        let responseData = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            pendingResponses[id] = continuation
            do {
                try write(payload)
            } catch {
                pendingResponses.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }

        do {
            return try decoder.decode(Response.self, from: responseData)
        } catch {
            throw CodexAppServerError.invalidResponse
        }
    }

    private func sendNotification<Params: Encodable>(method: String, params: Params?) async throws {
        let notification = JSONRPCNotification(method: method, params: params)
        let payload = try encoder.encode(notification)
        try write(payload)
    }

    private func write(_ payload: Data) throws {
        guard let stdinHandle else {
            throw CodexAppServerError.transportClosed
        }

        var linePayload = payload
        linePayload.append(0x0A)
        try stdinHandle.write(contentsOf: linePayload)
    }

    private func handleStdoutLine(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        guard
            let jsonObject = try? JSONSerialization.jsonObject(with: data),
            let message = jsonObject as? [String: Any]
        else {
            return
        }

        if let id = message["id"] as? String {
            if let errorObject = message["error"] as? [String: Any] {
                let message = errorObject["message"] as? String ?? "Codex app-server request failed."
                pendingResponses.removeValue(forKey: id)?.resume(throwing: CodexAppServerError.serverError(message))
                return
            }

            guard let result = message["result"] else {
                pendingResponses.removeValue(forKey: id)?.resume(throwing: CodexAppServerError.invalidResponse)
                return
            }

            do {
                let resultData = try JSONSerialization.data(withJSONObject: result)
                pendingResponses.removeValue(forKey: id)?.resume(returning: resultData)
            } catch {
                pendingResponses.removeValue(forKey: id)?.resume(throwing: CodexAppServerError.invalidResponse)
            }

            return
        }

        guard let method = message["method"] as? String else {
            return
        }

        if method == "account/rateLimits/updated",
           let params = message["params"]
        {
            do {
                let paramsData = try JSONSerialization.data(withJSONObject: params)
                let update = try decoder.decode(AccountRateLimitsUpdatedNotification.self, from: paramsData)
                eventContinuation.yield(.rateLimitsUpdated(GetAccountRateLimitsResponse(rateLimits: update.rateLimits, rateLimitsByLimitId: nil)))
            } catch {
                eventContinuation.yield(.stderr("Failed to decode rate-limit update."))
            }
        }
    }

    private func handleTermination(status: Int32) {
        guard isConnected else { return }
        isConnected = false
        process = nil
        stdinHandle = nil
        stdoutTask?.cancel()
        stderrTask?.cancel()
        stdoutTask = nil
        stderrTask = nil
        finishPendingResponses(with: CodexAppServerError.transportClosed)

        let reason = status == 0 ? nil : "Codex app-server exited with status \(status)."
        eventContinuation.yield(.disconnected(reason))
    }

    private func finishPendingResponses(with error: Error) {
        let continuations = pendingResponses.values
        pendingResponses.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
    }

    private func nextID() -> String {
        idCounter += 1
        return "req-\(idCounter)"
    }

    private static func locateCodexCLI() throws -> String {
        for candidate in codexPathCandidates(
            environmentPath: ProcessInfo.processInfo.environment["PATH"] ?? "",
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser.path
        ) {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        throw CodexAppServerError.codexCLINotFound
    }

    nonisolated static func codexPathCandidates(environmentPath: String, homeDirectory: String) -> [String] {
        let pathCandidates = environmentPath.split(separator: ":").map { pathComponent in
            URL(fileURLWithPath: String(pathComponent)).appendingPathComponent("codex").path
        }

        let fallbackCandidates = [
            URL(fileURLWithPath: homeDirectory).appendingPathComponent(".local/bin/codex").path,
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex"
        ]

        var seen = Set<String>()
        let orderedCandidates = pathCandidates + fallbackCandidates

        return orderedCandidates.filter { candidate in
            seen.insert(candidate).inserted
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct JSONRPCRequest<Params: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: String
    let method: String
    let params: Params
}

private struct JSONRPCNotification<Params: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let method: String
    let params: Params?
}

private struct JSONNull: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encodeNil()
    }
}

private struct InitializeParams: Encodable {
    let clientInfo: ClientInfo
    let capabilities: InitializeCapabilities?
}

private struct ClientInfo: Encodable {
    let name: String
    let version: String
}

private struct InitializeCapabilities: Encodable {
    let experimentalApi: Bool
    let optOutNotificationMethods: [String]?
}

private struct InitializeResponse: Decodable {
    let userAgent: String
}

private struct AccountReadParams: Encodable {
    let refreshToken: Bool
}

private struct AccountRateLimitsUpdatedNotification: Decodable {
    let rateLimits: CodexRateLimitsSnapshot
}

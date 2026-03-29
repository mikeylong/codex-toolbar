import Foundation

protocol OpenAIUsageClient: Sendable {
    func readCosts(
        adminKey: String,
        startTime: Int64,
        endTime: Int64,
        limit: Int
    ) async throws -> [OpenAICostBucket]

    func readCompletionsUsage(
        adminKey: String,
        startTime: Int64,
        endTime: Int64,
        limit: Int
    ) async throws -> [OpenAICompletionsUsageBucket]
}

enum OpenAIUsageClientError: LocalizedError, Sendable, Equatable {
    case invalidURL
    case invalidResponse(String?)
    case httpStatus(Int, String?)
    case apiError(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "OpenAI usage request URL was invalid."
        case let .invalidResponse(message):
            if let message, !message.isEmpty {
                return "OpenAI usage API returned an invalid response: \(message)"
            }
            return "OpenAI usage API returned an invalid response."
        case let .httpStatus(statusCode, message):
            if let message, !message.isEmpty {
                return message
            }
            return "OpenAI usage API returned HTTP \(statusCode)."
        case let .apiError(message):
            return message
        case let .transport(message):
            return message
        }
    }
}

struct LiveOpenAIUsageClient: OpenAIUsageClient {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    init(
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = decoder
    }

    func readCosts(
        adminKey: String,
        startTime: Int64,
        endTime: Int64,
        limit: Int
    ) async throws -> [OpenAICostBucket] {
        let response: OpenAIListResponse<OpenAICostBucket> = try await request(
            path: "/organization/costs",
            adminKey: adminKey,
            startTime: startTime,
            endTime: endTime,
            limit: limit,
            responseType: OpenAIListResponse<OpenAICostBucket>.self
        )
        return response.data
    }

    func readCompletionsUsage(
        adminKey: String,
        startTime: Int64,
        endTime: Int64,
        limit: Int
    ) async throws -> [OpenAICompletionsUsageBucket] {
        let response: OpenAIListResponse<OpenAICompletionsUsageBucket> = try await request(
            path: "/organization/usage/completions",
            adminKey: adminKey,
            startTime: startTime,
            endTime: endTime,
            limit: limit,
            responseType: OpenAIListResponse<OpenAICompletionsUsageBucket>.self
        )
        return response.data
    }

    private func request<Response: Decodable>(
        path: String,
        adminKey: String,
        startTime: Int64,
        endTime: Int64,
        limit: Int,
        responseType: Response.Type
    ) async throws -> Response {
        guard var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
            throw OpenAIUsageClientError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "start_time", value: String(startTime)),
            URLQueryItem(name: "end_time", value: String(endTime)),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        guard let url = components.url else {
            throw OpenAIUsageClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(adminKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw OpenAIUsageClientError.transport(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIUsageClientError.invalidResponse(nil)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let apiErrorMessage = try? decoder.decode(OpenAIAPIErrorEnvelope.self, from: data).error?.message
            throw OpenAIUsageClientError.httpStatus(httpResponse.statusCode, apiErrorMessage)
        }

        do {
            return try decoder.decode(responseType, from: data)
        } catch {
            throw OpenAIUsageClientError.invalidResponse(Self.describeDecodingFailure(error))
        }
    }

    private static func describeDecodingFailure(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return error.localizedDescription
        }

        switch decodingError {
        case let .typeMismatch(_, context),
             let .valueNotFound(_, context),
             let .keyNotFound(_, context),
             let .dataCorrupted(context):
            let codingPath = context.codingPath
                .map(\.stringValue)
                .filter { !$0.isEmpty }
                .joined(separator: ".")

            if codingPath.isEmpty {
                return context.debugDescription
            }

            return "\(context.debugDescription) at `\(codingPath)`."
        @unknown default:
            return error.localizedDescription
        }
    }
}

private struct OpenAIAPIErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String?
    }

    let error: APIError?
}

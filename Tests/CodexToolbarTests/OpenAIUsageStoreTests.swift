import Foundation
import XCTest
@testable import CodexToolbar

@MainActor
final class OpenAIUsageStoreTests: XCTestCase {
    func testSnapshotAggregatesTodayAndTrailingThirtyDays() {
        let calendar = Self.makeCalendar()
        let now = Self.date("2026-03-30T12:00:00Z")
        let snapshot = OpenAIUsageStore.snapshot(
            fromCosts: [
                Self.costBucket(start: "2026-03-30T00:00:00Z", amount: "1.25"),
                Self.costBucket(start: "2026-03-29T00:00:00Z", amount: "2.50")
            ],
            usageBuckets: [
                Self.usageBucket(start: "2026-03-30T00:00:00Z", requests: 3, input: 100, output: 25),
                Self.usageBucket(start: "2026-03-29T00:00:00Z", requests: 5, input: 200, output: 50)
            ],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(snapshot?.today.costAmount, Decimal(string: "1.25"))
        XCTAssertEqual(snapshot?.today.requestCount, 3)
        XCTAssertEqual(snapshot?.today.inputTokens, 100)
        XCTAssertEqual(snapshot?.today.outputTokens, 25)
        XCTAssertEqual(snapshot?.trailingThirtyDays.costAmount, Decimal(string: "3.75"))
        XCTAssertEqual(snapshot?.trailingThirtyDays.requestCount, 8)
        XCTAssertEqual(snapshot?.trailingThirtyDays.inputTokens, 300)
        XCTAssertEqual(snapshot?.trailingThirtyDays.outputTokens, 75)
    }

    func testSnapshotUsesZeroValuesWhenEndpointsSucceedWithEmptyBuckets() {
        let snapshot = OpenAIUsageStore.snapshot(
            fromCosts: [],
            usageBuckets: [],
            now: Self.date("2026-03-30T12:00:00Z"),
            calendar: Self.makeCalendar()
        )

        XCTAssertNil(snapshot?.today.costAmount)
        XCTAssertEqual(snapshot?.today.requestCount, 0)
        XCTAssertNil(snapshot?.trailingThirtyDays.costAmount)
        XCTAssertEqual(snapshot?.trailingThirtyDays.outputTokens, 0)
    }

    func testViewDataShowsSetupMessageWhenEnabledWithoutAdminKey() {
        let store = makeStore(adminKey: nil)

        XCTAssertEqual(
            store.viewData?.statusMessage,
            "Configure an OpenAI admin key to view organization API usage."
        )
        XCTAssertFalse(store.hasConfiguredAdminKey)
    }

    func testRefreshKeepsLastKnownCostsWhenCostsEndpointFails() async {
        let client = FakeStoreOpenAIUsageClient()
        client.costBuckets = [
            Self.costBucket(start: "2026-03-30T00:00:00Z", amount: "4.20")
        ]
        client.usageBuckets = [
            Self.usageBucket(start: "2026-03-30T00:00:00Z", requests: 2, input: 120, output: 45)
        ]
        let store = makeStore(adminKey: "sk-admin-123", client: client)

        await store.refreshNow()
        client.costsError = StoreOpenAIUsageError("Costs API down")

        await store.refreshNow()

        XCTAssertEqual(
            store.viewData?.periodSummaries.first?.primaryText?.replacingOccurrences(of: "\u{00A0}", with: ""),
            "$4.20 spent · 2 requests"
        )
        XCTAssertEqual(store.viewData?.costsStatusMessage, "Costs stale: Costs API down")
        XCTAssertNil(store.viewData?.usageStatusMessage)
    }

    func testRefreshKeepsLastKnownUsageWhenUsageEndpointFails() async {
        let client = FakeStoreOpenAIUsageClient()
        client.costBuckets = [
            Self.costBucket(start: "2026-03-30T00:00:00Z", amount: "3.10")
        ]
        client.usageBuckets = [
            Self.usageBucket(start: "2026-03-30T00:00:00Z", requests: 7, input: 700, output: 70)
        ]
        let store = makeStore(adminKey: "sk-admin-123", client: client)

        await store.refreshNow()
        client.usageError = StoreOpenAIUsageError("Usage API down")

        await store.refreshNow()

        XCTAssertEqual(store.viewData?.periodSummaries.first?.secondaryText, "700 input · 70 output")
        XCTAssertNil(store.viewData?.costsStatusMessage)
        XCTAssertEqual(store.viewData?.usageStatusMessage, "Usage stale: Usage API down")
    }

    func testRefreshWithoutAnySuccessfulDataShowsGeneralFailureMessage() async {
        let client = FakeStoreOpenAIUsageClient()
        client.costsError = StoreOpenAIUsageError("Costs API down")
        client.usageError = StoreOpenAIUsageError("Usage API down")
        let store = makeStore(adminKey: "sk-admin-123", client: client)

        await store.refreshNow()

        XCTAssertEqual(store.viewData?.statusMessage, "Unable to load OpenAI API usage.")
        XCTAssertTrue(store.viewData?.periodSummaries.isEmpty ?? false)
    }

    private func makeStore(
        adminKey: String?,
        client: FakeStoreOpenAIUsageClient = FakeStoreOpenAIUsageClient()
    ) -> OpenAIUsageStore {
        OpenAIUsageStore(
            client: client,
            adminKeyStore: FakeStoreOpenAIAdminKeyStore(initialKey: adminKey),
            nowProvider: { Self.date("2026-03-30T12:00:00Z") },
            calendar: Self.makeCalendar(),
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            isEnabled: true
        )
    }

    nonisolated private static func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    nonisolated private static func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: value)!
    }

    nonisolated private static func costBucket(start: String, amount: String) -> OpenAICostBucket {
        let startDate = date(start)
        let endDate = startDate.addingTimeInterval(86_400)
        return try! JSONDecoder().decode(
            OpenAICostBucket.self,
            from: Data(
                """
                {
                  "object": "bucket",
                  "start_time": \(Int(startDate.timeIntervalSince1970)),
                  "end_time": \(Int(endDate.timeIntervalSince1970)),
                  "results": [
                    {
                      "object": "organization.costs.result",
                      "amount": {
                        "value": \(amount),
                        "currency": "USD"
                      }
                    }
                  ]
                }
                """.utf8
            )
        )
    }

    nonisolated private static func usageBucket(start: String, requests: Int, input: Int, output: Int) -> OpenAICompletionsUsageBucket {
        let startDate = date(start)
        let endDate = startDate.addingTimeInterval(86_400)
        return try! JSONDecoder().decode(
            OpenAICompletionsUsageBucket.self,
            from: Data(
                """
                {
                  "object": "bucket",
                  "start_time": \(Int(startDate.timeIntervalSince1970)),
                  "end_time": \(Int(endDate.timeIntervalSince1970)),
                  "results": [
                    {
                      "object": "organization.usage.completions.result",
                      "input_tokens": \(input),
                      "output_tokens": \(output),
                      "num_model_requests": \(requests)
                    }
                  ]
                }
                """.utf8
            )
        )
    }
}

private final class FakeStoreOpenAIAdminKeyStore: @unchecked Sendable, OpenAIAdminKeyStore {
    private(set) var storedKey: String?

    init(initialKey: String?) {
        storedKey = initialKey
    }

    func readAdminKey() throws -> String? {
        storedKey
    }

    func writeAdminKey(_ key: String) throws {
        storedKey = key
    }

    func removeAdminKey() throws {
        storedKey = nil
    }
}

private final class FakeStoreOpenAIUsageClient: @unchecked Sendable, OpenAIUsageClient {
    var costBuckets: [OpenAICostBucket] = []
    var usageBuckets: [OpenAICompletionsUsageBucket] = []
    var costsError: Error?
    var usageError: Error?

    func readCosts(
        adminKey: String,
        startTime: Int64,
        endTime: Int64,
        limit: Int
    ) async throws -> [OpenAICostBucket] {
        if let costsError {
            throw costsError
        }
        return costBuckets
    }

    func readCompletionsUsage(
        adminKey: String,
        startTime: Int64,
        endTime: Int64,
        limit: Int
    ) async throws -> [OpenAICompletionsUsageBucket] {
        if let usageError {
            throw usageError
        }
        return usageBuckets
    }
}

private struct StoreOpenAIUsageError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

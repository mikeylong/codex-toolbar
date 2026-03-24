import XCTest
@testable import CodexToolbar

final class RateLimitDecodingTests: XCTestCase {
    func testDecodesSingleBucketResponse() throws {
        let json = """
        {
          "rateLimits": {
            "limitId": "codex",
            "limitName": "Codex",
            "planType": "pro",
            "primary": {
              "resetsAt": 1741269240,
              "usedPercent": 88,
              "windowDurationMins": 300
            },
            "secondary": {
              "resetsAt": 1741737600,
              "usedPercent": 92,
              "windowDurationMins": 10080
            }
          },
          "rateLimitsByLimitId": null
        }
        """

        let response = try JSONDecoder().decode(GetAccountRateLimitsResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.displaySnapshot().limitId, "codex")
        XCTAssertEqual(response.displaySnapshot().primary?.usedPercent, 88)
        XCTAssertEqual(response.displaySnapshot().secondary?.windowDurationMins, 10080)
    }

    func testPrefersTopLevelRateLimitsWhenPresent() throws {
        let json = """
        {
          "rateLimits": {
            "limitId": "default",
            "limitName": "Default",
            "planType": "pro",
            "primary": { "resetsAt": 1741269240, "usedPercent": 12, "windowDurationMins": 300 },
            "secondary": null
          },
          "rateLimitsByLimitId": {
            "codex": {
              "limitId": "codex",
              "limitName": "Codex",
              "planType": "pro",
              "primary": { "resetsAt": 1741269240, "usedPercent": 88, "windowDurationMins": 300 },
              "secondary": { "resetsAt": 1741737600, "usedPercent": 92, "windowDurationMins": 10080 }
            }
          }
        }
        """

        let response = try JSONDecoder().decode(GetAccountRateLimitsResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.displaySnapshot().limitId, "default")
        XCTAssertEqual(response.displaySnapshot().primary?.usedPercent, 12)
    }

    func testFallsBackToCodexBucketWhenTopLevelWindowsMissing() throws {
        let json = """
        {
          "rateLimits": {
            "limitId": "default",
            "limitName": "Default",
            "planType": "pro",
            "primary": null,
            "secondary": null
          },
          "rateLimitsByLimitId": {
            "codex": {
              "limitId": "codex",
              "limitName": "Codex",
              "planType": "pro",
              "primary": { "resetsAt": 1741269240, "usedPercent": 88, "windowDurationMins": 300 },
              "secondary": { "resetsAt": 1741737600, "usedPercent": 92, "windowDurationMins": 10080 }
            }
          }
        }
        """

        let response = try JSONDecoder().decode(GetAccountRateLimitsResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.displaySnapshot().limitId, "codex")
        XCTAssertEqual(response.displaySnapshot().primary?.usedPercent, 88)
    }

    func testDecodesSupplementalSparkLimitFromRateLimitMap() throws {
        let json = """
        {
          "rateLimits": {
            "limitId": "codex",
            "limitName": "Codex",
            "planType": "pro",
            "primary": { "resetsAt": 1741269240, "usedPercent": 12, "windowDurationMins": 300 },
            "secondary": null
          },
          "rateLimitsByLimitId": {
            "codex_bengalfox": {
              "limitId": "codex_bengalfox",
              "limitName": "GPT-5.3-Codex-Spark",
              "planType": "pro",
              "primary": { "resetsAt": 1741269240, "usedPercent": 88, "windowDurationMins": 300 },
              "secondary": { "resetsAt": 1741737600, "usedPercent": 92, "windowDurationMins": 10080 }
            }
          }
        }
        """

        let response = try JSONDecoder().decode(GetAccountRateLimitsResponse.self, from: Data(json.utf8))
        let candidates = response.cardCandidates()
        let sparkCandidate = try XCTUnwrap(candidates.first { $0.limitId == "codex_bengalfox" })

        XCTAssertEqual(response.rateLimitsByLimitId?.keys.contains("codex_bengalfox"), true)
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(sparkCandidate.limitName, "GPT-5.3-Codex-Spark")
        XCTAssertEqual(sparkCandidate.categoryLabel, "GPT-5.3-Codex-Spark")
        XCTAssertNotNil(sparkCandidate.snapshot.primary)
    }

    func testDecodesMissingPrimaryOrSecondary() throws {
        let json = """
        {
          "rateLimits": {
            "limitId": "codex",
            "limitName": "Codex",
            "planType": "pro",
            "primary": null,
            "secondary": {
              "resetsAt": 1741737600,
              "usedPercent": 92,
              "windowDurationMins": 10080
            }
          },
          "rateLimitsByLimitId": null
        }
        """

        let response = try JSONDecoder().decode(GetAccountRateLimitsResponse.self, from: Data(json.utf8))

        XCTAssertNil(response.displaySnapshot().primary)
        XCTAssertEqual(response.displaySnapshot().secondary?.usedPercent, 92)
    }

    func testDecodesCreditSnapshotFields() throws {
        let json = """
        {
          "rateLimits": {
            "credits": {
              "balance": "243 credit remaining",
              "hasCredits": true,
              "unlimited": false
            },
            "limitId": "codex",
            "limitName": "Codex",
            "planType": "pro",
            "primary": { "resetsAt": 1741269240, "usedPercent": 12, "windowDurationMins": 300 },
            "secondary": null
          },
          "rateLimitsByLimitId": null
        }
        """

        let response = try JSONDecoder().decode(GetAccountRateLimitsResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.displaySnapshot().credits?.balance, "243 credit remaining")
        XCTAssertEqual(response.displaySnapshot().credits?.hasCredits, true)
        XCTAssertEqual(response.displaySnapshot().credits?.unlimited, false)
    }
}

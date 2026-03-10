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
}

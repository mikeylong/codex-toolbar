import XCTest
@testable import CodexToolbar

final class OpenAIUsageDecodingTests: XCTestCase {
    func testDecodesCostsResponse() throws {
        let json = """
        {
          "data": [
            {
              "object": "bucket",
              "start_time": 1711843200,
              "end_time": 1711929600,
              "results": [
                {
                  "object": "organization.costs.result",
                  "amount": {
                    "value": 12.34,
                    "currency": "usd"
                  }
                }
              ]
            }
          ],
          "next_page": null
        }
        """

        let response = try JSONDecoder().decode(OpenAIListResponse<OpenAICostBucket>.self, from: Data(json.utf8))

        XCTAssertEqual(response.data.count, 1)
        XCTAssertEqual(response.data[0].results[0].amount?.value, Decimal(string: "12.34")!)
        XCTAssertEqual(response.data[0].results[0].amount?.currency, "usd")
    }

    func testDecodesCostsResponseWhenDocsUseSingularResultKey() throws {
        let json = """
        {
          "data": [
            {
              "object": "bucket",
              "start_time": 1711843200,
              "end_time": 1711929600,
              "result": [
                {
                  "object": "organization.costs.result",
                  "amount": {
                    "value": 1.25,
                    "currency": "usd"
                  }
                }
              ]
            }
          ],
          "next_page": null
        }
        """

        let response = try JSONDecoder().decode(OpenAIListResponse<OpenAICostBucket>.self, from: Data(json.utf8))

        XCTAssertEqual(response.data[0].results.count, 1)
        XCTAssertEqual(response.data[0].results[0].amount?.value, Decimal(string: "1.25")!)
    }

    func testDecodesCostsResponseWhenResultIsSingleObject() throws {
        let json = """
        {
          "data": [
            {
              "object": "bucket",
              "start_time": 1711843200,
              "end_time": 1711929600,
              "result": {
                "object": "organization.costs.result",
                "amount": {
                  "value": 1.25,
                  "currency": "usd"
                }
              }
            }
          ],
          "next_page": null
        }
        """

        let response = try JSONDecoder().decode(OpenAIListResponse<OpenAICostBucket>.self, from: Data(json.utf8))

        XCTAssertEqual(response.data[0].results.count, 1)
        XCTAssertEqual(response.data[0].results[0].amount?.value, Decimal(string: "1.25")!)
    }

    func testDecodesCompletionsUsageResponse() throws {
        let json = """
        {
          "data": [
            {
              "object": "bucket",
              "start_time": 1711843200,
              "end_time": 1711929600,
              "results": [
                {
                  "object": "organization.usage.completions.result",
                  "input_tokens": 1234,
                  "output_tokens": 567,
                  "num_model_requests": 42
                }
              ]
            }
          ],
          "next_page": null
        }
        """

        let response = try JSONDecoder().decode(OpenAIListResponse<OpenAICompletionsUsageBucket>.self, from: Data(json.utf8))

        XCTAssertEqual(response.data.count, 1)
        XCTAssertEqual(response.data[0].results[0].inputTokens, 1234)
        XCTAssertEqual(response.data[0].results[0].outputTokens, 567)
        XCTAssertEqual(response.data[0].results[0].numModelRequests, 42)
    }

    func testDecodesNullCostAmountWithoutFailingWholeResponse() throws {
        let json = """
        {
          "data": [
            {
              "object": "bucket",
              "start_time": 1711843200,
              "end_time": 1711929600,
              "results": [
                {
                  "object": "organization.costs.result",
                  "amount": null,
                  "line_item": null,
                  "project_id": null
                }
              ]
            }
          ],
          "next_page": null
        }
        """

        let response = try JSONDecoder().decode(OpenAIListResponse<OpenAICostBucket>.self, from: Data(json.utf8))

        XCTAssertEqual(response.data.count, 1)
        XCTAssertNil(response.data[0].results[0].amount)
    }

    func testDecodesStringCostAmountValue() throws {
        let json = """
        {
          "data": [
            {
              "object": "bucket",
              "start_time": 1711843200,
              "end_time": 1711929600,
              "results": [
                {
                  "object": "organization.costs.result",
                  "amount": {
                    "value": "0.06",
                    "currency": "usd"
                  }
                }
              ]
            }
          ],
          "next_page": null
        }
        """

        let response = try JSONDecoder().decode(OpenAIListResponse<OpenAICostBucket>.self, from: Data(json.utf8))

        XCTAssertEqual(response.data.count, 1)
        XCTAssertEqual(response.data[0].results[0].amount?.value, Decimal(string: "0.06")!)
        XCTAssertEqual(response.data[0].results[0].amount?.currency, "usd")
    }
}

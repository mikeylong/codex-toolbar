import Foundation

struct OpenAIListResponse<Item: Decodable & Equatable & Sendable>: Decodable, Equatable, Sendable {
    let data: [Item]
    let nextPage: String?

    enum CodingKeys: String, CodingKey {
        case data
        case nextPage = "next_page"
    }
}

struct OpenAICostBucket: Decodable, Equatable, Sendable {
    let object: String?
    let startTime: Int64
    let endTime: Int64
    let results: [OpenAICostResult]

    enum CodingKeys: String, CodingKey {
        case object
        case startTime = "start_time"
        case endTime = "end_time"
        case results
        case result
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        object = try container.decodeIfPresent(String.self, forKey: .object)
        startTime = try container.decode(Int64.self, forKey: .startTime)
        endTime = try container.decode(Int64.self, forKey: .endTime)

        results = try decodeManyOrOne(
            from: container,
            pluralKey: .results,
            singularKey: .result
        )
    }

    var startDate: Date {
        Date(timeIntervalSince1970: TimeInterval(startTime))
    }
}

struct OpenAICostResult: Decodable, Equatable, Sendable {
    struct Amount: Decodable, Equatable, Sendable {
        let value: Decimal?
        let currency: String?

        private struct ObjectValue: Decodable {
            let value: DecimalValue?
            let currency: String?
        }

        private enum DecimalValue: Decodable, Equatable, Sendable {
            case decimal(Decimal)

            var decimal: Decimal {
                switch self {
                case let .decimal(value):
                    return value
                }
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()

                if let decimal = try? container.decode(Decimal.self) {
                    self = .decimal(decimal)
                    return
                }

                if let stringValue = try? container.decode(String.self),
                   let decimal = Decimal(string: stringValue, locale: Locale(identifier: "en_US_POSIX")) {
                    self = .decimal(decimal)
                    return
                }

                throw DecodingError.typeMismatch(
                    DecimalValue.self,
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Expected a decimal number or decimal string."
                    )
                )
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()

            if let objectValue = try? container.decode(ObjectValue.self) {
                value = objectValue.value?.decimal
                currency = objectValue.currency
                return
            }

            if let decimalValue = try? container.decode(DecimalValue.self) {
                value = decimalValue.decimal
                currency = nil
                return
            }

            throw DecodingError.typeMismatch(
                Amount.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected an amount object, number, or decimal string."
                )
            )
        }
    }

    let object: String?
    let amount: Amount?
}

struct OpenAICompletionsUsageBucket: Decodable, Equatable, Sendable {
    let object: String?
    let startTime: Int64
    let endTime: Int64
    let results: [OpenAICompletionsUsageResult]

    enum CodingKeys: String, CodingKey {
        case object
        case startTime = "start_time"
        case endTime = "end_time"
        case results
        case result
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        object = try container.decodeIfPresent(String.self, forKey: .object)
        startTime = try container.decode(Int64.self, forKey: .startTime)
        endTime = try container.decode(Int64.self, forKey: .endTime)

        results = try decodeManyOrOne(
            from: container,
            pluralKey: .results,
            singularKey: .result
        )
    }

    var startDate: Date {
        Date(timeIntervalSince1970: TimeInterval(startTime))
    }
}

struct OpenAICompletionsUsageResult: Decodable, Equatable, Sendable {
    let object: String?
    let inputTokens: Int
    let outputTokens: Int
    let numModelRequests: Int

    enum CodingKeys: String, CodingKey {
        case object
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case numModelRequests = "num_model_requests"
    }
}

struct OpenAIUsageRollup: Equatable, Sendable {
    let costAmount: Decimal?
    let currencyCode: String?
    let requestCount: Int?
    let inputTokens: Int?
    let outputTokens: Int?

    var hasAnyMetric: Bool {
        costAmount != nil || requestCount != nil || inputTokens != nil || outputTokens != nil
    }
}

struct OpenAIUsageSnapshot: Equatable, Sendable {
    let today: OpenAIUsageRollup
    let trailingThirtyDays: OpenAIUsageRollup

    var hasAnyMetric: Bool {
        today.hasAnyMetric || trailingThirtyDays.hasAnyMetric
    }
}

private func decodeManyOrOne<Value: Decodable, Key: CodingKey>(
    from container: KeyedDecodingContainer<Key>,
    pluralKey: Key,
    singularKey: Key
) throws -> [Value] {
    if let values: [Value] = try decodeArrayOrSingle(from: container, key: pluralKey) {
        return values
    }

    if let values: [Value] = try decodeArrayOrSingle(from: container, key: singularKey) {
        return values
    }

    return []
}

private func decodeArrayOrSingle<Value: Decodable, Key: CodingKey>(
    from container: KeyedDecodingContainer<Key>,
    key: Key
) throws -> [Value]? {
    guard container.contains(key) else {
        return nil
    }

    if try container.decodeNil(forKey: key) {
        return []
    }

    do {
        return try container.decode([Value].self, forKey: key)
    } catch {
        guard let arrayError = error as? DecodingError else {
            throw error
        }

        do {
            let value = try container.decode(Value.self, forKey: key)
            return [value]
        } catch {
            guard let singleError = error as? DecodingError else {
                throw error
            }

            throw preferSpecificDecodingError(singleError, fallback: arrayError)
        }
    }
}

private func preferSpecificDecodingError(_ primary: DecodingError, fallback: DecodingError) -> DecodingError {
    switch primary {
    case .typeMismatch, .valueNotFound, .keyNotFound, .dataCorrupted:
        return primary
    @unknown default:
        return fallback
    }
}

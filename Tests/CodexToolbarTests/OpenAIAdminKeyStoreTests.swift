import XCTest
@testable import CodexToolbar

final class OpenAIAdminKeyStoreTests: XCTestCase {
    func testRoundTripsStoredAdminKeyThroughSecretStore() throws {
        let secretStore = MemorySecretStore()
        let store = KeychainOpenAIAdminKeyStore(
            secretStore: secretStore,
            service: "com.example.codextoolbar.tests",
            account: "OPENAI_ADMIN_KEY"
        )

        try store.writeAdminKey("sk-admin-123")

        XCTAssertEqual(try store.readAdminKey(), "sk-admin-123")
        XCTAssertEqual(secretStore.storage["com.example.codextoolbar.tests:OPENAI_ADMIN_KEY"], Data("sk-admin-123".utf8))
    }

    func testRemoveDeletesStoredAdminKey() throws {
        let secretStore = MemorySecretStore()
        let store = KeychainOpenAIAdminKeyStore(
            secretStore: secretStore,
            service: "com.example.codextoolbar.tests",
            account: "OPENAI_ADMIN_KEY"
        )
        try store.writeAdminKey("sk-admin-123")

        try store.removeAdminKey()

        XCTAssertNil(try store.readAdminKey())
    }

    func testReadThrowsWhenStoredDataIsNotUTF8() {
        let secretStore = MemorySecretStore()
        secretStore.storage["com.example.codextoolbar.tests:OPENAI_ADMIN_KEY"] = Data([0xFF])
        let store = KeychainOpenAIAdminKeyStore(
            secretStore: secretStore,
            service: "com.example.codextoolbar.tests",
            account: "OPENAI_ADMIN_KEY"
        )

        XCTAssertThrowsError(try store.readAdminKey()) { error in
            XCTAssertEqual(error as? OpenAIAdminKeyStoreError, .invalidData)
        }
    }
}

private final class MemorySecretStore: @unchecked Sendable, SecretStore {
    var storage: [String: Data] = [:]

    func read(service: String, account: String) throws -> Data? {
        storage["\(service):\(account)"]
    }

    func upsert(_ data: Data, service: String, account: String) throws {
        storage["\(service):\(account)"] = data
    }

    func remove(service: String, account: String) throws {
        storage.removeValue(forKey: "\(service):\(account)")
    }
}

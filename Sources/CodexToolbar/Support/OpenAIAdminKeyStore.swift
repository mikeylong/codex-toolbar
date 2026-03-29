import Foundation
import Security

protocol OpenAIAdminKeyStore: Sendable {
    func readAdminKey() throws -> String?
    func writeAdminKey(_ key: String) throws
    func removeAdminKey() throws
}

enum OpenAIAdminKeyStoreError: LocalizedError, Equatable, Sendable {
    case unexpectedStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case let .unexpectedStatus(status):
            return "OpenAI admin key keychain access failed (\(status))."
        case .invalidData:
            return "OpenAI admin key data was invalid."
        }
    }
}

protocol SecretStore: Sendable {
    func read(service: String, account: String) throws -> Data?
    func upsert(_ data: Data, service: String, account: String) throws
    func remove(service: String, account: String) throws
}

struct KeychainSecretStore: SecretStore {
    func read(service: String, account: String) throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw OpenAIAdminKeyStoreError.invalidData
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw OpenAIAdminKeyStoreError.unexpectedStatus(status)
        }
    }

    func upsert(_ data: Data, service: String, account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw OpenAIAdminKeyStoreError.unexpectedStatus(addStatus)
            }
        default:
            throw OpenAIAdminKeyStoreError.unexpectedStatus(updateStatus)
        }
    }

    func remove(service: String, account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OpenAIAdminKeyStoreError.unexpectedStatus(status)
        }
    }
}

struct KeychainOpenAIAdminKeyStore: OpenAIAdminKeyStore {
    private let secretStore: SecretStore
    private let service: String
    private let account: String

    init(
        secretStore: SecretStore = KeychainSecretStore(),
        service: String = Bundle.main.bundleIdentifier ?? "com.mikelong.codextoolbar",
        account: String = "OPENAI_ADMIN_KEY"
    ) {
        self.secretStore = secretStore
        self.service = service
        self.account = account
    }

    func readAdminKey() throws -> String? {
        guard let data = try secretStore.read(service: service, account: account) else {
            return nil
        }

        guard let key = String(data: data, encoding: .utf8) else {
            throw OpenAIAdminKeyStoreError.invalidData
        }

        return key
    }

    func writeAdminKey(_ key: String) throws {
        guard let data = key.data(using: .utf8) else {
            throw OpenAIAdminKeyStoreError.invalidData
        }

        try secretStore.upsert(data, service: service, account: account)
    }

    func removeAdminKey() throws {
        try secretStore.remove(service: service, account: account)
    }
}

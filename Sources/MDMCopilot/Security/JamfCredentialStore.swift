import Foundation
import Security

struct JamfCredentials: Codable, Equatable {
    var tenantURL: URL
    var networkID: String
    var apiKey: String
}

enum CredentialStoreError: LocalizedError {
    case encodingFailed
    case decodingFailed
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            "The Jamf School credentials could not be encoded."
        case .decodingFailed:
            "The stored Jamf School credentials could not be decoded."
        case .keychain(let status):
            "Keychain returned status \(status)."
        }
    }
}

protocol JamfCredentialStoring {
    func save(_ credentials: JamfCredentials) throws
    func load() throws -> JamfCredentials?
    func delete() throws
}

struct KeychainJamfCredentialStore: JamfCredentialStoring {
    private let service: String
    private let account = "default-tenant"

    init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "dev.example.MDMProfileBuilder.local") {
        service = "\(bundleIdentifier).JamfSchool"
    }

    func save(_ credentials: JamfCredentials) throws {
        guard let data = try? JSONEncoder().encode(credentials) else {
            throw CredentialStoreError.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            attributes.forEach { addQuery[$0.key] = $0.value }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw CredentialStoreError.keychain(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw CredentialStoreError.keychain(updateStatus)
        }
    }

    func load() throws -> JamfCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw CredentialStoreError.keychain(status)
        }
        guard let data = result as? Data,
              let credentials = try? JSONDecoder().decode(JamfCredentials.self, from: data) else {
            throw CredentialStoreError.decodingFailed
        }
        return credentials
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status)
        }
    }
}

struct KeychainJamfPlatformCredentialStore: JamfPlatformCredentialStoring {
    private let service: String
    private let account = "default-tenant"

    init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "dev.example.MDMProfileBuilder.local") {
        service = "\(bundleIdentifier).JamfPlatform"
    }

    func save(_ credentials: JamfPlatformCredentials) throws {
        guard let data = try? JSONEncoder().encode(credentials) else {
            throw CredentialStoreError.encodingFailed
        }
        let query = baseQuery
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            attributes.forEach { addQuery[$0.key] = $0.value }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw CredentialStoreError.keychain(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw CredentialStoreError.keychain(updateStatus)
        }
    }

    func load() throws -> JamfPlatformCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw CredentialStoreError.keychain(status)
        }
        guard let data = result as? Data,
              let credentials = try? JSONDecoder().decode(JamfPlatformCredentials.self, from: data) else {
            throw CredentialStoreError.decodingFailed
        }
        return credentials
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

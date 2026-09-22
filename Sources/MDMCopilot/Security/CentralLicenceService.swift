import CryptoKit
import Foundation

struct CentralLicenceServiceConfiguration: Equatable, Sendable {
    var baseURL: URL
    var leasePublicKey: Data

    static var current: CentralLicenceServiceConfiguration? {
        let bundle = Bundle.main
        guard let urlText = bundle.object(forInfoDictionaryKey: "MDMCopilotLicenceServiceURL") as? String,
              let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https",
              url.host != nil,
              let keyText = bundle.object(forInfoDictionaryKey: "MDMCopilotLeasePublicKey") as? String,
              let key = Data(base64Encoded: keyText.trimmingCharacters(in: .whitespacesAndNewlines)),
              key.count == 32 else {
            return nil
        }
        return CentralLicenceServiceConfiguration(baseURL: url, leasePublicKey: key)
    }
}

struct CentralLicenceLeasePayload: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let maximumDuration: TimeInterval = 20 * 60

    var version: Int
    var licenceID: UUID
    var installationID: UUID
    var bundleIdentifier: String
    var role: AccessRole
    var issuedAt: Date
    var validUntil: Date

    var duration: TimeInterval {
        validUntil.timeIntervalSince(issuedAt)
    }
}

struct CentralLicenceDirectoryRecord: Decodable, Equatable, Sendable {
    var licenceID: UUID
    var subject: String
    var displayName: String
    var notes: String
    var role: AccessRole
    var issuedAt: Date
    var expiresAt: Date?
    var installationID: UUID
    var bundleIdentifier: String
    var state: IssuedLicenceState
    var revokedAt: Date?
    var replacedByLicenceID: UUID?
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case licenceID = "licence_id"
        case subject
        case displayName = "display_name"
        case notes
        case role
        case issuedAt = "issued_at"
        case expiresAt = "expires_at"
        case installationID = "installation_id"
        case bundleIdentifier = "bundle_identifier"
        case state = "status"
        case revokedAt = "revoked_at"
        case replacedByLicenceID = "replaced_by_licence_id"
        case updatedAt = "updated_at"
    }
}

enum CentralLicenceServiceError: LocalizedError, Equatable {
    case unavailable(String)
    case denied(String)
    case revoked
    case replaced
    case expired
    case invalidLease

    var isDefinitiveDenial: Bool {
        switch self {
        case .denied, .revoked, .replaced, .expired, .invalidLease:
            true
        case .unavailable:
            false
        }
    }

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            "The central licence service is temporarily unavailable. \(message)"
        case .denied(let message):
            message
        case .revoked:
            "This licence has been revoked by a licence administrator."
        case .replaced:
            "This licence has been replaced. Activate the latest access code issued for this Mac."
        case .expired:
            "This annual licence has expired. Request a new access code from a licence administrator."
        case .invalidLease:
            "The central licence service returned an invalid signed lease. Access has been locked."
        }
    }
}

protocol CentralLicenceServicing: Sendable {
    func activate(
        accessCode: String,
        licence: AccessLicencePayload,
        devicePrivateKey: Curve25519.Signing.PrivateKey
    ) async throws -> CentralLicenceLeasePayload

    func check(
        licence: AccessLicencePayload,
        devicePrivateKey: Curve25519.Signing.PrivateKey
    ) async throws -> CentralLicenceLeasePayload

    func listIssuedLicences(
        administrator: AccessLicencePayload,
        devicePrivateKey: Curve25519.Signing.PrivateKey
    ) async throws -> [CentralLicenceDirectoryRecord]

    func registerIssuedLicence(
        accessCode: String,
        administrator: AccessLicencePayload,
        devicePrivateKey: Curve25519.Signing.PrivateKey
    ) async throws

    func reissueLicence(
        oldLicenceID: UUID,
        accessCode: String,
        administrator: AccessLicencePayload,
        devicePrivateKey: Curve25519.Signing.PrivateKey
    ) async throws

    func revokeLicence(
        licenceID: UUID,
        administrator: AccessLicencePayload,
        devicePrivateKey: Curve25519.Signing.PrivateKey
    ) async throws -> Date

    func updateLicenceMetadata(
        licenceID: UUID,
        displayName: String,
        notes: String,
        administrator: AccessLicencePayload,
        devicePrivateKey: Curve25519.Signing.PrivateKey
    ) async throws
}

actor CloudflareCentralLicenceService: CentralLicenceServicing {
    private struct LeaseResponse: Decodable {
        var lease: String
    }

    private struct ErrorResponse: Decodable {
        var error: String
    }

    private struct ActivationBody: Encodable {
        var accessCode: String
        var devicePublicKey: String
    }

    private struct RegisterBody: Encodable {
        var accessCode: String
    }

    private struct ReissueBody: Encodable {
        var accessCode: String
        var oldLicenceID: String
    }

    private struct MetadataBody: Encodable {
        var displayName: String
        var notes: String
    }

    private struct RevocationResponse: Decodable {
        var revokedAt: Double
    }

    private struct LicenceDirectoryResponse: Decodable {
        var licences: [CentralLicenceDirectoryRecord]
    }

    private let configuration: CentralLicenceServiceConfiguration
    private let session: URLSession
    private let clock = ContinuousClock()
    private var serverDateReference: Date?
    private var serverClockReference: ContinuousClock.Instant?

    init(
        configuration: CentralLicenceServiceConfiguration,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
    }

    func activate(
        accessCode: String,
        licence: AccessLicencePayload,
        devicePrivateKey: Curve25519.Signing.PrivateKey
    ) async throws -> CentralLicenceLeasePayload {
        let body = try encode(ActivationBody(
            accessCode: accessCode.trimmingCharacters(in: .whitespacesAndNewlines),
            devicePublicKey: devicePrivateKey.publicKey.rawRepresentation.base64EncodedString()
        ))
        let data = try await send(method: "POST", path: "/v1/licences/activate", body: body)
        return try acceptLease(from: data, expected: licence)
    }

    func check(
        licence: AccessLicencePayload,
        devicePrivateKey: Curve25519.Signing.PrivateKey
    ) async throws -> CentralLicenceLeasePayload {
        let data = try await sendAuthenticated(
            method: "POST",
            path: "/v1/licences/check",
            body: Data("{}".utf8),
            licence: licence,
            devicePrivateKey: devicePrivateKey
        )
        return try acceptLease(from: data, expected: licence)
    }

    func listIssuedLicences(
        administrator: AccessLicencePayload,
        devicePrivateKey: Curve25519.Signing.PrivateKey
    ) async throws -> [CentralLicenceDirectoryRecord] {
        let data = try await sendAuthenticated(
            method: "GET",
            path: "/v1/admin/licences",
            body: Data(),
            licence: administrator,
            devicePrivateKey: devicePrivateKey
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(LicenceDirectoryResponse.self, from: data).licences
    }

    func registerIssuedLicence(
        accessCode: String,
        administrator: AccessLicencePayload,
        devicePrivateKey: Curve25519.Signing.PrivateKey
    ) async throws {
        let body = try encode(RegisterBody(accessCode: accessCode))
        _ = try await sendAuthenticated(
            method: "POST",
            path: "/v1/admin/licences/register",
            body: body,
            licence: administrator,
            devicePrivateKey: devicePrivateKey
        )
    }

    func reissueLicence(
        oldLicenceID: UUID,
        accessCode: String,
        administrator: AccessLicencePayload,
        devicePrivateKey: Curve25519.Signing.PrivateKey
    ) async throws {
        let body = try encode(ReissueBody(
            accessCode: accessCode,
            oldLicenceID: oldLicenceID.uuidString.lowercased()
        ))
        _ = try await sendAuthenticated(
            method: "POST",
            path: "/v1/admin/licences/reissue",
            body: body,
            licence: administrator,
            devicePrivateKey: devicePrivateKey
        )
    }

    func revokeLicence(
        licenceID: UUID,
        administrator: AccessLicencePayload,
        devicePrivateKey: Curve25519.Signing.PrivateKey
    ) async throws -> Date {
        let data = try await sendAuthenticated(
            method: "POST",
            path: "/v1/admin/licences/\(licenceID.uuidString.lowercased())/revoke",
            body: Data("{}".utf8),
            licence: administrator,
            devicePrivateKey: devicePrivateKey
        )
        let response = try decoder.decode(RevocationResponse.self, from: data)
        return Date(timeIntervalSince1970: response.revokedAt / 1_000)
    }

    func updateLicenceMetadata(
        licenceID: UUID,
        displayName: String,
        notes: String,
        administrator: AccessLicencePayload,
        devicePrivateKey: Curve25519.Signing.PrivateKey
    ) async throws {
        let body = try encode(MetadataBody(displayName: displayName, notes: notes))
        _ = try await sendAuthenticated(
            method: "PATCH",
            path: "/v1/admin/licences/\(licenceID.uuidString.lowercased())/metadata",
            body: body,
            licence: administrator,
            devicePrivateKey: devicePrivateKey
        )
    }

    private func acceptLease(
        from data: Data,
        expected licence: AccessLicencePayload
    ) throws -> CentralLicenceLeasePayload {
        guard let response = try? decoder.decode(LeaseResponse.self, from: data) else {
            throw CentralLicenceServiceError.invalidLease
        }
        let lease = try CentralLicenceLeaseCodec.verify(
            response.lease,
            publicKeyData: configuration.leasePublicKey,
            expectedLicence: licence
        )
        serverDateReference = lease.issuedAt
        serverClockReference = clock.now
        return lease
    }

    private func sendAuthenticated(
        method: String,
        path: String,
        body: Data,
        licence: AccessLicencePayload,
        devicePrivateKey: Curve25519.Signing.PrivateKey
    ) async throws -> Data {
        guard let timestamp = currentServerTimestampMilliseconds() else {
            throw CentralLicenceServiceError.unavailable("Open the app while online to establish trusted service time.")
        }
        let nonce = UUID().uuidString.lowercased()
        let bodyHash = SHA256.hash(data: body)
            .map { String(format: "%02x", $0) }
            .joined()
        let canonical = [method.uppercased(), path, String(timestamp), nonce, bodyHash]
            .joined(separator: "\n")
        let signature = try devicePrivateKey.signature(for: Data(canonical.utf8)).base64URL
        let headers = [
            "X-MDM-Licence-ID": licence.licenceID.uuidString.lowercased(),
            "X-MDM-Installation-ID": licence.installationID.uuidString.lowercased(),
            "X-MDM-Timestamp": String(timestamp),
            "X-MDM-Nonce": nonce,
            "X-MDM-Signature": signature
        ]
        return try await send(method: method, path: path, body: body, headers: headers)
    }

    private func send(
        method: String,
        path: String,
        body: Data? = nil,
        headers: [String: String] = [:]
    ) async throws -> Data {
        let url = endpoint(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw CentralLicenceServiceError.unavailable("No HTTP response was received.")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw mapServiceError(status: http.statusCode, data: data)
            }
            return data
        } catch let error as CentralLicenceServiceError {
            throw error
        } catch {
            throw CentralLicenceServiceError.unavailable(error.localizedDescription)
        }
    }

    private func endpoint(_ path: String) -> URL {
        var url = configuration.baseURL
        for component in path.split(separator: "/") {
            url.appendPathComponent(String(component))
        }
        return url
    }

    private func currentServerTimestampMilliseconds() -> Int64? {
        guard let serverDateReference, let serverClockReference else { return nil }
        let elapsed = serverClockReference.duration(to: clock.now)
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
        return Int64((serverDateReference.timeIntervalSince1970 + seconds) * 1_000)
    }

    private func mapServiceError(status: Int, data: Data) -> CentralLicenceServiceError {
        let message = (try? decoder.decode(ErrorResponse.self, from: data).error)
            ?? "The licence service returned HTTP \(status)."
        let lowercased = message.lowercased()
        if lowercased.contains("revoked") { return .revoked }
        if lowercased.contains("replaced") { return .replaced }
        if lowercased.contains("expired") { return .expired }
        if status >= 500 || status == 429 { return .unavailable(message) }
        return .denied(message)
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private var decoder: JSONDecoder { JSONDecoder() }
}

enum CentralLicenceLeaseCodec {
    static let prefix = "MDML1"

    static func verify(
        _ token: String,
        publicKeyData: Data,
        expectedLicence: AccessLicencePayload
    ) throws -> CentralLicenceLeasePayload {
        let parts = token.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
        guard parts.count == 3,
              parts[0] == Substring(prefix),
              let payloadData = Data(base64URL: String(parts[1])),
              let signature = Data(base64URL: String(parts[2])),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData),
              publicKey.isValidSignature(signature, for: payloadData) else {
            throw CentralLicenceServiceError.invalidLease
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let lease = try? decoder.decode(CentralLicenceLeasePayload.self, from: payloadData),
              lease.version == CentralLicenceLeasePayload.currentVersion,
              lease.licenceID == expectedLicence.licenceID,
              lease.installationID == expectedLicence.installationID,
              lease.bundleIdentifier == expectedLicence.bundleIdentifier,
              lease.role == expectedLicence.role,
              lease.duration > 0,
              lease.duration <= CentralLicenceLeasePayload.maximumDuration else {
            throw CentralLicenceServiceError.invalidLease
        }
        return lease
    }
}

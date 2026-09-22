import CryptoKit
import Foundation

enum AccessRole: String, Codable, CaseIterable, Equatable {
    case annualUser
    case permanentUser
    case licenceAdministrator

    var title: String {
        switch self {
        case .annualUser: "Annual user"
        case .permanentUser: "Permanent user"
        case .licenceAdministrator: "Licence administrator"
        }
    }

    var isPermanent: Bool {
        self != .annualUser
    }
}

enum AppDistributionEdition: String, Equatable {
    case development
    case standardUser = "standard-user"
    case licenceAdministrator = "licence-administrator"

    var title: String {
        switch self {
        case .development: "Development"
        case .standardUser: "Standard user"
        case .licenceAdministrator: "Licence administrator"
        }
    }

    func allows(_ role: AccessRole) -> Bool {
        switch self {
        case .development:
            true
        case .standardUser:
            role == .annualUser || role == .permanentUser
        case .licenceAdministrator:
            role == .licenceAdministrator
        }
    }
}

struct AppDistributionPolicy: Equatable {
    var edition: AppDistributionEdition
    var requiresOnlineLicenceCheck: Bool
    var requiresCentralLicenceService: Bool
    var standardBundleIdentifier: String?

    init(
        edition: AppDistributionEdition,
        requiresOnlineLicenceCheck: Bool,
        requiresCentralLicenceService: Bool = false,
        standardBundleIdentifier: String? = nil
    ) {
        self.edition = edition
        self.requiresOnlineLicenceCheck = requiresOnlineLicenceCheck
        self.requiresCentralLicenceService = requiresCentralLicenceService
        self.standardBundleIdentifier = standardBundleIdentifier
    }

    func canIssueAnnualLicence(
        for recipientBundleIdentifier: String,
        currentBundleIdentifier: String
    ) -> Bool {
        switch edition {
        case .development:
            recipientBundleIdentifier == currentBundleIdentifier
                || recipientBundleIdentifier == standardBundleIdentifier
        case .licenceAdministrator:
            recipientBundleIdentifier == standardBundleIdentifier
        case .standardUser:
            false
        }
    }

    static var current: AppDistributionPolicy {
        let bundle = Bundle.main
        let configuredEdition = (bundle.object(forInfoDictionaryKey: "MDMCopilotDistributionEdition") as? String)
            .flatMap(AppDistributionEdition.init(rawValue:))

        #if DEBUG
        let fallbackEdition: AppDistributionEdition = .development
        #else
        let fallbackEdition: AppDistributionEdition = .standardUser
        #endif

        let onlineValue = bundle.object(forInfoDictionaryKey: "MDMCopilotRequiresOnlineLicenceCheck")
        let requiresOnline: Bool
        if let boolValue = onlineValue as? Bool {
            requiresOnline = boolValue
        } else if let stringValue = onlineValue as? String {
            requiresOnline = ["1", "true", "yes"].contains(stringValue.lowercased())
        } else {
            requiresOnline = false
        }

        let centralValue = bundle.object(forInfoDictionaryKey: "MDMCopilotRequiresCentralLicenceService")
        let requiresCentral: Bool
        if let boolValue = centralValue as? Bool {
            requiresCentral = boolValue
        } else if let stringValue = centralValue as? String {
            requiresCentral = ["1", "true", "yes"].contains(stringValue.lowercased())
        } else {
            requiresCentral = false
        }

        let standardBundleIdentifier = (bundle.object(
            forInfoDictionaryKey: "MDMCopilotStandardBundleIdentifier"
        ) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        return AppDistributionPolicy(
            edition: configuredEdition ?? fallbackEdition,
            requiresOnlineLicenceCheck: requiresOnline,
            requiresCentralLicenceService: requiresCentral,
            standardBundleIdentifier: standardBundleIdentifier?.isEmpty == false
                ? standardBundleIdentifier
                : nil
        )
    }
}

struct AccessLicencePayload: Codable, Equatable {
    static let currentVersion = 1

    var version: Int = currentVersion
    var licenceID: UUID
    var subject: String
    var role: AccessRole
    var issuedAt: Date
    var expiresAt: Date?
    var installationID: UUID
    var bundleIdentifier: String
}

struct InstallationRequest: Codable, Equatable {
    static let currentVersion = 1

    var version: Int = currentVersion
    var installationID: UUID
    var bundleIdentifier: String
}

struct IssuerPrivateKeyDocument: Codable, Equatable {
    static let currentVersion = 1

    var version: Int = currentVersion
    var privateKey: String
}

enum IssuedLicenceState: String, Codable, Equatable {
    case active
    case revoked
    case replaced

    var title: String {
        switch self {
        case .active: "Active"
        case .revoked: "Revoked"
        case .replaced: "Replaced"
        }
    }
}

struct IssuedLicenceRecord: Codable, Identifiable, Equatable {
    var id: UUID { licenceID }

    var licenceID: UUID
    var displayName: String
    var signedSubject: String
    var notes: String
    var role: AccessRole
    var issuedAt: Date
    var expiresAt: Date?
    var installationID: UUID
    var bundleIdentifier: String
    var accessCode: String
    var state: IssuedLicenceState
    var updatedAt: Date
    var revokedAt: Date?
    var replacedByLicenceID: UUID?

    func status(at date: Date) -> String {
        if state != .active {
            return state.title
        }
        if let expiresAt, expiresAt <= date {
            return "Expired"
        }
        return state.title
    }
}

struct IssuedLicenceRegistryDocument: Codable, Equatable {
    static let currentVersion = 1

    var version: Int = currentVersion
    var records: [IssuedLicenceRecord]
}

enum AccessLicenceError: LocalizedError, Equatable {
    case malformedCode
    case unsupportedVersion
    case invalidSignature
    case wrongApplication
    case wrongInstallation
    case invalidValidityPeriod
    case notYetValid
    case expired
    case trustedIssuerNotConfigured
    case trustedTimeUnavailable
    case roleNotAllowed
    case centralServiceNotConfigured
    case administratorRequired
    case issuerKeyMissing
    case issuerKeyDoesNotMatch
    case invalidSubject
    case issuedLicenceNotFound
    case issuedLicenceInactive

    var errorDescription: String? {
        switch self {
        case .malformedCode:
            "The access code is not in a valid MDM Profile Builder Demo format."
        case .unsupportedVersion:
            "This access code version is not supported by this app."
        case .invalidSignature:
            "The access code signature is invalid."
        case .wrongApplication:
            "This access code was issued for a different application."
        case .wrongInstallation:
            "This access code belongs to a different Mac installation. Request a new code for this installation."
        case .invalidValidityPeriod:
            "The access code has an invalid validity period."
        case .notYetValid:
            "The access code was issued in the future and cannot be used."
        case .expired:
            "This annual access code has expired. Request a new code from a licence administrator."
        case .trustedIssuerNotConfigured:
            "This build does not contain the trusted licence issuer public key."
        case .trustedTimeUnavailable:
            "This edition needs an internet connection to verify its licence. Check the connection and try again."
        case .roleNotAllowed:
            "This access code is for a different app edition. Use a standard-user code with the standard installer or an administrator code with the administrator installer."
        case .centralServiceNotConfigured:
            "This packaged edition is missing its central licence-service configuration. Install a correctly configured release package."
        case .administratorRequired:
            "A licence administrator role is required for this action."
        case .issuerKeyMissing:
            "The licence issuer key has not been installed on this administrator Mac."
        case .issuerKeyDoesNotMatch:
            "The supplied issuer key does not match this app's trusted public key."
        case .invalidSubject:
            "Enter the name of the person or organisation receiving the licence."
        case .issuedLicenceNotFound:
            "The issued licence record could not be found."
        case .issuedLicenceInactive:
            "This licence is already revoked or has been replaced."
        }
    }
}

enum AccessLicenceCodec {
    static let licencePrefix = "MDMC1"
    static let requestPrefix = "MDMR1"
    static let maximumAnnualDuration: TimeInterval = 367 * 24 * 60 * 60
    static let futureIssueTolerance: TimeInterval = 10 * 60

    static func sign(
        _ payload: AccessLicencePayload,
        using privateKey: Curve25519.Signing.PrivateKey
    ) throws -> String {
        let payloadData = try encoder.encode(payload)
        let signature = try privateKey.signature(for: payloadData)
        return [licencePrefix, payloadData.base64URL, signature.base64URL]
            .joined(separator: ".")
    }

    static func verify(
        _ code: String,
        using publicKey: Curve25519.Signing.PublicKey
    ) throws -> AccessLicencePayload {
        let parts = code.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
        guard parts.count == 3,
              parts[0] == Substring(licencePrefix),
              let payloadData = Data(base64URL: String(parts[1])),
              let signature = Data(base64URL: String(parts[2])) else {
            throw AccessLicenceError.malformedCode
        }
        guard publicKey.isValidSignature(signature, for: payloadData) else {
            throw AccessLicenceError.invalidSignature
        }
        guard let payload = try? decoder.decode(AccessLicencePayload.self, from: payloadData) else {
            throw AccessLicenceError.malformedCode
        }
        guard payload.version == AccessLicencePayload.currentVersion else {
            throw AccessLicenceError.unsupportedVersion
        }
        return payload
    }

    static func validate(
        _ payload: AccessLicencePayload,
        installationID: UUID,
        bundleIdentifier: String,
        trustedDate: Date? = nil
    ) throws {
        guard payload.bundleIdentifier == bundleIdentifier else {
            throw AccessLicenceError.wrongApplication
        }
        guard payload.installationID == installationID else {
            throw AccessLicenceError.wrongInstallation
        }

        switch payload.role {
        case .annualUser:
            guard let expiresAt = payload.expiresAt,
                  expiresAt > payload.issuedAt,
                  expiresAt.timeIntervalSince(payload.issuedAt) <= maximumAnnualDuration else {
                throw AccessLicenceError.invalidValidityPeriod
            }
            guard let trustedDate else {
                throw AccessLicenceError.trustedTimeUnavailable
            }
            guard payload.issuedAt.timeIntervalSince(trustedDate) <= futureIssueTolerance else {
                throw AccessLicenceError.notYetValid
            }
            guard trustedDate < expiresAt else {
                throw AccessLicenceError.expired
            }
        case .permanentUser, .licenceAdministrator:
            guard payload.expiresAt == nil else {
                throw AccessLicenceError.invalidValidityPeriod
            }
        }
    }

    static func makeRequest(
        installationID: UUID,
        bundleIdentifier: String
    ) throws -> String {
        let request = InstallationRequest(
            installationID: installationID,
            bundleIdentifier: bundleIdentifier
        )
        return requestPrefix + "." + (try encoder.encode(request)).base64URL
    }

    static func decodeRequest(_ code: String) throws -> InstallationRequest {
        let parts = code.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
        guard parts.count == 2,
              parts[0] == Substring(requestPrefix),
              let data = Data(base64URL: String(parts[1])),
              let request = try? decoder.decode(InstallationRequest.self, from: data) else {
            throw AccessLicenceError.malformedCode
        }
        guard request.version == InstallationRequest.currentVersion else {
            throw AccessLicenceError.unsupportedVersion
        }
        return request
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URL: String) {
        var value = base64URL
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = value.count % 4
        if remainder != 0 {
            value.append(String(repeating: "=", count: 4 - remainder))
        }
        self.init(base64Encoded: value)
    }
}

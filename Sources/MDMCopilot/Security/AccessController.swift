import CryptoKit
import Foundation

enum AccessStatus: Equatable {
    case checking
    case locked(String)
    case active(AccessLicencePayload, verifiedAt: Date?)

    var licence: AccessLicencePayload? {
        guard case .active(let payload, _) = self else { return nil }
        return payload
    }
}

@MainActor
final class AccessController: ObservableObject {
    @Published private(set) var status: AccessStatus = .checking
    @Published private(set) var installationID: UUID
    @Published private(set) var issuerKeyInstalled = false
    @Published private(set) var issuedLicences: [IssuedLicenceRecord] = []
    @Published private(set) var licenceDirectoryError: String?
    @Published var isLicenceAdministrationPresented = false

    static let onlineRevalidationInterval: TimeInterval = 6 * 60 * 60
    static let centralRevalidationInterval: TimeInterval = 10 * 60
    static let centralRetryInterval: TimeInterval = 60
    private static let verificationPollInterval: TimeInterval = 30

    private enum Account {
        static let installationID = "installation-id"
        static let accessCode = "signed-access-code"
        static let issuerPrivateKey = "licence-issuer-private-key"
        static let developmentPublicKey = "development-trusted-public-key"
        static let issuedLicenceRegistry = "issued-licence-registry"
        static let installationSigningKey = "installation-signing-key"
    }

    private let secureStore: AccessSecureStoring
    private let timeProvider: TrustedTimeProviding
    private let centralService: (any CentralLicenceServicing)?
    private let devicePrivateKey: Curve25519.Signing.PrivateKey
    private let bundleIdentifier: String
    let distributionPolicy: AppDistributionPolicy
    private let trustedIssuerProvider: () throws -> Data?
    private let clock = ContinuousClock()
    private var storageError: Error?
    private var nextOnlineVerification: ContinuousClock.Instant?
    private var centralLeaseDeadline: ContinuousClock.Instant?

    init(
        secureStore: AccessSecureStoring = KeychainAccessSecureStore(),
        timeProvider: TrustedTimeProviding = HTTPSTrustedTimeProvider(),
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "dev.example.MDMProfileBuilder.local",
        distributionPolicy: AppDistributionPolicy = .current,
        centralService: (any CentralLicenceServicing)? = CentralLicenceServiceConfiguration.current.map {
            CloudflareCentralLicenceService(configuration: $0)
        },
        trustedIssuerProvider: (() throws -> Data?)? = nil
    ) {
        self.secureStore = secureStore
        self.timeProvider = timeProvider
        self.centralService = centralService
        self.bundleIdentifier = bundleIdentifier
        self.distributionPolicy = distributionPolicy

        if let trustedIssuerProvider {
            self.trustedIssuerProvider = trustedIssuerProvider
        } else {
            self.trustedIssuerProvider = {
                if let value = Bundle.main.object(forInfoDictionaryKey: "MDMCopilotLicencePublicKey") as? String,
                   let data = Data(base64Encoded: value.trimmingCharacters(in: .whitespacesAndNewlines)),
                   !data.isEmpty {
                    return data
                }
                #if DEBUG
                return try secureStore.load(account: Account.developmentPublicKey)
                #else
                return nil
                #endif
            }
        }

        var resolvedDevicePrivateKey = Curve25519.Signing.PrivateKey()
        do {
            if let data = try secureStore.load(account: Account.installationID),
               let value = String(data: data, encoding: .utf8),
               let existingID = UUID(uuidString: value) {
                installationID = existingID
            } else {
                let newID = UUID()
                try secureStore.save(Data(newID.uuidString.utf8), account: Account.installationID)
                installationID = newID
            }
            if let keyData = try secureStore.load(account: Account.installationSigningKey),
               let existingKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: keyData) {
                resolvedDevicePrivateKey = existingKey
            } else {
                resolvedDevicePrivateKey = Curve25519.Signing.PrivateKey()
                try secureStore.save(
                    resolvedDevicePrivateKey.rawRepresentation,
                    account: Account.installationSigningKey
                )
            }
            issuerKeyInstalled = try secureStore.load(account: Account.issuerPrivateKey) != nil
        } catch {
            installationID = UUID()
            storageError = error
            status = .locked("The installation identity could not be stored securely: \(error.localizedDescription)")
        }
        devicePrivateKey = resolvedDevicePrivateKey

        if storageError == nil {
            do {
                issuedLicences = try Self.loadIssuedLicences(from: secureStore)
            } catch {
                licenceDirectoryError = "The issued-user directory could not be loaded: \(error.localizedDescription)"
            }
        }
    }

    var installationRequestCode: String {
        (try? AccessLicenceCodec.makeRequest(
            installationID: installationID,
            bundleIdentifier: bundleIdentifier
        )) ?? "Request unavailable"
    }

    var activeLicence: AccessLicencePayload? { status.licence }
    var isAdministrator: Bool { activeLicence?.role == .licenceAdministrator }

    func checkInstallationRequest(_ code: String) -> InstallationRequestCheck {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return InstallationRequestCheck(isValid: false, message: "Paste an MDMR1 installation request code.")
        }
        do {
            let request = try AccessLicenceCodec.decodeRequest(trimmed)
            guard distributionPolicy.canIssueAnnualLicence(
                for: request.bundleIdentifier,
                currentBundleIdentifier: bundleIdentifier
            ) else {
                return InstallationRequestCheck(isValid: false, message: AccessLicenceError.wrongApplication.localizedDescription)
            }
            return InstallationRequestCheck(
                isValid: true,
                message: "Valid request for installation \(request.installationID.uuidString.lowercased())."
            )
        } catch {
            return InstallationRequestCheck(isValid: false, message: error.localizedDescription)
        }
    }

    func runVerificationLoop() async {
        await refreshAccess()
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(Self.verificationPollInterval))
            } catch {
                return
            }
            if let nextOnlineVerification,
               clock.now >= nextOnlineVerification {
                await refreshAccess()
            }
        }
    }

    func refreshAccess() async {
        guard storageError == nil else { return }
        let previousStatus = status
        let unexpiredCentralLease = centralLeaseDeadline.map { clock.now < $0 } ?? false
        nextOnlineVerification = nil
        if !unexpiredCentralLease {
            status = .checking
        }
        do {
            guard let data = try secureStore.load(account: Account.accessCode),
                  let code = String(data: data, encoding: .utf8) else {
                centralLeaseDeadline = nil
                status = .locked("Enter an access code to use MDM Profile Builder Demo.")
                return
            }
            status = try await evaluate(code, forceCentralActivation: centralLeaseDeadline == nil)
        } catch {
            if let centralError = error as? CentralLicenceServiceError,
               !centralError.isDefinitiveDenial,
               unexpiredCentralLease,
               case .active = previousStatus {
                status = previousStatus
                if let centralLeaseDeadline {
                    nextOnlineVerification = min(
                        centralLeaseDeadline,
                        clock.now.advanced(by: .seconds(Self.centralRetryInterval))
                    )
                }
            } else {
                centralLeaseDeadline = nil
                status = .locked(error.localizedDescription)
            }
        }
    }

    func activate(code: String) async {
        nextOnlineVerification = nil
        centralLeaseDeadline = nil
        status = .checking
        do {
            let evaluated = try await evaluate(code, forceCentralActivation: true)
            try secureStore.save(Data(code.trimmingCharacters(in: .whitespacesAndNewlines).utf8), account: Account.accessCode)
            status = evaluated
        } catch {
            status = .locked(error.localizedDescription)
        }
    }

    func deactivate() {
        nextOnlineVerification = nil
        centralLeaseDeadline = nil
        do {
            try secureStore.delete(account: Account.accessCode)
            status = .locked("Access has been removed from this Mac. The installation request ID is unchanged.")
        } catch {
            status = .locked(error.localizedDescription)
        }
    }

    func importIssuerPrivateKey(_ base64Value: String) throws {
        guard isAdministrator else { throw AccessLicenceError.administratorRequired }
        guard let privateData = Data(base64Encoded: base64Value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: privateData),
              let trustedData = try trustedIssuerProvider() else {
            throw AccessLicenceError.issuerKeyDoesNotMatch
        }
        guard privateKey.publicKey.rawRepresentation == trustedData else {
            throw AccessLicenceError.issuerKeyDoesNotMatch
        }
        try secureStore.save(privateData, account: Account.issuerPrivateKey)
        issuerKeyInstalled = true
    }

    func importIssuerPrivateKeyDocument(_ data: Data) throws {
        guard let document = try? JSONDecoder().decode(IssuerPrivateKeyDocument.self, from: data),
              document.version == IssuerPrivateKeyDocument.currentVersion else {
            throw AccessLicenceError.issuerKeyDoesNotMatch
        }
        try importIssuerPrivateKey(document.privateKey)
    }

    func refreshIssuedLicenceDirectory() async {
        guard distributionPolicy.requiresCentralLicenceService else { return }
        guard let centralService, let administrator = activeLicence, isAdministrator else {
            licenceDirectoryError = AccessLicenceError.administratorRequired.localizedDescription
            return
        }
        do {
            let remoteRecords = try await centralService.listIssuedLicences(
                administrator: administrator,
                devicePrivateKey: devicePrivateKey
            )
            let storedCodes = Dictionary(
                uniqueKeysWithValues: issuedLicences.map { ($0.licenceID, $0.accessCode) }
            )
            let mergedRecords = remoteRecords.map { remote in
                IssuedLicenceRecord(
                    licenceID: remote.licenceID,
                    displayName: remote.displayName,
                    signedSubject: remote.subject,
                    notes: remote.notes,
                    role: remote.role,
                    issuedAt: remote.issuedAt,
                    expiresAt: remote.expiresAt,
                    installationID: remote.installationID,
                    bundleIdentifier: remote.bundleIdentifier,
                    accessCode: storedCodes[remote.licenceID] ?? "",
                    state: remote.state,
                    updatedAt: remote.updatedAt,
                    revokedAt: remote.revokedAt,
                    replacedByLicenceID: remote.replacedByLicenceID
                )
            }
            try persistIssuedLicences(mergedRecords)
        } catch {
            licenceDirectoryError = "The central issued-user directory could not be refreshed: \(error.localizedDescription)"
        }
    }

    func issueAnnualLicence(subject: String, requestCode: String) async throws -> String {
        guard isAdministrator else { throw AccessLicenceError.administratorRequired }
        let cleanSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanSubject.isEmpty else { throw AccessLicenceError.invalidSubject }

        let request = try AccessLicenceCodec.decodeRequest(requestCode)
        guard distributionPolicy.canIssueAnnualLicence(
            for: request.bundleIdentifier,
            currentBundleIdentifier: bundleIdentifier
        ) else {
            throw AccessLicenceError.wrongApplication
        }
        let issued = try await makeAnnualLicence(subject: cleanSubject, request: request)
        if distributionPolicy.requiresCentralLicenceService {
            guard let centralService, let administrator = activeLicence else {
                throw AccessLicenceError.centralServiceNotConfigured
            }
            try await centralService.registerIssuedLicence(
                accessCode: issued.code,
                administrator: administrator,
                devicePrivateKey: devicePrivateKey
            )
        }
        var records = issuedLicences
        records.insert(record(for: issued.payload, code: issued.code), at: 0)
        try persistIssuedLicences(records)
        return issued.code
    }

    func updateIssuedLicence(
        id: UUID,
        displayName: String,
        notes: String
    ) async throws {
        guard isAdministrator else { throw AccessLicenceError.administratorRequired }
        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw AccessLicenceError.invalidSubject }
        guard let index = issuedLicences.firstIndex(where: { $0.id == id }) else {
            throw AccessLicenceError.issuedLicenceNotFound
        }

        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if distributionPolicy.requiresCentralLicenceService {
            guard let centralService, let administrator = activeLicence else {
                throw AccessLicenceError.centralServiceNotConfigured
            }
            try await centralService.updateLicenceMetadata(
                licenceID: id,
                displayName: cleanName,
                notes: cleanNotes,
                administrator: administrator,
                devicePrivateKey: devicePrivateKey
            )
        }
        var records = issuedLicences
        records[index].displayName = cleanName
        records[index].notes = cleanNotes
        records[index].updatedAt = Date()
        try persistIssuedLicences(records)
    }

    func reissueAnnualLicence(id: UUID, subject: String) async throws -> String {
        guard isAdministrator else { throw AccessLicenceError.administratorRequired }
        let cleanSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanSubject.isEmpty else { throw AccessLicenceError.invalidSubject }
        guard let oldIndex = issuedLicences.firstIndex(where: { $0.id == id }) else {
            throw AccessLicenceError.issuedLicenceNotFound
        }

        let oldRecord = issuedLicences[oldIndex]
        let request = InstallationRequest(
            installationID: oldRecord.installationID,
            bundleIdentifier: oldRecord.bundleIdentifier
        )
        let issued = try await makeAnnualLicence(subject: cleanSubject, request: request)
        if distributionPolicy.requiresCentralLicenceService {
            guard let centralService, let administrator = activeLicence else {
                throw AccessLicenceError.centralServiceNotConfigured
            }
            try await centralService.reissueLicence(
                oldLicenceID: id,
                accessCode: issued.code,
                administrator: administrator,
                devicePrivateKey: devicePrivateKey
            )
        }
        var records = issuedLicences
        records[oldIndex].state = .replaced
        records[oldIndex].updatedAt = issued.payload.issuedAt
        records[oldIndex].replacedByLicenceID = issued.payload.licenceID
        records.insert(record(for: issued.payload, code: issued.code, notes: oldRecord.notes), at: 0)
        try persistIssuedLicences(records)
        return issued.code
    }

    func revokeIssuedLicence(id: UUID) async throws {
        guard isAdministrator else { throw AccessLicenceError.administratorRequired }
        guard let index = issuedLicences.firstIndex(where: { $0.id == id }) else {
            throw AccessLicenceError.issuedLicenceNotFound
        }
        guard issuedLicences[index].state == .active else {
            throw AccessLicenceError.issuedLicenceInactive
        }

        let revokedAt: Date
        if distributionPolicy.requiresCentralLicenceService {
            guard let centralService, let administrator = activeLicence else {
                throw AccessLicenceError.centralServiceNotConfigured
            }
            revokedAt = try await centralService.revokeLicence(
                licenceID: id,
                administrator: administrator,
                devicePrivateKey: devicePrivateKey
            )
        } else {
            revokedAt = try await timeProvider.trustedDate()
        }
        var records = issuedLicences
        records[index].state = .revoked
        records[index].revokedAt = revokedAt
        records[index].updatedAt = revokedAt
        try persistIssuedLicences(records)
    }

    #if DEBUG
    func createDevelopmentAdministrator() async {
        status = .checking
        do {
            let privateKey: Curve25519.Signing.PrivateKey
            if let existing = try secureStore.load(account: Account.issuerPrivateKey),
               let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: existing) {
                privateKey = key
            } else {
                privateKey = Curve25519.Signing.PrivateKey()
                try secureStore.save(privateKey.rawRepresentation, account: Account.issuerPrivateKey)
            }
            try secureStore.save(privateKey.publicKey.rawRepresentation, account: Account.developmentPublicKey)
            issuerKeyInstalled = true

            let payload = AccessLicencePayload(
                licenceID: UUID(),
                subject: "Local development administrator",
                role: .licenceAdministrator,
                issuedAt: Date(),
                expiresAt: nil,
                installationID: installationID,
                bundleIdentifier: bundleIdentifier
            )
            let code = try AccessLicenceCodec.sign(payload, using: privateKey)
            try secureStore.save(Data(code.utf8), account: Account.accessCode)
            status = .active(payload, verifiedAt: nil)
            isLicenceAdministrationPresented = true
        } catch {
            status = .locked(error.localizedDescription)
        }
    }
    #endif

    private func evaluate(
        _ code: String,
        forceCentralActivation: Bool
    ) async throws -> AccessStatus {
        guard let publicKeyData = try trustedIssuerProvider(),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData) else {
            throw AccessLicenceError.trustedIssuerNotConfigured
        }
        let payload = try AccessLicenceCodec.verify(code, using: publicKey)
        guard distributionPolicy.edition.allows(payload.role) else {
            throw AccessLicenceError.roleNotAllowed
        }

        if distributionPolicy.requiresCentralLicenceService {
            guard let centralService else {
                throw AccessLicenceError.centralServiceNotConfigured
            }
            let lease: CentralLicenceLeasePayload
            if forceCentralActivation {
                lease = try await centralService.activate(
                    accessCode: code,
                    licence: payload,
                    devicePrivateKey: devicePrivateKey
                )
            } else {
                lease = try await centralService.check(
                    licence: payload,
                    devicePrivateKey: devicePrivateKey
                )
            }
            try AccessLicenceCodec.validate(
                payload,
                installationID: installationID,
                bundleIdentifier: bundleIdentifier,
                trustedDate: lease.issuedAt
            )
            centralLeaseDeadline = clock.now.advanced(by: .seconds(lease.duration))
            let secondsUntilExpiry = payload.expiresAt?.timeIntervalSince(lease.issuedAt)
                ?? Self.centralRevalidationInterval
            nextOnlineVerification = clock.now.advanced(by: .seconds(min(
                Self.centralRevalidationInterval,
                max(0, secondsUntilExpiry)
            )))
            return .active(payload, verifiedAt: lease.issuedAt)
        }

        if payload.role == .annualUser || distributionPolicy.requiresOnlineLicenceCheck {
            let trustedDate: Date
            do {
                trustedDate = try await timeProvider.trustedDate()
            } catch {
                throw AccessLicenceError.trustedTimeUnavailable
            }
            try AccessLicenceCodec.validate(
                payload,
                installationID: installationID,
                bundleIdentifier: bundleIdentifier,
                trustedDate: trustedDate
            )
            let nextInterval: TimeInterval
            if let expiresAt = payload.expiresAt {
                let secondsUntilExpiry = expiresAt.timeIntervalSince(trustedDate)
                nextInterval = min(Self.onlineRevalidationInterval, max(0, secondsUntilExpiry))
            } else {
                nextInterval = Self.onlineRevalidationInterval
            }
            nextOnlineVerification = clock.now.advanced(by: .seconds(nextInterval))
            return .active(payload, verifiedAt: trustedDate)
        }
        nextOnlineVerification = nil
        try AccessLicenceCodec.validate(
            payload,
            installationID: installationID,
            bundleIdentifier: bundleIdentifier
        )
        return .active(payload, verifiedAt: nil)
    }

    private func makeAnnualLicence(
        subject: String,
        request: InstallationRequest
    ) async throws -> (payload: AccessLicencePayload, code: String) {
        guard let privateData = try secureStore.load(account: Account.issuerPrivateKey),
              let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: privateData) else {
            throw AccessLicenceError.issuerKeyMissing
        }
        guard let trustedData = try trustedIssuerProvider(),
              privateKey.publicKey.rawRepresentation == trustedData else {
            throw AccessLicenceError.issuerKeyDoesNotMatch
        }

        let issuedAt = try await timeProvider.trustedDate()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let expiresAt = calendar.date(byAdding: .year, value: 1, to: issuedAt) else {
            throw AccessLicenceError.invalidValidityPeriod
        }
        let payload = AccessLicencePayload(
            licenceID: UUID(),
            subject: subject,
            role: .annualUser,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            installationID: request.installationID,
            bundleIdentifier: request.bundleIdentifier
        )
        return (payload, try AccessLicenceCodec.sign(payload, using: privateKey))
    }

    private func record(
        for payload: AccessLicencePayload,
        code: String,
        notes: String = ""
    ) -> IssuedLicenceRecord {
        IssuedLicenceRecord(
            licenceID: payload.licenceID,
            displayName: payload.subject,
            signedSubject: payload.subject,
            notes: notes,
            role: payload.role,
            issuedAt: payload.issuedAt,
            expiresAt: payload.expiresAt,
            installationID: payload.installationID,
            bundleIdentifier: payload.bundleIdentifier,
            accessCode: code,
            state: .active,
            updatedAt: payload.issuedAt,
            revokedAt: nil,
            replacedByLicenceID: nil
        )
    }

    private func persistIssuedLicences(_ records: [IssuedLicenceRecord]) throws {
        let document = IssuedLicenceRegistryDocument(records: records)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try secureStore.save(try encoder.encode(document), account: Account.issuedLicenceRegistry)
        issuedLicences = records
        licenceDirectoryError = nil
    }

    private static func loadIssuedLicences(
        from secureStore: AccessSecureStoring
    ) throws -> [IssuedLicenceRecord] {
        guard let data = try secureStore.load(account: Account.issuedLicenceRegistry) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let document = try decoder.decode(IssuedLicenceRegistryDocument.self, from: data)
        guard document.version == IssuedLicenceRegistryDocument.currentVersion else {
            throw AccessLicenceError.unsupportedVersion
        }
        return document.records
    }
}

struct InstallationRequestCheck: Equatable {
    var isValid: Bool
    var message: String
}

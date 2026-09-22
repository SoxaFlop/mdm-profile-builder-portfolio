import CryptoKit
import XCTest
@testable import MDMCopilot

final class AccessLicenceCodecTests: XCTestCase {
    private let bundleIdentifier = "dev.example.MDMProfileBuilder.local"

    func testSignedAnnualLicenceValidatesForIntendedInstallation() throws {
        let key = Curve25519.Signing.PrivateKey()
        let installationID = UUID()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let payload = annualPayload(installationID: installationID, issuedAt: now)

        let code = try AccessLicenceCodec.sign(payload, using: key)
        let verified = try AccessLicenceCodec.verify(code, using: key.publicKey)

        XCTAssertNoThrow(try AccessLicenceCodec.validate(
            verified,
            installationID: installationID,
            bundleIdentifier: bundleIdentifier,
            trustedDate: now.addingTimeInterval(60)
        ))
    }

    func testTamperedCodeIsRejected() throws {
        let key = Curve25519.Signing.PrivateKey()
        let payload = annualPayload(installationID: UUID(), issuedAt: Date())
        var parts = try AccessLicenceCodec.sign(payload, using: key).split(separator: ".").map(String.init)
        let firstSignatureCharacter = parts[2].startIndex
        parts[2].replaceSubrange(
            firstSignatureCharacter...firstSignatureCharacter,
            with: parts[2].first == "A" ? "B" : "A"
        )
        let code = parts.joined(separator: ".")

        XCTAssertThrowsError(try AccessLicenceCodec.verify(code, using: key.publicKey)) { error in
            XCTAssertEqual(error as? AccessLicenceError, .invalidSignature)
        }
    }

    func testCodeCannotMoveToAnotherInstallation() throws {
        let key = Curve25519.Signing.PrivateKey()
        let now = Date()
        let payload = annualPayload(installationID: UUID(), issuedAt: now)
        let code = try AccessLicenceCodec.sign(payload, using: key)
        let verified = try AccessLicenceCodec.verify(code, using: key.publicKey)

        XCTAssertThrowsError(try AccessLicenceCodec.validate(
            verified,
            installationID: UUID(),
            bundleIdentifier: bundleIdentifier,
            trustedDate: now
        )) { error in
            XCTAssertEqual(error as? AccessLicenceError, .wrongInstallation)
        }
    }

    func testExpiredAnnualLicenceIsRejectedUsingTrustedTime() throws {
        let key = Curve25519.Signing.PrivateKey()
        let issuedAt = Date(timeIntervalSince1970: 1_900_000_000)
        let payload = annualPayload(installationID: UUID(), issuedAt: issuedAt)
        let code = try AccessLicenceCodec.sign(payload, using: key)
        let verified = try AccessLicenceCodec.verify(code, using: key.publicKey)

        XCTAssertThrowsError(try AccessLicenceCodec.validate(
            verified,
            installationID: payload.installationID,
            bundleIdentifier: bundleIdentifier,
            trustedDate: payload.expiresAt!
        )) { error in
            XCTAssertEqual(error as? AccessLicenceError, .expired)
        }
    }

    func testPermanentRoleHasNoExpiryOrTrustedTimeRequirement() throws {
        let key = Curve25519.Signing.PrivateKey()
        let payload = AccessLicencePayload(
            licenceID: UUID(),
            subject: "Permanent technician",
            role: .permanentUser,
            issuedAt: Date(),
            expiresAt: nil,
            installationID: UUID(),
            bundleIdentifier: bundleIdentifier
        )
        let code = try AccessLicenceCodec.sign(payload, using: key)
        let verified = try AccessLicenceCodec.verify(code, using: key.publicKey)

        XCTAssertNoThrow(try AccessLicenceCodec.validate(
            verified,
            installationID: payload.installationID,
            bundleIdentifier: bundleIdentifier
        ))
    }

    private func annualPayload(installationID: UUID, issuedAt: Date) -> AccessLicencePayload {
        AccessLicencePayload(
            licenceID: UUID(),
            subject: "Annual technician",
            role: .annualUser,
            issuedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(365 * 24 * 60 * 60),
            installationID: installationID,
            bundleIdentifier: bundleIdentifier
        )
    }
}

final class CentralLicenceLeaseCodecTests: XCTestCase {
    private let bundleIdentifier = "dev.example.MDMProfileBuilder"

    func testValidCentralLeaseIsAcceptedForTheExpectedLicence() throws {
        let leaseKey = Curve25519.Signing.PrivateKey()
        let licence = licencePayload()
        let issuedAt = Date(timeIntervalSince1970: 2_000_000_000)
        let lease = CentralLicenceLeasePayload(
            version: CentralLicenceLeasePayload.currentVersion,
            licenceID: licence.licenceID,
            installationID: licence.installationID,
            bundleIdentifier: licence.bundleIdentifier,
            role: licence.role,
            issuedAt: issuedAt,
            validUntil: issuedAt.addingTimeInterval(15 * 60)
        )

        let verified = try CentralLicenceLeaseCodec.verify(
            try signLease(lease, using: leaseKey),
            publicKeyData: leaseKey.publicKey.rawRepresentation,
            expectedLicence: licence
        )

        XCTAssertEqual(verified, lease)
    }

    func testCentralLeaseCannotBeUsedForAnotherLicence() throws {
        let leaseKey = Curve25519.Signing.PrivateKey()
        let licence = licencePayload()
        let issuedAt = Date(timeIntervalSince1970: 2_000_000_000)
        let lease = CentralLicenceLeasePayload(
            version: CentralLicenceLeasePayload.currentVersion,
            licenceID: UUID(),
            installationID: licence.installationID,
            bundleIdentifier: licence.bundleIdentifier,
            role: licence.role,
            issuedAt: issuedAt,
            validUntil: issuedAt.addingTimeInterval(15 * 60)
        )

        XCTAssertThrowsError(try CentralLicenceLeaseCodec.verify(
            try signLease(lease, using: leaseKey),
            publicKeyData: leaseKey.publicKey.rawRepresentation,
            expectedLicence: licence
        )) { error in
            XCTAssertEqual(error as? CentralLicenceServiceError, .invalidLease)
        }
    }

    private func licencePayload() -> AccessLicencePayload {
        let issuedAt = Date(timeIntervalSince1970: 2_000_000_000)
        return AccessLicencePayload(
            licenceID: UUID(),
            subject: "Annual technician",
            role: .annualUser,
            issuedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(365 * 24 * 60 * 60),
            installationID: UUID(),
            bundleIdentifier: bundleIdentifier
        )
    }

    private func signLease(
        _ lease: CentralLicenceLeasePayload,
        using privateKey: Curve25519.Signing.PrivateKey
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let payload = try encoder.encode(lease)
        let signature = try privateKey.signature(for: payload)
        return [CentralLicenceLeaseCodec.prefix, payload.base64URL, signature.base64URL]
            .joined(separator: ".")
    }
}

@MainActor
final class AccessControllerTests: XCTestCase {
    private let bundleIdentifier = "dev.example.MDMProfileBuilder.local"

    func testAdministratorCanIssueExactlyOneCalendarYearAnnualCode() async throws {
        let store = InMemoryAccessStore()
        let issuer = Curve25519.Signing.PrivateKey()
        let trustedDate = Date(timeIntervalSince1970: 2_000_000_000)
        let controller = AccessController(
            secureStore: store,
            timeProvider: FixedTrustedTimeProvider(date: trustedDate),
            bundleIdentifier: bundleIdentifier,
            trustedIssuerProvider: { issuer.publicKey.rawRepresentation }
        )
        let adminPayload = AccessLicencePayload(
            licenceID: UUID(),
            subject: "Licensing admin",
            role: .licenceAdministrator,
            issuedAt: trustedDate,
            expiresAt: nil,
            installationID: controller.installationID,
            bundleIdentifier: bundleIdentifier
        )
        await controller.activate(code: try AccessLicenceCodec.sign(adminPayload, using: issuer))
        try controller.importIssuerPrivateKey(issuer.rawRepresentation.base64EncodedString())

        let recipientID = UUID()
        let request = try AccessLicenceCodec.makeRequest(
            installationID: recipientID,
            bundleIdentifier: bundleIdentifier
        )
        let code = try await controller.issueAnnualLicence(subject: "School technician", requestCode: request)
        let issued = try AccessLicenceCodec.verify(code, using: issuer.publicKey)

        XCTAssertEqual(issued.role, .annualUser)
        XCTAssertEqual(issued.installationID, recipientID)
        XCTAssertEqual(issued.issuedAt, trustedDate)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(issued.expiresAt, calendar.date(byAdding: .year, value: 1, to: trustedDate))
        XCTAssertEqual(controller.issuedLicences.count, 1)
        XCTAssertEqual(controller.issuedLicences.first?.displayName, "School technician")
        XCTAssertEqual(controller.issuedLicences.first?.state, .active)
        XCTAssertEqual(controller.issuedLicences.first?.accessCode, code)
    }

    func testIssuedLicenceDirectoryPersistsEditsInSecureStore() async throws {
        let store = InMemoryAccessStore()
        let issuer = Curve25519.Signing.PrivateKey()
        let trustedDate = Date(timeIntervalSince1970: 2_000_000_000)
        let controller = try await administratorController(
            store: store,
            issuer: issuer,
            trustedDate: trustedDate
        )
        let request = try AccessLicenceCodec.makeRequest(
            installationID: UUID(),
            bundleIdentifier: bundleIdentifier
        )
        _ = try await controller.issueAnnualLicence(subject: "Original name", requestCode: request)
        let licenceID = try XCTUnwrap(controller.issuedLicences.first?.id)

        try await controller.updateIssuedLicence(
            id: licenceID,
            displayName: "Edited technician",
            notes: "Johannesburg campus"
        )

        let restored = AccessController(
            secureStore: store,
            timeProvider: FixedTrustedTimeProvider(date: trustedDate),
            bundleIdentifier: bundleIdentifier,
            trustedIssuerProvider: { issuer.publicKey.rawRepresentation }
        )
        XCTAssertEqual(restored.issuedLicences.first?.displayName, "Edited technician")
        XCTAssertEqual(restored.issuedLicences.first?.signedSubject, "Original name")
        XCTAssertEqual(restored.issuedLicences.first?.notes, "Johannesburg campus")
    }

    func testReissuingCreatesNewCodeAndMarksOldRecordReplaced() async throws {
        let store = InMemoryAccessStore()
        let issuer = Curve25519.Signing.PrivateKey()
        let trustedDate = Date(timeIntervalSince1970: 2_000_000_000)
        let controller = try await administratorController(
            store: store,
            issuer: issuer,
            trustedDate: trustedDate
        )
        let installationID = UUID()
        let request = try AccessLicenceCodec.makeRequest(
            installationID: installationID,
            bundleIdentifier: bundleIdentifier
        )
        _ = try await controller.issueAnnualLicence(subject: "Original name", requestCode: request)
        let oldID = try XCTUnwrap(controller.issuedLicences.first?.id)

        let replacementCode = try await controller.reissueAnnualLicence(
            id: oldID,
            subject: "Updated name"
        )
        let replacement = try AccessLicenceCodec.verify(replacementCode, using: issuer.publicKey)

        XCTAssertEqual(controller.issuedLicences.count, 2)
        XCTAssertEqual(controller.issuedLicences.first?.id, replacement.licenceID)
        XCTAssertEqual(controller.issuedLicences.first?.signedSubject, "Updated name")
        XCTAssertEqual(controller.issuedLicences.first?.installationID, installationID)
        let oldRecord = try XCTUnwrap(controller.issuedLicences.first { $0.id == oldID })
        XCTAssertEqual(oldRecord.state, .replaced)
        XCTAssertEqual(oldRecord.replacedByLicenceID, replacement.licenceID)
    }

    func testRevocationIsRecordedButDoesNotInvalidateOfflineSignedCode() async throws {
        let store = InMemoryAccessStore()
        let issuer = Curve25519.Signing.PrivateKey()
        let trustedDate = Date(timeIntervalSince1970: 2_000_000_000)
        let controller = try await administratorController(
            store: store,
            issuer: issuer,
            trustedDate: trustedDate
        )
        let installationID = UUID()
        let request = try AccessLicenceCodec.makeRequest(
            installationID: installationID,
            bundleIdentifier: bundleIdentifier
        )
        let code = try await controller.issueAnnualLicence(subject: "Revoked user", requestCode: request)
        let licenceID = try XCTUnwrap(controller.issuedLicences.first?.id)

        try await controller.revokeIssuedLicence(id: licenceID)

        XCTAssertEqual(controller.issuedLicences.first?.state, .revoked)
        XCTAssertEqual(controller.issuedLicences.first?.revokedAt, trustedDate)
        let signedPayload = try AccessLicenceCodec.verify(code, using: issuer.publicKey)
        XCTAssertNoThrow(try AccessLicenceCodec.validate(
            signedPayload,
            installationID: installationID,
            bundleIdentifier: bundleIdentifier,
            trustedDate: trustedDate.addingTimeInterval(60)
        ))
    }

    #if DEBUG
    func testDevelopmentAdministratorOpensReadyLicenceSetup() async {
        let controller = AccessController(
            secureStore: InMemoryAccessStore(),
            timeProvider: FixedTrustedTimeProvider(date: Date()),
            bundleIdentifier: bundleIdentifier
        )

        await controller.createDevelopmentAdministrator()

        XCTAssertTrue(controller.isAdministrator)
        XCTAssertTrue(controller.issuerKeyInstalled)
        XCTAssertTrue(controller.isLicenceAdministrationPresented)
        XCTAssertTrue(controller.checkInstallationRequest(controller.installationRequestCode).isValid)
    }
    #endif

    func testAnnualUserCannotIssueCodes() async throws {
        let store = InMemoryAccessStore()
        let issuer = Curve25519.Signing.PrivateKey()
        let now = Date()
        let controller = AccessController(
            secureStore: store,
            timeProvider: FixedTrustedTimeProvider(date: now),
            bundleIdentifier: bundleIdentifier,
            trustedIssuerProvider: { issuer.publicKey.rawRepresentation }
        )
        let userPayload = AccessLicencePayload(
            licenceID: UUID(),
            subject: "Annual user",
            role: .annualUser,
            issuedAt: now,
            expiresAt: now.addingTimeInterval(365 * 24 * 60 * 60),
            installationID: controller.installationID,
            bundleIdentifier: bundleIdentifier
        )
        await controller.activate(code: try AccessLicenceCodec.sign(userPayload, using: issuer))

        do {
            _ = try await controller.issueAnnualLicence(
                subject: "Another user",
                requestCode: controller.installationRequestCode
            )
            XCTFail("An annual user must not be able to issue licences")
        } catch {
            XCTAssertEqual(error as? AccessLicenceError, .administratorRequired)
        }
    }

    func testAnnualAccessFailsClosedWithoutFreshTrustedTime() async throws {
        let store = InMemoryAccessStore()
        let issuer = Curve25519.Signing.PrivateKey()
        let now = Date()
        let onlineController = AccessController(
            secureStore: store,
            timeProvider: FixedTrustedTimeProvider(date: now),
            bundleIdentifier: bundleIdentifier,
            trustedIssuerProvider: { issuer.publicKey.rawRepresentation }
        )
        let payload = AccessLicencePayload(
            licenceID: UUID(),
            subject: "Annual user",
            role: .annualUser,
            issuedAt: now,
            expiresAt: now.addingTimeInterval(365 * 24 * 60 * 60),
            installationID: onlineController.installationID,
            bundleIdentifier: bundleIdentifier
        )
        await onlineController.activate(code: try AccessLicenceCodec.sign(payload, using: issuer))
        XCTAssertEqual(onlineController.activeLicence?.role, .annualUser)

        let offlineController = AccessController(
            secureStore: store,
            timeProvider: UnavailableTrustedTimeProvider(),
            bundleIdentifier: bundleIdentifier,
            trustedIssuerProvider: { issuer.publicKey.rawRepresentation }
        )
        await offlineController.refreshAccess()

        guard case .locked(let message) = offlineController.status else {
            return XCTFail("Annual access must lock when trusted time is unavailable")
        }
        XCTAssertTrue(message.contains("internet connection"))
    }

    func testStandardEditionRejectsAdministratorCode() async throws {
        let store = InMemoryAccessStore()
        let issuer = Curve25519.Signing.PrivateKey()
        let now = Date()
        let controller = AccessController(
            secureStore: store,
            timeProvider: FixedTrustedTimeProvider(date: now),
            bundleIdentifier: bundleIdentifier,
            distributionPolicy: AppDistributionPolicy(
                edition: .standardUser,
                requiresOnlineLicenceCheck: true
            ),
            trustedIssuerProvider: { issuer.publicKey.rawRepresentation }
        )
        let payload = AccessLicencePayload(
            licenceID: UUID(),
            subject: "Administrator",
            role: .licenceAdministrator,
            issuedAt: now,
            expiresAt: nil,
            installationID: controller.installationID,
            bundleIdentifier: bundleIdentifier
        )

        await controller.activate(code: try AccessLicenceCodec.sign(payload, using: issuer))

        guard case .locked(let message) = controller.status else {
            return XCTFail("The standard edition must reject administrator access")
        }
        XCTAssertTrue(message.contains("different app edition"))
    }

    func testAdministratorEditionRejectsUserCode() async throws {
        let store = InMemoryAccessStore()
        let issuer = Curve25519.Signing.PrivateKey()
        let now = Date()
        let controller = AccessController(
            secureStore: store,
            timeProvider: FixedTrustedTimeProvider(date: now),
            bundleIdentifier: bundleIdentifier,
            distributionPolicy: AppDistributionPolicy(
                edition: .licenceAdministrator,
                requiresOnlineLicenceCheck: true
            ),
            trustedIssuerProvider: { issuer.publicKey.rawRepresentation }
        )
        let payload = AccessLicencePayload(
            licenceID: UUID(),
            subject: "Annual user",
            role: .annualUser,
            issuedAt: now,
            expiresAt: now.addingTimeInterval(365 * 24 * 60 * 60),
            installationID: controller.installationID,
            bundleIdentifier: bundleIdentifier
        )

        await controller.activate(code: try AccessLicenceCodec.sign(payload, using: issuer))

        guard case .locked(let message) = controller.status else {
            return XCTFail("The administrator edition must reject standard-user access")
        }
        XCTAssertTrue(message.contains("different app edition"))
    }

    func testOnlinePolicyFailsClosedForAdministratorWhenTrustedTimeIsUnavailable() async throws {
        let store = InMemoryAccessStore()
        let issuer = Curve25519.Signing.PrivateKey()
        let now = Date()
        let controller = AccessController(
            secureStore: store,
            timeProvider: UnavailableTrustedTimeProvider(),
            bundleIdentifier: bundleIdentifier,
            distributionPolicy: AppDistributionPolicy(
                edition: .licenceAdministrator,
                requiresOnlineLicenceCheck: true
            ),
            trustedIssuerProvider: { issuer.publicKey.rawRepresentation }
        )
        let payload = AccessLicencePayload(
            licenceID: UUID(),
            subject: "Administrator",
            role: .licenceAdministrator,
            issuedAt: now,
            expiresAt: nil,
            installationID: controller.installationID,
            bundleIdentifier: bundleIdentifier
        )

        await controller.activate(code: try AccessLicenceCodec.sign(payload, using: issuer))

        guard case .locked(let message) = controller.status else {
            return XCTFail("The packaged administrator edition must fail closed without online verification")
        }
        XCTAssertTrue(message.contains("internet connection"))
    }

    func testCentralLicenceActivationAndConfirmedRevocation() async throws {
        let store = InMemoryAccessStore()
        let issuer = Curve25519.Signing.PrivateKey()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let service = MockCentralLicenceService(now: now)
        let controller = AccessController(
            secureStore: store,
            timeProvider: FixedTrustedTimeProvider(date: now),
            bundleIdentifier: bundleIdentifier,
            distributionPolicy: AppDistributionPolicy(
                edition: .standardUser,
                requiresOnlineLicenceCheck: true,
                requiresCentralLicenceService: true
            ),
            centralService: service,
            trustedIssuerProvider: { issuer.publicKey.rawRepresentation }
        )
        let payload = AccessLicencePayload(
            licenceID: UUID(),
            subject: "Annual user",
            role: .annualUser,
            issuedAt: now,
            expiresAt: now.addingTimeInterval(365 * 24 * 60 * 60),
            installationID: controller.installationID,
            bundleIdentifier: bundleIdentifier
        )

        await controller.activate(code: try AccessLicenceCodec.sign(payload, using: issuer))
        XCTAssertEqual(controller.activeLicence, payload)
        let activationCount = await service.activationCount()
        XCTAssertEqual(activationCount, 1)

        await service.setCheckError(.revoked)
        await controller.refreshAccess()

        guard case .locked(let message) = controller.status else {
            return XCTFail("A confirmed central revocation must lock the app")
        }
        XCTAssertTrue(message.contains("revoked"))
    }

    func testTemporaryCentralOutageHonoursUnexpiredSignedLease() async throws {
        let store = InMemoryAccessStore()
        let issuer = Curve25519.Signing.PrivateKey()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let service = MockCentralLicenceService(now: now)
        let controller = AccessController(
            secureStore: store,
            timeProvider: FixedTrustedTimeProvider(date: now),
            bundleIdentifier: bundleIdentifier,
            distributionPolicy: AppDistributionPolicy(
                edition: .standardUser,
                requiresOnlineLicenceCheck: true,
                requiresCentralLicenceService: true
            ),
            centralService: service,
            trustedIssuerProvider: { issuer.publicKey.rawRepresentation }
        )
        let payload = AccessLicencePayload(
            licenceID: UUID(),
            subject: "Annual user",
            role: .annualUser,
            issuedAt: now,
            expiresAt: now.addingTimeInterval(365 * 24 * 60 * 60),
            installationID: controller.installationID,
            bundleIdentifier: bundleIdentifier
        )

        await controller.activate(code: try AccessLicenceCodec.sign(payload, using: issuer))
        await service.setCheckError(.unavailable("Temporary test outage"))
        await controller.refreshAccess()

        XCTAssertEqual(controller.activeLicence, payload)
    }

    func testAdministratorEditionIssuesStandardBundleLicenceThroughCentralService() async throws {
        let store = InMemoryAccessStore()
        let issuer = Curve25519.Signing.PrivateKey()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let service = MockCentralLicenceService(now: now)
        let administratorBundle = "dev.example.MDMProfileBuilder.Admin"
        let standardBundle = "dev.example.MDMProfileBuilder"
        let controller = AccessController(
            secureStore: store,
            timeProvider: FixedTrustedTimeProvider(date: now),
            bundleIdentifier: administratorBundle,
            distributionPolicy: AppDistributionPolicy(
                edition: .licenceAdministrator,
                requiresOnlineLicenceCheck: true,
                requiresCentralLicenceService: true,
                standardBundleIdentifier: standardBundle
            ),
            centralService: service,
            trustedIssuerProvider: { issuer.publicKey.rawRepresentation }
        )
        let administrator = AccessLicencePayload(
            licenceID: UUID(),
            subject: "Licence administrator",
            role: .licenceAdministrator,
            issuedAt: now,
            expiresAt: nil,
            installationID: controller.installationID,
            bundleIdentifier: administratorBundle
        )
        await controller.activate(code: try AccessLicenceCodec.sign(administrator, using: issuer))
        try controller.importIssuerPrivateKey(issuer.rawRepresentation.base64EncodedString())
        let request = try AccessLicenceCodec.makeRequest(
            installationID: UUID(),
            bundleIdentifier: standardBundle
        )

        let code = try await controller.issueAnnualLicence(
            subject: "School technician",
            requestCode: request
        )
        let issued = try AccessLicenceCodec.verify(code, using: issuer.publicKey)

        XCTAssertEqual(issued.bundleIdentifier, standardBundle)
        let registeredLicenceIDs = await service.registeredLicenceIDs()
        XCTAssertEqual(registeredLicenceIDs, [issued.licenceID])

        await service.setDirectoryRecords([
            CentralLicenceDirectoryRecord(
                licenceID: issued.licenceID,
                subject: issued.subject,
                displayName: "Edited centrally",
                notes: "Shared record",
                role: issued.role,
                issuedAt: issued.issuedAt,
                expiresAt: issued.expiresAt,
                installationID: issued.installationID,
                bundleIdentifier: issued.bundleIdentifier,
                state: .active,
                revokedAt: nil,
                replacedByLicenceID: nil,
                updatedAt: now.addingTimeInterval(60)
            )
        ])
        await controller.refreshIssuedLicenceDirectory()

        XCTAssertEqual(controller.issuedLicences.first?.displayName, "Edited centrally")
        XCTAssertEqual(controller.issuedLicences.first?.accessCode, code)
    }

    private func administratorController(
        store: InMemoryAccessStore,
        issuer: Curve25519.Signing.PrivateKey,
        trustedDate: Date
    ) async throws -> AccessController {
        let controller = AccessController(
            secureStore: store,
            timeProvider: FixedTrustedTimeProvider(date: trustedDate),
            bundleIdentifier: bundleIdentifier,
            trustedIssuerProvider: { issuer.publicKey.rawRepresentation }
        )
        let adminPayload = AccessLicencePayload(
            licenceID: UUID(),
            subject: "Licensing admin",
            role: .licenceAdministrator,
            issuedAt: trustedDate,
            expiresAt: nil,
            installationID: controller.installationID,
            bundleIdentifier: bundleIdentifier
        )
        await controller.activate(code: try AccessLicenceCodec.sign(adminPayload, using: issuer))
        try controller.importIssuerPrivateKey(issuer.rawRepresentation.base64EncodedString())
        return controller
    }
}

private actor MockCentralLicenceService: CentralLicenceServicing {
    private let now: Date
    private var activations = 0
    private var checkError: CentralLicenceServiceError?
    private var registeredIDs: [UUID] = []
    private var directoryRecords: [CentralLicenceDirectoryRecord] = []

    init(now: Date) {
        self.now = now
    }

    func activate(
        accessCode: String,
        licence: AccessLicencePayload,
        devicePrivateKey: Curve25519.Signing.PrivateKey
    ) async throws -> CentralLicenceLeasePayload {
        activations += 1
        return lease(for: licence)
    }

    func check(
        licence: AccessLicencePayload,
        devicePrivateKey: Curve25519.Signing.PrivateKey
    ) async throws -> CentralLicenceLeasePayload {
        if let checkError { throw checkError }
        return lease(for: licence)
    }

    func listIssuedLicences(
        administrator: AccessLicencePayload,
        devicePrivateKey: Curve25519.Signing.PrivateKey
    ) async throws -> [CentralLicenceDirectoryRecord] {
        directoryRecords
    }

    func registerIssuedLicence(
        accessCode: String,
        administrator: AccessLicencePayload,
        devicePrivateKey: Curve25519.Signing.PrivateKey
    ) async throws {
        let parts = accessCode.split(separator: ".")
        guard parts.count == 3,
              let data = Data(base64URL: String(parts[1])) else {
            throw CentralLicenceServiceError.denied("Invalid test code")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        registeredIDs.append(try decoder.decode(AccessLicencePayload.self, from: data).licenceID)
    }

    func reissueLicence(
        oldLicenceID: UUID,
        accessCode: String,
        administrator: AccessLicencePayload,
        devicePrivateKey: Curve25519.Signing.PrivateKey
    ) async throws {}

    func revokeLicence(
        licenceID: UUID,
        administrator: AccessLicencePayload,
        devicePrivateKey: Curve25519.Signing.PrivateKey
    ) async throws -> Date {
        now
    }

    func updateLicenceMetadata(
        licenceID: UUID,
        displayName: String,
        notes: String,
        administrator: AccessLicencePayload,
        devicePrivateKey: Curve25519.Signing.PrivateKey
    ) async throws {}

    func setCheckError(_ error: CentralLicenceServiceError?) {
        checkError = error
    }

    func setDirectoryRecords(_ records: [CentralLicenceDirectoryRecord]) {
        directoryRecords = records
    }

    func activationCount() -> Int { activations }
    func registeredLicenceIDs() -> [UUID] { registeredIDs }

    private func lease(for licence: AccessLicencePayload) -> CentralLicenceLeasePayload {
        CentralLicenceLeasePayload(
            version: CentralLicenceLeasePayload.currentVersion,
            licenceID: licence.licenceID,
            installationID: licence.installationID,
            bundleIdentifier: licence.bundleIdentifier,
            role: licence.role,
            issuedAt: now,
            validUntil: now.addingTimeInterval(15 * 60)
        )
    }
}

private final class InMemoryAccessStore: AccessSecureStoring {
    private var values: [String: Data] = [:]

    func save(_ data: Data, account: String) throws { values[account] = data }
    func load(account: String) throws -> Data? { values[account] }
    func delete(account: String) throws { values.removeValue(forKey: account) }
}

private struct UnavailableTrustedTimeProvider: TrustedTimeProviding {
    func trustedDate() async throws -> Date {
        throw TrustedTimeError.insufficientSources
    }
}

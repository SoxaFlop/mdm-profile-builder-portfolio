import AppKit
import Foundation

@MainActor
final class ConnectionSettingsViewModel: ObservableObject {
    @Published var tenantURL = ""
    @Published var networkID = ""
    @Published var apiKey = ""
    @Published var statusMessage = "No Jamf School connection configured."
    @Published var isTesting = false
    @Published var platformRegion: JamfPlatformRegion = .eu
    @Published var platformTenantID = ""
    @Published var platformClientID = ""
    @Published var platformClientSecret = ""
    @Published var platformStatusMessage = "Platform API beta is not configured."
    @Published var isTestingPlatform = false
    @Published var externalAIProvider: AssistantProvider = .localQwen
    @Published var externalAIModel = AssistantProvider.localQwen.defaultModel
    @Published var externalAIAPIKey = ""
    @Published var externalAIStatusMessage = "On-device Qwen is active. No profile or attachment data leaves this Mac."
    @Published var isTestingExternalAI = false
    @Published var microsoftTenantID = MicrosoftCopilotAuthService.defaultTenant
    @Published var microsoftClientID = ""
    @Published var microsoftSignedInAccount = ""
    @Published var microsoftDeviceCode = ""
    @Published var isSigningInMicrosoft = false

    private let credentialStore: JamfCredentialStoring
    private let platformCredentialStore: JamfPlatformCredentialStoring
    private let externalAIConfigurationStore: ExternalAIConfigurationStoring
    private let externalAICredentialStore: ExternalAICredentialStoring
    private let externalAIService: ExternalAIService
    private let microsoftAuthService: MicrosoftCopilotAuthService
    private lazy var connector: JamfSchoolConnecting = JamfSchoolReadOnlyConnector(
        credentialStore: credentialStore
    )
    private lazy var platformConnector: JamfPlatformConnecting = JamfPlatformConnector(
        credentialStore: platformCredentialStore
    )

    init(
        credentialStore: JamfCredentialStoring = KeychainJamfCredentialStore(),
        platformCredentialStore: JamfPlatformCredentialStoring = KeychainJamfPlatformCredentialStore(),
        externalAIConfigurationStore: ExternalAIConfigurationStoring = UserDefaultsExternalAIConfigurationStore(),
        externalAICredentialStore: ExternalAICredentialStoring = KeychainExternalAICredentialStore(),
        externalAIService: ExternalAIService = ExternalAIService(),
        microsoftAuthService: MicrosoftCopilotAuthService? = nil
    ) {
        self.credentialStore = credentialStore
        self.platformCredentialStore = platformCredentialStore
        self.externalAIConfigurationStore = externalAIConfigurationStore
        self.externalAICredentialStore = externalAICredentialStore
        self.externalAIService = externalAIService
        self.microsoftAuthService = microsoftAuthService ?? MicrosoftCopilotAuthService(credentialStore: externalAICredentialStore)
        loadLegacyCredentials()
        loadPlatformCredentials()
        loadExternalAIConfiguration()
    }

    func save() {
        do {
            let credentials = try validatedCredentials()
            try credentialStore.save(credentials)
            statusMessage = "Saved securely in this Mac's Keychain. Read-only API access is available."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func testConnection() async {
        save()
        guard (try? validatedCredentials()) != nil else { return }

        isTesting = true
        defer { isTesting = false }
        do {
            try await connector.testConnection()
            let groups = try await connector.listDeviceGroups()
            statusMessage = "Connected successfully. Found \(groups.count) device group\(groups.count == 1 ? "" : "s"). Write actions remain disabled."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func removeCredentials() {
        do {
            try credentialStore.delete()
            tenantURL = ""
            networkID = ""
            apiKey = ""
            statusMessage = "Credentials removed from Keychain."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func savePlatformCredentials() {
        do {
            let credentials = try validatedPlatformCredentials()
            try platformCredentialStore.save(credentials)
            platformStatusMessage = "Platform API credentials saved securely in Keychain."
        } catch {
            platformStatusMessage = error.localizedDescription
        }
    }

    func testPlatformConnection() async {
        savePlatformCredentials()
        guard (try? validatedPlatformCredentials()) != nil else { return }

        isTestingPlatform = true
        defer { isTestingPlatform = false }
        do {
            try await platformConnector.testConnection()
            platformStatusMessage = "Connected to the Platform API beta. Blueprint lifecycle operations are available according to the integration's permissions."
        } catch {
            platformStatusMessage = error.localizedDescription
        }
    }

    func removePlatformCredentials() {
        do {
            try platformCredentialStore.delete()
            platformTenantID = ""
            platformClientID = ""
            platformClientSecret = ""
            platformStatusMessage = "Platform API credentials removed from Keychain."
        } catch {
            platformStatusMessage = error.localizedDescription
        }
    }

    func selectedExternalAIProviderChanged() {
        externalAIModel = externalAIProvider.defaultModel
        externalAIAPIKey = ""
        if externalAIProvider == .localQwen {
            externalAIStatusMessage = "On-device Qwen is active. No profile or attachment data leaves this Mac."
        } else if externalAIProvider == .microsoftCopilot {
            loadMicrosoftAccount()
            externalAIStatusMessage = microsoftSignedInAccount.isEmpty
                ? "Sign in with a Microsoft 365 work or school account that has a Copilot licence. Personal Microsoft accounts are not supported by Microsoft’s Copilot Chat API."
                : "Microsoft 365 Copilot is signed in as \(microsoftSignedInAccount)."
        } else {
            externalAIStatusMessage = "Enter a developer API key, then save it in this Mac’s Keychain. Profile context and any attached text will be sent to \(externalAIProvider.title) only when the technician submits a message."
        }
    }

    func saveExternalAIConfiguration() {
        let configuration = ExternalAIConfiguration(
            provider: externalAIProvider,
            model: externalAIModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? externalAIProvider.defaultModel : externalAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        do {
            if externalAIProvider.requiresAPIKey {
                guard !externalAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ExternalAIError.credentialsMissing(externalAIProvider)
                }
                try externalAICredentialStore.save(ExternalAICredentials(apiKey: externalAIAPIKey), for: externalAIProvider)
            } else if externalAIProvider == .microsoftCopilot {
                guard (try microsoftAuthService.loadSignedInAccount()) != nil else {
                    throw ExternalAIError.microsoftConfigurationMissing
                }
            }
            externalAIConfigurationStore.save(configuration)
            if externalAIProvider == .localQwen {
                externalAIStatusMessage = "On-device Qwen is active."
            } else if externalAIProvider == .microsoftCopilot {
                externalAIStatusMessage = "Microsoft 365 Copilot is selected for the assistant."
            } else {
                externalAIStatusMessage = "\(externalAIProvider.title) is selected. Its credential is stored in this Mac’s Keychain."
            }
        } catch {
            externalAIStatusMessage = error.localizedDescription
        }
    }

    func testExternalAIConnection() async {
        if externalAIProvider == .microsoftCopilot {
            isTestingExternalAI = true
            defer { isTestingExternalAI = false }
            do {
                let configuration = ExternalAIConfiguration(provider: .microsoftCopilot, model: externalAIModel)
                try await externalAIService.test(configuration: configuration, apiKey: "")
                externalAIStatusMessage = "Microsoft 365 Copilot answered through the signed-in work or school account."
            } catch {
                externalAIStatusMessage = error.localizedDescription
            }
            return
        }
        guard externalAIProvider.requiresAPIKey else {
            externalAIStatusMessage = "The local model does not need a network connection."
            return
        }
        let key = externalAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            externalAIStatusMessage = ExternalAIError.credentialsMissing(externalAIProvider).localizedDescription
            return
        }
        isTestingExternalAI = true
        defer { isTestingExternalAI = false }
        do {
            let configuration = ExternalAIConfiguration(provider: externalAIProvider, model: externalAIModel)
            try await externalAIService.test(configuration: configuration, apiKey: key)
            externalAIStatusMessage = "Connection test succeeded. Save to Keychain before using this provider in the assistant."
        } catch {
            externalAIStatusMessage = error.localizedDescription
        }
    }

    func removeExternalAIConfiguration() {
        do {
            if externalAIProvider.requiresAPIKey {
                try externalAICredentialStore.delete(for: externalAIProvider)
            } else if externalAIProvider == .microsoftCopilot {
                try microsoftAuthService.signOut()
                microsoftSignedInAccount = ""
                microsoftDeviceCode = ""
            }
            externalAIConfigurationStore.save(.local)
            externalAIProvider = .localQwen
            externalAIModel = AssistantProvider.localQwen.defaultModel
            externalAIAPIKey = ""
            externalAIStatusMessage = "External AI configuration removed. On-device Qwen is active."
        } catch {
            externalAIStatusMessage = error.localizedDescription
        }
    }

    func signInWithMicrosoft() async {
        externalAIProvider = .microsoftCopilot
        let tenant = microsoftTenantID.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientID = microsoftClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        isSigningInMicrosoft = true
        microsoftDeviceCode = ""
        defer { isSigningInMicrosoft = false }

        do {
            let signIn = try await microsoftAuthService.beginDeviceCodeSignIn(tenant: tenant, clientID: clientID)
            microsoftDeviceCode = signIn.userCode
            externalAIStatusMessage = "Microsoft sign-in opened in your browser. Enter code \(signIn.userCode) and approve the requested Copilot permissions."
            NSWorkspace.shared.open(signIn.verificationURI)
            let account = try await microsoftAuthService.completeDeviceCodeSignIn(signIn)
            microsoftTenantID = account.tenant
            microsoftClientID = account.clientID
            microsoftSignedInAccount = account.displayName
            microsoftDeviceCode = ""
            externalAIConfigurationStore.save(ExternalAIConfiguration(provider: .microsoftCopilot, model: AssistantProvider.microsoftCopilot.defaultModel))
            externalAIModel = AssistantProvider.microsoftCopilot.defaultModel
            externalAIStatusMessage = "Signed in as \(account.displayName). Microsoft 365 Copilot is now active for the assistant."
        } catch {
            externalAIStatusMessage = error.localizedDescription
        }
    }

    private func loadLegacyCredentials() {
        do {
            guard let credentials = try credentialStore.load() else { return }
            tenantURL = credentials.tenantURL.absoluteString
            networkID = credentials.networkID
            apiKey = credentials.apiKey
            statusMessage = "Jamf School credentials loaded from Keychain."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func loadPlatformCredentials() {
        do {
            guard let credentials = try platformCredentialStore.load() else { return }
            platformRegion = credentials.region
            platformTenantID = credentials.tenantID.uuidString.lowercased()
            platformClientID = credentials.clientID
            platformClientSecret = credentials.clientSecret
            platformStatusMessage = "Platform API credentials loaded from Keychain."
        } catch {
            platformStatusMessage = error.localizedDescription
        }
    }

    private func loadExternalAIConfiguration() {
        let configuration = externalAIConfigurationStore.load()
        externalAIProvider = configuration.provider
        externalAIModel = configuration.model
        guard externalAIProvider.requiresAPIKey else {
            selectedExternalAIProviderChanged()
            return
        }
        do {
            externalAIAPIKey = try externalAICredentialStore.load(for: externalAIProvider)?.apiKey ?? ""
            externalAIStatusMessage = externalAIAPIKey.isEmpty
                ? "\(externalAIProvider.title) is selected but its API key is missing."
                : "\(externalAIProvider.title) credentials are loaded from Keychain."
        } catch {
            externalAIStatusMessage = error.localizedDescription
        }
    }

    private func loadMicrosoftAccount() {
        do {
            if let credentials = try externalAICredentialStore.load(for: .microsoftCopilot) {
                microsoftTenantID = credentials.microsoftTenant ?? MicrosoftCopilotAuthService.defaultTenant
                microsoftClientID = credentials.microsoftClientID ?? ""
                microsoftSignedInAccount = credentials.microsoftAccountName ?? ""
            }
        } catch {
            externalAIStatusMessage = error.localizedDescription
        }
    }

    private func validatedCredentials() throws -> JamfCredentials {
        let trimmedURL = tenantURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNetworkID = networkID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, !trimmedNetworkID.isEmpty, !apiKey.isEmpty else {
            throw JamfConnectorError.credentialsMissing
        }
        guard let url = URL(string: trimmedURL),
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            throw JamfConnectorError.invalidTenantURL
        }
        return JamfCredentials(tenantURL: url, networkID: trimmedNetworkID, apiKey: apiKey)
    }

    private func validatedPlatformCredentials() throws -> JamfPlatformCredentials {
        let tenant = platformTenantID.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientID = platformClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let tenantID = UUID(uuidString: tenant),
              !clientID.isEmpty,
              !platformClientSecret.isEmpty else {
            throw JamfPlatformError.invalidCredentials
        }
        return JamfPlatformCredentials(
            region: platformRegion,
            tenantID: tenantID,
            clientID: clientID,
            clientSecret: platformClientSecret
        )
    }
}

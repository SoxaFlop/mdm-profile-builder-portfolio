import Foundation
import Security

enum AssistantProvider: String, Codable, CaseIterable, Identifiable {
    case localQwen
    case openAI
    case gemini
    case claude
    case microsoftCopilot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localQwen: "On-device Qwen"
        case .openAI: "ChatGPT / OpenAI API"
        case .gemini: "Google Gemini API"
        case .claude: "Anthropic Claude API"
        case .microsoftCopilot: "Microsoft 365 Copilot"
        }
    }

    var defaultModel: String {
        switch self {
        case .localQwen: "Qwen3.5 4B · MLX · 4-bit"
        case .openAI: "gpt-5"
        case .gemini: "gemini-3.5-flash"
        case .claude: "claude-sonnet-4-20250514"
        case .microsoftCopilot: "Microsoft 365 Copilot Chat API"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .localQwen, .microsoftCopilot: false
        case .openAI, .gemini, .claude: true
        }
    }

    var isExternal: Bool { self != .localQwen }
}

struct ExternalAIConfiguration: Codable, Equatable {
    var provider: AssistantProvider
    var model: String

    static let local = ExternalAIConfiguration(provider: .localQwen, model: AssistantProvider.localQwen.defaultModel)
}

struct ExternalAICredentials: Codable, Equatable {
    let apiKey: String
    var microsoftTenant: String?
    var microsoftClientID: String?
    var microsoftAccessToken: String?
    var microsoftRefreshToken: String?
    var microsoftAccessTokenExpiresAt: Date?
    var microsoftAccountName: String?

    init(
        apiKey: String = "",
        microsoftTenant: String? = nil,
        microsoftClientID: String? = nil,
        microsoftAccessToken: String? = nil,
        microsoftRefreshToken: String? = nil,
        microsoftAccessTokenExpiresAt: Date? = nil,
        microsoftAccountName: String? = nil
    ) {
        self.apiKey = apiKey
        self.microsoftTenant = microsoftTenant
        self.microsoftClientID = microsoftClientID
        self.microsoftAccessToken = microsoftAccessToken
        self.microsoftRefreshToken = microsoftRefreshToken
        self.microsoftAccessTokenExpiresAt = microsoftAccessTokenExpiresAt
        self.microsoftAccountName = microsoftAccountName
    }
}

protocol ExternalAIConfigurationStoring {
    func load() -> ExternalAIConfiguration
    func save(_ configuration: ExternalAIConfiguration)
}

struct UserDefaultsExternalAIConfigurationStore: ExternalAIConfigurationStoring {
    private let key = "MDMCopilot.ExternalAI.Configuration"

    func load() -> ExternalAIConfiguration {
        guard let data = UserDefaults.standard.data(forKey: key),
              let configuration = try? JSONDecoder().decode(ExternalAIConfiguration.self, from: data) else {
            return .local
        }
        return configuration
    }

    func save(_ configuration: ExternalAIConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

protocol ExternalAICredentialStoring {
    func save(_ credentials: ExternalAICredentials, for provider: AssistantProvider) throws
    func load(for provider: AssistantProvider) throws -> ExternalAICredentials?
    func delete(for provider: AssistantProvider) throws
}

struct KeychainExternalAICredentialStore: ExternalAICredentialStoring {
    private let service: String

    init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "dev.example.MDMProfileBuilder.local") {
        service = "\(bundleIdentifier).ExternalAI"
    }

    func save(_ credentials: ExternalAICredentials, for provider: AssistantProvider) throws {
        guard let data = try? JSONEncoder().encode(credentials) else { throw ExternalAIError.credentialEncodingFailed }
        let query = baseQuery(for: provider)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecItemNotFound {
            var add = query
            attributes.forEach { add[$0.key] = $0.value }
            let status = SecItemAdd(add as CFDictionary, nil)
            guard status == errSecSuccess else { throw ExternalAIError.keychain(status) }
        } else if update != errSecSuccess {
            throw ExternalAIError.keychain(update)
        }
    }

    func load(for provider: AssistantProvider) throws -> ExternalAICredentials? {
        var query = baseQuery(for: provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let credentials = try? JSONDecoder().decode(ExternalAICredentials.self, from: data) else {
            throw ExternalAIError.keychain(status)
        }
        return credentials
    }

    func delete(for provider: AssistantProvider) throws {
        let status = SecItemDelete(baseQuery(for: provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw ExternalAIError.keychain(status) }
    }

    private func baseQuery(for provider: AssistantProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
    }
}

enum ExternalAIError: LocalizedError {
    case credentialsMissing(AssistantProvider)
    case unsupportedProvider
    case credentialEncodingFailed
    case keychain(OSStatus)
    case invalidResponse
    case providerFailure(String)
    case microsoftConfigurationMissing
    case microsoftSignInTimedOut

    var errorDescription: String? {
        switch self {
        case .credentialsMissing(let provider): "Add a developer API key for \(provider.title) in Jamf settings before using it."
        case .unsupportedProvider: "The selected AI provider is not available."
        case .credentialEncodingFailed: "The external AI credential could not be stored."
        case .keychain(let status): "Keychain returned status \(status)."
        case .invalidResponse: "The selected AI provider returned an unreadable response."
        case .providerFailure(let message): message
        case .microsoftConfigurationMissing: "Enter a Microsoft Entra application client ID, then sign in with a Microsoft 365 work or school account that has a Copilot licence."
        case .microsoftSignInTimedOut: "Microsoft sign-in timed out before the account was approved."
        }
    }
}

struct MicrosoftDeviceCodeSignIn: Decodable, Equatable {
    let userCode: String
    let verificationURI: URL
    let message: String

    private let deviceCode: String
    private let interval: Int
    private let expiresIn: Int
    let tenant: String
    let clientID: String

    var pollIntervalSeconds: Int { max(interval, 5) }
    var expiresAt: Date { Date().addingTimeInterval(TimeInterval(expiresIn)) }

    private enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case interval
        case expiresIn = "expires_in"
        case message
    }

    init(
        deviceCode: String,
        userCode: String,
        verificationURI: URL,
        interval: Int,
        expiresIn: Int,
        message: String,
        tenant: String,
        clientID: String
    ) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationURI = verificationURI
        self.interval = interval
        self.expiresIn = expiresIn
        self.message = message
        self.tenant = tenant
        self.clientID = clientID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceCode = try container.decode(String.self, forKey: .deviceCode)
        userCode = try container.decode(String.self, forKey: .userCode)
        verificationURI = try container.decode(URL.self, forKey: .verificationURI)
        interval = try container.decodeIfPresent(Int.self, forKey: .interval) ?? 5
        expiresIn = try container.decodeIfPresent(Int.self, forKey: .expiresIn) ?? 900
        message = try container.decode(String.self, forKey: .message)
        tenant = MicrosoftCopilotAuthService.defaultTenant
        clientID = ""
    }

    func withConfiguration(tenant: String, clientID: String) -> MicrosoftDeviceCodeSignIn {
        MicrosoftDeviceCodeSignIn(
            deviceCode: deviceCode,
            userCode: userCode,
            verificationURI: verificationURI,
            interval: interval,
            expiresIn: expiresIn,
            message: message,
            tenant: tenant,
            clientID: clientID
        )
    }

    var tokenRequestFields: [String: String] {
        [
            "client_id": clientID,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            "device_code": deviceCode
        ]
    }
}

struct MicrosoftSignedInAccount: Equatable {
    let displayName: String
    let tenant: String
    let clientID: String
}

struct MicrosoftCopilotAuthService {
    static let defaultTenant = "organizations"
    static let copilotScopes = [
        "openid",
        "profile",
        "offline_access",
        "User.Read",
        "Sites.Read.All",
        "Mail.Read",
        "People.Read.All",
        "OnlineMeetingTranscript.Read.All",
        "Chat.Read",
        "ChannelMessage.Read.All",
        "ExternalItem.Read.All"
    ]

    private let credentialStore: ExternalAICredentialStoring
    private let session: URLSession

    init(
        credentialStore: ExternalAICredentialStoring = KeychainExternalAICredentialStore(),
        session: URLSession = .shared
    ) {
        self.credentialStore = credentialStore
        self.session = session
    }

    func beginDeviceCodeSignIn(tenant: String, clientID: String) async throws -> MicrosoftDeviceCodeSignIn {
        let normalisedTenant = normaliseTenant(tenant)
        let trimmedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: trimmedClientID) != nil else { throw ExternalAIError.microsoftConfigurationMissing }

        var request = URLRequest(url: identityURL(tenant: normalisedTenant, path: "devicecode"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncodedBody([
            "client_id": trimmedClientID,
            "scope": Self.copilotScopes.joined(separator: " ")
        ])
        let data = try await perform(request)
        return try JSONDecoder().decode(MicrosoftDeviceCodeSignIn.self, from: data)
            .withConfiguration(tenant: normalisedTenant, clientID: trimmedClientID)
    }

    func completeDeviceCodeSignIn(_ signIn: MicrosoftDeviceCodeSignIn) async throws -> MicrosoftSignedInAccount {
        let deadline = signIn.expiresAt
        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(signIn.pollIntervalSeconds) * 1_000_000_000)
            do {
                let token = try await tokenResponse(tenant: signIn.tenant, fields: signIn.tokenRequestFields)
                let account = try await storeToken(token, tenant: signIn.tenant, clientID: signIn.clientID)
                return account
            } catch let error as MicrosoftOAuthError where error.error == "authorization_pending" {
                continue
            } catch let error as MicrosoftOAuthError where error.error == "slow_down" {
                try await Task.sleep(nanoseconds: UInt64(signIn.pollIntervalSeconds) * 1_000_000_000)
                continue
            }
        }
        throw ExternalAIError.microsoftSignInTimedOut
    }

    func loadSignedInAccount() throws -> MicrosoftSignedInAccount? {
        guard let credentials = try credentialStore.load(for: .microsoftCopilot),
              let tenant = credentials.microsoftTenant,
              let clientID = credentials.microsoftClientID,
              credentials.microsoftRefreshToken?.isEmpty == false else {
            return nil
        }
        return MicrosoftSignedInAccount(
            displayName: credentials.microsoftAccountName ?? "Microsoft 365 account",
            tenant: tenant,
            clientID: clientID
        )
    }

    func accessToken() async throws -> String {
        guard var credentials = try credentialStore.load(for: .microsoftCopilot),
              let tenant = credentials.microsoftTenant,
              let clientID = credentials.microsoftClientID else {
            throw ExternalAIError.microsoftConfigurationMissing
        }
        if let accessToken = credentials.microsoftAccessToken,
           let expiresAt = credentials.microsoftAccessTokenExpiresAt,
           expiresAt.timeIntervalSinceNow > 120 {
            return accessToken
        }
        guard let refreshToken = credentials.microsoftRefreshToken, !refreshToken.isEmpty else {
            throw ExternalAIError.microsoftConfigurationMissing
        }
        let token = try await tokenResponse(tenant: tenant, fields: [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "scope": Self.copilotScopes.joined(separator: " ")
        ])
        credentials.microsoftAccessToken = token.accessToken
        credentials.microsoftRefreshToken = token.refreshToken ?? refreshToken
        credentials.microsoftAccessTokenExpiresAt = Date().addingTimeInterval(TimeInterval(max(token.expiresIn - 60, 60)))
        try credentialStore.save(credentials, for: .microsoftCopilot)
        return token.accessToken
    }

    func signOut() throws {
        try credentialStore.delete(for: .microsoftCopilot)
    }

    private func storeToken(_ token: MicrosoftTokenResponse, tenant: String, clientID: String) async throws -> MicrosoftSignedInAccount {
        let accountName = try await microsoftAccountName(accessToken: token.accessToken)
        let credentials = ExternalAICredentials(
            microsoftTenant: tenant,
            microsoftClientID: clientID,
            microsoftAccessToken: token.accessToken,
            microsoftRefreshToken: token.refreshToken,
            microsoftAccessTokenExpiresAt: Date().addingTimeInterval(TimeInterval(max(token.expiresIn - 60, 60))),
            microsoftAccountName: accountName
        )
        try credentialStore.save(credentials, for: .microsoftCopilot)
        return MicrosoftSignedInAccount(displayName: accountName, tenant: tenant, clientID: clientID)
    }

    private func microsoftAccountName(accessToken: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://graph.microsoft.com/v1.0/me?$select=displayName,userPrincipalName,mail")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let data = try await perform(request)
        let me = try JSONDecoder().decode(MicrosoftGraphMe.self, from: data)
        return me.userPrincipalName ?? me.mail ?? me.displayName ?? "Microsoft 365 account"
    }

    private func tokenResponse(tenant: String, fields: [String: String]) async throws -> MicrosoftTokenResponse {
        var request = URLRequest(url: identityURL(tenant: tenant, path: "token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncodedBody(fields)
        let data = try await perform(request, decodeOAuthErrors: true)
        return try JSONDecoder().decode(MicrosoftTokenResponse.self, from: data)
    }

    private func perform(_ request: URLRequest, decodeOAuthErrors: Bool = false) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ExternalAIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if decodeOAuthErrors,
               let oauth = try? JSONDecoder().decode(MicrosoftOAuthError.self, from: data) {
                throw oauth
            }
            let detail = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw ExternalAIError.providerFailure("Microsoft returned HTTP \(http.statusCode): \(String(detail.prefix(400)))")
        }
        return data
    }

    private func identityURL(tenant: String, path: String) -> URL {
        URL(string: "https://login.microsoftonline.com/\(tenant)/oauth2/v2.0/\(path)")!
    }

    private func normaliseTenant(_ tenant: String) -> String {
        let trimmed = tenant.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultTenant : trimmed
    }
}

struct ExternalAIService {
    let credentialStore: ExternalAICredentialStoring
    let session: URLSession

    init(
        credentialStore: ExternalAICredentialStoring = KeychainExternalAICredentialStore(),
        session: URLSession = .shared
    ) {
        self.credentialStore = credentialStore
        self.session = session
    }

    func respond(to request: LocalModelRequest, configuration: ExternalAIConfiguration) async -> LocalModelResponse {
        do {
            let text = try await responseText(to: request, configuration: configuration)
            return ExternalAIResponseParser.parse(text, request: request)
        } catch {
            return LocalModelResponse(
                message: "The \(configuration.provider.title) connection could not answer this request: \(error.localizedDescription)\n\nThe local profile and Jamf School have not been changed.",
                edits: []
            )
        }
    }

    func test(configuration: ExternalAIConfiguration, apiKey: String) async throws {
        let request = LocalModelRequest(prompt: "Reply with exactly: connection ready", intent: .blank, validationIssues: [])
        _ = try await responseText(to: request, configuration: configuration, suppliedAPIKey: apiKey)
    }

    private func responseText(
        to request: LocalModelRequest,
        configuration: ExternalAIConfiguration,
        suppliedAPIKey: String? = nil
    ) async throws -> String {
        guard configuration.provider != .localQwen else { throw ExternalAIError.unsupportedProvider }
        if configuration.provider == .microsoftCopilot {
            return try await microsoftCopilotResponse(context: ExternalAIPrompt.context(for: request))
        }
        let apiKey: String
        if let suppliedAPIKey {
            apiKey = suppliedAPIKey
        } else if let saved = try credentialStore.load(for: configuration.provider) {
            apiKey = saved.apiKey
        } else {
            throw ExternalAIError.credentialsMissing(configuration.provider)
        }
        let context = ExternalAIPrompt.context(for: request)
        switch configuration.provider {
        case .openAI:
            return try await openAIResponse(model: configuration.model, apiKey: apiKey, context: context)
        case .gemini:
            return try await geminiResponse(model: configuration.model, apiKey: apiKey, context: context)
        case .claude:
            return try await claudeResponse(model: configuration.model, apiKey: apiKey, context: context)
        case .localQwen, .microsoftCopilot:
            throw ExternalAIError.unsupportedProvider
        }
    }

    private func openAIResponse(model: String, apiKey: String, context: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "instructions": ExternalAIPrompt.instructions,
            "input": context
        ])
        let data = try await perform(request)
        let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        let content = response.output?.flatMap { $0.content ?? [] } ?? []
        guard let text = content.compactMap(\.text).joined(separator: "\n").nonEmpty else {
            throw ExternalAIError.invalidResponse
        }
        return text
    }

    private func geminiResponse(model: String, apiKey: String, context: String) async throws -> String {
        let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):generateContent?key=\(apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiKey)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "systemInstruction": ["parts": [["text": ExternalAIPrompt.instructions]]],
            "contents": [["role": "user", "parts": [["text": context]]]],
            "generationConfig": ["temperature": 0, "responseMimeType": "application/json"]
        ])
        let data = try await perform(request)
        let response = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let text = response.candidates?.first?.content?.parts?.compactMap(\.text).joined(separator: "\n").nonEmpty else {
            throw ExternalAIError.invalidResponse
        }
        return text
    }

    private func claudeResponse(model: String, apiKey: String, context: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "max_tokens": 1_000,
            "temperature": 0,
            "system": ExternalAIPrompt.instructions,
            "messages": [["role": "user", "content": context]]
        ])
        let data = try await perform(request)
        let response = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        guard let text = response.content.compactMap(\.text).joined(separator: "\n").nonEmpty else {
            throw ExternalAIError.invalidResponse
        }
        return text
    }

    private func microsoftCopilotResponse(context: String) async throws -> String {
        let token = try await MicrosoftCopilotAuthService(
            credentialStore: credentialStore,
            session: session
        ).accessToken()
        let conversation = try await createMicrosoftCopilotConversation(accessToken: token)
        var request = URLRequest(url: URL(string: "https://graph.microsoft.com/beta/copilot/conversations/\(conversation.id)/chat")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "message": [
                "text": "\(ExternalAIPrompt.instructions)\n\n\(context)"
            ],
            "locationHint": [
                "timeZone": TimeZone.current.identifier
            ]
        ])
        let data = try await perform(request)
        let response = try JSONDecoder().decode(MicrosoftCopilotConversation.self, from: data)
        let requestText = context.components(separatedBy: "TECHNICIAN REQUEST").last?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text = response.messages
            .map(\.text)
            .last(where: { message in
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmed.isEmpty && trimmed != requestText
            })?.nonEmpty else {
            throw ExternalAIError.invalidResponse
        }
        return text
    }

    private func createMicrosoftCopilotConversation(accessToken: String) async throws -> MicrosoftCopilotConversation {
        var request = URLRequest(url: URL(string: "https://graph.microsoft.com/beta/copilot/conversations")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        let data = try await perform(request)
        return try JSONDecoder().decode(MicrosoftCopilotConversation.self, from: data)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ExternalAIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw ExternalAIError.providerFailure("Provider returned HTTP \(http.statusCode): \(String(detail.prefix(400)))")
        }
        return data
    }
}

private enum ExternalAIPrompt {
    static let instructions = """
    Put only the final technician-facing answer in reply. By default, keep it under 120 words and five
    bullets. Only go longer when the technician explicitly requests a detailed guide or step-by-step
    instructions. Do not narrate your analysis, repeat the prompt or expose private reasoning.
    You are an expert Jamf School and Apple device-management assistant inside a macOS profile builder. In this app, "users", "students", "kids", "learners" and "pupils" mean the people using the iPads targeted by the local profile draft. Answer the technician's actual question first. You may explain, troubleshoot, compare options, recommend the best solution, provide detailed steps and ask one focused follow-up question. Never say you do not understand merely because no verified edit matches; infer the most likely intent from the full sentence and recent conversation. If an important detail is missing, give the most useful likely answer first, state the assumption briefly and then ask for that detail. Return exactly one JSON object and no Markdown: {"reply":"clear technician guidance","edits":[{"kind":"set_restriction","restrictionKey":"exact key","value":true}]}. Allowed edit kinds are set_restriction, add_dock_app, remove_dock_app, rename_profile and set_target_group. Use an empty edits array for guidance, troubleshooting or any proposed change that does not precisely match the supplied catalogue. For creation requests, include all safe exact edits that can be applied to the local draft and use the reply to explain any settings that still need technician choice. If students cannot access a feature, first check whether the current local draft disables that exact feature. When it does, return the exact verified edit that allows the feature in the local draft and explain the local fix and remaining Jamf School checks. Treat recognised standard English words as intentional and correct only unmistakable spelling mistakes; never change "provide" to "profile" or "remotely" to "remote". Treat short requests such as "provide a how-to guide", "show me how" or "give me the steps" as follow-ups to the latest technician question in the supplied recent conversation. Never expose hidden reasoning, planning text or phrases like "the user wants" or "I need to". Never claim a Jamf School write, deployment or remote repair. Explain likely causes, evidence, checks and safe next steps. The verification boundary limits profile edits, not useful conversation; the app validates every edit independently.
    """

    static func context(for request: LocalModelRequest) -> String {
        let configuredKeys = Set(request.intent.restrictions.compactMap { key, state in
            state == .unchanged ? nil : key
        })
        var relevantDefinitions = RestrictionCatalogue.relevant(to: request.prompt, limit: 12)
        for key in configuredKeys where !relevantDefinitions.contains(where: { $0.key == key }) {
            relevantDefinitions.append(RestrictionCatalogue.definition(for: key))
        }
        let restrictions = relevantDefinitions.prefix(20).map { definition in
            "\(definition.key.rawValue) | \(definition.title) | true=\(definition.label(for: .allow)) | false=\(definition.label(for: .deny))"
        }.joined(separator: "\n")
        let configured = request.intent.restrictions.compactMap { key, state -> String? in
            state == .unchanged ? nil : "\(key.rawValue)=\(state == .allow ? "true" : "false")"
        }.sorted().joined(separator: ", ")
        let groups = request.jamfContext.deviceGroups.prefix(80).map { "\($0.name) [id=\($0.id)]" }.joined(separator: ", ")
        let documents = request.jamfKnowledgeSnippets.map { "SOURCE: \($0.title)\n\($0.excerpt)" }.joined(separator: "\n\n")
        let attachments = request.attachments.map(\.promptExcerpt).joined(separator: "\n\n")
        let recentConversation = request.recentMessages.suffix(8).map { message in
            let role = message.role == .technician ? "Technician" : "Assistant"
            let text = message.text.lowercased().contains("password")
                ? "[secret-bearing message withheld]"
                : String(message.text.prefix(600))
            return "\(role): \(text)"
        }.joined(separator: "\n")
        return """
        CURRENT LOCAL DRAFT
        Name: \(request.intent.name)
        Platform: \(request.intent.platform.rawValue)
        Target group: \(request.intent.scope.deviceGroupName)
        Supervised: \(request.intent.devicesAreSupervised)
        Time filter: \(request.intent.jamfTimeFilter?.summary ?? "none")
        Restrictions: \(configured.isEmpty ? "none" : configured)
        Dock: \(request.intent.dockItems.map(\.displayName).joined(separator: ", "))
        Known synced Jamf School device groups: \(groups.isEmpty ? "none" : groups)

        RELEVANT VERIFIED RESTRICTIONS
        \(restrictions.isEmpty ? "No exact restriction matched. Answer the question as practical guidance, ask one focused clarification if needed, and use no edit." : restrictions)

        RELEVANT LOCAL JAMF SCHOOL DOCUMENTATION
        \(documents.isEmpty ? "none" : documents)

        ATTACHMENTS EXTRACTED LOCALLY
        \(attachments.isEmpty ? "none" : attachments)

        RECENT CONVERSATION
        \(recentConversation.isEmpty ? "none" : recentConversation)

        TECHNICIAN REQUEST
        \(request.prompt)
        """
    }
}

private struct ExternalAIResponseEnvelope: Decodable {
    let reply: String?
    let edits: [ExternalAIProposedEdit]?
}

private struct ExternalAIProposedEdit: Decodable {
    let kind: String
    let restrictionKey: String?
    let value: Bool?
    let app: String?
    let name: String?

    func intentEdit(jamfContext: JamfReadContext) -> IntentEdit? {
        switch kind {
        case "set_restriction":
            guard let restrictionKey, let value, let key = RestrictionKey(rawValue: restrictionKey) else { return nil }
            return .setRestriction(key, value ? .allow : .deny)
        case "add_dock_app":
            return app?.lowercased() == "safari" ? .addDockItem(.safari) : app?.lowercased() == "classroom" ? .addDockItem(.classroom) : nil
        case "remove_dock_app":
            return app?.lowercased() == "safari" ? .removeDockItem(.safari) : app?.lowercased() == "classroom" ? .removeDockItem(.classroom) : nil
        case "rename_profile":
            guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
            return .renameProfile(String(name.prefix(100)))
        case "set_target_group":
            guard jamfContext.isConnected,
                  let name = name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let group = jamfContext.deviceGroups.first(where: { $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) else { return nil }
            return .setScopeName(group.name)
        default:
            return nil
        }
    }
}

private enum ExternalAIResponseParser {
    static func parse(_ text: String, request: LocalModelRequest) -> LocalModelResponse {
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let json = extractedJSONObject(from: cleaned),
              let data = json.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(ExternalAIResponseEnvelope.self, from: data) else {
            if isUsefulAdvisory(cleaned) {
                return LocalModelResponse(
                    message: cleaned + "\n\nThis is guidance only; the local profile and Jamf School have not been changed.",
                    edits: []
                )
            }
            return LocalModelResponse(
                message: "I can still help with this. Tell me the result you want and whether you are configuring a new profile or troubleshooting deployed devices; I’ll recommend the best Jamf School route and only apply exact verified edits.",
                edits: []
            )
        }
        let proposed = envelope.edits ?? []
        let edits = proposed.compactMap { $0.intentEdit(jamfContext: request.jamfContext) }
        let reply = envelope.reply?.trimmingCharacters(in: .whitespacesAndNewlines)
        if !edits.isEmpty {
            return LocalModelResponse(
                message: "I applied these verified local edits suggested by the external AI:\n• \(edits.map(\.verifiedDescription).joined(separator: "\n• "))\n\nNothing has been sent to Jamf School yet.",
                edits: edits
            )
        }
        if let reply, !reply.isEmpty, isUsefulAdvisory(reply, maximumLength: 6_000) {
            let rejected = proposed.count - edits.count
            let note = rejected > 0
                ? "\n\nI kept the local draft unchanged because the proposed edit did not match a verified Apple setting or known Jamf device group."
                : ""
            return LocalModelResponse(message: reply + note, edits: [])
        }
        return LocalModelResponse(
            message: "I can help with the likely Jamf School solution, but one detail would make the recommendation precise: what should students be able or unable to do, and is this a new configuration or a current device problem?",
            edits: []
        )
    }

    private static func extractedJSONObject(from text: String) -> String? {
        if text.first == "{", text.last == "}" { return text }
        guard let first = text.firstIndex(of: "{"),
              let last = text.lastIndex(of: "}"),
              first <= last else { return nil }
        return String(text[first...last])
    }

    private static func isUsefulAdvisory(
        _ text: String,
        maximumLength: Int = 1_600
    ) -> Bool {
        let lowercased = text.lowercased()
        guard text.count >= 2, text.count <= maximumLength else { return false }
        let unsafeClaims = [
            "i applied", "i changed", "i updated", "i removed", "successfully deployed",
            "okay, the user", "okay, the technician", "the technician is asking",
            "the user wants", "let me look", "let me start", "i need to check",
            "i need to set", "i should check", "looking at the allowed",
            "thinking process:", "analyze the request", "the answer should",
            "system prompt states", "output format:", "do not reveal chain-of-thought",
            "but wait", "wait, the technician", "wait, the user's request"
        ]
        return !unsafeClaims.contains(where: lowercased.contains)
    }
}

private struct OpenAIResponse: Decodable {
    struct Output: Decodable { let content: [Content]? }
    struct Content: Decodable { let text: String? }
    let output: [Output]?
}

private struct GeminiResponse: Decodable {
    struct Candidate: Decodable { let content: Content? }
    struct Content: Decodable { let parts: [Part]? }
    struct Part: Decodable { let text: String? }
    let candidates: [Candidate]?
}

private struct ClaudeResponse: Decodable {
    struct Content: Decodable { let text: String? }
    let content: [Content]
}

private struct MicrosoftTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct MicrosoftOAuthError: Decodable, LocalizedError {
    let error: String
    let errorDescription: String?

    private enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }

    var localizedDescription: String { errorDescription ?? error }
}

private struct MicrosoftGraphMe: Decodable {
    let displayName: String?
    let userPrincipalName: String?
    let mail: String?
}

private struct MicrosoftCopilotConversation: Decodable {
    struct Message: Decodable {
        let text: String
    }

    let id: String
    let messages: [Message]

    private enum CodingKeys: String, CodingKey {
        case id
        case messages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        messages = try container.decodeIfPresent([Message].self, forKey: .messages) ?? []
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private func formEncodedBody(_ fields: [String: String]) -> Data {
    fields
        .map { key, value in
            "\(key.formEncoded)=\(value.formEncoded)"
        }
        .joined(separator: "&")
        .data(using: .utf8) ?? Data()
}

private extension String {
    var formEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .formURLQueryAllowed) ?? self
    }
}

private extension CharacterSet {
    static let formURLQueryAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "!*'();:@&=+$,/?%#[]")
        return allowed
    }()
}

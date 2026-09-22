import Foundation

enum DetailPane: String, CaseIterable, Identifiable {
    case assistant = "Assistant"
    case jamfSchool = "Jamf School"
    case payload = "Payload preview"

    var id: String { rawValue }
}

enum JamfConnectionState: Equatable {
    case notConfigured
    case connecting
    case connected
    case failed(String)

    var title: String {
        switch self {
        case .notConfigured: "Not connected"
        case .connecting: "Connecting…"
        case .connected: "Read-only connected"
        case .failed: "Connection failed"
        }
    }
}

enum PlatformConnectionState: Equatable {
    case notConfigured
    case connecting
    case connected
    case failed(String)

    var title: String {
        switch self {
        case .notConfigured: "Platform beta not connected"
        case .connecting: "Connecting to Platform beta…"
        case .connected: "Blueprint lifecycle connected"
        case .failed: "Platform connection failed"
        }
    }
}

enum EnhancedModelPreparationState: Equatable {
    case available
    case preparing(ModelDownloadProgress)
    case ready
    case failed(String)
}

@MainActor
final class WorkspaceViewModel: ObservableObject {
    @Published var intent: ProfileIntent
    @Published var messages: [ChatMessage]
    @Published var draftMessage = ""
    @Published var selectedDetailPane: DetailPane = .assistant
    @Published var isModelResponding = false
    @Published private(set) var assistantAttachments: [AssistantAttachment] = []
    @Published private(set) var isProcessingAttachments = false
    @Published private(set) var attachmentStatusMessage: String?
    @Published private(set) var externalAIConfiguration: ExternalAIConfiguration
    @Published private(set) var enhancedModelState: EnhancedModelPreparationState = .available
    @Published private(set) var jamfConnectionState: JamfConnectionState = .notConfigured
    @Published private(set) var jamfProfiles: [JamfProfileSummary] = []
    @Published private(set) var jamfDeviceGroups: [JamfDeviceGroup] = []
    @Published private(set) var platformConnectionState: PlatformConnectionState = .notConfigured
    @Published private(set) var jamfBlueprints: [JamfBlueprintSummary] = []
    @Published var selectedBlueprintID: UUID?
    @Published private(set) var isPlatformMutating = false
    @Published private(set) var platformStatusMessage = "Connect the Jamf Platform API beta to manage blueprints."
    let jamfKnowledge = JamfSchoolKnowledgeBase()

    let localModel: LocalModelServing
    private let validator = ProfileValidator()
    private let compiler = ProfileCompiler()
    private let blueprintCompiler = BlueprintCompiler()
    private let jamfConnector: JamfSchoolConnecting
    private let platformConnector: JamfPlatformConnecting
    private let auditLogger: JamfMutationAuditLogging
    private let externalAIConfigurationStore: ExternalAIConfigurationStoring
    private let externalAIService: ExternalAIService

    init(
        intent: ProfileIntent = .blank,
        localModel: LocalModelServing = AdaptiveLocalModelService(),
        jamfConnector: JamfSchoolConnecting = JamfSchoolReadOnlyConnector(),
        platformConnector: JamfPlatformConnecting = JamfPlatformConnector(),
        auditLogger: JamfMutationAuditLogging = LocalJamfMutationAuditLogger(),
        externalAIConfigurationStore: ExternalAIConfigurationStoring = UserDefaultsExternalAIConfigurationStore(),
        externalAIService: ExternalAIService = ExternalAIService()
    ) {
        self.intent = intent
        self.localModel = localModel
        self.jamfConnector = jamfConnector
        self.platformConnector = platformConnector
        self.auditLogger = auditLogger
        self.externalAIConfigurationStore = externalAIConfigurationStore
        self.externalAIService = externalAIService
        self.externalAIConfiguration = externalAIConfigurationStore.load()
        self.messages = [
            ChatMessage(
                role: .assistant,
                text: "This assistant runs on-device. Verified profile edits are checked against Apple's catalogue. You can enable the stronger Qwen model for local reasoning; Apple Intelligence and the deterministic interpreter remain available as fallbacks. No prompt or Jamf credential leaves this Mac."
            )
        ]
        if let enhanced = localModel as? EnhancedLocalModelServing,
           enhanced.isEnhancedModelLoaded {
            enhancedModelState = .ready
        }
    }

    var supportsEnhancedModel: Bool {
        localModel is EnhancedLocalModelServing
    }

    var assistantDisplayName: String {
        externalAIConfiguration.provider == .localQwen
            ? localModel.displayName
            : externalAIConfiguration.provider.title
    }

    var assistantStatusDetail: String {
        externalAIConfiguration.provider == .localQwen
            ? localModel.statusDetail
            : "External AI connection · selected profile context is sent only when you submit a message"
    }

    var isUsingExternalAI: Bool { externalAIConfiguration.provider.isExternal }

    var enhancedModelName: String {
        (localModel as? EnhancedLocalModelServing)?.enhancedModelName ?? "Enhanced local model"
    }

    var enhancedModelDownloadDescription: String {
        (localModel as? EnhancedLocalModelServing)?.enhancedModelDownloadDescription ?? ""
    }

    var isEnhancedModelReady: Bool {
        if case .ready = enhancedModelState { return true }
        return (localModel as? EnhancedLocalModelServing)?.isEnhancedModelLoaded == true
    }

    var validationIssues: [ValidationIssue] {
        validator.validate(intent)
    }

    var hasValidationErrors: Bool {
        validationIssues.contains { $0.severity == .error }
    }

    var compiledProfile: CompiledProfile? {
        try? compiler.compile(intent)
    }

    var payloadPreview: String {
        if let compiledProfile {
            return jamfTimeFilterPreview + "\n\n" + compiledProfile.redactedXML
        }
        let errors = validationIssues
            .filter { $0.severity == .error }
            .map { "• \($0.title): \($0.detail)" }
            .joined(separator: "\n")
        return "Resolve the following before compiling:\n\n" + errors
    }

    private var jamfTimeFilterPreview: String {
        guard let filter = intent.jamfTimeFilter else {
            return "Jamf School schedule\nNo time filter configured."
        }
        return """
        Jamf School schedule (deployment metadata, not part of .mobileconfig)
        Active days: \(JamfWeekday.allCases.filter(filter.activeDays.contains).map(\.title).joined(separator: ", "))
        Active time: \(filter.isActiveAllDay ? "All day" : "\(filter.startTime.displayName) to \(filter.endTime.displayName)")
        Holidays: \(filter.disableOnConfiguredHolidays ? "Disabled on configured Jamf School holidays" : "Active on configured Jamf School holidays")
        """
    }

    var jamfReadContext: JamfReadContext {
        JamfReadContext(
            isConnected: jamfConnectionState == .connected,
            profiles: jamfProfiles,
            deviceGroups: jamfDeviceGroups,
            blueprints: jamfBlueprints
        )
    }

    var matchingJamfProfiles: [JamfProfileSummary] {
        let profileName = intent.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !profileName.isEmpty else { return [] }
        return jamfProfiles.filter {
            $0.name.compare(
                profileName,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame
        }
    }

    var selectedJamfDeviceGroup: JamfDeviceGroup? {
        if let groupID = intent.scope.deviceGroupID {
            return jamfDeviceGroups.first { $0.id == groupID }
        }
        return jamfDeviceGroups.first {
            $0.name.compare(
                intent.scope.deviceGroupName,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame
        }
    }

    var pendingWiFiPasswordPayload: WiFiPayloadIntent? {
        intent.wifiPayloads.last {
            $0.authenticationType == .personal &&
                $0.securityType?.requiresCredential == true &&
                $0.password.isEmpty
        }
    }

    var matchingJamfBlueprints: [JamfBlueprintSummary] {
        let profileName = intent.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !profileName.isEmpty else { return [] }
        return jamfBlueprints.filter {
            $0.name.compare(
                profileName,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame
        }
    }

    var selectedJamfBlueprint: JamfBlueprintSummary? {
        if let selectedBlueprintID {
            return jamfBlueprints.first { $0.id == selectedBlueprintID }
        }
        return matchingJamfBlueprints.count == 1 ? matchingJamfBlueprints[0] : nil
    }

    var canCreateBlueprint: Bool {
        platformConnectionState == .connected &&
        jamfConnectionState == .connected &&
        selectedJamfDeviceGroup != nil &&
        compiledProfile != nil &&
        intent.jamfTimeFilter == nil &&
        matchingJamfBlueprints.isEmpty &&
        matchingJamfProfiles.isEmpty &&
        !isPlatformMutating
    }

    func setRestriction(_ key: RestrictionKey, state: RestrictionState) {
        var updated = intent
        updated.restrictions[key] = state
        intent = updated
    }

    func setDockItem(_ item: DockItem, isIncluded: Bool) {
        var updated = intent
        updated.dockItems.removeAll { $0.id == item.id }
        if isIncluded { updated.dockItems.append(item) }
        intent = updated
    }

    func addWiFiPayload() {
        var updated = intent
        updated.wifiPayloads.append(WiFiPayloadIntent())
        intent = updated
        messages.append(ChatMessage(
            role: .assistant,
            text: "Wi-Fi payload started. Enter the exact SSID, choose the authentication and security types, then provide any password in the secure field."
        ))
    }

    func removeWiFiPayload(id: UUID) {
        var updated = intent
        updated.wifiPayloads.removeAll { $0.id == id }
        intent = updated
    }

    func saveWiFiPassword(_ password: String, for payloadID: UUID) {
        guard !password.isEmpty,
              let index = intent.wifiPayloads.firstIndex(where: { $0.id == payloadID }) else {
            return
        }
        var updated = intent
        updated.wifiPayloads[index].password = password
        intent = updated
        messages.append(ChatMessage(
            role: .assistant,
            text: "The Wi-Fi password for ‘\(updated.wifiPayloads[index].ssid)’ is stored in memory and redacted from the preview. Review validation before export or deployment."
        ))
    }

    func abandonWiFiDraft(id: UUID) {
        guard intent.wifiPayloads.contains(where: { $0.id == id }) else { return }
        removeWiFiPayload(id: id)
        messages.append(ChatMessage(
            role: .assistant,
            text: "The incomplete local Wi-Fi draft was removed. Nothing was changed in Jamf School."
        ))
    }

    func selectJamfDeviceGroup(id: Int) {
        guard jamfConnectionState == .connected,
              let group = jamfDeviceGroups.first(where: { $0.id == id }) else { return }
        var updated = intent
        updated.scope.deviceGroupName = group.name
        updated.scope.deviceGroupID = group.id
        intent = updated
        messages.append(ChatMessage(
            role: .assistant,
            text: "Target group set locally to the existing Jamf School group ‘\(group.name)’. Nothing has been deployed."
        ))
    }

    func clearJamfDeviceGroupSelection() {
        var updated = intent
        updated.scope.deviceGroupName = ""
        updated.scope.deviceGroupID = nil
        intent = updated
    }

    func syncJamfSchool() async {
        guard jamfConnectionState != .connecting else { return }
        jamfConnectionState = .connecting

        do {
            let profiles = try await jamfConnector.listProfiles()
            let groups = try await jamfConnector.listDeviceGroups()
            jamfProfiles = profiles.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            jamfDeviceGroups = groups.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            if let selectedGroupID = intent.scope.deviceGroupID,
               !jamfDeviceGroups.contains(where: { $0.id == selectedGroupID }) {
                clearJamfDeviceGroupSelection()
            }
            jamfConnectionState = .connected
            messages.append(ChatMessage(
                role: .assistant,
                text: "Jamf School read-only sync completed: \(profiles.count) profile\(profiles.count == 1 ? "" : "s") and \(groups.count) device group\(groups.count == 1 ? "" : "s") loaded. Credentials were not passed to the local model."
            ))
        } catch {
            jamfProfiles = []
            jamfDeviceGroups = []
            clearJamfDeviceGroupSelection()
            jamfConnectionState = .failed(error.localizedDescription)
        }
    }

    func syncJamfPlatform() async {
        guard platformConnectionState != .connecting, !isPlatformMutating else { return }
        platformConnectionState = .connecting
        do {
            let blueprints = try await platformConnector.listBlueprints()
            jamfBlueprints = blueprints.sorted {
                $0.updated > $1.updated
            }
            if let selectedBlueprintID,
               !blueprints.contains(where: { $0.id == selectedBlueprintID }) {
                self.selectedBlueprintID = nil
            }
            if selectedBlueprintID == nil {
                let matches = blueprints.filter {
                    $0.name.compare(intent.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                }
                if matches.count == 1 { selectedBlueprintID = matches[0].id }
            }
            platformConnectionState = .connected
            platformStatusMessage = "Loaded \(blueprints.count) managed blueprint\(blueprints.count == 1 ? "" : "s")."
        } catch {
            jamfBlueprints = []
            platformConnectionState = .failed(error.localizedDescription)
            platformStatusMessage = error.localizedDescription
        }
    }

    func selectBlueprint(id: UUID) {
        guard jamfBlueprints.contains(where: { $0.id == id }) else { return }
        selectedBlueprintID = id
    }

    func createBlueprint() async {
        guard canCreateBlueprint else {
            platformStatusMessage = "Creation is blocked until validation, exact group selection and duplicate checks pass."
            return
        }
        await performPlatformMutation(action: "create", blueprint: nil) {
            let response = try await platformConnector.createBlueprint(try blueprintCompiler.compile(intent))
            selectedBlueprintID = response.id
            return response.id
        }
    }

    func updateSelectedBlueprint() async {
        guard let blueprint = selectedJamfBlueprint else {
            platformStatusMessage = "Select exactly one blueprint to update."
            return
        }
        await performPlatformMutation(action: "update", blueprint: blueprint) {
            try await platformConnector.updateBlueprint(
                id: blueprint.id,
                draft: try blueprintCompiler.compile(intent)
            )
            return blueprint.id
        }
    }

    func deploySelectedBlueprint() async {
        guard let blueprint = selectedJamfBlueprint else {
            platformStatusMessage = "Select exactly one blueprint to deploy."
            return
        }
        await performPlatformMutation(action: "deploy", blueprint: blueprint) {
            let remote = try await platformConnector.blueprint(id: blueprint.id)
            guard let expectedGroupID = intent.scope.deviceGroupID,
                  remote.scope.deviceGroups == [String(expectedGroupID)] else {
                throw JamfPlatformError.destructiveGuard(
                    "Deployment blocked because the remote blueprint scope does not exactly match the selected Jamf School device group."
                )
            }
            try await platformConnector.deployBlueprint(id: blueprint.id)
            return blueprint.id
        }
    }

    func undeploySelectedBlueprint() async {
        guard let blueprint = selectedJamfBlueprint else {
            platformStatusMessage = "Select exactly one blueprint to undeploy."
            return
        }
        await performPlatformMutation(action: "undeploy", blueprint: blueprint) {
            try await platformConnector.undeployBlueprint(id: blueprint.id)
            return blueprint.id
        }
    }

    func deleteSelectedBlueprint() async {
        guard let blueprint = selectedJamfBlueprint else {
            platformStatusMessage = "Select exactly one blueprint to delete."
            return
        }
        guard blueprint.deploymentState.state == .notDeployed else {
            platformStatusMessage = "Undeploy ‘\(blueprint.name)’ and refresh its state before deletion."
            return
        }
        await performPlatformMutation(action: "delete", blueprint: blueprint) {
            let remote = try await platformConnector.blueprint(id: blueprint.id)
            guard remote.deploymentState.state == .notDeployed else {
                throw JamfPlatformError.destructiveGuard(
                    "Deletion blocked because Jamf reports that this blueprint is still deployed or out of date. Undeploy and refresh first."
                )
            }
            try await platformConnector.deleteBlueprint(id: blueprint.id)
            selectedBlueprintID = nil
            return blueprint.id
        }
    }

    func sendMessage(_ rawPrompt: String) {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isModelResponding else { return }

        if captureExpectedWiFiPassword(from: prompt) {
            return
        }

        messages.append(ChatMessage(role: .technician, text: prompt))
        isModelResponding = true

        externalAIConfiguration = externalAIConfigurationStore.load()
        let request = LocalModelRequest(
            prompt: prompt,
            intent: intent,
            validationIssues: validationIssues,
            jamfContext: jamfReadContext,
            recentMessages: Array(messages.suffix(8)),
            jamfKnowledgeSnippets: jamfKnowledge.snippets(for: prompt),
            attachments: assistantAttachments
        )
        Task {
            let response: LocalModelResponse
            if let deterministic = PlaceholderLocalModelService()
                .deterministicResponseIfHandled(to: request) {
                response = deterministic
            } else if externalAIConfiguration.provider.isExternal {
                response = await externalAIService.respond(to: request, configuration: externalAIConfiguration)
            } else {
                response = await localModel.respond(to: request)
            }
            let verifiedResponse = await responseWithVerifiedLocalEditsIfNeeded(response, request: request)
            let safeResponse = await responseReplacingUnsafeModelOutput(verifiedResponse, request: request)
            apply(safeResponse.edits)
            messages.append(ChatMessage(
                role: .assistant,
                text: presentationSafeMessage(safeResponse.message, for: request),
                details: responseDetails(for: request, response: safeResponse)
            ))
            isModelResponding = false
        }
    }

    func sendMessage() {
        let prompt = draftMessage
        draftMessage = ""
        sendMessage(prompt)
    }

    func useQuickPrompt(_ prompt: String) {
        sendMessage(prompt)
    }

    func addAssistantAttachments(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        let remainingCapacity = max(8 - assistantAttachments.count, 0)
        guard remainingCapacity > 0 else {
            attachmentStatusMessage = "Remove an attachment before adding more than eight files."
            return
        }

        isProcessingAttachments = true
        attachmentStatusMessage = "Reading \(min(urls.count, remainingCapacity)) attachment\(min(urls.count, remainingCapacity) == 1 ? "" : "s") locally…"
        var addedCount = 0
        var failures: [String] = []
        for url in urls.prefix(remainingCapacity) {
            do {
                let attachment = try await Task.detached(priority: .userInitiated) {
                    try AssistantAttachmentProcessor.analyse(url: url)
                }.value
                assistantAttachments.append(attachment)
                addedCount += 1
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        isProcessingAttachments = false
        if failures.isEmpty {
            attachmentStatusMessage = "\(addedCount) attachment\(addedCount == 1 ? "" : "s") ready for local analysis."
        } else {
            attachmentStatusMessage = failures.joined(separator: " · ")
        }
    }

    func removeAssistantAttachment(id: UUID) {
        assistantAttachments.removeAll { $0.id == id }
        attachmentStatusMessage = assistantAttachments.isEmpty
            ? "No attachments are currently included with assistant requests."
            : "\(assistantAttachments.count) attachment\(assistantAttachments.count == 1 ? "" : "s") remain available to the assistant."
    }

    func recordAttachmentSelectionFailure(_ error: Error) {
        attachmentStatusMessage = "Could not select attachments: \(error.localizedDescription)"
    }

    func prepareEnhancedModel() async {
        await prepareEnhancedModel(persistPreference: true)
    }

    func restoreEnhancedModelIfEnabled() async {
        guard UserDefaults.standard.bool(forKey: Self.enhancedModelPreferenceKey) else { return }
        await prepareEnhancedModel(persistPreference: false)
    }

    private func apply(_ edits: [IntentEdit]) {
        var updated = intent
        for edit in edits {
            switch edit {
            case .setRestriction(let key, let state):
                updated.restrictions[key] = state
            case .addDockItem(let item):
                if !updated.dockItems.contains(item) {
                    updated.dockItems.append(item)
                }
            case .removeDockItem(let item):
                updated.dockItems.removeAll { $0 == item }
            case .addWiFiPayload(let wifi):
                if !updated.wifiPayloads.contains(where: { $0.id == wifi.id }) {
                    updated.wifiPayloads.append(wifi)
                }
            case .updateWiFiPayload(let wifi):
                if let index = updated.wifiPayloads.firstIndex(where: { $0.id == wifi.id }) {
                    updated.wifiPayloads[index] = wifi
                }
            case .removeWiFiPayload(let id):
                updated.wifiPayloads.removeAll { $0.id == id }
            case .renameProfile(let name):
                updated.name = name
            case .setDevicesAreSupervised(let isSupervised):
                updated.devicesAreSupervised = isSupervised
            case .setScopeName(let name):
                if jamfConnectionState == .connected,
                   let group = jamfDeviceGroups.first(where: {
                    $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                }) {
                    updated.scope.deviceGroupName = group.name
                    updated.scope.deviceGroupID = group.id
                }
            case .configureJamfTimeFilter(let filter):
                updated.jamfTimeFilter = filter
            case .removeJamfTimeFilter:
                updated.jamfTimeFilter = nil
            }
        }
        intent = updated
    }

    private func responseWithVerifiedLocalEditsIfNeeded(
        _ response: LocalModelResponse,
        request: LocalModelRequest
    ) async -> LocalModelResponse {
        guard response.edits.isEmpty else { return response }

        let localPlan = await PlaceholderLocalModelService().respond(to: request)
        guard !localPlan.edits.isEmpty else {
            return Self.looksLikeModelSelfTalk(response.message) ? localPlan : response
        }

        let cleanModelMessage = response.message.trimmingCharacters(in: .whitespacesAndNewlines)
        let localMessage = localPlan.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanModelMessage.isEmpty,
           !Self.looksLikeModelSelfTalk(cleanModelMessage) {
            return LocalModelResponse(
                message: cleanModelMessage + "\n\nI also converted the safe parts into verified local draft edits:\n\n" + localMessage,
                edits: localPlan.edits
            )
        }
        return localPlan
    }

    private func responseReplacingUnsafeModelOutput(
        _ response: LocalModelResponse,
        request: LocalModelRequest
    ) async -> LocalModelResponse {
        guard Self.looksLikeModelSelfTalk(response.message) else { return response }

        if !response.edits.isEmpty {
            return LocalModelResponse(
                message: "Done — I’ve updated the verified local draft:\n• " + response.edits
                    .map(\.verifiedDescription)
                    .joined(separator: "\n• ") + "\n\nNothing has been sent to Jamf School yet.",
                edits: response.edits
            )
        }
        return await PlaceholderLocalModelService().respond(to: request)
    }

    private func prepareEnhancedModel(persistPreference: Bool) async {
        guard let enhanced = localModel as? EnhancedLocalModelServing else { return }
        guard !enhanced.isEnhancedModelLoaded else {
            enhancedModelState = .ready
            return
        }
        if case .preparing = enhancedModelState { return }

        enhancedModelState = .preparing(.starting)
        do {
            try await enhanced.prepareEnhancedModel { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if case .preparing(let current) = self.enhancedModelState,
                       progress.fractionCompleted < current.fractionCompleted {
                        return
                    }
                    self.enhancedModelState = .preparing(progress)
                }
            }
            if persistPreference {
                UserDefaults.standard.set(true, forKey: Self.enhancedModelPreferenceKey)
            }
            enhancedModelState = .ready
            messages.append(ChatMessage(
                role: .assistant,
                text: "The enhanced Qwen model is loaded and will now handle requests that the verified command layer cannot resolve directly. Inference stays on this Mac."
            ))
        } catch {
            enhancedModelState = .failed(error.localizedDescription)
            messages.append(ChatMessage(
                role: .assistant,
                text: "The enhanced local model could not be loaded: \(error.localizedDescription)"
            ))
        }
    }

    private static let enhancedModelPreferenceKey = "MDMCopilotEnhancedModelEnabled"

    private func presentationSafeMessage(
        _ message: String,
        for request: LocalModelRequest
    ) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.looksLikeModelSelfTalk(trimmed) {
            return "I cleaned up an incomplete model response. The profile is unchanged unless verified edits are listed above."
        }
        guard trimmed.first == "{" || trimmed.hasPrefix("```json") else {
            return conciseVisibleReply(trimmed, for: request.prompt)
        }
        let json = trimmed
            .replacingOccurrences(of: "```json", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let reply = try? JSONDecoder().decode(AssistantReplyEnvelope.self, from: Data(json.utf8)).reply,
           !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !Self.looksLikeModelSelfTalk(reply) {
            return conciseVisibleReply(reply, for: request.prompt)
        }
        return "I kept the local profile unchanged because the model response was incomplete. I can still help: tell me the result you want for students and whether this is a new setup or a problem on deployed devices, and I’ll recommend the most practical Jamf School route."
    }

    private func conciseVisibleReply(_ text: String, for prompt: String) -> String {
        let lowercasedPrompt = prompt.lowercased()
        let explicitlyRequestsDetail = [
            "step-by-step", "step by step", "give me the steps", "show me the steps",
            "walk me through", "how-to guide", "how to guide", "detailed guide",
            "full guide", "full detail", "everything", "how do i", "how can i"
        ].contains(where: lowercasedPrompt.contains)
        guard !explicitlyRequestsDetail, text.count > 1_100 else { return text }

        let prefix = String(text.prefix(1_100))
        let minimumUsefulLength = 650
        let endings = ["\n\n", ".\n", ". ", "? ", "! "]
        let preferredCut = endings.compactMap { marker -> String.Index? in
            guard let range = prefix.range(of: marker, options: .backwards),
                  prefix.distance(from: prefix.startIndex, to: range.upperBound) >= minimumUsefulLength else {
                return nil
            }
            return range.upperBound
        }.max { lhs, rhs in
            prefix.distance(from: prefix.startIndex, to: lhs) < prefix.distance(from: prefix.startIndex, to: rhs)
        }
        let shortened = preferredCut.map { String(prefix[..<$0]) } ?? prefix
        return shortened.trimmingCharacters(in: .whitespacesAndNewlines)
            + "\n\nAsk for a step-by-step guide if you want the full procedure."
    }

    private func responseDetails(
        for request: LocalModelRequest,
        response: LocalModelResponse
    ) -> String {
        var checked = ["the current local draft", "the relevant verified Apple settings"]
        if !request.validationIssues.isEmpty {
            checked.append("\(request.validationIssues.count) validation finding\(request.validationIssues.count == 1 ? "" : "s")")
        }
        if request.jamfContext.isConnected {
            checked.append("the synced Jamf School read context")
        }
        if !request.jamfKnowledgeSnippets.isEmpty {
            checked.append("\(request.jamfKnowledgeSnippets.count) local Jamf knowledge reference\(request.jamfKnowledgeSnippets.count == 1 ? "" : "s")")
        }
        if !request.attachments.isEmpty {
            checked.append("\(request.attachments.count) local attachment\(request.attachments.count == 1 ? "" : "s")")
        }

        let result = response.edits.isEmpty
            ? "No local draft changes were made."
            : "\(response.edits.count) verified local draft change\(response.edits.count == 1 ? " was" : "s were") prepared."
        return "Checked: \(checked.joined(separator: ", ")).\nResult: \(result) Nothing was sent to Jamf School."
    }

    private static func looksLikeModelSelfTalk(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        return [
            "okay, the user",
            "okay, the technician",
            "the technician is asking",
            "the user wants",
            "let me look",
            "let me start",
            "i need to check",
            "i need to set",
            "i should check",
            "looking at the allowed",
            "thinking process:",
            "analyze the request",
            "evaluate the \"",
            "the answer should",
            "system prompt states",
            "output format:",
            "do not reveal chain-of-thought",
            "but wait",
            "wait, the technician",
            "wait, the user's request",
            "since the exact catalogue"
        ].contains(where: lowercased.contains)
    }

    private func captureExpectedWiFiPassword(from prompt: String) -> Bool {
        guard let pending = pendingWiFiPasswordPayload else { return false }

        let lowercased = prompt.lowercased()
        let prefixes = ["password is ", "password: ", "passphrase is ", "passphrase: "]
        var candidate: String?
        for prefix in prefixes where lowercased.hasPrefix(prefix) {
            let offset = lowercased.distance(from: lowercased.startIndex, to: lowercased.index(lowercased.startIndex, offsetBy: prefix.count))
            let start = prompt.index(prompt.startIndex, offsetBy: offset)
            candidate = String(prompt[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        let reservedWords: Set<String> = [
            "cancel", "skip", "later", "no", "yes", "help", "camera", "screenshots",
            "airdrop", "wpa", "wpa2", "wpa3", "wep", "open"
        ]
        if candidate == nil,
           !prompt.contains(where: \.isWhitespace),
           !reservedWords.contains(lowercased),
           isPlausibleWiFiCredential(prompt, security: pending.securityType) {
            candidate = prompt
        }

        guard let password = candidate, !password.isEmpty else { return false }
        messages.append(ChatMessage(role: .technician, text: "Wi-Fi password entered securely ••••••••"))
        saveWiFiPassword(password, for: pending.id)
        return true
    }

    private func isPlausibleWiFiCredential(
        _ value: String,
        security: WiFiSecurityType?
    ) -> Bool {
        switch security {
        case .wep:
            return [5, 10, 13, 26].contains(value.count)
        case .wpa, .wpa2, .wpa3, .any:
            return (8...64).contains(value.count)
        case Optional.some(WiFiSecurityType.none), Optional.none:
            return false
        }
    }

    private func performPlatformMutation(
        action: String,
        blueprint: JamfBlueprintSummary?,
        operation: () async throws -> UUID
    ) async {
        guard !isPlatformMutating else { return }
        isPlatformMutating = true
        defer { isPlatformMutating = false }
        let name = blueprint?.name ?? intent.name
        do {
            let blueprintID = try await operation()
            auditLogger.record(JamfMutationAuditEntry(
                timestamp: Date(),
                action: action,
                blueprintID: blueprintID,
                blueprintName: name,
                deviceGroupID: intent.scope.deviceGroupID,
                outcome: "succeeded"
            ))
            platformStatusMessage = "Blueprint \(action) request succeeded for ‘\(name)’. Refreshing state…"
            let blueprints = try await platformConnector.listBlueprints()
            jamfBlueprints = blueprints.sorted { $0.updated > $1.updated }
            platformConnectionState = .connected
            platformStatusMessage = "Blueprint \(action) completed for ‘\(name)’."
        } catch {
            auditLogger.record(JamfMutationAuditEntry(
                timestamp: Date(),
                action: action,
                blueprintID: blueprint?.id,
                blueprintName: name,
                deviceGroupID: intent.scope.deviceGroupID,
                outcome: "failed: \(error.localizedDescription)"
            ))
            platformStatusMessage = error.localizedDescription
        }
    }
}

private struct AssistantReplyEnvelope: Decodable {
    let reply: String
}

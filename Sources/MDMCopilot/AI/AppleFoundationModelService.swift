import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

final class AdaptiveLocalModelService: EnhancedLocalModelServing {
    private let fallback = PlaceholderLocalModelService()
    private let qwen = QwenLocalModelService()

    var displayName: String {
        if qwen.isLoaded { return qwen.displayName }
        return isAppleFoundationModelAvailable
            ? "Apple on-device Foundation Model"
            : fallback.displayName
    }

    var isGenerativeModelLoaded: Bool {
        qwen.isLoaded || isAppleFoundationModelAvailable
    }

    var isEnhancedModelLoaded: Bool { qwen.isLoaded }
    var enhancedModelName: String { qwen.displayName }
    var enhancedModelDownloadDescription: String { "about 3 GB" }

    private var isAppleFoundationModelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    var statusDetail: String {
        if qwen.isLoaded {
            return "Qwen runs through MLX on this Mac; prompts stay local"
        }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return "Apple Intelligence is ready; prompts stay on this Mac"
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Enable Apple Intelligence to use the generative model"
            case .unavailable(.deviceNotEligible):
                return "This Mac is not eligible for Apple Intelligence"
            case .unavailable(.modelNotReady):
                return "Apple's on-device model is still being prepared"
            case .unavailable:
                return "Apple's on-device model is unavailable"
            }
        }
        #endif
        return "Requires macOS 26 and an Apple Intelligence-capable Mac; fallback active"
    }

    func prepareEnhancedModel(
        progressHandler: @Sendable @escaping (ModelDownloadProgress) -> Void
    ) async throws {
        try await qwen.prepare(progressHandler: progressHandler)
    }

    func respond(to request: LocalModelRequest) async -> LocalModelResponse {
        if let deterministic = fallback.deterministicResponseIfHandled(to: request) {
            return deterministic
        }

        let verifiedFallback = await fallback.respond(to: request)
        if !verifiedFallback.edits.isEmpty {
            return verifiedFallback
        }

        let interpretation = PromptInterpretation.interpret(request.prompt)
        let interpretedRequest = LocalModelRequest(
            prompt: interpretation.correctedPrompt,
            intent: request.intent,
            validationIssues: request.validationIssues,
            jamfContext: request.jamfContext,
            recentMessages: request.recentMessages,
            jamfKnowledgeSnippets: request.jamfKnowledgeSnippets,
            attachments: request.attachments
        )

        if qwen.isLoaded {
            do {
                return try await qwen.respond(to: interpretedRequest)
                    .acknowledging(interpretation)
            } catch {
                return LocalModelResponse(
                    message: "The enhanced model hit a local runtime problem, so I switched to the offline guidance layer.\n\n\(verifiedFallback.message)",
                    edits: verifiedFallback.edits
                ).acknowledging(interpretation)
            }
        }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), SystemLanguageModel.default.isAvailable {
            do {
                return try await foundationModelResponse(to: interpretedRequest)
                    .acknowledging(interpretation)
            } catch {
                let fallbackResponse = await fallback.respond(to: request)
                return LocalModelResponse(
                    message: "The Apple on-device model couldn’t complete that request, so I checked it with the safe local interpreter instead. \(fallbackResponse.message)",
                    edits: fallbackResponse.edits
                )
            }
        }
        #endif
        return await fallback.respond(to: request)
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
private extension AdaptiveLocalModelService {
    func foundationModelResponse(to request: LocalModelRequest) async throws -> LocalModelResponse {
        let instructions = """
        You are an on-device assistant for a technician building an Apple iPad management profile.
        Put only the final technician-facing answer in the reply. Keep normal answers under 120 words
        and five bullets. Only go longer for an explicitly requested detailed or step-by-step guide.
        Do not narrate your analysis, repeat the prompt or expose private reasoning.
        Answer the technician's request directly and translate any exact supported changes into structured
        edits. If a requested setting is unsupported or ambiguous, use no edit but still provide useful
        Jamf School or Apple device-management guidance. Never
        invent Apple payload keys, Jamf endpoints, device facts, or deployment results. Never claim
        that a Jamf write occurred. Questions may be answered with an empty edits list. Keep the reply
        concise and state exactly what was changed or recommended. Sound like a warm,
        practical technical colleague: confident but never overconfident, with a little personality
        and no corporate filler. Treat recognised standard English words as intentional. Correct only an
        unmistakable spelling mistake when context leaves one clear meaning, and never change “provide”
        to “profile” or “remotely” to “remote”. Mention it only when it changes your interpretation.
        In this app, "users", "students", "kids", "learners" and "pupils" mean the people using the
        iPads targeted by the local profile draft. If students cannot access a feature, first check
        whether this local draft disables that exact feature. When it does, return the exact verified
        edit that allows the feature in the local draft and explain the change and remaining Jamf checks.
        For troubleshooting, separate what the local draft proves from what needs checking on an iPad,
        in Jamf School or in Apple School Manager. Offer one safe next step, and only propose a profile
        edit when a supported local setting directly addresses the confirmed cause. Never claim a remote
        diagnosis, repair or deployment result that you cannot observe.
        Treat short requests such as “provide a how-to guide”, “show me how” and “give me the steps” as
        follow-ups to the most recent technician question supplied in the conversation context.
        Answer first. You may troubleshoot, compare approaches, recommend the best option and provide
        step-by-step instructions even when no local edit exists. Never say you do not understand merely
        because no verified profile key matches. Infer the most likely intent from context; if important
        information is missing, give the likely answer, state the assumption and ask one focused question.
        The verification boundary limits profile edits, not useful conversation.
        """
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(
            to: prompt(for: request),
            generating: GeneratedAssistantResponse.self,
            options: GenerationOptions(temperature: 0, maximumResponseTokens: 350)
        )

        let mappedEdits = response.content.edits.compactMap {
            $0.intentEdit(jamfContext: request.jamfContext)
        }
        let rejectedCount = response.content.edits.count - mappedEdits.count
        var message: String
        if mappedEdits.isEmpty, rejectedCount > 0 {
            let reply = response.content.reply.trimmingCharacters(in: .whitespacesAndNewlines)
            message = reply.isEmpty
                ? "I kept the local draft unchanged because the proposed edit did not match a verified setting. Tell me the outcome you want and I’ll recommend the closest supported Jamf School approach."
                : reply + "\n\nI kept the local draft unchanged because the proposed edit did not match a verified Apple setting or known Jamf device group."
        } else if !mappedEdits.isEmpty {
            message = "Done — I’ve updated the verified local draft:\n• " + mappedEdits
                .map(\.verifiedDescription)
                .joined(separator: "\n• ")
            message += "\n\nNothing has been sent to Jamf School yet."
            if rejectedCount > 0 {
                message += "\n\nI ignored \(rejectedCount) unsupported or unverified proposal\(rejectedCount == 1 ? "" : "s")."
            }
        } else {
            message = response.content.reply.trimmingCharacters(in: .whitespacesAndNewlines)
            if message.isEmpty {
                message = "I can still help with this as a Jamf School or Apple device-management question. Tell me the outcome you want and whether this is a new setup or an issue on deployed devices, and I’ll recommend the most practical route."
            }
        }
        return LocalModelResponse(message: message, edits: mappedEdits)
    }

    func prompt(for request: LocalModelRequest) -> String {
        let configuredKeys = Set(request.intent.restrictions.compactMap {
            $0.value == .unchanged ? nil : $0.key
        })
        var relevantDefinitions = RestrictionCatalogue.relevant(to: request.prompt, limit: 12)
        for key in configuredKeys where !relevantDefinitions.contains(where: { $0.key == key }) {
            relevantDefinitions.append(RestrictionCatalogue.definition(for: key))
        }
        let restrictions = relevantDefinitions.prefix(20).map { definition in
            let state = request.intent.restrictions[definition.key] ?? .unchanged
            let currentValue = state == .unchanged ? "unchanged" : (state == .allow ? "true" : "false")
            return "\(definition.title) [key=\(definition.key.rawValue), current=\(currentValue), true means \(definition.label(for: .allow)), false means \(definition.label(for: .deny))]"
        }.joined(separator: ", ")
        let dock = request.intent.dockItems.map(\.displayName).joined(separator: ", ")
        let findings = request.validationIssues.prefix(8).map {
            "\($0.title): \($0.detail)"
        }.joined(separator: " | ")
        let groups = request.jamfContext.deviceGroups.prefix(40).map {
            "\($0.name) [id=\($0.id), members=\($0.members ?? 0)]"
        }.joined(separator: "; ")
        let profiles = request.jamfContext.profiles.prefix(40).map(\.name).joined(separator: "; ")
        let blueprints = request.jamfContext.blueprints.prefix(40).map {
            "\($0.name) [\($0.deploymentState.state.title)]"
        }.joined(separator: "; ")
        let wifi = request.intent.wifiPayloads.map { network in
            let security = network.securityType?.rawValue ?? "not selected"
            let credential = network.authenticationType == .enterprise
                ? "enterprise credential \(network.enterprise.password.isEmpty ? "missing" : "present")"
                : "password \(network.password.isEmpty ? "missing" : "present")"
            return "SSID=\(network.ssid.isEmpty ? "missing" : network.ssid), security=\(security), authentication=\(network.authenticationType.rawValue), \(credential)"
        }.joined(separator: "; ")
        let conversation = request.recentMessages.suffix(8).map { message in
            let role = message.role == .technician ? "Technician" : "Assistant"
            let text = message.text.lowercased().contains("password")
                ? "[message withheld because it may contain a secret]"
                : String(message.text.prefix(600))
            return "\(role): \(text)"
        }.joined(separator: "\n")
        let attachments = request.attachments.map(\.promptExcerpt).joined(separator: "\n\n")

        return """
        Current local profile:
        name: \(request.intent.name)
        platform: \(request.intent.platform.rawValue)
        target group: \(request.intent.scope.deviceGroupName)
        supervised: \(request.intent.devicesAreSupervised)
        relevant and configured restrictions: \(restrictions.isEmpty ? "none" : restrictions)
        Dock: \(dock.isEmpty ? "none" : dock)
        Wi-Fi payloads: \(wifi.isEmpty ? "none" : wifi)
        validation findings: \(findings.isEmpty ? "none" : findings)

        Read-only Jamf School context:
        connection: \(request.jamfContext.isConnected ? "connected" : "not connected")
        device groups: \(groups.isEmpty ? "none loaded" : groups)
        existing profiles: \(profiles.isEmpty ? "none loaded" : profiles)
        managed blueprints: \(blueprints.isEmpty ? "none loaded" : blueprints)

        The model may explain lifecycle state but must never claim to create, update, deploy,
        undeploy or delete a blueprint. Those actions require technician confirmation in the UI.

        Recent conversation, with possible secret-bearing messages withheld:
        \(conversation.isEmpty ? "none" : conversation)

        Local attachments, extracted on this Mac:
        \(attachments.isEmpty ? "none" : attachments)

        <technician_request>
        \(request.prompt)
        </technician_request>
        """
    }
}

@available(macOS 26.0, *)
@Generable(description: "A concise response and zero or more safe edits to the local profile draft.")
private struct GeneratedAssistantResponse {
    @Guide(description: "Supported changes requested by the technician.", .maximumCount(8))
    var edits: [GeneratedIntentEdit]

    @Guide(description: "A concise explanation of edits made or why no supported edit was made.")
    var reply: String
}

@available(macOS 26.0, *)
@Generable(description: "One supported edit to the local profile draft.")
private enum GeneratedIntentEdit {
    case setRestriction(restrictionKey: String, value: GeneratedBooleanValue)
    case addDockApp(app: GeneratedDockApp)
    case removeDockApp(app: GeneratedDockApp)
    case renameProfile(name: String)
    case setTargetGroup(name: String)

    func intentEdit(jamfContext: JamfReadContext) -> IntentEdit? {
        switch self {
        case .setRestriction(let restrictionKey, let value):
            guard let key = RestrictionCatalogue.resolve(restrictionKey) else { return nil }
            return .setRestriction(key, value.state)
        case .addDockApp(let app):
            return .addDockItem(app.item)
        case .removeDockApp(let app):
            return .removeDockItem(app.item)
        case .renameProfile(let name):
            guard let cleaned = cleanedName(name) else { return nil }
            return .renameProfile(cleaned)
        case .setTargetGroup(let name):
            guard jamfContext.isConnected,
                  let cleaned = cleanedName(name),
                  let group = jamfContext.deviceGroups.first(where: {
                      $0.name.compare(cleaned, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                  }) else { return nil }
            return .setScopeName(group.name)
        }
    }

    private func cleanedName(_ value: String) -> String? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(100))
    }
}

@available(macOS 26.0, *)
@Generable
private enum GeneratedBooleanValue {
    case unchanged
    case trueValue
    case falseValue

    var state: RestrictionState {
        switch self {
        case .unchanged: .unchanged
        case .trueValue: .allow
        case .falseValue: .deny
        }
    }
}

@available(macOS 26.0, *)
@Generable
private enum GeneratedDockApp {
    case classroom
    case safari

    var item: DockItem {
        switch self {
        case .classroom: .classroom
        case .safari: .safari
        }
    }
}
#endif

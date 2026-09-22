import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

final class QwenLocalModelService: @unchecked Sendable {
    static let modelID = "mlx-community/Qwen3.5-4B-MLX-4bit"
    static let modelRevision = "32f3e8ecf65426fc3306969496342d504bfa13f3"

    let displayName = "Qwen3.5 4B · MLX · 4-bit"

    private let lock = NSLock()
    private var container: ModelContainer?

    var isLoaded: Bool {
        locked { container != nil }
    }

    func prepare(
        progressHandler: @Sendable @escaping (ModelDownloadProgress) -> Void
    ) async throws {
        guard !isLoaded else {
            progressHandler(ModelDownloadProgress(
                fractionCompleted: 1,
                completedBytes: nil,
                totalBytes: nil,
                bytesPerSecond: nil,
                estimatedSecondsRemaining: 0
            ))
            return
        }

        let configuration = ModelConfiguration(
            id: Self.modelID,
            revision: Self.modelRevision,
            extraEOSTokens: ["<|im_end|>"]
        )
        let progressReporter = ModelDownloadProgressReporter(handler: progressHandler)
        progressReporter.report(completedBytes: 0, totalBytes: nil)
        let loaded = try await LLMModelFactory.shared.loadContainer(
            from: #hubDownloader(),
            using: #huggingFaceTokenizerLoader(),
            configuration: configuration,
            progressHandler: { progress in
                progressReporter.report(
                    completedBytes: progress.completedUnitCount,
                    totalBytes: progress.totalUnitCount
                )
            }
        )
        locked { container = loaded }
        progressReporter.report(completedBytes: 1, totalBytes: 1)
    }

    func respond(to request: LocalModelRequest) async throws -> LocalModelResponse {
        guard let container = locked({ container }) else {
            throw QwenLocalModelError.notLoaded
        }

        let session = ChatSession(
            container,
            instructions: Self.instructions,
            generateParameters: GenerateParameters(
                maxTokens: 500,
                maxKVSize: 4_096,
                kvBits: 8,
                temperature: 0
            ),
            additionalContext: ["enable_thinking": false]
        )
        let output = try await session.respond(to: "/no_think\n" + prompt(for: request))
        do {
            return try verifiedResponse(forModelOutput: output, request: request)
        } catch {
            if let advice = advisoryReply(from: output) {
                return LocalModelResponse(
                    message: advice + "\n\nThis is on-device guidance only; no local profile edit or Jamf School change has been made.",
                    edits: []
                )
            }
            return LocalModelResponse(message: bestEffortClarification(for: request), edits: [])
        }
    }

    func verifiedResponse(
        forModelOutput output: String,
        request: LocalModelRequest
    ) throws -> LocalModelResponse {
        let envelope = try decodeEnvelope(from: output)
        return verifiedResponse(from: envelope, request: request)
    }

    private func prompt(for request: LocalModelRequest) -> String {
        let configuredKeys = Set(request.intent.restrictions.compactMap { key, state in
            state == .unchanged ? nil : key
        })
        var relevantDefinitions = RestrictionCatalogue.relevant(to: request.prompt, limit: 12)
        for key in configuredKeys where !relevantDefinitions.contains(where: { $0.key == key }) {
            relevantDefinitions.append(RestrictionCatalogue.definition(for: key))
        }
        let catalogue = relevantDefinitions.prefix(20).map { definition in
            "\(definition.key.rawValue) | \(definition.title) | true=\(definition.label(for: .allow)) | false=\(definition.label(for: .deny))"
        }.joined(separator: "\n")
        let configured = request.intent.restrictions.compactMap { key, state -> String? in
            guard state != .unchanged else { return nil }
            return "\(key.rawValue)=\(state == .allow ? "true" : "false")"
        }.sorted().joined(separator: ", ")
        let groups = request.jamfContext.deviceGroups.prefix(80).map {
            "\($0.name) [id=\($0.id)]"
        }.joined(separator: ", ")
        let timeFilter = request.intent.jamfTimeFilter?.summary ?? "none"
        let recentConversation = request.recentMessages.suffix(8).map { message in
            let role = message.role == .technician ? "Technician" : "Assistant"
            let text = message.text.lowercased().contains("password")
                ? "[secret-bearing message withheld]"
                : String(message.text.prefix(500))
            return "\(role): \(text)"
        }.joined(separator: "\n")
        let documentation = request.jamfKnowledgeSnippets.map {
            "SOURCE: \($0.title) (\($0.sourceURL.absoluteString))\n\($0.excerpt)"
        }.joined(separator: "\n\n")
        let attachments = request.attachments.map(\.promptExcerpt).joined(separator: "\n\n")

        return """
        CURRENT LOCAL DRAFT
        Name: \(request.intent.name)
        Platform: \(request.intent.platform.rawValue)
        Target group: \(request.intent.scope.deviceGroupName)
        Supervised: \(request.intent.devicesAreSupervised)
        Jamf School time filter: \(timeFilter)
        Configured restrictions: \(configured.isEmpty ? "none" : configured)
        Dock: \(request.intent.dockItems.map(\.displayName).joined(separator: ", "))
        Known Jamf device groups: \(groups.isEmpty ? "none loaded" : groups)

        RELEVANT VERIFIED BOOLEAN RESTRICTIONS
        \(catalogue.isEmpty ? "No exact restriction matched. Answer as practical Jamf School or Apple device-management guidance and use no edit." : catalogue)

        RECENT CONVERSATION
        \(recentConversation.isEmpty ? "none" : recentConversation)

        RELEVANT LOCAL JAMF SCHOOL DOCUMENTATION
        \(documentation.isEmpty ? "No local documentation excerpt matched this request." : documentation)

        LOCAL ATTACHMENTS
        \(attachments.isEmpty ? "No PDF or image is attached." : attachments)

        TECHNICIAN REQUEST
        \(request.prompt)
        """
    }

    private func decodeEnvelope(from output: String) throws -> QwenResponseEnvelope {
        let withoutThinking: String
        if let end = output.range(of: "</think>", options: .caseInsensitive) {
            withoutThinking = String(output[end.upperBound...])
        } else {
            withoutThinking = output
        }

        for candidate in jsonObjectCandidates(in: withoutThinking).reversed() {
            guard let data = candidate.data(using: .utf8) else { continue }
            if let envelope = try? JSONDecoder().decode(QwenResponseEnvelope.self, from: data) {
                return envelope
            }
        }
        throw QwenLocalModelError.invalidJSON
    }

    private func jsonObjectCandidates(in text: String) -> [String] {
        var candidates: [String] = []
        var depth = 0
        var start: String.Index?
        var isInsideString = false
        var isEscaped = false

        for index in text.indices {
            let character = text[index]
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
                continue
            }

            if character == "\"" {
                isInsideString = true
            } else if character == "{" {
                if depth == 0 { start = index }
                depth += 1
            } else if character == "}", depth > 0 {
                depth -= 1
                if depth == 0, let objectStart = start {
                    candidates.append(String(text[objectStart...index]))
                    start = nil
                }
            }
        }
        return candidates
    }

    private func verifiedResponse(
        from envelope: QwenResponseEnvelope,
        request: LocalModelRequest
    ) -> LocalModelResponse {
        let proposals = Array(envelope.edits.prefix(8))
        let edits = proposals.compactMap { proposal in
            proposal.intentEdit(jamfContext: request.jamfContext)
        }
        let rejectedCount = proposals.count - edits.count

        if !edits.isEmpty {
            var message = "Done — I’ve updated the verified local draft:\n• " + edits
                .map(\.verifiedDescription)
                .joined(separator: "\n• ")
            message += "\n\nNothing has been sent to Jamf School yet."
            if rejectedCount > 0 {
                message += "\n\nI ignored \(rejectedCount) unsupported or unverified proposal\(rejectedCount == 1 ? "" : "s")."
            }
            return LocalModelResponse(message: message, edits: edits)
        }

        if rejectedCount > 0 {
            let reply = envelope.reply.trimmingCharacters(in: .whitespacesAndNewlines)
            if !reply.isEmpty,
               !Self.appearsToClaimAnUnverifiedEdit(reply),
               !Self.appearsToBeInternalReasoning(reply) {
                return LocalModelResponse(
                    message: reply + "\n\nI kept the local draft unchanged because the proposed edit did not match a verified Apple setting or known Jamf device group.",
                    edits: []
                )
            }
            return LocalModelResponse(
                message: bestEffortClarification(for: request),
                edits: []
            )
        }

        let reply = envelope.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reply.isEmpty,
              !Self.appearsToClaimAnUnverifiedEdit(reply),
              !Self.appearsToBeInternalReasoning(reply) else {
            return LocalModelResponse(
                message: bestEffortClarification(for: request),
                edits: []
            )
        }
        return LocalModelResponse(message: reply, edits: [])
    }

    private func locked<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }

    private static let instructions = """
    You are the private, on-device reasoning layer for a macOS Apple device-management profile builder.
    Write like a warm, practical technical colleague: clear, calm and lightly conversational, never
    robotic or overly cheerful. Treat recognised standard English words as intentional. Correct only an
    unmistakable spelling mistake when sentence context leaves one clear meaning; never change “provide”
    to “profile” or “remotely” to “remote”. Mention a correction only when it changes your interpretation.
    In this app, "users", "students", "kids", "learners" and "pupils" mean the people using the iPads
    targeted by the local profile draft on the left. If they cannot access a feature, first check whether
    the current local draft disables that feature before suggesting Jamf School or device-side checks.
    When an exact current restriction is the blocker, return the verified edit that allows the feature
    in the local draft and explain both the local fix and any remaining Jamf School checks.
    Treat short requests such as “provide a how-to guide”, “show me how” and “give me the steps” as
    follow-ups to the most recent technician question in RECENT CONVERSATION. Answer that subject instead
    of trying to convert the follow-up wording into a profile edit.
    Answer the technician’s actual question first. You may explain, compare approaches, troubleshoot,
    provide detailed steps, recommend a best option and ask one focused follow-up question. Never say you
    do not understand merely because no verified edit matches. Infer the most likely intent from the full
    sentence and recent conversation. If more detail would materially change the answer, give the most
    useful likely answer first, state the assumption briefly, then ask for that detail.
    Return exactly one JSON object and no Markdown. Never reveal planning, chain-of-thought,
    hidden reasoning or phrases such as "the user wants" or "I need to". The object must use this schema:
    {"reply":"brief answer","edits":[{"kind":"set_restriction","restrictionKey":"exact catalogue key","value":true},{"kind":"add_dock_app","app":"Safari"},{"kind":"remove_dock_app","app":"Classroom"},{"kind":"rename_profile","name":"name"},{"kind":"set_target_group","name":"exact known group"}]}
    Put only the final technician-facing answer in reply. By default, keep it under 120 words and use no
    more than five bullets. Only give a longer procedure when the technician explicitly asks for a detailed
    guide or step-by-step instructions. Do not narrate how you analysed the request or repeat the prompt.

    Use only edit kinds shown above. For set_restriction, copy an exact key from the supplied catalogue and use the Boolean value whose meaning matches the request. Do not invent keys. Do not treat a request such as 'add Wi-Fi configuration' as an SSID. Wi-Fi is handled by a separate guided form, so use no edit and explain what information is needed if it is not already being handled. Never include or request a password in JSON. Never claim that Jamf School was changed, that devices were updated, or that an edit succeeded. Edits affect only the local draft and are independently validated.
    You are encouraged to give useful Jamf School, Apple School Manager and Apple device-management advice even when no supported local edit exists. For these questions, use an empty edits array and give practical options, suggested Jamf profile or payload types, consequences, and the one to five details you still need. For troubleshooting, distinguish evidence in the supplied local draft from checks that must happen on the device, in Jamf School or in Apple School Manager. Do not invent remote diagnostics or say a remote issue was repaired. Only propose a profile edit when an exact supplied catalogue setting directly and safely addresses a confirmed local cause. The verification boundary limits edits, not useful conversation.
    """

    private func bestEffortClarification(for request: LocalModelRequest) -> String {
        let relevant = RestrictionCatalogue.relevant(to: request.prompt).prefix(4)
        if !relevant.isEmpty {
            let options = relevant.map { definition in
                let state = request.intent.restrictions[definition.key] ?? .unchanged
                return "• \(definition.title): currently \(definition.label(for: state))"
            }.joined(separator: "\n")
            return "The closest verified settings are:\n\(options)\n\nI can explain the likely Jamf School solution or update one of these settings. Tell me the outcome you want students to experience, and whether this is a new configuration or a problem on devices already in use."
        }

        return "I can still help with this as a Jamf School or Apple device-management question. Tell me the result you want and whether you are planning a new setup or troubleshooting deployed devices; I’ll give you the most practical route and only change the local draft when an exact verified setting matches."
    }

    private func advisoryReply(from output: String) -> String? {
        let withoutThinking: String
        if let end = output.range(of: "</think>", options: .caseInsensitive) {
            withoutThinking = String(output[end.upperBound...])
        } else if output.range(of: "<think>", options: .caseInsensitive) != nil {
            return nil
        } else {
            withoutThinking = output
        }
        let cleaned = withoutThinking
            .replacingOccurrences(of: "```json", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.first == "{" {
            // Never show the technician an internal JSON envelope. Qwen can occasionally
            // omit the edits array, which makes the strict response decoder reject an
            // otherwise useful reply.
            if let envelope = try? JSONDecoder().decode(QwenAdvisoryEnvelope.self, from: Data(cleaned.utf8)),
               let reply = envelope.reply?.trimmingCharacters(in: .whitespacesAndNewlines),
               !reply.isEmpty,
               !Self.appearsToClaimAnUnverifiedEdit(reply),
               !Self.appearsToBeInternalReasoning(reply) {
                return String(reply.prefix(1_200))
            }
            return nil
        }
        guard cleaned.count >= 2,
              cleaned.count <= 1_600,
              !Self.appearsToClaimAnUnverifiedEdit(cleaned),
              !Self.appearsToBeInternalReasoning(cleaned) else { return nil }
        return String(cleaned.prefix(1_200))
    }

    private static func appearsToClaimAnUnverifiedEdit(_ reply: String) -> Bool {
        let text = reply.lowercased()
        return [
            "i applied", "i added", "i changed", "i updated", "i removed",
            "successfully added", "successfully updated", "was successfully"
        ].contains(where: text.contains)
    }

    private static func appearsToBeInternalReasoning(_ reply: String) -> Bool {
        let text = reply.lowercased()
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
        ].contains(where: text.contains)
    }
}

private struct QwenAdvisoryEnvelope: Decodable {
    let reply: String?
}

private struct QwenResponseEnvelope: Decodable {
    let reply: String
    let edits: [QwenProposedEdit]
}

private struct QwenProposedEdit: Decodable {
    let kind: String
    let restrictionKey: String?
    let value: Bool?
    let app: String?
    let name: String?

    func intentEdit(jamfContext: JamfReadContext) -> IntentEdit? {
        switch kind {
        case "set_restriction":
            guard let restrictionKey,
                  let value,
                  let key = RestrictionKey(rawValue: restrictionKey) else { return nil }
            return .setRestriction(key, value ? .allow : .deny)
        case "add_dock_app":
            guard let app = dockItem else { return nil }
            return .addDockItem(app)
        case "remove_dock_app":
            guard let app = dockItem else { return nil }
            return .removeDockItem(app)
        case "rename_profile":
            guard let name = cleanedName else { return nil }
            return .renameProfile(name)
        case "set_target_group":
            guard jamfContext.isConnected,
                  let requestedName = cleanedName,
                  let group = jamfContext.deviceGroups.first(where: {
                      $0.name.compare(
                          requestedName,
                          options: [.caseInsensitive, .diacriticInsensitive]
                      ) == .orderedSame
                  }) else { return nil }
            return .setScopeName(group.name)
        default:
            return nil
        }
    }

    private var dockItem: DockItem? {
        switch app?.lowercased() {
        case "safari": .safari
        case "classroom": .classroom
        default: nil
        }
    }

    private var cleanedName: String? {
        guard let name else { return nil }
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : String(cleaned.prefix(100))
    }
}

private final class ModelDownloadProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private let handler: @Sendable (ModelDownloadProgress) -> Void
    private var startedAt = Date()
    private var lastSampleAt = Date()
    private var lastSampleBytes: Int64 = 0
    private var smoothedBytesPerSecond: Double?
    private var lastReportedFraction = -1.0
    private var lastReportedAt = Date.distantPast

    init(handler: @Sendable @escaping (ModelDownloadProgress) -> Void) {
        self.handler = handler
    }

    func report(completedBytes: Int64, totalBytes: Int64?) {
        let safeCompleted = max(completedBytes, 0)
        let safeTotal = totalBytes.map { max($0, 0) }.flatMap { $0 > 0 ? $0 : nil }
        let fraction = safeTotal.map { min(max(Double(safeCompleted) / Double($0), 0), 1) } ?? 0
        let now = Date()

        lock.lock()
        let elapsed = now.timeIntervalSince(lastSampleAt)
        if elapsed >= 0.4, safeCompleted >= lastSampleBytes {
            let currentSpeed = Double(safeCompleted - lastSampleBytes) / elapsed
            if currentSpeed > 0 {
                smoothedBytesPerSecond = smoothedBytesPerSecond.map { ($0 * 0.7) + (currentSpeed * 0.3) } ?? currentSpeed
            }
            lastSampleAt = now
            lastSampleBytes = safeCompleted
        }
        let shouldReport = fraction > lastReportedFraction || now.timeIntervalSince(lastReportedAt) >= 1
        guard shouldReport else {
            lock.unlock()
            return
        }
        lastReportedFraction = fraction
        lastReportedAt = now
        let speed = smoothedBytesPerSecond
        let remaining: TimeInterval?
        if let total = safeTotal, let speed, speed > 0 {
            remaining = max(0, Double(total - safeCompleted) / speed)
        } else {
            remaining = nil
        }
        lock.unlock()

        handler(ModelDownloadProgress(
            fractionCompleted: fraction,
            completedBytes: safeTotal == nil ? nil : safeCompleted,
            totalBytes: safeTotal,
            bytesPerSecond: speed,
            estimatedSecondsRemaining: remaining
        ))
    }
}

private enum QwenLocalModelError: LocalizedError {
    case notLoaded
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .notLoaded: "The enhanced local model is not loaded."
        case .invalidJSON: "The enhanced local model returned an invalid structured response."
        }
    }
}

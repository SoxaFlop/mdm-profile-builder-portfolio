import AppKit
import Foundation

enum IntentEdit: Equatable {
    case setRestriction(RestrictionKey, RestrictionState)
    case addDockItem(DockItem)
    case removeDockItem(DockItem)
    case addWiFiPayload(WiFiPayloadIntent)
    case updateWiFiPayload(WiFiPayloadIntent)
    case removeWiFiPayload(UUID)
    case renameProfile(String)
    case setDevicesAreSupervised(Bool)
    case setScopeName(String)
    case configureJamfTimeFilter(JamfTimeFilter)
    case removeJamfTimeFilter

    var verifiedDescription: String {
        switch self {
        case .setRestriction(let key, let state):
            let definition = RestrictionCatalogue.definition(for: key)
            return "\(definition.title) → \(definition.label(for: state))"
        case .addDockItem(let item):
            return "Add \(item.displayName) to the Dock"
        case .removeDockItem(let item):
            return "Remove \(item.displayName) from the Dock"
        case .addWiFiPayload:
            return "Add a local Wi-Fi payload"
        case .updateWiFiPayload:
            return "Update the local Wi-Fi payload"
        case .removeWiFiPayload:
            return "Remove the local Wi-Fi payload"
        case .renameProfile(let name):
            return "Rename the profile to ‘\(name)’"
        case .setDevicesAreSupervised(let isSupervised):
            return isSupervised
                ? "Mark target iPads as supervised for validation"
                : "Mark target iPads as not supervised for validation"
        case .setScopeName(let name):
            return "Set the target group to ‘\(name)’"
        case .configureJamfTimeFilter(let filter):
            return "Set Jamf School time filter: \(filter.summary)"
        case .removeJamfTimeFilter:
            return "Remove the Jamf School time filter"
        }
    }
}

struct LocalModelRequest {
    let prompt: String
    let intent: ProfileIntent
    let validationIssues: [ValidationIssue]
    let jamfContext: JamfReadContext
    let recentMessages: [ChatMessage]
    let jamfKnowledgeSnippets: [JamfKnowledgeSnippet]
    let attachments: [AssistantAttachment]

    init(
        prompt: String,
        intent: ProfileIntent,
        validationIssues: [ValidationIssue],
        jamfContext: JamfReadContext = .empty,
        recentMessages: [ChatMessage] = [],
        jamfKnowledgeSnippets: [JamfKnowledgeSnippet] = [],
        attachments: [AssistantAttachment] = []
    ) {
        self.prompt = prompt
        self.intent = intent
        self.validationIssues = validationIssues
        self.jamfContext = jamfContext
        self.recentMessages = recentMessages
        self.jamfKnowledgeSnippets = jamfKnowledgeSnippets
        self.attachments = attachments
    }
}

struct LocalModelResponse {
    let message: String
    let edits: [IntentEdit]

    func acknowledging(_ interpretation: PromptInterpretation) -> LocalModelResponse {
        guard !interpretation.corrections.isEmpty else { return self }
        if !edits.isEmpty {
            let assumptions = interpretation.corrections.map {
                "‘\($0.original)’ as ‘\($0.replacement)’"
            }.joined(separator: ", ")
            return LocalModelResponse(
                message: "I read the full sentence as: ‘\(interpretation.correctedPrompt)’. That uses \(assumptions).\n\nBefore I change the profile, please confirm which meaning you intended. Reply ‘use this interpretation’ to continue, or restate the request if you meant something else.",
                edits: []
            )
        }
        let acknowledgement: String
        if interpretation.corrections.count == 1,
           let correction = interpretation.corrections.first {
            acknowledgement = "I read the full sentence with ‘\(correction.original)’ meaning ‘\(correction.replacement)’ and used that interpretation for this answer."
        } else {
            let assumptions = interpretation.corrections.map {
                "‘\($0.original)’ means ‘\($0.replacement)’"
            }.joined(separator: ", ")
            acknowledgement = "I read the full sentence using these likely corrections: \(assumptions)."
        }
        return LocalModelResponse(
            message: acknowledgement + "\n\n" + message,
            edits: edits
        )
    }
}

struct PromptInterpretation {
    struct Correction: Equatable {
        let original: String
        let replacement: String
    }

    let correctedPrompt: String
    let corrections: [Correction]

    static func interpret(_ prompt: String) -> PromptInterpretation {
        let source = prompt as NSString
        let lowercased = prompt.lowercased() as NSString
        let protectedStart = protectedValueStart(in: lowercased)
        let fullRange = NSRange(location: 0, length: source.length)
        let matches = wordExpression.matches(in: prompt, range: fullRange)
        let corrected = NSMutableString(string: prompt)
        var corrections: [Correction] = []

        for match in matches.reversed() {
            if let protectedStart, match.range.location >= protectedStart { continue }
            let original = source.substring(with: match.range)
            let word = original.lowercased()
            guard !vocabulary.contains(word),
                  !isRecognisedEnglishWord(word),
                  let replacement = closestKnownWord(to: word) else { continue }
            corrected.replaceCharacters(in: match.range, with: replacement)
            corrections.append(Correction(original: original, replacement: replacement))
        }

        return PromptInterpretation(
            correctedPrompt: corrected as String,
            corrections: corrections.reversed()
        )
    }

    private static let wordExpression = try! NSRegularExpression(pattern: #"[A-Za-z][A-Za-z]{3,}"#)

    private static let coreVocabulary: Set<String> = [
        "restriction", "restrictions", "restrict", "disabled", "disable", "disallow",
        "blocked", "block", "denied", "deny", "allowed", "allow", "enabled", "enable",
        "required", "require", "unchanged", "reset", "remove", "removed", "delete", "add",
        "profile", "profiles", "setting", "settings", "configured", "configuration", "configure",
        "camera", "screenshot", "screenshots", "recording", "airdrop", "appstore", "installation",
        "download", "downloads", "downloading", "install", "installs", "installing", "update", "updates",
        "updating", "access", "sign", "signin", "login", "working", "work",
        "account", "accounts", "modification", "wifi", "wireless", "network", "networks", "security",
        "password", "supervision", "supervised", "validation", "issue", "issues", "dock", "safari",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "weekdays",
        "classroom", "functionality", "summarise", "summarize", "explain", "describe",
        "provide", "guide", "steps", "remote", "remotely", "managed", "school", "student",
        "students", "learner", "learners", "question", "answer", "help", "please", "simple"
    ]

    private static let vocabulary: Set<String> = {
        let ignored: Set<String> = [
            "this", "that", "these", "those", "with", "from", "into", "when", "while", "being",
            "have", "will", "only", "using", "user", "users", "device", "devices", "system", "apple"
        ]
        var words = coreVocabulary
        for definition in RestrictionCatalogue.iPadOS {
            for phrase in [definition.title] + definition.searchTerms {
                let range = NSRange(location: 0, length: (phrase as NSString).length)
                for match in wordExpression.matches(in: phrase, range: range) {
                    let word = (phrase as NSString).substring(with: match.range).lowercased()
                    if !ignored.contains(word) { words.insert(word) }
                }
            }
        }
        return words
    }()

    private static func protectedValueStart(in prompt: NSString) -> Int? {
        let markers = [
            "ssid is ", "ssid: ", "network named ", "network called ",
            "rename profile to ", "name the profile ", "call the profile "
        ]
        return markers.compactMap { marker -> Int? in
            let range = prompt.range(of: marker)
            return range.location == NSNotFound ? nil : range.location + range.length
        }.min()
    }

    private static func closestKnownWord(to word: String) -> String? {
        guard word.count >= 5 else { return nil }
        // Keep correction deliberately conservative. A two-character edit turned valid
        // words such as “provide” and “remotely” into catalogue words such as “profile”
        // and “remote”. One edit still catches the useful cases (camra, disabel,
        // restryictions and tueadays) without rewriting normal technician language.
        let maximumDistance = 1
        var bestDistance = maximumDistance + 1
        var bestMatches: [String] = []

        for candidate in vocabulary where abs(candidate.count - word.count) <= maximumDistance {
            let distance = editDistance(word, candidate, limit: maximumDistance)
            if distance < bestDistance {
                bestDistance = distance
                bestMatches = [candidate]
            } else if distance == bestDistance {
                bestMatches.append(candidate)
            }
        }
        guard bestDistance <= maximumDistance, bestMatches.count == 1 else { return nil }
        return bestMatches[0]
    }

    private static func isRecognisedEnglishWord(_ word: String) -> Bool {
        let range = NSSpellChecker.shared.checkSpelling(
            of: word,
            startingAt: 0,
            language: "en_ZA",
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        return range.location == NSNotFound
    }

    private static func editDistance(_ lhs: String, _ rhs: String, limit: Int) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        if abs(left.count - right.count) > limit { return limit + 1 }

        var previousPrevious: [Int]?
        var previous = Array(0...right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1]
            var rowMinimum = current[0]
            for (rightIndex, rightCharacter) in right.enumerated() {
                let insertion = current[rightIndex] + 1
                let deletion = previous[rightIndex + 1] + 1
                let substitution = previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                var value = min(insertion, deletion, substitution)
                if leftIndex > 0,
                   rightIndex > 0,
                   leftCharacter == right[rightIndex - 1],
                   left[leftIndex - 1] == rightCharacter,
                   let previousPrevious {
                    value = min(value, previousPrevious[rightIndex - 1] + 1)
                }
                current.append(value)
                rowMinimum = min(rowMinimum, value)
            }
            if rowMinimum > limit { return limit + 1 }
            previousPrevious = previous
            previous = current
        }
        return previous[right.count]
    }
}

protocol LocalModelServing {
    var displayName: String { get }
    var isGenerativeModelLoaded: Bool { get }
    var statusDetail: String { get }
    func respond(to request: LocalModelRequest) async -> LocalModelResponse
}

struct ModelDownloadProgress: Equatable, Sendable {
    let fractionCompleted: Double
    let completedBytes: Int64?
    let totalBytes: Int64?
    let bytesPerSecond: Double?
    let estimatedSecondsRemaining: TimeInterval?

    static let starting = ModelDownloadProgress(
        fractionCompleted: 0,
        completedBytes: nil,
        totalBytes: nil,
        bytesPerSecond: nil,
        estimatedSecondsRemaining: nil
    )
}

protocol EnhancedLocalModelServing: LocalModelServing {
    var isEnhancedModelLoaded: Bool { get }
    var enhancedModelName: String { get }
    var enhancedModelDownloadDescription: String { get }
    func prepareEnhancedModel(
        progressHandler: @Sendable @escaping (ModelDownloadProgress) -> Void
    ) async throws
}

/// A deliberately small, transparent offline implementation.
///
/// It remains available when Apple's on-device Foundation Model is unavailable,
/// without downloading a model or calling a paid API. Another local runtime can
/// conform to `LocalModelServing` without changing the views or compiler.
struct PlaceholderLocalModelService: LocalModelServing {
    let displayName = "Offline command interpreter"
    let isGenerativeModelLoaded = false
    let statusDetail = "Deterministic fallback ready"

    func respond(to request: LocalModelRequest) async -> LocalModelResponse {
        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let interpretation = PromptInterpretation.interpret(prompt)
        let interpretedPrompt = interpretation.correctedPrompt
        let lowercased = interpretedPrompt.lowercased()
        guard !lowercased.isEmpty else {
            return LocalModelResponse(message: "Enter a question or requested change.", edits: [])
        }

        if let response = confirmedSpellingInterpretationResponse(for: request, prompt: lowercased) {
            return response
        }

        if let response = profileStateResponse(for: request, prompt: lowercased) {
            return response.acknowledging(interpretation)
        }

        if let response = followUpGuidanceResponse(for: request, prompt: lowercased) {
            return response.acknowledging(interpretation)
        }

        if let response = confirmedTroubleshootingEditResponse(for: request, prompt: lowercased) {
            return response.acknowledging(interpretation)
        }

        if let response = jamfSoftwareUpdateResponse(prompt: lowercased) {
            return response.acknowledging(interpretation)
        }

        if let response = profileBuildResponse(for: request, prompt: lowercased) {
            return response.acknowledging(interpretation)
        }

        if let response = profileEditResponse(for: request, prompt: lowercased) {
            return response.acknowledging(interpretation)
        }

        if let response = troubleshootingResponse(for: request, prompt: lowercased) {
            return response.acknowledging(interpretation)
        }

        if let response = wifiResponse(for: request, prompt: interpretedPrompt, lowercased: lowercased) {
            return response.acknowledging(interpretation)
        }

        if isValidationQuestion(lowercased) {
            return validationResponse(request.validationIssues).acknowledging(interpretation)
        }

        if lowercased.contains("supervision") {
            return LocalModelResponse(
                message: "AirDrop, App Store/app installation and account-modification controls require supervision on current iPadOS. The app validates those requirements before export.",
                edits: []
            ).acknowledging(interpretation)
        }

        return LocalModelResponse(
            message: openEndedFallbackMessage(for: request, prompt: lowercased),
            edits: []
        ).acknowledging(interpretation)
    }

    func deterministicResponseIfHandled(to request: LocalModelRequest) -> LocalModelResponse? {
        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let interpretation = PromptInterpretation.interpret(prompt)
        let interpretedPrompt = interpretation.correctedPrompt
        let lowercased = interpretedPrompt.lowercased()
        if let response = confirmedSpellingInterpretationResponse(for: request, prompt: lowercased) {
            return response
        }
        if let response = profileStateResponse(for: request, prompt: lowercased) {
            return response.acknowledging(interpretation)
        }
        if let response = followUpGuidanceResponse(for: request, prompt: lowercased) {
            return response.acknowledging(interpretation)
        }
        if let response = confirmedTroubleshootingEditResponse(for: request, prompt: lowercased) {
            return response.acknowledging(interpretation)
        }
        if let response = jamfSoftwareUpdateResponse(prompt: lowercased) {
            return response.acknowledging(interpretation)
        }
        if let response = profileBuildResponse(for: request, prompt: lowercased) {
            return response.acknowledging(interpretation)
        }
        if let response = profileEditResponse(for: request, prompt: lowercased) {
            return response.acknowledging(interpretation)
        }
        if let response = troubleshootingResponse(for: request, prompt: lowercased),
           !response.edits.isEmpty {
            return response.acknowledging(interpretation)
        }
        if isValidationQuestion(lowercased) {
            return validationResponse(request.validationIssues).acknowledging(interpretation)
        }
        return wifiResponse(for: request, prompt: interpretedPrompt, lowercased: lowercased)?
            .acknowledging(interpretation)
    }

    private func openEndedFallbackMessage(
        for request: LocalModelRequest,
        prompt: String
    ) -> String {
        let relevant = RestrictionCatalogue.relevant(to: prompt).prefix(4)
        if !relevant.isEmpty {
            let settings = relevant.map { definition -> String in
                let state = request.intent.restrictions[definition.key] ?? .unchanged
                return "• \(definition.title) is currently \(definition.label(for: state)). \(definition.summary.replacingOccurrences(of: "`", with: ""))"
            }.joined(separator: "\n")
            return "This looks related to these verified iPad settings:\n\(settings)\n\nTell me the outcome you want for students, or whether you are reporting a problem already happening on deployed iPads. I’ll then recommend the most likely fix and change any exact matching setting in the local draft."
        }

        if let snippet = request.jamfKnowledgeSnippets.first {
            return "The closest local Jamf School guidance is from ‘\(snippet.title)’:\n\n\(String(snippet.excerpt.prefix(1_200)))\n\nTell me whether you want setup steps, troubleshooting checks or a profile recommendation and I’ll turn this into a practical plan."
        }

        return "Let’s work out the best approach. Tell me the result you want on the students’ iPads and whether this is a new configuration or a problem already happening on deployed devices. I can then recommend the Jamf School workflow, troubleshoot likely causes and apply any exact verified profile settings to the local draft."
    }

    private func isValidationQuestion(_ prompt: String) -> Bool {
        prompt.contains("validation") ||
            prompt.contains("what is wrong") ||
            prompt.contains("what are the errors") ||
            prompt.contains("validation errors")
    }

    private func referencedRestrictionMatches(in prompt: String) -> [(Int, RestrictionDefinition)] {
        RestrictionCatalogue.iPadOS.compactMap { definition -> (Int, RestrictionDefinition)? in
            let positions = definition.searchTerms.compactMap { term -> Int? in
                guard let range = prompt.range(of: term) else { return nil }
                return prompt.distance(from: prompt.startIndex, to: range.lowerBound)
            }
            guard let firstPosition = positions.min() else { return nil }
            return (firstPosition, definition)
        }.sorted { $0.0 < $1.0 }
    }

    private func profileEditResponse(
        for request: LocalModelRequest,
        prompt: String
    ) -> LocalModelResponse? {
        var edits: [IntentEdit] = []
        var changedLabels: [String] = []

        for (_, definition) in referencedRestrictionMatches(in: prompt) {
            guard let requestedState = stateRequested(for: definition, in: prompt) else {
                continue
            }
            edits.append(.setRestriction(definition.key, requestedState))
            changedLabels.append("\(definition.title) → \(definition.label(for: requestedState))")
        }

        let asksToRemove = prompt.contains("remove") || prompt.contains("take")
        if prompt.contains("dock") {
            for item in [DockItem.classroom, .safari]
            where prompt.contains(item.displayName.lowercased()) {
                if asksToRemove {
                    edits.append(.removeDockItem(item))
                    changedLabels.append("Remove \(item.displayName) from Dock")
                } else if prompt.contains("add") ||
                            prompt.contains("put") ||
                            prompt.contains("include") {
                    edits.append(.addDockItem(item))
                    changedLabels.append("Add \(item.displayName) to Dock")
                }
            }
        }

        guard !edits.isEmpty else { return nil }
        return LocalModelResponse(
            message: "Done — I’ve updated the local draft:\n• " + changedLabels.joined(separator: "\n• ") + "\n\nNothing has been sent to Jamf School yet.",
            edits: edits
        )
    }

    private func followUpGuidanceResponse(
        for request: LocalModelRequest,
        prompt: String
    ) -> LocalModelResponse? {
        let asksForSteps = [
            "provide a how to guide", "provide a how-to guide", "give me a how to guide",
            "give me a how-to guide", "provide a guide", "give me the steps", "show me the steps",
            "provide troubleshooting steps", "give me troubleshooting steps", "troubleshooting steps",
            "walk me through", "show me how", "how do i do that", "how can i do that",
            "how can i troubleshoot"
        ].contains(where: prompt.contains)
        guard asksForSteps,
              let previousPrompt = previousTechnicianPrompt(in: request)?.lowercased() else {
            return nil
        }

        if isJamfSoftwareUpdateQuestion(previousPrompt) {
            return jamfSoftwareUpdateGuide()
        }
        if isAppleAccountSignInIssue(previousPrompt) {
            return appleAccountTroubleshootingGuide(for: request)
        }
        return nil
    }

    private func previousTechnicianPrompt(in request: LocalModelRequest) -> String? {
        var prompts = request.recentMessages
            .filter { $0.role == .technician }
            .map(\.text)
        if let last = prompts.last,
           last.trimmingCharacters(in: .whitespacesAndNewlines)
            .compare(
                request.prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame {
            prompts.removeLast()
        }
        return prompts.last
    }

    private func previousAssistantMessage(in request: LocalModelRequest) -> String? {
        request.recentMessages
            .filter { $0.role == .assistant }
            .map(\.text)
            .last
    }

    private func confirmedTroubleshootingEditResponse(
        for request: LocalModelRequest,
        prompt: String
    ) -> LocalModelResponse? {
        let confirmsFix = [
            "apply the profile fix", "yes, apply the profile fix", "yes apply the profile fix"
        ].contains(where: prompt.contains)
        guard confirmsFix,
              let previous = previousAssistantMessage(in: request),
              previous.lowercased().contains("reply ‘apply the profile fix’") else {
            return nil
        }

        guard let definition = RestrictionCatalogue.iPadOS.first(where: {
            previous.localizedCaseInsensitiveContains($0.title)
        }) else {
            return LocalModelResponse(
                message: "I have your confirmation, but I can’t identify one exact verified setting from the previous answer. Tell me the feature name and I’ll show you the matching change before applying it.",
                edits: []
            )
        }

        return LocalModelResponse(
            message: "Confirmed — I’ve changed \(definition.title) to \(definition.label(for: .allow)) in the local draft. Nothing has been sent to Jamf School yet. Check for another assigned profile with the opposite setting before deployment.",
            edits: [.setRestriction(definition.key, .allow)]
        )
    }

    private func confirmedSpellingInterpretationResponse(
        for request: LocalModelRequest,
        prompt: String
    ) -> LocalModelResponse? {
        let confirmsInterpretation = [
            "use this interpretation", "yes, use this interpretation", "yes use this interpretation"
        ].contains(where: prompt.contains)
        guard confirmsInterpretation,
              previousAssistantMessage(in: request)?.lowercased().contains("reply ‘use this interpretation’") == true,
              let originalPrompt = previousTechnicianPrompt(in: request) else {
            return nil
        }

        let interpretation = PromptInterpretation.interpret(originalPrompt)
        guard !interpretation.corrections.isEmpty else { return nil }
        let correctedRequest = LocalModelRequest(
            prompt: interpretation.correctedPrompt,
            intent: request.intent,
            validationIssues: request.validationIssues,
            jamfContext: request.jamfContext,
            recentMessages: request.recentMessages,
            jamfKnowledgeSnippets: request.jamfKnowledgeSnippets,
            attachments: request.attachments
        )
        guard let planned = deterministicResponseIfHandled(to: correctedRequest) else {
            return LocalModelResponse(
                message: "Thanks, I’ve confirmed that interpretation. Tell me whether you want guidance only or a change to the local profile, and I’ll continue from the corrected request.",
                edits: []
            )
        }
        return LocalModelResponse(
            message: "Confirmed — I used the corrected full-sentence interpretation.\n\n" + planned.message,
            edits: planned.edits
        )
    }

    private func jamfSoftwareUpdateResponse(prompt: String) -> LocalModelResponse? {
        guard isJamfSoftwareUpdateQuestion(prompt) else { return nil }
        return LocalModelResponse(
            message: "Yes. Jamf School can remotely download or install iOS and iPadOS updates on eligible managed iPads. The iPads must be supervised or enrolled through Automated Device Enrolment, have a valid push connection, be online and report the update as available.\n\nFor a once-off update, use Devices › Updates. For deadline-based update enforcement on iPadOS 17 or later, Jamf recommends a Software Updates component in a blueprint. A restrictions payload can delay updates, but it does not send the update command itself.\n\nIf you want the exact clicks and checks, ask me for the step-by-step guide.",
            edits: []
        )
    }

    private func isJamfSoftwareUpdateQuestion(_ prompt: String) -> Bool {
        let mentionsUpdate = [
            "ios update", "ios updates", "ipados update", "ipados updates",
            "os update", "os updates", "software update", "software updates",
            "update managed ipad", "update managed ipads"
        ].contains(where: prompt.contains)
        let mentionsManagedContext = [
            "jamf", "managed ipad", "managed ipads", "remotely", "remote", "mdm"
        ].contains(where: prompt.contains)
        return mentionsUpdate && mentionsManagedContext
    }

    private func jamfSoftwareUpdateGuide() -> LocalModelResponse {
        LocalModelResponse(
            message: "Here’s the Jamf School how-to guide for managed iPad updates.\n\nBefore you start\n• Confirm the iPads are supervised or enrolled through Automated Device Enrolment and that the Jamf push certificate is valid.\n• Make sure the devices are online, have enough free storage and are connected to power where practical. For Shared iPad, log users out first; Jamf also requires more than 50% battery for that workflow.\n\nOnce-off or group update\n1. In Jamf School, go to Devices › Updates.\n2. If Updates is missing, go to Organisation › Settings and enable “Allow Jamf School to check for OS updates (supervised only)”, then refresh device inventory.\n3. Filter to the required device group and select the relevant OS-version tab.\n4. Select the iPads.\n5. From Update, choose Download to stage the update or Install to download and start the installation workflow.\n6. Review the device activity and inventory afterwards to confirm the command and resulting OS version. Avoid clearing passcodes unless there is a specific, approved reason, because doing so weakens device security and removes passcode-protected items.\n\nDeadline-based enforcement with blueprints\n1. Open Blueprints and create a clearly named blueprint.\n2. Add the Software Updates component. The Software Update Settings component only configures behaviour; it does not trigger an update by itself.\n3. Choose the enforcement type, target OS version and deadline.\n4. Scope it to a pilot device group first, save, then deploy.\n5. After check-in, devices may begin downloading immediately, so stagger large groups to protect the school network.\n\nNothing in the local profile draft has been changed because sending an OS update is a Jamf School device-management action, not an Apple restrictions edit.",
            edits: []
        )
    }

    private func troubleshootingResponse(
        for request: LocalModelRequest,
        prompt: String
    ) -> LocalModelResponse? {
        if let response = studentAccessIssueResponse(for: request, prompt: prompt) {
            return response
        }

        if isAppleAccountSignInIssue(prompt) {
            return appleAccountSignInResponse(for: request, prompt: prompt)
        }

        if isComposerPerformanceIssue(prompt) {
            return LocalModelResponse(
                message: "That sounds like the message composer is being slowed down by the rest of the builder redrawing while you type. The composer now keeps its draft text separate from the profile workspace, so typing should remain responsive even with the full restrictions catalogue open. Stop and run the latest Xcode build; if it still lags, tell me whether it happens only after the local model is loaded and I’ll narrow it down.",
                edits: []
            )
        }

        if let response = timeFilterEditResponse(for: request, prompt: prompt) {
            return response
        }

        if isTimedDeviceAccessRequest(prompt) {
            return timedDeviceAccessResponse()
        }

        if isScheduleConfigurationQuestion(prompt), request.intent.jamfTimeFilter != nil {
            return timeFilterConfigurationInstructions(for: request)
        }

        if isJamfProfileIssue(prompt) {
            return jamfProfileTroubleshootingResponse(for: request)
        }

        if isApplicationIssue(prompt) {
            return LocalModelResponse(
                message: "I can help troubleshoot the app, but I need one concrete symptom: what you clicked, what you expected, and the exact message or result you saw. I can check the local draft, validation, model state and Jamf connection state here; I won’t pretend to have repaired something on the Mac or in Jamf School until it is confirmed.",
                edits: []
            )
        }

        return nil
    }

    private func studentAccessIssueResponse(
        for request: LocalModelRequest,
        prompt: String
    ) -> LocalModelResponse? {
        let mentionsProfileUser = [
            "student", "students", "learner", "learners", "kids", "children",
            "user", "users", "pupil", "pupils"
        ].contains(where: prompt.contains)
        let reportsAccessProblem = [
            "can't access", "cant access", "cannot access", "can not access",
            "can't use", "cant use", "cannot use", "can not use",
            "can't open", "cant open", "cannot open", "can not open",
            "can't download", "cant download", "cannot download", "can not download",
            "can't install", "cant install", "cannot install", "can not install",
            "can't update", "cant update", "cannot update", "can not update",
            "can't sign", "cant sign", "cannot sign", "can not sign",
            "blocked from", "no access to", "unable to access", "unable to use",
            "unable to download", "unable to install", "unable to update",
            "isn't working", "isnt working", "doesn't work", "doesnt work",
            "not available", "is missing", "has disappeared", "is greyed out"
        ].contains(where: prompt.contains)
        let reportsGeneralInability = [
            "can't", "cant", "cannot", "can not", "unable"
        ].contains(where: prompt.contains)
        guard mentionsProfileUser && (reportsAccessProblem || reportsGeneralInability),
              let definition = referencedRestrictionMatches(in: prompt).first?.1 else {
            return nil
        }

        let currentState = request.intent.restrictions[definition.key] ?? .unchanged
        if currentState == .deny {
            if asksForExplanation(prompt) {
                return LocalModelResponse(
                    message: "The most likely cause visible in this local draft is \(definition.title): it is currently set to \(definition.label(for: .deny)), which can stop students from using that feature. Another assigned Jamf School profile could also enforce the same restriction.\n\nDo you want me to change this local setting to \(definition.label(for: .allow)), or would you prefer troubleshooting steps only? Reply ‘apply the profile fix’ to confirm the draft change.",
                    edits: []
                )
            }
            return LocalModelResponse(
                message: "I found and fixed the likely blocker in this local draft: \(definition.title) was disabled, so students receiving this profile could not use it. I’ve changed it to \(definition.label(for: .allow)).\n\nThis is a reversible local draft change and nothing has been sent to Jamf School yet. Before deployment, check whether another assigned Jamf School profile also disables the same feature.",
                edits: [.setRestriction(definition.key, .allow)]
            )
        }

        if currentState == .allow {
            return LocalModelResponse(
                message: "This local draft already allows \(definition.title), so it is probably not the profile setting blocking students. Next checks: confirm the affected iPad is in the intended Jamf School device group, check for another assigned restrictions profile, then check app, network or account availability on the device.",
                edits: []
            )
        }

        return LocalModelResponse(
            message: "This local draft leaves \(definition.title) unchanged, so it does not itself block students from using it. If the goal is to explicitly allow it in this profile, say ‘allow \(definition.title) for students’. If the problem is already happening on devices, check Jamf School for another profile with \(definition.title) disabled.",
            edits: []
        )
    }

    private func isAppleAccountSignInIssue(_ prompt: String) -> Bool {
        let mentionsAccount = ["apple account", "apple id", "icloud account", "managed apple account"]
            .contains(where: prompt.contains)
        let mentionsSignIn = ["sign in", "sign-in", "signin", "log in", "login", "can't sign", "cant sign", "cannot sign"]
            .contains(where: prompt.contains)
        return mentionsAccount && mentionsSignIn
    }

    private func appleAccountSignInResponse(
        for request: LocalModelRequest,
        prompt: String
    ) -> LocalModelResponse {
        let accountState = request.intent.restrictions[.accountModification] ?? .unchanged
        if accountState == .deny {
            if asksForExplanation(prompt) {
                return LocalModelResponse(
                    message: "The most likely cause visible in this local draft is Account modification: it is set to Disable, which prevents students from configuring or signing in to an Apple Account. Other possible causes are another assigned restrictions profile, a disabled or incorrect Managed Apple Account, the Shared iPad sign-in method, network access, or incorrect date and time.\n\nDo you want me to set Account modification to Allow in this local draft, or provide troubleshooting steps only? Reply ‘apply the profile fix’ to confirm the draft change.",
                    edits: []
                )
            }
            return LocalModelResponse(
                message: "I found and fixed the likely blocker in this local draft: Account modification was disabled, so students could not configure or sign in to an Apple Account. It is now set to Allow.\n\nThis is a reversible local draft change and nothing has been sent to Jamf School yet. Before deployment, also check that another restrictions profile is not disabling the same setting and that the Managed Apple Account is active in Apple School Manager.",
                edits: [.setRestriction(.accountModification, .allow)]
            )
        }

        let localStatus: String
        switch accountState {
        case .allow:
            localStatus = "This local draft explicitly allows Account modification, so it is unlikely to be the blocker."
        case .unchanged:
            localStatus = "This local draft leaves Account modification unchanged, so it does not itself block Apple Account sign-in."
        case .deny:
            localStatus = ""
        }
        let connectionStep = request.jamfContext.isConnected
            ? "On an affected iPad, check Managed Profiles and the Jamf School activity log for another profile that disables Account modification."
            : "Connect and sync Jamf School first, then check the profiles assigned to an affected device for Account modification being disabled."
        return LocalModelResponse(
            message: "Let’s work through this safely. \(localStatus)\n\nCheck these next:\n• \(connectionStep)\n• If a Safelist and Blocklist profile is used, enable iCloud and Google account sign-ins there.\n• Confirm the student’s Apple Account or Managed Apple Account credentials, and use the correct sign-in flow for Shared iPad if applicable.\n• Confirm the iPad has a working network connection and automatic date and time.\n\nI can safely change a confirmed restriction in this local draft, but I won’t claim that a remote Jamf profile or Apple Account problem is fixed until it is verified.",
            edits: []
        )
    }

    private func appleAccountTroubleshootingGuide(
        for request: LocalModelRequest
    ) -> LocalModelResponse {
        let accountState = request.intent.restrictions[.accountModification] ?? .unchanged
        let firstCheck: String
        switch accountState {
        case .deny:
            firstCheck = "The local draft currently disables Account modification, which is the first likely blocker. Reply ‘apply the profile fix’ if you want me to set it to Allow locally."
        case .allow:
            firstCheck = "The local draft already allows Account modification, so check other assigned profiles next."
        case .unchanged:
            firstCheck = "The local draft leaves Account modification unchanged, so check whether another assigned profile disables it."
        }

        return LocalModelResponse(
            message: "\(firstCheck)\n\nTroubleshooting order:\n1. In Jamf School, open an affected iPad and review every assigned restrictions profile for Account modification conflicts.\n2. In Apple School Manager, confirm the Managed Apple Account is active and the username or domain is correct.\n3. Confirm the sign-in method matches the deployment: Shared iPad Managed Apple Account sign-in differs from a one-to-one iPad.\n4. Check internet access, Apple service reachability and automatic date and time.\n5. Test any profile change on one pilot iPad, force a check-in, then verify sign-in before wider deployment.\n\nNothing has been sent to Jamf School.",
            edits: []
        )
    }

    private func asksForExplanation(_ prompt: String) -> Bool {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix("?") || [
            "why ", "why are", "why can't", "why cant", "how come",
            "what is causing", "what causes", "can you explain", "explain why"
        ].contains(where: prompt.contains)
    }

    private func isComposerPerformanceIssue(_ prompt: String) -> Bool {
        let mentionsInput = ["prompt bar", "text bar", "text field", "typing", "type in", "input field"]
            .contains(where: prompt.contains)
        let mentionsPerformance = ["slow", "delay", "delayed", "lag", "laggy", "freez", "unresponsive"]
            .contains(where: prompt.contains)
        return mentionsInput && mentionsPerformance
    }

    private func isJamfProfileIssue(_ prompt: String) -> Bool {
        let mentionsJamf = prompt.contains("jamf") || prompt.contains("managed profile") || prompt.contains("profile")
        let mentionsProblem = ["not apply", "isn't applying", "isnt applying", "not install", "failed", "failure", "troubleshoot", "not working", "problem"]
            .contains(where: prompt.contains)
        return mentionsJamf && mentionsProblem
    }

    private func isTimedDeviceAccessRequest(_ prompt: String) -> Bool {
        let mentionsSchedule = [
            "time lock", "time-lock", "end of the school day", "after school",
            "after-school", "every school day", "every weekday", "at the end of"
        ].contains(where: prompt.contains)
        let mentionsDeviceControl = ["lock", "restrict", "devices", "ipads", "students"]
            .contains(where: prompt.contains)
        return mentionsSchedule && mentionsDeviceControl
    }

    private func isScheduleConfigurationQuestion(_ prompt: String) -> Bool {
        let asksHow = ["how do i", "how to", "where do i", "help me configure", "set this up"]
            .contains(where: prompt.contains)
        let scheduleContext = ["that", "this", "schedule", "time filter", "jamf", "profile"]
            .contains(where: prompt.contains)
        return asksHow && scheduleContext
    }

    private func timeFilterConfigurationInstructions(for request: LocalModelRequest) -> LocalModelResponse {
        guard let filter = request.intent.jamfTimeFilter else {
            return LocalModelResponse(message: "Choose the schedule first, then I can give you the matching Jamf School steps.", edits: [])
        }
        let target = request.intent.scope.deviceGroupName.isEmpty
            ? "select the correct student device group"
            : "confirm the target group is ‘\(request.intent.scope.deviceGroupName)’"
        return LocalModelResponse(
            message: "Set the same schedule in Jamf School like this:\n1. In Jamf School, open the profile you want to schedule, or create a separate profile if this is only needed at certain times.\n2. Open its General settings and enable the time filter.\n3. Select \(JamfWeekday.allCases.filter(filter.activeDays.contains).map(\.title).joined(separator: ", ")).\n4. Set the active time to \(filter.isActiveAllDay ? "all day" : "\(filter.startTime.displayName) to \(filter.endTime.displayName)").\n5. Set the holiday behaviour to \(filter.disableOnConfiguredHolidays ? "disable the profile on Jamf School holidays" : "leave the profile active on Jamf School holidays").\n6. Choose automatic installation, then \(target).\n7. Save it and test with one supervised iPad first. The iPad must check in after the start time before Jamf can apply the change.\n\nYour local draft already records: \(filter.summary). Nothing has been sent to Jamf School yet.",
            edits: []
        )
    }

    private func timeFilterEditResponse(
        for request: LocalModelRequest,
        prompt: String
    ) -> LocalModelResponse? {
        let requestedDays = parsedTimeFilterDays(from: prompt)
        let refersToSchedule = ["time filter", "schedule", "school day", "weekdays", "holidays"]
            .contains(where: prompt.contains) ||
            (request.intent.jamfTimeFilter != nil && requestedDays != nil)
        guard refersToSchedule else { return nil }

        if ["remove", "clear", "disable"].contains(where: prompt.contains),
           request.intent.jamfTimeFilter != nil {
            return LocalModelResponse(
                message: "I removed the Jamf School time filter from this local draft. The underlying Apple restrictions remain unchanged.",
                edits: [.removeJamfTimeFilter]
            )
        }

        let requestedTimes = parsedTimeFilterTimes(from: prompt)
        let discussesHolidays = prompt.contains("holiday")
        let makesHolidayException = ["disable on holiday", "not during holiday", "exclude holiday", "skip holiday"]
            .contains(where: prompt.contains)
        let enablesOnHolidays = ["enable on holiday", "include holiday", "during holidays"]
            .contains(where: prompt.contains)
        guard requestedDays != nil || requestedTimes != nil || discussesHolidays else { return nil }

        var filter = request.intent.jamfTimeFilter ?? .afterSchoolWeekdays
        let addsDays = request.intent.jamfTimeFilter != nil && ["add", "also", "include", "plus"]
            .contains(where: prompt.contains) ||
            (request.intent.jamfTimeFilter != nil && prompt.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("and "))
        if let requestedDays {
            filter.activeDays = addsDays
                ? filter.activeDays.union(requestedDays)
                : requestedDays
        }
        if let requestedTimes {
            filter.startTime = requestedTimes.start
            filter.endTime = requestedTimes.end
            filter.isActiveAllDay = false
        }
        if makesHolidayException { filter.disableOnConfiguredHolidays = true }
        if enablesOnHolidays { filter.disableOnConfiguredHolidays = false }

        let action = addsDays && requestedDays != nil ? "I added those day(s) to" : "I updated"
        return LocalModelResponse(
            message: "\(action) the local Jamf School schedule: \(filter.summary). This schedule is shown in the preview, but it is not embedded in the Apple mobileconfig file. Review it, then set the matching time filter in Jamf School’s General profile settings.",
            edits: [.configureJamfTimeFilter(filter)]
        )
    }

    private func parsedTimeFilterDays(from prompt: String) -> Set<JamfWeekday>? {
        if ["monday to friday", "mon to fri", "mon-fri", "weekdays", "school days"].contains(where: prompt.contains) {
            return [.monday, .tuesday, .wednesday, .thursday, .friday]
        }
        if prompt.contains("weekend") {
            return [.saturday, .sunday]
        }
        let weekdayAliases: [JamfWeekday: [String]] = [
            .monday: ["monday", "mondays", "mon"],
            .tuesday: ["tuesday", "tuesdays", "tue", "tues", "tuseday", "tueseday", "tuesady"],
            .wednesday: ["wednesday", "wednesdays", "wed", "wensday", "wednsday"],
            .thursday: ["thursday", "thursdays", "thu", "thur", "thurs", "thurday"],
            .friday: ["friday", "fridays", "fri"],
            .saturday: ["saturday", "saturdays", "sat"],
            .sunday: ["sunday", "sundays", "sun"]
        ]
        let selected = Set(JamfWeekday.allCases.filter { day in
            (weekdayAliases[day] ?? []).contains(where: prompt.contains)
        })
        return selected.isEmpty ? nil : selected
    }

    private func parsedTimeFilterTimes(from prompt: String) -> (start: JamfTimeOfDay, end: JamfTimeOfDay)? {
        let expression = try! NSRegularExpression(pattern: #"\b([01]?\d|2[0-3]):([0-5]\d)\b"#)
        let range = NSRange(location: 0, length: (prompt as NSString).length)
        let matches = expression.matches(in: prompt, range: range)
        guard matches.count >= 2,
              let startHour = Int((prompt as NSString).substring(with: matches[0].range(at: 1))),
              let startMinute = Int((prompt as NSString).substring(with: matches[0].range(at: 2))),
              let endHour = Int((prompt as NSString).substring(with: matches[1].range(at: 1))),
              let endMinute = Int((prompt as NSString).substring(with: matches[1].range(at: 2))) else {
            return nil
        }
        return (JamfTimeOfDay(hour: startHour, minute: startMinute), JamfTimeOfDay(hour: endHour, minute: endMinute))
    }

    private func timedDeviceAccessResponse() -> LocalModelResponse {
        LocalModelResponse(
            message: "Yes — Jamf School’s time filter is normally the right starting point for this. It makes a profile active only during the selected days and time range, so you can create an after-school profile without manually switching it every day.\n\nFirst, choose the outcome:\n• Recommended: restrict the iPads after school to a small approved app list, using a time-filtered Safelist and Blocklist or Layout profile.\n• Different and higher-risk: remotely lock every iPad with a passcode. I would not schedule that blindly because staff can be locked out and recovery becomes harder.\n\nSuggested Jamf School setup:\n1. Create a separate ‘After-school iPad access’ profile for the student device group.\n2. In General, enable Use time filter, choose the school days, set the after-school start and end time, and exclude holidays if needed.\n3. Use automatic installation.\n4. Add only the restrictions or allowed apps required after school. Keep Wi-Fi in its own profile so the iPads remain manageable.\n\nImportant: Jamf queues the profile at the start time, and an iPad must check in before it receives the change. Pilot the schedule with a small group before relying on it.\n\nBefore I turn this into a precise recommendation, tell me: (1) do you mean restricted apps or an actual passcode lock, (2) the days and exact start/end times, (3) which apps should still work, (4) the target device group, and (5) whether holidays should be excluded.\n\nThis app does not yet compile Jamf time filters or Safelist and Blocklist profiles, so I have not changed the local draft.",
            edits: []
        )
    }

    private func jamfProfileTroubleshootingResponse(for request: LocalModelRequest) -> LocalModelResponse {
        let scope = request.intent.scope.deviceGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        let scopeStep = scope.isEmpty
            ? "Sync device groups and select the exact target group, then verify that an affected iPad is actually a member."
            : "This local draft targets ‘\(scope)’. Verify that an affected iPad is a member of that group."
        let connectionStep = request.jamfContext.isConnected
            ? "Open the affected device in Jamf School and review its Managed Profiles and activity history for the specific install or removal failure."
            : "Connect and sync Jamf School first, then open the affected device to review its Managed Profiles and activity history for the specific failure."
        let validationStep = request.validationIssues.isEmpty
            ? "The local draft has no current validation findings, but that does not prove a remote profile installed."
            : "Fix the local validation findings before deployment, then retry only after confirming the target scope."
        return LocalModelResponse(
            message: "Here’s the quickest way to narrow down a Jamf School profile problem:\n• \(connectionStep)\n• \(scopeStep)\n• Check whether the profile is set to deploy automatically or on demand, and whether a conflicting profile has the opposite setting.\n• \(validationStep)\n\nI can fix conflicts that are visible in this local draft. For a tenant-side failure, send me the exact Jamf activity-log message and I’ll help interpret the next safe step.",
            edits: []
        )
    }

    private func isApplicationIssue(_ prompt: String) -> Bool {
        let mentionsApp = prompt.contains("mdm copilot") || prompt.contains("the app") || prompt.contains("application")
        let mentionsProblem = ["issue", "problem", "error", "crash", "not working", "stuck", "slow"]
            .contains(where: prompt.contains)
        return mentionsApp && mentionsProblem
    }

    private func profileBuildResponse(
        for request: LocalModelRequest,
        prompt: String
    ) -> LocalModelResponse? {
        let confirmedBalancedBaseline = [
            "use balanced baseline", "apply balanced baseline", "balanced classroom baseline",
            "use the balanced baseline", "apply the balanced baseline",
            "lets do balanced baseline", "let's do balanced baseline"
        ].contains(where: prompt.contains)
        let asksToBuild = ["build", "create", "make", "set up", "setup"].contains(where: prompt.contains)
        let mentionsProfile = prompt.contains("profile") || prompt.contains("configuration")
        let wantsLockdown = [
            "lockdown", "locked down", "lock down", "student restrictions", "school restrictions"
        ].contains(where: prompt.contains)
        let mentionsStudents = [
            "student", "students", "learner", "learners", "pupil", "pupils", "grade"
        ].contains(where: prompt.contains)
        let asksForBroadRestrictions = prompt.contains("restrict") &&
            mentionsStudents &&
            referencedRestrictionMatches(in: prompt).isEmpty
        guard confirmedBalancedBaseline ||
                (asksToBuild && mentionsProfile && (wantsLockdown || asksForBroadRestrictions)) else {
            return nil
        }

        let grade = extractedGrade(from: prompt)
        let baselineName = grade.map { "Grade \($0)" } ?? "student"

        guard confirmedBalancedBaseline else {
            let audience = grade.map { "Grade \($0) students" } ?? "students"
            return LocalModelResponse(
                message: "Before I change the draft, let’s confirm what ‘restricted’ should mean for \(audience). A restriction profile can affect several different areas, so applying a large generic set without confirming it could block teaching tools you still need.\n\nChoose one of these starting points:\n• Balanced baseline — prevent student app installation/removal, account and device-setting changes, AirDrop, screenshots and passcode changes; keep camera, Safari and school-specific apps unchanged.\n• Custom — tell me the areas to control: apps, accounts, sharing, camera/screen capture, web content, Wi-Fi, device settings or an approved-app list.\n\nReply ‘use balanced baseline’ or list the exact outcomes you want. I won’t scan or apply the wider restriction catalogue until you confirm.",
                edits: []
            )
        }

        var edits: [IntentEdit] = []
        if request.intent.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            edits.append(.renameProfile(suggestedProfileName(from: prompt)))
        }
        if !request.intent.devicesAreSupervised {
            edits.append(.setDevicesAreSupervised(true))
        }

        let baseline: [(RestrictionKey, RestrictionState)] = [
            (.appInstallation, .deny),
            (.allowAppRemoval, .deny),
            (.accountModification, .deny),
            (.airDrop, .deny),
            (.screenCapture, .deny),
            (.allowPasscodeModification, .deny),
            (.allowDeviceNameModification, .deny),
            (.allowUIConfigurationProfileInstallation, .deny),
            (.forceAutomaticDateAndTime, .allow),
            (.forceWiFiPowerOn, .allow),
            (.allowAssistantWhileLocked, .deny)
        ]

        for (key, state) in baseline where (request.intent.restrictions[key] ?? .unchanged) != state {
            edits.append(.setRestriction(key, state))
        }
        guard !edits.isEmpty else {
            return LocalModelResponse(
                message: "This draft already matches the confirmed \(baselineName) balanced baseline. Review the configured restrictions and add any school-specific items such as camera, Safari, YouTube, Wi-Fi or app safelists.",
                edits: []
            )
        }

        let changed = edits.map(\.verifiedDescription).joined(separator: "\n• ")
        return LocalModelResponse(
            message: "I applied the confirmed \(baselineName) balanced baseline to the local draft:\n• \(changed)\n\nI left camera, Safari and app safelists unchanged because those depend on the school’s teaching model. If you want a stricter profile, say things like ‘disable camera’, ‘disable Safari’ or ‘only allow these apps’. Nothing has been sent to Jamf School yet.",
            edits: edits
        )
    }

    private func suggestedProfileName(from prompt: String) -> String {
        if let grade = extractedGrade(from: prompt) {
            return "Grade \(grade) iPad Lockdown"
        }
        return "Student iPad Lockdown"
    }

    private func extractedGrade(from prompt: String) -> String? {
        let expression = try! NSRegularExpression(pattern: #"\bgrade\s+([0-9]{1,2})\b"#, options: .caseInsensitive)
        let range = NSRange(location: 0, length: (prompt as NSString).length)
        guard let match = expression.firstMatch(in: prompt, range: range) else { return nil }
        return (prompt as NSString).substring(with: match.range(at: 1))
    }

    private func profileStateResponse(
        for request: LocalModelRequest,
        prompt: String
    ) -> LocalModelResponse? {
        let asksForDisabledState = [
            "what is disabled",
            "what's disabled",
            "what functionality is disabled",
            "what functionality of the devices is disabled",
            "what has been disabled",
            "what has been removed",
            "everything that has been removed",
            "list disabled"
        ].contains(where: prompt.contains)
        if asksForDisabledState {
            let disabled = configuredRestrictions(in: request.intent).compactMap { definition, state -> String? in
                switch (definition.semantics, state) {
                case (.permission, .deny), (.toggle, .deny), (.requirement, .allow):
                    return restrictionExplanation(definition, state: state)
                default:
                    return nil
                }
            }
            guard !disabled.isEmpty else {
                return LocalModelResponse(
                    message: "Good news—this draft does not currently disable any device functionality.",
                    edits: []
                )
            }
            return LocalModelResponse(
                message: "Here’s what this draft currently prevents or enforces on the iPads:\n• " + disabled.joined(separator: "\n• ") + "\n\nThis is still a local draft; nothing has been sent to Jamf School.",
                edits: []
            )
        }

        let asksForProfileSummary = [
            "what does this profile do", "what will this profile do", "describe this profile",
            "explain this profile", "summarise this profile", "summarize this profile",
            "what settings are set", "what settings have been set", "show configured settings",
            "what is configured in this profile", "what has been configured in this profile"
        ].contains(where: prompt.contains) ||
            ((prompt.contains("restriction") || prompt.contains("restrictions")) &&
             ["what", "which", "list", "show", "tell", "describe", "explain", "all"].contains(where: prompt.contains)) ||
            (prompt.contains("profile") &&
             (prompt.contains("configured") || prompt.contains("settings")) &&
             ["what", "which", "show", "tell", "describe", "explain"].contains(where: prompt.contains))
        guard asksForProfileSummary else { return nil }
        return completeProfileSummary(for: request)
    }

    private func completeProfileSummary(for request: LocalModelRequest) -> LocalModelResponse {
        let intent = request.intent
        let profileName = intent.name.trimmingCharacters(in: .whitespacesAndNewlines)
        var sections: [String] = []
        let heading = profileName.isEmpty
            ? "Here’s what this profile draft will do when it is deployed:"
            : "Here’s what ‘\(profileName)’ will do when it is deployed:"

        let restrictions = configuredRestrictions(in: intent)
        if restrictions.isEmpty {
            sections.append("Restrictions\n• No restrictions are currently configured.")
        } else {
            let lines = restrictions.map { restrictionExplanation($0.0, state: $0.1) }
            sections.append("Restrictions\n• " + lines.joined(separator: "\n• "))
        }

        if !intent.wifiPayloads.isEmpty {
            let networks = intent.wifiPayloads.map { wifi -> String in
                let name = wifi.ssid.isEmpty ? "an SSID that still needs to be entered" : "‘\(wifi.ssid)’"
                let security = wifi.securityType?.title ?? "a security type that still needs to be selected"
                let joining = wifi.autoJoin ? "join automatically" : "require the user to select it manually"
                let visibility = wifi.hiddenNetwork ? " It is marked as a hidden network." : ""
                return "Connect to \(name) using \(security) and \(joining).\(visibility)"
            }
            sections.append("Wi-Fi\n• " + networks.joined(separator: "\n• "))
        }

        if !intent.dockItems.isEmpty {
            let apps = intent.dockItems.map(\.displayName).joined(separator: ", ")
            sections.append("Dock\n• Place \(apps) in the managed iPad Dock.")
        }

        let target = intent.scope.deviceGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetDescription = target.isEmpty
            ? "No Jamf School device group is selected yet."
            : "Target the existing Jamf School group ‘\(target)’ once deployment is confirmed."
        let supervisionDescription = intent.devicesAreSupervised
            ? "The draft expects supervised iPads."
            : "The draft is not currently marked as requiring supervised iPads."
        sections.append("Scope\n• \(targetDescription)\n• \(supervisionDescription)")

        if !request.validationIssues.isEmpty {
            let errors = request.validationIssues.filter { $0.severity == .error }.count
            let warnings = request.validationIssues.filter { $0.severity == .warning }.count
            let status: String
            if errors > 0 {
                status = "There \(errors == 1 ? "is" : "are") \(errors) validation error\(errors == 1 ? "" : "s") to fix before deployment."
            } else if warnings > 0 {
                status = "There \(warnings == 1 ? "is" : "are") \(warnings) validation warning\(warnings == 1 ? "" : "s") to review."
            } else {
                status = "The remaining validation notes are informational."
            }
            sections.append("Before deployment\n• \(status)")
        }

        return LocalModelResponse(
            message: heading + "\n\n" + sections.joined(separator: "\n\n") + "\n\nNothing has been sent to Jamf School yet.",
            edits: []
        )
    }

    private func configuredRestrictions(
        in intent: ProfileIntent
    ) -> [(RestrictionDefinition, RestrictionState)] {
        RestrictionCatalogue.iPadOS.compactMap { definition in
            let state = intent.restrictions[definition.key] ?? .unchanged
            return state == .unchanged ? nil : (definition, state)
        }
    }

    private func restrictionExplanation(
        _ definition: RestrictionDefinition,
        state: RestrictionState
    ) -> String {
        "\(definition.title) — \(definition.label(for: state)). \(practicalEffect(of: definition, state: state))"
    }

    private func practicalEffect(
        of definition: RestrictionDefinition,
        state: RestrictionState
    ) -> String {
        if definition.key == .forceWiFiPowerOn, state == .deny {
            return "The profile does not force Wi-Fi to remain on, so users can turn it off."
        }
        if definition.key == .forceAutomaticDateAndTime, state == .deny {
            return "The profile does not force automatic date and time, so users can change those settings."
        }

        let expectedCondition: String?
        switch (definition.semantics, state) {
        case (.permission, .deny), (.toggle, .deny): expectedCondition = "false"
        case (.requirement, .allow), (.toggle, .allow): expectedCondition = "true"
        default: expectedCondition = nil
        }
        if let expectedCondition,
           let summary = summaryEffect(definition.summary, condition: expectedCondition) {
            return summary
        }

        let feature = definition.title
            .replacingOccurrences(of: "Allow ", with: "", options: [.anchored, .caseInsensitive])
            .lowercasingFirstLetter()
        switch (definition.semantics, state) {
        case (.permission, .allow):
            return "The profile explicitly keeps \(feature) available to users."
        case (.permission, .deny):
            return "The profile disables \(feature)."
        case (.requirement, .allow):
            return "The profile enforces this requirement on the iPads."
        case (.requirement, .deny):
            return "The profile explicitly does not enforce this requirement."
        case (.toggle, .allow):
            return "The profile enables \(feature)."
        case (.toggle, .deny):
            return "The profile disables \(feature)."
        case (_, .unchanged):
            return "The profile leaves this setting unchanged."
        }
    }

    private func summaryEffect(_ rawSummary: String, condition: String) -> String? {
        var summary = rawSummary.replacingOccurrences(of: "`", with: "")
        if let noteRange = summary.range(of: " > Note:", options: .caseInsensitive) {
            summary = String(summary[..<noteRange.lowerBound])
        }
        let prefix = "If \(condition), "
        guard summary.lowercased().hasPrefix(prefix.lowercased()) else { return nil }
        summary.removeFirst(prefix.count)
        summary = summary.replacingOccurrences(of: "the system", with: "the iPad", options: [.caseInsensitive, .anchored])
        summary = summary.replacingOccurrences(of: "Control Center", with: "Control Centre")
        summary = summary.replacingOccurrences(of: " and later.", with: ".")
        return summary.uppercasingFirstLetter()
    }

    private func wifiResponse(
        for request: LocalModelRequest,
        prompt: String,
        lowercased: String
    ) -> LocalModelResponse? {
        let mentionsWiFi = lowercased.contains("wi-fi") ||
            lowercased.contains("wifi") ||
            lowercased.contains("wireless") ||
            lowercased.contains("ssid") ||
            lowercased.contains("802.1x") ||
            lowercased.contains("eap") ||
            lowercased.contains("network profile")
        let incomplete = request.intent.wifiPayloads.last(where: wifiNeedsInformation)
        let latest = request.intent.wifiPayloads.last

        let rejectsCurrentSSID = [
            "ssid is not",
            "ssid isn't",
            "ssid isnt",
            "not the ssid",
            "wrong ssid"
        ].contains(where: lowercased.contains)
        if rejectsCurrentSSID, var wifi = latest {
            wifi.ssid = ""
            return LocalModelResponse(
                message: "Understood. I cleared the incorrect SSID from the current Wi-Fi draft. What is the exact, case-sensitive SSID?",
                edits: [.updateWiFiPayload(wifi)]
            )
        }

        let abandonsWiFi = incomplete != nil &&
            (lowercased.contains("leave") ||
             lowercased.contains("cancel") ||
             lowercased.contains("skip") ||
             lowercased.contains("not now") ||
             lowercased.contains("unconfigured")) &&
            (lowercased.contains("wi-fi") ||
             lowercased.contains("wifi") ||
             lowercased.contains("network") ||
             lowercased.contains("it"))
        if abandonsWiFi, let incomplete {
            return LocalModelResponse(
                message: "I removed the incomplete local Wi-Fi draft. Nothing was changed in Jamf School, and other profile edits can continue normally.",
                edits: [.removeWiFiPayload(incomplete.id)]
            )
        }

        let explicitSSID = explicitlyExtractedSSID(from: prompt)
        let ssidAnswer = incomplete.flatMap { wifi in
            explicitSSID ?? bareSSIDFollowUp(from: prompt, lowercased: lowercased, current: wifi)
        }
        let securityAnswer = extractedSecurity(from: lowercased)
        let answersEAPQuestion = incomplete?.authenticationType == .enterprise &&
            (lowercased.contains("peap") ||
             lowercased.contains("ttls") ||
             lowercased.contains("eap-tls") ||
             lowercased.contains("eap tls") ||
             lowercased.contains("eap-fast") ||
             lowercased.contains("eap fast"))
        let isRelevantFollowUp = ssidAnswer != nil || securityAnswer != nil || answersEAPQuestion
        guard mentionsWiFi || isRelevantFollowUp else { return nil }

        if lowercased.contains("password") || lowercased.contains("passphrase") {
            return LocalModelResponse(
                message: "Enter the password in the secure Wi-Fi field shown below this conversation. It is stored only in memory and is never sent to the model.",
                edits: []
            )
        }

        let removesNetwork = (lowercased.contains("remove") || lowercased.contains("delete")) &&
            (lowercased.contains("wi-fi") || lowercased.contains("wifi") || lowercased.contains("network"))
        if removesNetwork, let target = matchingWiFi(in: request.intent, prompt: lowercased) {
            return LocalModelResponse(
                message: "I removed the local Wi-Fi payload for ‘\(target.ssid)’. Nothing was changed in Jamf School.",
                edits: [.removeWiFiPayload(target.id)]
            )
        }

        let startsNetwork = mentionsWiFi &&
            !lowercased.contains("ssid") &&
            (lowercased.contains("create") ||
             lowercased.contains("add") ||
             lowercased.contains("configure") ||
             lowercased.contains("connect"))
        var wifi: WiFiPayloadIntent
        let isNew: Bool
        if let incomplete {
            wifi = incomplete
            isNew = false
        } else if explicitSSID != nil, let latest {
            wifi = latest
            isNew = false
        } else if startsNetwork {
            wifi = WiFiPayloadIntent()
            isNew = true
        } else {
            return nil
        }

        if let ssid = explicitSSID ?? ssidAnswer {
            wifi.ssid = ssid
        }
        if let security = extractedSecurity(from: lowercased) {
            wifi.securityType = security
        }
        if lowercased.contains("enterprise") || lowercased.contains("802.1x") || lowercased.contains("eap") {
            wifi.authenticationType = .enterprise
            if lowercased.contains("eap-tls") || lowercased.contains("eap tls") {
                addEAP(.tls, to: &wifi)
            }
            if lowercased.contains("peap") { addEAP(.peap, to: &wifi) }
            if lowercased.contains("ttls") { addEAP(.ttls, to: &wifi) }
            if lowercased.contains("eap-fast") || lowercased.contains("eap fast") {
                addEAP(.fast, to: &wifi)
            }
        }
        if lowercased.contains("hidden network") || lowercased.contains("hidden ssid") {
            wifi.hiddenNetwork = true
        }
        if lowercased.contains("do not auto join") || lowercased.contains("disable auto join") {
            wifi.autoJoin = false
        } else if lowercased.contains("auto join") || lowercased.contains("autojoin") {
            wifi.autoJoin = true
        }

        let questions = missingWiFiInformation(wifi)
        let prefix = isNew ? "I started a local Wi-Fi payload." : "I updated the Wi-Fi draft."
        let message: String
        if questions.isEmpty {
            message = "\(prefix) Its required non-secret fields are complete. Review it in the builder before export or deployment."
        } else {
            message = "\(prefix) I still need:\n• " + questions.joined(separator: "\n• ")
        }
        return LocalModelResponse(
            message: message,
            edits: [isNew ? .addWiFiPayload(wifi) : .updateWiFiPayload(wifi)]
        )
    }

    private func wifiNeedsInformation(_ wifi: WiFiPayloadIntent) -> Bool {
        !missingWiFiInformation(wifi).isEmpty
    }

    private func missingWiFiInformation(_ wifi: WiFiPayloadIntent) -> [String] {
        var missing: [String] = []
        if wifi.ssid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append("the exact, case-sensitive SSID")
        }
        if wifi.securityType == nil {
            missing.append("the security type: Open, WEP, WPA, WPA2, WPA3 or Any")
        }
        if wifi.authenticationType == .enterprise && wifi.enterprise.acceptedEAPTypes.isEmpty {
            missing.append("the enterprise EAP type, such as PEAP, EAP-TTLS or EAP-TLS")
        }
        if wifi.authenticationType == .personal,
           wifi.securityType?.requiresCredential == true,
           wifi.password.isEmpty {
            missing.append("the Wi-Fi password in the secure field")
        }
        return missing
    }

    private func explicitlyExtractedSSID(from prompt: String) -> String? {
        let markers = ["ssid is ", "ssid: ", "ssid ", "network named ", "network called "]
        for marker in markers {
            guard let range = prompt.range(of: marker, options: .caseInsensitive) else { continue }
            var value = String(prompt[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            for separator in [" and security", ", security", " with security", " using "] {
                if let separatorRange = value.range(of: separator, options: .caseInsensitive) {
                    value = String(value[..<separatorRange.lowerBound])
                }
            }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\"'.,"))
            let lowercasedValue = value.lowercased()
            if !value.isEmpty,
               !lowercasedValue.hasPrefix("not "),
               lowercasedValue != "not" {
                return String(value.prefix(128))
            }
        }
        return nil
    }

    private func bareSSIDFollowUp(
        from prompt: String,
        lowercased: String,
        current: WiFiPayloadIntent
    ) -> String? {
        let commandWords = [
            "disable", "allow", "enable", "remove", "delete", "leave", "cancel",
            "skip", "fix", "validation", "camera", "screenshot", "dock", "profile",
            "create", "add", "configure", "configuration", "connect", "wifi", "wi-fi",
            "wireless", "network", "ssid", "security", "password", "passphrase"
        ]
        let looksLikeBareSSID = current.ssid.isEmpty &&
            prompt.count <= 64 &&
            extractedSecurity(from: lowercased) == nil &&
            !commandWords.contains(where: lowercased.contains)
        let cleaned = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return looksLikeBareSSID && !cleaned.isEmpty ? String(cleaned.prefix(128)) : nil
    }

    private func extractedSecurity(from prompt: String) -> WiFiSecurityType? {
        if prompt.contains("wpa3") { return .wpa3 }
        if prompt.contains("wpa2") { return .wpa2 }
        if prompt.contains("wpa") { return .wpa }
        if prompt.contains("wep") { return .wep }
        if prompt.contains("open network") || prompt.contains("no password") { return WiFiSecurityType.none }
        if prompt.contains("any security") { return .any }
        return nil
    }

    private func addEAP(_ type: WiFiEAPType, to wifi: inout WiFiPayloadIntent) {
        if !wifi.enterprise.acceptedEAPTypes.contains(type) {
            wifi.enterprise.acceptedEAPTypes.append(type)
        }
    }

    private func matchingWiFi(in intent: ProfileIntent, prompt: String) -> WiFiPayloadIntent? {
        intent.wifiPayloads.first {
            !$0.ssid.isEmpty && prompt.contains($0.ssid.lowercased())
        } ?? (intent.wifiPayloads.count == 1 ? intent.wifiPayloads[0] : nil)
    }

    private func stateRequested(
        for definition: RestrictionDefinition,
        in prompt: String
    ) -> RestrictionState? {
        let termRanges = definition.searchTerms.compactMap { prompt.range(of: $0) }
        guard let termRange = termRanges.min(by: {
            prompt.distance(from: prompt.startIndex, to: $0.lowerBound) <
            prompt.distance(from: prompt.startIndex, to: $1.lowerBound)
        }) else { return nil }

        if definition.semantics == .requirement {
            let removesRequirement = [
                "do not require", "don't require", "dont require", "stop requiring",
                "allow users to change", "let users change", "permit users to change"
            ].contains(where: prompt.contains)
            if removesRequirement { return .deny }

            let enforcesRequirement = [
                "require", "force", "prevent", "restrict", "must use",
                "stop users from", "cannot change", "can't change", "cant change",
                "cannot turn off", "can't turn off", "cant turn off"
            ].contains(where: prompt.contains)
            if enforcesRequirement { return .allow }
        }

        if definition.semantics == .permission || definition.semantics == .toggle {
            let explicitlySetsOutcome = [
                "make sure", "ensure", "prevent", "restrict", "stop users from",
                "stop students from", "do not allow", "don't allow", "dont allow",
                "must not", "should not"
            ].contains(where: prompt.contains)
            let deniesAccess = [
                "cannot access", "can't access", "cant access", "can not access",
                "cannot use", "can't use", "cant use", "can not use",
                "cannot open", "can't open", "cant open", "can not open",
                "not available", "unavailable"
            ].contains(where: prompt.contains)
            let statesGeneralInability = [
                "cannot", "can't", "cant", "can not", "unable"
            ].contains(where: prompt.contains)
            if explicitlySetsOutcome &&
                (deniesAccess || statesGeneralInability || prompt.contains("prevent") || prompt.contains("restrict")) {
                return .deny
            }

            let permitsAccess = [
                "make sure students can", "make sure users can", "ensure students can",
                "ensure users can", "let students", "let users", "permit students",
                "permit users"
            ].contains(where: prompt.contains)
            if permitsAccess { return .allow }
        }

        let directives: [(phrase: String, state: RestrictionState)] = [
            ("clear the restriction", .unchanged),
            ("unchanged", .unchanged),
            ("reset", .unchanged),
            ("disable", .deny),
            ("disallow", .deny),
            ("block", .deny),
            ("deny", .deny),
            ("allow", .allow),
            ("enable", .allow)
        ]

        let occurrences = directives.flatMap { directive in
            ranges(of: directive.phrase, in: prompt).map { range in
                (range: range, state: directive.state)
            }
        }
        let preceding = occurrences
            .filter { $0.range.lowerBound <= termRange.lowerBound }
            .min {
                prompt.distance(from: $0.range.lowerBound, to: termRange.lowerBound) <
                prompt.distance(from: $1.range.lowerBound, to: termRange.lowerBound)
            }
        if let preceding { return preceding.state }

        let following = occurrences
            .filter { $0.range.lowerBound > termRange.lowerBound }
            .min {
                prompt.distance(from: termRange.lowerBound, to: $0.range.lowerBound) <
                prompt.distance(from: termRange.lowerBound, to: $1.range.lowerBound)
            }
        return occurrences.count == 1 ? following?.state : nil
    }

    private func ranges(of phrase: String, in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(of: phrase, range: searchStart..<text.endIndex) {
            ranges.append(range)
            searchStart = range.upperBound
        }
        return ranges
    }

    private func validationResponse(_ issues: [ValidationIssue]) -> LocalModelResponse {
        guard !issues.isEmpty else {
            return LocalModelResponse(
                message: "The current draft has no validation findings.",
                edits: []
            )
        }

        let summary = issues.map { issue in
            let label: String
            switch issue.severity {
            case .error: label = "Error"
            case .warning: label = "Warning"
            case .information: label = "Note"
            }
            return "• \(label): \(issue.title) — \(issue.detail)"
        }.joined(separator: "\n")

        return LocalModelResponse(message: summary, edits: [])
    }
}

private extension String {
    func uppercasingFirstLetter() -> String {
        guard let first else { return self }
        return String(first).uppercased() + String(dropFirst())
    }

    func lowercasingFirstLetter() -> String {
        guard let first else { return self }
        return String(first).lowercased() + String(dropFirst())
    }
}

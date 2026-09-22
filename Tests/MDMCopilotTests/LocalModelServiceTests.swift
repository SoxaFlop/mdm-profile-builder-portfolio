import XCTest
@testable import MDMCopilot

final class LocalModelServiceTests: XCTestCase {
    func testPlaceholderProducesTypedRestrictionEdit() async {
        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "Disable screenshots",
            intent: .gradeSevenExample,
            validationIssues: []
        ))

        XCTAssertEqual(response.edits, [.setRestriction(.screenCapture, .deny)])
    }

    func testPlaceholderStartsGuidedWiFiPayloadWithoutGuessingRequiredValues() async {
        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "Configure a complex Wi-Fi certificate",
            intent: .gradeSevenExample,
            validationIssues: []
        ))

        guard case .addWiFiPayload(let wifi) = response.edits.first else {
            return XCTFail("Expected a typed Wi-Fi draft")
        }
        XCTAssertTrue(wifi.ssid.isEmpty)
        XCTAssertNil(wifi.securityType)
        XCTAssertTrue(response.message.contains("exact, case-sensitive SSID"))
    }

    func testWiFiCreationPhraseIsNotMistakenForTheSSID() async {
        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "Let's add Wi-Fi configuration",
            intent: .gradeSevenExample,
            validationIssues: []
        ))

        guard case .addWiFiPayload(let wifi) = response.edits.first else {
            return XCTFail("Expected a typed Wi-Fi draft")
        }
        XCTAssertTrue(wifi.ssid.isEmpty)
        XCTAssertTrue(response.message.contains("exact, case-sensitive SSID"))
    }

    func testPlaceholderAsksProductiveClarificationForOpenEndedPrompt() async {
        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "Make coffee",
            intent: .gradeSevenExample,
            validationIssues: []
        ))

        XCTAssertTrue(response.edits.isEmpty)
        XCTAssertTrue(response.message.contains("result you want"))
        XCTAssertFalse(response.message.lowercased().contains("don't understand"))
        XCTAssertFalse(response.message.lowercased().contains("not confident"))
    }

    func testPlaceholderSeparatesMixedAllowAndDisableInstructions() async {
        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "Disable screenshots and allow camera",
            intent: .gradeSevenExample,
            validationIssues: []
        ))

        XCTAssertEqual(response.edits, [
            .setRestriction(.screenCapture, .deny),
            .setRestriction(.camera, .allow)
        ])
    }

    func testProfileStateQuestionIsAnsweredFromIntent() async {
        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "What functionality is disabled?",
            intent: .gradeSevenExample,
            validationIssues: []
        ))

        XCTAssertTrue(response.message.contains("AirDrop"))
        XCTAssertTrue(response.message.contains("Screenshots"))
        XCTAssertFalse(response.message.contains("All functionality"))
        XCTAssertTrue(response.edits.isEmpty)
    }

    func testMisspeltRestrictionSummaryExplainsPracticalProfileBehaviour() async {
        var intent = ProfileIntent.blank
        intent.name = "Student Wi-Fi Profile"
        intent.devicesAreSupervised = true
        intent.restrictions[.forceWiFiPowerOn] = .allow
        intent.restrictions[.safariAllowAutoFill] = .allow

        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "Tell me all the restryictions made in this profile",
            intent: intent,
            validationIssues: []
        ))

        XCTAssertTrue(response.message.contains("‘restryictions’"))
        XCTAssertTrue(response.message.contains("‘restrictions’"))
        XCTAssertTrue(response.message.contains("prevents turning off Wi-Fi"))
        XCTAssertTrue(response.message.contains("AutoFill"))
        XCTAssertTrue(response.message.contains("Nothing has been sent to Jamf School yet"))
        XCTAssertFalse(response.message.contains("forceWiFiPowerOn=true"))
        XCTAssertTrue(response.edits.isEmpty)
    }

    func testMisspeltCommandRequiresConfirmationBeforeApplyingVerifiedEdit() async {
        let interpretation = PromptInterpretation.interpret("Disabel the camra")
        XCTAssertEqual(interpretation.correctedPrompt.lowercased(), "disable the camera")

        let service = PlaceholderLocalModelService()
        let response = await service.respond(to: LocalModelRequest(
            prompt: "Disabel the camra",
            intent: .blank,
            validationIssues: []
        ))

        XCTAssertTrue(response.edits.isEmpty)
        XCTAssertTrue(response.message.contains("disable the camera"))
        XCTAssertTrue(response.message.contains("use this interpretation"))

        let confirmation = await service.respond(to: LocalModelRequest(
            prompt: "Use this interpretation",
            intent: .blank,
            validationIssues: [],
            recentMessages: [
                ChatMessage(role: .technician, text: "Disabel the camra"),
                ChatMessage(role: .assistant, text: response.message),
                ChatMessage(role: .technician, text: "Use this interpretation")
            ]
        ))

        XCTAssertEqual(confirmation.edits, [.setRestriction(.camera, .deny)])
        XCTAssertTrue(confirmation.message.contains("Confirmed"))
        XCTAssertTrue(confirmation.message.contains("Done"))
    }

    func testValidGuideAndRemoteWordsAreNotSpellCorrected() {
        let interpretation = PromptInterpretation.interpret("Provide a how to guide for doing this remotely")

        XCTAssertEqual(
            interpretation.correctedPrompt,
            "Provide a how to guide for doing this remotely"
        )
        XCTAssertTrue(interpretation.corrections.isEmpty)
    }

    func testValidUnableWordIsNotChangedIntoOppositeInstruction() {
        let prompt = "Why are students unable to sign into their Apple Accounts?"
        let interpretation = PromptInterpretation.interpret(prompt)

        XCTAssertEqual(interpretation.correctedPrompt, prompt)
        XCTAssertTrue(interpretation.corrections.isEmpty)
    }

    func testAppleAccountQuestionExplainsAndAsksBeforeChangingDraft() async {
        var intent = ProfileIntent.blank
        intent.restrictions[.accountModification] = .deny

        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "Why are students unable to sign into their Apple Accounts?",
            intent: intent,
            validationIssues: []
        ))

        XCTAssertTrue(response.edits.isEmpty)
        XCTAssertTrue(response.message.contains("most likely cause"))
        XCTAssertTrue(response.message.contains("Account modification"))
        XCTAssertTrue(response.message.contains("apply the profile fix"))
        XCTAssertFalse(response.message.contains("spelling mistake"))
    }

    func testConfirmedTroubleshootingFixAppliesPreviouslyExplainedSetting() async {
        var intent = ProfileIntent.blank
        intent.restrictions[.accountModification] = .deny
        let service = PlaceholderLocalModelService()
        let question = "Why are students unable to sign into their Apple Accounts?"
        let explanation = await service.respond(to: LocalModelRequest(
            prompt: question,
            intent: intent,
            validationIssues: []
        ))

        let confirmation = await service.respond(to: LocalModelRequest(
            prompt: "Apply the profile fix",
            intent: intent,
            validationIssues: [],
            recentMessages: [
                ChatMessage(role: .technician, text: question),
                ChatMessage(role: .assistant, text: explanation.message),
                ChatMessage(role: .technician, text: "Apply the profile fix")
            ]
        ))

        XCTAssertEqual(confirmation.edits, [.setRestriction(.accountModification, .allow)])
        XCTAssertTrue(confirmation.message.contains("Confirmed"))
        XCTAssertTrue(confirmation.message.contains("Nothing has been sent to Jamf School"))
    }

    func testExplicitNegativeOutcomeDisablesReferencedFeature() async {
        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "Make sure students cannot access their camera",
            intent: .blank,
            validationIssues: []
        ))

        XCTAssertEqual(response.edits, [.setRestriction(.camera, .deny)])
        XCTAssertTrue(response.message.contains("Camera → Disable"))
    }

    func testSSIDValueIsNotSpellCorrected() async {
        var intent = ProfileIntent.blank
        intent.wifiPayloads = [WiFiPayloadIntent()]

        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "SSID is Restrictons-WiFi and security is WPA2",
            intent: intent,
            validationIssues: []
        ))

        guard case .updateWiFiPayload(let wifi) = response.edits.first else {
            return XCTFail("Expected the Wi-Fi draft to be updated")
        }
        XCTAssertEqual(wifi.ssid, "Restrictons-WiFi")
        XCTAssertFalse(response.message.contains("spelling mistake"))
    }

    func testProfileSummaryDescribesWiFiDockAndScopeWithoutSecrets() async {
        var intent = ProfileIntent.blank
        intent.scope = ProfileScope(deviceGroupName: "Grade 8", deviceGroupID: 42)
        intent.dockItems = [.classroom]
        intent.wifiPayloads = [WiFiPayloadIntent(
            ssid: "Students",
            securityType: .wpa2,
            password: "never-show-this"
        )]

        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "What does this profile do?",
            intent: intent,
            validationIssues: []
        ))

        XCTAssertTrue(response.message.contains("Connect to ‘Students’"))
        XCTAssertTrue(response.message.contains("WPA2/WPA3"))
        XCTAssertTrue(response.message.contains("Classroom"))
        XCTAssertTrue(response.message.contains("Grade 8"))
        XCTAssertFalse(response.message.contains("never-show-this"))
    }

    func testWiFiFollowUpUpdatesIncompleteDraft() async {
        var intent = ProfileIntent.gradeSevenExample
        let draft = WiFiPayloadIntent()
        intent.wifiPayloads = [draft]

        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "SSID is Student-Network and security is WPA2",
            intent: intent,
            validationIssues: []
        ))

        guard case .updateWiFiPayload(let wifi) = response.edits.first else {
            return XCTFail("Expected a Wi-Fi update")
        }
        XCTAssertEqual(wifi.id, draft.id)
        XCTAssertEqual(wifi.ssid, "Student-Network")
        XCTAssertEqual(wifi.securityType, .wpa2)
        XCTAssertTrue(response.message.contains("secure field"))
    }

    func testIncompleteWiFiDoesNotHijackRestrictionCommand() async {
        var intent = ProfileIntent.gradeSevenExample
        intent.wifiPayloads = [WiFiPayloadIntent(ssid: "Student-Network")]

        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "Disable camera",
            intent: intent,
            validationIssues: []
        ))

        XCTAssertEqual(response.edits, [.setRestriction(.camera, .deny)])
        XCTAssertFalse(response.message.contains("Wi-Fi draft"))
    }

    func testLeavingNetworkUnconfiguredRemovesIncompleteDraft() async {
        var intent = ProfileIntent.gradeSevenExample
        let wifi = WiFiPayloadIntent(ssid: "Student-Network")
        intent.wifiPayloads = [wifi]

        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "Let's leave the network unconfigured for now",
            intent: intent,
            validationIssues: []
        ))

        XCTAssertEqual(response.edits, [.removeWiFiPayload(wifi.id)])
        XCTAssertTrue(response.message.contains("removed"))
    }

    func testSSIDCorrectionClearsExistingValueWithoutCreatingAnotherPayload() async {
        var intent = ProfileIntent.gradeSevenExample
        let wifi = WiFiPayloadIntent(
            ssid: "lets add wifi configuration",
            securityType: .wpa2,
            password: "stored-secret"
        )
        intent.wifiPayloads = [wifi]

        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "The SSID is not lets add wifi configuration",
            intent: intent,
            validationIssues: []
        ))

        guard case .updateWiFiPayload(let updated) = response.edits.first else {
            return XCTFail("Expected the existing Wi-Fi payload to be corrected")
        }
        XCTAssertEqual(updated.id, wifi.id)
        XCTAssertTrue(updated.ssid.isEmpty)
        XCTAssertEqual(response.edits.count, 1)
        XCTAssertTrue(response.message.contains("cleared"))
    }

    func testExplicitSSIDUpdatesCompletedExistingPayload() async {
        var intent = ProfileIntent.gradeSevenExample
        let wifi = WiFiPayloadIntent(
            ssid: "Old-Network",
            securityType: .wpa2,
            password: "stored-secret"
        )
        intent.wifiPayloads = [wifi]

        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "SSID is Student-Network",
            intent: intent,
            validationIssues: []
        ))

        guard case .updateWiFiPayload(let updated) = response.edits.first else {
            return XCTFail("Expected the existing Wi-Fi payload to be updated")
        }
        XCTAssertEqual(updated.id, wifi.id)
        XCTAssertEqual(updated.ssid, "Student-Network")
    }

    func testDateAndTimeRequestUsesForceAutomaticDateAndTimeTrueValue() async {
        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "Create a profile that restricts users from changing the date and time",
            intent: .gradeSevenExample,
            validationIssues: []
        ))

        XCTAssertEqual(response.edits, [
            .setRestriction(.forceAutomaticDateAndTime, .allow)
        ])
        XCTAssertTrue(response.message.contains("Automatic date and time → Require"))
    }

    func testAppleAccountTroubleshootingFixesConfirmedLocalRestrictionBlocker() async {
        var intent = ProfileIntent.blank
        intent.restrictions[.accountModification] = .deny

        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "The kids can't sign into an Apple Account",
            intent: intent,
            validationIssues: []
        ))

        XCTAssertEqual(response.edits, [.setRestriction(.accountModification, .allow)])
        XCTAssertTrue(response.message.contains("Account modification was disabled"))
        XCTAssertTrue(response.message.contains("now set to Allow"))
        XCTAssertTrue(response.message.contains("nothing has been sent to Jamf School"))
    }

    func testAppleAccountTroubleshootingCanSafelyFixConfirmedLocalBlocker() async {
        var intent = ProfileIntent.blank
        intent.restrictions[.accountModification] = .deny

        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "Fix Apple Account sign-in in this profile",
            intent: intent,
            validationIssues: []
        ))

        XCTAssertEqual(response.edits, [.setRestriction(.accountModification, .allow)])
        XCTAssertTrue(response.message.contains("now set to Allow"))
        XCTAssertTrue(response.message.contains("nothing has been sent to Jamf School"))
    }

    func testStudentAccessIssueFixesLocalProfileRestrictionBlocker() async {
        var intent = ProfileIntent.blank
        intent.restrictions[.camera] = .deny

        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "Students cannot access the camera",
            intent: intent,
            validationIssues: []
        ))

        XCTAssertEqual(response.edits, [.setRestriction(.camera, .allow)])
        XCTAssertTrue(response.message.contains("Camera was disabled"))
        XCTAssertTrue(response.message.contains("students receiving this profile"))
        XCTAssertTrue(response.message.contains("reversible local draft change"))
    }

    func testStudentAccessIssueCanApplyConfirmedLocalFix() async {
        var intent = ProfileIntent.blank
        intent.restrictions[.camera] = .deny

        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "Fix students cannot access camera",
            intent: intent,
            validationIssues: []
        ))

        XCTAssertEqual(response.edits, [.setRestriction(.camera, .allow)])
        XCTAssertTrue(response.message.contains("found and fixed"))
    }

    func testStudentCannotDownloadFromAppStoreFixesTheExactRestriction() async {
        var intent = ProfileIntent.blank
        intent.restrictions[.appInstallation] = .deny

        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "students cannot download from the appstore",
            intent: intent,
            validationIssues: []
        ))

        XCTAssertEqual(response.edits, [.setRestriction(.appInstallation, .allow)])
        XCTAssertTrue(response.message.contains("App installation / App Store was disabled"))
        XCTAssertTrue(response.message.contains("nothing has been sent to Jamf School"))
        XCTAssertFalse(response.message.contains("spelling mistake"))
    }

    func testStudentCannotAirDropFixesConfirmedDraftBlocker() async {
        var intent = ProfileIntent.blank
        intent.restrictions[.airDrop] = .deny

        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "students cannot airdrop",
            intent: intent,
            validationIssues: []
        ))

        XCTAssertEqual(response.edits, [.setRestriction(.airDrop, .allow)])
        XCTAssertTrue(response.message.contains("AirDrop was disabled"))
    }

    func testValidationQuestionIsHandledBeforeEnhancedModel() {
        let response = PlaceholderLocalModelService().deterministicResponseIfHandled(to: LocalModelRequest(
            prompt: "What are the validation errors?",
            intent: .blank,
            validationIssues: []
        ))

        XCTAssertEqual(response?.message, "The current draft has no validation findings.")
        XCTAssertEqual(response?.edits, [])
    }

    func testJamfProfileTroubleshootingDoesNotClaimRemoteRepair() async {
        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "My Jamf profile is not working",
            intent: .blank,
            validationIssues: []
        ))

        XCTAssertTrue(response.message.contains("Connect and sync Jamf School first"))
        XCTAssertTrue(response.message.contains("activity history"))
        XCTAssertTrue(response.edits.isEmpty)
    }

    func testBroadTroubleshootingIsLeftForGenerativeReasoning() {
        let response = PlaceholderLocalModelService().deterministicResponseIfHandled(to: LocalModelRequest(
            prompt: "My Jamf profile is not working",
            intent: .blank,
            validationIssues: []
        ))

        XCTAssertNil(response)
    }

    func testComposerDelayTroubleshootingExplainsResponsiveInputFix() async {
        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "The prompt text bar is delayed when typing",
            intent: .blank,
            validationIssues: []
        ))

        XCTAssertTrue(response.message.contains("typing should remain responsive"))
        XCTAssertTrue(response.edits.isEmpty)
    }

    func testTimedAfterSchoolAccessRequestOffersJamfTimeFilterPlan() async {
        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "I need to put a time lock on all my devices at the end of the school day every day, how can I do that?",
            intent: .blank,
            validationIssues: []
        ))

        XCTAssertTrue(response.message.contains("time filter"))
        XCTAssertTrue(response.message.contains("Safelist and Blocklist"))
        XCTAssertTrue(response.message.contains("passcode lock"))
        XCTAssertTrue(response.message.contains("days and exact start/end times"))
        XCTAssertTrue(response.edits.isEmpty)
    }

    func testBroadLockdownRequestConfirmsNeedsBeforeChangingDraft() async {
        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "build a profile for grade 7 students make sure the device is locked down",
            intent: .blank,
            validationIssues: []
        ))

        XCTAssertTrue(response.edits.isEmpty)
        XCTAssertTrue(response.message.contains("Balanced baseline"))
        XCTAssertTrue(response.message.contains("Custom"))
        XCTAssertTrue(response.message.contains("I won’t scan or apply the wider restriction catalogue until you confirm"))
    }

    func testBroadGradeRestrictionRequestConfirmsNeedsBeforeChangingDraft() async {
        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "create a profile to restrict grade 7 students",
            intent: .blank,
            validationIssues: []
        ))

        XCTAssertTrue(response.edits.isEmpty)
        XCTAssertTrue(response.message.contains("Grade 7 students"))
        XCTAssertTrue(response.message.contains("use balanced baseline"))
    }

    func testConfirmedBalancedBaselineAppliesVerifiedEdits() async {
        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "use balanced baseline for grade 7",
            intent: .blank,
            validationIssues: []
        ))

        XCTAssertTrue(response.edits.contains(.renameProfile("Grade 7 iPad Lockdown")))
        XCTAssertTrue(response.edits.contains(.setDevicesAreSupervised(true)))
        XCTAssertTrue(response.edits.contains(.setRestriction(.airDrop, .deny)))
        XCTAssertTrue(response.message.contains("confirmed Grade 7 balanced baseline"))
    }

    func testNaturalBalancedBaselineConfirmationAppliesVerifiedEdits() async {
        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "lets do balanced baseline",
            intent: .blank,
            validationIssues: []
        ))

        XCTAssertTrue(response.edits.contains(.setRestriction(.airDrop, .deny)))
        XCTAssertTrue(response.edits.contains(.setRestriction(.accountModification, .deny)))
        XCTAssertTrue(response.message.contains("balanced baseline"))
    }

    func testHowToFollowUpContinuesJamfSoftwareUpdateQuestion() async {
        let updateQuestion = "iOS updates on managed iPads can this be done remotely on Jamf"
        let followUp = "provide a how to guide"
        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: followUp,
            intent: .blank,
            validationIssues: [],
            recentMessages: [
                ChatMessage(role: .technician, text: updateQuestion),
                ChatMessage(role: .assistant, text: "Yes, Jamf School supports managed updates."),
                ChatMessage(role: .technician, text: followUp)
            ]
        ))

        XCTAssertTrue(response.message.contains("Devices › Updates"))
        XCTAssertTrue(response.message.contains("Blueprints"))
        XCTAssertTrue(response.message.contains("Software Updates component"))
        XCTAssertFalse(response.message.contains("spelling mistake"))
        XCTAssertTrue(response.edits.isEmpty)
    }

    func testTroubleshootingFollowUpContinuesAppleAccountQuestion() async {
        var intent = ProfileIntent.blank
        intent.restrictions[.accountModification] = .deny
        let accountQuestion = "Why are students unable to sign into their Apple Accounts?"
        let followUp = "provide troubleshooting steps"
        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: followUp,
            intent: intent,
            validationIssues: [],
            recentMessages: [
                ChatMessage(role: .technician, text: accountQuestion),
                ChatMessage(role: .assistant, text: "Account modification may be the blocker."),
                ChatMessage(role: .technician, text: followUp)
            ]
        ))

        XCTAssertTrue(response.message.contains("Account modification"))
        XCTAssertTrue(response.message.contains("Apple School Manager"))
        XCTAssertTrue(response.message.contains("pilot iPad"))
        XCTAssertFalse(response.message.lowercased().contains("let me"))
        XCTAssertTrue(response.edits.isEmpty)
    }

    func testJamfSoftwareUpdateQuestionGetsDirectAccurateAnswer() async {
        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "iOS updates on managed iPads can this be done remotely on Jamf",
            intent: .blank,
            validationIssues: []
        ))

        XCTAssertTrue(response.message.contains("Devices › Updates"))
        XCTAssertTrue(response.message.contains("iPadOS 17 or later"))
        XCTAssertTrue(response.message.contains("blueprint"))
        XCTAssertFalse(response.message.contains("spelling mistake"))
    }

    func testAssistantEditsTimeFilterDaysTimesAndHolidayBehaviour() async {
        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "Set the time filter Monday to Friday from 15:30 to 22:00 and disable on holidays",
            intent: .blank,
            validationIssues: []
        ))

        guard case .configureJamfTimeFilter(let filter) = response.edits.first else {
            return XCTFail("Expected a Jamf time filter edit")
        }
        XCTAssertEqual(filter.activeDays, [.monday, .tuesday, .wednesday, .thursday, .friday])
        XCTAssertEqual(filter.startTime, JamfTimeOfDay(hour: 15, minute: 30))
        XCTAssertEqual(filter.endTime, JamfTimeOfDay(hour: 22, minute: 0))
        XCTAssertTrue(filter.disableOnConfiguredHolidays)
    }

    func testScheduleFollowUpAddsMisspeltWeekdayWithoutRemovingExistingDays() async {
        var intent = ProfileIntent.blank
        intent.jamfTimeFilter = JamfTimeFilter(
            activeDays: [.monday, .friday],
            startTime: JamfTimeOfDay(hour: 7, minute: 0),
            endTime: JamfTimeOfDay(hour: 14, minute: 10),
            isActiveAllDay: false,
            disableOnConfiguredHolidays: true
        )

        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "and tueadays",
            intent: intent,
            validationIssues: []
        ))

        guard case .configureJamfTimeFilter(let filter) = response.edits.first else {
            return XCTFail("Expected a time-filter update")
        }
        XCTAssertEqual(filter.activeDays, [.monday, .tuesday, .friday])
        XCTAssertTrue(response.message.contains("added"))
    }

    func testScheduleFollowUpExplainsJamfConfigurationSteps() async {
        var intent = ProfileIntent.blank
        intent.jamfTimeFilter = .afterSchoolWeekdays

        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "how do I do that?",
            intent: intent,
            validationIssues: []
        ))

        XCTAssertTrue(response.message.contains("General settings"))
        XCTAssertTrue(response.message.contains("automatic installation"))
    }

    func testEnhancedModelAcceptsOnlyExactCatalogueBackedJSONEdit() throws {
        let output = #"{"reply":"Done","edits":[{"kind":"set_restriction","restrictionKey":"forceAutomaticDateAndTime","value":true}]}"#
        let response = try QwenLocalModelService().verifiedResponse(
            forModelOutput: output,
            request: LocalModelRequest(
                prompt: "Prevent users from changing date and time",
                intent: .gradeSevenExample,
                validationIssues: []
            )
        )

        XCTAssertEqual(response.edits, [
            .setRestriction(.forceAutomaticDateAndTime, .allow)
        ])
        XCTAssertTrue(response.message.contains("verified local draft"))
        XCTAssertTrue(response.message.contains("→ Require"))
    }

    func testEnhancedModelRejectsInventedRestrictionAndFalseSuccessReply() throws {
        let output = #"{"reply":"The restriction was successfully added.","edits":[{"kind":"set_restriction","restrictionKey":"dateAndTime","value":false}]}"#
        let response = try QwenLocalModelService().verifiedResponse(
            forModelOutput: output,
            request: LocalModelRequest(
                prompt: "Prevent users from changing date and time",
                intent: .gradeSevenExample,
                validationIssues: []
            )
        )

        XCTAssertTrue(response.edits.isEmpty)
        XCTAssertTrue(response.message.contains("closest verified settings"))
        XCTAssertFalse(response.message.contains("successfully added"))
    }

    func testEnhancedModelKeepsUsefulAdviceWhenProposedEditIsRejected() throws {
        let output = #"{"reply":"Check the affected device's assigned profiles and activity history, then confirm whether another profile blocks AirDrop.","edits":[{"kind":"set_restriction","restrictionKey":"inventedAirDropKey","value":true}]}"#
        let response = try QwenLocalModelService().verifiedResponse(
            forModelOutput: output,
            request: LocalModelRequest(
                prompt: "Students cannot AirDrop; what should I check?",
                intent: .blank,
                validationIssues: []
            )
        )

        XCTAssertTrue(response.edits.isEmpty)
        XCTAssertTrue(response.message.contains("activity history"))
        XCTAssertTrue(response.message.contains("kept the local draft unchanged"))
    }

    func testEnhancedModelUsesFinalJSONAfterDiscardingPlanningText() throws {
        let output = """
        Thinking Process: I need to inspect the request first.
        {"reply":"example only","edits":[]}
        Final answer:
        {"reply":"Camera will be disabled.","edits":[{"kind":"set_restriction","restrictionKey":"allowCamera","value":false}]}
        """
        let response = try QwenLocalModelService().verifiedResponse(
            forModelOutput: output,
            request: LocalModelRequest(
                prompt: "Disable camera",
                intent: .blank,
                validationIssues: []
            )
        )

        XCTAssertEqual(response.edits, [.setRestriction(.camera, .deny)])
        XCTAssertFalse(response.message.contains("Thinking Process"))
        XCTAssertTrue(response.message.contains("Camera → Disable"))
    }

    func testDisabledStateIncludesEnforcedRequirement() async {
        var intent = ProfileIntent.gradeSevenExample
        intent.restrictions[.forceAutomaticDateAndTime] = .allow
        let response = await PlaceholderLocalModelService().respond(to: LocalModelRequest(
            prompt: "What functionality is disabled?",
            intent: intent,
            validationIssues: []
        ))

        XCTAssertTrue(response.message.contains("Automatic date and time — Require"))
        XCTAssertTrue(response.message.contains("Set Automatically"))
    }
}

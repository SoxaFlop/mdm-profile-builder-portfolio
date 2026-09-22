import XCTest
@testable import MDMCopilot

@MainActor
final class WorkspaceViewModelTests: XCTestCase {
    func testWorkspaceStartsWithAnEmptyDraft() {
        let model = WorkspaceViewModel(
            localModel: PlaceholderLocalModelService(),
            jamfConnector: FakeJamfConnector(profiles: [], groups: [])
        )

        XCTAssertTrue(model.intent.name.isEmpty)
        XCTAssertTrue(model.intent.profileDescription.isEmpty)
        XCTAssertTrue(model.intent.organisation.isEmpty)
        XCTAssertTrue(model.intent.scope.deviceGroupName.isEmpty)
        XCTAssertNil(model.intent.scope.deviceGroupID)
        XCTAssertFalse(model.intent.devicesAreSupervised)
        XCTAssertTrue(model.intent.restrictions.isEmpty)
        XCTAssertTrue(model.intent.dockItems.isEmpty)
        XCTAssertTrue(model.intent.wifiPayloads.isEmpty)
    }

    func testJamfSyncLoadsOnlySanitisedReadContext() async {
        let connector = FakeJamfConnector(
            profiles: [
                JamfProfileSummary(
                    id: 11,
                    locationId: 2,
                    identifier: "profile.identifier",
                    name: "Grade 7 iPad Profile",
                    description: nil,
                    platform: "iOS"
                )
            ],
            groups: [
                JamfDeviceGroup(
                    id: 42,
                    locationId: 2,
                    name: "Grade 7",
                    description: nil,
                    isSmartGroup: false,
                    members: 128,
                    shared: false
                )
            ]
        )
        let model = WorkspaceViewModel(
            intent: .gradeSevenExample,
            localModel: PlaceholderLocalModelService(),
            jamfConnector: connector
        )

        await model.syncJamfSchool()

        XCTAssertEqual(model.jamfConnectionState, .connected)
        XCTAssertEqual(model.jamfReadContext.profiles.map(\.id), [11])
        XCTAssertEqual(model.jamfReadContext.deviceGroups.map(\.id), [42])
        XCTAssertEqual(model.matchingJamfProfiles.map(\.id), [11])
    }

    func testSelectingLoadedGroupStoresItsJamfIDInIntent() async {
        let group = JamfDeviceGroup(
            id: 42,
            locationId: nil,
            name: "Grade 7",
            description: nil,
            isSmartGroup: false,
            members: 128,
            shared: false
        )
        let model = WorkspaceViewModel(
            localModel: PlaceholderLocalModelService(),
            jamfConnector: FakeJamfConnector(profiles: [], groups: [group])
        )

        await model.syncJamfSchool()
        model.selectJamfDeviceGroup(id: 42)

        XCTAssertEqual(model.intent.scope.deviceGroupID, 42)
        XCTAssertEqual(model.intent.scope.deviceGroupName, "Grade 7")
    }

    func testGroupCannotBeSelectedBeforeJamfIsConnected() {
        let group = JamfDeviceGroup(
            id: 42,
            locationId: nil,
            name: "Grade 7",
            description: nil,
            isSmartGroup: false,
            members: 128,
            shared: false
        )
        let model = WorkspaceViewModel(
            localModel: PlaceholderLocalModelService(),
            jamfConnector: FakeJamfConnector(profiles: [], groups: [group])
        )

        model.selectJamfDeviceGroup(id: 42)

        XCTAssertNil(model.intent.scope.deviceGroupID)
        XCTAssertTrue(model.intent.scope.deviceGroupName.isEmpty)
    }

    func testDeployedBlueprintMustBeUndeployedBeforeDelete() async {
        let connector = FakePlatformConnector(state: .deployed)
        let model = WorkspaceViewModel(
            localModel: PlaceholderLocalModelService(),
            jamfConnector: FakeJamfConnector(profiles: [], groups: []),
            platformConnector: connector,
            auditLogger: DiscardingAuditLogger()
        )

        await model.syncJamfPlatform()
        model.selectBlueprint(id: connector.blueprint.id)
        await model.deleteSelectedBlueprint()

        XCTAssertEqual(connector.deleteCount, 0)
        XCTAssertTrue(model.platformStatusMessage.contains("Undeploy"))
    }

    func testExpectedWiFiPasswordIsCapturedBeforeModelAndMaskedInChat() {
        var intent = ProfileIntent.gradeSevenExample
        let wifi = WiFiPayloadIntent(
            ssid: "Student-Network",
            securityType: .wpa2
        )
        intent.wifiPayloads = [wifi]
        let model = WorkspaceViewModel(
            intent: intent,
            localModel: PlaceholderLocalModelService(),
            jamfConnector: FakeJamfConnector(profiles: [], groups: [])
        )

        model.draftMessage = "12345678"
        model.sendMessage()

        XCTAssertEqual(model.intent.wifiPayloads.first?.password, "12345678")
        XCTAssertFalse(model.messages.contains { $0.text.contains("12345678") })
        XCTAssertTrue(model.messages.contains { $0.text.contains("entered securely") })
        XCTAssertFalse(model.isModelResponding)
    }

    func testNormalCommandIsNotCapturedAsPendingWiFiPassword() async {
        var intent = ProfileIntent.gradeSevenExample
        intent.wifiPayloads = [
            WiFiPayloadIntent(ssid: "Student-Network", securityType: .wpa2)
        ]
        let model = WorkspaceViewModel(
            intent: intent,
            localModel: PlaceholderLocalModelService(),
            jamfConnector: FakeJamfConnector(profiles: [], groups: [])
        )

        model.draftMessage = "Disable camera"
        model.sendMessage()
        while model.isModelResponding { await Task.yield() }

        XCTAssertEqual(model.intent.restrictions[.camera], .deny)
        XCTAssertTrue(model.intent.wifiPayloads.first?.password.isEmpty == true)
    }

    func testWorkspaceConfirmsBroadProfileNeedsBeforeApplyingEdits() async {
        let model = WorkspaceViewModel(
            localModel: TalkOnlyModel(),
            jamfConnector: FakeJamfConnector(profiles: [], groups: [])
        )

        model.sendMessage("build a profile for grade 7 students make sure the dveice is locked down")
        while model.isModelResponding { await Task.yield() }

        XCTAssertTrue(model.intent.name.isEmpty)
        XCTAssertFalse(model.intent.devicesAreSupervised)
        XCTAssertTrue(model.intent.restrictions.values.allSatisfy { $0 == .unchanged })
        XCTAssertTrue(model.messages.last?.text.contains("use balanced baseline") == true)
        XCTAssertTrue(model.messages.last?.text.contains("Okay, the user wants") == false)
    }

    func testWorkspaceReplacesLeakedModelSelfTalkWithSafeAnswerAndDetails() async throws {
        let model = WorkspaceViewModel(
            localModel: TalkOnlyModel(),
            jamfConnector: FakeJamfConnector(profiles: [], groups: [])
        )

        model.sendMessage("Compare the unusual deployment options for this situation")
        while model.isModelResponding { await Task.yield() }

        let reply = try XCTUnwrap(model.messages.last)
        XCTAssertFalse(reply.text.contains("Okay, the user wants"))
        XCTAssertFalse(reply.text.contains("I need to choose"))
        XCTAssertFalse(reply.text.isEmpty)
        XCTAssertTrue(reply.details?.contains("Checked:") == true)
        XCTAssertTrue(reply.details?.contains("Nothing was sent to Jamf School") == true)
    }

    func testWorkspaceShortensOrdinaryVerboseAnswerButKeepsDetailsCollapsedData() async throws {
        let model = WorkspaceViewModel(
            localModel: VerboseAnswerModel(),
            jamfConnector: FakeJamfConnector(profiles: [], groups: [])
        )

        model.sendMessage("Compare the unusual deployment options for this situation")
        while model.isModelResponding { await Task.yield() }

        let reply = try XCTUnwrap(model.messages.last)
        XCTAssertLessThan(reply.text.count, 1_300)
        XCTAssertTrue(reply.text.contains("Ask for a step-by-step guide"))
        XCTAssertNotNil(reply.details)
    }
}

private struct TalkOnlyModel: LocalModelServing {
    let displayName = "Talk-only test model"
    let isGenerativeModelLoaded = true
    let statusDetail = "Testing"

    func respond(to request: LocalModelRequest) async -> LocalModelResponse {
        LocalModelResponse(
            message: "Okay, the user wants to build a profile. I need to choose settings, but no local profile edit has been made.",
            edits: []
        )
    }
}

private struct VerboseAnswerModel: LocalModelServing {
    let displayName = "Verbose test model"
    let isGenerativeModelLoaded = true
    let statusDetail = "Testing"

    func respond(to request: LocalModelRequest) async -> LocalModelResponse {
        let paragraph = "This is a useful technician-facing comparison of the available deployment options and their practical consequences. "
        return LocalModelResponse(message: String(repeating: paragraph, count: 20), edits: [])
    }
}

private final class FakeJamfConnector: JamfSchoolConnecting {
    let capabilities = JamfConnectorCapabilities.currentReadOnly
    let profiles: [JamfProfileSummary]
    let groups: [JamfDeviceGroup]

    init(profiles: [JamfProfileSummary], groups: [JamfDeviceGroup]) {
        self.profiles = profiles
        self.groups = groups
    }

    func testConnection() async throws {}
    func listProfiles() async throws -> [JamfProfileSummary] { profiles }
    func profile(id: Int) async throws -> JamfProfileSummary { profiles.first { $0.id == id }! }
    func listDeviceGroups() async throws -> [JamfDeviceGroup] { groups }

    func createProfile(from compiledProfile: CompiledProfile) async throws -> JamfProfileSummary {
        throw JamfConnectorError.writeActionsDisabled
    }

    func updateProfile(id: Int, from compiledProfile: CompiledProfile) async throws -> JamfProfileSummary {
        throw JamfConnectorError.writeActionsDisabled
    }

    func assignProfile(id: Int, toDeviceGroupID groupID: Int) async throws {
        throw JamfConnectorError.writeActionsDisabled
    }
}

private final class FakePlatformConnector: JamfPlatformConnecting {
    let blueprint: JamfBlueprintSummary
    var deleteCount = 0

    init(state: JamfBlueprintState) {
        blueprint = JamfBlueprintSummary(
            id: UUID(),
            name: "Grade 7 iPad Profile",
            description: nil,
            created: Date(),
            updated: Date(),
            deploymentState: JamfBlueprintDeploymentState(state: state)
        )
    }

    func testConnection() async throws {}
    func listBlueprints() async throws -> [JamfBlueprintSummary] { [blueprint] }
    func blueprint(id: UUID) async throws -> JamfBlueprintDetail {
        JamfBlueprintDetail(
            id: blueprint.id,
            name: blueprint.name,
            description: blueprint.description,
            scope: JamfBlueprintScope(deviceGroups: ["42"]),
            created: blueprint.created,
            updated: blueprint.updated,
            deploymentState: blueprint.deploymentState,
            steps: []
        )
    }
    func createBlueprint(_ draft: JamfBlueprintDraft) async throws -> JamfBlueprintCreateResponse {
        JamfBlueprintCreateResponse(id: blueprint.id, href: URL(string: "https://example.invalid")!)
    }
    func updateBlueprint(id: UUID, draft: JamfBlueprintDraft) async throws {}
    func deployBlueprint(id: UUID) async throws {}
    func undeployBlueprint(id: UUID) async throws {}
    func deleteBlueprint(id: UUID) async throws { deleteCount += 1 }
}

private struct DiscardingAuditLogger: JamfMutationAuditLogging {
    func record(_ entry: JamfMutationAuditEntry) {}
}

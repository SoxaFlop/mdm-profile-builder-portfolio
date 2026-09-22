import SwiftUI

struct JamfIntegrationView: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    @State private var pendingAction: BlueprintConfirmation?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                connectionCard
                platformLifecycleCard
                deploymentPreflight
                deviceGroups
                blueprints
                profiles
            }
            .padding(16)
        }
        .alert(item: $pendingAction) { action in
            Alert(
                title: Text(action.title),
                message: Text(action.message(groupName: model.intent.scope.deviceGroupName)),
                primaryButton: action.isDestructive
                    ? .destructive(Text(action.buttonTitle)) { perform(action) }
                    : .default(Text(action.buttonTitle)) { perform(action) },
                secondaryButton: .cancel()
            )
        }
    }

    private var connectionCard: some View {
        GroupBox("Read-only Jamf School connection") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(model.jamfConnectionState.title, systemImage: connectionIcon)
                        .foregroundStyle(connectionColour)
                    Spacer()
                    SettingsLink {
                        Label("Credentials", systemImage: "key.fill")
                    }
                    Button {
                        Task { await model.syncJamfSchool() }
                    } label: {
                        Label(
                            model.jamfConnectionState == .connected ? "Refresh" : "Connect and sync",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.jamfConnectionState == .connecting)
                }

                if case .failed(let message) = model.jamfConnectionState {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                Text("This legacy API connection reads profile names and device groups. It cannot modify profiles. Its API credentials remain in Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)
        }
    }

    private var platformLifecycleCard: some View {
        GroupBox("Managed blueprint lifecycle (Platform API beta)") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(model.platformConnectionState.title, systemImage: platformConnectionIcon)
                        .foregroundStyle(platformConnectionColour)
                    Spacer()
                    SettingsLink {
                        Label("Platform credentials", systemImage: "key.fill")
                    }
                    Button {
                        Task { await model.syncJamfPlatform() }
                    } label: {
                        Label(
                            model.platformConnectionState == .connected ? "Refresh blueprints" : "Connect Platform beta",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.platformConnectionState == .connecting || model.isPlatformMutating)
                }

                Text(model.platformStatusMessage)
                    .font(.caption)
                    .foregroundStyle(platformStatusColour)
                    .textSelection(.enabled)

                Divider()

                HStack(spacing: 8) {
                    Button("Create blueprint draft") {
                        pendingAction = .create(name: model.intent.name)
                    }
                    .disabled(!model.canCreateBlueprint)

                    Button("Update selected") {
                        if let blueprint = model.selectedJamfBlueprint {
                            pendingAction = .update(blueprint)
                        }
                    }
                    .disabled(!canUpdateSelected)

                    Button(
                        model.selectedJamfBlueprint?.deploymentState.state == .outOfDate
                            ? "Deploy changes"
                            : "Deploy selected"
                    ) {
                        if let blueprint = model.selectedJamfBlueprint {
                            pendingAction = .deploy(blueprint)
                        }
                    }
                    .disabled(
                        model.selectedJamfBlueprint == nil ||
                        model.selectedJamfBlueprint?.deploymentState.state == .deployed ||
                        model.isPlatformMutating
                    )

                    Button("Undeploy selected") {
                        if let blueprint = model.selectedJamfBlueprint {
                            pendingAction = .undeploy(blueprint)
                        }
                    }
                    .disabled(
                        model.selectedJamfBlueprint == nil ||
                        model.selectedJamfBlueprint?.deploymentState.state == .notDeployed ||
                        model.isPlatformMutating
                    )

                    Spacer()

                    Button("Delete selected", role: .destructive) {
                        if let blueprint = model.selectedJamfBlueprint {
                            pendingAction = .delete(blueprint)
                        }
                    }
                    .disabled(
                        model.selectedJamfBlueprint?.deploymentState.state != .notDeployed ||
                        model.isPlatformMutating
                    )
                }

                if model.isPlatformMutating {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for Jamf Platform API…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Create makes an undeployed draft. Update, deploy, undeploy and delete operate only on the selected blueprint after confirmation. A deployed or out-of-date blueprint must be undeployed before deletion.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)
        }
    }

    private var deploymentPreflight: some View {
        GroupBox("Reconciliation preflight") {
            VStack(alignment: .leading, spacing: 10) {
                preflightRow(
                    title: "Local payload",
                    detail: model.compiledProfile == nil
                        ? "Resolve validation errors before export."
                        : "Compiled locally and ready for technician review.",
                    isReady: model.compiledProfile != nil
                )
                preflightRow(
                    title: "Target device group",
                    detail: targetGroupDetail,
                    isReady: model.selectedJamfDeviceGroup != nil
                )
                preflightRow(
                    title: "Existing profile name",
                    detail: matchingProfileDetail,
                    isReady: model.jamfConnectionState == .connected && model.matchingJamfProfiles.isEmpty
                )
                preflightRow(
                    title: "Managed blueprint match",
                    detail: matchingBlueprintDetail,
                    isReady: model.platformConnectionState == .connected && model.matchingJamfBlueprints.count <= 1
                )
                if model.intent.jamfTimeFilter != nil {
                    preflightRow(
                        title: "Jamf School time filter",
                        detail: "This schedule is saved in the local draft and preview. Configure the matching time filter manually in Jamf School’s General profile settings; the supported Blueprint API flow cannot send it yet.",
                        isReady: false
                    )
                }

                Label(
                    "The assistant prepares typed settings only. A technician must confirm every lifecycle request and should pilot deployment on a test group.",
                    systemImage: "person.badge.shield.checkmark.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.top, 2)
            }
            .padding(.top, 6)
        }
    }

    private var blueprints: some View {
        GroupBox("Managed blueprints (\(model.jamfBlueprints.count))") {
            VStack(alignment: .leading, spacing: 8) {
                if model.jamfBlueprints.isEmpty {
                    emptyState("Connect the Platform API beta to load blueprints managed through its supported lifecycle endpoints.")
                } else {
                    ForEach(model.jamfBlueprints) { blueprint in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(blueprint.name).fontWeight(.medium)
                                Text("\(blueprint.deploymentState.state.title) · Updated \(blueprint.updated.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.selectedJamfBlueprint?.id == blueprint.id {
                                Label("Selected", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else {
                                Button("Select") { model.selectBlueprint(id: blueprint.id) }
                                    .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
            }
            .padding(.top, 6)
        }
    }

    private var deviceGroups: some View {
        GroupBox("Device groups (\(model.jamfDeviceGroups.count))") {
            VStack(alignment: .leading, spacing: 8) {
                if model.jamfDeviceGroups.isEmpty {
                    emptyState("Connect to load the groups available to this API key.")
                } else {
                    ForEach(model.jamfDeviceGroups) { group in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.name).fontWeight(.medium)
                                Text(groupMetadata(group))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.intent.scope.deviceGroupID == group.id {
                                Label("Selected", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            } else {
                                Button("Use as target") {
                                    model.selectJamfDeviceGroup(id: group.id)
                                }
                                .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
            }
            .padding(.top, 6)
        }
    }

    private var profiles: some View {
        GroupBox("Existing profiles (\(model.jamfProfiles.count))") {
            VStack(alignment: .leading, spacing: 8) {
                if model.jamfProfiles.isEmpty {
                    emptyState("Connect to check existing profile names before manual upload.")
                } else {
                    ForEach(model.jamfProfiles) { profile in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name).fontWeight(.medium)
                                Text(profileMetadata(profile))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.matchingJamfProfiles.contains(profile) {
                                Label("Name match", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
            }
            .padding(.top, 6)
        }
    }

    private var connectionIcon: String {
        switch model.jamfConnectionState {
        case .notConfigured: "link.badge.plus"
        case .connecting: "arrow.triangle.2.circlepath"
        case .connected: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var connectionColour: Color {
        switch model.jamfConnectionState {
        case .notConfigured: .secondary
        case .connecting: .blue
        case .connected: .green
        case .failed: .red
        }
    }

    private var platformConnectionIcon: String {
        switch model.platformConnectionState {
        case .notConfigured: "shippingbox"
        case .connecting: "arrow.triangle.2.circlepath"
        case .connected: "checkmark.shield.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var platformConnectionColour: Color {
        switch model.platformConnectionState {
        case .notConfigured: .secondary
        case .connecting: .blue
        case .connected: .green
        case .failed: .red
        }
    }

    private var platformStatusColour: Color {
        if case .failed = model.platformConnectionState { return .red }
        return .secondary
    }

    private var canUpdateSelected: Bool {
        model.selectedJamfBlueprint != nil &&
        model.compiledProfile != nil &&
        model.selectedJamfDeviceGroup != nil &&
        !model.isPlatformMutating
    }

    private var targetGroupDetail: String {
        if let group = model.selectedJamfDeviceGroup {
            return "Matched to ‘\(group.name)’ (ID \(group.id))."
        }
        return model.jamfConnectionState == .connected
            ? "‘\(model.intent.scope.deviceGroupName)’ does not exactly match a loaded group."
            : "Connect to verify ‘\(model.intent.scope.deviceGroupName)’ against Jamf School."
    }

    private var matchingProfileDetail: String {
        guard model.jamfConnectionState == .connected else {
            return "Connect to check for an existing profile with this name."
        }
        if model.matchingJamfProfiles.isEmpty {
            return "No exact name match found in the loaded profiles."
        }
        return "Found \(model.matchingJamfProfiles.count) legacy exact name match\(model.matchingJamfProfiles.count == 1 ? "" : "es"). Automatic creation is blocked; migrate or remove it manually in Jamf School."
    }

    private var matchingBlueprintDetail: String {
        guard model.platformConnectionState == .connected else {
            return "Connect the Platform API beta to check managed blueprints."
        }
        switch model.matchingJamfBlueprints.count {
        case 0: return "No exact managed blueprint match; a new undeployed draft may be created."
        case 1: return "One exact match found; update it instead of creating a duplicate."
        default: return "Multiple exact matches found. Select and reconcile them individually before deployment."
        }
    }

    private func preflightRow(title: String, detail: String, isReady: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isReady ? .green : .orange)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
    }

    private func groupMetadata(_ group: JamfDeviceGroup) -> String {
        var details = ["ID \(group.id)"]
        if let members = group.members { details.append("\(members) member\(members == 1 ? "" : "s")") }
        if group.isSmartGroup == true { details.append("smart group") }
        return details.joined(separator: " · ")
    }

    private func profileMetadata(_ profile: JamfProfileSummary) -> String {
        ["ID \(profile.id)", profile.platform].compactMap { $0 }.joined(separator: " · ")
    }

    private func perform(_ action: BlueprintConfirmation) {
        Task {
            switch action {
            case .create: await model.createBlueprint()
            case .update: await model.updateSelectedBlueprint()
            case .deploy: await model.deploySelectedBlueprint()
            case .undeploy: await model.undeploySelectedBlueprint()
            case .delete: await model.deleteSelectedBlueprint()
            }
        }
    }
}

private enum BlueprintConfirmation: Identifiable {
    case create(name: String)
    case update(JamfBlueprintSummary)
    case deploy(JamfBlueprintSummary)
    case undeploy(JamfBlueprintSummary)
    case delete(JamfBlueprintSummary)

    var id: String {
        switch self {
        case .create(let name): "create-\(name)"
        case .update(let item): "update-\(item.id)"
        case .deploy(let item): "deploy-\(item.id)"
        case .undeploy(let item): "undeploy-\(item.id)"
        case .delete(let item): "delete-\(item.id)"
        }
    }

    var title: String {
        switch self {
        case .create: "Create blueprint draft?"
        case .update: "Update selected blueprint?"
        case .deploy: "Deploy selected blueprint?"
        case .undeploy: "Undeploy selected blueprint?"
        case .delete: "Permanently delete blueprint?"
        }
    }

    var buttonTitle: String {
        switch self {
        case .create: "Create draft"
        case .update: "Update"
        case .deploy: "Deploy"
        case .undeploy: "Undeploy"
        case .delete: "Delete"
        }
    }

    var isDestructive: Bool {
        switch self {
        case .undeploy, .delete: true
        default: false
        }
    }

    func message(groupName: String) -> String {
        switch self {
        case .create(let name):
            "Create an undeployed blueprint named ‘\(name)’ scoped to ‘\(groupName)’? Nothing will reach devices until a separate deploy confirmation."
        case .update(let item):
            "Replace the configuration and scope of ‘\(item.name)’ with the current local draft? This does not bypass the separate deployment control."
        case .deploy(let item):
            "Deploy ‘\(item.name)’ to its configured device group? Managed settings may change on devices."
        case .undeploy(let item):
            "Undeploy ‘\(item.name)’? Its managed configuration may be removed from scoped devices."
        case .delete(let item):
            "Permanently delete the undeployed blueprint ‘\(item.name)’? This cannot be undone by MDM Profile Builder Demo."
        }
    }
}

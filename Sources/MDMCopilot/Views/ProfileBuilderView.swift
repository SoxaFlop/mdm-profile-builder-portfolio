import SwiftUI

struct ProfileBuilderView: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    @State private var restrictionSearch = ""
    @State private var showConfiguredRestrictionsOnly = false
    @State private var expandedRestrictionCategories: Set<RestrictionCategory> = [
        .accountIdentity,
        .appsInstallation,
        .networkSharing,
        .securityPrivacy
    ]
    @State private var validationDetailsExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Build profile")
                            .font(.title2.bold())
                        Text("Changes compile locally as you work.")
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("Profile") {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                        GridRow {
                            Text("Name")
                                .gridColumnAlignment(.trailing)
                            TextField("e.g. Grade 7 iPad restrictions", text: $model.intent.name)
                        }
                        GridRow {
                            Text("Description")
                            TextField("e.g. Prevents account changes during class", text: $model.intent.profileDescription)
                        }
                        GridRow {
                            Text("Organisation")
                            TextField("e.g. Demo Organisation (optional)", text: $model.intent.organisation)
                        }
                        GridRow {
                            Text("Platform")
                            Picker("Platform", selection: $model.intent.platform) {
                                ForEach(ManagedPlatform.allCases) { platform in
                                    Text(platform.rawValue).tag(platform)
                                }
                            }
                            .labelsHidden()
                        }
                        GridRow {
                            Text("Target group")
                            targetGroupControl
                        }
                    }
                    .padding(.top, 6)

                    Toggle("Target iPads are supervised", isOn: $model.intent.devicesAreSupervised)
                        .padding(.top, 12)
                }

                ValidationSummaryView(isExpanded: $validationDetailsExpanded)

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Use a Jamf School time filter", isOn: timeFilterEnabledBinding)

                        if let timeFilter = model.intent.jamfTimeFilter {
                            Text("This controls when Jamf School should make the profile active. It is not included in the Apple .mobileconfig file.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("Jamf queues the profile at the start time; an iPad must check in before it receives the change. Pilot the schedule with a small group first.")
                                .font(.caption2)
                                .foregroundStyle(.orange)

                            HStack(spacing: 6) {
                                ForEach(JamfWeekday.allCases) { day in
                                    if timeFilter.activeDays.contains(day) {
                                        Button(day.shortTitle) { toggleTimeFilterDay(day) }
                                            .buttonStyle(.borderedProminent)
                                            .controlSize(.small)
                                    } else {
                                        Button(day.shortTitle) { toggleTimeFilterDay(day) }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                    }
                                }
                            }

                            Toggle("Active all day", isOn: timeFilterBinding(\.isActiveAllDay))

                            if !timeFilter.isActiveAllDay {
                                HStack {
                                    DatePicker("Start", selection: timeBinding(for: \.startTime), displayedComponents: .hourAndMinute)
                                    DatePicker("End", selection: timeBinding(for: \.endTime), displayedComponents: .hourAndMinute)
                                }
                            }

                            Toggle(
                                "Disable on holidays configured in Jamf School",
                                isOn: timeFilterBinding(\.disableOnConfiguredHolidays)
                            )

                            Text(timeFilter.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Label("Jamf School schedule", systemImage: "calendar.badge.clock")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top) {
                            Text("Create personal or enterprise Wi-Fi payloads. The assistant can start the payload and ask for missing information.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(action: model.addWiFiPayload) {
                                Label("Add Wi-Fi", systemImage: "plus")
                            }
                        }

                        if model.intent.wifiPayloads.isEmpty {
                            ContentUnavailableView(
                                "No Wi-Fi payloads",
                                systemImage: "wifi",
                                description: Text("Add one here or ask the assistant to create a network profile.")
                            )
                            .frame(minHeight: 130)
                        }

                        ForEach($model.intent.wifiPayloads) { $wifi in
                            WiFiPayloadEditor(wifi: $wifi) {
                                model.removeWiFiPayload(id: wifi.id)
                            }
                            if wifi.id != model.intent.wifiPayloads.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Wi-Fi networks", systemImage: "wifi")
                }

                GroupBox("iPad Dock") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("This generates Apple's managed Home Screen Layout payload.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach([DockItem.classroom, .safari]) { item in
                            Toggle(item.displayName, isOn: dockBinding(for: item))
                        }
                    }
                    .padding(.top, 4)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            TextField("Search restrictions", text: $restrictionSearch)
                                .textFieldStyle(.roundedBorder)
                            Toggle("Configured only", isOn: $showConfiguredRestrictionsOnly)
                                .toggleStyle(.checkbox)
                        }

                        Text("\(RestrictionCatalogue.iPadOS.count) current iPadOS boolean restrictions from \(RestrictionCatalogue.schemaVersion). Search by feature, category or Apple payload key.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if filteredRestrictions.isEmpty {
                            ContentUnavailableView(
                                "No matching restrictions",
                                systemImage: "line.3.horizontal.decrease.circle",
                                description: Text("Change the search or show all restrictions.")
                            )
                            .frame(minHeight: 120)
                        }

                        LazyVStack(spacing: 8) {
                            ForEach(filteredRestrictionGroups) { group in
                                DisclosureGroup(isExpanded: categoryExpansionBinding(for: group.category)) {
                                    VStack(spacing: 0) {
                                        ForEach(Array(group.definitions.enumerated()), id: \.element.id) { index, definition in
                                            RestrictionRow(definition: definition)
                                            if index < group.definitions.count - 1 {
                                                Divider()
                                            }
                                        }
                                    }
                                    .padding(.top, 4)
                                } label: {
                                    HStack {
                                        Label(group.category.title, systemImage: group.category.systemImage)
                                        Spacer()
                                        Text(group.summary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .padding(10)
                                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Label("Restrictions catalogue", systemImage: "switch.2")
                }
            }
            .padding(18)
        }
    }

    private func dockBinding(for item: DockItem) -> Binding<Bool> {
        Binding(
            get: { model.intent.dockItems.contains(item) },
            set: { model.setDockItem(item, isIncluded: $0) }
        )
    }

    private var timeFilterEnabledBinding: Binding<Bool> {
        Binding(
            get: { model.intent.jamfTimeFilter != nil },
            set: { enabled in
                var updated = model.intent
                updated.jamfTimeFilter = enabled ? .afterSchoolWeekdays : nil
                model.intent = updated
            }
        )
    }

    private func timeFilterBinding<Value>(
        _ keyPath: WritableKeyPath<JamfTimeFilter, Value>
    ) -> Binding<Value> {
        Binding(
            get: { model.intent.jamfTimeFilter![keyPath: keyPath] },
            set: { value in
                var updated = model.intent
                updated.jamfTimeFilter![keyPath: keyPath] = value
                model.intent = updated
            }
        )
    }

    private func timeBinding(for keyPath: WritableKeyPath<JamfTimeFilter, JamfTimeOfDay>) -> Binding<Date> {
        Binding(
            get: {
                let time = model.intent.jamfTimeFilter![keyPath: keyPath]
                return Calendar.current.date(from: DateComponents(hour: time.hour, minute: time.minute)) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                var updated = model.intent
                updated.jamfTimeFilter![keyPath: keyPath] = JamfTimeOfDay(
                    hour: components.hour ?? 0,
                    minute: components.minute ?? 0
                )
                model.intent = updated
            }
        )
    }

    private func toggleTimeFilterDay(_ day: JamfWeekday) {
        var updated = model.intent
        if updated.jamfTimeFilter!.activeDays.contains(day) {
            updated.jamfTimeFilter!.activeDays.remove(day)
        } else {
            updated.jamfTimeFilter!.activeDays.insert(day)
        }
        model.intent = updated
    }

    @ViewBuilder
    private var targetGroupControl: some View {
        if model.jamfConnectionState == .connected, !model.jamfDeviceGroups.isEmpty {
            Picker("Target group", selection: selectedGroupBinding) {
                Text("Select a Jamf School device group…")
                    .tag(Int?.none)
                ForEach(model.jamfDeviceGroups) { group in
                    Text(group.name)
                        .tag(Optional(group.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        } else {
            TextField(targetGroupPlaceholder, text: .constant(""))
                .disabled(true)
        }
    }

    private var selectedGroupBinding: Binding<Int?> {
        Binding(
            get: {
                guard let groupID = model.intent.scope.deviceGroupID,
                      model.jamfDeviceGroups.contains(where: { $0.id == groupID }) else {
                    return nil
                }
                return groupID
            },
            set: { groupID in
                if let groupID {
                    model.selectJamfDeviceGroup(id: groupID)
                } else {
                    model.clearJamfDeviceGroupSelection()
                }
            }
        )
    }

    private var targetGroupPlaceholder: String {
        switch model.jamfConnectionState {
        case .notConfigured:
            "Connect Jamf School to choose a device group"
        case .connecting:
            "Synchronising Jamf School device groups…"
        case .failed:
            "Reconnect Jamf School to load device groups"
        case .connected:
            "No device groups found in Jamf School"
        }
    }

    private var filteredRestrictions: [RestrictionDefinition] {
        let query = restrictionSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return RestrictionCatalogue.iPadOS.filter { definition in
            let matchesConfiguration = !showConfiguredRestrictionsOnly ||
                (model.intent.restrictions[definition.key] ?? .unchanged) != .unchanged
            let matchesSearch = query.isEmpty ||
                definition.category.title.lowercased().contains(query) ||
                definition.title.lowercased().contains(query) ||
                definition.key.rawValue.lowercased().contains(query) ||
                definition.searchTerms.contains(where: { $0.contains(query) })
            return matchesConfiguration && matchesSearch
        }
    }

    private var filteredRestrictionGroups: [RestrictionGroup] {
        RestrictionCategory.allCases.compactMap { category in
            let definitions = filteredRestrictions.filter { $0.category == category }
            guard !definitions.isEmpty else { return nil }
            return RestrictionGroup(
                category: category,
                definitions: definitions,
                configuredCount: definitions.filter {
                    (model.intent.restrictions[$0.key] ?? .unchanged) != .unchanged
                }.count
            )
        }
    }

    private func categoryExpansionBinding(for category: RestrictionCategory) -> Binding<Bool> {
        Binding(
            get: {
                !restrictionSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    expandedRestrictionCategories.contains(category)
            },
            set: { expanded in
                if expanded {
                    expandedRestrictionCategories.insert(category)
                } else {
                    expandedRestrictionCategories.remove(category)
                }
            }
        )
    }
}

private struct RestrictionGroup: Identifiable {
    let category: RestrictionCategory
    let definitions: [RestrictionDefinition]
    let configuredCount: Int

    var id: RestrictionCategory { category }

    var summary: String {
        if configuredCount > 0 {
            return "\(configuredCount) configured · \(definitions.count) shown"
        }
        return "\(definitions.count) shown"
    }
}

private enum RestrictionCategory: String, CaseIterable, Identifiable {
    case accountIdentity
    case appsInstallation
    case networkSharing
    case securityPrivacy
    case iCloudData
    case siriIntelligence
    case classroomEducation
    case safariWeb
    case mediaGameCenter
    case deviceSettings
    case systemRequirements
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accountIdentity: "Account and identity"
        case .appsInstallation: "Apps and installation"
        case .networkSharing: "Network and sharing"
        case .securityPrivacy: "Security and privacy"
        case .iCloudData: "iCloud and data movement"
        case .siriIntelligence: "Siri and intelligence"
        case .classroomEducation: "Classroom and education"
        case .safariWeb: "Safari and web"
        case .mediaGameCenter: "Media and Game Centre"
        case .deviceSettings: "Device settings"
        case .systemRequirements: "System requirements"
        case .other: "Other restrictions"
        }
    }

    var systemImage: String {
        switch self {
        case .accountIdentity: "person.crop.circle"
        case .appsInstallation: "app.badge"
        case .networkSharing: "network"
        case .securityPrivacy: "lock.shield"
        case .iCloudData: "icloud"
        case .siriIntelligence: "brain.head.profile"
        case .classroomEducation: "graduationcap"
        case .safariWeb: "safari"
        case .mediaGameCenter: "gamecontroller"
        case .deviceSettings: "gearshape"
        case .systemRequirements: "checkmark.shield"
        case .other: "ellipsis.circle"
        }
    }
}

private extension RestrictionDefinition {
    var category: RestrictionCategory {
        let key = key.rawValue.lowercased()
        let text = ([title, summary] + searchTerms).joined(separator: " ").lowercased()

        if containsAny(["account", "apple id", "apple account", "icloud account", "managed apple account"], in: text) {
            return .accountIdentity
        }
        if containsAny(["app installation", "app store", "app removal", "apps", "marketplace", "web distribution", "app clips", "in app purchases", "enterprise app"], in: text) {
            return .appsInstallation
        }
        if containsAny(["airdrop", "airprint", "wi-fi", "wifi", "bluetooth", "cellular", "hotspot", "vpn", "network", "host pairing", "usb", "satellite"], in: text) {
            return .networkSharing
        }
        if containsAny(["icloud", "cloud", "backup", "keychain", "managed", "unmanaged", "documents", "photo library", "private relay"], in: text) {
            return .iCloudData
        }
        if containsAny(["siri", "assistant", "apple intelligence", "genmoji", "image playground", "image wand", "writing tools", "dictation", "translation", "external intelligence"], in: text) {
            return .siriIntelligence
        }
        if containsAny(["classroom", "screen observation", "remote screen", "shared device", "temporary session"], in: text) {
            return .classroomEducation
        }
        if key.hasPrefix("safari") || containsAny(["safari", "browser", "web clip", "javascript", "pop-up", "popup"], in: text) {
            return .safariWeb
        }
        if containsAny(["game center", "itunes", "music", "podcasts", "bookstore", "news", "explicit", "video conferencing", "multiplayer"], in: text) {
            return .mediaGameCenter
        }
        if containsAny(["modification", "wallpaper", "device name", "diagnostic", "erase", "esim", "touch id", "fingerprint", "default browser", "default calling", "default messaging", "notifications"], in: text) {
            return .deviceSettings
        }
        if key.hasPrefix("force") || key.hasPrefix("require") || containsAny(["require", "force", "automatic date", "pasteboard"], in: text) {
            return .systemRequirements
        }
        if containsAny(["passcode", "password", "camera", "screenshot", "screen shot", "lock screen", "unlock", "nfc", "privacy", "trust", "tls"], in: text) {
            return .securityPrivacy
        }
        return .other
    }

    private func containsAny(_ needles: [String], in haystack: String) -> Bool {
        needles.contains { haystack.contains($0) }
    }
}

private struct WiFiPayloadEditor: View {
    @Binding var wifi: WiFiPayloadIntent
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(wifi.ssid.isEmpty ? "New Wi-Fi network" : wifi.ssid)
                    .font(.headline)
                Spacer()
                Button("Remove", role: .destructive, action: remove)
                    .buttonStyle(.borderless)
            }

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                GridRow {
                    Text("SSID")
                    TextField("Case-sensitive network name", text: $wifi.ssid)
                }
                GridRow {
                    Text("Authentication")
                    Picker("Authentication", selection: $wifi.authenticationType) {
                        ForEach(WiFiAuthenticationType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Security")
                    Picker("Security", selection: $wifi.securityType) {
                        Text("Select security type…").tag(WiFiSecurityType?.none)
                        ForEach(WiFiSecurityType.allCases) { type in
                            Text(type.title).tag(Optional(type))
                        }
                    }
                    .labelsHidden()
                }
                if wifi.authenticationType == .personal,
                   wifi.securityType?.requiresCredential == true {
                    GridRow {
                        Text("Password")
                        SecureField("Required", text: $wifi.password)
                    }
                }
            }

            if wifi.authenticationType == .enterprise {
                enterpriseEditor
            }

            DisclosureGroup("Advanced network options") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Join this network automatically", isOn: $wifi.autoJoin)
                    Toggle("Hidden network", isOn: $wifi.hiddenNetwork)
                    Toggle("Disable private Wi-Fi address for this network", isOn: $wifi.disableMACAddressRandomisation)

                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                        GridRow {
                            Text("Proxy")
                            Picker("Proxy", selection: $wifi.proxy.type) {
                                ForEach(WiFiProxyType.allCases) { type in
                                    Text(type.title).tag(type)
                                }
                            }
                            .labelsHidden()
                        }
                        if wifi.proxy.type == .manual {
                            GridRow {
                                Text("Proxy server")
                                TextField("proxy.example.org", text: $wifi.proxy.server)
                            }
                            GridRow {
                                Text("Proxy port")
                                TextField("8080", text: proxyPortBinding)
                            }
                            GridRow {
                                Text("Proxy username")
                                TextField("Optional", text: $wifi.proxy.username)
                            }
                            GridRow {
                                Text("Proxy password")
                                SecureField("Optional", text: $wifi.proxy.password)
                            }
                        } else if wifi.proxy.type == .automatic {
                            GridRow {
                                Text("PAC URL")
                                TextField("https://example.org/proxy.pac", text: $wifi.proxy.pacURL)
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }

            Label(
                "Passwords are kept in memory, omitted from saved draft data and redacted from the preview. The exported profile necessarily contains the credentials needed by the device.",
                systemImage: "lock.shield"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private var enterpriseEditor: some View {
        GroupBox("Enterprise authentication") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Select only the EAP methods supplied by the network administrator.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 115))], alignment: .leading) {
                    ForEach(WiFiEAPType.allCases) { type in
                        Toggle(type.title, isOn: eapBinding(for: type))
                            .toggleStyle(.checkbox)
                    }
                }

                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                    GridRow {
                        Text("Username")
                        TextField("Optional or Jamf variable", text: $wifi.enterprise.username)
                    }
                    GridRow {
                        Text("Password")
                        SecureField("Optional for certificate-based EAP", text: $wifi.enterprise.password)
                    }
                    GridRow {
                        Text("Outer identity")
                        TextField("Optional anonymous identity", text: $wifi.enterprise.outerIdentity)
                    }
                    GridRow {
                        Text("Trusted servers")
                        TextField("radius1.example.org, radius2.example.org", text: trustedServersBinding)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func eapBinding(for type: WiFiEAPType) -> Binding<Bool> {
        Binding(
            get: { wifi.enterprise.acceptedEAPTypes.contains(type) },
            set: { enabled in
                wifi.enterprise.acceptedEAPTypes.removeAll { $0 == type }
                if enabled { wifi.enterprise.acceptedEAPTypes.append(type) }
            }
        )
    }

    private var trustedServersBinding: Binding<String> {
        Binding(
            get: { wifi.enterprise.trustedServerNames.joined(separator: ", ") },
            set: { value in
                wifi.enterprise.trustedServerNames = value
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    private var proxyPortBinding: Binding<String> {
        Binding(
            get: { wifi.proxy.port.map(String.init) ?? "" },
            set: { wifi.proxy.port = Int($0.filter(\.isNumber)) }
        )
    }
}

private struct RestrictionRow: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    let definition: RestrictionDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(definition.title)
                        .fontWeight(.medium)
                    Text(definition.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Picker(definition.title, selection: restrictionBinding) {
                    ForEach(RestrictionState.allCases) { state in
                        Text(definition.label(for: state)).tag(state)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 245)
            }

            Text("\(definition.minimumOS) · Supervision: \(definition.supervision.rawValue)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
    }

    private var restrictionBinding: Binding<RestrictionState> {
        Binding(
            get: { model.intent.restrictions[definition.key] ?? .unchanged },
            set: { model.setRestriction(definition.key, state: $0) }
        )
    }
}

private struct ValidationSummaryView: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: expandedBinding) {
            VStack(alignment: .leading, spacing: 10) {
                if !model.validationIssues.isEmpty {
                    ForEach(model.validationIssues) { issue in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: icon(for: issue.severity))
                                .foregroundStyle(colour(for: issue.severity))
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(issue.title).fontWeight(.medium)
                                Text(issue.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                } else {
                    Text("This draft currently has no validation findings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Label("Validation", systemImage: validationIcon)
                    .foregroundStyle(validationColour)
                Spacer()
                Text(validationSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .onChange(of: validationIssueSignature) { _, _ in
            if hasValidationErrors {
                isExpanded = true
            }
        }
    }

    private var expandedBinding: Binding<Bool> {
        Binding(
            get: { isExpanded || hasValidationErrors },
            set: { isExpanded = $0 }
        )
    }

    private var validationIssueSignature: String {
        model.validationIssues.map { "\($0.severity)-\($0.title)-\($0.detail)" }.joined(separator: "|")
    }

    private var hasValidationErrors: Bool {
        model.validationIssues.contains { $0.severity == .error }
    }

    private var validationSummary: String {
        let errors = model.validationIssues.filter { $0.severity == .error }.count
        let warnings = model.validationIssues.filter { $0.severity == .warning }.count
        let notes = model.validationIssues.filter { $0.severity == .information }.count
        if errors > 0 {
            return "\(errors) error\(errors == 1 ? "" : "s")"
        }
        if warnings > 0 {
            return "\(warnings) warning\(warnings == 1 ? "" : "s")"
        }
        if notes > 0 {
            return "\(notes) note\(notes == 1 ? "" : "s")"
        }
        return "No findings"
    }

    private var validationIcon: String {
        if model.validationIssues.contains(where: { $0.severity == .error }) {
            return "xmark.octagon.fill"
        }
        if model.validationIssues.contains(where: { $0.severity == .warning }) {
            return "exclamationmark.triangle.fill"
        }
        return "checkmark.circle.fill"
    }

    private var validationColour: Color {
        if model.validationIssues.contains(where: { $0.severity == .error }) {
            return .red
        }
        if model.validationIssues.contains(where: { $0.severity == .warning }) {
            return .orange
        }
        return .green
    }

    private func icon(for severity: ValidationSeverity) -> String {
        switch severity {
        case .error: "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .information: "info.circle.fill"
        }
    }

    private func colour(for severity: ValidationSeverity) -> Color {
        switch severity {
        case .error: .red
        case .warning: .orange
        case .information: .blue
        }
    }
}

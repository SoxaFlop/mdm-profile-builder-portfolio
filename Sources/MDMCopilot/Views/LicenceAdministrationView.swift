import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LicenceAdministrationView: View {
    private enum Page: String, CaseIterable, Identifiable {
        case users = "Users"
        case issue = "Issue access"

        var id: Self { self }
    }

    @EnvironmentObject private var access: AccessController
    @Environment(\.dismiss) private var dismiss
    @State private var page: Page = .users
    @State private var selectedLicenceID: UUID?
    @State private var searchText = ""
    @State private var editedName = ""
    @State private var editedNotes = ""
    @State private var subject = ""
    @State private var installationRequest = ""
    @State private var generatedCode = ""
    @State private var showingIssuerKeyImporter = false
    @State private var showingRevocationConfirmation = false
    @State private var statusMessage = "View centrally registered licences or generate a new annual code."
    @State private var statusIsError = false
    @State private var isWorking = false

    private var requestCheck: InstallationRequestCheck {
        access.checkInstallationRequest(installationRequest)
    }

    private var filteredLicences: [IssuedLicenceRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return access.issuedLicences }
        return access.issuedLicences.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.signedSubject.localizedCaseInsensitiveContains(query)
                || $0.installationID.uuidString.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedLicence: IssuedLicenceRecord? {
        access.issuedLicences.first { $0.id == selectedLicenceID }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Picker("Licence administration page", selection: $page) {
                ForEach(Page.allCases) { page in
                    Text(page.rawValue).tag(page)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)
            .padding(14)

            Divider()

            switch page {
            case .users:
                userDirectory
            case .issue:
                issueAccessForm
            }

            Divider()
            statusBar
        }
        .frame(width: 980, height: 760)
        .fileImporter(
            isPresented: $showingIssuerKeyImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: importIssuerKey
        )
        .confirmationDialog(
            "Remove access for \(selectedLicence?.displayName ?? "this user")?",
            isPresented: $showingRevocationConfirmation,
            titleVisibility: .visible
        ) {
            Button("Mark licence revoked", role: .destructive) {
                revokeSelectedLicence()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if access.distributionPolicy.requiresCentralLicenceService {
                Text("This publishes the revocation to the central licence service. A running user app will lock when its current signed lease expires, normally within 15 minutes.")
            } else {
                Text("This records the revocation on this administrator Mac only. The user's existing code will continue working until it expires.")
            }
        }
        .onAppear {
            if selectedLicenceID == nil {
                selectedLicenceID = access.issuedLicences.first?.id
            }
            loadSelectedLicenceForEditing()
            #if DEBUG
            if installationRequest.isEmpty,
               access.activeLicence?.subject == "Local development administrator" {
                installationRequest = access.installationRequestCode
            }
            #endif
            if let directoryError = access.licenceDirectoryError {
                statusMessage = directoryError
                statusIsError = true
            }
            if access.distributionPolicy.requiresCentralLicenceService {
                refreshDirectory()
            }
        }
        .onChange(of: selectedLicenceID) { _, _ in
            loadSelectedLicenceForEditing()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Licence administration")
                    .font(.title2.bold())
                Text("View issued users, licence dates, edits, renewals and revocations")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(20)
    }

    private var userDirectory: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label(
                    "\(access.issuedLicences.count) issued licence\(access.issuedLicences.count == 1 ? "" : "s")",
                    systemImage: "person.2"
                )
                .font(.headline)
                if access.distributionPolicy.requiresCentralLicenceService {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        refreshDirectory()
                    }
                    .disabled(isWorking)
                }
                Spacer()
                TextField("Search users or installation ID", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                Button("Issue new access", systemImage: "plus") {
                    page = .issue
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(14)

            Divider()

            if access.issuedLicences.isEmpty {
                ContentUnavailableView {
                    Label("No issued users yet", systemImage: "person.crop.circle.badge.plus")
                } description: {
                    Text(access.distributionPolicy.requiresCentralLicenceService
                        ? "Centrally registered user licences will appear here with their issue and expiry dates."
                        : "Licences generated on this administrator Mac will appear here with their issue and expiry dates.")
                } actions: {
                    Button("Issue the first licence") { page = .issue }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    licenceList
                        .frame(minWidth: 310, idealWidth: 350, maxWidth: 390)
                    licenceDetail
                        .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var licenceList: some View {
        List(selection: $selectedLicenceID) {
            ForEach(filteredLicences) { record in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(record.displayName)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        statusBadge(for: record)
                    }
                    HStack(spacing: 5) {
                        Image(systemName: "calendar")
                        Text(expirySummary(for: record))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 5)
                .tag(record.id)
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if filteredLicences.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    @ViewBuilder
    private var licenceDetail: some View {
        if let record = selectedLicence {
            Form {
                Section("User record") {
                    TextField("User or organisation", text: $editedName)
                    TextField("Notes (optional)", text: $editedNotes, axis: .vertical)
                        .lineLimit(2...4)

                    if editedName.trimmingCharacters(in: .whitespacesAndNewlines) != record.signedSubject {
                        Label(
                            "The signed code still names “\(record.signedSubject)”. Reissue the licence to apply the edited name to a new code.",
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Button("Save record changes", systemImage: "square.and.arrow.down") {
                        saveSelectedLicence()
                    }
                    .disabled(isWorking || editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("Licence") {
                    LabeledContent("Status") { statusBadge(for: record) }
                    LabeledContent("Role", value: record.role.title)
                    LabeledContent("Issued", value: record.issuedAt.formatted(date: .long, time: .shortened))
                    LabeledContent(
                        "Expires",
                        value: record.expiresAt?.formatted(date: .long, time: .shortened) ?? "No expiry"
                    )
                    if let revokedAt = record.revokedAt {
                        LabeledContent("Revoked", value: revokedAt.formatted(date: .long, time: .shortened))
                    }
                    if let replacementID = record.replacedByLicenceID {
                        LabeledContent("Replacement ID", value: replacementID.uuidString.lowercased())
                            .textSelection(.enabled)
                    }
                }

                Section("Bound installation") {
                    Text(record.installationID.uuidString.lowercased())
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Text("An access code works only on this installation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Actions") {
                    HStack {
                        Button("Copy access code", systemImage: "doc.on.doc") {
                            copyToPasteboard(record.accessCode)
                            statusMessage = "The stored access code was copied. Send it only to the intended user."
                            statusIsError = false
                        }
                        .disabled(record.accessCode.isEmpty)

                        Button("Reissue for one year", systemImage: "arrow.clockwise") {
                            reissueSelectedLicence()
                        }
                        .disabled(isWorking || record.state != .active)

                        Spacer()

                        Button("Remove access", systemImage: "person.crop.circle.badge.minus", role: .destructive) {
                            showingRevocationConfirmation = true
                        }
                        .disabled(isWorking || record.state != .active)
                    }

                    Text(access.distributionPolicy.requiresCentralLicenceService
                        ? "Reissuing replaces the current central record and creates a new signed code for the same Mac. Removing access publishes a central revocation that is enforced when the user's current lease expires. Codes issued by another administrator are not copied between Macs, but they can still be reissued or revoked here."
                        : "Reissuing replaces this local directory record. Removing access is local only in this development build.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !generatedCode.isEmpty {
                    Section("Latest generated access code") {
                        TextEditor(text: .constant(generatedCode))
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 100)
                            .textSelection(.enabled)
                        Button("Copy latest code", systemImage: "doc.on.doc") {
                            copyToPasteboard(generatedCode)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView(
                "Select a user",
                systemImage: "person.crop.circle",
                description: Text("Choose an issued licence to view and manage its details.")
            )
        }
    }

    private var issueAccessForm: some View {
        Form {
            Section("Issuer key") {
                LabeledContent("Status") {
                    Label(
                        access.issuerKeyInstalled ? "Installed in Keychain" : "Not installed",
                        systemImage: access.issuerKeyInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(access.issuerKeyInstalled ? .green : .orange)
                }

                if !access.issuerKeyInstalled {
                    Button("Import issuer key file…", systemImage: "key.viewfinder") {
                        showingIssuerKeyImporter = true
                    }
                }

                Text(access.distributionPolicy.requiresCentralLicenceService
                    ? "The private signing key stays in this Mac's Keychain. User status and licence dates are synchronised through the central service; access-code copies remain only on the administrator Mac that issued them."
                    : "The private signing key and issued-user directory stay in this Mac's Keychain. They are not included in user codes or source control.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Recipient") {
                TextField("Recipient name or organisation (required)", text: $subject)
                TextEditor(text: $installationRequest)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 90)
                    .overlay(alignment: .topLeading) {
                        if installationRequest.isEmpty {
                            Text("Paste the user's MDMR1 installation request code")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    }

                HStack {
                    Button("Paste request code", systemImage: "doc.on.clipboard") {
                        installationRequest = NSPasteboard.general.string(forType: .string) ?? ""
                    }
                    #if DEBUG
                    Button("Use this Mac for testing") {
                        installationRequest = access.installationRequestCode
                    }
                    #endif
                }

                Label(
                    requestCheck.message,
                    systemImage: requestCheck.isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(requestCheck.isValid ? .green : .orange)
                .textSelection(.enabled)

                Button("Generate one-year access code", systemImage: "key.horizontal.fill") {
                    issueLicence()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    isWorking
                        || !access.issuerKeyInstalled
                        || !requestCheck.isValid
                        || subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }

            if !generatedCode.isEmpty {
                Section("Generated annual access code") {
                    TextEditor(text: .constant(generatedCode))
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 120)
                        .textSelection(.enabled)
                    HStack {
                        Button("Copy access code", systemImage: "doc.on.doc") {
                            copyToPasteboard(generatedCode)
                        }
                        Button("View issued user", systemImage: "person.text.rectangle") {
                            selectedLicenceID = access.issuedLicences.first?.id
                            page = .users
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var statusBar: some View {
        HStack(spacing: 9) {
            if isWorking {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: statusIsError ? "exclamationmark.triangle.fill" : "info.circle")
            }
            Text(statusMessage)
                .foregroundStyle(statusIsError ? .red : .secondary)
                .lineLimit(2)
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func statusBadge(for record: IssuedLicenceRecord) -> some View {
        let status = record.status(at: Date())
        return Text(status)
            .font(.caption.weight(.semibold))
            .foregroundStyle(statusColour(status))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColour(status).opacity(0.12), in: Capsule())
    }

    private func statusColour(_ status: String) -> Color {
        switch status {
        case "Active": .green
        case "Expired": .orange
        default: .secondary
        }
    }

    private func expirySummary(for record: IssuedLicenceRecord) -> String {
        guard let expiry = record.expiresAt else { return "No expiry" }
        return "Expires \(expiry.formatted(date: .abbreviated, time: .omitted))"
    }

    private func loadSelectedLicenceForEditing() {
        guard let record = selectedLicence else {
            editedName = ""
            editedNotes = ""
            return
        }
        editedName = record.displayName
        editedNotes = record.notes
    }

    private func saveSelectedLicence() {
        guard let id = selectedLicenceID else { return }
        isWorking = true
        statusIsError = false
        statusMessage = "Updating the user record…"
        Task {
            defer { isWorking = false }
            do {
                try await access.updateIssuedLicence(id: id, displayName: editedName, notes: editedNotes)
                statusMessage = "User record updated. Reissue the licence if the edited name must be included in a new signed code."
                statusIsError = false
            } catch {
                statusMessage = error.localizedDescription
                statusIsError = true
            }
        }
    }

    private func refreshDirectory() {
        guard access.distributionPolicy.requiresCentralLicenceService else { return }
        isWorking = true
        statusIsError = false
        statusMessage = "Refreshing the central issued-user directory…"
        Task {
            defer { isWorking = false }
            await access.refreshIssuedLicenceDirectory()
            if let error = access.licenceDirectoryError {
                statusMessage = error
                statusIsError = true
                return
            }
            if selectedLicenceID == nil
                || !access.issuedLicences.contains(where: { $0.id == selectedLicenceID }) {
                selectedLicenceID = access.issuedLicences.first?.id
            }
            statusMessage = "Central directory refreshed."
            statusIsError = false
        }
    }

    private func issueLicence() {
        isWorking = true
        statusIsError = false
        statusMessage = access.distributionPolicy.requiresCentralLicenceService
            ? "Signing and registering the annual access code with the central service…"
            : "Checking trusted time and signing the annual access code…"
        Task {
            defer { isWorking = false }
            do {
                generatedCode = try await access.issueAnnualLicence(
                    subject: subject,
                    requestCode: installationRequest
                )
                selectedLicenceID = access.issuedLicences.first?.id
                statusMessage = access.distributionPolicy.requiresCentralLicenceService
                    ? "Annual access code generated and registered centrally."
                    : "Annual access code generated and added to this Mac's issued-user directory."
                statusIsError = false
            } catch {
                generatedCode = ""
                statusMessage = error.localizedDescription
                statusIsError = true
            }
        }
    }

    private func reissueSelectedLicence() {
        guard let id = selectedLicenceID else { return }
        isWorking = true
        statusIsError = false
        statusMessage = access.distributionPolicy.requiresCentralLicenceService
            ? "Creating and registering the replacement licence…"
            : "Checking trusted time and reissuing annual access…"
        Task {
            defer { isWorking = false }
            do {
                generatedCode = try await access.reissueAnnualLicence(id: id, subject: editedName)
                selectedLicenceID = access.issuedLicences.first?.id
                statusMessage = "A new one-year code was created. Send it to the user; the previous licence is now marked as replaced."
                statusIsError = false
            } catch {
                statusMessage = error.localizedDescription
                statusIsError = true
            }
        }
    }

    private func revokeSelectedLicence() {
        guard let id = selectedLicenceID else { return }
        isWorking = true
        statusIsError = false
        statusMessage = access.distributionPolicy.requiresCentralLicenceService
            ? "Publishing the revocation to the central service…"
            : "Recording the local revocation using trusted time…"
        Task {
            defer { isWorking = false }
            do {
                try await access.revokeIssuedLicence(id: id)
                statusMessage = access.distributionPolicy.requiresCentralLicenceService
                    ? "Licence revoked centrally. A running user app will lock when its signed lease expires, normally within 15 minutes."
                    : "Licence marked as revoked in this administrator's local directory."
                statusIsError = false
            } catch {
                statusMessage = error.localizedDescription
                statusIsError = true
            }
        }
    }

    private func importIssuerKey(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess { url.stopAccessingSecurityScopedResource() }
            }
            try access.importIssuerPrivateKeyDocument(Data(contentsOf: url))
            statusMessage = "Issuer key imported into this Mac's Keychain. Securely archive or remove the external key file."
            statusIsError = false
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
        }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

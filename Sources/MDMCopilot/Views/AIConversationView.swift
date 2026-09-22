import SwiftUI
import UniformTypeIdentifiers

struct AIConversationView: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    @State private var secureWiFiPassword = ""
    @State private var composerText = ""
    @State private var isAttachmentImporterPresented = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Profile assistant")
                        .font(.headline)
                    Text(model.assistantDisplayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(model.assistantStatusDetail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(
                    model.isUsingExternalAI ? "External AI active" : (model.localModel.isGenerativeModelLoaded ? "Model loaded" : "Safe placeholder"),
                    systemImage: model.isUsingExternalAI ? "network" : (model.localModel.isGenerativeModelLoaded ? "cpu.fill" : "command")
                )
                .font(.caption)
                .foregroundStyle(model.isUsingExternalAI ? .orange : (model.localModel.isGenerativeModelLoaded ? .green : .blue))
            }
            .padding(16)

            if !model.isUsingExternalAI, model.supportsEnhancedModel, !model.isEnhancedModelReady {
                Divider()
                enhancedModelSetup
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.accentColor.opacity(0.06))
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Label(knowledgeStatusText, systemImage: "books.vertical")
                        .font(.caption)
                        .foregroundStyle(knowledgeStatusColour)
                    Spacer()
                    Button(knowledgeButtonTitle) {
                        Task { await model.jamfKnowledge.downloadOfficialDocumentation() }
                    }
                    .controlSize(.small)
                    .disabled(isKnowledgeDownloading)
                }
                if let progress = knowledgeProgress {
                    ProgressView(value: knowledgeFraction(progress))
                        .controlSize(.small)
                    Text(knowledgeProgressDetail(progress))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }
                        if model.isModelResponding {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Preparing a concise answer on-device…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: model.messages.count) { _, _ in
                    if let id = model.messages.last?.id {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                if let wifi = model.pendingWiFiPasswordPayload {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(
                                "Password required for \(wifi.ssid.isEmpty ? "this Wi-Fi network" : "‘\(wifi.ssid)’")",
                                systemImage: "lock.shield"
                            )
                            .font(.subheadline.weight(.semibold))

                            HStack {
                                SecureField("Wi-Fi password", text: $secureWiFiPassword)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit { saveWiFiPassword(for: wifi.id) }
                                Button("Save securely") {
                                    saveWiFiPassword(for: wifi.id)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(secureWiFiPassword.isEmpty)
                                Button("Leave unconfigured") {
                                    secureWiFiPassword = ""
                                    model.abandonWiFiDraft(id: wifi.id)
                                }
                            }

                            Text("The password stays in memory, is withheld from the model and is redacted from the payload preview.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        quickPrompt("Explain validation issues")
                        quickPrompt("Disable screenshots")
                        quickPrompt("Allow camera")
                        quickPrompt("Create a Wi-Fi profile")
                        quickPrompt("Remove Safari from the Dock")
                    }
                }

                attachmentTray

                HStack(alignment: .bottom, spacing: 10) {
                    TextField(
                        "Ask about or edit this profile…",
                        text: $composerText,
                        axis: .vertical
                    )
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(sendComposerMessage)

                    Button {
                        isAttachmentImporterPresented = true
                    } label: {
                        Label("Attach PDF or image", systemImage: "paperclip")
                    }
                    .help("Attach a PDF or screenshot for local text extraction")
                    .disabled(model.isProcessingAttachments)

                    Button(action: sendComposerMessage) {
                        Label("Send", systemImage: "arrow.up.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        model.isModelResponding ||
                        composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
            .padding(14)
        }
        .fileImporter(
            isPresented: $isAttachmentImporterPresented,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task { await model.addAssistantAttachments(urls) }
            case .failure(let error):
                model.recordAttachmentSelectionFailure(error)
            }
        }
    }

    @ViewBuilder
    private var enhancedModelSetup: some View {
        switch model.enhancedModelState {
        case .preparing(let progress):
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Downloading \(model.enhancedModelName)…")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text(progress.fractionCompleted.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: progress.fractionCompleted)
                Text(modelDownloadDetail(progress))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Enhanced model could not be loaded")
                        .font(.caption.weight(.semibold))
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Try again") {
                    Task { await model.prepareEnhancedModel() }
                }
            }
        case .available:
            HStack(spacing: 10) {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use the stronger \(model.enhancedModelName) model")
                        .font(.caption.weight(.semibold))
                    Text("Free and local. One-time download of \(model.enhancedModelDownloadDescription); no paid API or account.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Download and use") {
                    Task { await model.prepareEnhancedModel() }
                }
                .buttonStyle(.borderedProminent)
            }
        case .ready:
            EmptyView()
        }
    }

    private func quickPrompt(_ text: String) -> some View {
        Button(text) { model.useQuickPrompt(text) }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.isModelResponding)
    }

    @ViewBuilder
    private var attachmentTray: some View {
        if model.isProcessingAttachments || !model.assistantAttachments.isEmpty || model.attachmentStatusMessage != nil {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "paperclip")
                    Text(model.isProcessingAttachments ? "Reading attachment locally…" : "Attachments available to the assistant")
                        .font(.caption.weight(.medium))
                    Spacer()
                    if model.isProcessingAttachments {
                        ProgressView().controlSize(.small)
                    }
                }
                .foregroundStyle(.secondary)

                if !model.assistantAttachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(model.assistantAttachments) { attachment in
                                HStack(spacing: 4) {
                                    Image(systemName: attachment.kind == .pdf ? "doc.richtext" : "text.viewfinder")
                                    Text(attachment.filename)
                                        .lineLimit(1)
                                    Button {
                                        model.removeAssistantAttachment(id: attachment.id)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove \(attachment.filename)")
                                }
                                .font(.caption)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                            }
                        }
                    }
                }
                if let status = model.attachmentStatusMessage {
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text("Files stay on this Mac. PDFs provide extracted text; images use local OCR for visible text and error messages.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func saveWiFiPassword(for payloadID: UUID) {
        guard !secureWiFiPassword.isEmpty else { return }
        model.saveWiFiPassword(secureWiFiPassword, for: payloadID)
        secureWiFiPassword = ""
    }

    private func sendComposerMessage() {
        let prompt = composerText
        guard !model.isModelResponding,
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        composerText = ""
        model.sendMessage(prompt)
    }

    private var isKnowledgeDownloading: Bool {
        if case .downloading = model.jamfKnowledge.state { return true }
        return false
    }

    private var knowledgeButtonTitle: String {
        switch model.jamfKnowledge.state {
        case .notDownloaded: return "Download official Jamf knowledge"
        case .downloading(let progress):
            if let total = progress.totalDocuments {
                return "Downloading \(progress.completedDocuments)/\(total)"
            }
            return "Starting download…"
        case .ready: return "Refresh knowledge"
        case .failed: return "Try download again"
        }
    }

    private var knowledgeStatusText: String {
        switch model.jamfKnowledge.state {
        case .notDownloaded:
            return "Jamf School knowledge is not downloaded"
        case .downloading(let progress):
            switch progress.phase {
            case .findingDocuments:
                return "Finding official Jamf School documentation…"
            case .downloadingDocuments:
                guard let total = progress.totalDocuments else {
                    return "Preparing Jamf School knowledge download…"
                }
                return "Indexing Jamf School documentation: \(progress.completedDocuments)/\(total)"
            }
        case .ready(let documentCount, let updatedAt):
            return "\(documentCount) Jamf School documents stored locally · updated \(updatedAt.formatted(date: .abbreviated, time: .omitted))"
        case .failed(let message):
            return "Jamf knowledge download failed: \(message)"
        }
    }

    private var knowledgeStatusColour: Color {
        switch model.jamfKnowledge.state {
        case .failed: .orange
        case .ready: .green
        case .notDownloaded, .downloading: .secondary
        }
    }

    private var knowledgeProgress: JamfKnowledgeDownloadProgress? {
        if case .downloading(let progress) = model.jamfKnowledge.state { return progress }
        return nil
    }

    private func knowledgeFraction(_ progress: JamfKnowledgeDownloadProgress) -> Double {
        guard let total = progress.totalDocuments, total > 0 else { return 0.02 }
        let pageProgress = Double(progress.completedDocuments) / Double(total)
        guard let pageBytes = progress.currentDocumentTotalBytes, pageBytes > 0 else { return pageProgress }
        let currentPageProgress = Double(progress.currentDocumentBytes) / Double(pageBytes)
        return min(max(pageProgress + (currentPageProgress / Double(total)), 0), 1)
    }

    private func knowledgeProgressDetail(_ progress: JamfKnowledgeDownloadProgress) -> String {
        var details: [String] = []
        if progress.currentDocumentBytes > 0 {
            if let total = progress.currentDocumentTotalBytes {
                details.append("current page \(formattedBytes(progress.currentDocumentBytes)) of \(formattedBytes(total))")
            } else {
                details.append("current page \(formattedBytes(progress.currentDocumentBytes)) received")
            }
        }
        if let seconds = progress.estimatedSecondsRemaining {
            details.append("about \(formattedDuration(seconds)) remaining")
        } else if progress.phase == .findingDocuments {
            details.append("checking the official documentation index")
        } else {
            details.append("estimating time remaining after the first completed page")
        }
        return details.joined(separator: " · ")
    }

    private func modelDownloadDetail(_ progress: ModelDownloadProgress) -> String {
        var details: [String] = []
        if let completed = progress.completedBytes, let total = progress.totalBytes {
            details.append("\(formattedBytes(completed)) of \(formattedBytes(total))")
        } else {
            details.append("Preparing the download manifest and checking any cached model files")
        }
        if let speed = progress.bytesPerSecond, speed > 0 {
            details.append("\(formattedBytes(Int64(speed)))/s")
        }
        if let seconds = progress.estimatedSecondsRemaining {
            details.append("about \(formattedDuration(seconds)) remaining")
        } else if progress.fractionCompleted < 1 {
            details.append("time remaining will appear once data starts transferring")
        }
        return details.joined(separator: " · ")
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(bytes, 0), countStyle: .file)
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let wholeSeconds = max(Int(seconds.rounded()), 0)
        if wholeSeconds < 60 { return "less than a minute" }
        let minutes = wholeSeconds / 60
        let secondsRemainder = wholeSeconds % 60
        return minutes >= 60
            ? "\(minutes / 60)h \(minutes % 60)m"
            : "\(minutes)m \(secondsRemainder)s"
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .technician { Spacer(minLength: 70) }
            VStack(alignment: .leading, spacing: 8) {
                Text(message.text)
                    .textSelection(.enabled)

                if message.role == .assistant,
                   let details = message.details,
                   !details.isEmpty {
                    Divider()
                    DisclosureGroup {
                        Text(details)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(.top, 3)
                    } label: {
                        Label("Details", systemImage: "checklist")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .controlSize(.small)
                }
            }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    message.role == .technician ? Color.accentColor : Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .foregroundStyle(message.role == .technician ? .white : .primary)
            if message.role == .assistant { Spacer(minLength: 70) }
        }
        .frame(maxWidth: .infinity)
    }
}

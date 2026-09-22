import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PayloadPreviewView: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    @State private var exportError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple configuration profile")
                        .font(.headline)
                    Text("Unsigned XML · generated locally · secrets redacted in preview")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: copyPayload) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                Button(action: exportProfile) {
                    Label("Export .mobileconfig", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.compiledProfile == nil)
            }
            .padding(14)

            Divider()

            ScrollView([.horizontal, .vertical]) {
                Text(model.payloadPreview)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(16)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .alert(
            "Export failed",
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "Unknown error")
        }
    }

    private func copyPayload() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.payloadPreview, forType: .string)
    }

    private func exportProfile() {
        guard let profile = model.compiledProfile else { return }

        let panel = NSSavePanel()
        panel.title = "Export configuration profile"
        panel.nameFieldStringValue = profile.fileName
        panel.canCreateDirectories = true
        if let mobileconfig = UTType(filenameExtension: "mobileconfig") {
            panel.allowedContentTypes = [mobileconfig]
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try profile.data.write(to: url, options: .atomic)
        } catch {
            exportError = error.localizedDescription
        }
    }
}

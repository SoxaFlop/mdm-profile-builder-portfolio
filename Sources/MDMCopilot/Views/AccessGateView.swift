import AppKit
import SwiftUI

struct AccessGateView: View {
    @EnvironmentObject private var access: AccessController
    @State private var accessCode = ""

    var body: some View {
        Group {
            switch access.status {
            case .active:
                WorkspaceView()
            case .checking:
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Checking access…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .locked(let message):
                activationView(message: message)
            }
        }
        .task {
            await access.runVerificationLoop()
        }
    }

    private func activationView(message: String) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.blue)

                Text("\(AppBrand.displayName) access")
                    .font(.largeTitle.bold())
                Text("This is the \(access.distributionPolicy.edition.title.lowercased()) edition. It needs a matching signed access code. Send the request code below to your licence administrator, then paste the returned access code.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Label(message, systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Retry verification", systemImage: "arrow.clockwise") {
                    Task { await access.refreshAccess() }
                }

                Spacer()

                Text(access.distributionPolicy.requiresCentralLicenceService
                    ? "This packaged edition checks the central licence service every 10 minutes and uses a signed lease lasting no more than 15 minutes. Revoked, replaced or expired access is locked centrally, and disconnecting cannot create an indefinite offline bypass."
                    : "This development edition validates its signed access locally. Connected Release packages use the central licence service.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(42)
            .frame(minWidth: 420, idealWidth: 480, maxWidth: 520, maxHeight: .infinity, alignment: .topLeading)
            .background(.blue.opacity(0.06))

            Divider()

            Form {
                Section("Installation request code") {
                    TextEditor(text: .constant(access.installationRequestCode))
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 90)
                        .textSelection(.enabled)
                    Button("Copy request code", systemImage: "doc.on.doc") {
                        copy(access.installationRequestCode)
                    }
                }

                Section("Access code") {
                    TextEditor(text: $accessCode)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 150)
                    HStack {
                        Button("Paste") {
                            accessCode = NSPasteboard.general.string(forType: .string) ?? ""
                        }
                        Spacer()
                        Button("Activate") {
                            Task { await access.activate(code: accessCode) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(accessCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                #if DEBUG
                Section("Xcode development only") {
                    Text("Creates a local development issuer and permanent administrator. This option is compiled out of Release builds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Create administrator and open licence setup") {
                        Task { await access.createDevelopmentAdministrator() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                #endif
            }
            .formStyle(.grouped)
            .padding(30)
            .frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1_000, minHeight: 680)
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

struct AccessSettingsGateView: View {
    @EnvironmentObject private var access: AccessController

    var body: some View {
        if access.activeLicence != nil {
            ConnectionSettingsView()
                .frame(width: 640, height: 760)
        } else {
            ContentUnavailableView(
                "Access required",
                systemImage: "lock.shield",
                description: Text("Activate MDM Profile Builder Demo in the main window before changing Jamf settings.")
            )
            .frame(width: 520, height: 360)
        }
    }
}

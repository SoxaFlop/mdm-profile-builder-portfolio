import SwiftUI

struct WorkspaceView: View {
    @EnvironmentObject private var model: WorkspaceViewModel
    @EnvironmentObject private var access: AccessController

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                ProfileBuilderView()
                    .frame(minWidth: 500, idealWidth: 620)

                detailPane
                    .frame(minWidth: 480, idealWidth: 650)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 28))
                .foregroundStyle(.primary)
                .frame(width: 42, height: 38)
                .accessibilityLabel("Profile builder")

            VStack(alignment: .leading, spacing: 2) {
                Text(AppBrand.displayName)
                    .font(.headline)
                Text("Local profile builder for Jamf School")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label("On-device AI", systemImage: "lock.shield")
                .foregroundStyle(.green)
            Button {
                model.selectedDetailPane = .jamfSchool
            } label: {
                Label(model.jamfConnectionState.title, systemImage: jamfStatusIcon)
            }
            .buttonStyle(.plain)
            .foregroundStyle(jamfStatusColour)

            SettingsLink {
                Label("Jamf settings", systemImage: "gearshape")
            }

            if access.isAdministrator {
                Button {
                    access.isLicenceAdministrationPresented = true
                } label: {
                    Label("Manage licences", systemImage: "person.2.badge.gearshape")
                }
                .buttonStyle(.borderedProminent)
            }

            Menu {
                if let licence = access.activeLicence {
                    Text(licence.subject)
                    if let expiresAt = licence.expiresAt {
                        Text("Expires \(expiresAt.formatted(date: .abbreviated, time: .omitted))")
                    } else {
                        Text("No expiry")
                    }
                    Divider()
                }
                if access.isAdministrator {
                    Button("Licence administration…", systemImage: "key.horizontal") {
                        access.isLicenceAdministrationPresented = true
                    }
                }
                Button("Remove access from this Mac", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    access.deactivate()
                }
            } label: {
                Label(access.activeLicence?.role.title ?? "Access", systemImage: "person.crop.circle.badge.checkmark")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .sheet(isPresented: $access.isLicenceAdministrationPresented) {
            LicenceAdministrationView()
                .environmentObject(access)
        }
    }

    private var detailPane: some View {
        VStack(spacing: 0) {
            Picker("Detail", selection: $model.selectedDetailPane) {
                ForEach(DetailPane.allCases) { pane in
                    Text(pane.rawValue).tag(pane)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            Divider()

            switch model.selectedDetailPane {
            case .assistant:
                AIConversationView()
            case .jamfSchool:
                JamfIntegrationView()
            case .payload:
                PayloadPreviewView()
            }
        }
    }

    private var jamfStatusIcon: String {
        switch model.jamfConnectionState {
        case .notConfigured: "link.badge.plus"
        case .connecting: "arrow.triangle.2.circlepath"
        case .connected: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var jamfStatusColour: Color {
        switch model.jamfConnectionState {
        case .notConfigured: .secondary
        case .connecting: .blue
        case .connected: .green
        case .failed: .red
        }
    }
}

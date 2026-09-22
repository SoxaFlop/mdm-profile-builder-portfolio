import SwiftUI

struct ConnectionSettingsView: View {
    @StateObject private var model = ConnectionSettingsViewModel()

    var body: some View {
        Form {
            Section("Jamf School read-only connection") {
                TextField(
                    "https://your-school.jamfcloud.com/api",
                    text: $model.tenantURL
                )
                .textContentType(.URL)

                TextField("Network ID", text: $model.networkID)
                SecureField("API key", text: $model.apiKey)

                Text("The API key is stored as a generic password in this Mac's Keychain. It is never written to the project or application logs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Assistant AI provider") {
                Picker("Provider", selection: $model.externalAIProvider) {
                    ForEach(AssistantProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }
                .onChange(of: model.externalAIProvider) { _, _ in
                    model.selectedExternalAIProviderChanged()
                }

                TextField("Model", text: $model.externalAIModel)

                if model.externalAIProvider.requiresAPIKey {
                    SecureField("Developer API key", text: $model.externalAIAPIKey)
                    Text("This is an API connection, not a ChatGPT, Gemini or Claude website login. The key is stored only in this Mac’s Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if model.externalAIProvider == .microsoftCopilot {
                    TextField("Tenant ID or organisations", text: $model.microsoftTenantID)
                        .textContentType(.organizationName)
                    TextField("Microsoft Entra application client ID", text: $model.microsoftClientID)
                    if !model.microsoftSignedInAccount.isEmpty {
                        Label("Signed in as \(model.microsoftSignedInAccount)", systemImage: "person.crop.circle.badge.checkmark")
                            .foregroundStyle(.green)
                    }
                    if !model.microsoftDeviceCode.isEmpty {
                        Text("Enter code \(model.microsoftDeviceCode) in the Microsoft sign-in page.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .textSelection(.enabled)
                    }
                    Text("Microsoft 365 Copilot uses delegated Microsoft Graph beta access. Sign in with a work or school Microsoft 365 account that has a Copilot licence. The app stores tokens in this Mac’s Keychain and withholds Jamf secrets and Wi-Fi passwords.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if model.externalAIProvider.isExternal {
                    Label("External AI is optional. When it is active, the selected local profile, synced Jamf names, relevant documentation and deliberately attached PDF/OCR text are sent to that provider when you submit a message. Jamf credentials, Wi-Fi passwords and licence secrets are withheld.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Label("Qwen remains fully on-device and free to use.", systemImage: "lock.shield.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                HStack {
                    Button("Save AI connection", action: model.saveExternalAIConfiguration)
                    if model.externalAIProvider == .microsoftCopilot {
                        Button("Sign in with Microsoft") {
                            Task { await model.signInWithMicrosoft() }
                        }
                        .disabled(model.isSigningInMicrosoft)
                    }
                    Button("Test connection") {
                        Task { await model.testExternalAIConnection() }
                    }
                    .disabled(model.isTestingExternalAI || (!model.externalAIProvider.requiresAPIKey && model.externalAIProvider != .microsoftCopilot))
                    if model.isTestingExternalAI || model.isSigningInMicrosoft { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Use on-device AI", role: .destructive, action: model.removeExternalAIConfiguration)
                }

                Text(model.externalAIStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section("Safety mode") {
                Label("The legacy Jamf School API remains read-only.", systemImage: "lock.shield.fill")
                    .foregroundStyle(.orange)
                Text("Use a least-privilege legacy API key with Read access only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Save to Keychain", action: model.save)
                    Button("Test read-only connection") {
                        Task { await model.testConnection() }
                    }
                    .disabled(model.isTesting)

                    if model.isTesting { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Remove", role: .destructive, action: model.removeCredentials)
                }

                Text(model.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }


            Section("Jamf Platform API Gateway beta") {
                Picker("Region", selection: $model.platformRegion) {
                    ForEach(JamfPlatformRegion.allCases) { region in
                        Text(region.title).tag(region)
                    }
                }

                TextField("Tenant UUID", text: $model.platformTenantID)
                TextField("Client ID", text: $model.platformClientID)
                SecureField("Client secret", text: $model.platformClientSecret)

                Text("This separate OAuth integration enables supported blueprint create, update, deploy, undeploy and delete operations. All values are stored in Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Platform permissions and safeguards") {
                Text("Request only read, create, update, delete and deploy permissions for School blueprints. The AI cannot execute these operations; every mutation requires technician confirmation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Save Platform credentials", action: model.savePlatformCredentials)
                    Button("Test Platform connection") {
                        Task { await model.testPlatformConnection() }
                    }
                    .disabled(model.isTestingPlatform)

                    if model.isTestingPlatform { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Remove Platform credentials", role: .destructive, action: model.removePlatformCredentials)
                }

                Text(model.platformStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 12)
    }
}

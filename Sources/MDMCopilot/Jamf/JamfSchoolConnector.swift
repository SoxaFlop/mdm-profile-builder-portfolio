import Foundation

struct JamfProfileSummary: Codable, Equatable, Identifiable {
    let id: Int
    let locationId: Int?
    let identifier: String?
    let name: String
    let description: String?
    let platform: String?
}

struct JamfDeviceGroup: Codable, Equatable, Identifiable {
    let id: Int
    let locationId: Int?
    let name: String
    let description: String?
    let isSmartGroup: Bool?
    let members: Int?
    let shared: Bool?
}

/// Sanitised read-only tenant metadata that may be supplied to the local model.
/// Credentials, device identifiers and raw API responses are deliberately absent.
struct JamfReadContext: Equatable {
    let isConnected: Bool
    let profiles: [JamfProfileSummary]
    let deviceGroups: [JamfDeviceGroup]
    let blueprints: [JamfBlueprintSummary]

    static let empty = JamfReadContext(
        isConnected: false,
        profiles: [],
        deviceGroups: [],
        blueprints: []
    )
}

struct JamfConnectorCapabilities: Equatable {
    let canListProfiles: Bool
    let canReadProfileDetails: Bool
    let canListDeviceGroups: Bool
    let canCreateProfiles: Bool
    let canUpdateProfiles: Bool
    let canAssignProfileScope: Bool

    static let currentReadOnly = JamfConnectorCapabilities(
        canListProfiles: true,
        canReadProfileDetails: true,
        canListDeviceGroups: true,
        canCreateProfiles: false,
        canUpdateProfiles: false,
        canAssignProfileScope: false
    )
}

enum JamfConnectorError: LocalizedError {
    case credentialsMissing
    case invalidTenantURL
    case invalidResponse
    case requestFailed(statusCode: Int, message: String?)
    case writeActionsDisabled

    var errorDescription: String? {
        switch self {
        case .credentialsMissing:
            "Save a Jamf School tenant URL, Network ID and API key in Settings first."
        case .invalidTenantURL:
            "The Jamf School tenant URL must be a valid HTTPS URL."
        case .invalidResponse:
            "Jamf School returned an unexpected response."
        case .requestFailed(let statusCode, let message):
            "Jamf School returned HTTP \(statusCode)\(message.map { ": \($0)" } ?? "")."
        case .writeActionsDisabled:
            "Jamf School write actions are disabled. The current public API reference does not document a supported profile create, update or scope-assignment workflow."
        }
    }
}

protocol JamfSchoolConnecting {
    var capabilities: JamfConnectorCapabilities { get }

    func testConnection() async throws
    func listProfiles() async throws -> [JamfProfileSummary]
    func profile(id: Int) async throws -> JamfProfileSummary
    func listDeviceGroups() async throws -> [JamfDeviceGroup]

    func createProfile(from compiledProfile: CompiledProfile) async throws -> JamfProfileSummary
    func updateProfile(id: Int, from compiledProfile: CompiledProfile) async throws -> JamfProfileSummary
    func assignProfile(id: Int, toDeviceGroupID groupID: Int) async throws
}

/// Implements only documented, read-only Jamf School API calls.
///
/// Every write method fails before a request is built. This is intentional: the
/// current public Jamf School API reference documents profile reads but does not
/// publish supported profile create/update/scope endpoints.
final class JamfSchoolReadOnlyConnector: JamfSchoolConnecting {
    let capabilities = JamfConnectorCapabilities.currentReadOnly

    private let credentialStore: JamfCredentialStoring
    private let session: URLSession

    init(
        credentialStore: JamfCredentialStoring = KeychainJamfCredentialStore(),
        session: URLSession = .shared
    ) {
        self.credentialStore = credentialStore
        self.session = session
    }

    func testConnection() async throws {
        _ = try await listProfiles()
    }

    func listProfiles() async throws -> [JamfProfileSummary] {
        let response: ProfileListResponse = try await get(path: "profiles/", protocolVersion: 2)
        return response.profiles
    }

    func profile(id: Int) async throws -> JamfProfileSummary {
        try await get(path: "profiles/\(id)", protocolVersion: 2)
    }

    func listDeviceGroups() async throws -> [JamfDeviceGroup] {
        let response: DeviceGroupListResponse = try await get(
            path: "devices/groups",
            protocolVersion: 1
        )
        return response.deviceGroups
    }

    func createProfile(from compiledProfile: CompiledProfile) async throws -> JamfProfileSummary {
        throw JamfConnectorError.writeActionsDisabled
    }

    func updateProfile(id: Int, from compiledProfile: CompiledProfile) async throws -> JamfProfileSummary {
        throw JamfConnectorError.writeActionsDisabled
    }

    func assignProfile(id: Int, toDeviceGroupID groupID: Int) async throws {
        throw JamfConnectorError.writeActionsDisabled
    }

    private func get<Response: Decodable>(
        path: String,
        protocolVersion: Int
    ) async throws -> Response {
        guard let credentials = try credentialStore.load() else {
            throw JamfConnectorError.credentialsMissing
        }
        let endpoint = try makeEndpoint(baseURL: credentials.tenantURL, path: path)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            String(protocolVersion),
            forHTTPHeaderField: "X-Server-Protocol-Version"
        )
        request.setValue(
            basicAuthorisation(networkID: credentials.networkID, apiKey: credentials.apiKey),
            forHTTPHeaderField: "Authorization"
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw JamfConnectorError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let error = try? JSONDecoder().decode(JamfErrorResponse.self, from: data)
            throw JamfConnectorError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: error?.message
            )
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func makeEndpoint(baseURL: URL, path: String) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host != nil,
              components.user == nil,
              components.password == nil else {
            throw JamfConnectorError.invalidTenantURL
        }

        components.query = nil
        components.fragment = nil
        let trimmedBasePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = trimmedBasePath == "api" ? "/api" : "/api"
        guard let apiBaseURL = components.url else {
            throw JamfConnectorError.invalidTenantURL
        }

        return path
            .split(separator: "/", omittingEmptySubsequences: true)
            .reduce(apiBaseURL) { partialURL, component in
                partialURL.appendingPathComponent(String(component))
            }
    }

    private func basicAuthorisation(networkID: String, apiKey: String) -> String {
        let credentials = Data("\(networkID):\(apiKey)".utf8).base64EncodedString()
        return "Basic \(credentials)"
    }
}

private struct ProfileListResponse: Decodable {
    let profiles: [JamfProfileSummary]
}

private struct DeviceGroupListResponse: Decodable {
    let deviceGroups: [JamfDeviceGroup]

    enum CodingKeys: String, CodingKey {
        case deviceGroups = "DeviceGroups"
    }
}

private struct JamfErrorResponse: Decodable {
    let message: String?
}

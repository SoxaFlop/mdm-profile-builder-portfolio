import Foundation

enum JamfPlatformRegion: String, Codable, CaseIterable, Identifiable {
    case us
    case eu
    case apac

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
}

struct JamfPlatformCredentials: Codable, Equatable {
    let region: JamfPlatformRegion
    let tenantID: UUID
    let clientID: String
    let clientSecret: String
}

enum JamfBlueprintState: String, Codable, Equatable {
    case notDeployed = "NOT_DEPLOYED"
    case deployed = "DEPLOYED"
    case outOfDate = "OUT_OF_DATE"

    var title: String {
        switch self {
        case .notDeployed: "Not deployed"
        case .deployed: "Deployed"
        case .outOfDate: "Changes not deployed"
        }
    }
}

struct JamfBlueprintDeploymentState: Codable, Equatable {
    let state: JamfBlueprintState
}

struct JamfBlueprintSummary: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let description: String?
    let created: Date
    let updated: Date
    let deploymentState: JamfBlueprintDeploymentState
}

struct JamfBlueprintCreateResponse: Codable, Equatable {
    let id: UUID
    let href: URL
}

struct JamfBlueprintDetail: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let description: String?
    let scope: JamfBlueprintScope
    let created: Date
    let updated: Date
    let deploymentState: JamfBlueprintDeploymentState
    let steps: [JamfBlueprintStep]
}

enum JamfPlatformError: LocalizedError {
    case credentialsMissing
    case invalidCredentials
    case invalidResponse
    case requestFailed(statusCode: Int, message: String?)
    case destructiveGuard(String)

    var errorDescription: String? {
        switch self {
        case .credentialsMissing:
            "Save Platform API region, tenant ID, client ID and client secret in Settings first."
        case .invalidCredentials:
            "The Platform API credentials or tenant ID are invalid."
        case .invalidResponse:
            "Jamf Platform API returned an unexpected response."
        case .requestFailed(let statusCode, let message):
            "Jamf Platform API returned HTTP \(statusCode)\(message.map { ": \($0)" } ?? "")."
        case .destructiveGuard(let message):
            message
        }
    }
}

protocol JamfPlatformCredentialStoring {
    func save(_ credentials: JamfPlatformCredentials) throws
    func load() throws -> JamfPlatformCredentials?
    func delete() throws
}

protocol JamfPlatformConnecting {
    func testConnection() async throws
    func listBlueprints() async throws -> [JamfBlueprintSummary]
    func blueprint(id: UUID) async throws -> JamfBlueprintDetail
    func createBlueprint(_ draft: JamfBlueprintDraft) async throws -> JamfBlueprintCreateResponse
    func updateBlueprint(id: UUID, draft: JamfBlueprintDraft) async throws
    func deployBlueprint(id: UUID) async throws
    func undeployBlueprint(id: UUID) async throws
    func deleteBlueprint(id: UUID) async throws
}

final class JamfPlatformConnector: JamfPlatformConnecting {
    private let credentialStore: JamfPlatformCredentialStoring
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder: JSONDecoder

    init(
        credentialStore: JamfPlatformCredentialStoring = KeychainJamfPlatformCredentialStore(),
        session: URLSession = .shared
    ) {
        self.credentialStore = credentialStore
        self.session = session
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func testConnection() async throws {
        _ = try await listBlueprints()
    }

    func listBlueprints() async throws -> [JamfBlueprintSummary] {
        var results: [JamfBlueprintSummary] = []
        var page = 0
        var totalCount = 1
        while results.count < totalCount, page < 100 {
            let response: BlueprintPage = try await request(
                method: "GET",
                path: "blueprints?page=\(page)&page-size=100&sort=created:desc",
                expectedStatusCodes: [200]
            )
            results.append(contentsOf: response.results)
            totalCount = response.totalCount ?? results.count
            guard !response.results.isEmpty else { break }
            page += 1
        }
        return results
    }

    func blueprint(id: UUID) async throws -> JamfBlueprintDetail {
        try await request(
            method: "GET",
            path: "blueprints/\(id.uuidString.lowercased())",
            expectedStatusCodes: [200]
        )
    }

    func createBlueprint(_ draft: JamfBlueprintDraft) async throws -> JamfBlueprintCreateResponse {
        try await request(
            method: "POST",
            path: "blueprints",
            body: encoder.encode(draft),
            contentType: "application/json",
            expectedStatusCodes: [201]
        )
    }

    func updateBlueprint(id: UUID, draft: JamfBlueprintDraft) async throws {
        let _: EmptyResponse = try await request(
            method: "PATCH",
            path: "blueprints/\(id.uuidString.lowercased())",
            body: encoder.encode(draft),
            contentType: "application/merge-patch+json",
            expectedStatusCodes: [204]
        )
    }

    func deployBlueprint(id: UUID) async throws {
        try await action(path: "blueprints/\(id.uuidString.lowercased())/deploy")
    }

    func undeployBlueprint(id: UUID) async throws {
        try await action(path: "blueprints/\(id.uuidString.lowercased())/undeploy")
    }

    func deleteBlueprint(id: UUID) async throws {
        let _: EmptyResponse = try await request(
            method: "DELETE",
            path: "blueprints/\(id.uuidString.lowercased())",
            expectedStatusCodes: [204]
        )
    }

    private func action(path: String) async throws {
        let _: EmptyResponse = try await request(
            method: "POST",
            path: path,
            expectedStatusCodes: [202]
        )
    }

    private func request<Response: Decodable>(
        method: String,
        path: String,
        body: Data? = nil,
        contentType: String? = nil,
        expectedStatusCodes: Set<Int>
    ) async throws -> Response {
        guard let credentials = try credentialStore.load() else {
            throw JamfPlatformError.credentialsMissing
        }
        let token = try await accessToken(credentials: credentials)
        let endpoint = try endpoint(credentials: credentials, path: path)
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw JamfPlatformError.invalidResponse
        }
        guard expectedStatusCodes.contains(httpResponse.statusCode) else {
            let apiError = try? decoder.decode(PlatformAPIErrorResponse.self, from: data)
            throw JamfPlatformError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: apiError?.bestMessage
            )
        }
        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }
        return try decoder.decode(Response.self, from: data)
    }

    private func accessToken(credentials: JamfPlatformCredentials) async throws -> String {
        let endpoint = URL(string: "https://\(credentials.region.rawValue).apigw.jamf.com/auth/token")!
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "client_credentials"),
            URLQueryItem(name: "client_id", value: credentials.clientID),
            URLQueryItem(name: "client_secret", value: credentials.clientSecret)
        ]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw JamfPlatformError.invalidResponse
        }
        guard httpResponse.statusCode == 200,
              let token = try? decoder.decode(TokenResponse.self, from: data),
              !token.accessToken.isEmpty else {
            if httpResponse.statusCode == 401 { throw JamfPlatformError.invalidCredentials }
            throw JamfPlatformError.requestFailed(statusCode: httpResponse.statusCode, message: nil)
        }
        return token.accessToken
    }

    private func endpoint(credentials: JamfPlatformCredentials, path: String) throws -> URL {
        guard var components = URLComponents(
            string: "https://\(credentials.region.rawValue).apigw.jamf.com/api/blueprints/v1/tenant/\(credentials.tenantID.uuidString.lowercased())/"
        ) else { throw JamfPlatformError.invalidCredentials }

        let pathAndQuery = path.split(separator: "?", maxSplits: 1).map(String.init)
        components.path += pathAndQuery[0]
        if pathAndQuery.count == 2 { components.percentEncodedQuery = pathAndQuery[1] }
        guard let url = components.url else { throw JamfPlatformError.invalidCredentials }
        return url
    }
}

private struct BlueprintPage: Decodable {
    let results: [JamfBlueprintSummary]
    let totalCount: Int?
}

private struct TokenResponse: Decodable {
    let accessToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

private struct PlatformAPIErrorResponse: Decodable {
    let message: String?
    let detail: String?
    let title: String?

    var bestMessage: String? { detail ?? message ?? title }
}

private struct EmptyResponse: Decodable {}

struct JamfMutationAuditEntry: Codable {
    let timestamp: Date
    let action: String
    let blueprintID: UUID?
    let blueprintName: String
    let deviceGroupID: Int?
    let outcome: String
}

protocol JamfMutationAuditLogging {
    func record(_ entry: JamfMutationAuditEntry)
}

struct LocalJamfMutationAuditLogger: JamfMutationAuditLogging {
    func record(_ entry: JamfMutationAuditEntry) {
        do {
            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("MDMCopilot", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("jamf-mutation-audit.jsonl")
            var data = try JSONEncoder().encode(entry)
            data.append(0x0A)
            if FileManager.default.fileExists(atPath: file.path) {
                let handle = try FileHandle(forWritingTo: file)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: file, options: .atomic)
            }
        } catch {
            // A logging failure must not expose credentials or crash the app.
        }
    }
}

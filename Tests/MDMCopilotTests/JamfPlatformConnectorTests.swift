import XCTest
@testable import MDMCopilot

final class JamfPlatformConnectorTests: XCTestCase {
    override func tearDown() {
        PlatformMockURLProtocol.handler = nil
        super.tearDown()
    }

    func testOAuthAndBlueprintListUseFixedGatewayEndpoints() async throws {
        let tenantID = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlatformMockURLProtocol.self]
        let connector = JamfPlatformConnector(
            credentialStore: FixedPlatformCredentialStore(credentials: JamfPlatformCredentials(
                region: .eu,
                tenantID: tenantID,
                clientID: "test-client",
                clientSecret: "unit-test-value"
            )),
            session: URLSession(configuration: configuration)
        )
        var requests: [URLRequest] = []

        PlatformMockURLProtocol.handler = { request in
            requests.append(request)
            let url = try XCTUnwrap(request.url)
            if url.path == "/auth/token" {
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(url.host, "eu.apigw.jamf.com")
                let body = String(data: try XCTUnwrap(Self.bodyData(from: request)), encoding: .utf8)
                XCTAssertTrue(body?.contains("grant_type=client_credentials") == true)
                return Self.response(url: url, status: 200, json: #"{"access_token":"local-test-token"}"#)
            }

            XCTAssertEqual(
                url.path,
                "/api/blueprints/v1/tenant/11111111-2222-3333-4444-555555555555/blueprints"
            )
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer local-test-token")
            return Self.response(
                url: url,
                status: 200,
                json: #"{"results":[{"id":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee","name":"Grade 7 iPad Profile","created":"2026-08-17T08:00:00Z","updated":"2026-08-17T09:00:00Z","deploymentState":{"state":"NOT_DEPLOYED"}}],"totalCount":1}"#
            )
        }

        let blueprints = try await connector.listBlueprints()

        XCTAssertEqual(blueprints.count, 1)
        XCTAssertEqual(blueprints[0].deploymentState.state, .notDeployed)
        XCTAssertEqual(requests.count, 2)
    }

    func testLifecycleWritesUseDocumentedMethodsAndNeverCombineDeployWithCreate() async throws {
        let tenantID = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let blueprintID = try XCTUnwrap(UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlatformMockURLProtocol.self]
        let connector = JamfPlatformConnector(
            credentialStore: FixedPlatformCredentialStore(credentials: JamfPlatformCredentials(
                region: .eu,
                tenantID: tenantID,
                clientID: "test-client",
                clientSecret: "unit-test-value"
            )),
            session: URLSession(configuration: configuration)
        )
        var operations: [(method: String, path: String, contentType: String?)] = []

        PlatformMockURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            if url.path == "/auth/token" {
                return Self.response(url: url, status: 200, json: #"{"access_token":"local-test-token"}"#)
            }
            operations.append((
                request.httpMethod ?? "",
                url.path,
                request.value(forHTTPHeaderField: "Content-Type")
            ))
            if request.httpMethod == "POST", url.path.hasSuffix("/blueprints") {
                let body = String(data: try XCTUnwrap(Self.bodyData(from: request)), encoding: .utf8)
                XCTAssertTrue(body?.contains(#""deviceGroups":["42"]"#) == true)
                XCTAssertTrue(body?.contains("com.jamf.ddm-configuration-profile") == true)
                return Self.response(
                    url: url,
                    status: 201,
                    json: #"{"id":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee","href":"https://eu.apigw.jamf.com/blueprint"}"#
                )
            }
            let status = request.httpMethod == "POST" ? 202 : 204
            return Self.response(url: url, status: status, json: "")
        }

        var intent = ProfileIntent.gradeSevenExample
        intent.scope.deviceGroupID = 42
        let draft = try BlueprintCompiler().compile(intent)
        _ = try await connector.createBlueprint(draft)
        try await connector.updateBlueprint(id: blueprintID, draft: draft)
        try await connector.deployBlueprint(id: blueprintID)
        try await connector.undeployBlueprint(id: blueprintID)
        try await connector.deleteBlueprint(id: blueprintID)

        XCTAssertEqual(operations.map(\.method), ["POST", "PATCH", "POST", "POST", "DELETE"])
        XCTAssertEqual(operations[0].contentType, "application/json")
        XCTAssertEqual(operations[1].contentType, "application/merge-patch+json")
        XCTAssertTrue(operations[2].path.hasSuffix("/deploy"))
        XCTAssertTrue(operations[3].path.hasSuffix("/undeploy"))
    }

    private static func response(
        url: URL,
        status: Int,
        json: String
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: url,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!,
            Data(json.utf8)
        )
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var result = Data()
        let bufferSize = 1_024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            guard count > 0 else { break }
            result.append(buffer, count: count)
        }
        return result
    }
}

private struct FixedPlatformCredentialStore: JamfPlatformCredentialStoring {
    let credentials: JamfPlatformCredentials
    func save(_ credentials: JamfPlatformCredentials) throws {}
    func load() throws -> JamfPlatformCredentials? { credentials }
    func delete() throws {}
}

private final class PlatformMockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try XCTUnwrap(Self.handler)(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

import XCTest
@testable import MDMCopilot

final class JamfConnectorTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testWriteActionsFailClosedWithoutNetworkAccess() async throws {
        let connector = JamfSchoolReadOnlyConnector(credentialStore: EmptyCredentialStore())
        let compiled = try ProfileCompiler().compile(.gradeSevenExample)

        do {
            _ = try await connector.createProfile(from: compiled)
            XCTFail("A read-only connector must never create a profile")
        } catch let error as JamfConnectorError {
            guard case .writeActionsDisabled = error else {
                return XCTFail("Unexpected connector error: \(error)")
            }
        }
    }

    func testDocumentedProfileAndDeviceGroupReadsUseExpectedProtocolVersions() async throws {
        let credentials = JamfCredentials(
            tenantURL: try XCTUnwrap(URL(string: "https://school.example/api")),
            networkID: "network-id",
            apiKey: "unit-test-value"
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let connector = JamfSchoolReadOnlyConnector(
            credentialStore: FixedCredentialStore(credentials: credentials),
            session: URLSession(configuration: configuration)
        )
        var requestCount = 0

        MockURLProtocol.handler = { request in
            requestCount += 1
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Basic " + Data("network-id:unit-test-value".utf8).base64EncodedString()
            )

            let json: String
            if request.url?.path == "/api/profiles" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Server-Protocol-Version"), "2")
                json = #"{"profiles":[{"id":11,"name":"Grade 7 iPad Profile"}]}"#
            } else if request.url?.path == "/api/devices/groups" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Server-Protocol-Version"), "1")
                json = #"{"DeviceGroups":[{"id":42,"name":"Grade 7","members":128}]}"#
            } else {
                return (HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 404,
                    httpVersion: nil,
                    headerFields: nil
                )!, Data())
            }

            return (HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!, Data(json.utf8))
        }

        let profiles = try await connector.listProfiles()
        let groups = try await connector.listDeviceGroups()

        XCTAssertEqual(profiles.map(\.id), [11])
        XCTAssertEqual(groups.map(\.id), [42])
        XCTAssertEqual(requestCount, 2)
    }
}

private struct EmptyCredentialStore: JamfCredentialStoring {
    func save(_ credentials: JamfCredentials) throws {}
    func load() throws -> JamfCredentials? { nil }
    func delete() throws {}
}

private struct FixedCredentialStore: JamfCredentialStoring {
    let credentials: JamfCredentials

    func save(_ credentials: JamfCredentials) throws {}
    func load() throws -> JamfCredentials? { credentials }
    func delete() throws {}
}

private final class MockURLProtocol: URLProtocol {
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

import XCTest
@testable import MDMCopilot

final class BlueprintCompilerTests: XCTestCase {
    func testExampleCompilesToDocumentedConfigurationProfileComponent() throws {
        var intent = ProfileIntent.gradeSevenExample
        intent.scope.deviceGroupID = 42

        let draft = try BlueprintCompiler().compile(intent)

        XCTAssertEqual(draft.scope.deviceGroups, ["42"])
        XCTAssertEqual(draft.steps.count, 1)
        XCTAssertEqual(
            draft.steps[0].components[0].identifier,
            "com.jamf.ddm-configuration-profile"
        )
        let content = draft.steps[0].components[0].configuration.payloadContent
        XCTAssertEqual(content.count, 2)
        XCTAssertEqual(content[0]["payloadType"], .string("com.apple.applicationaccess"))
        XCTAssertEqual(content[0]["allowAirDrop"], .boolean(false))
        XCTAssertEqual(content[0]["allowCamera"], .boolean(true))
        XCTAssertEqual(content[1]["payloadType"], .string("com.apple.homescreenlayout"))
    }

    func testBlueprintRequiresExactSelectedGroupID() {
        XCTAssertThrowsError(try BlueprintCompiler().compile(.gradeSevenExample)) { error in
            guard case BlueprintCompilerError.scopeMissing = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }
}

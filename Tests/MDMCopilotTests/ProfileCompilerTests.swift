import Foundation
import XCTest
@testable import MDMCopilot

final class ProfileCompilerTests: XCTestCase {
    func testGradeSevenExampleCompilesExpectedApplePayloads() throws {
        let compiled = try ProfileCompiler().compile(.gradeSevenExample)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: compiled.data,
                options: [],
                format: nil
            ) as? [String: Any]
        )
        let payloads = try XCTUnwrap(plist["PayloadContent"] as? [[String: Any]])
        XCTAssertEqual(payloads.count, 2)

        let restrictions = try XCTUnwrap(payloads.first {
            $0["PayloadType"] as? String == "com.apple.applicationaccess"
        })
        XCTAssertEqual(restrictions["allowAirDrop"] as? Bool, false)
        XCTAssertEqual(restrictions["allowAppInstallation"] as? Bool, false)
        XCTAssertEqual(restrictions["allowAccountModification"] as? Bool, false)
        XCTAssertEqual(restrictions["allowScreenShot"] as? Bool, false)
        XCTAssertEqual(restrictions["allowCamera"] as? Bool, true)

        let homeScreen = try XCTUnwrap(payloads.first {
            $0["PayloadType"] as? String == "com.apple.homescreenlayout"
        })
        let dock = try XCTUnwrap(homeScreen["Dock"] as? [[String: String]])
        XCTAssertEqual(Set(dock.compactMap { $0["BundleID"] }), [
            "com.apple.classroom",
            "com.apple.mobilesafari"
        ])
    }

    func testCompilerRejectsEmptyProfile() {
        let intent = ProfileIntent(
            name: "Empty",
            scope: ProfileScope(deviceGroupName: "Test", deviceGroupID: nil)
        )

        XCTAssertThrowsError(try ProfileCompiler().compile(intent))
    }

    func testWiFiPayloadCompilesAndPreviewRedactsSecrets() throws {
        let password = "Correct-Horse-Battery-Staple"
        let intent = ProfileIntent(
            name: "Student Wi-Fi",
            scope: ProfileScope(deviceGroupName: "Students", deviceGroupID: 42),
            wifiPayloads: [
                WiFiPayloadIntent(
                    ssid: "Student-Network",
                    securityType: .wpa2,
                    password: password
                )
            ]
        )

        let compiled = try ProfileCompiler().compile(intent)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: compiled.data,
                options: [],
                format: nil
            ) as? [String: Any]
        )
        let payloads = try XCTUnwrap(plist["PayloadContent"] as? [[String: Any]])
        let wifi = try XCTUnwrap(payloads.first)

        XCTAssertEqual(wifi["PayloadType"] as? String, "com.apple.wifi.managed")
        XCTAssertEqual(wifi["SSID_STR"] as? String, "Student-Network")
        XCTAssertEqual(wifi["EncryptionType"] as? String, "WPA2")
        XCTAssertEqual(wifi["Password"] as? String, password)
        XCTAssertFalse(compiled.redactedXML.contains(password))
        XCTAssertTrue(compiled.redactedXML.contains("••••••••"))
    }

    func testWiFiSecretIsExcludedFromCodableDraftData() throws {
        let wifi = WiFiPayloadIntent(
            ssid: "Student-Network",
            securityType: .wpa2,
            password: "Do-Not-Persist"
        )

        let encoded = try JSONEncoder().encode(wifi)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("Do-Not-Persist"))
        let decoded = try JSONDecoder().decode(WiFiPayloadIntent.self, from: encoded)
        XCTAssertTrue(decoded.password.isEmpty)
    }
}

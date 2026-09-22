import XCTest
@testable import MDMCopilot

final class ValidationTests: XCTestCase {
    func testUnsupervisedDevicesFailSupervisionRequiredRestrictions() {
        var intent = ProfileIntent.gradeSevenExample
        intent.devicesAreSupervised = false

        let issues = ProfileValidator().validate(intent)

        XCTAssertTrue(issues.contains {
            $0.id == "supervision-required" && $0.severity == .error
        })
    }

    func testHomeScreenLayoutProducesSafetyWarning() {
        let issues = ProfileValidator().validate(.gradeSevenExample)
        XCTAssertTrue(issues.contains { $0.id == "layout-locks-home-screen" })
    }

    func testIncompleteWiFiDraftRequiresSSIDSecurityAndPassword() {
        let wifi = WiFiPayloadIntent(securityType: .wpa2)
        let intent = ProfileIntent(
            name: "Wi-Fi",
            scope: ProfileScope(deviceGroupName: "Pilot", deviceGroupID: nil),
            wifiPayloads: [wifi]
        )

        let issues = ProfileValidator().validate(intent)

        XCTAssertTrue(issues.contains { $0.id.hasPrefix("wifi-ssid-") && $0.severity == .error })
        XCTAssertTrue(issues.contains { $0.id.hasPrefix("wifi-password-") && $0.severity == .error })
    }

    func testRestrictionCatalogueUsesFullAppleBooleanSchemaSlice() {
        XCTAssertGreaterThanOrEqual(RestrictionCatalogue.iPadOS.count, 150)
        XCTAssertNotNil(RestrictionKey(rawValue: "allowBluetoothModification"))
        XCTAssertNotNil(RestrictionKey(rawValue: "forceWiFiToAllowedNetworksOnly"))
    }

    func testRestrictionLabelsReflectAppleBooleanSemantics() {
        let camera = RestrictionCatalogue.definition(for: .camera)
        XCTAssertEqual(camera.label(for: .allow), "Allow")
        XCTAssertEqual(camera.label(for: .deny), "Disable")

        let automaticTime = RestrictionCatalogue.definition(for: .forceAutomaticDateAndTime)
        XCTAssertEqual(automaticTime.label(for: .allow), "Require")
        XCTAssertEqual(automaticTime.label(for: .deny), "Do not require")
    }

    func testTimeFilterRequiresDaysAndExposesJamfOnlyMetadata() {
        var intent = ProfileIntent.blank
        intent.name = "Timed profile"
        intent.restrictions[.camera] = .deny
        intent.jamfTimeFilter = JamfTimeFilter(
            activeDays: [],
            startTime: .afterSchool,
            endTime: .endOfDay,
            isActiveAllDay: false,
            disableOnConfiguredHolidays: true
        )

        let issues = ProfileValidator().validate(intent)
        XCTAssertTrue(issues.contains { $0.id == "time-filter-days-required" && $0.severity == .error })
        XCTAssertTrue(issues.contains { $0.id == "time-filter-jamf-metadata" })
    }
}

import Foundation

enum ValidationSeverity: Int, Comparable {
    case information
    case warning
    case error

    static func < (lhs: ValidationSeverity, rhs: ValidationSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ValidationIssue: Identifiable, Equatable {
    let id: String
    let severity: ValidationSeverity
    let title: String
    let detail: String
}

struct ProfileValidator {
    func validate(_ intent: ProfileIntent) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []

        if intent.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(ValidationIssue(
                id: "profile-name-required",
                severity: .error,
                title: "Profile name required",
                detail: "Enter a clear profile name before exporting."
            ))
        }

        if intent.scope.deviceGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(ValidationIssue(
                id: "scope-not-selected",
                severity: .warning,
                title: "No target group selected",
                detail: "The generated file does not contain Jamf scope. Select and verify the device group manually in Jamf School."
            ))
        }

        if let timeFilter = intent.jamfTimeFilter {
            if timeFilter.activeDays.isEmpty {
                issues.append(ValidationIssue(
                    id: "time-filter-days-required",
                    severity: .error,
                    title: "Time filter needs at least one day",
                    detail: "Select the days on which Jamf School should make this profile active."
                ))
            }
            if !timeFilter.isActiveAllDay,
               timeFilter.startTime == timeFilter.endTime {
                issues.append(ValidationIssue(
                    id: "time-filter-range-required",
                    severity: .error,
                    title: "Time filter needs a time range",
                    detail: "Choose different start and end times, or mark the profile active all day."
                ))
            }
            if !timeFilter.isActiveAllDay,
               timeFilter.endTime < timeFilter.startTime {
                issues.append(ValidationIssue(
                    id: "time-filter-overnight-review",
                    severity: .warning,
                    title: "Overnight time filter",
                    detail: "The end time is earlier than the start time. Verify the intended after-midnight behaviour in Jamf School on a pilot group before deployment."
                ))
            }
            issues.append(ValidationIssue(
                id: "time-filter-jamf-metadata",
                severity: .information,
                title: "Jamf School schedule required",
                detail: "Time filters are Jamf School profile settings, not Apple mobileconfig payloads. This draft records the schedule for review, but the current supported Blueprint API flow does not send it."
            ))
        }

        let configuredRestrictions = intent.restrictions.filter { $0.value != .unchanged }
        if configuredRestrictions.isEmpty && intent.dockItems.isEmpty && intent.wifiPayloads.isEmpty {
            issues.append(ValidationIssue(
                id: "profile-empty",
                severity: .error,
                title: "Profile has no settings",
                detail: "Configure at least one restriction, layout item or network payload."
            ))
        }

        if !intent.devicesAreSupervised {
            let required = configuredRestrictions.keys
                .map(RestrictionCatalogue.definition(for:))
                .filter { $0.supervision == .required }
                .map(\.title)
                .sorted()

            if !required.isEmpty {
                issues.append(ValidationIssue(
                    id: "supervision-required",
                    severity: .error,
                    title: "Supervision required",
                    detail: required.joined(separator: ", ") + " require supervised iPad devices."
                ))
            }
        }

        if !intent.dockItems.isEmpty {
            issues.append(ValidationIssue(
                id: "layout-locks-home-screen",
                severity: .warning,
                title: "Home Screen layout is locked",
                detail: "Apple's Home Screen Layout payload prevents users from rearranging the managed layout. Test it on a small group first."
            ))
        }

        let payloadCount = (configuredRestrictions.isEmpty ? 0 : 1) +
            (intent.dockItems.isEmpty ? 0 : 1) + intent.wifiPayloads.count
        if payloadCount > 1 {
            issues.append(ValidationIssue(
                id: "multiple-payloads",
                severity: .information,
                title: "Multiple Apple payloads will be generated",
                detail: "This profile contains \(payloadCount) payloads. Consider separating critical network settings if your Jamf School operating standard uses one payload per profile."
            ))
        }

        if intent.restrictions[.appInstallation] == .deny,
           intent.dockItems.contains(.classroom) {
            issues.append(ValidationIssue(
                id: "classroom-installation",
                severity: .information,
                title: "Ensure Classroom is installed",
                detail: "MDM can install Classroom while user app installation is disabled, but the app must still be licensed and scoped in Jamf School."
            ))
        }

        let duplicateSSIDs = Dictionary(grouping: intent.wifiPayloads) {
            $0.ssid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }.filter { !$0.key.isEmpty && $0.value.count > 1 }
        if !duplicateSSIDs.isEmpty {
            issues.append(ValidationIssue(
                id: "wifi-duplicate-ssid",
                severity: .warning,
                title: "Duplicate Wi-Fi networks",
                detail: "The profile contains more than one payload for: \(duplicateSSIDs.keys.sorted().joined(separator: ", ")). Verify that the differing security settings are intentional."
            ))
        }

        for wifi in intent.wifiPayloads {
            validate(wifi, into: &issues)
        }

        return issues.sorted { first, second in
            if first.severity == second.severity { return first.title < second.title }
            return first.severity > second.severity
        }
    }

    private func validate(
        _ wifi: WiFiPayloadIntent,
        into issues: inout [ValidationIssue]
    ) {
        let suffix = wifi.id.uuidString.lowercased()
        let ssid = wifi.ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        if ssid.isEmpty {
            issues.append(ValidationIssue(
                id: "wifi-ssid-\(suffix)",
                severity: .error,
                title: "Wi-Fi SSID required",
                detail: "Enter the exact, case-sensitive network name."
            ))
        }

        guard let security = wifi.securityType else {
            issues.append(ValidationIssue(
                id: "wifi-security-\(suffix)",
                severity: .error,
                title: "Wi-Fi security type required",
                detail: "Choose the security type supplied by the network administrator."
            ))
            return
        }

        if security == .none {
            issues.append(ValidationIssue(
                id: "wifi-open-network-\(suffix)",
                severity: .warning,
                title: "Open Wi-Fi network",
                detail: "This network has no link-layer password. Confirm that this is intentional before deployment."
            ))
        }
        if security == .wep {
            issues.append(ValidationIssue(
                id: "wifi-wep-\(suffix)",
                severity: .warning,
                title: "WEP is obsolete",
                detail: "WEP is not considered secure. Use WPA2 or WPA3 if the network supports it."
            ))
        }

        switch wifi.authenticationType {
        case .personal:
            if security.requiresCredential && wifi.password.isEmpty {
                issues.append(ValidationIssue(
                    id: "wifi-password-\(suffix)",
                    severity: .error,
                    title: "Wi-Fi password required",
                    detail: "Enter the network password in the secure field. It is kept in memory and redacted from the on-screen payload preview."
                ))
            }
        case .enterprise:
            if wifi.enterprise.acceptedEAPTypes.isEmpty {
                issues.append(ValidationIssue(
                    id: "wifi-eap-type-\(suffix)",
                    severity: .error,
                    title: "Enterprise EAP type required",
                    detail: "Select at least one EAP type supplied by the network administrator."
                ))
            }
            if wifi.enterprise.acceptedEAPTypes.contains(.tls) {
                issues.append(ValidationIssue(
                    id: "wifi-eap-tls-certificate-\(suffix)",
                    severity: .error,
                    title: "EAP-TLS certificate payload required",
                    detail: "EAP-TLS must reference an identity certificate in the same profile. Certificate and SCEP payload editing is the next catalogue module and must be configured before this network can compile."
                ))
            }
            if wifi.enterprise.trustedServerNames.isEmpty {
                issues.append(ValidationIssue(
                    id: "wifi-trusted-servers-\(suffix)",
                    severity: .warning,
                    title: "No trusted RADIUS server names",
                    detail: "Specify the expected authentication-server names where your network design supports certificate validation."
                ))
            }
        }

        switch wifi.proxy.type {
        case .none:
            break
        case .manual:
            if wifi.proxy.server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                wifi.proxy.port == nil || !(1...65_535).contains(wifi.proxy.port ?? 0) {
                issues.append(ValidationIssue(
                    id: "wifi-manual-proxy-\(suffix)",
                    severity: .error,
                    title: "Manual proxy details incomplete",
                    detail: "Enter a proxy server and a TCP port between 1 and 65535."
                ))
            }
        case .automatic:
            guard let url = URL(string: wifi.proxy.pacURL),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  url.host != nil else {
                issues.append(ValidationIssue(
                    id: "wifi-pac-url-\(suffix)",
                    severity: .error,
                    title: "Valid PAC URL required",
                    detail: "Enter the complete HTTP or HTTPS URL for the proxy auto-configuration file."
                ))
                return
            }
        }

        if wifi.disableMACAddressRandomisation {
            issues.append(ValidationIssue(
                id: "wifi-private-address-\(suffix)",
                severity: .warning,
                title: "Private Wi-Fi address disabled",
                detail: "The device will use a stable hardware address for this network and show a reduced-privacy warning. Confirm that the network requires this."
            ))
        }
    }
}

import Foundation

enum ProfileCompilerError: LocalizedError {
    case validationFailed([ValidationIssue])
    case serialisationFailed

    var errorDescription: String? {
        switch self {
        case .validationFailed:
            "The profile contains validation errors."
        case .serialisationFailed:
            "The profile could not be serialised as a property list."
        }
    }
}

struct CompiledProfile {
    let data: Data
    let xml: String
    let redactedXML: String
    let fileName: String
}

struct ProfileCompiler {
    private let validator = ProfileValidator()

    func compile(_ intent: ProfileIntent) throws -> CompiledProfile {
        let errors = validator.validate(intent).filter { $0.severity == .error }
        guard errors.isEmpty else {
            throw ProfileCompilerError.validationFailed(errors)
        }

        let payloads = payloadDictionaries(for: intent, redactingSecrets: false)
        let redactedPayloads = payloadDictionaries(for: intent, redactingSecrets: true)

        let root = rootDictionary(for: intent, payloads: payloads)
        let redactedRoot = rootDictionary(for: intent, payloads: redactedPayloads)

        let data = try PropertyListSerialization.data(
            fromPropertyList: root,
            format: .xml,
            options: 0
        )
        let redactedData = try PropertyListSerialization.data(
            fromPropertyList: redactedRoot,
            format: .xml,
            options: 0
        )
        guard let xml = String(data: data, encoding: .utf8),
              let redactedXML = String(data: redactedData, encoding: .utf8) else {
            throw ProfileCompilerError.serialisationFailed
        }

        return CompiledProfile(
            data: data,
            xml: xml,
            redactedXML: redactedXML,
            fileName: sanitisedFileName(intent.name) + ".mobileconfig"
        )
    }

    private func payloadDictionaries(
        for intent: ProfileIntent,
        redactingSecrets: Bool
    ) -> [[String: Any]] {
        var payloads: [[String: Any]] = []

        let configuredRestrictions = intent.restrictions.filter { $0.value != .unchanged }
        if !configuredRestrictions.isEmpty {
            var restrictionsPayload = commonPayloadFields(
                displayName: "Restrictions",
                identifier: payloadIdentifier(intent, suffix: "restrictions"),
                payloadType: "com.apple.applicationaccess",
                uuid: intent.restrictionsPayloadUUID
            )

            for (key, state) in configuredRestrictions {
                restrictionsPayload[key.rawValue] = state == .allow
            }
            payloads.append(restrictionsPayload)
        }

        if !intent.dockItems.isEmpty {
            var homeScreenPayload = commonPayloadFields(
                displayName: "Home Screen Layout",
                identifier: payloadIdentifier(intent, suffix: "homescreen"),
                payloadType: "com.apple.homescreenlayout",
                uuid: intent.homeScreenPayloadUUID
            )
            homeScreenPayload["Dock"] = intent.dockItems.map {
                ["Type": "Application", "BundleID": $0.bundleID]
            }
            homeScreenPayload["Pages"] = []
            payloads.append(homeScreenPayload)
        }

        for wifi in intent.wifiPayloads {
            var wifiPayload = commonPayloadFields(
                displayName: wifi.ssid.isEmpty ? "Wi-Fi" : "Wi-Fi: \(wifi.ssid)",
                identifier: payloadIdentifier(intent, suffix: "wifi.\(wifi.id.uuidString.lowercased())"),
                payloadType: "com.apple.wifi.managed",
                uuid: wifi.payloadUUID
            )
            wifiPayload["SSID_STR"] = wifi.ssid
            wifiPayload["AutoJoin"] = wifi.autoJoin
            wifiPayload["HIDDEN_NETWORK"] = wifi.hiddenNetwork
            wifiPayload["DisableAssociationMACRandomization"] = wifi.disableMACAddressRandomisation
            wifiPayload["EncryptionType"] = wifi.securityType?.rawValue ?? WiFiSecurityType.any.rawValue

            switch wifi.authenticationType {
            case .personal:
                if wifi.securityType?.requiresCredential == true, !wifi.password.isEmpty {
                    wifiPayload["Password"] = redactingSecrets ? "••••••••" : wifi.password
                }
            case .enterprise:
                var eap: [String: Any] = [
                    "AcceptEAPTypes": wifi.enterprise.acceptedEAPTypes.map(\.rawValue)
                ]
                if !wifi.enterprise.username.isEmpty {
                    eap["UserName"] = wifi.enterprise.username
                }
                if !wifi.enterprise.password.isEmpty {
                    eap["UserPassword"] = redactingSecrets ? "••••••••" : wifi.enterprise.password
                }
                if !wifi.enterprise.outerIdentity.isEmpty {
                    eap["OuterIdentity"] = wifi.enterprise.outerIdentity
                }
                if !wifi.enterprise.trustedServerNames.isEmpty {
                    eap["TLSTrustedServerNames"] = wifi.enterprise.trustedServerNames
                }
                wifiPayload["EAPClientConfiguration"] = eap
                if let certificateUUID = wifi.enterprise.identityCertificatePayloadUUID {
                    wifiPayload["PayloadCertificateUUID"] = certificateUUID.uuidString.uppercased()
                }
            }

            wifiPayload["ProxyType"] = wifi.proxy.type.rawValue
            switch wifi.proxy.type {
            case .none:
                break
            case .manual:
                wifiPayload["ProxyServer"] = wifi.proxy.server
                if let port = wifi.proxy.port { wifiPayload["ProxyServerPort"] = port }
                if !wifi.proxy.username.isEmpty { wifiPayload["ProxyUsername"] = wifi.proxy.username }
                if !wifi.proxy.password.isEmpty {
                    wifiPayload["ProxyPassword"] = redactingSecrets ? "••••••••" : wifi.proxy.password
                }
            case .automatic:
                wifiPayload["ProxyPACURL"] = wifi.proxy.pacURL
            }

            payloads.append(wifiPayload)
        }

        return payloads
    }

    private func rootDictionary(
        for intent: ProfileIntent,
        payloads: [[String: Any]]
    ) -> [String: Any] {
        var root: [String: Any] = [
            "PayloadContent": payloads,
            "PayloadDescription": intent.profileDescription,
            "PayloadDisplayName": intent.name,
            "PayloadIdentifier": payloadIdentifier(intent),
            "PayloadType": "Configuration",
            "PayloadUUID": intent.profileUUID.uuidString.uppercased(),
            "PayloadVersion": 1
        ]

        let organisation = intent.organisation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !organisation.isEmpty {
            root["PayloadOrganization"] = organisation
        }
        return root
    }

    private func commonPayloadFields(
        displayName: String,
        identifier: String,
        payloadType: String,
        uuid: UUID
    ) -> [String: Any] {
        [
            "PayloadDisplayName": displayName,
            "PayloadIdentifier": identifier,
            "PayloadType": payloadType,
            "PayloadUUID": uuid.uuidString.uppercased(),
            "PayloadVersion": 1
        ]
    }

    private func payloadIdentifier(_ intent: ProfileIntent, suffix: String? = nil) -> String {
        let base = "dev.example.mdmprofilebuilder.\(intent.id.uuidString.lowercased())"
        guard let suffix else { return base }
        return base + "." + suffix
    }

    private func sanitisedFileName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let words = name.components(separatedBy: allowed.inverted).filter { !$0.isEmpty }
        return words.isEmpty ? "MDM-Profile" : words.joined(separator: "-")
    }
}

import Foundation

enum JSONValue: Codable, Equatable {
    case string(String)
    case integer(Int)
    case double(Double)
    case boolean(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .boolean(value) }
        else if let value = try? container.decode(Int.self) { self = .integer(value) }
        else if let value = try? container.decode(Double.self) { self = .double(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct JamfBlueprintDraft: Codable, Equatable {
    let name: String
    let description: String?
    let scope: JamfBlueprintScope
    let steps: [JamfBlueprintStep]
}

struct JamfBlueprintScope: Codable, Equatable {
    let deviceGroups: [String]
}

struct JamfBlueprintStep: Codable, Equatable {
    let name: String?
    let components: [JamfBlueprintComponent]
    let activationPredicate: String?
}

struct JamfBlueprintComponent: Codable, Equatable {
    let identifier: String
    let configuration: JamfBlueprintProfileConfiguration
}

struct JamfBlueprintProfileConfiguration: Codable, Equatable {
    let payloadDisplayName: String
    let payloadContent: [[String: JSONValue]]
}

enum BlueprintCompilerError: LocalizedError {
    case validationFailed([ValidationIssue])
    case scopeMissing
    case timeFilterUnsupported

    var errorDescription: String? {
        switch self {
        case .validationFailed:
            "Resolve the local profile validation errors before preparing a blueprint."
        case .scopeMissing:
            "Select an exact Jamf School device group before preparing a blueprint."
        case .timeFilterUnsupported:
            "The local time filter must be configured in Jamf School's General profile settings. The current documented Blueprint API flow does not provide a time-filter field, so deployment is blocked to avoid silently dropping the schedule."
        }
    }
}

/// Converts the existing typed intent into Jamf's documented Blueprint API
/// configuration-profile component. It never accepts model-generated raw JSON.
struct BlueprintCompiler {
    private let validator = ProfileValidator()

    func compile(_ intent: ProfileIntent) throws -> JamfBlueprintDraft {
        let errors = validator.validate(intent).filter { $0.severity == .error }
        guard errors.isEmpty else { throw BlueprintCompilerError.validationFailed(errors) }
        guard let deviceGroupID = intent.scope.deviceGroupID else {
            throw BlueprintCompilerError.scopeMissing
        }
        guard intent.jamfTimeFilter == nil else {
            throw BlueprintCompilerError.timeFilterUnsupported
        }

        var payloadContent: [[String: JSONValue]] = []
        let configuredRestrictions = intent.restrictions.filter { $0.value != .unchanged }
        if !configuredRestrictions.isEmpty {
            var restrictions: [String: JSONValue] = [
                "payloadType": .string("com.apple.applicationaccess")
            ]
            for (key, state) in configuredRestrictions {
                restrictions[key.rawValue] = .boolean(state == .allow)
            }
            payloadContent.append(restrictions)
        }

        if !intent.dockItems.isEmpty {
            let dock = intent.dockItems.map { item in
                JSONValue.object([
                    "Type": .string("Application"),
                    "BundleID": .string(item.bundleID)
                ])
            }
            payloadContent.append([
                "payloadType": .string("com.apple.homescreenlayout"),
                "Dock": .array(dock),
                "Pages": .array([])
            ])
        }

        for wifi in intent.wifiPayloads {
            var network: [String: JSONValue] = [
                "payloadType": .string("com.apple.wifi.managed"),
                "SSID_STR": .string(wifi.ssid),
                "AutoJoin": .boolean(wifi.autoJoin),
                "HIDDEN_NETWORK": .boolean(wifi.hiddenNetwork),
                "DisableAssociationMACRandomization": .boolean(wifi.disableMACAddressRandomisation),
                "EncryptionType": .string(wifi.securityType?.rawValue ?? WiFiSecurityType.any.rawValue),
                "ProxyType": .string(wifi.proxy.type.rawValue)
            ]

            switch wifi.authenticationType {
            case .personal:
                if wifi.securityType?.requiresCredential == true {
                    network["Password"] = .string(wifi.password)
                }
            case .enterprise:
                var eap: [String: JSONValue] = [
                    "AcceptEAPTypes": .array(
                        wifi.enterprise.acceptedEAPTypes.map { .integer($0.rawValue) }
                    )
                ]
                if !wifi.enterprise.username.isEmpty {
                    eap["UserName"] = .string(wifi.enterprise.username)
                }
                if !wifi.enterprise.password.isEmpty {
                    eap["UserPassword"] = .string(wifi.enterprise.password)
                }
                if !wifi.enterprise.outerIdentity.isEmpty {
                    eap["OuterIdentity"] = .string(wifi.enterprise.outerIdentity)
                }
                if !wifi.enterprise.trustedServerNames.isEmpty {
                    eap["TLSTrustedServerNames"] = .array(
                        wifi.enterprise.trustedServerNames.map { .string($0) }
                    )
                }
                network["EAPClientConfiguration"] = .object(eap)
                if let certificateUUID = wifi.enterprise.identityCertificatePayloadUUID {
                    network["PayloadCertificateUUID"] = .string(certificateUUID.uuidString.uppercased())
                }
            }

            switch wifi.proxy.type {
            case .none:
                break
            case .manual:
                network["ProxyServer"] = .string(wifi.proxy.server)
                if let port = wifi.proxy.port { network["ProxyServerPort"] = .integer(port) }
                if !wifi.proxy.username.isEmpty { network["ProxyUsername"] = .string(wifi.proxy.username) }
                if !wifi.proxy.password.isEmpty { network["ProxyPassword"] = .string(wifi.proxy.password) }
            case .automatic:
                network["ProxyPACURL"] = .string(wifi.proxy.pacURL)
            }

            payloadContent.append(network)
        }

        let component = JamfBlueprintComponent(
            identifier: "com.jamf.ddm-configuration-profile",
            configuration: JamfBlueprintProfileConfiguration(
                payloadDisplayName: intent.name,
                payloadContent: payloadContent
            )
        )
        return JamfBlueprintDraft(
            name: intent.name,
            description: intent.profileDescription,
            // Jamf School's legacy group ID is submitted as a string. The
            // Blueprint schema deliberately permits non-UUID string values;
            // this must first be verified against a pilot School tenant.
            scope: JamfBlueprintScope(deviceGroups: [String(deviceGroupID)]),
            steps: [
                JamfBlueprintStep(
                    name: "iPad configuration profile",
                    components: [component],
                    activationPredicate: "@status(device.operating-system.family) == 'iPadOS'"
                )
            ]
        )
    }
}

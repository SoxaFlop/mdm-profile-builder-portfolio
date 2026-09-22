import Foundation

enum ManagedPlatform: String, Codable, CaseIterable, Identifiable {
    case iPadOS

    var id: String { rawValue }
}

enum RestrictionState: String, Codable, CaseIterable, Identifiable {
    case unchanged
    case allow
    case deny

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unchanged: "Unchanged"
        case .allow: "Allow"
        case .deny: "Disable"
        }
    }
}

enum WiFiSecurityType: String, Codable, CaseIterable, Identifiable {
    case none = "None"
    case wep = "WEP"
    case wpa = "WPA"
    case wpa2 = "WPA2"
    case wpa3 = "WPA3"
    case any = "Any"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Open (no password)"
        case .wep: "WEP"
        case .wpa: "WPA/WPA2"
        case .wpa2: "WPA2/WPA3"
        case .wpa3: "WPA3 only"
        case .any: "Any supported security"
        }
    }

    var requiresCredential: Bool { self != .none }
}

enum WiFiAuthenticationType: String, Codable, CaseIterable, Identifiable {
    case personal
    case enterprise

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum WiFiEAPType: Int, Codable, CaseIterable, Identifiable {
    case tls = 13
    case leap = 17
    case sim = 18
    case ttls = 21
    case aka = 23
    case peap = 25
    case fast = 43

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .tls: "EAP-TLS"
        case .leap: "LEAP"
        case .sim: "EAP-SIM"
        case .ttls: "EAP-TTLS"
        case .aka: "EAP-AKA"
        case .peap: "PEAP"
        case .fast: "EAP-FAST"
        }
    }
}

enum WiFiProxyType: String, Codable, CaseIterable, Identifiable {
    case none = "None"
    case manual = "Manual"
    case automatic = "Auto"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .manual: "Manual"
        case .automatic: "Automatic (PAC)"
        }
    }
}

struct WiFiEnterpriseSettings: Equatable, Codable {
    var acceptedEAPTypes: [WiFiEAPType] = []
    var username = ""
    /// Memory-only. It is deliberately excluded from Codable draft data.
    var password = ""
    var outerIdentity = ""
    var trustedServerNames: [String] = []
    var identityCertificatePayloadUUID: UUID?

    private enum CodingKeys: String, CodingKey {
        case acceptedEAPTypes
        case username
        case outerIdentity
        case trustedServerNames
        case identityCertificatePayloadUUID
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        acceptedEAPTypes = try container.decodeIfPresent([WiFiEAPType].self, forKey: .acceptedEAPTypes) ?? []
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        password = ""
        outerIdentity = try container.decodeIfPresent(String.self, forKey: .outerIdentity) ?? ""
        trustedServerNames = try container.decodeIfPresent([String].self, forKey: .trustedServerNames) ?? []
        identityCertificatePayloadUUID = try container.decodeIfPresent(UUID.self, forKey: .identityCertificatePayloadUUID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(acceptedEAPTypes, forKey: .acceptedEAPTypes)
        try container.encode(username, forKey: .username)
        try container.encode(outerIdentity, forKey: .outerIdentity)
        try container.encode(trustedServerNames, forKey: .trustedServerNames)
        try container.encodeIfPresent(identityCertificatePayloadUUID, forKey: .identityCertificatePayloadUUID)
    }
}

struct WiFiProxyConfiguration: Equatable, Codable {
    var type: WiFiProxyType = .none
    var server = ""
    var port: Int?
    var username = ""
    /// Memory-only. It is deliberately excluded from Codable draft data.
    var password = ""
    var pacURL = ""

    private enum CodingKeys: String, CodingKey {
        case type
        case server
        case port
        case username
        case pacURL
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(WiFiProxyType.self, forKey: .type) ?? .none
        server = try container.decodeIfPresent(String.self, forKey: .server) ?? ""
        port = try container.decodeIfPresent(Int.self, forKey: .port)
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        password = ""
        pacURL = try container.decodeIfPresent(String.self, forKey: .pacURL) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(server, forKey: .server)
        try container.encodeIfPresent(port, forKey: .port)
        try container.encode(username, forKey: .username)
        try container.encode(pacURL, forKey: .pacURL)
    }
}

struct WiFiPayloadIntent: Identifiable, Equatable, Codable {
    let id: UUID
    let payloadUUID: UUID
    var ssid: String
    var securityType: WiFiSecurityType?
    var authenticationType: WiFiAuthenticationType
    /// Memory-only. It is deliberately excluded from Codable draft data.
    var password: String
    var autoJoin: Bool
    var hiddenNetwork: Bool
    var disableMACAddressRandomisation: Bool
    var enterprise: WiFiEnterpriseSettings
    var proxy: WiFiProxyConfiguration

    init(
        id: UUID = UUID(),
        payloadUUID: UUID = UUID(),
        ssid: String = "",
        securityType: WiFiSecurityType? = nil,
        authenticationType: WiFiAuthenticationType = .personal,
        password: String = "",
        autoJoin: Bool = true,
        hiddenNetwork: Bool = false,
        disableMACAddressRandomisation: Bool = false,
        enterprise: WiFiEnterpriseSettings = WiFiEnterpriseSettings(),
        proxy: WiFiProxyConfiguration = WiFiProxyConfiguration()
    ) {
        self.id = id
        self.payloadUUID = payloadUUID
        self.ssid = ssid
        self.securityType = securityType
        self.authenticationType = authenticationType
        self.password = password
        self.autoJoin = autoJoin
        self.hiddenNetwork = hiddenNetwork
        self.disableMACAddressRandomisation = disableMACAddressRandomisation
        self.enterprise = enterprise
        self.proxy = proxy
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case payloadUUID
        case ssid
        case securityType
        case authenticationType
        case autoJoin
        case hiddenNetwork
        case disableMACAddressRandomisation
        case enterprise
        case proxy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        payloadUUID = try container.decode(UUID.self, forKey: .payloadUUID)
        ssid = try container.decodeIfPresent(String.self, forKey: .ssid) ?? ""
        securityType = try container.decodeIfPresent(WiFiSecurityType.self, forKey: .securityType)
        authenticationType = try container.decodeIfPresent(WiFiAuthenticationType.self, forKey: .authenticationType) ?? .personal
        password = ""
        autoJoin = try container.decodeIfPresent(Bool.self, forKey: .autoJoin) ?? true
        hiddenNetwork = try container.decodeIfPresent(Bool.self, forKey: .hiddenNetwork) ?? false
        disableMACAddressRandomisation = try container.decodeIfPresent(Bool.self, forKey: .disableMACAddressRandomisation) ?? false
        enterprise = try container.decodeIfPresent(WiFiEnterpriseSettings.self, forKey: .enterprise) ?? WiFiEnterpriseSettings()
        proxy = try container.decodeIfPresent(WiFiProxyConfiguration.self, forKey: .proxy) ?? WiFiProxyConfiguration()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(payloadUUID, forKey: .payloadUUID)
        try container.encode(ssid, forKey: .ssid)
        try container.encodeIfPresent(securityType, forKey: .securityType)
        try container.encode(authenticationType, forKey: .authenticationType)
        try container.encode(autoJoin, forKey: .autoJoin)
        try container.encode(hiddenNetwork, forKey: .hiddenNetwork)
        try container.encode(disableMACAddressRandomisation, forKey: .disableMACAddressRandomisation)
        try container.encode(enterprise, forKey: .enterprise)
        try container.encode(proxy, forKey: .proxy)
    }
}

struct DockItem: Codable, Equatable, Identifiable {
    let bundleID: String
    let displayName: String

    var id: String { bundleID }

    static let classroom = DockItem(
        bundleID: "com.apple.classroom",
        displayName: "Classroom"
    )

    static let safari = DockItem(
        bundleID: "com.apple.mobilesafari",
        displayName: "Safari"
    )
}

struct ProfileScope: Codable, Equatable {
    var deviceGroupName: String
    var deviceGroupID: Int?
}

enum JamfWeekday: String, Codable, CaseIterable, Identifiable {
    case monday, tuesday, wednesday, thursday, friday, saturday, sunday

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var shortTitle: String { String(title.prefix(3)) }
}

struct JamfTimeOfDay: Codable, Equatable, Comparable {
    var hour: Int
    var minute: Int

    static let afterSchool = JamfTimeOfDay(hour: 15, minute: 0)
    static let endOfDay = JamfTimeOfDay(hour: 23, minute: 59)

    var minutesSinceMidnight: Int { hour * 60 + minute }
    var displayName: String { String(format: "%02d:%02d", hour, minute) }

    static func < (lhs: JamfTimeOfDay, rhs: JamfTimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}

/// Jamf School profile metadata. It is deliberately kept outside the Apple
/// .mobileconfig because time filters are configured by Jamf School, not Apple.
struct JamfTimeFilter: Codable, Equatable {
    var activeDays: Set<JamfWeekday>
    var startTime: JamfTimeOfDay
    var endTime: JamfTimeOfDay
    var isActiveAllDay: Bool
    var disableOnConfiguredHolidays: Bool

    static let afterSchoolWeekdays = JamfTimeFilter(
        activeDays: [.monday, .tuesday, .wednesday, .thursday, .friday],
        startTime: .afterSchool,
        endTime: .endOfDay,
        isActiveAllDay: false,
        disableOnConfiguredHolidays: true
    )

    var summary: String {
        let days = JamfWeekday.allCases.filter(activeDays.contains).map(\.shortTitle).joined(separator: ", ")
        let time = isActiveAllDay ? "all day" : "\(startTime.displayName)–\(endTime.displayName)"
        let holidays = disableOnConfiguredHolidays ? "disabled on configured holidays" : "active on configured holidays"
        return "\(days) · \(time) · \(holidays)"
    }
}

struct ProfileIntent: Codable, Equatable, Identifiable {
    let id: UUID
    let profileUUID: UUID
    let restrictionsPayloadUUID: UUID
    let homeScreenPayloadUUID: UUID

    var name: String
    var profileDescription: String
    var organisation: String
    var platform: ManagedPlatform
    var scope: ProfileScope
    var devicesAreSupervised: Bool
    var restrictions: [RestrictionKey: RestrictionState]
    var dockItems: [DockItem]
    var wifiPayloads: [WiFiPayloadIntent]
    var jamfTimeFilter: JamfTimeFilter?

    init(
        id: UUID = UUID(),
        profileUUID: UUID = UUID(),
        restrictionsPayloadUUID: UUID = UUID(),
        homeScreenPayloadUUID: UUID = UUID(),
        name: String,
        profileDescription: String = "Created locally with MDM Profile Builder Demo",
        organisation: String = "",
        platform: ManagedPlatform = .iPadOS,
        scope: ProfileScope,
        devicesAreSupervised: Bool = true,
        restrictions: [RestrictionKey: RestrictionState] = [:],
        dockItems: [DockItem] = [],
        wifiPayloads: [WiFiPayloadIntent] = [],
        jamfTimeFilter: JamfTimeFilter? = nil
    ) {
        self.id = id
        self.profileUUID = profileUUID
        self.restrictionsPayloadUUID = restrictionsPayloadUUID
        self.homeScreenPayloadUUID = homeScreenPayloadUUID
        self.name = name
        self.profileDescription = profileDescription
        self.organisation = organisation
        self.platform = platform
        self.scope = scope
        self.devicesAreSupervised = devicesAreSupervised
        self.restrictions = restrictions
        self.dockItems = dockItems
        self.wifiPayloads = wifiPayloads
        self.jamfTimeFilter = jamfTimeFilter
    }

    static var blank: ProfileIntent {
        ProfileIntent(
            name: "",
            profileDescription: "",
            organisation: "",
            scope: ProfileScope(deviceGroupName: "", deviceGroupID: nil),
            devicesAreSupervised: false
        )
    }

    static var gradeSevenExample: ProfileIntent {
        ProfileIntent(
            name: "Grade 7 iPad Profile",
            scope: ProfileScope(deviceGroupName: "Grade 7", deviceGroupID: nil),
            restrictions: [
                .airDrop: .deny,
                .appInstallation: .deny,
                .accountModification: .deny,
                .screenCapture: .deny,
                .camera: .allow
            ],
            dockItems: [.classroom, .safari]
        )
    }
}

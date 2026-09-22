// Generated from Apple's com.apple.applicationaccess device-management schema.
// Source: https://github.com/apple/device-management
// Schema snapshot: iOS/iPadOS 26.4. Regenerate with Tools/GenerateRestrictionCatalogue.rb.

import Foundation

enum SupervisionRequirement: String {
    case required = "Required"
    case recommended = "Recommended"
    case notRequired = "Not required"
}

enum RestrictionValueType: String {
    case boolean
}

enum BooleanRestrictionSemantics: String {
    case permission
    case requirement
    case toggle
}

enum RestrictionKey: String, Codable, CaseIterable, Identifiable {
    case accountModification = "allowAccountModification"
    case allowActivityContinuation = "allowActivityContinuation"
    case allowAddingGameCenterFriends = "allowAddingGameCenterFriends"
    case airDrop = "allowAirDrop"
    case allowAirPrint = "allowAirPrint"
    case allowAirPrintCredentialsStorage = "allowAirPrintCredentialsStorage"
    case allowAirPrintiBeaconDiscovery = "allowAirPrintiBeaconDiscovery"
    case allowAppCellularDataModification = "allowAppCellularDataModification"
    case allowAppClips = "allowAppClips"
    case appInstallation = "allowAppInstallation"
    case allowAppleIntelligenceReport = "allowAppleIntelligenceReport"
    case allowApplePersonalizedAdvertising = "allowApplePersonalizedAdvertising"
    case allowAppRemoval = "allowAppRemoval"
    case allowAppsToBeHidden = "allowAppsToBeHidden"
    case allowAppsToBeLocked = "allowAppsToBeLocked"
    case allowAssistant = "allowAssistant"
    case allowAssistantUserGeneratedContent = "allowAssistantUserGeneratedContent"
    case allowAssistantWhileLocked = "allowAssistantWhileLocked"
    case allowAutoCorrection = "allowAutoCorrection"
    case allowAutoDim = "allowAutoDim"
    case allowAutomaticAppDownloads = "allowAutomaticAppDownloads"
    case allowAutoUnlock = "allowAutoUnlock"
    case allowBluetoothModification = "allowBluetoothModification"
    case allowBookstore = "allowBookstore"
    case allowBookstoreErotica = "allowBookstoreErotica"
    case allowCallRecording = "allowCallRecording"
    case camera = "allowCamera"
    case allowCellularPlanModification = "allowCellularPlanModification"
    case allowChat = "allowChat"
    case allowCloudBackup = "allowCloudBackup"
    case allowCloudDocumentSync = "allowCloudDocumentSync"
    case allowCloudKeychainSync = "allowCloudKeychainSync"
    case allowCloudPhotoLibrary = "allowCloudPhotoLibrary"
    case allowCloudPrivateRelay = "allowCloudPrivateRelay"
    case allowContinuousPathKeyboard = "allowContinuousPathKeyboard"
    case allowDefaultBrowserModification = "allowDefaultBrowserModification"
    case allowDefaultCallingAppModification = "allowDefaultCallingAppModification"
    case allowDefaultMessagingAppModification = "allowDefaultMessagingAppModification"
    case allowDefinitionLookup = "allowDefinitionLookup"
    case allowDeviceNameModification = "allowDeviceNameModification"
    case allowDiagnosticSubmission = "allowDiagnosticSubmission"
    case allowDiagnosticSubmissionModification = "allowDiagnosticSubmissionModification"
    case allowDictation = "allowDictation"
    case allowEnablingRestrictions = "allowEnablingRestrictions"
    case allowEnterpriseAppTrust = "allowEnterpriseAppTrust"
    case allowEnterpriseBookBackup = "allowEnterpriseBookBackup"
    case allowEnterpriseBookMetadataSync = "allowEnterpriseBookMetadataSync"
    case allowEraseContentAndSettings = "allowEraseContentAndSettings"
    case allowESIMModification = "allowESIMModification"
    case allowESIMOutgoingTransfers = "allowESIMOutgoingTransfers"
    case allowExplicitContent = "allowExplicitContent"
    case allowExternalIntelligenceIntegrations = "allowExternalIntelligenceIntegrations"
    case allowExternalIntelligenceIntegrationsSignIn = "allowExternalIntelligenceIntegrationsSignIn"
    case allowFilesNetworkDriveAccess = "allowFilesNetworkDriveAccess"
    case allowFilesUSBDriveAccess = "allowFilesUSBDriveAccess"
    case allowFindMyDevice = "allowFindMyDevice"
    case allowFindMyFriends = "allowFindMyFriends"
    case allowFindMyFriendsModification = "allowFindMyFriendsModification"
    case allowFingerprintForUnlock = "allowFingerprintForUnlock"
    case allowFingerprintModification = "allowFingerprintModification"
    case allowGameCenter = "allowGameCenter"
    case allowGenmoji = "allowGenmoji"
    case allowGlobalBackgroundFetchWhenRoaming = "allowGlobalBackgroundFetchWhenRoaming"
    case allowHostPairing = "allowHostPairing"
    case allowImagePlayground = "allowImagePlayground"
    case allowImageWand = "allowImageWand"
    case allowInAppPurchases = "allowInAppPurchases"
    case allowiPhoneMirroring = "allowiPhoneMirroring"
    case allowiPhoneWidgetsOnMac = "allowiPhoneWidgetsOnMac"
    case allowiTunes = "allowiTunes"
    case allowKeyboardShortcuts = "allowKeyboardShortcuts"
    case allowLiveVoicemail = "allowLiveVoicemail"
    case allowLockScreenControlCenter = "allowLockScreenControlCenter"
    case allowLockScreenNotificationsView = "allowLockScreenNotificationsView"
    case allowLockScreenTodayView = "allowLockScreenTodayView"
    case allowMailPrivacyProtection = "allowMailPrivacyProtection"
    case allowMailSmartReplies = "allowMailSmartReplies"
    case allowMailSummary = "allowMailSummary"
    case allowManagedAppsCloudSync = "allowManagedAppsCloudSync"
    case allowManagedToWriteUnmanagedContacts = "allowManagedToWriteUnmanagedContacts"
    case allowMarketplaceAppInstallation = "allowMarketplaceAppInstallation"
    case allowMultiplayerGaming = "allowMultiplayerGaming"
    case allowMusicService = "allowMusicService"
    case allowNews = "allowNews"
    case allowNFC = "allowNFC"
    case allowNotesTranscription = "allowNotesTranscription"
    case allowNotesTranscriptionSummary = "allowNotesTranscriptionSummary"
    case allowNotificationsModification = "allowNotificationsModification"
    case allowOpenFromManagedToUnmanaged = "allowOpenFromManagedToUnmanaged"
    case allowOpenFromUnmanagedToManaged = "allowOpenFromUnmanagedToManaged"
    case allowOTAPKIUpdates = "allowOTAPKIUpdates"
    case allowPairedWatch = "allowPairedWatch"
    case allowPassbookWhileLocked = "allowPassbookWhileLocked"
    case allowPasscodeModification = "allowPasscodeModification"
    case allowPasswordAutoFill = "allowPasswordAutoFill"
    case allowPasswordProximityRequests = "allowPasswordProximityRequests"
    case allowPasswordSharing = "allowPasswordSharing"
    case allowPersonalHotspotModification = "allowPersonalHotspotModification"
    case allowPersonalizedHandwritingResults = "allowPersonalizedHandwritingResults"
    case allowPhotoStream = "allowPhotoStream"
    case allowPodcasts = "allowPodcasts"
    case allowPredictiveKeyboard = "allowPredictiveKeyboard"
    case allowProximitySetupToNewDevice = "allowProximitySetupToNewDevice"
    case allowRadioService = "allowRadioService"
    case allowRapidSecurityResponseInstallation = "allowRapidSecurityResponseInstallation"
    case allowRapidSecurityResponseRemoval = "allowRapidSecurityResponseRemoval"
    case allowRCSMessaging = "allowRCSMessaging"
    case allowRemoteScreenObservation = "allowRemoteScreenObservation"
    case allowSafari = "allowSafari"
    case allowSafariHistoryClearing = "allowSafariHistoryClearing"
    case allowSafariPrivateBrowsing = "allowSafariPrivateBrowsing"
    case allowSafariSummary = "allowSafariSummary"
    case allowSatelliteConnection = "allowSatelliteConnection"
    case screenCapture = "allowScreenShot"
    case allowSharedDeviceTemporarySession = "allowSharedDeviceTemporarySession"
    case allowSharedStream = "allowSharedStream"
    case allowSpellCheck = "allowSpellCheck"
    case allowSpotlightInternetResults = "allowSpotlightInternetResults"
    case allowSystemAppRemoval = "allowSystemAppRemoval"
    case allowUIAppInstallation = "allowUIAppInstallation"
    case allowUIConfigurationProfileInstallation = "allowUIConfigurationProfileInstallation"
    case allowUnmanagedToReadManagedContacts = "allowUnmanagedToReadManagedContacts"
    case allowUnpairedExternalBootToRecovery = "allowUnpairedExternalBootToRecovery"
    case allowUntrustedTLSPrompt = "allowUntrustedTLSPrompt"
    case allowUSBRestrictedMode = "allowUSBRestrictedMode"
    case allowVideoConferencing = "allowVideoConferencing"
    case allowVideoConferencingRemoteControl = "allowVideoConferencingRemoteControl"
    case allowVisualIntelligenceSummary = "allowVisualIntelligenceSummary"
    case allowVoiceDialing = "allowVoiceDialing"
    case allowVPNCreation = "allowVPNCreation"
    case allowWallpaperModification = "allowWallpaperModification"
    case allowWebDistributionAppInstallation = "allowWebDistributionAppInstallation"
    case allowWritingTools = "allowWritingTools"
    case forceAirDropUnmanaged = "forceAirDropUnmanaged"
    case forceAirPlayOutgoingRequestsPairingPassword = "forceAirPlayOutgoingRequestsPairingPassword"
    case forceAirPrintTrustedTLSRequirement = "forceAirPrintTrustedTLSRequirement"
    case forceAssistantProfanityFilter = "forceAssistantProfanityFilter"
    case forceAuthenticationBeforeAutoFill = "forceAuthenticationBeforeAutoFill"
    case forceAutomaticDateAndTime = "forceAutomaticDateAndTime"
    case forceClassroomAutomaticallyJoinClasses = "forceClassroomAutomaticallyJoinClasses"
    case forceClassroomRequestPermissionToLeaveClasses = "forceClassroomRequestPermissionToLeaveClasses"
    case forceClassroomUnpromptedAppAndDeviceLock = "forceClassroomUnpromptedAppAndDeviceLock"
    case forceClassroomUnpromptedScreenObservation = "forceClassroomUnpromptedScreenObservation"
    case forceDelayedSoftwareUpdates = "forceDelayedSoftwareUpdates"
    case forceEncryptedBackup = "forceEncryptedBackup"
    case forceITunesStorePasswordEntry = "forceITunesStorePasswordEntry"
    case forceLimitAdTracking = "forceLimitAdTracking"
    case forceOnDeviceOnlyDictation = "forceOnDeviceOnlyDictation"
    case forceOnDeviceOnlyTranslation = "forceOnDeviceOnlyTranslation"
    case forcePreserveESIMOnErase = "forcePreserveESIMOnErase"
    case forceWatchWristDetection = "forceWatchWristDetection"
    case forceWiFiPowerOn = "forceWiFiPowerOn"
    case forceWiFiToAllowedNetworksOnly = "forceWiFiToAllowedNetworksOnly"
    case forceWiFiWhitelisting = "forceWiFiWhitelisting"
    case requireManagedPasteboard = "requireManagedPasteboard"
    case safariAllowAutoFill = "safariAllowAutoFill"
    case safariAllowJavaScript = "safariAllowJavaScript"
    case safariAllowPopups = "safariAllowPopups"
    case safariForceFraudWarning = "safariForceFraudWarning"

    var id: String { rawValue }
}

struct RestrictionDefinition: Identifiable, Equatable {
    let key: RestrictionKey
    let title: String
    let summary: String
    let minimumOS: String
    let supervision: SupervisionRequirement
    let searchTerms: [String]
    let semantics: BooleanRestrictionSemantics
    let valueType: RestrictionValueType = .boolean

    var id: RestrictionKey { key }

    func label(for state: RestrictionState) -> String {
        switch (semantics, state) {
        case (_, .unchanged): "Unchanged"
        case (.permission, .allow): "Allow"
        case (.permission, .deny): "Disable"
        case (.requirement, .allow): "Require"
        case (.requirement, .deny): "Do not require"
        case (.toggle, .allow): "Enable"
        case (.toggle, .deny): "Disable"
        }
    }
}

enum RestrictionCatalogue {
    static let schemaVersion = "Apple iOS/iPadOS 26.4"

    static let iPadOS: [RestrictionDefinition] = [
RestrictionDefinition(
    key: .accountModification,
    title: "Account modification",
    summary: "If `false`, the system disables modification of accounts, such as Apple Accounts, and internet-based accounts, such as Mail, Contacts, and Calendar.",
    minimumOS: "iPadOS 7.0",
    supervision: .required,
    searchTerms: ["account modification", "allow account modification", "allowaccountmodification", "account changes", "accounts"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowActivityContinuation,
    title: "Allow Handoff",
    summary: "If `false`, the system disables activity continuation. Support for this restriction on unsupervised devices and with Managed Apple Accounts is deprecated. In a future release, this restriction will begin requiring supervision and will apply to personal Apple Accounts only.",
    minimumOS: "iPadOS 8.0",
    supervision: .notRequired,
    searchTerms: ["allow handoff", "allow activity continuation", "allowactivitycontinuation"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowAddingGameCenterFriends,
    title: "Allow Adding Game Center Friends",
    summary: "If `false`, the system prohibits adding friends to Game Center. Requires a supervised device in iOS 13 and later.",
    minimumOS: "iPadOS 4.2.1",
    supervision: .required,
    searchTerms: ["allow adding game center friends", "allowaddinggamecenterfriends"],
    semantics: .permission
),
RestrictionDefinition(
    key: .airDrop,
    title: "AirDrop",
    summary: "If `false`, the system disables AirDrop.",
    minimumOS: "iPadOS 7.0",
    supervision: .required,
    searchTerms: ["airdrop", "allow air drop", "allowairdrop", "air drop"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowAirPrint,
    title: "Allow AirPrint",
    summary: "If `false`, the system disables AirPrint.",
    minimumOS: "iPadOS 11.0",
    supervision: .required,
    searchTerms: ["allow airprint", "allow air print", "allowairprint"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowAirPrintCredentialsStorage,
    title: "Allow storage of AirPrint credentials in Keychain",
    summary: "If `false`, the system disables Keychain storage of user name and password for AirPrint.",
    minimumOS: "iPadOS 11.0",
    supervision: .required,
    searchTerms: ["allow storage of airprint credentials in keychain", "allow air print credentials storage", "allowairprintcredentialsstorage"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowAirPrintiBeaconDiscovery,
    title: "Allow discovery of AirPrint printers using iBeacons",
    summary: "If `false`, the system disables iBeacon discovery of AirPrint printers, which prevents spurious AirPrint Bluetooth beacons from phishing for network traffic.",
    minimumOS: "iPadOS 11.0",
    supervision: .required,
    searchTerms: ["allow discovery of airprint printers using ibeacons", "allow air printi beacon discovery", "allowairprintibeacondiscovery"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowAppCellularDataModification,
    title: "Allow Modifying Cellular Data Usage for Apps Settings",
    summary: "If `false`, the system disables changing settings for cellular data usage for apps.",
    minimumOS: "iPadOS 7.0",
    supervision: .required,
    searchTerms: ["allow modifying cellular data usage for apps settings", "allow app cellular data modification", "allowappcellulardatamodification"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowAppClips,
    title: "Allow App Clips",
    summary: "If `false`, the system prevents a user from adding any App Clips, and removes any existing App Clips on the device.",
    minimumOS: "iPadOS 14.0",
    supervision: .required,
    searchTerms: ["allow app clips", "allowappclips"],
    semantics: .permission
),
RestrictionDefinition(
    key: .appInstallation,
    title: "App installation / App Store",
    summary: "If `false`, the system disables the App Store and removes its icon from the Home Screen. Users are unable to install or update their apps. This applies to App Store apps, marketplace apps, and locally installed apps (using Configurator, Xcode, and so forth). In iOS 10 and later, MDM commands can ...",
    minimumOS: "iPadOS 4.0",
    supervision: .required,
    searchTerms: ["app installation / app store", "allow app installation", "allowappinstallation", "app store", "appstore", "app installation", "install apps"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowAppleIntelligenceReport,
    title: "Allow Apple Intelligence Report",
    summary: "If `false`, the system disables Apple Intelligence reports.",
    minimumOS: "iPadOS 18.4",
    supervision: .required,
    searchTerms: ["allow apple intelligence report", "allowappleintelligencereport"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowApplePersonalizedAdvertising,
    title: "Allow Apple Personalized Advertising",
    summary: "If `false`, the system limits Apple personalized advertising.",
    minimumOS: "iPadOS 14.0",
    supervision: .notRequired,
    searchTerms: ["allow apple personalized advertising", "allowapplepersonalizedadvertising"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowAppRemoval,
    title: "Allow App Removal",
    summary: "If `false`, the system disables removal of apps from an iOS device. This applies to App Store apps, marketplace apps, and locally installed apps (using Configurator, Xcode, and so forth).",
    minimumOS: "iPadOS 4.2.1",
    supervision: .required,
    searchTerms: ["allow app removal", "allowappremoval"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowAppsToBeHidden,
    title: "Allow Hiding Apps",
    summary: "If `false`, disables the ability for the user to hide apps. It doesn't affect the user's ability to leave it in the App Library, while removing it from the Home Screen.",
    minimumOS: "iPadOS 18.0",
    supervision: .required,
    searchTerms: ["allow hiding apps", "allow apps to be hidden", "allowappstobehidden"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowAppsToBeLocked,
    title: "Allow Locking Apps",
    summary: "If `false`, disables the ability for the user to lock apps. Because hiding apps also requires locking them, disallowing locking also disallows hiding.",
    minimumOS: "iPadOS 18.0",
    supervision: .required,
    searchTerms: ["allow locking apps", "allow apps to be locked", "allowappstobelocked"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowAssistant,
    title: "Allow Siri",
    summary: "If `false`, the system disables Siri.",
    minimumOS: "iPadOS 5.0",
    supervision: .notRequired,
    searchTerms: ["allow siri", "allow assistant", "allowassistant"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowAssistantUserGeneratedContent,
    title: "Allow Assistant User Generated Content",
    summary: "If `false`, the system prevents Siri from querying user-generated content from the web.",
    minimumOS: "iPadOS 7.0",
    supervision: .required,
    searchTerms: ["allow assistant user generated content", "allowassistantusergeneratedcontent"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowAssistantWhileLocked,
    title: "Allow Siri While Locked",
    summary: "If `false`, the system disables Siri when the device is locked. The system ignores this restriction if the device doesn't have a passcode set.",
    minimumOS: "iPadOS 5.1",
    supervision: .notRequired,
    searchTerms: ["allow siri while locked", "allow assistant while locked", "allowassistantwhilelocked"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowAutoCorrection,
    title: "Allow Auto Correction",
    summary: "If `false`, the system disables keyboard autocorrection.",
    minimumOS: "iPadOS 8.1.3",
    supervision: .required,
    searchTerms: ["allow auto correction", "allowautocorrection"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowAutoDim,
    title: "Allow Auto Dim",
    summary: "If `false`, disables auto dim on iPads with OLED displays.",
    minimumOS: "iPadOS 17.4",
    supervision: .required,
    searchTerms: ["allow auto dim", "allowautodim"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowAutomaticAppDownloads,
    title: "Allow Automatic App Downloads",
    summary: "If `false`, the system prevents automatic downloading of apps purchased on other devices. This setting doesn't affect updates to existing apps.",
    minimumOS: "iPadOS 9.0",
    supervision: .required,
    searchTerms: ["allow automatic app downloads", "allowautomaticappdownloads"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowAutoUnlock,
    title: "Allow Auto Unlock",
    summary: "If `false`, the system disallows auto unlock. Support for this restriction on unsupervised devices is deprecated.",
    minimumOS: "iPadOS 14.5",
    supervision: .notRequired,
    searchTerms: ["allow auto unlock", "allowautounlock"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowBluetoothModification,
    title: "Allow modifying Bluetooth settings",
    summary: "If `false`, the system prevents modification of Bluetooth settings.",
    minimumOS: "iPadOS 11.0",
    supervision: .required,
    searchTerms: ["allow modifying bluetooth settings", "allow bluetooth modification", "allowbluetoothmodification"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowBookstore,
    title: "Allow Bookstore",
    summary: "If `false`, the system removes the Book Store tab from the Books app.",
    minimumOS: "iPadOS 6.0",
    supervision: .required,
    searchTerms: ["allow bookstore", "allowbookstore"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowBookstoreErotica,
    title: "Allow Bookstore Erotica",
    summary: "If `false`, the system prevents the user from downloading Apple Books media that's tagged as erotica. Support for this restriction on unsupervised devices is deprecated.",
    minimumOS: "iPadOS 6.0",
    supervision: .notRequired,
    searchTerms: ["allow bookstore erotica", "allowbookstoreerotica"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowCallRecording,
    title: "Allow Call Recording",
    summary: "If `false`, disables call recording.",
    minimumOS: "iPadOS 18.1",
    supervision: .required,
    searchTerms: ["allow call recording", "allowcallrecording"],
    semantics: .permission
),
RestrictionDefinition(
    key: .camera,
    title: "Camera",
    summary: "If `false`, the system disables the camera and removes its icon from the Home Screen, and users are unable to take photographs. Support for this restriction on unsupervised devices is deprecated.",
    minimumOS: "iPadOS 4.0",
    supervision: .notRequired,
    searchTerms: ["camera", "allow camera", "allowcamera", "photos"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowCellularPlanModification,
    title: "Allow Cellular Plan Modification",
    summary: "If `false`, the system prevents users from changing settings related to their cellular plan (available only on select carriers).",
    minimumOS: "iPadOS 11.0",
    supervision: .required,
    searchTerms: ["allow cellular plan modification", "allowcellularplanmodification"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowChat,
    title: "Allow use of iMessage",
    summary: "If `false`, the system disables the use of iMessage with supervised devices. If the device supports text messaging, the user can still send and receive text messages.",
    minimumOS: "iPadOS 5.0",
    supervision: .required,
    searchTerms: ["allow use of imessage", "allow chat", "allowchat"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowCloudBackup,
    title: "Allow iCloud Backup",
    summary: "If `false`, the system disables backing up the device to iCloud. Support for this restriction on unsupervised devices is deprecated.",
    minimumOS: "iPadOS 5.0",
    supervision: .notRequired,
    searchTerms: ["allow icloud backup", "allow cloud backup", "allowcloudbackup"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowCloudDocumentSync,
    title: "Allow iCloud Document Sync",
    summary: "If `false`, the system disables document and key-value syncing to iCloud. Requires a supervised device in iOS 13 and later, and Shared iPad doesn't support it. Support for this restriction on unsupervised devices and with Managed Apple Accounts is deprecated.",
    minimumOS: "iPadOS 5.0",
    supervision: .required,
    searchTerms: ["allow icloud document sync", "allow cloud document sync", "allowclouddocumentsync"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowCloudKeychainSync,
    title: "Allow Cloud Keychain Sync",
    summary: "If `false`, the system disables iCloud Keychain synchronization. Support for this restriction on unsupervised devices and with Managed Apple Accounts is deprecated.",
    minimumOS: "iPadOS 7.0",
    supervision: .notRequired,
    searchTerms: ["allow cloud keychain sync", "allowcloudkeychainsync"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowCloudPhotoLibrary,
    title: "Allow iCloud Photo Library",
    summary: "If `false`, the system disables iCloud Photo Library. The system removes any photos from local storage that aren't fully downloaded from iCloud Photo Library to the device. Support for this restriction on unsupervised devices and with Managed Apple Accounts is deprecated.",
    minimumOS: "iPadOS 9.0",
    supervision: .notRequired,
    searchTerms: ["allow icloud photo library", "allow cloud photo library", "allowcloudphotolibrary"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowCloudPrivateRelay,
    title: "Allow Cloud Private Relay",
    summary: "If `false`, the system disables iCloud Private Relay. Support for this restriction on unsupervised devices and with Managed Apple Accounts is deprecated.",
    minimumOS: "iPadOS 15.0",
    supervision: .required,
    searchTerms: ["allow cloud private relay", "allowcloudprivaterelay"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowContinuousPathKeyboard,
    title: "Allow Continuous Path Keyboard",
    summary: "If `false`, the system disables QuickPath keyboard.",
    minimumOS: "iPadOS 13.0",
    supervision: .required,
    searchTerms: ["allow continuous path keyboard", "allowcontinuouspathkeyboard"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowDefaultBrowserModification,
    title: "Allow default browser modification",
    summary: "If `false`, disables default browser preference modification. The MDM Settings command to set the default browser preference still works when applying this.",
    minimumOS: "iPadOS 18.2",
    supervision: .required,
    searchTerms: ["allow default browser modification", "allowdefaultbrowsermodification"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowDefaultCallingAppModification,
    title: "Allow default calling app modification",
    summary: "If `false`, disables default calling app preference modification. The MDM Settings command to set the default calling app preference still works when applying this.",
    minimumOS: "iPadOS 18.4",
    supervision: .required,
    searchTerms: ["allow default calling app modification", "allowdefaultcallingappmodification"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowDefaultMessagingAppModification,
    title: "Allow default messaging app modification",
    summary: "If `false`, disables default messaging app preference modification. The MDM Settings command to set the default messaging app preference still works when applying this.",
    minimumOS: "iPadOS 18.4",
    supervision: .required,
    searchTerms: ["allow default messaging app modification", "allowdefaultmessagingappmodification"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowDefinitionLookup,
    title: "Allow Define",
    summary: "If `false`, the system disables definition lookup.",
    minimumOS: "iPadOS 8.1.3",
    supervision: .required,
    searchTerms: ["allow define", "allow definition lookup", "allowdefinitionlookup"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowDeviceNameModification,
    title: "Allow Modifying Device Name",
    summary: "If `false`, the system prevents the user from changing the device name.",
    minimumOS: "iPadOS 9.0",
    supervision: .required,
    searchTerms: ["allow modifying device name", "allow device name modification", "allowdevicenamemodification"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowDiagnosticSubmission,
    title: "Allow diagnostic submission",
    summary: "If `false`, the system prevents the device from automatically submitting diagnostic reports to Apple.",
    minimumOS: "iPadOS 6.0",
    supervision: .notRequired,
    searchTerms: ["allow diagnostic submission", "allowdiagnosticsubmission"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowDiagnosticSubmissionModification,
    title: "Allow modifying diagnostics settings",
    summary: "If `false`, the system disables changing the diagnostic submission and app analytics settings in the Diagnostics & Usage UI in Settings.",
    minimumOS: "iPadOS 9.3.2",
    supervision: .required,
    searchTerms: ["allow modifying diagnostics settings", "allow diagnostic submission modification", "allowdiagnosticsubmissionmodification"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowDictation,
    title: "Allow dictation",
    summary: "If `false`, the system disallows dictation input.",
    minimumOS: "iPadOS 10.3",
    supervision: .required,
    searchTerms: ["allow dictation", "allowdictation"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowEnablingRestrictions,
    title: "Allow Configuring Restrictions or ScreenTime",
    summary: "If `false`, the system disables the Enable Restrictions option in the Restrictions UI in Settings. If `false` in iOS 12 and later, the system disables the Enable ScreenTime option in the ScreenTime UI in Settings and disables ScreenTime if already enabled.",
    minimumOS: "iPadOS 8.0",
    supervision: .required,
    searchTerms: ["allow configuring restrictions or screentime", "allow enabling restrictions", "allowenablingrestrictions"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowEnterpriseAppTrust,
    title: "Allow Trusting Enterprise Apps",
    summary: "If `false`, the system removes the Trust Enterprise Developer button in Settings > General > VPN & Device Management, which prevents provisioning apps by universal provisioning profiles. This restriction applies to free developer accounts and enterprise app developers that aren't implicitly trust...",
    minimumOS: "iPadOS 9.0",
    supervision: .notRequired,
    searchTerms: ["allow trusting enterprise apps", "allow enterprise app trust", "allowenterpriseapptrust"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowEnterpriseBookBackup,
    title: "Allow Enterprise Books Backup",
    summary: "If `false`, the system disables backup of Enterprise books.",
    minimumOS: "iPadOS 8.0",
    supervision: .notRequired,
    searchTerms: ["allow enterprise books backup", "allow enterprise book backup", "allowenterprisebookbackup"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowEnterpriseBookMetadataSync,
    title: "Allow Enterprise Books Notes and Highlights Sync",
    summary: "If `false`, the system disables sync of Enterprise books, notes, and highlights.",
    minimumOS: "iPadOS 8.0",
    supervision: .notRequired,
    searchTerms: ["allow enterprise books notes and highlights sync", "allow enterprise book metadata sync", "allowenterprisebookmetadatasync"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowEraseContentAndSettings,
    title: "Allow Erase All Content and Settings",
    summary: "If `false`, the system disables the Erase All Content and Settings option in the Reset UI.",
    minimumOS: "iPadOS 8.0",
    supervision: .required,
    searchTerms: ["allow erase all content and settings", "allow erase content and settings", "allowerasecontentandsettings"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowESIMModification,
    title: "Allow eSIM Modification",
    summary: "If `false`, the system disables modifications of eSIMs.",
    minimumOS: "iPadOS 12.1",
    supervision: .required,
    searchTerms: ["allow esim modification", "allow esimmodification", "allowesimmodification"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowESIMOutgoingTransfers,
    title: "Allow eSIM Outgoing Transfers",
    summary: "If `false`, prevents the transfer of an eSIM from the device on which the restriction is installed to a different device.",
    minimumOS: "iPadOS 18.0",
    supervision: .required,
    searchTerms: ["allow esim outgoing transfers", "allow esimoutgoing transfers", "allowesimoutgoingtransfers"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowExplicitContent,
    title: "Allow Explicit Content",
    summary: "If `false`, the system hides explicit music or video content purchased from the iTunes Store. The system marks explicit content as such by content providers, such as record labels, when sold through the iTunes Store. Explicit content in the News and Podcast apps is also hidden. Requires a supervi...",
    minimumOS: "iPadOS 4.0",
    supervision: .required,
    searchTerms: ["allow explicit content", "allowexplicitcontent"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowExternalIntelligenceIntegrations,
    title: "Allow external intelligence integrations",
    summary: "If `false`, disables the use of external, cloud-based intelligence services with Siri. In iOS, this restriction is temporarily allowed on unsupervised and user enrollments. In a future release, this restriction will require supervision, and will be ignored on unsupervised devices.",
    minimumOS: "iPadOS 18.2",
    supervision: .notRequired,
    searchTerms: ["allow external intelligence integrations", "allowexternalintelligenceintegrations"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowExternalIntelligenceIntegrationsSignIn,
    title: "Allow external intelligence integrations sign-in",
    summary: "If `false`, forces external intelligence providers into anonymous mode. If a user is already signed in to an external intelligence provider, applying this restriction signs them out when attempting the next request.",
    minimumOS: "iPadOS 18.2",
    supervision: .notRequired,
    searchTerms: ["allow external intelligence integrations sign-in", "allow external intelligence integrations sign in", "allowexternalintelligenceintegrationssignin"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowFilesNetworkDriveAccess,
    title: "Allow Files Network Drive Access",
    summary: "If `false`, the system prevents connecting to network drives in the Files app.",
    minimumOS: "iPadOS 13.1",
    supervision: .required,
    searchTerms: ["allow files network drive access", "allowfilesnetworkdriveaccess"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowFilesUSBDriveAccess,
    title: "Allow Files USBDrive Access",
    summary: "If `false`, the system prevents connecting to any connected USB devices in the Files app.",
    minimumOS: "iPadOS 13.0",
    supervision: .required,
    searchTerms: ["allow files usbdrive access", "allowfilesusbdriveaccess"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowFindMyDevice,
    title: "Allow Find My Device",
    summary: "If `false`, the system disables Find My Device in the Find My app.",
    minimumOS: "iPadOS 13.0",
    supervision: .required,
    searchTerms: ["allow find my device", "allowfindmydevice"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowFindMyFriends,
    title: "Allow Find My Friends",
    summary: "If `false`, the system disables Find My Friends in the Find My app.",
    minimumOS: "iPadOS 13.0",
    supervision: .required,
    searchTerms: ["allow find my friends", "allowfindmyfriends"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowFindMyFriendsModification,
    title: "Allow Find My Friends Modification",
    summary: "If `false`, the system disables changes to Find My Friends.",
    minimumOS: "iPadOS 7.0",
    supervision: .required,
    searchTerms: ["allow find my friends modification", "allowfindmyfriendsmodification"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowFingerprintForUnlock,
    title: "Allow Touch ID to Unlock Device",
    summary: "If `false`, the system prevents Touch ID, Face ID, or Optic ID from unlocking a device. Support for this restriction on unsupervised devices is deprecated.",
    minimumOS: "iPadOS 7.0",
    supervision: .notRequired,
    searchTerms: ["allow touch id to unlock device", "allow fingerprint for unlock", "allowfingerprintforunlock"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowFingerprintModification,
    title: "Allow Modifying Touch ID Fingerprints",
    summary: "If `false`, the system prevents the user from modifying Touch ID or Face ID.",
    minimumOS: "iPadOS 8.3",
    supervision: .required,
    searchTerms: ["allow modifying touch id fingerprints", "allow fingerprint modification", "allowfingerprintmodification"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowGameCenter,
    title: "Allow Game Center",
    summary: "If `false`, the system disables Game Center, and the system removes its icon from the Home Screen.",
    minimumOS: "iPadOS 6.0",
    supervision: .required,
    searchTerms: ["allow game center", "allowgamecenter"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowGenmoji,
    title: "Allow Genmoji",
    summary: "If `false`, prohibits creating new Genmoji.",
    minimumOS: "iPadOS 18.0",
    supervision: .required,
    searchTerms: ["allow genmoji", "allowgenmoji"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowGlobalBackgroundFetchWhenRoaming,
    title: "Allow Automatic Sync While Roaming",
    summary: "If `false`, the system disables global background fetch activity when an iOS phone is roaming. Support for this restriction on unsupervised devices is deprecated.",
    minimumOS: "iPadOS 4.0",
    supervision: .notRequired,
    searchTerms: ["allow automatic sync while roaming", "allow global background fetch when roaming", "allowglobalbackgroundfetchwhenroaming"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowHostPairing,
    title: "Allow Host Pairing",
    summary: "If `false`, the system disables host pairing with the exception of the supervision host. If there's no configured supervision host certificate, the system disables all pairing. Host pairing lets the administrator control whether an iOS device can pair with a host Mac or PC.",
    minimumOS: "iPadOS 7.0",
    supervision: .required,
    searchTerms: ["allow host pairing", "allowhostpairing"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowImagePlayground,
    title: "Allow Image Playground",
    summary: "If `false`, prohibits the use of image generation.",
    minimumOS: "iPadOS 18.0",
    supervision: .required,
    searchTerms: ["allow image playground", "allowimageplayground"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowImageWand,
    title: "Allow Image Wand",
    summary: "If `false`, prohibits the use of Image Wand.",
    minimumOS: "iPadOS 18.0",
    supervision: .required,
    searchTerms: ["allow image wand", "allowimagewand"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowInAppPurchases,
    title: "Allow In App Purchases",
    summary: "If `false`, the system prohibits in-app purchasing. Support for this restriction on unsupervised devices is deprecated.",
    minimumOS: "iPadOS 4.0",
    supervision: .notRequired,
    searchTerms: ["allow in app purchases", "allowinapppurchases"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowiPhoneMirroring,
    title: "Allow iPhone mirroring",
    summary: "If `false`, prohibits the use of iPhone Mirroring. In macOS, this prevents the Mac from mirroring any iPhone. In iOS, this prevents the iPhone from mirroring to any Mac.",
    minimumOS: "iPadOS 18.0",
    supervision: .required,
    searchTerms: ["allow iphone mirroring", "allowi phone mirroring", "allowiphonemirroring"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowiPhoneWidgetsOnMac,
    title: "Allow iPhone widget on Mac",
    summary: "If `false`, the system disallows iPhone widgets on a Mac that signs in with the same Apple Account for iCloud.",
    minimumOS: "iPadOS 17.0",
    supervision: .required,
    searchTerms: ["allow iphone widget on mac", "allowi phone widgets on mac", "allowiphonewidgetsonmac"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowiTunes,
    title: "Allow use of iTunes",
    summary: "If `false`, the system disables the iTunes Music Store and removes its icon from the Home Screen. Users can't preview, purchase, or download content. Requires a supervised device in iOS 13 and later.",
    minimumOS: "iPadOS 4.0",
    supervision: .required,
    searchTerms: ["allow use of itunes", "allowi tunes", "allowitunes"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowKeyboardShortcuts,
    title: "Allow Keyboard Shortcuts",
    summary: "If `false`, the system disables keyboard shortcuts.",
    minimumOS: "iPadOS 9.0",
    supervision: .required,
    searchTerms: ["allow keyboard shortcuts", "allowkeyboardshortcuts"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowLiveVoicemail,
    title: "Allow Live Voicemail",
    summary: "If `false`, the system disables live voicemail on the device.",
    minimumOS: "iPadOS 17.2",
    supervision: .required,
    searchTerms: ["allow live voicemail", "allowlivevoicemail"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowLockScreenControlCenter,
    title: "Allow Lock Screen Control Center",
    summary: "If `false`, the system prevents Control Center from appearing on the Lock Screen.",
    minimumOS: "iPadOS 7.0",
    supervision: .notRequired,
    searchTerms: ["allow lock screen control center", "allowlockscreencontrolcenter"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowLockScreenNotificationsView,
    title: "Allow Lock Screen Notifications View",
    summary: "If `false`, the system disables the Notifications history view on the Lock Screen, so users can't view past notifications. However, they can still see notifications when they arrive.",
    minimumOS: "iPadOS 7.0",
    supervision: .notRequired,
    searchTerms: ["allow lock screen notifications view", "allowlockscreennotificationsview"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowLockScreenTodayView,
    title: "Allow Lock Screen Today View",
    summary: "If `false`, the system disables the Today view in Notification Center on the Lock Screen.",
    minimumOS: "iPadOS 7.0",
    supervision: .notRequired,
    searchTerms: ["allow lock screen today view", "allowlockscreentodayview"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowMailPrivacyProtection,
    title: "Allow Mail Privacy Protection",
    summary: "If `false`, the system disables Mail Privacy Protection on the device.",
    minimumOS: "iPadOS 15.2",
    supervision: .required,
    searchTerms: ["allow mail privacy protection", "allowmailprivacyprotection"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowMailSmartReplies,
    title: "Allow Mail Smart Replies",
    summary: "If `false`, disables smart replies in Mail.",
    minimumOS: "iPadOS 18.4",
    supervision: .required,
    searchTerms: ["allow mail smart replies", "allowmailsmartreplies"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowMailSummary,
    title: "Allow Mail Summary",
    summary: "If `false`, disables the ability to create summaries of email messages manually. This doesn't affect automatic summary generation.",
    minimumOS: "iPadOS 18.1",
    supervision: .required,
    searchTerms: ["allow mail summary", "allowmailsummary"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowManagedAppsCloudSync,
    title: "Allow iCloud Sync for Managed Apps",
    summary: "If `false`, the system prevents managed apps from using iCloud sync.",
    minimumOS: "iPadOS 8.0",
    supervision: .notRequired,
    searchTerms: ["allow icloud sync for managed apps", "allow managed apps cloud sync", "allowmanagedappscloudsync"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowManagedToWriteUnmanagedContacts,
    title: "Allow managed apps to write to managed contacts accounts",
    summary: "If `true`, the system allows managed apps to write contacts to unmanaged accounts. If `allowOpenFromManagedToUnmanaged` is `true`, this restriction has no effect. > Important: > Use MDM to install profiles that contain this restriction.",
    minimumOS: "iPadOS 12.0",
    supervision: .notRequired,
    searchTerms: ["allow managed apps to write to managed contacts accounts", "allow managed to write unmanaged contacts", "allowmanagedtowriteunmanagedcontacts"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowMarketplaceAppInstallation,
    title: "Allow App Installation from alternative marketplaces",
    summary: "If `false`, the system prevents installation of alternative marketplace apps from the web and prevents any installed alternative marketplace apps from installing apps.",
    minimumOS: "iPadOS 17.4",
    supervision: .required,
    searchTerms: ["allow app installation from alternative marketplaces", "allow marketplace app installation", "allowmarketplaceappinstallation"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowMultiplayerGaming,
    title: "Allow Multiplayer Gaming",
    summary: "If `false`, the system prohibits multiplayer gaming.",
    minimumOS: "iPadOS 4.1",
    supervision: .required,
    searchTerms: ["allow multiplayer gaming", "allowmultiplayergaming"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowMusicService,
    title: "Allow Apple Music",
    summary: "If `false`, the system disables the Music service, and the Music app reverts to classic mode.",
    minimumOS: "iPadOS 9.3",
    supervision: .required,
    searchTerms: ["allow apple music", "allow music service", "allowmusicservice"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowNews,
    title: "Allow use of News",
    summary: "If `false`, the system disables News.",
    minimumOS: "iPadOS 9.0",
    supervision: .required,
    searchTerms: ["allow use of news", "allow news", "allownews"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowNFC,
    title: "Allow NFC",
    summary: "If `false`, the system disables NFC.",
    minimumOS: "iPadOS 14.2",
    supervision: .required,
    searchTerms: ["allow nfc", "allownfc"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowNotesTranscription,
    title: "Allow Notes Transcription",
    summary: "If `false`, disables transcription in Notes.",
    minimumOS: "iPadOS 18.4",
    supervision: .required,
    searchTerms: ["allow notes transcription", "allownotestranscription"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowNotesTranscriptionSummary,
    title: "Allow Notes Transcription Summary",
    summary: "If `false`, disables transcription summarization in Notes.",
    minimumOS: "iPadOS 18.3",
    supervision: .required,
    searchTerms: ["allow notes transcription summary", "allownotestranscriptionsummary"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowNotificationsModification,
    title: "Allow Modifying Notifications Settings",
    summary: "If `false`, the system disables modification of notification settings.",
    minimumOS: "iPadOS 9.3",
    supervision: .required,
    searchTerms: ["allow modifying notifications settings", "allow notifications modification", "allownotificationsmodification"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowOpenFromManagedToUnmanaged,
    title: "Enable allow open from managed to unmanaged",
    summary: "If `false`, documents in managed apps and accounts open only in other managed apps and accounts.",
    minimumOS: "iPadOS 7.0",
    supervision: .notRequired,
    searchTerms: ["enable allow open from managed to unmanaged", "allow open from managed to unmanaged", "allowopenfrommanagedtounmanaged"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowOpenFromUnmanagedToManaged,
    title: "Enable allow open from unmanaged to managed",
    summary: "If `false`, documents in unmanaged apps and accounts open only in other unmanaged apps and accounts.",
    minimumOS: "iPadOS 7.0",
    supervision: .notRequired,
    searchTerms: ["enable allow open from unmanaged to managed", "allow open from unmanaged to managed", "allowopenfromunmanagedtomanaged"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowOTAPKIUpdates,
    title: "Allow OTAPKIUpdates",
    summary: "If `false`, the system disables over-the-air PKI updates. Setting this restriction to `false` doesn't disable CRL and OCSP checks.",
    minimumOS: "iPadOS 7.0",
    supervision: .notRequired,
    searchTerms: ["allow otapkiupdates", "allowotapkiupdates"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowPairedWatch,
    title: "Allow Pairing With Apple Watch",
    summary: "If `false`, the system disables pairing with an Apple Watch, and the system unpairs any currently paired Apple Watch and erases its content.",
    minimumOS: "iPadOS 9.0",
    supervision: .required,
    searchTerms: ["allow pairing with apple watch", "allow paired watch", "allowpairedwatch"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowPassbookWhileLocked,
    title: "Allow Wallet While Locked",
    summary: "If `false`, the system hides Passbook notifications from the Lock Screen.",
    minimumOS: "iPadOS 6.0",
    supervision: .notRequired,
    searchTerms: ["allow wallet while locked", "allow passbook while locked", "allowpassbookwhilelocked"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowPasscodeModification,
    title: "Allow Modifying Passcode",
    summary: "If `false`, the system prevents adding, changing, or removing the passcode. The system ignores this restriction on Shared iPad.",
    minimumOS: "iPadOS 9.0",
    supervision: .required,
    searchTerms: ["allow modifying passcode", "allow passcode modification", "allowpasscodemodification"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowPasswordAutoFill,
    title: "Allow Password Auto Fill",
    summary: "If `false`, the system disables: - The AutoFill Passwords feature in iOS, with Keychain and third-party password managers - Prompting the user to use a saved password in Safari or in apps - Automatic strong passwords - Suggesting strong passwords to users However, if `false`, the system doesn't p...",
    minimumOS: "iPadOS 12.0",
    supervision: .required,
    searchTerms: ["allow password auto fill", "allowpasswordautofill"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowPasswordProximityRequests,
    title: "Allow Password Proximity Requests",
    summary: "If `false`, the system disables requesting passwords from nearby devices.",
    minimumOS: "iPadOS 12.0",
    supervision: .required,
    searchTerms: ["allow password proximity requests", "allowpasswordproximityrequests"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowPasswordSharing,
    title: "Allow Password Sharing",
    summary: "If `false`, the system disables sharing passwords with the AirDrop passwords feature, or with the Passwords app.",
    minimumOS: "iPadOS 12.0",
    supervision: .required,
    searchTerms: ["allow password sharing", "allowpasswordsharing"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowPersonalHotspotModification,
    title: "Allow modifying Personal Hotspot settings",
    summary: "If `false`, the system disables modifications of the personal hotspot setting.",
    minimumOS: "iPadOS 12.2",
    supervision: .required,
    searchTerms: ["allow modifying personal hotspot settings", "allow personal hotspot modification", "allowpersonalhotspotmodification"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowPersonalizedHandwritingResults,
    title: "Allow personalized handwriting results",
    summary: "If false, prevents the system from generating text in the user's handwriting.",
    minimumOS: "iPadOS 18.0",
    supervision: .required,
    searchTerms: ["allow personalized handwriting results", "allowpersonalizedhandwritingresults"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowPhotoStream,
    title: "Allow Photo Stream",
    summary: "If `false`, the system disables Photo Stream.",
    minimumOS: "iPadOS 5.0",
    supervision: .notRequired,
    searchTerms: ["allow photo stream", "allowphotostream"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowPodcasts,
    title: "Allow Podcasts",
    summary: "If `false`, the system disables podcasts.",
    minimumOS: "iPadOS 8.0",
    supervision: .required,
    searchTerms: ["allow podcasts", "allowpodcasts"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowPredictiveKeyboard,
    title: "Allow Predictive Keyboard",
    summary: "If `false`, the system disables predictive keyboards.",
    minimumOS: "iPadOS 8.1.3",
    supervision: .required,
    searchTerms: ["allow predictive keyboard", "allowpredictivekeyboard"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowProximitySetupToNewDevice,
    title: "Allow Proximity Setup To New Device",
    summary: "If `false`, disables the prompt to set up new devices that are nearby. Starting with iOS 26.3, this also prevents exporting iOS data to set up new Android devices.",
    minimumOS: "iPadOS 11.0",
    supervision: .required,
    searchTerms: ["allow proximity setup to new device", "allowproximitysetuptonewdevice"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowRadioService,
    title: "Allow iTunes Radio",
    summary: "If `false`, the system disables Apple Music Radio.",
    minimumOS: "iPadOS 9.3",
    supervision: .required,
    searchTerms: ["allow itunes radio", "allow radio service", "allowradioservice"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowRapidSecurityResponseInstallation,
    title: "Allow Background Security Improvement Installation",
    summary: "If `false`, the system prohibits installation of Background Security Improvements.",
    minimumOS: "iPadOS 16.0",
    supervision: .required,
    searchTerms: ["allow background security improvement installation", "allow rapid security response installation", "allowrapidsecurityresponseinstallation"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowRapidSecurityResponseRemoval,
    title: "Allow Background Security Improvement Removal",
    summary: "If `false`, the system prohibits removal of Background Security Improvements.",
    minimumOS: "iPadOS 16.0",
    supervision: .required,
    searchTerms: ["allow background security improvement removal", "allow rapid security response removal", "allowrapidsecurityresponseremoval"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowRCSMessaging,
    title: "Allow RCSMessaging",
    summary: "If `false`, prevents the use of RCS messaging.",
    minimumOS: "iPadOS 18.1",
    supervision: .required,
    searchTerms: ["allow rcsmessaging", "allowrcsmessaging"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowRemoteScreenObservation,
    title: "Allow Remote Screen Observation",
    summary: "If `false`, the system disables remote screen observation by the Classroom app. Nest this key beneath `allowScreenShot` as a subrestriction. If `allowScreenShot` is `false`, the Classroom app doesn't observe remote screens. Requires a supervised device until iOS 13 and macOS 10.15. Allowed for us...",
    minimumOS: "iPadOS 9.3",
    supervision: .notRequired,
    searchTerms: ["allow remote screen observation", "allowremotescreenobservation"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowSafari,
    title: "Allow use of Safari",
    summary: "If `false`, the system disables the Safari web browser app, and the system removes its icon from the Home Screen. This setting also prevents users from opening web clips. Requires a supervised device in iOS 13 and later.",
    minimumOS: "iPadOS 4.0",
    supervision: .required,
    searchTerms: ["allow use of safari", "allow safari", "allowsafari"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowSafariHistoryClearing,
    title: "Allow Safari History Clearing",
    summary: "If `false`, the system disables the ability to clear browsing history in Safari.",
    minimumOS: "iPadOS 26.0",
    supervision: .required,
    searchTerms: ["allow safari history clearing", "allowsafarihistoryclearing"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowSafariPrivateBrowsing,
    title: "Allow Safari Private Browsing",
    summary: "If `false`, the system disables the ability to use private browsing in Safari.",
    minimumOS: "iPadOS 26.0",
    supervision: .required,
    searchTerms: ["allow safari private browsing", "allowsafariprivatebrowsing"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowSafariSummary,
    title: "Allow Safari Summary",
    summary: "If `false`, the system disables the ability to summarize content in Safari.",
    minimumOS: "iPadOS 18.4",
    supervision: .required,
    searchTerms: ["allow safari summary", "allowsafarisummary"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowSatelliteConnection,
    title: "Allow use of satellite connectivity",
    summary: "If `false`, the system prohibits the connection to and use of satellite services.",
    minimumOS: "iPadOS 18.2",
    supervision: .required,
    searchTerms: ["allow use of satellite connectivity", "allow satellite connection", "allowsatelliteconnection"],
    semantics: .permission
),
RestrictionDefinition(
    key: .screenCapture,
    title: "Screenshots and screen recording",
    summary: "If `false`, the system disables saving a screenshot of the display and capturing a screen recording. It also disables the Classroom app from observing remote screens.",
    minimumOS: "iPadOS 3.1",
    supervision: .notRequired,
    searchTerms: ["screenshots and screen recording", "allow screen shot", "allowscreenshot", "screenshot", "screenshots", "screen capture", "screen recording"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowSharedDeviceTemporarySession,
    title: "Allow Shared Device Temporary Session",
    summary: "If `false`, the system makes temporary sessions unavailable on Shared iPad.",
    minimumOS: "iPadOS 13.4",
    supervision: .required,
    searchTerms: ["allow shared device temporary session", "allowshareddevicetemporarysession"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowSharedStream,
    title: "Allow Shared Stream",
    summary: "If `false`, the system disables Shared Photo Stream. Support for this restriction on unsupervised devices is deprecated.",
    minimumOS: "iPadOS 6.0",
    supervision: .notRequired,
    searchTerms: ["allow shared stream", "allowsharedstream"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowSpellCheck,
    title: "Allow Spell Check",
    summary: "If `false`, the system disables the keyboard spell checker.",
    minimumOS: "iPadOS 8.1.3",
    supervision: .required,
    searchTerms: ["allow spell check", "allowspellcheck"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowSpotlightInternetResults,
    title: "Allow Siri Suggestions",
    summary: "If `false`, the system disables Spotlight Internet search results in Siri Suggestions. Support for this restriction on unsupervised devices is deprecated.",
    minimumOS: "iPadOS 8.0",
    supervision: .notRequired,
    searchTerms: ["allow siri suggestions", "allow spotlight internet results", "allowspotlightinternetresults"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowSystemAppRemoval,
    title: "Allow System App Removal",
    summary: "If `false`, the system disables the removal of system apps from the device.",
    minimumOS: "iPadOS 11.0",
    supervision: .required,
    searchTerms: ["allow system app removal", "allowsystemappremoval"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowUIAppInstallation,
    title: "Allow App Installation from App Store",
    summary: "If `false`, the system disables the App Store and removes its icon from the Home Screen. However, users can continue to install or update their apps either locally (via Configurator, Xcode, and so forth), or using alternative marketplace apps. In iOS 10 and later, MDM commands can override this r...",
    minimumOS: "iPadOS 9.0",
    supervision: .required,
    searchTerms: ["allow app installation from app store", "allow uiapp installation", "allowuiappinstallation"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowUIConfigurationProfileInstallation,
    title: "Allow UI Configuration Profile Installation",
    summary: "If `false`, the system prohibits the user from installing configuration profiles and certificates interactively.",
    minimumOS: "iPadOS 6.0",
    supervision: .required,
    searchTerms: ["allow ui configuration profile installation", "allow uiconfiguration profile installation", "allowuiconfigurationprofileinstallation"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowUnmanagedToReadManagedContacts,
    title: "Allow unmanaged apps to read managed contacts accounts",
    summary: "If `true`, the system allows unmanaged apps to read from managed contacts accounts. If `allowOpenFromManagedToUnmanaged` is `true`, this restriction has no effect. > Important: > Use MDM to install profiles that contain this restriction.",
    minimumOS: "iPadOS 12.0",
    supervision: .notRequired,
    searchTerms: ["allow unmanaged apps to read managed contacts accounts", "allow unmanaged to read managed contacts", "allowunmanagedtoreadmanagedcontacts"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowUnpairedExternalBootToRecovery,
    title: "Allow Unpaired External Boot To Recovery",
    summary: "If `true`, the system allows unpaired devices to boot devices into recovery.",
    minimumOS: "iPadOS 14.5",
    supervision: .required,
    searchTerms: ["allow unpaired external boot to recovery", "allowunpairedexternalboottorecovery"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowUntrustedTLSPrompt,
    title: "Allow user to accept untrusted TLS certificates",
    summary: "If `false`, the system automatically rejects untrusted HTTPS certificates without prompting the user.",
    minimumOS: "iPadOS 5.0",
    supervision: .notRequired,
    searchTerms: ["allow user to accept untrusted tls certificates", "allow untrusted tlsprompt", "allowuntrustedtlsprompt"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowUSBRestrictedMode,
    title: "Allow USBRestricted Mode",
    summary: "If `false`, the system allows iOS devices to always connect to USB accessories while locked. In macOS, allows new USB and Thunderbolt accessories, and SD cards to connect without authorization. If the system has Lockdown mode enabled, it ignores this value. This restriction is not supported on th...",
    minimumOS: "iPadOS 11.4.1",
    supervision: .required,
    searchTerms: ["allow usbrestricted mode", "allowusbrestrictedmode"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowVideoConferencing,
    title: "Allow Video Conferencing",
    summary: "If `false`, the system hides the FaceTime app. Requires a supervised device in iOS 13 and later.",
    minimumOS: "iPadOS 4.0",
    supervision: .required,
    searchTerms: ["allow video conferencing", "allowvideoconferencing"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowVideoConferencingRemoteControl,
    title: "Allow Video Conferencing Remote Control",
    summary: "If `false`, disables the ability for a remote FaceTime session to request control of the device.",
    minimumOS: "iPadOS 18.4",
    supervision: .required,
    searchTerms: ["allow video conferencing remote control", "allowvideoconferencingremotecontrol"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowVisualIntelligenceSummary,
    title: "Allow Visual Intelligence Summary",
    summary: "If `false`, the system disables visual intelligence summarization.",
    minimumOS: "iPadOS 18.3",
    supervision: .required,
    searchTerms: ["allow visual intelligence summary", "allowvisualintelligencesummary"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowVoiceDialing,
    title: "Allow Voice Dialing While Device is Locked",
    summary: "If `false`, the system disables voice dialing if the device is locked with a passcode.",
    minimumOS: "iPadOS 4.0",
    supervision: .notRequired,
    searchTerms: ["allow voice dialing while device is locked", "allow voice dialing", "allowvoicedialing"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowVPNCreation,
    title: "Allow Adding VPN Configurations (Supervised devices only)",
    summary: "If `false`, the system allows only managed apps to create VPN configurations. Prior to iOS 18, the system also allows unmanaged apps to create VPN configurations.",
    minimumOS: "iPadOS 11.0",
    supervision: .required,
    searchTerms: ["allow adding vpn configurations (supervised devices only)", "allow vpncreation", "allowvpncreation"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowWallpaperModification,
    title: "Allow Modifying Wallpaper",
    summary: "If `false`, the system prevents changing the wallpaper.",
    minimumOS: "iPadOS 9.0",
    supervision: .required,
    searchTerms: ["allow modifying wallpaper", "allow wallpaper modification", "allowwallpapermodification"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowWebDistributionAppInstallation,
    title: "Allow App Installation from web sites",
    summary: "If `false`, the device prevents installation of apps directly from the web.",
    minimumOS: "iPadOS 17.5",
    supervision: .required,
    searchTerms: ["allow app installation from web sites", "allow web distribution app installation", "allowwebdistributionappinstallation"],
    semantics: .permission
),
RestrictionDefinition(
    key: .allowWritingTools,
    title: "Allow writing tools",
    summary: "If `false`, disables Apple Intelligence writing tools.",
    minimumOS: "iPadOS 18.0",
    supervision: .required,
    searchTerms: ["allow writing tools", "allowwritingtools"],
    semantics: .permission
),
RestrictionDefinition(
    key: .forceAirDropUnmanaged,
    title: "Treat AirDrop as Unmanaged Destination",
    summary: "If `true`, the system considers AirDrop to be an unmanaged drop target.",
    minimumOS: "iPadOS 9.0",
    supervision: .notRequired,
    searchTerms: ["treat airdrop as unmanaged destination", "require air drop unmanaged", "forceairdropunmanaged"],
    semantics: .requirement
),
RestrictionDefinition(
    key: .forceAirPlayOutgoingRequestsPairingPassword,
    title: "Require Air Play Outgoing Requests Pairing Password",
    summary: "If `true`, the system forces all devices receiving AirPlay requests from this device to use a pairing password.",
    minimumOS: "iPadOS 7.1",
    supervision: .notRequired,
    searchTerms: ["require air play outgoing requests pairing password", "forceairplayoutgoingrequestspairingpassword"],
    semantics: .requirement
),
RestrictionDefinition(
    key: .forceAirPrintTrustedTLSRequirement,
    title: "Disallow AirPrint to destinations with untrusted certificates",
    summary: "If `true`, the system requires trusted certificates for TLS printing communication.",
    minimumOS: "iPadOS 11.0",
    supervision: .required,
    searchTerms: ["disallow airprint to destinations with untrusted certificates", "require air print trusted tlsrequirement", "forceairprinttrustedtlsrequirement"],
    semantics: .requirement
),
RestrictionDefinition(
    key: .forceAssistantProfanityFilter,
    title: "Enable Siri Profanity Filter",
    summary: "If `true`, the system forces the use of the profanity filter for Siri and dictation. Requires a supervised device in iOS.",
    minimumOS: "iPadOS 5.0",
    supervision: .required,
    searchTerms: ["enable siri profanity filter", "require assistant profanity filter", "forceassistantprofanityfilter"],
    semantics: .requirement
),
RestrictionDefinition(
    key: .forceAuthenticationBeforeAutoFill,
    title: "Require Authentication Before Auto Fill",
    summary: "If `true`, the user needs to authenticate before the system can autofill passwords or credit card information in Safari and apps. If this restriction isn't enforced, the user can toggle this feature in Settings. Only supported on devices with Face ID or Touch ID.",
    minimumOS: "iPadOS 11.0",
    supervision: .required,
    searchTerms: ["require authentication before auto fill", "forceauthenticationbeforeautofill"],
    semantics: .requirement
),
RestrictionDefinition(
    key: .forceAutomaticDateAndTime,
    title: "Automatic date and time",
    summary: "If `true`, the system enables the Set Automatically feature in Date & Time and the user can't disable it. The system updates the device's time zone only when the device can determine its location using a cellular connection or Wi-Fi with location services enabled.",
    minimumOS: "iPadOS 12.0",
    supervision: .required,
    searchTerms: ["automatic date and time", "require automatic date and time", "forceautomaticdateandtime", "date and time", "date & time", "change the date and time", "changing the date and time", "set automatically"],
    semantics: .requirement
),
RestrictionDefinition(
    key: .forceClassroomAutomaticallyJoinClasses,
    title: "Require Classroom Automatically Join Classes",
    summary: "If `true`, the system automatically gives permission to the teacher's requests without prompting the student.",
    minimumOS: "iPadOS 11.0",
    supervision: .required,
    searchTerms: ["require classroom automatically join classes", "forceclassroomautomaticallyjoinclasses"],
    semantics: .requirement
),
RestrictionDefinition(
    key: .forceClassroomRequestPermissionToLeaveClasses,
    title: "Require Classroom Request Permission To Leave Classes",
    summary: "If `true`, a student enrolled in an unmanaged course through Classroom needs to request permission from the teacher to leave the course.",
    minimumOS: "iPadOS 11.3",
    supervision: .required,
    searchTerms: ["require classroom request permission to leave classes", "forceclassroomrequestpermissiontoleaveclasses"],
    semantics: .requirement
),
RestrictionDefinition(
    key: .forceClassroomUnpromptedAppAndDeviceLock,
    title: "Require Classroom Unprompted App And Device Lock",
    summary: "If `true`, the system allows the teacher to lock apps or the device without prompting the student.",
    minimumOS: "iPadOS 11.0",
    supervision: .required,
    searchTerms: ["require classroom unprompted app and device lock", "forceclassroomunpromptedappanddevicelock"],
    semantics: .requirement
),
RestrictionDefinition(
    key: .forceClassroomUnpromptedScreenObservation,
    title: "Require Classroom Unprompted Screen Observation",
    summary: "If `true` and `ScreenObservationPermissionModificationAllowed` is also `true` in the Education payload, a student enrolled in a managed course through the Classroom app automatically gives permission to that course teacher's requests to observe the student's screen without prompting the student.",
    minimumOS: "iPadOS 11.0",
    supervision: .required,
    searchTerms: ["require classroom unprompted screen observation", "forceclassroomunpromptedscreenobservation"],
    semantics: .requirement
),
RestrictionDefinition(
    key: .forceDelayedSoftwareUpdates,
    title: "Require Delayed Software Updates",
    summary: "If `true`, the system delays user visibility of software updates. In macOS, the system allows seed build updates without delay. The delay is 30 days unless you set `enforcedSoftwareUpdateDelay` to another value.",
    minimumOS: "iPadOS 11.3",
    supervision: .required,
    searchTerms: ["require delayed software updates", "forcedelayedsoftwareupdates"],
    semantics: .requirement
),
RestrictionDefinition(
    key: .forceEncryptedBackup,
    title: "Force Encrypted Backups",
    summary: "If `true`, the system encrypts all backups.",
    minimumOS: "iPadOS 4.0",
    supervision: .notRequired,
    searchTerms: ["force encrypted backups", "require encrypted backup", "forceencryptedbackup"],
    semantics: .requirement
),
RestrictionDefinition(
    key: .forceITunesStorePasswordEntry,
    title: "Require iTunes password for all purchases",
    summary: "If `true`, the system forces the user to enter their iTunes password for each transaction.",
    minimumOS: "iPadOS 6.0",
    supervision: .notRequired,
    searchTerms: ["require itunes password for all purchases", "require itunes store password entry", "forceitunesstorepasswordentry"],
    semantics: .requirement
),
RestrictionDefinition(
    key: .forceLimitAdTracking,
    title: "Require Limit Ad Tracking",
    summary: "If `true`, the system limits ad tracking. Additionally, it disables app tracking and the Allow Apps to Request to Track setting.",
    minimumOS: "iPadOS 7.0",
    supervision: .notRequired,
    searchTerms: ["require limit ad tracking", "forcelimitadtracking"],
    semantics: .requirement
),
RestrictionDefinition(
    key: .forceOnDeviceOnlyDictation,
    title: "Require On Device Only Dictation",
    summary: "If `true`, the system disables connections to Siri servers for the purposes of dictation.",
    minimumOS: "iPadOS 14.5",
    supervision: .notRequired,
    searchTerms: ["require on device only dictation", "forceondeviceonlydictation"],
    semantics: .requirement
),
RestrictionDefinition(
    key: .forceOnDeviceOnlyTranslation,
    title: "Require On Device Only Translation",
    summary: "If `true`, the device can't connect to Siri servers for the purposes of translation.",
    minimumOS: "iPadOS 15.0",
    supervision: .notRequired,
    searchTerms: ["require on device only translation", "forceondeviceonlytranslation"],
    semantics: .requirement
),
RestrictionDefinition(
    key: .forcePreserveESIMOnErase,
    title: "Force Preserve ESIM on Erase",
    summary: "If `true`, the system preserves eSIM when it erases the device due to too many failed password attempts or the Erase All Content and Settings option in Settings > General > Reset. > Note: > The system doesn't preserve eSIM if Find My initiates erasing the device.",
    minimumOS: "iPadOS 17.2",
    supervision: .required,
    searchTerms: ["force preserve esim on erase", "require preserve esimon erase", "forcepreserveesimonerase"],
    semantics: .requirement
),
RestrictionDefinition(
    key: .forceWatchWristDetection,
    title: "Force Apple Watch Wrist Detection",
    summary: "If `true`, the system forces a paired Apple Watch to use Wrist Detection.",
    minimumOS: "iPadOS 8.2",
    supervision: .notRequired,
    searchTerms: ["force apple watch wrist detection", "require watch wrist detection", "forcewatchwristdetection"],
    semantics: .requirement
),
RestrictionDefinition(
    key: .forceWiFiPowerOn,
    title: "Disallow Wi-Fi from being turned off",
    summary: "If `true`, the system prevents turning off Wi-Fi in Settings or Control Center, even by entering or leaving Airplane Mode. It doesn't prevent selecting which Wi-Fi network to use. and later.",
    minimumOS: "iPadOS 13.0",
    supervision: .required,
    searchTerms: ["disallow wi-fi from being turned off", "require wi fi power on", "forcewifipoweron"],
    semantics: .requirement
),
RestrictionDefinition(
    key: .forceWiFiToAllowedNetworksOnly,
    title: "Require Wi Fi To Allowed Networks Only",
    summary: "If `true`, the system limits the device to only join Wi-Fi networks set up through a configuration profile.",
    minimumOS: "iPadOS 14.5",
    supervision: .required,
    searchTerms: ["require wi fi to allowed networks only", "forcewifitoallowednetworksonly"],
    semantics: .requirement
),
RestrictionDefinition(
    key: .forceWiFiWhitelisting,
    title: "Only join Wi-Fi networks installed by profiles",
    summary: "Use `forceWiFiToAllowedNetworksOnly` instead.",
    minimumOS: "iPadOS 10.3",
    supervision: .required,
    searchTerms: ["only join wi-fi networks installed by profiles", "require wi fi whitelisting", "forcewifiwhitelisting"],
    semantics: .requirement
),
RestrictionDefinition(
    key: .requireManagedPasteboard,
    title: "require Managed Pasteboard",
    summary: "If `true`, copy-and-paste functionality is limited by the `allowOpenFromManagedToUnmanaged` and `allowOpenFromUnmanagedToManaged` restrictions.",
    minimumOS: "iPadOS 15.0",
    supervision: .notRequired,
    searchTerms: ["require managed pasteboard", "requiremanagedpasteboard"],
    semantics: .requirement
),
RestrictionDefinition(
    key: .safariAllowAutoFill,
    title: "Allow AutoFill in Safari",
    summary: "If `false`, the system disables Safari AutoFill for passwords, contact info, and credit cards, and also prevents using the Keychain for AutoFill. Requires a supervised device in iOS 13 and later. > Note: > The system still allows third-party password managers, and apps can use AutoFill.",
    minimumOS: "iPadOS 4.0",
    supervision: .required,
    searchTerms: ["allow autofill in safari", "safari allow auto fill", "safariallowautofill"],
    semantics: .toggle
),
RestrictionDefinition(
    key: .safariAllowJavaScript,
    title: "Allow JavaScript",
    summary: "If `false`, Safari doesn't execute JavaScript. This restriction will require supervision in a future release.",
    minimumOS: "iPadOS 4.0",
    supervision: .notRequired,
    searchTerms: ["allow javascript", "safari allow java script", "safariallowjavascript"],
    semantics: .toggle
),
RestrictionDefinition(
    key: .safariAllowPopups,
    title: "Allow Pop-ups",
    summary: "If `false`, Safari doesn't allow pop-up windows. Support for this restriction on unsupervised devices is deprecated.",
    minimumOS: "iPadOS 4.0",
    supervision: .notRequired,
    searchTerms: ["allow pop-ups", "safari allow popups", "safariallowpopups"],
    semantics: .toggle
),
RestrictionDefinition(
    key: .safariForceFraudWarning,
    title: "Enable Fraud Warning",
    summary: "If `true`, the system enables Safari fraud warning.",
    minimumOS: "iPadOS 4.0",
    supervision: .notRequired,
    searchTerms: ["enable fraud warning", "safari force fraud warning", "safariforcefraudwarning"],
    semantics: .toggle
)
    ]

    static func definition(for key: RestrictionKey) -> RestrictionDefinition {
        iPadOS.first(where: { $0.key == key })!
    }

    static func resolve(_ value: String) -> RestrictionKey? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exactKey = RestrictionKey(rawValue: cleaned) { return exactKey }
        let normalised = cleaned.lowercased()
        let matches = iPadOS.filter { definition in
            definition.title.lowercased() == normalised ||
                definition.searchTerms.contains(normalised)
        }
        return matches.count == 1 ? matches[0].key : nil
    }

    static func relevant(to prompt: String, limit: Int = 20) -> [RestrictionDefinition] {
        let query = prompt.lowercased()
        let matches = iPadOS.filter { definition in
            definition.searchTerms.contains(where: query.contains)
        }
        return Array(matches.prefix(limit))
    }
}

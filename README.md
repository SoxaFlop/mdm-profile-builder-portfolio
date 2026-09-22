# MDM Profile Builder Demo

A sanitised, native macOS portfolio project for drafting and validating Apple device-management configuration profiles. The app is written in Swift and SwiftUI and opens in Xcode. This repository is a separate demonstration copy: it has no connection to an organisation's live Jamf tenant, licensing service or deployment pipeline.

## What the code demonstrates

- A typed `ProfileIntent` model rather than unrestricted AI-generated XML.
- Validation before compiling a draft Apple `.mobileconfig` profile.
- A SwiftUI builder, conversation pane, validation summary and XML preview.
- Local AI paths and a deterministic offline command layer.
- Keychain-backed credential storage for optional integrations.
- A read-only Jamf School discovery connector. Optional Platform API blueprint operations are isolated behind explicit user confirmation and must be tested only against an authorised test tenant.
- Swift tests for the profile compiler, validation and integration boundaries.

The portfolio copy excludes the original branding and artwork, licensing backend, distribution scripts, live service configuration, credentials, exported profiles and inherited Git history. The Xcode project uses a generic bundle identifier and development access settings. It is **not a production MDM administration tool**.

## Open locally

1. Open `MDMCopilot.xcodeproj` in Xcode and select the `MDMCopilot` scheme with **My Mac** as the destination.
2. Let Xcode resolve the pinned Swift packages in `Package.resolved`. The optional local-model dependencies may take time to build and require an appropriate Apple silicon Mac.
3. Run the app in Debug. Use only fictional profile details and an isolated test tenant if you choose to configure Jamf School.
4. Run the Swift test suite with `swift test`.

No `.env`, API key, tenant URL or production service is needed to inspect the source. Never paste a real credential into a source file, test, issue or pull request.

## Safety boundaries

The default portfolio configuration does not contain a licence service URL or signing key. The legacy Jamf School connector is read-only. Blueprint write methods, where present, require a separate authorised integration and explicit confirmation; do not point the demo at a production tenant. Generated profiles must be reviewed by a technician before use.

See [SECURITY.md](SECURITY.md) for the disclosure and credential-handling policy. Third-party notices are in [Documentation/THIRD-PARTY-NOTICES.md](Documentation/THIRD-PARTY-NOTICES.md).

## Licence

MIT. See [LICENSE](LICENSE).

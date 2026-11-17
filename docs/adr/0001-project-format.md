# ADR-0001: Keep the Xcode 27 JSON project format; link ParsecKit via package-product-members

- Status: Accepted (2026-11-16, M0)
- Context: The template uses the JSON `project.xcproj` format, where synchronized folders add files automatically. Adding a local Swift package to this format is undocumented (PRD §6.3).
- Decision: Step 2 of the ladder worked, so we did not fall back to xcodegen. We found the syntax by trial against `xcprojformatter`, then confirmed it with a real `xcodebuild` build plus the `APP-001` test:
  - Top level: `"packages": [ { "kind": "local", "path": "Packages/ParsecKit" } ]`
  - App target: `"package-product-members": [ { "product-name": "ParsecEngine", "build-phase": { "build-phase": "frameworks" } }, … ]`
- Rename: target, folder and scheme names stay `SpaceTraderMac`. The product is `Parsec Merchant`, the module is `ParsecMerchant`, and the bundle id is `io.github.megatih.ParsecMerchant` (Debug adds `.debug`). The target's `"product"` reference and the Products group entry must use `Products/Parsec Merchant.app`. Otherwise Xcode fails with "Invalid reference".
- Consequences: Run `xcrun xcprojformatter --update SpaceTraderMac.xcodeproj` after every hand edit; it rejects unknown file kinds and drops unknown keys. Only the app target links package products. Test bundles reach the engine through `@testable import ParsecMerchant` to avoid linking the static libraries twice.
- `DEVELOPMENT_TEAM` (revised in M13): the JSON format has no base-xcconfig key, so PRD §6.3's optional `Config/Local.xcconfig` cannot be wired in. Instead, the project sets no team at all: automatic signing then uses "Sign to Run Locally" (ad-hoc) for every target, so a public clone builds with no account and no edits (PRD §10 check 6, verified by building with no team). The release build passes the same settings explicitly (`scripts/release.sh`). A developer who wants their own team picks it in Xcode's Signing & Capabilities and does not commit that change.

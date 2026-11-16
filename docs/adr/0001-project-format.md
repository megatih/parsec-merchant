# ADR-0001: Keep the Xcode 27 JSON project format; link ParsecKit via package-product-members

- Status: Accepted (2026-11-16, M0)
- Context: The template uses the JSON `project.xcproj` format, where synchronized folders add files automatically. Adding a local Swift package to this format is undocumented (PRD §6.3).
- Decision: Step 2 of the ladder worked, so we did not fall back to xcodegen. We found the syntax by trial against `xcprojformatter`, then confirmed it with a real `xcodebuild` build plus the `APP-001` test:
  - Top level: `"packages": [ { "kind": "local", "path": "Packages/ParsecKit" } ]`
  - App target: `"package-product-members": [ { "product-name": "ParsecEngine", "build-phase": { "build-phase": "frameworks" } }, … ]`
- Rename: target, folder and scheme names stay `SpaceTraderMac`. The product is `Parsec Merchant`, the module is `ParsecMerchant`, and the bundle id is `io.github.megatih.ParsecMerchant` (Debug adds `.debug`). The target's `"product"` reference and the Products group entry must use `Products/Parsec Merchant.app`. Otherwise Xcode fails with "Invalid reference".
- Consequences: Run `xcrun xcprojformatter --update SpaceTraderMac.xcodeproj` after every hand edit; it rejects unknown file kinds and drops unknown keys. Only the app target links package products. Test bundles reach the engine through `@testable import ParsecMerchant` to avoid linking the static libraries twice.
- `DEVELOPMENT_TEAM`: the JSON format has no base-xcconfig key, so the team id stays in the project for now. M13 revisits signing for clean clones (release builds use "Sign to Run Locally").

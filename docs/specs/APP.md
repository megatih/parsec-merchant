# APP: Application integration and project setup

> Format (PRD §7): `- **ID** {Mn} [M][W][P] statement (source)`. Tags: `[UI]` = covered by app or UI tests; `[manual]` = covered by a QA-REPORT row.

- **APP-001** {M0} [M][W][P] [UI] The app target links the `ParsecEngine` product of the local `ParsecKit` package, and app code can call engine symbols. (ADR-0001)
- **APP-002** {M0} [M][W][P] [UI] The app launches and shows its main window. (UI smoke test)
- **APP-003** {M0} [M][W][P] [manual] The product name is "Parsec Merchant". The bundle id is `io.github.megatih.ParsecMerchant`, with `.debug` added in Debug builds. (PRD §6.3)

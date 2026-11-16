// SPDX-License-Identifier: GPL-2.0-or-later
import SwiftUI
import ParsecEngine

/// Static information about the app and its linked engine.
enum AppInfo {
    static let engineVersion = ParsecEngineInfo.version
}

@main
struct ParsecMerchantApp: App {
    var body: some Scene {
        Window("Parsec Merchant", id: "main") {
            PlaceholderView()
        }
        .defaultSize(width: 1320, height: 860)
    }
}

/// Temporary root view until the app shell lands in M7.
struct PlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Parsec Merchant")
                .font(.largeTitle)
            Text("Engine \(AppInfo.engineVersion)")
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 640, minHeight: 400)
        .accessibilityIdentifier("placeholder.root")
    }
}

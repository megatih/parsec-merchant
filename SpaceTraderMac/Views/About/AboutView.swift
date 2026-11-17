// SPDX-License-Identifier: GPL-2.0-or-later
import ParsecArt
import Foundation
import ParsecEngine
import SwiftUI

/// The About window's facts (UI-SHELL-106, CREDITS.md).
nonisolated enum AboutContent {
    struct Credit: Identifiable, Equatable {
        /// The identifier qualifier (`about.link.<id>`).
        var id: String
        var names: String
        var role: LocalizedStringResource
        var url: URL?

        static func == (a: Credit, b: Credit) -> Bool { a.id == b.id && a.names == b.names && a.url == b.url }
    }

    static let credits: [Credit] = [
        Credit(id: "spronck", names: "Pieter Spronck", role: "Design and original code of Space Trader for Palm OS",
               url: URL(string: "https://www.spronck.net/spacetrader/")),
        Credit(id: "andersonGoldstein", names: "Sam Anderson and Samuel Goldstein", role: "Additional coding (Palm OS)", url: nil),
        Credit(id: "lee", names: "Matt Lee", role: "DopeWars, from which parts of the original trading code were derived", url: nil),
        Credit(id: "french", names: "Jay French", role: "Space Trader for Windows 2.01 (C# port)",
               url: URL(string: "https://github.com/SpaceTraderGame/SpaceTrader-Windows")),
        Credit(id: "pierron", names: "David Pierron", role: "Additional coding (Windows)", url: nil),
    ]

    static let basedOn: LocalizedStringResource = "Based on Space Trader by Pieter Spronck."
    static let gplNotice: LocalizedStringResource = """
        Parsec Merchant is free software under the GNU General Public License, version 2 or later. \
        It comes with ABSOLUTELY NO WARRANTY.
        """
    static let artworkNote: LocalizedStringResource = """
        All artwork, icons and sounds are new and generated in code. None of the original Space Trader pictures are used.
        """
    static let trademarkNote: LocalizedStringResource = """
        “Space Trader” is used only to credit the original work. Parsec Merchant is not affiliated with HermitWorks \
        Entertainment or any owner of that name.
        """

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static var engineVersion: String { ParsecEngineInfo.version }

    /// The bundled resource text (LICENSE as `License.txt`, CREDITS.md as `Credits.md`; UI-SHELL-107).
    static func bundledText(_ name: String, _ ext: String, bundle: Bundle = .main) -> String {
        let url = bundle.url(forResource: name, withExtension: ext)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "Legal")
        return url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }

    static var licenseText: String { bundledText("License", "txt") }
}

/// About Parsec Merchant (UI-SHELL-106). Contains no original Space Trader image.
struct AboutView: View {
    @Environment(\.openURL) private var openURL
    @State private var showsLicense = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading) {
                        ArtAccessibilityReader { a11y in
                            Wordmark(size: 26, increaseContrast: a11y.increaseContrast)
                        }
                        Text("Version \(AboutContent.appVersion) (\(AboutContent.build)) · Engine \(AboutContent.engineVersion)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Text(AboutContent.basedOn).font(.headline)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(AboutContent.credits) { credit in
                        VStack(alignment: .leading, spacing: 2) {
                            if let url = credit.url {
                                Button { openURL(url) } label: { Text(verbatim: credit.names).bold() }
                                    .buttonStyle(.link)
                                    .accessibilityIdentifier(AXID.About.link(credit.id))
                            } else {
                                Text(verbatim: credit.names).bold()
                                    .accessibilityIdentifier(AXID.About.link(credit.id))
                            }
                            Text(credit.role).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                Divider()
                Text(AboutContent.gplNotice)
                Text(AboutContent.artworkNote).font(.callout).foregroundStyle(.secondary)
                Text(AboutContent.trademarkNote).font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("View License") { showsLicense = true }
                        .accessibilityIdentifier(AXID.About.license)
                    Button("GitHub Project") { openURL(MenuCatalog.githubURL) }
                        .accessibilityIdentifier(AXID.About.github)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 520, height: 600)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AXID.About.window)
        .sheet(isPresented: $showsLicense) {
            LicenseSheet()
        }
        .modifier(AppTextSize())
    }
}

/// The bundled GPL text in a scrolling sheet.
struct LicenseSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            ScrollView {
                Text(verbatim: AboutContent.licenseText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier(AXID.About.licenseClose)
        }
        .padding(20)
        .frame(width: 620, height: 520)
    }
}

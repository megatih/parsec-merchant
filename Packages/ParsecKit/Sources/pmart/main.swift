// SPDX-License-Identifier: GPL-2.0-or-later
// pmart: renders ParsecArt to PNG files (ART-054).
//   pmart icon --out <dir> [--check <dir>]   AppIcon.icon/{icon.json,Assets/*.png} and Assets.xcassets/AppIcon.appiconset/*.png
//   pmart sheet --out <file.png> [--page planets]   a contact sheet (development aid); pages: planets (ART-079)
import Foundation
import ParsecArt
import SwiftUI

let args = Array(CommandLine.arguments.dropFirst())

func value(_ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("pmart: \(message)\n".utf8))
    exit(1)
}

let code: Int32 = MainActor.assumeIsolated {
    switch args.first {
    case "icon":
        guard let out = value("--out") else { fail("usage: pmart icon --out <dir> [--check <dir>]") }
        do {
            let written = try IconExport.write(to: URL(fileURLWithPath: out))
            print("pmart: wrote \(written.count) files to \(out)")
            if let check = value("--check") {
                let problems = IconExport.compare(written, outRoot: URL(fileURLWithPath: out), against: URL(fileURLWithPath: check))
                for p in problems { print("pmart: DIFF \(p)") }
                return problems.isEmpty ? 0 : 1
            }
            return 0
        } catch {
            fail("\(error)")
        }
    case "sheet":
        guard let out = value("--out") else { fail("usage: pmart sheet --out <file.png> [--page planets]") }
        do {
            try ContactSheet.write(to: URL(fileURLWithPath: out), page: value("--page"))
            print("pmart: wrote \(out)")
            return 0
        } catch {
            fail("\(error)")
        }
    default:
        print("usage: pmart icon --out <dir> [--check <dir>] | pmart sheet --out <file.png> [--page planets]")
        return 2
    }
}
exit(code)

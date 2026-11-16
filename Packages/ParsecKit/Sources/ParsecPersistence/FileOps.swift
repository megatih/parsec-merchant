// SPDX-License-Identifier: GPL-2.0-or-later
// File primitives shared by the stores (SAV-018, SAV-024): same-directory atomic writes and quarantine.
import Foundation

enum FileOps {
    /// SAV-018: writes `data` to a temporary file in the target's directory, then renames it over the target, so the
    /// target always holds either the complete old or the complete new bytes. The temporary file never survives.
    static func atomicWrite(_ data: Data, to target: URL) throws {
        let dir = target.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let temp = dir.appendingPathComponent(".\(target.lastPathComponent).tmp-\(UUID().uuidString.lowercased())")
        do {
            try data.write(to: temp)
            guard rename(temp.path, target.path) == 0 else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: target.path,
                                                               NSUnderlyingErrorKey: POSIXError(.init(rawValue: errno) ?? .EIO)])
            }
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }

    /// SAV-024: moves `file` into `corruptDirectory` under its own name, prefixed `1-`, `2-`, … when the name is taken.
    /// Never copies, never deletes.
    @discardableResult
    static func quarantine(_ file: URL, into corruptDirectory: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: corruptDirectory, withIntermediateDirectories: true)
        var dest = corruptDirectory.appendingPathComponent(file.lastPathComponent)
        var n = 1
        while fm.fileExists(atPath: dest.path) {
            dest = corruptDirectory.appendingPathComponent("\(n)-\(file.lastPathComponent)")
            n += 1
        }
        try fm.moveItem(at: file, to: dest)
        return dest
    }

    static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
}

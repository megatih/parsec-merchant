// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// Loads JSON fixtures copied into the test bundle (Tests/ParsecEngineTests/Fixtures).
enum Fixtures {
    static func data(_ path: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: "Fixtures/" + path, withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: path])
        }
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ path: String) throws -> T {
        try JSONDecoder().decode(T.self, from: data(path))
    }
}

import Foundation

enum AppDirectories {
    static let appName = "ZihuMusic"

    static var defaultMusicFolder: URL {
        FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Music", isDirectory: true)
    }

    static var applicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent(appName, isDirectory: true)
    }

    static var libraryFile: URL {
        applicationSupportDirectory.appendingPathComponent("library.json")
    }

    static var artworkDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Artwork", isDirectory: true)
    }

    static func ensureCreated() throws {
        try FileManager.default.createDirectory(at: applicationSupportDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
    }
}

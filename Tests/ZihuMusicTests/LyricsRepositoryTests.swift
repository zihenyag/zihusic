import XCTest
@testable import ZihuMusic

@MainActor
final class LyricsRepositoryTests: XCTestCase {
    func testCachedPreviewSurvivesRelaunchWithoutOpeningTheSource() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sidecar = directory.appendingPathComponent("song.lrc")
        try "[00:01.00]Original\n[00:01.00]翻译".write(to: sidecar, atomically: true, encoding: .utf8)
        let track = MusicTrack(filePath: "/test/song.flac", title: "Song", format: "FLAC", lyricsFilePath: sidecar.path)
        let first = await LyricsRepository(directory: directory.appendingPathComponent("cache")).timeline(for: track)
        try FileManager.default.removeItem(at: sidecar)
        let repository = LyricsRepository(directory: directory.appendingPathComponent("cache"))
        let preview = await repository.preview(for: track)
        XCTAssertEqual(preview, first)
        XCTAssertEqual(preview?.lines.first?.text, "Original\n翻译")
    }

    func testEditedSidecarRefreshesThePreviewAndUnrelatedMetadataKeepsTheCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sidecar = directory.appendingPathComponent("song.lrc")
        try "[00:01.00]Before".write(to: sidecar, atomically: true, encoding: .utf8)
        var track = MusicTrack(filePath: "/test/song.flac", title: "Song", format: "FLAC", lyricsFilePath: sidecar.path)
        let repository = LyricsRepository(directory: directory.appendingPathComponent("cache"))
        let before = await repository.timeline(for: track)
        track.title = "Renamed"
        track.updatedAt = Date()
        XCTAssertEqual(repository.cached(for: .init(track)), before)
        try "[00:02.00]After editing".write(to: sidecar, atomically: true, encoding: .utf8)
        let preview = await repository.preview(for: track)
        XCTAssertEqual(preview, before)
        let after = await repository.timeline(for: track)
        XCTAssertEqual(after.lines.first?.text, "After editing")
        XCTAssertEqual(after.lines.first?.time, 2)
    }

    func testChangedEmbeddedLyricsNeverReuseThePreviousTrackText() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = LyricsRepository(directory: directory)
        var track = MusicTrack(filePath: "/test/song.flac", title: "Song", format: "FLAC", embeddedLyrics: "[00:01]First")
        _ = await repository.timeline(for: track)
        track.embeddedLyrics = "[00:01]Second"
        XCTAssertNil(repository.cached(for: .init(track)))
        let updated = await repository.timeline(for: track)
        XCTAssertEqual(updated.lines.first?.text, "Second")
    }
}

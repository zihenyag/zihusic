import Foundation

struct DownloadResult: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var artist: String
    var album: String
    var format: String
    var sizeDescription: String
    var downloadURL: URL
    var sourcePageURL: URL?
}

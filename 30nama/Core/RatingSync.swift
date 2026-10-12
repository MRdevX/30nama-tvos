import Foundation

/// Where the ratings are kept off the device.
protocol RatingCloud: Sendable {
    /// The stored book and a tag naming that version of it, or nil when nothing has been stored yet.
    func load() async throws -> (data: Data, tag: String)?
    /// Stores a book built on the version named by `tag` (nil when there was none).
    /// Throws `RatingCloudError.changed` when the stored book has moved on since that version.
    func save(_ data: Data, replacing tag: String?) async throws
}

enum RatingCloudError: Error {
    /// Another device saved in the meantime.
    case changed
    /// No account to store under.
    case unavailable
}

/// Brings the ratings on this device and the stored ones to the same state.
enum RatingSync {
    /// Merges `local` with the stored book, stores the result if that changes anything, and
    /// returns it. When another device saves in between, starts over from what that device saved.
    static func run(local: RatingBook, cloud: RatingCloud, attempts: Int = 3) async throws -> RatingBook {
        for _ in 0..<attempts {
            let stored = try await cloud.load()
            // A stored book that cannot be read is replaced rather than left in the way.
            let theirs = stored.flatMap { RatingBook(data: $0.data) }
            let merged = local.merged(with: theirs ?? RatingBook())
            if merged == theirs { return merged }
            do {
                try await cloud.save(merged.encoded(), replacing: stored?.tag)
                return merged
            } catch RatingCloudError.changed {
                continue
            }
        }
        throw RatingCloudError.changed
    }
}

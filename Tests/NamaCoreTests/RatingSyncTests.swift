import XCTest
@testable import NamaCore

/// iCloud in miniature: one stored book with a version tag, and other devices that can save in between.
private final class FakeCloud: RatingCloud, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private var version = 0
    private var interruptions: [RatingBook] = []
    private(set) var saves = 0
    var signedIn = true

    init(_ book: RatingBook? = nil) { data = book?.encoded() }

    var book: RatingBook? { lock.withLock { data.flatMap(RatingBook.init(data:)) } }
    func store(raw: Data) { lock.withLock { data = raw; version += 1 } }
    /// Another device saves `book` just before our next save lands.
    func interrupt(with book: RatingBook) { lock.withLock { interruptions.append(book) } }

    func load() async throws -> (data: Data, tag: String)? {
        guard signedIn else { throw RatingCloudError.unavailable }
        return lock.withLock { data.map { ($0, String(version)) } }
    }

    func save(_ data: Data, replacing tag: String?) async throws {
        try lock.withLock {
            if !interruptions.isEmpty {
                self.data = interruptions.removeFirst().encoded()
                version += 1
            }
            guard tag == (self.data == nil ? nil : String(version)) else { throw RatingCloudError.changed }
            self.data = data
            version += 1
            saves += 1
        }
    }
}

final class RatingSyncTests: XCTestCase {
    private func book(_ entries: (id: Int, stars: Double?, at: TimeInterval)...) -> RatingBook {
        var book = RatingBook()
        for e in entries {
            let post = Post(JSON(["id": e.id, "title": ["english": "Title \(e.id)"], "genre": [["name": "Drama", "slug": "drama"]]] as [String: Any]))!
            if e.stars == nil { book.rate(post, stars: 1, date: Date(timeIntervalSince1970: e.at - 1)) }
            book.rate(post, stars: e.stars, date: Date(timeIntervalSince1970: e.at))
        }
        return book
    }

    func testFirstSyncUploadsWhatIsOnTheDevice() async throws {
        let cloud = FakeCloud()
        let local = book((1, 4, 10))
        let result = try await RatingSync.run(local: local, cloud: cloud)
        XCTAssertEqual(result, local)
        XCTAssertEqual(cloud.book, local)
    }

    func testRatingsFromAnotherDeviceComeDown() async throws {
        let cloud = FakeCloud(book((1, 4, 10), (2, 5, 20)))
        let result = try await RatingSync.run(local: RatingBook(), cloud: cloud)
        XCTAssertEqual(result.stars(for: 2), 5)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(cloud.saves, 0, "nothing new to send")
    }

    func testBothSidesEndUpWithTheSameBook() async throws {
        let cloud = FakeCloud(book((1, 4, 10), (2, 5, 20)))
        let result = try await RatingSync.run(local: book((2, nil, 30), (3, 2, 5)), cloud: cloud)
        XCTAssertEqual(result.stars(for: 1), 4)
        XCTAssertNil(result.stars(for: 2), "removed here after it was rated there")
        XCTAssertEqual(result.stars(for: 3), 2)
        XCTAssertEqual(cloud.book, result)
        XCTAssertEqual(cloud.saves, 1)
    }

    func testStartsOverWhenAnotherDeviceSavesInBetween() async throws {
        let cloud = FakeCloud(book((1, 4, 10)))
        cloud.interrupt(with: book((1, 4, 10), (9, 3, 15)))
        let result = try await RatingSync.run(local: book((2, 5, 20)), cloud: cloud)
        XCTAssertEqual(Set(result.ratings.keys), [1, 2, 9], "the other device's rating is not overwritten")
        XCTAssertEqual(cloud.book, result)
    }

    func testGivesUpWhenItKeepsLosingTheRace() async {
        let cloud = FakeCloud(book((1, 4, 10)))
        for n in 0..<3 { cloud.interrupt(with: book((1, 4, 10), (100 + n, 3, 15))) }
        do {
            _ = try await RatingSync.run(local: book((2, 5, 20)), cloud: cloud)
            XCTFail("expected the sync to give up")
        } catch {
            XCTAssertEqual(error as? RatingCloudError, .changed)
        }
        XCTAssertEqual(cloud.saves, 0)
    }

    func testAStoredBookThatCannotBeReadIsReplaced() async throws {
        let cloud = FakeCloud()
        cloud.store(raw: Data("not a book".utf8))
        let local = book((1, 4, 10))
        _ = try await RatingSync.run(local: local, cloud: cloud)
        XCTAssertEqual(cloud.book, local)
    }

    func testWithoutAnAccountNothingIsTouched() async {
        let cloud = FakeCloud()
        cloud.signedIn = false
        do {
            _ = try await RatingSync.run(local: book((1, 4, 10)), cloud: cloud)
            XCTFail("expected the sync to stop")
        } catch {
            XCTAssertEqual(error as? RatingCloudError, .unavailable)
        }
        XCTAssertNil(cloud.book)
    }
}

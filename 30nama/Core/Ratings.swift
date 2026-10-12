import Foundation

/// One title the user has rated, with just enough of the title kept to show it again without the network.
struct Rating: Codable, Equatable, Identifiable {
    var postID: Int
    /// Half-star steps from 0.5 to 5.
    var stars: Double
    var date: Date
    var titleEnglish: String?
    var titleLocal: String?
    var year: Int?
    var isSeries: Bool
    var isAnime: Bool
    var genres: [Genre]
    var posterLarge: URL?
    var posterBig: URL?
    var blurhash: String?

    struct Genre: Codable, Equatable {
        var name: String
        var slug: String
    }

    var id: Int { postID }

    init(post: Post, stars: Double, date: Date = Date()) {
        postID = post.id
        self.stars = Rating.snap(stars)
        self.date = date
        titleEnglish = post.titleEnglish
        titleLocal = post.titleLocal
        year = post.year
        isSeries = post.isSeries
        isAnime = post.kind == .anime
        genres = post.genres.map { Genre(name: $0.name, slug: $0.slug) }
        posterLarge = post.poster.large
        posterBig = post.poster.big
        blurhash = post.poster.blurhash
    }

    /// Nearest half star within 0.5...5.
    static func snap(_ stars: Double) -> Double {
        min(5, max(0.5, (stars * 2).rounded() / 2))
    }

    /// The title as a `Post`, so it can be drawn by the same cards and opened like any other.
    var post: Post? {
        var poster: [String: Any] = [:]
        if let blurhash { poster["preview"] = blurhash }
        var webp: [String: Any] = [:]
        if let posterLarge { webp["large"] = posterLarge.absoluteString }
        if let posterBig { webp["big"] = posterBig.absoluteString }
        poster["webp"] = webp
        var title: [String: Any] = [:]
        if let titleEnglish { title["english"] = titleEnglish }
        if let titleLocal { title["local"] = titleLocal }
        var info: [String: Any] = [:]
        if let year { info["year"] = year }
        var options: [String: Any] = ["is_series": isSeries]
        if isAnime { options["title_type"] = "anime" }
        return Post(JSON([
            "id": postID, "title": title, "info": info, "options": options,
            "genre": genres.map { ["name": $0.name, "slug": $0.slug] },
            "image": ["poster": poster],
        ] as [String: Any]))
    }
}

/// Everything the user has rated, and what that says about their taste.
struct RatingBook: Equatable {
    private(set) var ratings: [Int: Rating] = [:]

    init(_ ratings: [Rating] = []) {
        for r in ratings { self.ratings[r.postID] = r }
    }

    init?(data: Data) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let list = try? decoder.decode([Rating].self, from: data) else { return nil }
        self.init(list)
    }

    func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return (try? encoder.encode(newestFirst)) ?? Data()
    }

    var count: Int { ratings.count }
    var isEmpty: Bool { ratings.isEmpty }
    var newestFirst: [Rating] { ratings.values.sorted { ($0.date, $0.postID) > ($1.date, $1.postID) } }
    var average: Double? { isEmpty ? nil : ratings.values.map(\.stars).reduce(0, +) / Double(count) }

    func stars(for postID: Int) -> Double? { ratings[postID]?.stars }

    /// Sets the rating for a title, or removes it when `stars` is nil.
    mutating func rate(_ post: Post, stars: Double?, date: Date = Date()) {
        if let stars {
            ratings[post.id] = Rating(post: post, stars: stars, date: date)
        } else {
            ratings[post.id] = nil
        }
    }

    // MARK: Taste

    /// A rating above this counts for a genre, below it against.
    static let neutral = 3.0

    /// How much the user likes each genre: the average of (stars - neutral) over the titles rated
    /// in it, shrunk toward zero when there are only a few, so one five-star western does not
    /// outweigh ten four-star dramas.
    func taste() -> [String: Double] {
        var sum: [String: Double] = [:], n: [String: Double] = [:]
        for r in ratings.values {
            for g in r.genres {
                sum[g.slug, default: 0] += r.stars - RatingBook.neutral
                n[g.slug, default: 0] += 1
            }
        }
        return sum.reduce(into: [:]) { out, entry in
            let count = n[entry.key] ?? 1
            out[entry.key] = entry.value / (count + 2)
        }
    }

    /// Genres the user rates highest, best first.
    func favoriteGenres(limit: Int = 3) -> [String] {
        taste().filter { $0.value > 0 }.sorted { ($0.value, $0.key) > ($1.value, $1.key) }.prefix(limit).map(\.key)
    }

    /// How well a title fits the user's taste. Positive means "probably yes".
    func affinity(for post: Post, taste: [String: Double]) -> Double {
        let known = post.genres.compactMap { taste[$0.slug] }
        guard !known.isEmpty else { return 0 }
        let fit = known.reduce(0, +) / Double(known.count)
        // Between two titles that fit equally, prefer the better-regarded one.
        let acclaim = ((post.imdbScore ?? 6.5) - 6.5) * 0.08
        return fit + acclaim
    }

    /// Titles from `candidates` the user has not rated, best fit first, leaving out poor fits.
    func recommend(from candidates: [Post], limit: Int = 20) -> [Post] {
        let taste = taste()
        guard !taste.isEmpty else { return [] }
        var seen = Set(ratings.keys)
        return candidates
            .filter { seen.insert($0.id).inserted && !$0.comingSoon }
            .map { ($0, affinity(for: $0, taste: taste)) }
            .filter { $0.1 > 0 }
            .sorted { ($0.1, $0.0.id) > ($1.1, $1.0.id) }
            .prefix(limit)
            .map(\.0)
    }
}

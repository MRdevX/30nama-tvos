import SwiftUI

/// The user's own page: who they are, what their ratings say about their taste, the lists they
/// keep on 30nama, and what all that suggests they watch next.
struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.loc) private var loc

    @State private var picks: [Post] = []
    @State private var starters: [Post] = []
    @State private var watchlist: [Post] = []
    @State private var favorites: [Post] = []
    /// The full size of each list; the shelves only show the latest additions.
    @State private var listSizes: [String: Int] = [:]

    private let columns = Array(repeating: GridItem(.fixed(Theme.posterWidth), spacing: 32), count: 7)
    private static let gold = Color(hex: 0xF5C518)

    /// The title whose artwork washes the page: something the user chose, else something they rated.
    private var backdrop: Post? {
        favorites.first ?? watchlist.first ?? app.ratings.newestFirst.first?.post
    }

    var body: some View {
        ZStack {
            AmbientBackground()
            StageView(post: backdrop, dim: 0.5, glow: false)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 48) {
                    header
                    if !app.ratings.isEmpty { insights }
                    if !picks.isEmpty { shelf(loc(.forYou), posts: picks) }
                    if !watchlist.isEmpty { shelf(loc(.watchlist), posts: watchlist) }
                    if !favorites.isEmpty { shelf(loc(.favorites), posts: favorites) }
                    if app.ratings.isEmpty { emptyState } else { ratedGrid }
                }
                .padding(.horizontal, Theme.edge + 4)
                .padding(.top, 40)
                .padding(.bottom, 80)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        .overlay(alignment: .top) { TopShade() }
        .task(id: app.ratings) { await refresh() }
        .task(id: app.user?.id) { await loadLists() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 40) {
            avatar
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 18) {
                    Text(app.user?.name ?? loc(.guestAccount))
                        .font(.app(60, .heavy))
                        .foregroundStyle(LinearGradient(colors: [.white, Theme.text1.opacity(0.82)], startPoint: .top, endPoint: .bottom))
                        .lineLimit(1)
                        .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
                    if let type = app.user?.type {
                        Text(loc.accountType(type))
                            .font(.app(22, .bold))
                            .foregroundStyle(Theme.focusInk)
                            .padding(.horizontal, 18)
                            .frame(height: 40)
                            .background(Capsule(style: .continuous).fill(LinearGradient(colors: [Color(hex: 0xFFE27A), ProfileView.gold], startPoint: .top, endPoint: .bottom)))
                    }
                }
                HStack(spacing: 16) {
                    if !app.ratings.isEmpty {
                        Stat(value: loc.num(app.ratings.count), label: loc(.ratedCount))
                        if let average = app.ratings.average {
                            Stat(value: loc.num(Fmt.score(average)), label: loc(.averageRating), symbol: "star.fill")
                        }
                    }
                    if !watchlist.isEmpty { Stat(value: loc.num(listSizes["watchlist"] ?? watchlist.count), label: loc(.watchlist)) }
                    if !favorites.isEmpty { Stat(value: loc.num(listSizes["favorite"] ?? favorites.count), label: loc(.favorites)) }
                }
                // For the user's own eyes, and not the point of the page: kept small and quiet.
                if let user = app.user, let line = loc.subscriptionLine(user) {
                    Text(line)
                        .font(.app(21))
                        .foregroundStyle(Theme.text3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 30)
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(hex: 0xFF6A4D), Theme.accent, Color(hex: 0xD92B58)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let initials {
                Text(initials)
                    .font(.app(64, .heavy))
                    .foregroundStyle(.white)
                    .environment(\.layoutDirection, .leftToRight)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.white)
            }
            if let url = app.user?.avatar {
                RemoteImage(url: url, maxPixel: Int(180 * UIScreen.main.scale))
            }
        }
        .frame(width: 180, height: 180)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom), lineWidth: 3) }
        .shadow(color: Theme.accent.opacity(0.45), radius: 34, y: 10)
    }

    private struct Stat: View {
        let value: String
        let label: String
        var symbol: String?

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    if let symbol {
                        Image(systemName: symbol).font(.system(size: 22, weight: .bold)).foregroundStyle(ProfileView.gold)
                    }
                    Text(value).font(.app(36, .heavy)).foregroundStyle(Theme.text1)
                }
                Text(label).font(.app(20, .medium)).foregroundStyle(Theme.text3)
            }
            .padding(.horizontal, 26)
            .frame(minWidth: 150, minHeight: 96, alignment: .leading)
            .glass(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
        }
    }

    /// Initials of the signed-in name, or nil for a guest (who gets a person glyph instead).
    private var initials: String? {
        guard let name = app.user?.name else { return nil }
        let words = name.split(separator: " ")
        let letters = [words.first?.first, words.count > 1 ? words.last?.first : nil].compactMap { $0 }
        return letters.isEmpty ? nil : String(letters).uppercased()
    }

    // MARK: Taste

    /// What the ratings add up to: the genres that do best, and how generous the user is with stars.
    private var insights: some View {
        HStack(alignment: .top, spacing: 28) {
            panel(loc(.yourTaste)) {
                let genres = app.ratings.favoriteGenreNames()
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(genres.enumerated()), id: \.offset) { _, genre in
                        HStack(spacing: 18) {
                            Text(genre.name)
                                .font(.app(24, .semibold))
                                .foregroundStyle(Theme.text1)
                                .lineLimit(1)
                                .frame(width: 190, alignment: .leading)
                            GeometryReader { geo in
                                Capsule().fill(Color.white.opacity(0.1))
                                Capsule()
                                    .fill(LinearGradient(colors: [Color(hex: 0xFF6A4D), Theme.accent], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(12, geo.size.width * genre.strength))
                            }
                            .frame(height: 12)
                        }
                    }
                }
            }
            panel(loc(.howYouRate)) {
                let spread = app.ratings.spread()
                let most = max(1, spread.max() ?? 1)
                HStack(alignment: .bottom, spacing: 22) {
                    ForEach(Array(spread.enumerated()), id: \.offset) { index, count in
                        VStack(spacing: 10) {
                            Text(count > 0 ? loc.num(count) : " ")
                                .font(.app(20, .semibold))
                                .foregroundStyle(Theme.text2)
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(count > 0 ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFFE27A), ProfileView.gold], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.white.opacity(0.1)))
                                .frame(width: 54, height: max(8, 92 * CGFloat(count) / CGFloat(most)))
                            HStack(spacing: 4) {
                                Text(loc.num(index + 1)).font(.app(20, .semibold))
                                Image(systemName: "star.fill").font(.system(size: 14, weight: .bold))
                            }
                            .foregroundStyle(Theme.text3)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func panel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(title).font(.app(24, .semibold)).foregroundStyle(Theme.text3)
            content()
            Spacer(minLength: 0)
        }
        .padding(30)
        .frame(maxWidth: .infinity, minHeight: 250, maxHeight: 250, alignment: .topLeading)
        .glass(RoundedRectangle(cornerRadius: Theme.tileRadius + 6, style: .continuous))
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 34) {
            VStack(alignment: .leading, spacing: 14) {
                Text(loc(.noRatingsYet)).font(.app(34, .bold)).foregroundStyle(Theme.text1)
                Text(loc(.rateHint)).font(.app(26)).foregroundStyle(Theme.text2)
            }
            if !starters.isEmpty { shelf(loc(.startWithThese), posts: starters) }
        }
    }

    // MARK: Shelves

    private func shelf(_ title: String, posts: [Post]) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title).font(.app(32, .bold)).foregroundStyle(Theme.text1)
            ScrollView(.horizontal) {
                // Not lazy, for the reason given on Home: focus arriving from the side must find a card.
                HStack(spacing: 24) {
                    ForEach(posts) { PosterLink(post: $0) }
                }
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .focusSection()
        }
    }

    private var ratedGrid: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(loc(.yourRating)).font(.app(32, .bold)).foregroundStyle(Theme.text1)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 36) {
                ForEach(app.ratings.newestFirst) { rating in
                    if let post = rating.post {
                        PosterLink(post: post)
                            .overlay(alignment: .bottomLeading) {
                                HStack(spacing: 6) {
                                    Image(systemName: "star.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(ProfileView.gold)
                                    Text(loc.num(Fmt.score(rating.stars))).font(.app(20, .bold)).foregroundStyle(.white)
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .background(Capsule(style: .continuous).fill(Color.black.opacity(0.72)))
                                .padding(10)
                                .allowsHitTesting(false)
                            }
                    }
                }
            }
            .focusSection()
        }
    }

    // MARK: Data

    private func refresh() async {
        guard let feed = try? await app.home() else { return }
        let pool = feed.sections.flatMap(\.posts)
        if app.ratings.isEmpty {
            // Nothing to go on yet: offer the best-regarded titles to kick things off.
            starters = Array(pool.filter { !$0.comingSoon && $0.imdbScore != nil }
                .sorted { ($0.imdbScore ?? 0) > ($1.imdbScore ?? 0) }
                .prefix(12))
        } else {
            picks = app.ratings.recommend(from: pool, limit: 14)
        }
    }

    /// The lists the user keeps on 30nama itself. A guest has none.
    private func loadLists() async {
        async let watch = app.myList("watchlist")
        async let liked = app.myList("favorite")
        async let sizes = app.myListSizes()
        (watchlist, favorites, listSizes) = await (watch, liked, sizes)
    }
}

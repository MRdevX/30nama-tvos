import SwiftUI

/// The user's own page: who they are, what they have rated, and what that suggests they watch next.
struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.loc) private var loc

    @State private var picks: [Post] = []
    @State private var starters: [Post] = []

    private let columns = Array(repeating: GridItem(.fixed(Theme.posterWidth), spacing: 32), count: 7)

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 44) {
                header
                if app.ratings.isEmpty {
                    emptyState
                } else {
                    if !picks.isEmpty { shelf(loc(.forYou), posts: picks) }
                    ratedGrid
                }
            }
            .padding(.horizontal, Theme.edge + 4)
            .padding(.top, 20)
            .padding(.bottom, 80)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .background(AmbientBackground())
        .overlay(alignment: .top) { TopShade() }
        .task(id: app.ratings) { await refresh() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 28) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Theme.accent, Color(hex: 0xD92B58)], startPoint: .topLeading, endPoint: .bottomTrailing))
                if let initials {
                    Text(initials)
                        .font(.app(56, .heavy))
                        .foregroundStyle(.white)
                        .environment(\.layoutDirection, .leftToRight)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 150, height: 150)
            .shadow(color: Theme.accent.opacity(0.5), radius: 24, y: 8)

            VStack(alignment: .leading, spacing: 10) {
                Text(app.user?.name ?? loc(.guestAccount))
                    .font(.app(56, .bold))
                    .foregroundStyle(Theme.text1)
                if !app.ratings.isEmpty {
                    HStack(spacing: 14) {
                        Stat(value: loc.num(app.ratings.count), label: loc(.ratedCount))
                        if let average = app.ratings.average {
                            Stat(value: "★ " + loc.num(Fmt.score(average)), label: loc(.averageRating))
                        }
                    }
                }
            }
            Spacer()
        }
    }

    private struct Stat: View {
        let value: String
        let label: String
        var body: some View {
            HStack(spacing: 8) {
                Text(value).font(.app(28, .bold)).foregroundStyle(Theme.text1)
                Text(label).font(.app(24)).foregroundStyle(Theme.text3)
            }
            .padding(.horizontal, 20)
            .frame(height: 52)
            .glass(Capsule(style: .continuous))
        }
    }

    /// Initials of the signed-in name, or nil for a guest (who gets a person glyph instead).
    private var initials: String? {
        guard let name = app.user?.name else { return nil }
        let words = name.split(separator: " ")
        let letters = [words.first?.first, words.count > 1 ? words.last?.first : nil].compactMap { $0 }
        return letters.isEmpty ? nil : String(letters).uppercased()
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
        .padding(.top, 20)
    }

    // MARK: Shelves

    private func shelf(_ title: String, posts: [Post]) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title).font(.app(32, .bold)).foregroundStyle(Theme.text1)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 24) {
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
            LazyVGrid(columns: columns, alignment: .leading, spacing: 44) {
                ForEach(app.ratings.newestFirst) { rating in
                    if let post = rating.post {
                        VStack(alignment: .leading, spacing: 10) {
                            PosterLink(post: post)
                            Label(loc.num(Fmt.score(rating.stars)), systemImage: "star.fill")
                                .font(.app(21, .semibold))
                                .foregroundStyle(Color(hex: 0xF5C518))
                                .frame(width: Theme.posterWidth, alignment: .leading)
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
}

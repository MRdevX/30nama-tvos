import SwiftUI

@main
struct NamaApp: App {
    @State private var app = AppModel()

    init() {
        AppFont.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
        }
    }
}

/// Where a card or button leads.
enum Route: Hashable {
    case details(PostRef)
    case catalog(slug: String, title: String)
}

/// A title to open. Carries the list entry so the page has something to show while it loads.
struct PostRef: Hashable {
    let id: Int
    var preview: Post?
    /// Start playback as soon as the stream is known (the hero "Play" button).
    var autoplay = false

    init(_ post: Post, autoplay: Bool = false) {
        id = post.id
        preview = post
        self.autoplay = autoplay
    }
}

extension View {
    func withRoutes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .details(let ref): DetailsView(ref: ref)
            case .catalog(let slug, let title): CatalogView(slug: slug, title: title)
            }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    /// The opening title has run its course.
    @State private var introPlayed = false
    /// The opening title has finished leaving and is out of the hierarchy.
    @State private var splashGone = false

    /// The title leaves once it has played and there is something to show behind it.
    private var splashLeaving: Bool { introPlayed && app.phase != .booting }

    var body: some View {
        @Bindable var app = app
        ZStack {
            Theme.bg0.ignoresSafeArea()
            switch app.phase {
            case .booting:
                // Only seen when retrying after a failed start; the first start is covered by the opening title.
                ProgressView()
            case .failed:
                ErrorState(message: "\(app.loc(.noConnection)). \(app.loc(.tryAgain))") {
                    Task { await app.boot() }
                }
            case .login:
                LoginView()
            case .main:
                MainView()
            }
            if !splashGone {
                SplashView(leaving: splashLeaving)
                    .zIndex(10)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = app.toast {
                Toast(text: toast)
                    .padding(.bottom, 70)
                    .transition(.opacity.combined(with: .offset(y: 16)))
            }
        }
        .animation(.easeOut(duration: 0.4), value: app.phase)
        .onChange(of: splashLeaving) { _, leaving in
            guard leaving else { return }
            Task {
                try? await Task.sleep(for: .seconds(SplashView.exitDuration))
                splashGone = true
            }
        }
        .animation(.easeOut(duration: 0.24), value: app.toast)
        .environment(\.layoutDirection, app.settings.lang.isRTL ? .rightToLeft : .leftToRight)
        .environment(\.loc, app.loc)
        .environment(\.calm, app.settings.reduceMotion)
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $app.playback, onDismiss: { app.playerDidClose() }) { request in
            PlayerScreen(request: request)
                .ignoresSafeArea()
                .environment(app)
        }
        .task { await app.boot() }
        .onChange(of: scenePhase) { _, phase in
            // Coming back to the app: pick up what was rated on another Apple TV meanwhile.
            if phase == .active, app.phase == .main { app.syncRatings(unlessFresherThan: 60) }
        }
        .task {
            // The opening title runs its course once; after that it only waits on the network.
            try? await Task.sleep(for: .seconds(2.3))
            introPlayed = true
        }
    }
}

/// Opening title: light gathers behind the 30nama logo, the cube and then the name resolve out of
/// a blur and a glint runs across them. To leave, the red line under the logo runs out to both
/// edges of the screen and the card parts along it like a curtain, uncovering the app.
struct SplashView: View {
    /// Start the exit.
    var leaving = false

    /// How long the exit takes, from `leaving` turning true to nothing being left on screen.
    static let exitDuration = 1.15

    @State private var lit = false
    @State private var glint = false

    /// Where the cube ends and the name begins, as a fraction of the logo's width.
    private let logoSplit = 0.29
    private let logoHeight: CGFloat = 190

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            // The seam sits where the line is: just under the logo.
            let seam = size.height / 2 + 84
            let parting = Animation.timingCurve(0.7, 0, 0.2, 1, duration: 0.75).delay(0.38)
            ZStack(alignment: .top) {
                card(size)
                    .mask(alignment: .top) { Rectangle().frame(height: seam) }
                    .offset(y: leaving ? -seam : 0)
                    .animation(parting, value: leaving)
                card(size)
                    .mask(alignment: .bottom) { Rectangle().frame(height: size.height - seam) }
                    .offset(y: leaving ? size.height - seam : 0)
                    .animation(parting, value: leaving)
                Capsule()
                    .fill(LinearGradient(colors: [.clear, Theme.accent, Color(hex: 0xFF8A70), Theme.accent, .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(width: lit ? (leaving ? size.width * 1.1 : 320) : 0, height: 3)
                    .shadow(color: Theme.accent, radius: leaving ? 22 : 12)
                    .opacity(leaving ? 0 : 1)
                    .frame(width: size.width)
                    .offset(y: seam - 1.5)
                    .animation(.spring(response: 0.9, dampingFraction: 0.8).delay(leaving ? 0 : 0.75), value: lit)
                    .animation(.easeInOut(duration: 0.42), value: leaving)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            lit = true
            withAnimation(.easeInOut(duration: 0.9).delay(1.15)) { glint = true }
        }
    }

    /// Background, lights and wordmark. Drawn twice, once for each half of the curtain.
    private func card(_ size: CGSize) -> some View {
        ZStack {
            Theme.bg0
            // Two soft lights drifting apart: the projector's red and a cool counter-light.
            Circle().fill(Theme.accent)
                .frame(width: 760, height: 760)
                .blur(radius: 190)
                .opacity(lit ? 0.5 : 0)
                .offset(x: lit ? -210 : 0, y: lit ? 40 : 0)
            Circle().fill(Color(hex: 0x5B4BFF))
                .frame(width: 640, height: 640)
                .blur(radius: 190)
                .opacity(lit ? 0.4 : 0)
                .offset(x: lit ? 260 : 0, y: lit ? -70 : 0)
            wordmark
                .overlay {
                    // The glint: a white silhouette of the logo seen through a moving slit.
                    logo.renderingMode(.template).resizable().scaledToFit().frame(height: logoHeight).foregroundStyle(.white).mask {
                        LinearGradient(colors: [.clear, .white, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 150)
                            .rotationEffect(.degrees(18))
                            .offset(x: glint ? 460 : -460)
                    }
                }
                .offset(y: -22)
        }
        .frame(width: size.width, height: size.height)
        .animation(.easeOut(duration: 1.6), value: lit)
    }

    private var logo: Image { Image("Logo") }

    /// The logo in its two parts, so the cube can arrive a beat before the name.
    private var wordmark: some View {
        ZStack {
            logoPart(from: 0, to: logoSplit, delay: 0.2)
            logoPart(from: logoSplit, to: 1, delay: 0.42)
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private func logoPart(from start: Double, to end: Double, delay: Double) -> some View {
        logo.resizable().scaledToFit().frame(height: logoHeight)
            .mask {
                GeometryReader { geo in
                    Rectangle().frame(width: geo.size.width * (end - start)).offset(x: geo.size.width * start)
                }
            }
            .blur(radius: lit ? 0 : 18)
            .opacity(lit ? 1 : 0)
            .offset(y: lit ? 0 : 44)
            .scaleEffect(lit ? 1 : 1.3)
            .animation(.spring(response: 0.62, dampingFraction: 0.68).delay(delay), value: lit)
    }
}

struct MainView: View {
    enum Tab: Hashable { case profile, home, movies, series, anime, browse, search, settings }

    @Environment(AppModel.self) private var app
    @Environment(\.loc) private var loc
    @State private var tab = Tab.home

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { ProfileView().withRoutes() }
                .tabItem { iconTab(loc(.profile), "person.crop.circle") }
                .tag(Tab.profile)
            NavigationStack { HomeView().withRoutes() }
                .tabItem { Text(loc(.home)) }
                .tag(Tab.home)
            NavigationStack { CatalogView(slug: "movies", title: loc(.movies)).withRoutes() }
                .tabItem { Text(loc(.movies)) }
                .tag(Tab.movies)
            NavigationStack { CatalogView(slug: "series", title: loc(.series)).withRoutes() }
                .tabItem { Text(loc(.series)) }
                .tag(Tab.series)
            NavigationStack { CatalogView(slug: "anime", title: loc(.anime)).withRoutes() }
                .tabItem { Text(loc(.anime)) }
                .tag(Tab.anime)
            NavigationStack { BrowseView().withRoutes() }
                .tabItem { Text(loc(.browse)) }
                .tag(Tab.browse)
            NavigationStack { SearchView().withRoutes() }
                .tabItem { iconTab(loc(.search), "magnifyingglass", titled: roomy) }
                .tag(Tab.search)
            NavigationStack { SettingsView() }
                .tabItem { iconTab(loc(.settings), "gearshape", titled: roomy) }
                .tag(Tab.settings)
        }
        // A new language or account means a different catalogue: rebuild every tab.
        .id(app.contentVersion)
    }

    /// Persian titles are short enough for all eight tabs to fit the bar. English and Arabic ones
    /// are not, so there search and settings go by their icons alone, as is usual on tvOS.
    private var roomy: Bool { loc.lang == .fa }

    /// A tab with an icon. The tab bar always puts the icon to the left of the title, whatever the
    /// reading direction, so in a right-to-left language the two are drawn as one image with the
    /// icon leading.
    @ViewBuilder
    private func iconTab(_ title: String, _ symbol: String, titled: Bool = true) -> some View {
        if !titled {
            Image(systemName: symbol).accessibilityLabel(title)
        } else if loc.lang.isRTL, let image = MainView.tabImage(title, symbol) {
            Image(uiImage: image)
        } else {
            Label(title, systemImage: symbol)
        }
    }

    /// Title and icon as the tab bar itself would draw them, in right-to-left order.
    private static func tabImage(_ title: String, _ symbol: String) -> UIImage? {
        let font = UIFont.systemFont(ofSize: 25, weight: .bold)
        guard let icon = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(font: font, scale: .large)) else { return nil }
        let text = NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: UIColor.white])
        let textSize = text.size()
        let size = CGSize(width: ceil(textSize.width) + 8 + icon.size.width, height: max(ceil(textSize.height), icon.size.height))
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            text.draw(at: CGPoint(x: 0, y: (size.height - textSize.height) / 2))
            icon.withTintColor(.white).draw(at: CGPoint(x: size.width - icon.size.width, y: (size.height - icon.size.height) / 2))
        }.withRenderingMode(.alwaysTemplate)
        image.accessibilityLabel = title
        return image
    }
}

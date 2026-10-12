import Foundation

/// Interface strings. The language is an in-app setting (the catalogue itself is served in the
/// chosen language), so these live in code rather than in a `.strings` bundle that follows the
/// system locale.
enum S: String, CaseIterable {
    case home, search, browse, settings, movies, series, anime, movie
    case signIn, scanTitle, step1, step2, step3, orEnterCode, waiting, expired, codeFailed, guest, newCode, welcome
    case loading, error, tryAgain, retry, noConnection
    case continueWatching, newReleases, suggested, top10, featured
    case trendingWeek, newSeries, popularMovies, tmdb, tmdbOn, tmdbOff, tmdbCredit
    case cloudRatings, cloudSynced, cloudSyncing, cloudSignedOut, cloudFailed
    case play, resume, details, episodes, season, seasonsCount, episode, nowPlaying, cast
    case persianSub, minLeft, min, free, soon
    case loginToStream, loginToWatch, noStream, comingSoonNote
    case popularNow, topResults, nothingFor, searchPrompt
    case categories, genres, newest, popular, updated, results
    case account, language, signOut, signInQR, guestAccount, expires, accountType
    case playback, display, about, defaultSubs, subSize, autoplay, quality, qualityBest, qualityAuto, reduceMotion
    case on, off, small, medium, large, sample
    case profile, yourRating, forYou, ratedCount, averageRating, noRatingsYet, rateHint, startWithThese
    case subColor, subBackground, white, yellow, cyan, green, bgNone, bgHalf, bgSolid, bgBlurHalf, bgBlur
    case version, unofficial, apiHost
    case skipIntro, skipRecap, nextEpisode, subtitles, english, persian
    case subFailed, playError
    case signOutTitle, signOutBody, cancel
    case director, writer, creator, network, country, originalLanguage, status, storyline, information
}

struct Loc: Equatable {
    let lang: Lang

    func callAsFunction(_ key: S) -> String {
        (lang == .fa ? Loc.fa[key] : Loc.en[key]) ?? Loc.en[key] ?? key.rawValue
    }

    /// Digits in the interface language.
    func num(_ s: String) -> String { lang == .fa ? Fmt.persianDigits(s) : s }
    func num(_ n: Int) -> String { num(String(n)) }

    func title(forSection key: String) -> String {
        switch key {
        case "continue": return self(.continueWatching)
        case "for_you": return self(.forYou)
        case "tm_trend": return self(.trendingWeek)
        case "tm_fresh": return self(.newSeries)
        case "tm_pop": return self(.popularMovies)
        case "new_releases": return self(.newReleases)
        case "suggested": return self(.suggested)
        case "top_10": return self(.top10)
        case "movies": return self(.movies)
        case "series": return self(.series)
        case "anime": return self(.anime)
        default: return key
        }
    }

    func kind(_ kind: Post.Kind) -> String {
        switch kind {
        case .movie: return self(.movie)
        case .series: return self(.series)
        case .anime: return self(.anime)
        }
    }

    /// "Series · 4 seasons"
    func kindLine(_ post: Post) -> String {
        var s = kind(post.kind)
        if post.isSeries, let n = post.seasons, n > 0 {
            s += " · " + (lang == .fa ? "\(num(n)) \(self(.seasonsCount))" : "\(n) \(n == 1 ? "season" : self(.seasonsCount))")
        }
        return s
    }

    /// "S2 · E5" / "فصل ۲ · قسمت ۵"
    func episodeTag(season: Int, episode: String) -> String {
        lang == .fa ? "فصل \(num(season)) · قسمت \(num(episode))" : "S\(season) · E\(episode)"
    }

    static let en: [S: String] = [
        .home: "Home", .search: "Search", .browse: "Browse", .settings: "Settings",
        .movies: "Movies", .series: "Series", .anime: "Anime", .movie: "Movie",
        .signIn: "Sign in", .scanTitle: "Scan with your phone", .step1: "Open the camera on your phone",
        .step2: "Scan the code", .step3: "Confirm on 30nama.com", .orEnterCode: "Or go to 30nama.com/auth and enter",
        .waiting: "Waiting for scan…", .expired: "Code expired", .codeFailed: "Could not get a code",
        .guest: "Continue as guest", .newCode: "New code", .welcome: "Welcome",
        .loading: "Loading…", .error: "Something went wrong", .tryAgain: "Please try again in a moment.",
        .retry: "Retry", .noConnection: "Could not reach 30nama",
        .continueWatching: "Continue watching", .newReleases: "New releases", .suggested: "Suggested",
        .top10: "Top 10", .featured: "Featured",
        .trendingWeek: "Trending this week", .newSeries: "New & returning series",
        .popularMovies: "Popular movies now", .tmdb: "TMDB trending rows", .tmdbOn: "On", .tmdbOff: "Not set up",
        .tmdbCredit: "Trending lists come from TMDB. This app is not endorsed or certified by TMDB.",
        .cloudRatings: "Ratings in iCloud", .cloudSynced: "Up to date", .cloudSyncing: "Syncing…",
        .cloudSignedOut: "Not signed in to iCloud", .cloudFailed: "Could not sync",
        .play: "Play", .resume: "Resume", .details: "Details", .episodes: "Episodes", .season: "Season",
        .seasonsCount: "seasons", .episode: "Episode", .nowPlaying: "Now playing", .cast: "Cast",
        .persianSub: "Persian subtitles", .minLeft: "min left", .min: "min", .free: "FREE", .soon: "SOON",
        .loginToStream: "Sign in to stream and keep your place", .loginToWatch: "Sign in to watch",
        .noStream: "No stream available for this title", .comingSoonNote: "Coming soon",
        .popularNow: "Popular now", .topResults: "Results", .nothingFor: "Nothing found for",
        .searchPrompt: "Movies, series, anime",
        .categories: "Categories", .genres: "Genres", .newest: "Newest", .popular: "Popular",
        .updated: "Updated", .results: "titles",
        .account: "Account", .language: "Language", .signOut: "Sign out", .signInQR: "Sign in with QR code",
        .guestAccount: "Guest", .expires: "Subscription ends", .accountType: "Account type",
        .playback: "Playback", .display: "Display", .about: "About", .defaultSubs: "Default subtitles",
        .subSize: "Subtitle size", .autoplay: "Play next episode automatically", .quality: "Video quality",
        .qualityBest: "Highest", .qualityAuto: "Automatic", .reduceMotion: "Reduce motion",
        .on: "On", .off: "Off", .small: "Small", .medium: "Medium", .large: "Large",
        .sample: "This is how subtitles will look.",
        .profile: "Profile", .yourRating: "Your rating", .forYou: "Picked for you",
        .ratedCount: "rated", .averageRating: "average",
        .noRatingsYet: "You have not rated anything yet",
        .rateHint: "Open a title and give it stars. Your ratings shape what is picked for you.",
        .startWithThese: "Start with these",
        .subColor: "Subtitle colour", .subBackground: "Subtitle background",
        .white: "White", .yellow: "Yellow", .cyan: "Cyan", .green: "Green",
        .bgNone: "None", .bgHalf: "Black 50%", .bgSolid: "Black", .bgBlurHalf: "Blur 50%", .bgBlur: "Blur",
        .version: "Version", .unofficial: "Unofficial client for 30nama.com. Not affiliated with 30nama.",
        .apiHost: "Server",
        .skipIntro: "Skip Intro", .skipRecap: "Skip Recap", .nextEpisode: "Next Episode",
        .subtitles: "Subtitles", .english: "English", .persian: "Persian",
        .subFailed: "Could not load subtitles", .playError: "Playback failed",
        .signOutTitle: "Sign out?", .signOutBody: "You will need to scan a new code to sign in again.",
        .cancel: "Cancel",
        .director: "Director", .writer: "Writer", .creator: "Creator", .network: "Network",
        .country: "Country", .originalLanguage: "Language", .status: "Status", .storyline: "Storyline",
        .information: "Information",
    ]

    static let fa: [S: String] = [
        .home: "خانه", .search: "جستجو", .browse: "مرور", .settings: "تنظیمات",
        .movies: "فیلم", .series: "سریال", .anime: "انیمه", .movie: "فیلم",
        .signIn: "ورود", .scanTitle: "با گوشی اسکن کنید", .step1: "دوربین گوشی را باز کنید",
        .step2: "کد را اسکن کنید", .step3: "در ۳۰نما تأیید کنید", .orEnterCode: "یا در 30nama.com/auth این کد را وارد کنید",
        .waiting: "در انتظار اسکن…", .expired: "کد منقضی شد", .codeFailed: "دریافت کد ممکن نشد",
        .guest: "ادامه به‌عنوان مهمان", .newCode: "کد جدید", .welcome: "خوش آمدید",
        .loading: "در حال بارگذاری…", .error: "مشکلی پیش آمد", .tryAgain: "لطفاً کمی بعد دوباره تلاش کنید.",
        .retry: "تلاش دوباره", .noConnection: "اتصال به ۳۰نما برقرار نشد",
        .continueWatching: "ادامه تماشا", .newReleases: "تازه‌ها", .suggested: "پیشنهادی",
        .top10: "۱۰ برتر", .featured: "ویژه",
        .trendingWeek: "پرطرفدار این هفته", .newSeries: "سریال‌های جدید و ادامه‌دار",
        .popularMovies: "فیلم‌های محبوب امروز", .tmdb: "ردیف‌های ترند TMDB", .tmdbOn: "فعال", .tmdbOff: "تنظیم نشده",
        .tmdbCredit: "فهرست‌های ترند از TMDB می‌آید. این برنامه مورد تأیید TMDB نیست.",
        .cloudRatings: "ریت‌ها در iCloud", .cloudSynced: "همگام", .cloudSyncing: "در حال همگام‌سازی…",
        .cloudSignedOut: "وارد iCloud نشده‌اید", .cloudFailed: "همگام نشد",
        .play: "پخش", .resume: "ادامه", .details: "جزئیات", .episodes: "قسمت‌ها", .season: "فصل",
        .seasonsCount: "فصل", .episode: "قسمت", .nowPlaying: "در حال پخش", .cast: "بازیگران",
        .persianSub: "زیرنویس فارسی", .minLeft: "دقیقه مانده", .min: "دقیقه", .free: "رایگان", .soon: "به‌زودی",
        .loginToStream: "برای پخش و ادامهٔ تماشا وارد شوید", .loginToWatch: "برای تماشا وارد شوید",
        .noStream: "پخش این عنوان در دسترس نیست", .comingSoonNote: "به‌زودی",
        .popularNow: "محبوب این روزها", .topResults: "نتیجه‌ها", .nothingFor: "چیزی پیدا نشد برای",
        .searchPrompt: "فیلم، سریال، انیمه",
        .categories: "دسته‌ها", .genres: "ژانرها", .newest: "جدیدترین", .popular: "محبوب‌ترین",
        .updated: "به‌روزشده", .results: "عنوان",
        .account: "حساب کاربری", .language: "زبان", .signOut: "خروج از حساب", .signInQR: "ورود با کد QR",
        .guestAccount: "مهمان", .expires: "پایان اشتراک", .accountType: "نوع حساب",
        .playback: "پخش", .display: "نمایش", .about: "درباره", .defaultSubs: "زیرنویس پیش‌فرض",
        .subSize: "اندازهٔ زیرنویس", .autoplay: "پخش خودکار قسمت بعد", .quality: "کیفیت پخش",
        .qualityBest: "بالاترین", .qualityAuto: "خودکار", .reduceMotion: "کاهش حرکت",
        .on: "روشن", .off: "خاموش", .small: "کوچک", .medium: "متوسط", .large: "بزرگ",
        .sample: "زیرنویس به این شکل نمایش داده می‌شود.",
        .profile: "پروفایل", .yourRating: "ریت تو", .forYou: "پیشنهاد برای تو",
        .ratedCount: "ریت‌شده", .averageRating: "میانگین",
        .noRatingsYet: "هنوز به چیزی ریت نداده‌ای",
        .rateHint: "صفحهٔ هر فیلم را باز کن و ستاره بده. پیشنهادها از روی همین ریت‌ها ساخته می‌شوند.",
        .startWithThese: "از این‌ها شروع کن",
        .subColor: "رنگ زیرنویس", .subBackground: "پس‌زمینهٔ زیرنویس",
        .white: "سفید", .yellow: "زرد", .cyan: "فیروزه‌ای", .green: "سبز",
        .bgNone: "بدون پس‌زمینه", .bgHalf: "مشکی ۵۰٪", .bgSolid: "مشکی ۱۰۰٪", .bgBlurHalf: "بلور ۵۰٪", .bgBlur: "بلور ۱۰۰٪",
        .version: "نسخه", .unofficial: "برنامهٔ غیررسمی برای 30nama.com؛ وابسته به ۳۰نما نیست.",
        .apiHost: "سرور",
        .skipIntro: "رد کردن تیتراژ", .skipRecap: "رد کردن خلاصه", .nextEpisode: "قسمت بعد",
        .subtitles: "زیرنویس", .english: "انگلیسی", .persian: "فارسی",
        .subFailed: "بارگذاری زیرنویس ممکن نشد", .playError: "پخش با خطا روبه‌رو شد",
        .signOutTitle: "از حساب خارج می‌شوید؟", .signOutBody: "برای ورود دوباره باید کد جدیدی اسکن کنید.",
        .cancel: "انصراف",
        .director: "کارگردان", .writer: "نویسنده", .creator: "سازنده", .network: "شبکه",
        .country: "کشور", .originalLanguage: "زبان", .status: "وضعیت", .storyline: "داستان",
        .information: "اطلاعات",
    ]
}

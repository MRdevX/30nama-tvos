import SwiftUI
import AVKit

/// Full-screen playback in the system player.
///
/// `AVPlayerViewController` brings the transport bar, Siri Remote scrubbing, audio-track selection
/// and the info panel. On top of that this adds what 30nama's streams need: side-loaded WebVTT
/// subtitles, skip-intro and next-episode buttons, a quality menu and progress reporting.
struct PlayerScreen: UIViewControllerRepresentable {
    let request: PlaybackRequest

    @Environment(AppModel.self) private var app

    func makeCoordinator() -> PlayerEngine {
        PlayerEngine(request: request, app: app)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        context.coordinator.makeController()
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: PlayerEngine) {
        coordinator.shutdown()
    }
}

@MainActor
final class PlayerEngine: NSObject, AVPlayerViewControllerDelegate {
    private let post: Post
    private let items: [StreamItem]
    private let app: AppModel
    private let player = AVPlayer()

    private var index: Int
    private var resume: ContinueWatching?
    private var quality: Quality?
    private weak var controller: AVPlayerViewController?

    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var heartbeat: Timer?
    private var closed = false

    private var subtitleLanguage: String
    private var track = SubtitleTrack()
    private var subtitleCache: [URL: SubtitleTrack] = [:]
    private var subtitleTask: Task<Void, Never>?
    private let subtitleLabel = UILabel()
    /// Plate behind the subtitle text; clear, black or blurred depending on the setting.
    private let subtitlePlate = UIView()
    private let subtitleBlur = UIVisualEffectView(effect: nil)
    /// Holds the blur part-way in; see `applySubtitleBlur`.
    private var blurAnimator: UIViewPropertyAnimator?
    private var activeObserver: NSObjectProtocol?
    private var subtitleBottom: NSLayoutConstraint?
    /// What is covering the bottom of the picture at the moment.
    private var barShowing = false
    private var episodesShowing = false
    private var shownCue = ""
    /// Which contextual button is up ("intro", "recap", "next" or none), to avoid resetting it every tick.
    private var actionKey = ""

    private var loc: Loc { app.loc }
    private var current: StreamItem { items[index] }

    init(request: PlaybackRequest, app: AppModel) {
        post = request.post
        items = request.items
        index = min(max(0, request.index), max(0, request.items.count - 1))
        resume = request.resume
        self.app = app
        subtitleLanguage = app.settings.defaultSubtitle
    }

    // MARK: Lifecycle

    func makeController() -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.delegate = self
        self.controller = controller
        installSubtitleLabel(in: controller)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
        heartbeat = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.report() }
        }
        if items.isEmpty { close() } else { start(index) }
        return controller
    }

    func shutdown() {
        guard !closed else { return }
        closed = true
        report()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
        blurAnimator?.stopAnimation(true)
        statusObservation = nil
        heartbeat?.invalidate()
        subtitleTask?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func close() {
        app.closePlayer()
    }

    // MARK: Items

    /// Starts item `i`, from `position` if given, else from where the user left off.
    private func start(_ i: Int, at position: Double? = nil) {
        guard items.indices.contains(i) else { return close() }
        report()
        index = i
        guard let quality = current.quality(preferAdaptive: app.settings.preferAdaptive) else {
            app.showToast(loc(.noStream))
            return close()
        }
        load(quality, at: position ?? resumePosition())
        resume = nil
        selectSubtitle(subtitleLanguage, remember: false)
    }

    private func resumePosition() -> Double? {
        guard let resume, resume.fileID == current.fileID, resume.time > 5 else { return nil }
        // Left in the closing credits: start over rather than resume into the end.
        if resume.duration > 0, resume.time > resume.duration * 0.97 { return nil }
        return resume.time
    }

    private func load(_ quality: Quality, at position: Double?) {
        self.quality = quality
        let item = AVPlayerItem(url: quality.url)
        item.externalMetadata = metadata()

        statusObservation = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in self?.failed() }
        }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finished() }
        }

        player.replaceCurrentItem(with: item)
        if let position, position > 0 {
            player.seek(to: CMTime(seconds: position, preferredTimescale: 600))
        }
        player.play()

        actionKey = ""
        controller?.contextualActions = []
        refreshMenus()
        attachArtwork(to: item)
    }

    private func finished() {
        if index + 1 < items.count, app.settings.autoplayNext {
            start(index + 1)
        } else {
            close()
        }
    }

    private func failed() {
        guard !closed else { return }
        app.showToast(loc(.playError))
        close()
    }

    // MARK: Progress

    /// Tells the server where playback is, which drives "continue watching" on every device.
    private func report() {
        guard app.isLoggedIn, items.indices.contains(index), player.currentItem != nil else { return }
        let time = player.currentTime().seconds
        guard time.isFinite, time > 1 else { return }
        let duration = player.currentItem?.duration.seconds ?? 0
        let item = current
        let params = [
            "post_id": item.postID ?? String(post.id),
            "file_id": item.fileID,
            "user_id": app.user?.id ?? "",
            "time": String(Int(time)),
            "duration": String(duration.isFinite ? Int(duration) : 0),
            "token": item.token,
        ]
        let api = app.api
        Task { _ = try? await api.call("observer", params) }
    }

    private func tick(_ time: Double) {
        guard !closed, time.isFinite else { return }
        let cue = track.text(at: time)
        if cue != shownCue { showCue(cue) }

        var key = ""
        var actions: [UIAction] = []
        if let skip = current.skipTarget(at: time) {
            key = skip.isIntro ? "intro" : "recap"
            actions = [UIAction(title: loc(skip.isIntro ? .skipIntro : .skipRecap), image: UIImage(systemName: "forward.fill")) { [weak self] _ in
                self?.player.seek(to: CMTime(seconds: skip.to, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            }]
        } else if let credits = current.creditsStart, credits > 0, time >= credits, index + 1 < items.count {
            key = "next"
            actions = [UIAction(title: loc(.nextEpisode), image: UIImage(systemName: "forward.end.fill")) { [weak self] _ in
                guard let self else { return }
                self.start(self.index + 1)
            }]
        }
        if key != actionKey {
            actionKey = key
            controller?.contextualActions = actions
        }
    }

    // MARK: Menus and info panel

    private func refreshMenus() {
        guard let controller else { return }
        var menus: [UIMenuElement] = []

        let languages = ["fa", "en"].filter { current.subtitles[$0] != nil }
        if !languages.isEmpty {
            let options = [("off", loc(.off))] + languages.map { ($0, loc($0 == "fa" ? .persian : .english)) }
            let active = languages.contains(subtitleLanguage) ? subtitleLanguage : "off"
            menus.append(UIMenu(title: loc(.subtitles), image: UIImage(systemName: "text.bubble"), children: options.map { code, name in
                UIAction(title: name, state: code == active ? .on : .off) { [weak self] _ in
                    self?.selectSubtitle(code, remember: true)
                    self?.refreshMenus()
                }
            }))
        }

        if current.qualities.count > 1 {
            menus.append(UIMenu(title: loc(.quality), image: UIImage(systemName: "sparkles.tv"), children: current.qualities.map { option in
                UIAction(title: option.isAuto ? loc(.qualityAuto) : option.label, state: option == quality ? .on : .off) { [weak self] _ in
                    guard let self, option != self.quality else { return }
                    let position = self.player.currentTime().seconds
                    self.load(option, at: position.isFinite ? position : nil)
                }
            }))
        }
        controller.transportBarCustomMenuItems = menus

        if items.count > 1 {
            let season = current.season
            let strip = EpisodeStrip(
                entries: Array(items.enumerated()).filter { $0.element.season == season }.map { .init(index: $0.offset, item: $0.element) },
                playing: index
            ) { [weak self] chosen in
                self?.start(chosen)
            } shown: { [weak self] showing in
                guard let self, episodesShowing != showing else { return }
                episodesShowing = showing
                subtitleBottom?.constant = subtitleLift
                UIView.animate(withDuration: 0.3) { self.subtitlePlate.superview?.layoutIfNeeded() }
            }
            let host = UIHostingController(rootView: strip
                .environment(\.loc, loc)
                .environment(\.layoutDirection, loc.lang.isRTL ? .rightToLeft : .leftToRight))
            host.title = "\(loc(.season)) \(loc.num(season))"
            host.view.backgroundColor = .clear
            host.preferredContentSize = CGSize(width: 0, height: 290)
            controller.customInfoViewControllers = [host]
        } else {
            controller.customInfoViewControllers = []
        }
    }

    private func metadata() -> [AVMetadataItem] {
        func make(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
            let m = AVMutableMetadataItem()
            m.identifier = identifier
            m.value = value as NSString
            m.extendedLanguageTag = "und"
            return m
        }
        var out = [make(.commonIdentifierTitle, post.title(loc.lang))]
        if post.isSeries || items.count > 1 {
            var line = loc.episodeTag(season: current.season, episode: Episode.label(current.episodeRaw, fallback: index + 1))
            if let name = current.title(loc.lang) { line += " — " + name }
            out.append(make(.iTunesMetadataTrackSubTitle, line))
        }
        let plot = post.plot(loc.lang)
        if !plot.isEmpty { out.append(make(.commonIdentifierDescription, plot)) }
        if let genre = post.genres.first?.name { out.append(make(.quickTimeMetadataGenre, genre)) }
        return out
    }

    /// Poster for the info panel and Now Playing. Fetched separately so it never delays playback.
    private func attachArtwork(to item: AVPlayerItem) {
        guard let url = post.poster.jpeg else { return }
        Task { [weak self, weak item] in
            guard let (data, _) = try? await URLSession.shared.data(from: url), let item,
                  self?.player.currentItem === item else { return }
            let artwork = AVMutableMetadataItem()
            artwork.identifier = .commonIdentifierArtwork
            artwork.value = data as NSData
            artwork.dataType = kCMMetadataBaseDataType_JPEG as String
            artwork.extendedLanguageTag = "und"
            item.externalMetadata.append(artwork)
        }
    }

    // MARK: Subtitles

    /// Subtitles are separate WebVTT files, not tracks of the stream, so they are fetched here and
    /// drawn over the video.
    private func selectSubtitle(_ language: String, remember: Bool) {
        subtitleLanguage = language
        if remember { app.update { $0.defaultSubtitle = language } }
        subtitleTask?.cancel()
        track = SubtitleTrack()
        showCue("")
        guard language != "off", let url = current.subtitles[language] else { return }
        if let cached = subtitleCache[url] {
            track = cached
            return
        }
        subtitleTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url) else {
                if !Task.isCancelled, let self { self.app.showToast(self.loc(.subFailed)) }
                return
            }
            let parsed = await Task.detached { SubtitleTrack(vtt: String(decoding: data, as: UTF8.self)) }.value
            guard !Task.isCancelled, let self else { return }
            self.subtitleCache[url] = parsed
            if self.subtitleLanguage == language, self.current.subtitles[language] == url { self.track = parsed }
        }
    }

    private func installSubtitleLabel(in controller: AVPlayerViewController) {
        guard let overlay = controller.contentOverlayView else { return }
        subtitleLabel.numberOfLines = 0
        subtitleLabel.textAlignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitlePlate.translatesAutoresizingMaskIntoConstraints = false
        subtitlePlate.layer.cornerRadius = 14
        subtitlePlate.layer.cornerCurve = .continuous
        subtitlePlate.clipsToBounds = true
        subtitlePlate.isHidden = true
        subtitleBlur.frame = subtitlePlate.bounds
        subtitleBlur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        subtitlePlate.addSubview(subtitleBlur)
        subtitlePlate.addSubview(subtitleLabel)
        overlay.addSubview(subtitlePlate)

        subtitlePlate.backgroundColor = UIColor.black.withAlphaComponent(app.settings.subtitleBackground.plateOpacity)
        applySubtitleBlur()
        // A paused animator is finished off by the system when the app leaves the foreground,
        // which would snap a half blur to a full one; set it up again on return.
        activeObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySubtitleBlur() }
        }

        let bottom = subtitlePlate.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -70)
        subtitleBottom = bottom
        NSLayoutConstraint.activate([
            subtitlePlate.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            subtitlePlate.widthAnchor.constraint(lessThanOrEqualTo: overlay.widthAnchor, multiplier: 0.82),
            bottom,
            subtitleLabel.leadingAnchor.constraint(equalTo: subtitlePlate.leadingAnchor, constant: 26),
            subtitleLabel.trailingAnchor.constraint(equalTo: subtitlePlate.trailingAnchor, constant: -26),
            subtitleLabel.topAnchor.constraint(equalTo: subtitlePlate.topAnchor, constant: 8),
            subtitleLabel.bottomAnchor.constraint(equalTo: subtitlePlate.bottomAnchor, constant: -10),
        ])
    }

    /// A visual effect view has no "amount" and must not be made translucent, so a partial blur is
    /// made by animating the effect in and stopping the animation part-way.
    private func applySubtitleBlur() {
        let strength = app.settings.subtitleBackground.blurStrength
        blurAnimator?.stopAnimation(true)
        blurAnimator = nil
        subtitleBlur.isHidden = strength == 0
        subtitleBlur.effect = nil
        guard strength > 0 else { return }
        guard strength < 1 else {
            subtitleBlur.effect = UIBlurEffect(style: .dark)
            return
        }
        let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) { [subtitleBlur] in
            subtitleBlur.effect = UIBlurEffect(style: .dark)
        }
        animator.pausesOnCompletion = true
        animator.fractionComplete = strength
        blurAnimator = animator
    }

    private func showCue(_ text: String) {
        shownCue = text
        subtitlePlate.isHidden = text.isEmpty
        guard !text.isEmpty else {
            subtitleLabel.attributedText = nil
            return
        }
        // On a plate the text needs no help; on bare video it gets an outline and a shadow.
        let bare = app.settings.subtitleBackground == .none
        let size = CGFloat(app.settings.subtitleSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineHeightMultiple = 1.15
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(bare ? 0.9 : 0)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = CGSize(width: 0, height: 2)
        subtitleLabel.attributedText = NSAttributedString(string: text, attributes: [
            .font: UIFont(name: AppFont.name(.medium), size: size) ?? .systemFont(ofSize: size, weight: .medium),
            .foregroundColor: app.settings.subtitleColor.color,
            // Negative width strokes and fills: a thin black outline keeps text readable over bright scenes.
            .strokeColor: UIColor.black,
            .strokeWidth: bare ? -2.5 : 0,
            .shadow: shadow,
            .paragraphStyle: paragraph,
        ])
    }

    /// How far subtitles sit above the bottom edge: clear of the episodes panel or the transport
    /// bar while either is showing.
    private var subtitleLift: CGFloat { episodesShowing ? -470 : (barShowing ? -250 : -70) }

    /// Lifts subtitles clear of the transport bar while it is showing.
    nonisolated func playerViewController(
        _ playerViewController: AVPlayerViewController,
        willTransitionToVisibilityOfTransportBar visible: Bool,
        with coordinator: AVPlayerViewControllerAnimationCoordinator
    ) {
        MainActor.assumeIsolated {
            barShowing = visible
            // The panels live in the bar, so they are gone when it is.
            if !visible { episodesShowing = false }
            subtitleBottom?.constant = subtitleLift
            let overlay = playerViewController.contentOverlayView
            coordinator.addCoordinatedAnimations({ overlay?.layoutIfNeeded() }, completion: nil)
        }
    }
}

/// The current season's episodes, shown as a tab of the player's info panel.
private struct EpisodeStrip: View {
    struct Entry: Identifiable {
        let index: Int
        let item: StreamItem
        var id: Int { index }
    }

    let entries: [Entry]
    let playing: Int
    let select: (Int) -> Void
    /// Told when the strip comes on screen and when it leaves.
    let shown: (Bool) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 24) {
                    ForEach(entries) { entry in
                        Button { select(entry.index) } label: {
                            EpisodeTile(item: entry.item, position: entry.index + 1, nowPlaying: entry.index == playing)
                        }
                        .buttonStyle(CardButtonStyle(radius: Theme.tileRadius, scale: 1.06))
                        .id(entry.index)
                    }
                }
                .padding(.horizontal, Theme.edge)
                .padding(.vertical, 26)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .onAppear {
                proxy.scrollTo(playing, anchor: .center)
                shown(true)
            }
            .onDisappear { shown(false) }
        }
    }
}

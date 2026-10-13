import SwiftUI

/// What the player is offering to do right now: skip the intro or the recap, or go on to the next episode.
@MainActor
@Observable
final class PlayerPrompt {
    enum Kind: Equatable { case intro, recap, next }

    struct Offer: Equatable {
        var kind: Kind
        var title: String
        /// Next episode only: how far the credits have run, 0...1, when the next one starts by itself.
        var countdown: Double?
    }

    /// The offer on screen, if any.
    var offer: Offer?
}

/// The offer as a pill in the app's own style: the red of the primary button, since the select
/// button acts on it for as long as it is up.
struct PlayerPromptView: View {
    let prompt: PlayerPrompt

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
            if let offer = prompt.offer {
                pill(offer)
                    .id(offer.kind)
                    .transition(.blurFade.combined(with: .offset(y: 18)))
            }
        }
        .padding(.trailing, Theme.edge)
        // Above the line subtitles sit on, so a long one does not run under the pill.
        .padding(.bottom, 230)
        .animation(Theme.focusSpring, value: prompt.offer?.kind)
        .allowsHitTesting(false)
    }

    private func pill(_ offer: PlayerPrompt.Offer) -> some View {
        let shape = Capsule(style: .continuous)
        return HStack(spacing: 14) {
            Image(systemName: offer.kind == .next ? "forward.end.fill" : "forward.fill")
                .font(.system(size: 23, weight: .bold))
            Text(offer.title)
                .font(.app(27, .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 40)
        .frame(height: 80)
        .background {
            shape.fill(LinearGradient(colors: [Color(hex: 0xFF6A4D), Theme.accent, Color(hex: 0xD92B58)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let countdown = offer.countdown {
                // Fills as the credits run: when it is full, the next episode starts.
                GeometryReader { geo in
                    Rectangle().fill(Color.white.opacity(0.26)).frame(width: geo.size.width * countdown)
                }
                .clipShape(shape)
                .animation(.linear(duration: 0.3), value: countdown)
            }
            // A lit top edge, as on the app's glass.
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
        }
        .shadow(color: Theme.accent.opacity(0.55), radius: 26, y: 8)
        .shadow(color: .black.opacity(0.35), radius: 16, y: 10)
    }
}

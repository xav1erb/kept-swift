import SwiftUI

// Presentation-only pacing for scripted chat transcripts. The engine appends a whole turn in one
// frame (user line + acknowledgment + next prompts); the iMessage feel is a re-timing of what the
// view REVEALS: the user's line lands instantly, each of Pom's lines arrives behind a short
// typing-dots beat. The engine's transcript stays the deterministic truth — drafts, resume, and
// tests never see this class. A resumed transcript reveals instantly (no replay).

@Observable
final class TranscriptPacer {

    private(set) var visible: [DraftBubble] = []
    private(set) var isPomTyping = false

    /// True once every engine bubble is on screen — the input area waits for this, so the next
    /// question's chips/placeholder never spoil a line Pom hasn't "sent" yet.
    var isCaughtUp: Bool {
        visible.count == target.count && !isPomTyping
    }

    private var target: [DraftBubble] = []
    private var revealGeneration = 0
    private var isRevealing = false

    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.8)

    /// First sync on appear. `paceOpening` types the opening prompts in (fresh start);
    /// otherwise the whole transcript shows at once (mid-interview resume).
    func prime(_ bubbles: [DraftBubble], paceOpening: Bool) {
        if paceOpening {
            reset(to: [])
            sync(to: bubbles)
        } else {
            reset(to: bubbles)
        }
    }

    func sync(to bubbles: [DraftBubble]) {
        // The engine's transcript is append-only; anything else is a reset — reveal instantly.
        guard bubbles.count >= target.count, bubbles.starts(with: target) else {
            reset(to: bubbles)
            return
        }
        withAnimation(Self.spring) { target = bubbles }
        drain()
    }

    private func reset(to bubbles: [DraftBubble]) {
        revealGeneration += 1
        isRevealing = false
        target = bubbles
        visible = bubbles
        isPomTyping = false
    }

    private func drain() {
        guard !isRevealing else { return }
        isRevealing = true
        let generation = revealGeneration
        Task { [weak self] in
            await self?.reveal(generation)
        }
    }

    private func reveal(_ generation: Int) async {
        while revealGeneration == generation, visible.count < target.count {
            let next = target[visible.count]
            guard next.author == .pom else {
                withAnimation(Self.spring) { visible.append(next) }
                continue
            }
            // A breath before the dots, then a typing beat scaled to the line's length.
            try? await Task.sleep(for: .milliseconds(250))
            guard revealGeneration == generation else { return }
            withAnimation(Self.spring) { isPomTyping = true }
            let beat = min(1.1, 0.4 + Double(next.text.count) * 0.008)
            try? await Task.sleep(for: .seconds(beat))
            guard revealGeneration == generation else { return }
            withAnimation(Self.spring) {
                isPomTyping = false
                visible.append(next)
            }
        }
        if revealGeneration == generation {
            isRevealing = false
        }
    }
}

/// The arrival transition for a chat bubble — a small pop from the sender's corner, like a
/// message landing. Reduce Motion collapses it to a plain fade.
func bubbleArrival(for author: DraftBubble.Author, reduceMotion: Bool) -> AnyTransition {
    guard !reduceMotion else { return .opacity }
    let anchor: UnitPoint = author == .pom ? .bottomLeading : .bottomTrailing
    return .scale(scale: 0.9, anchor: anchor).combined(with: .opacity)
}

/// Pom's typing-dots bubble, shaped like her message bubbles.
struct TypingIndicatorBubble: View {
    @Environment(ThemeModel.self) private var themeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let scrollId = "pom-typing"

    var body: some View {
        let tokens = themeModel.tokens
        HStack {
            Image(systemName: "ellipsis")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(tokens.inkSoft)
                .symbolEffect(
                    .variableColor.iterative.dimInactiveLayers,
                    options: .repeating,
                    isActive: !reduceMotion
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(tokens.card.opacity(tokens.cardOpacity))
                .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.radiusSmall))
            Spacer(minLength: 40)
        }
    }
}

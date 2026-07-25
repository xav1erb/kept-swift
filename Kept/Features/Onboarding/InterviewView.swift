import SwiftUI

// 4.6 — the interview chat (docs/onboarding.md §6). Renders the engine's transcript; input
// adapts to the current node (chips / field / free text). Every screen state ships: the chat is
// never blank (the engine always has at least the current node's prompts).

struct ChatBubbleView: View {
    @Environment(ThemeModel.self) private var themeModel
    let bubble: DraftBubble

    var body: some View {
        let tokens = themeModel.tokens
        HStack {
            if bubble.author == .user { Spacer(minLength: 40) }
            Text(bubble.text)
                .font(KeptFont.ui(16))
                .foregroundStyle(tokens.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    bubble.author == .pom
                        ? tokens.card.opacity(tokens.cardOpacity)
                        : tokens.rose.opacity(0.35)
                )
                .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.radiusSmall))
            if bubble.author == .pom { Spacer(minLength: 40) }
        }
    }
}

struct InterviewView: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(ThemeModel.self) private var themeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pacer = TranscriptPacer()
    @State private var draft = ""

    var body: some View {
        let tokens = themeModel.tokens
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(pacer.visible) { bubble in
                            ChatBubbleView(bubble: bubble)
                                .id(bubble.id)
                                .transition(bubbleArrival(for: bubble.author, reduceMotion: reduceMotion))
                        }
                        if pacer.isPomTyping {
                            TypingIndicatorBubble()
                                .id(TypingIndicatorBubble.scrollId)
                                .transition(bubbleArrival(for: .pom, reduceMotion: reduceMotion))
                        }
                    }
                    .padding(20)
                }
                .onChange(of: pacer.visible.count) { scrollToLatest(proxy) }
                .onChange(of: pacer.isPomTyping) { scrollToLatest(proxy) }
            }
            inputArea
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .background(tokens.card.opacity(tokens.cardOpacity * 0.5))
        }
        .task {
            // A fresh start types the opening in; a resumed transcript never replays.
            pacer.prime(model.interview.bubbles, paceOpening: model.interview.answers.isEmpty)
        }
        .onChange(of: model.interview.bubbles) { _, bubbles in
            pacer.sync(to: bubbles)
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            if pacer.isPomTyping {
                proxy.scrollTo(TypingIndicatorBubble.scrollId, anchor: .bottom)
            } else if let last = pacer.visible.last?.id {
                proxy.scrollTo(last, anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private var inputArea: some View {
        let tokens = themeModel.tokens
        // The input waits for Pom's last line to land — it belongs to a question that, until
        // then, hasn't been "sent" yet.
        if let node = model.interview.currentNode, pacer.isCaughtUp {
            VStack(alignment: .leading, spacing: 10) {
                switch node.input {
                case .chips(let chips):
                    ChipFlow(chips: chips) { chip in
                        Task { await model.interviewTapChip(chip) }
                    }
                case .field(let placeholder, let keyboard):
                    answerField(placeholder: placeholder, isNumber: keyboard == .number)
                case .freeText(let placeholder):
                    answerField(placeholder: placeholder, isNumber: false, multiline: true)
                }
                if node.skippable {
                    Button("skip this one") { model.interviewSkip() }
                        .font(KeptFont.ui(13))
                        .foregroundStyle(tokens.inkSoft)
                }
            }
            .padding(.top, 10)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private func answerField(placeholder: String, isNumber: Bool, multiline: Bool = false) -> some View {
        let tokens = themeModel.tokens
        return HStack(spacing: 10) {
            TextField(placeholder, text: $draft, axis: multiline ? .vertical : .horizontal)
                .font(KeptFont.ui(16))
                .keyboardType(isNumber ? .numberPad : .default)
                .lineLimit(multiline ? 1...4 : 1...1)
                .padding(12)
                .background(tokens.card.opacity(tokens.cardOpacity))
                .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.radiusSmall))
            Button {
                let text = draft
                draft = ""
                Task { await model.interviewSubmitText(text) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(tokens.ink)
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

struct ChipFlow: View {
    @Environment(ThemeModel.self) private var themeModel
    let chips: [InterviewChip]
    let onTap: (InterviewChip) -> Void

    var body: some View {
        let tokens = themeModel.tokens
        FlowLayout(spacing: 8) {
            ForEach(chips) { chip in
                Button { onTap(chip) } label: {
                    Text(chip.label)
                        .font(KeptFont.ui(15))
                        .foregroundStyle(tokens.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(tokens.card.opacity(tokens.cardOpacity))
                        .clipShape(Capsule())
                }
            }
        }
    }
}

/// Minimal wrapping layout for chip rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.reduce(CGFloat.zero) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in computeRows(proposal: proposal, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var height: CGFloat = 0
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var current = Row()
        var x: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
                x = 0
            }
            current.indices.append(index)
            current.height = max(current.height, size.height)
            x += size.width + spacing
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

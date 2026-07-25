import SwiftUI

/// The chat tab (M4-CONTRACTS §6): persistent transcript, quick-reply chips, prep entry, and
/// the honest failure states — a failed reply keeps the user's bubble and offers retry; the
/// filing path already has the words.
struct ChapterChatTab: View {
    @Bindable var model: ChapterDetailModel
    @Environment(ThemeModel.self) private var themeModel

    @State private var draft = ""
    @FocusState private var composerFocused: Bool

    var body: some View {
        let tokens = themeModel.tokens
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if model.messages.isEmpty {
                            Text(ChapterDetailCopy.emptyChat)
                                .font(KeptFont.ui(14))
                                .foregroundStyle(tokens.inkSoft)
                                .multilineTextAlignment(.center)
                                .padding(.top, 40)
                        }
                        ForEach(model.messages) { message in
                            messageView(message, tokens: tokens)
                                .id(message.id)
                        }
                        if model.isAwaitingReply {
                            HStack {
                                Text(ChapterDetailCopy.typing)
                                    .font(KeptFont.ui(13))
                                    .foregroundStyle(tokens.inkSoft)
                                Spacer()
                            }
                            .padding(.horizontal, 4)
                        }
                        if model.replyFailed {
                            retryRow(tokens: tokens)
                        }
                        if model.filingLagged {
                            Text(ChapterDetailCopy.filingLag)
                                .font(KeptFont.ui(11))
                                .foregroundStyle(tokens.inkSoft)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                }
                .onChange(of: model.messages.count) {
                    if let last = model.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            chipsRow(tokens: tokens)
            if model.canOfferPrep, let event = model.upcomingEvent() {
                prepEntry(event: event, tokens: tokens)
            }
            composer(tokens: tokens)
        }
    }

    @ViewBuilder
    private func messageView(_ message: ChatMessageSnapshot, tokens: ThemeTokens) -> some View {
        VStack(spacing: 8) {
            if !message.text.isEmpty {
                ChatBubbleView(bubble: DraftBubble(
                    id: message.id,
                    author: message.author == .pom ? .pom : .user,
                    text: message.text
                ))
            }
            if let card = message.card {
                PrepCardView(card: card, model: model)
            }
        }
    }

    @ViewBuilder
    private func chipsRow(tokens: ThemeTokens) -> some View {
        let quickReplies = model.chips
        let showsPerspective = model.canAskPerspective && !model.isAwaitingReply
        let showsContinue = model.showsContinue
        if !quickReplies.isEmpty || showsPerspective || showsContinue {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if showsContinue {
                        chip(ChapterDetailCopy.prepContinue, tokens: tokens, accent: true) {
                            Task { await model.advancePrep() }
                        }
                    }
                    ForEach(quickReplies, id: \.self) { reply in
                        chip(reply, tokens: tokens) {
                            Task { await model.send(reply) }
                        }
                    }
                    if showsPerspective && !quickReplies.contains(ChapterDetailCopy.prepPerspectiveChip) {
                        chip(ChapterDetailCopy.prepPerspectiveChip, tokens: tokens) {
                            Task { await model.askPerspective() }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 6)
        }
    }

    private func chip(_ label: String, tokens: ThemeTokens, accent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(KeptFont.ui(13))
                .foregroundStyle(tokens.ink)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(accent ? tokens.gold.opacity(0.35) : tokens.card.opacity(tokens.cardOpacity))
                )
        }
        .disabled(model.isAwaitingReply)
    }

    private func prepEntry(event: EventSnapshot, tokens: ThemeTokens) -> some View {
        HStack(spacing: 10) {
            Text("\(ChapterDetailCopy.prepEntryPrefix) \u{201C}\(event.title)\u{201D}?")
                .font(KeptFont.ui(13))
                .foregroundStyle(tokens.inkSoft)
            Spacer()
            Button(ChapterDetailCopy.prepEntryCTA) {
                Task { await model.startPrep() }
            }
            .font(KeptFont.ui(13))
            .foregroundStyle(tokens.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: ThemeTokens.radiusSmall)
                .strokeBorder(tokens.gold.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private func retryRow(tokens: ThemeTokens) -> some View {
        Button {
            Task { await model.retryReply() }
        } label: {
            Text(ChapterDetailCopy.replyFailed)
                .font(KeptFont.ui(13))
                .foregroundStyle(tokens.inkSoft)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: ThemeTokens.radiusSmall)
                        .fill(tokens.rose.opacity(0.18))
                )
        }
    }

    private func composer(tokens: ThemeTokens) -> some View {
        HStack(spacing: 10) {
            // Text-only in M4 — the mic arrives with the M5 VoiceCapture module (no dead button).
            TextField(ChapterDetailCopy.composerPlaceholder, text: $draft, axis: .vertical)
                .font(KeptFont.ui(15))
                .foregroundStyle(tokens.ink)
                .lineLimit(1...4)
                .focused($composerFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: ThemeTokens.radiusSmall)
                        .fill(tokens.card.opacity(tokens.cardOpacity))
                )
            Button {
                let text = draft
                draft = ""
                Task { await model.send(text) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(
                        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? tokens.inkSoft.opacity(0.5) : tokens.gold
                    )
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isAwaitingReply)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

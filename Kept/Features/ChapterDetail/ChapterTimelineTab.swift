import SwiftUI

/// The timeline tab (M4-CONTRACTS §7): gradient line, the typed node grammar, and the folded
/// pill whose expansion is view-local @State — no store field exists, so a fresh render always
/// leads folded (structural refold).
struct ChapterTimelineTab: View {
    let model: ChapterDetailModel
    @Environment(ThemeModel.self) private var themeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tokens = themeModel.tokens
        let nodes = TimelineNode.nodes(for: model.events, now: .now, calendar: .current)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                introCard(tokens: tokens)
                if nodes.isEmpty {
                    Text(ChapterDetailCopy.timelineEmpty)
                        .font(KeptFont.ui(14))
                        .foregroundStyle(tokens.inkSoft)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    ForEach(nodes) { node in
                        TimelineNodeRow(node: node, reduceMotion: reduceMotion)
                    }
                }
                footer(tokens: tokens)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 90)
        }
    }

    private func introCard(tokens: ThemeTokens) -> some View {
        Text("\(ChapterDetailCopy.timelineIntroPrefix) \(model.summary?.title ?? "this chapter"), \(ChapterDetailCopy.timelineIntroSuffix)")
            .font(KeptFont.ui(14))
            .foregroundStyle(tokens.inkSoft)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ThemeTokens.radiusCard)
                    .fill(tokens.card.opacity(tokens.cardOpacity))
            )
            .padding(.bottom, 14)
    }

    private func footer(tokens: ThemeTokens) -> some View {
        Text(ChapterDetailCopy.timelineFooter)
            .font(KeptFont.ui(12))
            .foregroundStyle(tokens.inkSoft)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 22)
    }
}

/// One node on the line. The gradient segment colors run rose→lilac→mint via the row's accent.
private struct TimelineNodeRow: View {
    let node: TimelineNode
    let reduceMotion: Bool
    @Environment(ThemeModel.self) private var themeModel

    /// View-local by design (C3): there is nowhere to persist this — refold is structural.
    @State private var isExpanded = false
    @State private var pulseOn = false

    var body: some View {
        let tokens = themeModel.tokens
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                dot(tokens: tokens)
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [tokens.rose.opacity(0.5), tokens.lilac.opacity(0.5), tokens.mint.opacity(0.5)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 2)
            }
            .frame(width: 22)
            card(tokens: tokens)
                .padding(.bottom, 14)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func dot(tokens: ThemeTokens) -> some View {
        ZStack {
            Circle()
                .fill(accent(tokens: tokens))
                .frame(width: 10, height: 10)
            if node.pulses && !reduceMotion {
                Circle()
                    .stroke(accent(tokens: tokens).opacity(0.6), lineWidth: 2)
                    .frame(width: 10, height: 10)
                    .scaleEffect(pulseOn ? 2.0 : 1.0)
                    .opacity(pulseOn ? 0 : 0.8)
                    .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: pulseOn)
                    .onAppear { pulseOn = true }
            }
        }
        .padding(.top, 4)
    }

    private func accent(tokens: ThemeTokens) -> Color {
        switch node {
        case .folded: tokens.mint
        case .openStorm: tokens.rose
        case .calmReceipt: tokens.inkSoft
        case .upcoming: tokens.gold
        case .bright: tokens.gold
        case .receipt: tokens.inkSoft
        case .gentle: tokens.blue
        }
    }

    @ViewBuilder
    private func card(tokens: ThemeTokens) -> some View {
        switch node {
        case .folded(let event):
            foldedPill(event, tokens: tokens)
        case .openStorm(let event):
            eventCard(event, tokens: tokens) {
                Text("OPEN")
                    .font(KeptFont.ui(10).weight(.bold))
                    .foregroundStyle(tokens.rose)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(tokens.rose.opacity(0.18)))
            }
        case .calmReceipt(let event), .receipt(let event):
            eventCard(event, tokens: tokens) {
                Text(ChapterDetailCopy.onRecord)
                    .font(KeptFont.ui(11))
                    .foregroundStyle(tokens.inkSoft)
            }
        case .upcoming(let event, let prepped):
            upcomingCard(event, prepped: prepped, tokens: tokens)
        case .bright(let event):
            eventCard(event, tokens: tokens, gold: true) { EmptyView() }
        case .gentle(let event):
            eventCard(event, tokens: tokens) { EmptyView() }
        }
    }

    private func eventCard(
        _ event: EventSnapshot, tokens: ThemeTokens, gold: Bool = false,
        @ViewBuilder badge: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(event.date.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(KeptFont.ui(11))
                    .foregroundStyle(tokens.inkSoft)
                Spacer()
                badge()
            }
            Text(event.title)
                .font(KeptFont.display(15))
                .foregroundStyle(tokens.ink)
            if !event.body.isEmpty {
                Text(event.body)
                    .font(KeptFont.ui(13))
                    .foregroundStyle(tokens.inkSoft)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ThemeTokens.radiusCard)
                .fill(gold ? tokens.gold.opacity(0.2) : tokens.card.opacity(tokens.cardOpacity))
        )
    }

    private func upcomingCard(_ event: EventSnapshot, prepped: Bool, tokens: ThemeTokens) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.date.formatted(.dateTime.month(.abbreviated).day()))
                .font(KeptFont.ui(11))
                .foregroundStyle(tokens.inkSoft)
            Text(event.title)
                .font(KeptFont.display(15))
                .foregroundStyle(tokens.ink)
            if prepped {
                Text(ChapterDetailCopy.upcomingPrepped)
                    .font(KeptFont.ui(12))
                    .foregroundStyle(tokens.gold)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ThemeTokens.radiusCard)
                .strokeBorder(tokens.gold.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        )
    }

    @ViewBuilder
    private func foldedPill(_ event: EventSnapshot, tokens: ThemeTokens) -> some View {
        if isExpanded {
            VStack(alignment: .leading, spacing: 6) {
                Text(event.title)
                    .font(KeptFont.display(15))
                    .foregroundStyle(tokens.ink)
                if let reason = event.healedReason, !reason.isEmpty {
                    Text("\u{201C}\(reason)\u{201D}")
                        .font(KeptFont.ui(13))
                        .foregroundStyle(tokens.inkSoft)
                }
                Text(ChapterDetailCopy.foldedFrame)
                    .font(KeptFont.ui(12))
                    .foregroundStyle(tokens.mint)
                Button(ChapterDetailCopy.refold) {
                    withAnimation { isExpanded = false }
                }
                .font(KeptFont.ui(12))
                .foregroundStyle(tokens.inkSoft)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ThemeTokens.radiusCard)
                    .fill(tokens.mint.opacity(0.12))
            )
        } else {
            Button {
                withAnimation { isExpanded = true }
            } label: {
                Text(ChapterDetailCopy.foldedPill)
                    .font(KeptFont.ui(12))
                    .foregroundStyle(tokens.inkSoft)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().strokeBorder(
                            tokens.mint.opacity(0.7),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                    )
            }
        }
    }
}

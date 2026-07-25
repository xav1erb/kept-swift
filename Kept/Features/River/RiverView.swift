import SwiftUI

/// The River tab (M5-CONTRACTS §5): scroll view + generated layout, no 3D. The winding path is
/// a sinusoid Shape; cards ride alternating banks with the curve's offset; time markers float
/// on the stream. Only the open storm pulses (Reduce Motion honored).
struct RiverView: View {
    @Environment(KeptStore.self) private var store
    @Environment(ThemeModel.self) private var themeModel
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var model: RiverModel?

    var body: some View {
        let tokens = themeModel.tokens
        Group {
            if let model {
                switch model.state {
                case .loading:
                    ProgressView().tint(tokens.inkSoft)
                case .failed:
                    SurfacePlaceholder(title: "the River", state: .error(message: RiverCopy.emptyRiver))
                case .ready:
                    content(model: model, tokens: tokens)
                }
            } else {
                ProgressView().tint(tokens.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if model == nil { model = RiverModel(store: store) }
            model?.refresh()
        }
    }

    @ViewBuilder
    private func content(model: RiverModel, tokens: ThemeTokens) -> some View {
        VStack(spacing: 0) {
            filterRow(model: model, tokens: tokens)
            ScrollView {
                ZStack(alignment: .top) {
                    RiverPathShape(totalHeight: model.layout.totalHeight)
                        .stroke(
                            LinearGradient(
                                colors: [tokens.rose.opacity(0.55), tokens.lilac.opacity(0.55),
                                         tokens.blue.opacity(0.5), tokens.gold.opacity(0.6)],
                                startPoint: .top, endPoint: .bottom
                            ),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .frame(height: model.layout.totalHeight)

                    // Pom floats at Today.
                    ZStack {
                        Circle().fill(tokens.gold.opacity(0.9)).frame(width: 44, height: 44)
                        Circle().fill(tokens.card).frame(width: 36, height: 36)
                    }
                    .offset(y: 8)

                    ForEach(model.layout.markers) { marker in
                        Text(marker.label)
                            .font(KeptFont.ui(11).weight(.semibold))
                            .kerning(1.1)
                            .foregroundStyle(tokens.inkSoft)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(tokens.card.opacity(tokens.cardOpacity)))
                            .offset(x: RiverLayout.curveOffset(y: marker.y), y: marker.y)
                    }

                    ForEach(model.layout.slots) { slot in
                        if let card = model.cards.first(where: { $0.id == slot.cardId }) {
                            RiverCardView(card: card, reduceMotion: reduceMotion) {
                                router.open(deepLink: URL(string: "kept://chapter/\(card.chapterId.uuidString)")!)
                            }
                            .frame(width: 235)
                            .frame(maxWidth: .infinity, alignment: slot.bank == .left ? .leading : .trailing)
                            .padding(slot.bank == .left ? .leading : .trailing, 14)
                            .offset(x: RiverLayout.curveOffset(y: slot.y) * (slot.bank == .left ? 0.4 : -0.4), y: slot.y)
                        }
                    }

                    endCap(tokens: tokens)
                        .offset(y: model.layout.totalHeight - 96)

                    if model.cards.isEmpty {
                        Text(RiverCopy.emptyRiver)
                            .font(KeptFont.ui(14))
                            .foregroundStyle(tokens.inkSoft)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .offset(y: 120)
                    }
                }
                .frame(height: max(model.layout.totalHeight, 320), alignment: .top)
                .padding(.bottom, 90)
            }
        }
    }

    private func filterRow(model: RiverModel, tokens: ThemeTokens) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(
                    label: RiverCopy.everythingChip, icon: nil,
                    isSelected: model.selectedChapterId == nil, tokens: tokens
                ) { model.selectedChapterId = nil }
                ForEach(model.chapterFilters, id: \.id) { filter in
                    filterChip(
                        label: filter.title, icon: filter.iconRef,
                        isSelected: model.selectedChapterId == filter.id, tokens: tokens
                    ) { model.selectedChapterId = filter.id }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
    }

    private func filterChip(
        label: String, icon: String?, isSelected: Bool, tokens: ThemeTokens, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { PinIcon(iconRef: icon, tokens: tokens) }
                Text(label)
                    .font(KeptFont.ui(13))
                    .foregroundStyle(isSelected ? tokens.ink : tokens.inkSoft)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isSelected ? tokens.card.opacity(tokens.cardOpacity) : tokens.card.opacity(0.35))
            )
        }
    }

    private func endCap(tokens: ThemeTokens) -> some View {
        VStack(spacing: 6) {
            Text("☀️").font(.system(size: 30))
            Text(RiverCopy.endCap)
                .font(KeptFont.display(15))
                .foregroundStyle(tokens.inkSoft)
        }
    }
}

/// The winding stream — a centered sinusoid, the same function the layout offsets cards with.
private struct RiverPathShape: Shape {
    let totalHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX
        path.move(to: CGPoint(x: midX, y: 0))
        var y: CGFloat = 0
        while y < totalHeight {
            path.addLine(to: CGPoint(x: midX + RiverLayout.curveOffset(y: y), y: y))
            y += 12
        }
        return path
    }
}

/// One card on a bank. §9 in pixels: positives large & warm, negatives small & calm, the open
/// storm alone pulses, sensitive silence shows only the fixed line + an icon.
private struct RiverCardView: View {
    let card: RiverCard
    let reduceMotion: Bool
    let onOpen: () -> Void
    @Environment(ThemeModel.self) private var themeModel

    @State private var isExpanded = false   // folded pill only — view-local, structural refold
    @State private var pulseOn = false

    var body: some View {
        let tokens = themeModel.tokens
        Button(action: onOpen) {
            cardBody(tokens: tokens)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func cardBody(tokens: ThemeTokens) -> some View {
        switch card.kind {
        case .bright(let event):
            shell(tokens: tokens, fill: tokens.gold.opacity(0.2)) {
                badge(tokens: tokens)
                Text(event.title).font(KeptFont.display(15)).foregroundStyle(tokens.ink)
                if !event.body.isEmpty {
                    Text("\u{201C}\(event.body)\u{201D}")
                        .font(KeptFont.ui(13)).foregroundStyle(tokens.inkSoft).lineLimit(3)
                }
            }
        case .gentle(let event):
            shell(tokens: tokens) {
                badge(tokens: tokens)
                Text(event.title).font(KeptFont.display(14)).foregroundStyle(tokens.ink)
            }
        case .receipt(let event):
            shell(tokens: tokens) {
                badge(tokens: tokens)
                Text(event.title).font(KeptFont.display(14)).foregroundStyle(tokens.ink)
                Text(ChapterDetailCopy.onRecord).font(KeptFont.ui(11)).foregroundStyle(tokens.inkSoft)
            }
        case .calmReceipt(let event):
            shell(tokens: tokens) {
                badge(tokens: tokens)
                Text("\(event.title) — \(RiverCopy.onRecordCalmly)")
                    .font(KeptFont.ui(13)).foregroundStyle(tokens.inkSoft).lineLimit(2)
            }
        case .openStorm(let event):
            shell(tokens: tokens, fill: tokens.rose.opacity(0.14)) {
                HStack {
                    badge(tokens: tokens)
                    Spacer()
                    ZStack {
                        Circle().fill(tokens.rose).frame(width: 8, height: 8)
                        if !reduceMotion {
                            Circle()
                                .stroke(tokens.rose.opacity(0.6), lineWidth: 2)
                                .frame(width: 8, height: 8)
                                .scaleEffect(pulseOn ? 2.2 : 1.0)
                                .opacity(pulseOn ? 0 : 0.8)
                                .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: pulseOn)
                                .onAppear { pulseOn = true }
                        }
                    }
                    Text("OPEN")
                        .font(KeptFont.ui(10).weight(.bold)).foregroundStyle(tokens.rose)
                }
                Text(event.title).font(KeptFont.display(14)).foregroundStyle(tokens.ink)
            }
        case .folded:
            if isExpanded {
                shell(tokens: tokens, fill: tokens.mint.opacity(0.12)) {
                    Text(ChapterDetailCopy.foldedFrame)
                        .font(KeptFont.ui(12)).foregroundStyle(tokens.mint)
                    Text(ChapterDetailCopy.refold)
                        .font(KeptFont.ui(12)).foregroundStyle(tokens.inkSoft)
                }
                .onTapGesture { withAnimation { isExpanded = false } }
            } else {
                Text(ChapterDetailCopy.foldedPill)
                    .font(KeptFont.ui(12)).foregroundStyle(tokens.inkSoft)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(
                        Capsule().strokeBorder(
                            tokens.mint.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                    )
                    .onTapGesture { withAnimation { isExpanded = true } }
            }
        case .sensitiveSilence:
            shell(tokens: tokens, fill: tokens.blue.opacity(0.10)) {
                HStack(spacing: 6) {
                    PinIcon(iconRef: card.chapterIcon, tokens: themeModel.tokens)
                    Text(RiverCopy.sensitiveSilence)
                        .font(KeptFont.ui(13)).foregroundStyle(tokens.inkSoft)
                }
            }
        }
    }

    private func badge(tokens: ThemeTokens) -> some View {
        HStack(spacing: 5) {
            PinIcon(iconRef: card.chapterIcon, tokens: tokens)
            if !card.chapterTitle.isEmpty {
                Text(card.chapterTitle).font(KeptFont.ui(11)).foregroundStyle(tokens.inkSoft)
            }
            Spacer(minLength: 0)
            Text(card.date.formatted(.dateTime.month(.abbreviated).day()))
                .font(KeptFont.ui(10)).foregroundStyle(tokens.inkSoft.opacity(0.8))
        }
    }

    private func shell(
        tokens: ThemeTokens, fill: Color? = nil, @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) { content() }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ThemeTokens.radiusCard)
                    .fill(fill ?? tokens.card.opacity(tokens.cardOpacity))
            )
    }
}

import SwiftUI

/// The designed prep components (whitepaper §7 — "a designed component, not plain text").
/// Receipt chips render title/date FROM THE STORE via `model.receiptDisplay` — the model's
/// note only annotates; an id that doesn't resolve never got this far (envelope rejected).
struct PrepCardView: View {
    let card: PrepCard
    let model: ChapterDetailModel
    @Environment(ThemeModel.self) private var themeModel

    var body: some View {
        let tokens = themeModel.tokens
        Group {
            switch card {
            case .reframe(let goal, let receipts):
                reframeCard(goal: goal, receipts: receipts, tokens: tokens)
            case .likelyAnswers(let answers):
                likelyAnswersCard(answers: answers, tokens: tokens)
            case .perspective(let incidentRead, let patternRead, let signals, let grounding):
                perspectiveCard(
                    incidentRead: incidentRead, patternRead: patternRead,
                    signals: signals, grounding: grounding, tokens: tokens
                )
            case .keepCard(let items, let closingLine):
                keepCard(items: items, closingLine: closingLine, tokens: tokens)
            case .openingClose(let opening, let close):
                openingCloseCard(opening: opening, close: close, tokens: tokens)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Cards

    private func reframeCard(goal: String, receipts: [ReceiptRef], tokens: ThemeTokens) -> some View {
        cardShell(title: "the real goal", accent: tokens.lilac, tokens: tokens) {
            Text(goal)
                .font(KeptFont.ui(15))
                .foregroundStyle(tokens.ink)
            ForEach(receipts, id: \.id) { receipt in
                receiptChip(receipt, tokens: tokens)
            }
        }
    }

    private func likelyAnswersCard(answers: [LikelyAnswer], tokens: ThemeTokens) -> some View {
        cardShell(title: "likely answers", accent: tokens.blue, tokens: tokens) {
            ForEach(Array(answers.enumerated()), id: \.offset) { _, answer in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\u{201C}\(answer.theirLine)\u{201D}")
                        .font(KeptFont.ui(14))
                        .foregroundStyle(tokens.ink)
                    Text(answer.read)
                        .font(KeptFont.ui(12))
                        .foregroundStyle(tokens.inkSoft)
                    Text("you can say: \u{201C}\(answer.counter)\u{201D}")
                        .font(KeptFont.ui(13))
                        .foregroundStyle(tokens.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: ThemeTokens.radiusSmall)
                                .fill(tokens.mint.opacity(0.25))
                        )
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func perspectiveCard(
        incidentRead: String, patternRead: String, signals: [PerspectiveSignal],
        grounding: String, tokens: ThemeTokens
    ) -> some View {
        cardShell(title: "honest calibration", accent: tokens.peach, tokens: tokens) {
            labeled("this moment", incidentRead, tokens: tokens)
            labeled("the pattern", patternRead, tokens: tokens)
            ForEach(Array(signals.enumerated()), id: \.offset) { _, signal in
                HStack(alignment: .top, spacing: 6) {
                    Text(signal.present ? "●" : "○")
                        .font(.system(size: 11))
                        .foregroundStyle(signal.present ? tokens.rose : tokens.mint)
                        .padding(.top, 2)
                    Text(signal.text)
                        .font(KeptFont.ui(13))
                        .foregroundStyle(tokens.inkSoft)
                }
            }
            Text(grounding)
                .font(KeptFont.ui(14))
                .foregroundStyle(tokens.ink)
        }
    }

    private func keepCard(items: [ReceiptRef], closingLine: String, tokens: ThemeTokens) -> some View {
        cardShell(title: "worth remembering tonight", accent: tokens.gold, tokens: tokens, gold: true) {
            ForEach(items, id: \.id) { item in
                receiptChip(item, tokens: tokens)
            }
            Text(closingLine)
                .font(KeptFont.ui(14))
                .foregroundStyle(tokens.ink)
        }
    }

    private func openingCloseCard(opening: String, close: String, tokens: ThemeTokens) -> some View {
        cardShell(title: "your opening", accent: tokens.mint, tokens: tokens) {
            Text("\u{201C}\(opening)\u{201D}")
                .font(KeptFont.display(16))
                .foregroundStyle(tokens.ink)
            Text(close)
                .font(KeptFont.ui(13))
                .foregroundStyle(tokens.inkSoft)
        }
    }

    // MARK: - Pieces

    private func cardShell(
        title: String, accent: Color, tokens: ThemeTokens, gold: Bool = false,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(KeptFont.ui(11).weight(.semibold))
                .foregroundStyle(tokens.inkSoft)
                .textCase(.uppercase)
                .kerning(0.8)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ThemeTokens.radiusCard)
                .fill(gold ? tokens.gold.opacity(0.18) : tokens.card.opacity(themeModel.tokens.cardOpacity))
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: 3)
                .padding(.vertical, 10)
        }
    }

    private func labeled(_ label: String, _ text: String, tokens: ThemeTokens) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(KeptFont.ui(11))
                .foregroundStyle(tokens.inkSoft)
            Text(text)
                .font(KeptFont.ui(14))
                .foregroundStyle(tokens.ink)
        }
    }

    @ViewBuilder
    private func receiptChip(_ receipt: ReceiptRef, tokens: ThemeTokens) -> some View {
        if let display = model.receiptDisplay(receipt.id) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(tokens.gold)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(display.title) · \(display.date.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(KeptFont.ui(13))
                        .foregroundStyle(tokens.ink)
                    Text(receipt.note)
                        .font(KeptFont.ui(12))
                        .foregroundStyle(tokens.inkSoft)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: ThemeTokens.radiusSmall)
                    .fill(tokens.card.opacity(0.6))
            )
        }
    }
}

import SwiftUI

// The new-chapter surface (M3-CONTRACTS §5): the 10-type grid → the scripted sequence (shared
// engine + chat components) → the building moment → back to the world, where the new pin is.
// Sensitive types show NO question count anywhere (C3 — structural, never-tested).

struct NewChapterView: View {
    @Environment(NewChapterModel.self) private var model
    @Environment(ThemeModel.self) private var themeModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let tokens = themeModel.tokens
        Group {
            switch model.phase {
            case .picking:
                gridScreen(tokens: tokens)
            case .sequence:
                sequenceScreen(tokens: tokens)
            case .building:
                buildingScreen(tokens: tokens)
            case .done:
                doneScreen(tokens: tokens)
            }
        }
        .background(tokens.backgroundGradient.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            if model.phase == .done { model.reset() }
        }
    }

    // MARK: - The grid

    private func gridScreen(tokens: ThemeTokens) -> some View {
        @Bindable var model = model
        return ScrollView {
            VStack(spacing: 16) {
                Text("Start a new chapter")
                    .font(KeptFont.display(24))
                    .foregroundStyle(tokens.ink)
                    .padding(.top, 12)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                    ForEach(NewChapterModel.cards()) { card in
                        typeCard(card, tokens: tokens, isSelected: model.selectedType == card.type)
                            .onTapGesture { model.selectedType = card.type }
                    }
                }
                Text("Pom will ask a few questions to build this room — you can stop anytime.")
                    .font(KeptFont.ui(13))
                    .foregroundStyle(tokens.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button {
                    model.begin()
                } label: {
                    Text("Begin this chapter with Pom →")
                        .font(KeptFont.ui(16))
                        .foregroundStyle(tokens.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(tokens.card.opacity(model.selectedType == nil ? tokens.cardOpacity * 0.4 : tokens.cardOpacity))
                        .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.radiusSmall))
                }
                .disabled(model.selectedType == nil)
            }
            .padding(20)
        }
    }

    private func typeCard(_ card: NewChapterModel.TypeCard, tokens: ThemeTokens, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: card.symbol)
                .font(.system(size: 20))
                .foregroundStyle(tokens.ink)
            Text(card.name)
                .font(KeptFont.ui(15))
                .foregroundStyle(tokens.ink)
            Text(card.oneLiner)
                .font(KeptFont.ui(11))
                .foregroundStyle(tokens.inkSoft)
                .lineLimit(2, reservesSpace: true)
            // Sensitive types have no countText by construction — only the gentle tag renders.
            if let count = card.countText {
                Text(count)
                    .font(KeptFont.ui(10))
                    .foregroundStyle(tokens.inkSoft)
            } else if let gentle = card.gentleText {
                Text(gentle)
                    .font(KeptFont.ui(10))
                    .foregroundStyle(tokens.lilac)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tokens.card.opacity(tokens.cardOpacity))
        .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.radiusCard))
        .overlay(
            RoundedRectangle(cornerRadius: ThemeTokens.radiusCard)
                .strokeBorder(isSelected ? tokens.ink.opacity(0.6) : .clear, lineWidth: 1.5)
        )
    }

    // MARK: - The sequence (shared chat components)

    @ViewBuilder
    private func sequenceScreen(tokens: ThemeTokens) -> some View {
        if let engine = model.engine {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(engine.bubbles) { bubble in
                                ChatBubbleView(bubble: bubble).id(bubble.id)
                            }
                        }
                        .padding(20)
                    }
                    .onChange(of: engine.bubbles.count) {
                        if let last = engine.bubbles.last?.id {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                }
                sequenceInput(engine: engine, tokens: tokens)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .background(tokens.card.opacity(tokens.cardOpacity * 0.5))
            }
        }
    }

    @ViewBuilder
    private func sequenceInput(engine: InterviewEngine, tokens: ThemeTokens) -> some View {
        if engine.currentNode != nil {
            VStack(alignment: .leading, spacing: 10) {
                SequenceAnswerField { text in
                    await model.submitText(text)
                }
                HStack(spacing: 18) {
                    Button("skip this one") { model.skip() }
                        .font(KeptFont.ui(13))
                        .foregroundStyle(tokens.inkSoft)
                    Button("that's enough for now") {
                        Task { await model.stopEarly() }
                    }
                    .font(KeptFont.ui(13))
                    .foregroundStyle(tokens.inkSoft)
                }
            }
            .padding(.top, 10)
        }
    }

    // MARK: - Building / done (the flush moment — honest, no fake progress)

    private func buildingScreen(tokens: ThemeTokens) -> some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Building this room…")
                .font(KeptFont.display(20))
                .foregroundStyle(tokens.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func doneScreen(tokens: ThemeTokens) -> some View {
        VStack(spacing: 14) {
            Text("It's on your world now.")
                .font(KeptFont.display(22))
                .foregroundStyle(tokens.ink)
            if model.flushLagged {
                // Honest state: rows are still queued; filing lags, it never drops (NN#7).
                Text("Some of what you told me is still filing — it's safe, and it'll settle in shortly.")
                    .font(KeptFont.ui(13))
                    .foregroundStyle(tokens.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Button {
                dismiss()
            } label: {
                Text("Take me there")
                    .font(KeptFont.ui(16))
                    .foregroundStyle(tokens.ink)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(tokens.card.opacity(tokens.cardOpacity))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Free-text answer field for sequence nodes (every sequence node is free text).
private struct SequenceAnswerField: View {
    @Environment(ThemeModel.self) private var themeModel
    @State private var draft = ""
    let onSubmit: (String) async -> Void

    var body: some View {
        let tokens = themeModel.tokens
        HStack(spacing: 10) {
            TextField("tell me", text: $draft, axis: .vertical)
                .font(KeptFont.ui(16))
                .lineLimit(1...4)
                .padding(12)
                .background(tokens.card.opacity(tokens.cardOpacity))
                .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.radiusSmall))
            Button {
                let text = draft
                draft = ""
                Task { await onSubmit(text) }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(tokens.ink)
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

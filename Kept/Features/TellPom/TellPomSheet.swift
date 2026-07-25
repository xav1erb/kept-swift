import SwiftUI

/// The Tell Pom capture sheet (M5-CONTRACTS §3) — fresh each session: the model is created at
/// presentation and discarded at dismiss; chapters are the memory, this sheet never is.
struct TellPomSheet: View {
    @Environment(KeptStore.self) private var store
    @Environment(AppClients.self) private var clients
    @Environment(ThemeModel.self) private var themeModel
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var model: VentModel?
    @State private var draft = ""

    var body: some View {
        let tokens = themeModel.tokens
        VStack(spacing: 0) {
            header(tokens: tokens)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        if let model, model.items.isEmpty {
                            hero(tokens: tokens)
                            promptZone(model: model, tokens: tokens)
                        }
                        if let model {
                            ForEach(model.items) { item in
                                itemView(item, model: model, tokens: tokens)
                                    .id(item.id)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 12)
                }
                .onChange(of: model?.items.count ?? 0) {
                    if let last = model?.items.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            composer(tokens: tokens)
        }
        .background(tokens.backgroundGradient.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            if model == nil {
                let fresh = VentModel(store: store, extraction: clients.extraction)
                model = fresh
                await fresh.start()
            }
        }
    }

    // MARK: - Pieces

    private func header(tokens: ThemeTokens) -> some View {
        HStack {
            Text(VentCopy.sealedBadge)
                .font(KeptFont.ui(11).weight(.semibold))
                .foregroundStyle(tokens.inkSoft)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(tokens.card.opacity(tokens.cardOpacity)))
            Spacer()
            Button {
                Task { await model?.endHold() }
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tokens.inkSoft)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    private func hero(tokens: ThemeTokens) -> some View {
        VStack(spacing: 10) {
            // Pom hero — placeholder circle until F7 art.
            ZStack {
                Circle().fill(tokens.gold.opacity(0.9)).frame(width: 74, height: 74)
                Circle().fill(tokens.card).frame(width: 60, height: 60)
                Text("• •").font(.system(size: 13)).foregroundStyle(tokens.ink)
            }
            .padding(.top, 8)
            Text(VentCopy.hero)
                .font(KeptFont.display(26))
                .foregroundStyle(tokens.ink)
            Text(VentCopy.heroSub)
                .font(KeptFont.ui(14))
                .foregroundStyle(tokens.inkSoft)
                .multilineTextAlignment(.center)
            Text(VentCopy.filingNote)
                .font(KeptFont.ui(12))
                .foregroundStyle(tokens.inkSoft.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
        .padding(.bottom, 6)
    }

    private func promptZone(model: VentModel, tokens: ThemeTokens) -> some View {
        VStack(spacing: 10) {
            // The one contextual smart prompt (typed selection, §8.4).
            Button {
                draft = ""
            } label: {
                Text(model.smartPrompt.text)
                    .font(KeptFont.ui(14))
                    .foregroundStyle(tokens.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: ThemeTokens.radiusCard)
                            .fill(tokens.card.opacity(tokens.cardOpacity))
                    )
            }
            FlowLayout(spacing: 8) {
                ForEach(VentCopy.templateChips, id: \.self) { chip in
                    Button {
                        draft = String(chip.dropFirst(2)) // pre-fill without the emoji
                    } label: {
                        Text(chip)
                            .font(KeptFont.ui(13))
                            .foregroundStyle(tokens.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(tokens.card.opacity(tokens.cardOpacity * 0.8)))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func itemView(_ item: VentModel.SessionItem, model: VentModel, tokens: ThemeTokens) -> some View {
        switch item {
        case .userText(let id, let text):
            ChatBubbleView(bubble: DraftBubble(id: id, author: .user, text: text))
        case .filing:
            HStack {
                Text(VentCopy.filing)
                    .font(KeptFont.ui(13))
                    .foregroundStyle(tokens.inkSoft)
                Spacer()
            }
        case .confirmation(_, let line, let chips):
            VStack(alignment: .leading, spacing: 10) {
                Text(line)
                    .font(KeptFont.ui(14))
                    .foregroundStyle(tokens.ink)
                if !chips.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(chips, id: \.chapterId) { chip in
                            Button {
                                // The one navigation door (C8): the chip IS a deep link.
                                router.isTellPomPresented = false
                                router.open(deepLink: URL(string: "kept://chapter/\(chip.chapterId.uuidString)")!)
                            } label: {
                                HStack(spacing: 6) {
                                    PinIcon(iconRef: chip.iconRef, tokens: tokens)
                                    Text(chip.title)
                                        .font(KeptFont.ui(13))
                                        .foregroundStyle(tokens.ink)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(tokens.mint.opacity(0.25)))
                            }
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ThemeTokens.radiusCard)
                    .fill(tokens.card.opacity(tokens.cardOpacity))
            )
        case .question(let id, let prompt, let options):
            VStack(alignment: .leading, spacing: 10) {
                Text(prompt)
                    .font(KeptFont.ui(14))
                    .foregroundStyle(tokens.ink)
                FlowLayout(spacing: 8) {
                    ForEach(options, id: \.label) { option in
                        Button {
                            Task { await model.resolveQuestion(batchId: id, resolution: option.resolution) }
                        } label: {
                            Text(option.label)
                                .font(KeptFont.ui(13))
                                .foregroundStyle(tokens.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(tokens.lilac.opacity(0.25)))
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ThemeTokens.radiusCard)
                    .fill(tokens.card.opacity(tokens.cardOpacity))
            )
        case .keptLagged:
            Text(VentCopy.keptLagged)
                .font(KeptFont.ui(13))
                .foregroundStyle(tokens.inkSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func composer(tokens: ThemeTokens) -> some View {
        HStack(spacing: 10) {
            TextField(VentCopy.composerPlaceholder, text: composerBinding, axis: .vertical)
                .font(KeptFont.ui(15))
                .foregroundStyle(tokens.ink)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: ThemeTokens.radiusSmall)
                        .fill(tokens.card.opacity(tokens.cardOpacity))
                )
            if model?.micAvailable == true {
                micButton(tokens: tokens)
            }
            sendButton(tokens: tokens)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    /// While capturing, the composer mirrors the live partial transcript (editable on release).
    private var composerBinding: Binding<String> {
        Binding(
            get: { (model?.isCapturing == true) ? (model?.captureText ?? "") : draft },
            set: { draft = $0 }
        )
    }

    /// Hold-to-talk (§4): press = capture, release = transcript into the composer. Never auto-sends.
    private func micButton(tokens: ThemeTokens) -> some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 18))
            .foregroundStyle(model?.isCapturing == true ? tokens.rose : tokens.ink)
            .frame(width: 46, height: 46)
            .background(Circle().fill(tokens.gold.opacity(model?.isCapturing == true ? 0.55 : 0.35)))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if model?.isCapturing != true {
                            Task { await model?.beginHold() }
                        }
                    }
                    .onEnded { _ in
                        Task {
                            await model?.endHold()
                            draft = model?.captureText ?? draft
                        }
                    }
            )
            .accessibilityLabel("Hold to talk")
    }

    private func sendButton(tokens: ThemeTokens) -> some View {
        Button {
            let text = draft
            draft = ""
            Task { await model?.send(text) }
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(
                    draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? tokens.inkSoft.opacity(0.5) : tokens.gold
                )
        }
        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model?.isFiling == true)
        .accessibilityLabel("Send")
    }
}

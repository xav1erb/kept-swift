import SwiftUI

/// Chapter detail (M4): header + 💬 Chat / 🧵 Timeline. `Route.chapter(id)` lands here (C8);
/// every screen state ships (NN#6).
struct ChapterDetailView: View {
    let chapterId: UUID

    @Environment(KeptStore.self) private var store
    @Environment(AppClients.self) private var clients
    @Environment(ThemeModel.self) private var themeModel

    @State private var model: ChapterDetailModel?
    @State private var tab: DetailTab = .chat

    enum DetailTab: String, CaseIterable {
        case chat = "💬 Chat"
        case timeline = "🧵 Timeline"
    }

    var body: some View {
        let tokens = themeModel.tokens
        Group {
            if let model {
                switch model.state {
                case .loading:
                    ProgressView().tint(tokens.inkSoft)
                case .failed:
                    errorCard(tokens: tokens, model: model)
                case .ready:
                    content(model: model, tokens: tokens)
                }
            } else {
                ProgressView().tint(tokens.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tokens.backgroundGradient.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if model == nil {
                model = ChapterDetailModel(
                    chapterId: chapterId, store: store,
                    chat: clients.chat, extraction: clients.extraction
                )
            }
            model?.refresh()
        }
    }

    @ViewBuilder
    private func content(model: ChapterDetailModel, tokens: ThemeTokens) -> some View {
        VStack(spacing: 0) {
            header(model: model, tokens: tokens)
            tabPicker(tokens: tokens)
            switch tab {
            case .chat:
                ChapterChatTab(model: model)
            case .timeline:
                ChapterTimelineTab(model: model)
            }
        }
    }

    private func header(model: ChapterDetailModel, tokens: ThemeTokens) -> some View {
        HStack(spacing: 10) {
            BackButton()
            if let summary = model.summary {
                PinIcon(iconRef: summary.iconRef, tokens: tokens)
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.title)
                        .font(KeptFont.display(19))
                        .foregroundStyle(tokens.ink)
                        .lineLimit(1)
                    Text(model.headerStatus())
                        .font(KeptFont.ui(11))
                        .foregroundStyle(tokens.inkSoft)
                        .lineLimit(1)
                }
                Spacer()
                Text(ChapterDetailCopy.weatherGlyph(for: summary.state))
                    .font(.system(size: 20))
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private func tabPicker(tokens: ThemeTokens) -> some View {
        HStack(spacing: 8) {
            ForEach(DetailTab.allCases, id: \.rawValue) { candidate in
                Button {
                    tab = candidate
                } label: {
                    Text(candidate.rawValue)
                        .font(KeptFont.ui(13))
                        .foregroundStyle(tab == candidate ? tokens.ink : tokens.inkSoft)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(tab == candidate ? tokens.card.opacity(tokens.cardOpacity) : .clear)
                        )
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private func errorCard(tokens: ThemeTokens, model: ChapterDetailModel) -> some View {
        VStack(spacing: 12) {
            Text(ChapterDetailCopy.loadError)
                .font(KeptFont.ui(15))
                .foregroundStyle(tokens.inkSoft)
                .multilineTextAlignment(.center)
            Button("Try again") { model.refresh() }
                .font(KeptFont.ui(15))
                .foregroundStyle(tokens.ink)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: ThemeTokens.radiusCard)
                .fill(tokens.card.opacity(tokens.cardOpacity))
        )
        .padding(32)
    }
}

/// Plain back chevron — the shell hides the system bar so the header owns the top line.
private struct BackButton: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeModel.self) private var themeModel

    var body: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(themeModel.tokens.ink)
                .frame(width: 36, height: 36)
        }
        .accessibilityLabel("Back")
    }
}

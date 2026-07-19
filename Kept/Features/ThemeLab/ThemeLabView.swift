import SwiftUI

/// The M0 theming-engine proof (acceptance: selecting a theme re-skins this screen — and the
/// whole shell around it — live). Lives on the You tab for now; the real profile replaces it
/// at M7, and the onboarding theme picker (M2) reuses the same engine.
struct ThemeLabView: View {
    @Environment(ThemeModel.self) private var themeModel
    @Environment(KeptStore.self) private var store

    var body: some View {
        let tokens = themeModel.tokens
        ScrollView {
            VStack(spacing: 20) {
                Text("Theme Lab")
                    .font(KeptFont.display(28))
                    .foregroundStyle(tokens.ink)
                    .padding(.top, 24)

                themePicker
                sampleCard
                moodDots

                Text(themeModel.theme.palette.isStub
                     ? "STUB palette — designer values land with F7"
                     : "Cloud Cream — whitepaper §2.2 values")
                    .font(KeptFont.ui(12))
                    .foregroundStyle(tokens.inkSoft)

                SealedFooter()
                    .padding(.bottom, 110)
            }
        }
        .scrollIndicators(.hidden)
    }

    private var themePicker: some View {
        let tokens = themeModel.tokens
        return VStack(spacing: 8) {
            ForEach(Array(chunked(Theme.allCases, into: 3)), id: \.first!.id) { row in
                HStack(spacing: 8) {
                    ForEach(row) { theme in
                        swatch(for: theme)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: ThemeTokens.radiusCard)
                .fill(tokens.card.opacity(tokens.cardOpacity))
        )
        .padding(.horizontal, 20)
    }

    private func swatch(for theme: Theme) -> some View {
        let tokens = themeModel.tokens
        let palette = theme.palette
        let isSelected = themeModel.theme == theme
        return Button {
            themeModel.theme = theme               // the live re-skin
            try? store.setTheme(theme)             // persisted preference (typed command, C7)
        } label: {
            VStack(spacing: 6) {
                LinearGradient(
                    colors: [Color(hex: palette.backgroundTop), Color(hex: palette.backgroundBottom)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? tokens.gold : .clear, lineWidth: 2)
                )
                Text(theme.displayName)
                    .font(KeptFont.ui(10))
                    .foregroundStyle(tokens.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var sampleCard: some View {
        let tokens = themeModel.tokens
        return VStack(alignment: .leading, spacing: 10) {
            Text("A kept moment")
                .font(KeptFont.display(20))
                .foregroundStyle(tokens.ink)
            Text("Fraunces for display, Quicksand for UI — both bundled. Cards sit at 85% over the gradient with a soft lilac shadow.")
                .font(KeptFont.ui(14))
                .foregroundStyle(tokens.inkSoft)
            HStack(spacing: 8) {
                chip("bright", tokens.mint)
                chip("gold", tokens.gold)
                chip("storm", tokens.rose)
                chip("soft", tokens.lilac)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ThemeTokens.radiusCard)
                .fill(tokens.card.opacity(tokens.cardOpacity))
                .shadow(color: tokens.lilac.opacity(0.25), radius: 12, y: 4)
        )
        .padding(.horizontal, 20)
    }

    private var moodDots: some View {
        let tokens = themeModel.tokens
        return HStack(spacing: 14) {
            ForEach(ChapterState.allCases, id: \.self) { state in
                VStack(spacing: 4) {
                    Circle()
                        .fill(tokens.color(for: state))
                        .frame(width: 14, height: 14)
                    Text(state.rawValue)
                        .font(KeptFont.ui(10))
                        .foregroundStyle(tokens.inkSoft)
                }
            }
        }
    }

    private func chip(_ label: String, _ color: Color) -> some View {
        Text(label)
            .font(KeptFont.ui(12))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.35)))
            .foregroundStyle(themeModel.tokens.ink)
    }

    private func chunked(_ items: [Theme], into size: Int) -> [[Theme]] {
        stride(from: 0, to: items.count, by: size).map {
            Array(items[$0..<min($0 + size, items.count)])
        }
    }
}

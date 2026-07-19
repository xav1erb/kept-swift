import SwiftUI

/// Every surface state a screen must ship (NN#6). M0 placeholders default to a soft empty
/// state — an empty world is never a blank page.
enum SurfaceState: Equatable {
    case loading
    case empty(message: String)
    case error(message: String)
}

struct SurfacePlaceholder: View {
    @Environment(ThemeModel.self) private var themeModel

    let title: String
    let state: SurfaceState

    var body: some View {
        let tokens = themeModel.tokens
        VStack(spacing: 0) {
            Text(title)
                .font(KeptFont.display(28))
                .foregroundStyle(tokens.ink)
                .padding(.top, 24)

            Spacer()

            switch state {
            case .loading:
                ProgressView()
                    .tint(tokens.inkSoft)
                Text("one moment…")
                    .font(KeptFont.ui(15))
                    .foregroundStyle(tokens.inkSoft)
                    .padding(.top, 12)
            case .empty(let message):
                VStack(spacing: 10) {
                    Circle()
                        .strokeBorder(tokens.inkSoft.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                        .frame(width: 72, height: 72)
                    Text(message)
                        .font(KeptFont.ui(15))
                        .foregroundStyle(tokens.inkSoft)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: ThemeTokens.radiusCard)
                        .fill(tokens.card.opacity(tokens.cardOpacity))
                )
                .padding(.horizontal, 32)
            case .error(let message):
                VStack(spacing: 10) {
                    Image(systemName: "cloud.rain")
                        .font(.system(size: 32))
                        .foregroundStyle(tokens.rose)
                    Text(message)
                        .font(KeptFont.ui(15))
                        .foregroundStyle(tokens.ink)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: ThemeTokens.radiusCard)
                        .fill(tokens.card.opacity(tokens.cardOpacity))
                )
                .padding(.horizontal, 32)
            }

            Spacer()
            SealedFooter()
                .padding(.bottom, 96)   // clears the floating bar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The footer mark on every main surface (§2.2).
struct SealedFooter: View {
    @Environment(ThemeModel.self) private var themeModel

    var body: some View {
        Text("SEALED · KEPT ONLY FOR YOU")
            .font(KeptFont.ui(11))
            .kerning(1.2)
            .foregroundStyle(themeModel.tokens.inkSoft.opacity(0.8))
    }
}

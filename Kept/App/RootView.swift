import SwiftUI

/// The root gate. M0: app-lock state → lock screen or the shell. M2 adds the onboarding gate
/// (`!hasCompletedOnboarding`) in front of this.
struct RootView: View {
    @Environment(AppLockModel.self) private var appLock

    var body: some View {
        switch appLock.state {
        case .locked:
            LockScreenView()
        case .disabled, .unlocked:
            AppShellView()
        }
    }
}

struct LockScreenView: View {
    @Environment(AppLockModel.self) private var appLock
    @Environment(ThemeModel.self) private var themeModel

    var body: some View {
        let tokens = themeModel.tokens
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 40))
                .foregroundStyle(tokens.inkSoft)
            Text("Only your face opens your world.")
                .font(KeptFont.display(22))
                .foregroundStyle(tokens.ink)
                .multilineTextAlignment(.center)
            Button {
                Task { await appLock.unlock() }
            } label: {
                Text("Unlock 🔒")
                    .font(KeptFont.ui(17))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(tokens.card.opacity(tokens.cardOpacity))
                    .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.radiusSmall))
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tokens.backgroundGradient.ignoresSafeArea())
    }
}

#Preview {
    RootView()
        .environment(ThemeModel())
        .environment(Router())
        .environment(AppLockModel())
        .environment(try! KeptStore(configuration: .inMemory))
}

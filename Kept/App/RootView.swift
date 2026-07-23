import SwiftUI

/// The root gate (M2-CONTRACTS §2): `!hasCompletedOnboarding` → onboarding; else the M0
/// app-lock gate → lock screen or the shell.
struct RootView: View {
    @Environment(AppLockModel.self) private var appLock
    @Environment(KeptStore.self) private var store
    @Environment(OnboardingModel.self) private var onboarding

    private var needsOnboarding: Bool {
        // `isFinished` is the observable completion signal; the stored flag covers relaunches.
        !onboarding.isFinished && !(((try? store.userProfile())?.hasCompletedOnboarding) ?? false)
    }

    var body: some View {
        if needsOnboarding {
            OnboardingFlowView()
        } else {
            switch appLock.state {
            case .locked:
                LockScreenView()
            case .disabled, .unlocked:
                AppShellView()
            }
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

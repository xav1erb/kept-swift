import SwiftUI

// The onboarding container (M2-CONTRACTS §2): scaffold + progress segments from themePicker
// onward, step switching in the §8.1-amended order, F6 restricted landing. All copy verbatim
// from docs/onboarding.md (§13.11); structure + tokens only until F7 art lands.

struct OnboardingFlowView: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(ThemeModel.self) private var themeModel

    var body: some View {
        let tokens = themeModel.tokens
        VStack(spacing: 0) {
            if model.step.rawValue >= OnboardingStep.themePicker.rawValue, !model.restrictedStop {
                OnboardingProgressBar()
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }
            if model.restrictedStop {
                RestrictedLandingView()
            } else {
                stepView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.step)
        .background(tokens.backgroundGradient.ignoresSafeArea())
    }

    @ViewBuilder
    private var stepView: some View {
        switch model.step {
        case .splash: SplashView()
        case .meetPom: MeetPomView()
        case .themePicker: ThemePickerView()
        case .iconPicker: IconPickerView()
        case .aiConsent: AIConsentView()
        case .interview: InterviewView()
        case .privacyPledge: PrivacyPledgeView()
        case .faceID: FaceIDSetupView()
        case .signIn: OnboardingSignInView()
        case .worldGenerating: WorldGeneratingView()
        case .worldContents: WorldContentsView()
        case .reveal: RevealView()
        }
    }
}

struct OnboardingProgressBar: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(ThemeModel.self) private var themeModel

    /// One segment per step from themePicker on; the interview's fills fractionally (§0).
    private var segments: [Double] {
        let steps = OnboardingStep.allCases.filter { $0.rawValue >= OnboardingStep.themePicker.rawValue }
        return steps.map { step in
            if step.rawValue < model.step.rawValue { return 1.0 }
            if step == model.step {
                return step == .interview ? model.interview.progress : 0.5
            }
            return 0.0
        }
    }

    var body: some View {
        let tokens = themeModel.tokens
        HStack(spacing: 4) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, fill in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(tokens.inkSoft.opacity(0.2))
                        Capsule().fill(tokens.ink).frame(width: geo.size.width * fill)
                    }
                }
                .frame(height: 3)
            }
        }
        .accessibilityHidden(true)
    }
}

/// F6 under-13 soft landing (M2-CONTRACTS §6): warm, final, nothing retained.
struct RestrictedLandingView: View {
    @Environment(ThemeModel.self) private var themeModel

    var body: some View {
        let tokens = themeModel.tokens
        VStack(spacing: 16) {
            Text("🤍")
                .font(.system(size: 44))
            Text("Keeper is for 13 and up.")
                .font(KeptFont.display(24))
                .foregroundStyle(tokens.ink)
            Text("I hope we meet again when the time's right. Nothing you typed was kept.")
                .font(KeptFont.ui(16))
                .foregroundStyle(tokens.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

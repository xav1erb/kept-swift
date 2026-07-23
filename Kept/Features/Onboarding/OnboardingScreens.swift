import SwiftUI

// Screens 4.1–4.5 + 4.9 + 4.10 (docs/onboarding.md — copy verbatim, §13.11). Structure +
// tokens only until F7 art lands; Pom is a placeholder orb.

// MARK: - 4.1 Splash

struct SplashView: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(ThemeModel.self) private var themeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bobbing = false

    var body: some View {
        let tokens = themeModel.tokens
        VStack(spacing: 20) {
            Spacer()
            Text("🐣")
                .font(.system(size: 72))
                .offset(y: bobbing && !reduceMotion ? -8 : 0)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true),
                    value: bobbing
                )
                .onAppear { bobbing = true }
            Text("Keeper")
                .font(KeptFont.display(34))
                .foregroundStyle(tokens.ink)
            Text("a little world for your whole life, kept by someone who never forgets")
                .font(KeptFont.ui(17))
                .foregroundStyle(tokens.inkSoft)
                .multilineTextAlignment(.center)
            Text("Sealed · private · yours")
                .font(KeptFont.ui(14))
                .foregroundStyle(tokens.inkSoft)
            Spacer()
            OnboardingCTA(title: "Come in →") { model.advance() }
        }
        .padding(28)
    }
}

// MARK: - 4.2 Meet Pom + name

struct MeetPomView: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(ThemeModel.self) private var themeModel
    @State private var name = ""

    private static let bubbles = [
        "I'm so happy you're here :)",
        "Quick intro — I'm fully private. I keep everything you tell me, sealed, and I help you with any part of your life. The messy parts especially.",
        "I'm Pom :) Nice to virtually meet!",
        "And you are…?",
    ]

    var body: some View {
        let tokens = themeModel.tokens
        VStack(alignment: .leading, spacing: 0) {
            CadencedBubbles(texts: Self.bubbles)
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                TextField("your name (or a name you like)", text: $name)
                    .font(KeptFont.ui(17))
                    .padding(14)
                    .background(tokens.card.opacity(tokens.cardOpacity))
                    .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.radiusSmall))
                Text("only Pom ever sees this")
                    .font(KeptFont.ui(12))
                    .foregroundStyle(tokens.inkSoft)
            }
            HStack {
                Button("skip") { model.advance() }
                    .font(KeptFont.ui(15))
                    .foregroundStyle(tokens.inkSoft)
                Spacer()
                OnboardingCTA(title: "That's me ✓", compact: true) { model.setName(name) }
            }
            .padding(.top, 16)
        }
        .padding(24)
    }
}

// MARK: - 4.3 Theme picker (live re-skin REQUIRED — the M0 engine's proof)

struct ThemePickerView: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(ThemeModel.self) private var themeModel

    var body: some View {
        let tokens = themeModel.tokens
        VStack(spacing: 18) {
            Text("Pick your colors")
                .font(KeptFont.display(24))
                .foregroundStyle(tokens.ink)
            ThemePreviewCard()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], spacing: 10) {
                ForEach(Theme.allCases) { theme in
                    Button {
                        model.pickTheme(theme, themeModel: themeModel)
                    } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(theme.tokens.rose)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle().strokeBorder(
                                        themeModel.theme == theme ? tokens.ink : .clear, lineWidth: 2
                                    )
                                )
                            Text(theme.displayName)
                                .font(KeptFont.ui(12))
                                .foregroundStyle(tokens.ink)
                        }
                        .padding(8)
                    }
                }
            }
            Spacer()
            VStack(spacing: 6) {
                OnboardingCTA(title: "This one ✓") { model.advance() }
                Text("you can change it anytime")
                    .font(KeptFont.ui(12))
                    .foregroundStyle(tokens.inkSoft)
            }
        }
        .padding(24)
    }
}

/// The sample convo (verbatim) that re-skins instantly on selection.
struct ThemePreviewCard: View {
    @Environment(ThemeModel.self) private var themeModel

    var body: some View {
        let tokens = themeModel.tokens
        VStack(alignment: .leading, spacing: 8) {
            ChatBubbleView(bubble: DraftBubble(author: .user, text: "okay but how was the date??"))
            ChatBubbleView(bubble: DraftBubble(author: .pom, text: "POM. he brought flowers."))
            ChatBubbleView(bubble: DraftBubble(author: .user, text: "writing this in the story immediately 🌷"))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tokens.card.opacity(tokens.cardOpacity))
        .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.radiusLarge))
    }
}

// MARK: - 4.4 Icon picker

struct IconPickerView: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(ThemeModel.self) private var themeModel
    @State private var selected: IconOption = .pom
    @State private var applyFailed = false

    enum IconOption: String, CaseIterable, Identifiable {
        case pom, midnight, bloom, golden, fern, tide, notes, weather, utility
        var id: String { rawValue }

        /// nil = primary icon.
        var assetName: String? {
            switch self {
            case .pom: nil
            case .midnight: "IconMidnight"
            case .bloom: "IconBloom"
            case .golden: "IconGolden"
            case .fern: "IconFern"
            case .tide: "IconTide"
            case .notes: "IconNotes"
            case .weather: "IconWeather"
            case .utility: "IconUtility"
            }
        }

        var label: String {
            switch self {
            case .pom: "Pom"
            case .midnight: "Midnight"
            case .bloom: "Bloom"
            case .golden: "Golden"
            case .fern: "Fern"
            case .tide: "Tide"
            case .notes: "Notes"
            case .weather: "Weather"
            case .utility: "Utility"
            }
        }

        var swatch: Color {
            switch self {
            case .pom: Color(red: 0.96, green: 0.94, blue: 0.90)
            case .midnight: Color(red: 0.10, green: 0.11, blue: 0.18)
            case .bloom: Color(red: 0.96, green: 0.76, blue: 0.84)
            case .golden: Color(red: 0.91, green: 0.66, blue: 0.30)
            case .fern: Color(red: 0.29, green: 0.49, blue: 0.35)
            case .tide: Color(red: 0.24, green: 0.49, blue: 0.69)
            case .notes: Color(red: 0.97, green: 0.84, blue: 0.45)
            case .weather: Color(red: 0.29, green: 0.56, blue: 0.85)
            case .utility: Color(red: 0.56, green: 0.56, blue: 0.58)
            }
        }
    }

    var body: some View {
        let tokens = themeModel.tokens
        VStack(spacing: 18) {
            Text("Pick your icon — we keep things discreet here.")
                .font(KeptFont.display(22))
                .foregroundStyle(tokens.ink)
                .multilineTextAlignment(.center)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 14) {
                ForEach(IconOption.allCases) { option in
                    Button { selected = option } label: {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(option.swatch)
                                .frame(width: 56, height: 56)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14).strokeBorder(
                                        selected == option ? tokens.ink : .clear, lineWidth: 2
                                    )
                                )
                            Text(option.label)
                                .font(KeptFont.ui(12))
                                .foregroundStyle(tokens.ink)
                        }
                    }
                }
            }
            Text("The last three are disguises — the app shows up looking like a boring tool. Your world, hidden in plain sight.")
                .font(KeptFont.ui(13))
                .foregroundStyle(tokens.inkSoft)
                .multilineTextAlignment(.center)
            if applyFailed {
                Text("Couldn't switch the icon just now — keeping the default. You can retry from settings later.")
                    .font(KeptFont.ui(12))
                    .foregroundStyle(tokens.inkSoft)
            }
            Spacer()
            OnboardingCTA(title: "Confirm icon ✓") {
                Task { await model.confirmIcon(selected.assetName) }
            }
        }
        .padding(24)
    }
}

// MARK: - 4.5 Private-AI consent (LEGAL GATE)

struct AIConsentView: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(ThemeModel.self) private var themeModel
    @State private var agreed = false
    @State private var showingPolicy = false

    private static let claims = [
        "processed only to power your world",
        "never used to train AI models",
        "never sold / advertised on",
        "deletable always (including from AI processing)",
    ]

    var body: some View {
        let tokens = themeModel.tokens
        VStack(alignment: .leading, spacing: 18) {
            Text("One honest thing before we build.")
                .font(KeptFont.display(24))
                .foregroundStyle(tokens.ink)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Self.claims, id: \.self) { claim in
                    HStack(alignment: .top, spacing: 10) {
                        Text("·").font(KeptFont.display(17))
                        Text(claim).font(KeptFont.ui(16))
                    }
                    .foregroundStyle(tokens.ink)
                }
            }
            .padding(16)
            .background(tokens.card.opacity(tokens.cardOpacity))
            .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.radiusLarge))
            Toggle(isOn: $agreed) {
                Text("I understand and agree to the Privacy Policy and Terms.")
                    .font(KeptFont.ui(15))
                    .foregroundStyle(tokens.ink)
            }
            .toggleStyle(CheckboxToggleStyle())
            Button("Privacy Policy & Terms") { showingPolicy = true }
                .font(KeptFont.ui(13))
                .foregroundStyle(tokens.inkSoft)
            Spacer()
            OnboardingCTA(title: "Confirm & start building →", disabled: !agreed) {
                model.confirmConsent()
            }
        }
        .padding(24)
        .sheet(isPresented: $showingPolicy) { PolicySheet() }
    }
}

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                configuration.label
            }
        }
        .buttonStyle(.plain)
    }
}

struct PolicySheet: View {
    var body: some View {
        ScrollView {
            Text("Privacy Policy & Terms\n\nPlaceholder — the in-binary policy text lands with the F5 naming pass, before any store build.")
                .font(KeptFont.ui(15))
                .padding(24)
        }
    }
}

// MARK: - 4.9 Privacy pledge

struct PrivacyPledgeView: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(ThemeModel.self) private var themeModel

    private static let vows = [
        "encrypted",
        "never trained on, sold, or seen",
        "lives with you, behind your key",
        "erase-my-world = gone means gone",
    ]

    var body: some View {
        let tokens = themeModel.tokens
        VStack(spacing: 18) {
            Text("🔏")
                .font(.system(size: 56))
            Text("Now, the promise I made you — you just shared a real part of your life with me. I don't take that lightly. So, on the record:")
                .font(KeptFont.ui(17))
                .foregroundStyle(tokens.ink)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Self.vows, id: \.self) { vow in
                    HStack(spacing: 10) {
                        Text("·").font(KeptFont.display(17))
                        Text(vow).font(KeptFont.ui(16))
                    }
                    .foregroundStyle(tokens.ink)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tokens.card.opacity(tokens.cardOpacity))
            .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.radiusLarge))
            Spacer()
            OnboardingCTA(title: "Sealed. 🤍") { model.advance() }
        }
        .padding(24)
    }
}

// MARK: - 4.10 Face ID

struct FaceIDSetupView: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(ThemeModel.self) private var themeModel
    @Environment(AppLockModel.self) private var appLock

    var body: some View {
        let tokens = themeModel.tokens
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "faceid")
                .font(.system(size: 64))
                .foregroundStyle(tokens.ink)
            Text("Only your face opens your world.")
                .font(KeptFont.display(24))
                .foregroundStyle(tokens.ink)
                .multilineTextAlignment(.center)
            Spacer()
            OnboardingCTA(title: "Lock with Face ID 🔒") {
                appLock.setEnabled(true)
                model.advance()
            }
            Button("not needed") { model.advance() }
                .font(KeptFont.ui(15))
                .foregroundStyle(tokens.inkSoft)
        }
        .padding(24)
    }
}

// MARK: - Shared pieces

struct OnboardingCTA: View {
    @Environment(ThemeModel.self) private var themeModel
    let title: String
    var compact: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        let tokens = themeModel.tokens
        Button(action: action) {
            Text(title)
                .font(KeptFont.ui(17))
                .foregroundStyle(tokens.ink)
                .padding(.horizontal, compact ? 20 : 28)
                .padding(.vertical, 14)
                .frame(maxWidth: compact ? nil : .infinity)
                .background(tokens.card.opacity(tokens.cardOpacity))
                .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.radiusSmall))
        }
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }
}

/// Pom bubbles appearing with typing cadence (short delay per bubble; Reduce Motion → instant).
struct CadencedBubbles: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let texts: [String]
    @State private var shown = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(texts.prefix(shown).enumerated()), id: \.offset) { _, text in
                ChatBubbleView(bubble: DraftBubble(author: .pom, text: text))
            }
        }
        .task {
            if reduceMotion {
                shown = texts.count
                return
            }
            for index in texts.indices {
                try? await Task.sleep(for: .milliseconds(index == 0 ? 150 : 650))
                withAnimation(.easeOut(duration: 0.2)) { shown = index + 1 }
            }
        }
    }
}

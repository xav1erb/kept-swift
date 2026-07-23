import SwiftUI

// 4.7 world generating (post-sign-in per §8.1 — the flush IS the dwell), 4.8 world contents,
// 4.12 reveal. The generating checklist narrates REAL store state (C4: typed code, never model
// text, no fake progress). Disambiguation questions surface here, pre-reveal (C4 gate).

struct WorldGeneratingView: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(ThemeModel.self) private var themeModel

    var body: some View {
        let tokens = themeModel.tokens
        VStack(spacing: 20) {
            Spacer()
            Text("🌍")
                .font(.system(size: 64))
            Text("Pom is generating your world…")
                .font(KeptFont.display(22))
                .foregroundStyle(tokens.ink)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.generatingLines, id: \.self) { line in
                    Text(line)
                        .font(KeptFont.ui(15))
                        .foregroundStyle(tokens.inkSoft)
                }
                if model.generatingLines.isEmpty {
                    Text("✦ opening the first page…")
                        .font(KeptFont.ui(15))
                        .foregroundStyle(tokens.inkSoft)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(tokens.card.opacity(tokens.cardOpacity))
            .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.radiusLarge))
            if case .partial(let failedCount) = model.generatingPhase, failedCount > 0 {
                Text("A few things didn't file yet — I'm keeping them safe and will retry.")
                    .font(KeptFont.ui(13))
                    .foregroundStyle(tokens.inkSoft)
            }
            if model.generatingPhase == .askingQuestions, let question = model.pendingQuestions.first {
                DisambiguationCard(question: question)
            }
            Spacer()
        }
        .padding(24)
    }
}

/// The C4 gate in Pom's voice: held deltas apply only after the user answers.
struct DisambiguationCard: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(ThemeModel.self) private var themeModel
    let question: PendingDisambiguation

    var body: some View {
        let tokens = themeModel.tokens
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick question before I finish building —")
                .font(KeptFont.ui(14))
                .foregroundStyle(tokens.inkSoft)
            Text(question.question)
                .font(KeptFont.ui(16))
                .foregroundStyle(tokens.ink)
            ForEach(question.candidateIds, id: \.self) { candidateId in
                Button {
                    Task { await model.resolveQuestion(question, resolution: .existing(candidateId)) }
                } label: {
                    Text(model.candidateName(candidateId))
                        .font(KeptFont.ui(15))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(tokens.card.opacity(tokens.cardOpacity))
                        .clipShape(Capsule())
                }
            }
            Button {
                Task { await model.resolveQuestion(question, resolution: .newPerson) }
            } label: {
                Text("Someone new")
                    .font(KeptFont.ui(15))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(tokens.rose.opacity(0.35))
                    .clipShape(Capsule())
            }
        }
        .padding(16)
        .background(tokens.card.opacity(tokens.cardOpacity))
        .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.radiusLarge))
    }
}

// MARK: - 4.8 World contents

struct WorldContentsView: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(ThemeModel.self) private var themeModel
    @Environment(KeptStore.self) private var store

    private var builtTypes: [ChapterType] {
        (try? store.chapterSummaries())?.map(\.type) ?? []
    }

    /// Toggle rows: non-sensitive, unbuilt types. Sensitive rooms are never offered — they are
    /// user-opened only (C3).
    private var offerableTypes: [ChapterType] {
        ChapterType.allCases.filter { !$0.isSensitive && !builtTypes.contains($0) }
    }

    var body: some View {
        let tokens = themeModel.tokens
        VStack(alignment: .leading, spacing: 16) {
            Text("What should your world include?")
                .font(KeptFont.display(22))
                .foregroundStyle(tokens.ink)
            Text("don't worry, rooms can always be added or removed later.")
                .font(KeptFont.ui(14))
                .foregroundStyle(tokens.inkSoft)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(builtTypes, id: \.self) { type in
                        HStack {
                            Text(Self.label(for: type))
                                .font(KeptFont.ui(16))
                                .foregroundStyle(tokens.ink)
                            Spacer()
                            Text("COMPLETED")
                                .font(KeptFont.ui(11))
                                .foregroundStyle(tokens.mint)
                        }
                        .padding(14)
                        .background(tokens.card.opacity(tokens.cardOpacity))
                        .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.radiusSmall))
                    }
                    ForEach(offerableTypes, id: \.self) { type in
                        Button {
                            if model.selectedTypes.contains(type) {
                                model.selectedTypes.remove(type)
                            } else {
                                model.selectedTypes.insert(type)
                            }
                        } label: {
                            HStack {
                                Text(Self.label(for: type))
                                    .font(KeptFont.ui(16))
                                    .foregroundStyle(tokens.ink)
                                Spacer()
                                Image(systemName: model.selectedTypes.contains(type) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(tokens.ink)
                            }
                            .padding(14)
                            .background(tokens.card.opacity(tokens.cardOpacity * 0.7))
                            .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.radiusSmall))
                        }
                    }
                }
            }
            OnboardingCTA(title: "Confirm my world ✓") { model.confirmWorldContents() }
        }
        .padding(24)
        .onAppear {
            if model.selectedTypes.isEmpty {
                model.selectedTypes = Set(offerableTypes)
            }
        }
    }

    static func label(for type: ChapterType) -> String {
        switch type {
        case .relationship: "Relationship"
        case .family: "Family"
        case .friendship: "Friends"
        case .work: "Work & school"
        case .health: "Health"
        case .money: "Money"
        case .passion: "Passions"
        case .growth: "Growth"
        case .privateCorner: "Private corner"
        case .grief: "Grief & letting go"
        }
    }
}

// MARK: - 4.12 Reveal

struct RevealView: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(ThemeModel.self) private var themeModel
    @Environment(KeptStore.self) private var store

    private var userName: String {
        let name = (try? store.userProfile())?.name ?? ""
        return name.isEmpty ? "friend" : name
    }

    var body: some View {
        let tokens = themeModel.tokens
        VStack(spacing: 20) {
            Spacer()
            Text("🌍")
                .font(.system(size: 72))
            Text("\(userName)… welcome to your world. One room is lit. The rest, we'll light together.")
                .font(KeptFont.display(22))
                .foregroundStyle(tokens.ink)
                .multilineTextAlignment(.center)
            Spacer()
            if model.revealRoutesToPrep {
                OnboardingCTA(title: "Get me ready for tonight →") { model.finishOnboarding() }
            } else {
                OnboardingCTA(title: "Step inside ✨") { model.finishOnboarding() }
            }
        }
        .padding(24)
    }
}

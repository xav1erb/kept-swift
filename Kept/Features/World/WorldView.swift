import SwiftUI

// The World home surface (M3-CONTRACTS §4): top row · the GlobeKit orbit · dashed new-chapter
// row · Next up card · recent chapter cards · state-reactive greeting. Every tap deep-links
// through the Router (C8). Loading/empty/error all ship (NN#6) — an empty world is never a
// blank page.

struct WorldView: View {
    @Environment(KeptStore.self) private var store
    @Environment(ThemeModel.self) private var themeModel
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var model: WorldModel?

    var body: some View {
        let tokens = themeModel.tokens
        ScrollView {
            VStack(spacing: 20) {
                if let model {
                    topRow(model: model, tokens: tokens)
                    switch model.loadState {
                    case .loading:
                        globeSkeleton(tokens: tokens)
                    case .failed:
                        errorCard(model: model, tokens: tokens)
                    case .ready:
                        greetingRow(model: model, tokens: tokens)
                        GlobeOrbitView(model: model, reduceMotion: reduceMotion)
                        newChapterRow(tokens: tokens)
                        if let nextUp = model.nextUp {
                            nextUpCard(nextUp, tokens: tokens)
                        }
                        recentRow(model: model, tokens: tokens)
                    }
                } else {
                    globeSkeleton(tokens: tokens)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 110)  // clears the floating tab bar
        }
        .onAppear(perform: refresh)  // also fires on NavigationStack pop-back → pins update live
        .onChange(of: themeModel.theme) { refresh() }  // re-skin rings on theme switch
    }

    private func refresh() {
        if model == nil { model = WorldModel(store: store) }
        model?.refresh(tokens: themeModel.tokens)
    }

    // MARK: - Top row (＋ · title · 🔥 streak)

    private func topRow(model: WorldModel, tokens: ThemeTokens) -> some View {
        HStack(alignment: .top) {
            Button {
                router.path.append(.newChapter)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tokens.ink)
                    .frame(width: 38, height: 38)
                    .background(tokens.card.opacity(tokens.cardOpacity))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Start a new chapter")
            Spacer()
            VStack(spacing: 2) {
                Text("\(model.userName.isEmpty ? "your" : "\(model.userName)'s") world ✨")
                    .font(KeptFont.display(22))
                    .foregroundStyle(tokens.ink)
                Text(WorldCopy.subtitle)
                    .font(KeptFont.ui(13))
                    .foregroundStyle(tokens.inkSoft)
            }
            Spacer()
            Button {
                router.path.append(.streak)
            } label: {
                Text("🔥 \(model.streakCount)")
                    .font(KeptFont.ui(15))
                    .foregroundStyle(tokens.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(tokens.card.opacity(tokens.cardOpacity))
                    .clipShape(Capsule())
            }
            .accessibilityLabel("Streak: \(model.streakCount) days")
        }
    }

    private func greetingRow(model: WorldModel, tokens: ThemeTokens) -> some View {
        HStack(spacing: 10) {
            PomFace(pose: model.pose, tokens: tokens)
            Text(model.greeting)
                .font(KeptFont.ui(15))
                .foregroundStyle(tokens.inkSoft)
            Spacer()
        }
    }

    // MARK: - Rows below the globe

    private func newChapterRow(tokens: ThemeTokens) -> some View {
        Button {
            router.path.append(.newChapter)
        } label: {
            HStack {
                Spacer()
                Text(WorldCopy.newChapterRow)
                    .font(KeptFont.ui(15))
                    .foregroundStyle(tokens.inkSoft)
                Spacer()
            }
            .padding(.vertical, 14)
            .overlay(
                RoundedRectangle(cornerRadius: ThemeTokens.radiusSmall)
                    .strokeBorder(tokens.inkSoft.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            )
        }
    }

    private func nextUpCard(_ nextUp: NextUpCard, tokens: ThemeTokens) -> some View {
        Button {
            router.path.append(.chapter(nextUp.chapterId))
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(WorldCopy.nextUpHeader) · \(nextUp.relativeDay)")
                    .font(KeptFont.ui(12))
                    .foregroundStyle(tokens.inkSoft)
                    .textCase(.uppercase)
                Text(nextUp.eventTitle)
                    .font(KeptFont.display(18))
                    .foregroundStyle(tokens.ink)
                Text(nextUp.chapterTitle)
                    .font(KeptFont.ui(13))
                    .foregroundStyle(tokens.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(tokens.card.opacity(tokens.cardOpacity))
            .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.radiusCard))
        }
    }

    @ViewBuilder
    private func recentRow(model: WorldModel, tokens: ThemeTokens) -> some View {
        if !model.recentChapters.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(model.recentChapters) { chapter in
                        Button {
                            router.path.append(.chapter(chapter.id))
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(chapter.title)
                                    .font(KeptFont.ui(14))
                                    .foregroundStyle(tokens.ink)
                                    .lineLimit(1)
                                Text(AwarenessGrade.grade(for: chapter.awarenessPct).subline(pct: chapter.awarenessPct))
                                    .font(KeptFont.ui(11))
                                    .foregroundStyle(tokens.inkSoft)
                            }
                            .padding(12)
                            .frame(width: 150, alignment: .leading)
                            .background(tokens.card.opacity(tokens.cardOpacity))
                            .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.radiusSmall))
                            .overlay(alignment: .topTrailing) {
                                Circle()
                                    .fill(chapter.state.accentColor(tokens))
                                    .frame(width: 8, height: 8)
                                    .padding(10)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Loading / error (NN#6)

    private func globeSkeleton(tokens: ThemeTokens) -> some View {
        Circle()
            .fill(tokens.card.opacity(tokens.cardOpacity * 0.6))
            .frame(width: 220, height: 220)
            .padding(.vertical, 40)
            .accessibilityLabel("Your world is loading")
    }

    private func errorCard(model: WorldModel, tokens: ThemeTokens) -> some View {
        VStack(spacing: 12) {
            Text(WorldCopy.loadError)
                .font(KeptFont.ui(15))
                .foregroundStyle(tokens.ink)
                .multilineTextAlignment(.center)
            Button("Try again") { refresh() }
                .font(KeptFont.ui(15))
                .foregroundStyle(tokens.ink)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(tokens.card.opacity(tokens.cardOpacity))
                .clipShape(Capsule())
        }
        .padding(.vertical, 60)
    }
}

/// Placeholder Pom face (F7: real art later) — the pose is typed, the drawing is a stand-in.
struct PomFace: View {
    let pose: PomPose
    let tokens: ThemeTokens

    var body: some View {
        ZStack {
            Circle()
                .fill(tokens.gold.opacity(0.85))
                .frame(width: 40, height: 40)
            Text(eyes)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tokens.ink.opacity(0.8))
        }
        .accessibilityHidden(true)
    }

    private var eyes: String {
        switch pose {
        case .alert: "• •"
        case .cozy: "◠ ◠"
        case .sleepy: "– –"
        }
    }
}

// MARK: - The orbit (GlobeKit host)

/// Hosts GlobeKit: maps WorldPins → layouts each frame, drives idle spin/momentum via
/// TimelineView, renders pins as SwiftUI views (GlobeKit places, the host draws — §2).
struct GlobeOrbitView: View {
    @Environment(ThemeModel.self) private var themeModel
    @Environment(Router.self) private var router

    let model: WorldModel
    let reduceMotion: Bool

    @State private var lastDragX: CGFloat = 0
    @State private var lastTick: Date?

    private let config = GlobeConfig()

    var body: some View {
        let tokens = themeModel.tokens
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            orbit(tokens: tokens)
                .onChange(of: timeline.date) { _, date in
                    let dt = lastTick.map { date.timeIntervalSince($0) } ?? 0
                    lastTick = date
                    model.globe.tick(dt: min(dt, 0.1), config: config, idle: !reduceMotion)
                }
        }
        .frame(height: 320)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    model.globe.drag(deltaX: value.translation.width - lastDragX, config: config)
                    lastDragX = value.translation.width
                }
                .onEnded { _ in
                    lastDragX = 0
                    model.globe.settle()
                }
        )
    }

    @ViewBuilder
    private func orbit(tokens: ThemeTokens) -> some View {
        let layouts = model.globe.layout(pins: model.pins.map(\.pin), config: config)
        ZStack {
            // The little world itself — placeholder gradient sphere until F7 art.
            Circle()
                .fill(
                    LinearGradient(
                        colors: [tokens.mint.opacity(0.55), tokens.blue.opacity(0.45)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: 170, height: 170)
                .zIndex(0)

            if model.pins.isEmpty {
                Text(WorldCopy.emptyWorld)
                    .font(KeptFont.ui(14))
                    .foregroundStyle(tokens.inkSoft)
                    .offset(y: 120)
                    .zIndex(1)
            }

            // layouts[i] corresponds to model.pins[i] — layout() maps in order.
            ForEach(Array(zip(model.pins, layouts)), id: \.0.id) { worldPin, layout in
                GlobePinView(worldPin: worldPin, layout: layout, tokens: tokens, reduceMotion: reduceMotion)
                    .offset(x: layout.xOffset, y: yJitter(for: worldPin.id))
                    .zIndex(layout.zIndex)
                    .allowsHitTesting(!layout.isBehind)
                    .onTapGesture {
                        router.path.append(.chapter(worldPin.id))
                    }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Small deterministic vertical spread so pins don't sit on one line (id-derived, stable).
    private func yJitter(for id: UUID) -> CGFloat {
        let seed = id.uuidString.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        return CGFloat((abs(seed) % 90)) - 45
    }
}

struct GlobePinView: View {
    let worldPin: WorldPin
    let layout: PinLayout
    let tokens: ThemeTokens
    let reduceMotion: Bool

    @State private var breathing = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(tokens.inkSoft.opacity(0.25), lineWidth: 3)
                    .frame(width: 54, height: 54)
                Circle()
                    .trim(from: 0, to: CGFloat(worldPin.pin.awarenessPct) / 100)
                    .stroke(worldPin.pin.ringColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 54, height: 54)
                PinIcon(iconRef: worldPin.pin.iconRef, tokens: tokens)
            }
            Text(worldPin.title)
                .font(KeptFont.ui(12))
                .foregroundStyle(tokens.ink)
                .lineLimit(1)
                .frame(maxWidth: 110)
            Text(worldPin.pin.sublineText)
                .font(KeptFont.ui(10))
                .foregroundStyle(tokens.inkSoft)
            if let status = worldPin.pin.statusLine {
                Text(status)
                    .font(KeptFont.ui(10))
                    .foregroundStyle(tokens.ink)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tokens.rose.opacity(0.3))
                    .clipShape(Capsule())
                    .scaleEffect(breathing ? 1.06 : 1.0)
                    .frame(maxWidth: 130)
            }
        }
        .scaleEffect(layout.scale)
        .opacity(worldPin.isResting ? layout.opacity * 0.45 : layout.opacity)
        .blur(radius: layout.blur)
        .onAppear {
            // §19 never-rule: shouldPulse is structurally false for resting chapters.
            guard worldPin.shouldPulse, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }
}

/// iconRef is either an SF Symbol name or an emoji — render whichever it is.
struct PinIcon: View {
    let iconRef: String
    let tokens: ThemeTokens

    var body: some View {
        if UIImage(systemName: iconRef) != nil {
            Image(systemName: iconRef)
                .font(.system(size: 18))
                .foregroundStyle(tokens.ink)
        } else {
            Text(iconRef.isEmpty ? "•" : iconRef)
                .font(.system(size: 18))
        }
    }
}

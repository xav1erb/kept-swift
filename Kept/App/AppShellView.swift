import SwiftUI

/// The nav shell (§2.3): five slots — World · River · [Pom center button] · Wins · You.
/// Chapters have no tab; they are pushed onto the world stack.
struct AppShellView: View {
    @Environment(Router.self) private var router
    @Environment(ThemeModel.self) private var themeModel

    var body: some View {
        @Bindable var router = router
        let tokens = themeModel.tokens
        NavigationStack(path: $router.path) {
            ZStack(alignment: .bottom) {
                surface(for: router.tab)
                KeptTabBar()
            }
            .background(tokens.backgroundGradient.ignoresSafeArea())
            .navigationDestination(for: Route.self) { route in
                destination(for: route)
            }
        }
        .sheet(isPresented: $router.isTellPomPresented) {
            TellPomPlaceholderSheet()
        }
        .tint(tokens.ink)
    }

    @ViewBuilder
    private func surface(for tab: KeptTab) -> some View {
        switch tab {
        case .world:
            SurfacePlaceholder(
                title: "your world ✨",
                state: .empty(message: "Your world is on its way — the globe lands at M3. Nothing here is lost, just not yet built.")
            )
        case .river:
            SurfacePlaceholder(
                title: "the River",
                state: .empty(message: "The river starts flowing at M5 — every chapter will weave into one stream.")
            )
        case .wins:
            SurfacePlaceholder(
                title: "your wins ⭐",
                state: .empty(message: "Proof you're doing better than you think — arriving at M7.")
            )
        case .you:
            ThemeLabView()
        }
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .chapter(let id):
            SurfacePlaceholder(
                title: "chapter",
                state: .empty(message: "Chapter detail lands at M4.\n(\(id.uuidString.prefix(8))…)")
            )
        case .streak:
            SurfacePlaceholder(
                title: "tending your world",
                state: .empty(message: "The soft streak page lands at M7 — one protected rest day a week. 🌙")
            )
        }
    }
}

/// The five-slot bar. The center button is Pom's face — a plain circle until F7 art lands.
struct KeptTabBar: View {
    @Environment(Router.self) private var router
    @Environment(ThemeModel.self) private var themeModel

    var body: some View {
        let tokens = themeModel.tokens
        HStack(spacing: 0) {
            tabButton(.world, icon: "globe.europe.africa.fill", label: "World")
            tabButton(.river, icon: "water.waves", label: "River")
            pomButton
            tabButton(.wins, icon: "star.fill", label: "Wins")
            tabButton(.you, icon: "person.fill", label: "You")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: ThemeTokens.radiusLarge)
                .fill(tokens.card.opacity(tokens.cardOpacity))
                .shadow(color: tokens.lilac.opacity(0.25), radius: 12, y: 4)
        )
        .padding(.horizontal, 16)
    }

    private var pomButton: some View {
        let tokens = themeModel.tokens
        return Button {
            router.isTellPomPresented = true
        } label: {
            ZStack {
                Circle()
                    .fill(tokens.gold.opacity(0.9))
                    .frame(width: 54, height: 54)
                // Pom's face — placeholder circle until the designer's art (F7).
                Circle()
                    .fill(tokens.card)
                    .frame(width: 44, height: 44)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Tell Pom")
    }

    private func tabButton(_ tab: KeptTab, icon: String, label: String) -> some View {
        let tokens = themeModel.tokens
        let isSelected = router.tab == tab
        return Button {
            router.tab = tab
            router.path = []
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(label)
                    .font(KeptFont.ui(10))
            }
            .foregroundStyle(isSelected ? tokens.ink : tokens.inkSoft)
            .frame(maxWidth: .infinity)
        }
    }
}

/// Fresh-each-session capture sheet placeholder (the real Tell Pom lands at M5).
struct TellPomPlaceholderSheet: View {
    @Environment(ThemeModel.self) private var themeModel

    var body: some View {
        let tokens = themeModel.tokens
        VStack(spacing: 12) {
            Capsule()
                .fill(tokens.inkSoft.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
            Text("I'm listening.")
                .font(KeptFont.display(24))
                .foregroundStyle(tokens.ink)
            Text("Say anything — a mess, a win, three topics at once. Sorting it is my job, not yours. (Capture lands at M5.)")
                .font(KeptFont.ui(15))
                .foregroundStyle(tokens.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            SealedFooter()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tokens.backgroundGradient.ignoresSafeArea())
        .presentationDetents([.medium])
    }
}

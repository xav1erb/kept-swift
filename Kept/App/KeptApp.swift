import SwiftUI

@main
struct KeptApp: App {
    @State private var store: KeptStore
    @State private var themeModel: ThemeModel
    @State private var router = Router()
    @State private var appLock = AppLockModel()
    @State private var onboarding: OnboardingModel
    @State private var newChapter: NewChapterModel
    @State private var clients: AppClients
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            let store = try KeptStore()
            _store = State(initialValue: store)
            // Composition root wiring (M2/M4): backend from AppSecrets (Unconfigured when the
            // anon key is absent — the app runs fully local); extraction + chat endpoints = the
            // Supabase functions host with the user JWT (C5).
            let backend = BackendClientKey.liveValue
            let extraction: any ExtractionServicing
            let chat: any ChatServicing
            if let config = BackendConfig.load() {
                extraction = LiveExtractionClient(endpoint: ExtractionEndpoint(
                    baseURL: config.url,
                    accessToken: { @Sendable in try await backend.accessToken() }
                ))
                chat = LiveChatClient(endpoint: ChatEndpoint(
                    baseURL: config.url,
                    accessToken: { @Sendable in try await backend.accessToken() }
                ))
            } else {
                extraction = UnconfiguredExtractionClient()
                chat = UnconfiguredChatClient()
            }
            _clients = State(initialValue: AppClients(chat: chat, extraction: extraction))
            _onboarding = State(initialValue: OnboardingModel(
                store: store,
                backend: backend,
                extraction: extraction,
                masterKey: KeychainMasterKey()
            ))
            _newChapter = State(initialValue: NewChapterModel(store: store, extraction: extraction))
            _themeModel = State(initialValue: ThemeModel(
                theme: ((try? store.userProfile())?.theme) ?? .cloudCream
            ))
        } catch {
            // Composition root: there is no app without the store. Fail loudly (NN#7 spirit),
            // never limp along with an un-kept world.
            fatalError("KeptStore failed to open: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(themeModel)
                .environment(router)
                .environment(appLock)
                .environment(onboarding)
                .environment(newChapter)
                .environment(clients)
                .onOpenURL { url in
                    if url.host() == "auth-callback" {
                        Task { await onboarding.handleAuthCallback(url: url) }
                    } else {
                        _ = router.open(deepLink: url)
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    appLock.handleScenePhase(phase)
                }
        }
    }
}

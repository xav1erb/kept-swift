import SwiftUI

@main
struct KeptApp: App {
    @State private var store: KeptStore
    @State private var themeModel = ThemeModel()
    @State private var router = Router()
    @State private var appLock = AppLockModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            _store = State(initialValue: try KeptStore())
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
                .onOpenURL { url in
                    _ = router.open(deepLink: url)
                }
                .onChange(of: scenePhase) { _, phase in
                    appLock.handleScenePhase(phase)
                }
        }
    }
}

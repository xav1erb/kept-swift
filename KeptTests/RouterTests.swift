import Foundation
import Testing
@testable import Kept

/// M0 acceptance §7.4 — every notification will deep-link through this (C8/C10).
struct RouterTests {
    @Test func tabLinksSwitchTabs() {
        let router = Router()
        #expect(router.open(deepLink: URL(string: "kept://river")!))
        #expect(router.tab == .river)
        #expect(router.open(deepLink: URL(string: "kept://you")!))
        #expect(router.tab == .you)
        #expect(router.path.isEmpty)
    }

    @Test func chapterLinkPushesRoute() {
        let router = Router()
        let id = UUID()
        #expect(router.open(deepLink: URL(string: "kept://chapter/\(id.uuidString)")!))
        #expect(router.tab == .world)
        #expect(router.path == [.chapter(id)])
    }

    @Test func streakLinkPushesRoute() {
        let router = Router()
        #expect(router.open(deepLink: URL(string: "kept://streak")!))
        #expect(router.path == [.streak])
    }

    @Test func tellPomLinkPresentsSheet() {
        let router = Router()
        #expect(router.open(deepLink: URL(string: "kept://tellpom")!))
        #expect(router.isTellPomPresented)
    }

    @Test func unknownLinksAreRefusedLoudly() {
        let router = Router()
        #expect(!router.open(deepLink: URL(string: "kept://surveillance")!))
        #expect(!router.open(deepLink: URL(string: "kept://chapter/not-a-uuid")!))
        #expect(!router.open(deepLink: URL(string: "https://example.com/chapter/abc")!))
        #expect(router.tab == .world)
        #expect(router.path.isEmpty)
    }

    @Test func switchingTabClearsPath() {
        let router = Router()
        router.open(deepLink: URL(string: "kept://streak")!)
        #expect(!router.path.isEmpty)
        router.open(deepLink: URL(string: "kept://wins")!)
        #expect(router.path.isEmpty)
    }
}

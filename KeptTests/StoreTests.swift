import Foundation
import Testing
@testable import Kept

/// M0 acceptance §7.1/§7.2 — the full graph round-trips through the encrypted store, and the
/// store file carries NSFileProtectionComplete (enforcement itself is device-verified).
struct StoreTests {

    @Test func fullGraphRoundTripsThroughReopenedStore() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "kept-test-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        var store: KeptStore? = try KeptStore(configuration: .onDisk(url))

        // Seed the M0-CONTRACTS §7.1 graph: user, chapter, person, folded event, dated
        // commitment with evidence, goal, cross-link.
        try store!.setUserName("Ana")
        try store!.setTheme(.midnight)
        let chapterId = try store!.createChapter(
            type: .relationship, chapterKind: .situational,
            title: "Daniel · the Instagram thing", iconRef: "heart"
        )
        let otherChapterId = try store!.createChapter(
            type: .growth, chapterKind: .dimension, title: "Growth", iconRef: "leaf"
        )
        let personId = try store!.addPerson(name: "Daniel", relation: "partner")
        try store!.attach(personId: personId, toChapter: chapterId)
        let eventId = try store!.addEvent(
            chapterId: chapterId, date: Date(timeIntervalSince1970: 1_751_760_000),
            title: "The promise", body: "no following girls", valence: .neutral,
            isOpen: true, isUpcoming: false, source: .onboarding
        )
        let commitmentId = try store!.addCommitment(
            chapterId: chapterId, personId: personId,
            text: "no following girls", dateMade: Date(timeIntervalSince1970: 1_751_760_000)
        )
        try store!.addEvidence(eventId: eventId, toCommitment: commitmentId)
        try store!.setCommitmentStatus(commitmentId, status: .broken)
        try store!.addGoal(chapterId: chapterId, text: "€6,000 saved", targetDate: nil, progressNote: "at €4,200")
        try store!.addCrossLink(from: chapterId, to: otherChapterId, note: "insecurity ↔ relationship")
        try store!.setChapterState(chapterId, state: .tense)

        let profileBefore = try store!.userProfile()
        let chaptersBefore = try store!.chapterSummaries()
        let peopleBefore = try store!.people()
        let eventsBefore = try store!.events(inChapter: chapterId)
        let commitmentsBefore = try store!.commitments(inChapter: chapterId)
        let goalsBefore = try store!.goals()
        let linksBefore = try store!.crossLinks()

        // Reopen on the same URL with a fresh container.
        store = nil
        let reopened = try KeptStore(configuration: .onDisk(url))

        #expect(try reopened.userProfile() == profileBefore)
        #expect(try reopened.chapterSummaries() == chaptersBefore)
        #expect(try reopened.people() == peopleBefore)
        #expect(try reopened.events(inChapter: chapterId) == eventsBefore)
        #expect(try reopened.commitments(inChapter: chapterId) == commitmentsBefore)
        #expect(try reopened.goals() == goalsBefore)
        #expect(try reopened.crossLinks() == linksBefore)

        // Spot-check load-bearing values survived, not just equality of empty arrays.
        #expect(profileBefore.name == "Ana")
        #expect(profileBefore.theme == .midnight)
        #expect(chaptersBefore.count == 2)
        #expect(chaptersBefore.first?.state == .tense)
        #expect(commitmentsBefore.first?.status == .broken)
        #expect(commitmentsBefore.first?.evidenceEventIds == [eventId])
        #expect(peopleBefore.first?.chapterIds == [chapterId])
    }

    @Test func storeFileCarriesCompleteFileProtection() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "kept-prot-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try KeptStore(configuration: .onDisk(url))

        // The simulator's macOS-backed filesystem has no data-protection classes — setting the
        // attribute is a silent no-op there, so the full assert runs on device only (it is also
        // on the M0 device-verify checklist). On simulator we prove the file exists and the
        // protection call path completes without throwing.
        #expect(FileManager.default.fileExists(atPath: url.path))
        try KeptStore.applyFileProtection(storeURL: url)
        #if !targetEnvironment(simulator)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let protection = attributes[.protectionKey] as? FileProtectionType
        #expect(protection == .complete)
        #endif
    }

    @Test func singletonsAreFetchOrCreate() throws {
        let store = try KeptStore(configuration: .inMemory)
        let first = try store.userProfile()
        let second = try store.userProfile()
        #expect(first.id == second.id)

        let prefs = try store.notificationPrefs()
        #expect(prefs.genericLockScreenCopy)   // F12: generic phrasing default ON
        #expect(try store.notificationPrefs() == prefs)
    }

    @Test func sensitiveTypesAreTypeLevelFacts() {
        // §19 never-rule anchor: the flag the count-suppressing UI keys off (C3).
        #expect(ChapterType.privateCorner.isSensitive)
        #expect(ChapterType.grief.isSensitive)
        #expect(ChapterType.allCases.filter(\.isSensitive).count == 2)
    }

    @Test func unknownIdsFailLoudly() throws {
        let store = try KeptStore(configuration: .inMemory)
        #expect(throws: KeptStore.StoreError.self) {
            try store.setChapterState(UUID(), state: .warm)
        }
    }
}

import Foundation
import Testing
@testable import Kept

// F10 (M2-CONTRACTS §5): priority order, dedupe, sensitive exclusion (never-test), defer to
// tail, silent auto-resolve through the merge — plus the F6/§19 soft-copy source scans.

@MainActor
struct FollowupQueueTests {

    @Test func enqueueOrdersByPriorityAndExcludesSensitive() throws {
        let store = try KeptStore(configuration: .inMemory)
        // Deliberately shuffled + sensitive types included — the enqueue must fix both.
        try store.enqueueFollowups([.money, .grief, .family, .privateCorner, .work])
        #expect(try store.userProfile().followupQueue == [.family, .work, .money])
    }

    @Test func enqueueDeduplicates() throws {
        let store = try KeptStore(configuration: .inMemory)
        try store.enqueueFollowups([.family, .money])
        try store.enqueueFollowups([.money, .health])
        #expect(try store.userProfile().followupQueue == [.family, .money, .health])
    }

    @Test func deferMovesToTail() throws {
        let store = try KeptStore(configuration: .inMemory)
        try store.enqueueFollowups([.family, .work, .money])
        try store.deferFollowup(.family)
        #expect(try store.userProfile().followupQueue == [.work, .money, .family])
    }

    @Test func chapterCreationAutoResolvesSilently() async throws {
        let store = try KeptStore(configuration: .inMemory)
        try store.grantAIConsent()
        try store.enqueueFollowups([.family, .money])

        // A family chapter arrives through ANY capture (here: a filed vent) → the queue item
        // resolves with no copy, no celebration (F10 + C3).
        let envelopeJSON = """
        {"schemaVersion": 1, "utteranceId": "\(UUID().uuidString)", "disambiguations": [], "deltas": [
          {"kind": "upsertChapter", "ref": "c1", "type": "family", "chapterKind": "dimension", "title": "Mom"}
        ]}
        """
        let envelope = try JSONDecoder().decode(ExtractionEnvelope.self, from: Data(envelopeJSON.utf8))
        _ = try store.applyExtraction(
            envelope, sentContext: try store.extractionContext(), surface: .vent, clientTime: .now
        )
        #expect(try store.userProfile().followupQueue == [.money])
    }

    /// C3 never-scan (the M1 privacy-audit pattern): no queue-count or guilt copy anywhere in
    /// the app target. "One question per app-open, max" never becomes "2 rooms left".
    @Test func noQueueCountOrGuiltCopyInAppSources() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let appSources = repoRoot.appending(path: "Kept")
        let forbidden = [
            "rooms left", "questions left", "questions remaining", "rooms remaining",
            "We miss you", "we miss you", "don't forget me", "come back",
        ]
        let enumerator = FileManager.default.enumerator(at: appSources, includingPropertiesForKeys: nil)
        var scanned = 0
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let content = try String(contentsOf: url, encoding: .utf8)
            scanned += 1
            for phrase in forbidden {
                #expect(!content.contains(phrase), "\(url.lastPathComponent) contains forbidden copy: '\(phrase)'")
            }
        }
        #expect(scanned > 30)  // the scan actually walked the target
    }

    /// F6 never-scan: the restriction is invisible — no mode label anywhere.
    @Test func noVisibleMinorModeLabelInAppSources() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let appSources = repoRoot.appending(path: "Kept")
        let forbidden = ["teen mode", "Teen mode", "restricted mode", "Restricted mode", "minor mode"]
        let enumerator = FileManager.default.enumerator(at: appSources, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let content = try String(contentsOf: url, encoding: .utf8)
            for phrase in forbidden {
                #expect(!content.contains(phrase), "\(url.lastPathComponent) contains forbidden copy: '\(phrase)'")
            }
        }
    }
}

import Foundation
import Testing
@testable import Kept

/// The decode boundary (NN#7, M1-CONTRACTS §7.2): strict Codable both directions; hostile or
/// sloppy JSON fails loudly at the exact boundary it violates.
struct ExtractionDecodeTests {

    @Test func fullEnvelopeRoundTripsThroughEveryDeltaKind() throws {
        let personId = UUID()
        let chapterId = UUID()
        let eventId = UUID()
        let commitmentId = UUID()
        let envelope = ExtractionEnvelope(
            schemaVersion: 1,
            utteranceId: UUID(),
            deltas: [
                .upsertPerson(UpsertPersonDelta(
                    target: .ref("p1"), name: "Daniel", relation: "partner", mood: .warm,
                    roleFlags: [.confidant], rituals: ["Sunday cooking"],
                    notesAppend: "brought flowers", chapterRefs: [.ref("c1"), .id(chapterId)]
                )),
                .upsertChapter(UpsertChapterDelta(
                    target: .ref("c1"), type: .relationship, chapterKind: .situational,
                    title: "Daniel", iconRef: "heart", state: .tense
                )),
                .addEvent(AddEventDelta(
                    ref: "e1", chapterRef: .ref("c1"), date: WireDate(year: 2026, month: 7, day: 6),
                    datePrecision: .day, title: "The promise", body: "no following girls",
                    valence: .neutral, isOpen: true, isUpcoming: false
                )),
                .foldEvent(FoldEventDelta(eventId: eventId, reason: "I forgave him")),
                .addCommitment(AddCommitmentDelta(
                    ref: "cm1", chapterRef: .ref("c1"), personRef: .ref("p1"),
                    text: "no following girls", dateMade: WireDate(year: 2026, month: 7, day: 6),
                    datePrecision: .day
                )),
                .updateCommitmentStatus(UpdateCommitmentStatusDelta(
                    commitmentRef: .id(commitmentId), status: .broken, evidenceEventRef: .ref("e1")
                )),
                .upsertGoal(UpsertGoalDelta(
                    target: .ref("g1"), chapterRef: .id(chapterId), text: "€6,000 saved",
                    targetDate: WireDate(year: 2026, month: 12, day: 1), progressNote: "at €4,200"
                )),
                .setChapterState(SetChapterStateDelta(chapterRef: .id(chapterId), state: .warm)),
                .setPersonMood(SetPersonMoodDelta(personRef: .id(personId), mood: .drifting)),
                .addCrossLink(AddCrossLinkDelta(
                    fromChapterRef: .id(chapterId), toChapterRef: .ref("c1"),
                    note: "insecurity ↔ relationship"
                )),
                .fillSlots(FillSlotsDelta(chapterRef: .ref("c1"), slots: ["partnerName"])),
            ],
            disambiguations: [
                Disambiguation(
                    ref: "p9", mention: "Sara", candidateIds: [personId],
                    question: "work-Sara, not Instagram-Sara, right?"
                ),
            ]
        )

        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(ExtractionEnvelope.self, from: data)
        #expect(decoded == envelope)

        // The tag survives as the wire's "kind" discriminator.
        let raw = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let kinds = try #require(raw["deltas"] as? [[String: Any]]).compactMap { $0["kind"] as? String }
        #expect(kinds.first == "upsertPerson")
        #expect(kinds.count == 11)
    }

    @Test(arguments: [
        "2026-2-3",       // not zero-padded
        "2026-13-01",     // month out of range
        "2026-02-31",     // impossible calendar day
        "07-06-2026",     // wrong field order
        "july 6",         // prose
        "2026/07/06",     // wrong separator
    ])
    func wireDateRejectsSloppyFormats(_ raw: String) {
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(WireDate.self, from: Data("\"\(raw)\"".utf8))
        }
    }

    @Test func wireDateParsesAndResolvesInUTC() throws {
        let date = try JSONDecoder().decode(WireDate.self, from: Data("\"2026-07-06\"".utf8))
        #expect(date == WireDate(year: 2026, month: 7, day: 6))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let components = utc.dateComponents([.year, .month, .day, .hour], from: date.date)
        #expect(components.year == 2026)
        #expect(components.month == 7)
        #expect(components.day == 6)
        #expect(components.hour == 0)
    }

    @Test func entityHandleRequiresExactlyOneOfIdAndRef() throws {
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                EntityHandle.self,
                from: Data(#"{"id": "7A000000-0000-4000-8000-000000000001", "ref": "c1"}"#.utf8)
            )
        }
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(EntityHandle.self, from: Data("{}".utf8))
        }
        let byRef = try JSONDecoder().decode(EntityHandle.self, from: Data(#"{"ref": "c1"}"#.utf8))
        #expect(byRef == .ref("c1"))
        let uuid = UUID()
        let byId = try JSONDecoder().decode(
            EntityHandle.self, from: Data(#"{"id": "\#(uuid.uuidString)"}"#.utf8)
        )
        #expect(byId == .id(uuid))
    }

    @Test func disambiguationRequiresItsBindingRef() {
        // Ratification amendment: without `ref` there is no exact target to bind at resolution.
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(
                Disambiguation.self,
                from: Data(#"{"mention": "Sara", "candidateIds": [], "question": "which one?"}"#.utf8)
            )
        }
    }

    @Test func requestEncodesTheContractShape() throws {
        let request = ExtractionRequest(
            surface: .vent,
            clientTime: Date(timeIntervalSince1970: 1_784_419_200),
            locale: "en_NL",
            utterance: "three things happened today",
            context: ExtractionContext(
                people: [], chapters: [], openCommitments: [],
                recentEvents: [
                    ExtractionContext.EventContext(
                        id: UUID(), chapterId: nil, title: "The birthday fight",
                        date: WireDate(year: 2026, month: 6, day: 28), isOpen: false, isHealed: true
                    ),
                ]
            )
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let raw = try #require(
            try JSONSerialization.jsonObject(with: encoder.encode(request)) as? [String: Any]
        )
        #expect(raw["schemaVersion"] as? Int == ExtractionSchema.version)
        #expect(raw["surface"] as? String == "vent")
        #expect(raw["utterance"] as? String == "three things happened today")
        let context = try #require(raw["context"] as? [String: Any])
        let events = try #require(context["recentEvents"] as? [[String: Any]])
        // §8.3 ruling made visible on the wire: folded events travel flagged.
        #expect(events.first?["isHealed"] as? Bool == true)
        #expect(events.first?["date"] as? String == "2026-06-28")
    }
}

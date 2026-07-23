import Foundation

// New-chapter flow (M3-CONTRACTS §5): the grid + launch. The sequence itself is M2's
// InterviewEngine walking a ChapterSequenceScript (§8 ruling 1 — one path, C1). The chapter is
// created via the typed command at Begin; free-text answers queue and flush through the M1
// pipeline at the end of the sequence, which fills the awareness slots (the ring's number is
// computed at merge, C6).

@Observable
final class NewChapterModel {

    /// One grid card. `countText` is nil for sensitive types BY CONSTRUCTION — there is no code
    /// path that produces a count string for them (C3; the never-test asserts it).
    struct TypeCard: Identifiable, Equatable {
        let type: ChapterType
        let name: String
        let oneLiner: String
        let symbol: String
        let countText: String?
        let gentleText: String?

        var id: String { type.rawValue }
    }

    enum Phase: Equatable {
        case picking
        case sequence
        /// The end-of-sequence flush — extraction filing the answers into the new room.
        case building
        case done
    }

    private let store: KeptStore
    private let extraction: any ExtractionServicing

    private(set) var phase: Phase = .picking
    var selectedType: ChapterType?
    private(set) var engine: InterviewEngine?
    private(set) var chapterId: UUID?
    /// Rows still queued after a failed flush — filing lags, it never silently drops (NN#7).
    private(set) var flushLagged = false

    init(store: KeptStore, extraction: any ExtractionServicing) {
        self.store = store
        self.extraction = extraction
    }

    static func cards() -> [TypeCard] {
        ChapterType.allCases.map { type in
            TypeCard(
                type: type,
                name: type.displayName,
                oneLiner: type.oneLiner,
                symbol: type.gridSymbol,
                countText: type.isSensitive ? nil : "\(AwarenessSchema.slots(for: type).count) questions",
                gentleText: type.isSensitive ? "goes gently" : nil
            )
        }
    }

    /// Begin: create the chapter (typed command — the pin exists from this moment) and start
    /// the sequence.
    func begin() {
        guard let type = selectedType, phase == .picking else { return }
        do {
            let id = try store.createChapter(
                type: type,
                chapterKind: .dimension,
                title: type.displayName,
                iconRef: type.gridSymbol
            )
            chapterId = id
            let engine = InterviewEngine(
                store: store,
                script: ChapterSequenceScript(type: type, chapterId: id)
            )
            engine.start()
            self.engine = engine
            phase = .sequence
        } catch {
            // Creation failed — nothing to walk; stay on the grid (the view shows the soft error).
            chapterId = nil
        }
    }

    func submitText(_ text: String) async {
        await engine?.submitText(text)
        await finishIfComplete()
    }

    func skip() {
        engine?.skip()
        Task { await finishIfComplete() }
    }

    /// "you can stop anytime" — ends the sequence early; whatever was answered is kept.
    func stopEarly() async {
        await finish()
    }

    private func finishIfComplete() async {
        if engine?.isComplete == true { await finish() }
    }

    /// Flush the queued answers through the M1 pipeline — extraction files them into the new
    /// room and fills its slots. Failures keep rows queued (retry later), never drop.
    private func finish() async {
        guard phase == .sequence else { return }
        phase = .building
        let flusher = UtteranceFlusher(store: store, extraction: extraction)
        let result = await flusher.flush()
        flushLagged = !result.failedUtteranceIds.isEmpty
        phase = .done
    }

    /// Fresh state for the next visit (the model lives at the composition root).
    func reset() {
        phase = .picking
        selectedType = nil
        engine = nil
        chapterId = nil
        flushLagged = false
    }
}

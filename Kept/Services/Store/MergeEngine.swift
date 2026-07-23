import Foundation
import SwiftData

// The deterministic merge (docs/extraction.md §2–§4, C1/C4). The model PROPOSED the envelope;
// this file DISPOSES: strict validation first (envelope-atomic — reject everything or apply
// everything), then application in the spec's fixed order, then stored-number recompute (C6).
// Disambiguation-held deltas are the single atomicity exception: parked persisted, never dropped.

// MARK: - Public value types

/// What a merge did — feeds the filing confirmation surface (M5) and the disambiguation prompts.
nonisolated struct FilingSummary: Equatable, Sendable {
    let utteranceId: UUID
    let touchedChapterIds: [UUID]
    let pendingQuestions: [PendingDisambiguation]
    let wasAlreadyApplied: Bool
}

nonisolated struct PendingDisambiguation: Equatable, Sendable, Identifiable {
    let id: UUID
    let utteranceId: UUID
    let ref: String
    let mention: String
    let candidateIds: [UUID]
    let question: String
}

/// The user's answer to a disambiguation question (C4: person identity is never guessed).
nonisolated enum PersonResolution: Equatable, Sendable {
    case existing(UUID)
    case newPerson
}

nonisolated enum MergeError: Error, Equatable {
    case schemaVersionMismatch(envelope: Int, expected: Int)
    case unknownRef(String)
    case forwardRef(String)
    case duplicateRef(String)
    case idNotInContext(String)
    case invalidSlot(slot: String, chapterType: ChapterType)
    case invalidEnvelope(String)
    case unknownBatch(UUID)
    case invalidResolution(String)
}

// MARK: - The merge

extension KeptStore {

    /// Applies one delta envelope. `sentContext` is the exact context of the request that produced
    /// this envelope — an `id` the model emits that we did not send is a fabrication and rejects
    /// the whole envelope (extraction.md §2), even if the entity happens to exist.
    @discardableResult
    func applyExtraction(
        _ envelope: ExtractionEnvelope,
        sentContext: ExtractionContext,
        surface: Surface,
        clientTime: Date
    ) throws -> FilingSummary {
        guard envelope.schemaVersion == ExtractionSchema.version else {
            throw MergeError.schemaVersionMismatch(
                envelope: envelope.schemaVersion, expected: ExtractionSchema.version
            )
        }

        // §3 rule 1 — idempotency: a duplicate envelope is a no-op.
        if try isApplied(envelope.utteranceId) {
            return FilingSummary(
                utteranceId: envelope.utteranceId, touchedChapterIds: [],
                pendingQuestions: [], wasAlreadyApplied: true
            )
        }

        // ---- Validation pass (pure — no mutation happens before this completes) ----

        var ambiguousRefs = Set(envelope.disambiguations.map(\.ref))
        guard ambiguousRefs.count == envelope.disambiguations.count else {
            throw MergeError.invalidEnvelope("Duplicate disambiguation refs")
        }
        for disambiguation in envelope.disambiguations {
            for candidate in disambiguation.candidateIds {
                guard sentContext.people.contains(where: { $0.id == candidate }) else {
                    throw MergeError.idNotInContext("person \(candidate)")
                }
            }
        }
        try validate(envelope.deltas, sentContext: sentContext, ambiguousRefs: ambiguousRefs)

        // Deterministic backstop (§1): a person-create whose normalized name collides with an
        // existing person becomes a disambiguation itself — the model's diligence is never the
        // mechanism. User-confirmed new people resolve through the same gate.
        var disambiguations = envelope.disambiguations
        for case .upsertPerson(let delta) in envelope.deltas {
            guard case .ref(let ref) = delta.target, !ambiguousRefs.contains(ref) else { continue }
            let collisions = try allPersons().filter {
                Self.normalized($0.name) == Self.normalized(delta.name)
            }
            if !collisions.isEmpty {
                ambiguousRefs.insert(ref)
                disambiguations.append(Disambiguation(
                    ref: ref,
                    mention: delta.name,
                    candidateIds: collisions.map(\.id).sorted { $0.uuidString < $1.uuidString },
                    question: "Is this the \(delta.name) you've told me about, or someone new?"
                ))
            }
        }

        // Partition: any delta referencing an ambiguous ref is held, everything else applies.
        let held = envelope.deltas.filter { Self.references($0, anyOf: ambiguousRefs) }
        let applied = envelope.deltas.filter { !Self.references($0, anyOf: ambiguousRefs) }

        // ---- Apply pass (single save at the end; rollback on any failure) ----

        do {
            var bindings: [String: UUID] = [:]
            let touched = try apply(
                applied, bindings: &bindings, surface: surface, clientTime: clientTime
            )

            var pending: [PendingDisambiguation] = []
            let encoder = JSONEncoder()
            for disambiguation in disambiguations where ambiguousRefs.contains(disambiguation.ref) {
                let heldForRef = held.filter { Self.references($0, anyOf: [disambiguation.ref]) }
                let batch = HeldDeltaBatch(
                    utteranceId: envelope.utteranceId,
                    ref: disambiguation.ref,
                    mention: disambiguation.mention,
                    candidateIds: disambiguation.candidateIds,
                    question: disambiguation.question,
                    deltasJSON: try encoder.encode(heldForRef),
                    bindingsJSON: try encoder.encode(bindings),
                    surfaceRaw: surface.rawValue,
                    clientTime: clientTime
                )
                modelContext.insert(batch)
                pending.append(PendingDisambiguation(
                    id: batch.id, utteranceId: envelope.utteranceId, ref: disambiguation.ref,
                    mention: disambiguation.mention, candidateIds: disambiguation.candidateIds,
                    question: disambiguation.question
                ))
            }

            modelContext.insert(AppliedUtterance(utteranceId: envelope.utteranceId))
            try modelContext.save()
            return FilingSummary(
                utteranceId: envelope.utteranceId, touchedChapterIds: touched,
                pendingQuestions: pending, wasAlreadyApplied: false
            )
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func pendingDisambiguations() throws -> [PendingDisambiguation] {
        try modelContext.fetch(FetchDescriptor<HeldDeltaBatch>(sortBy: [SortDescriptor(\.createdAt)]))
            .map {
                PendingDisambiguation(
                    id: $0.id, utteranceId: $0.utteranceId, ref: $0.ref, mention: $0.mention,
                    candidateIds: $0.candidateIds, question: $0.question
                )
            }
    }

    /// Resolves one held batch: binds the ambiguous ref to an existing person or a confirmed-new
    /// one, then merges the held deltas with the original envelope's bindings. Person merges only
    /// ever happen HERE, from an explicit user answer (C4).
    @discardableResult
    func resolveDisambiguation(batchId: UUID, resolution: PersonResolution) throws -> FilingSummary {
        guard let batch = try modelContext.fetch(
            FetchDescriptor<HeldDeltaBatch>(predicate: #Predicate { $0.id == batchId })
        ).first else {
            throw MergeError.unknownBatch(batchId)
        }
        guard let surface = Surface(rawValue: batch.surfaceRaw) else {
            throw MergeError.invalidEnvelope("Corrupt held batch surface '\(batch.surfaceRaw)'")
        }
        let decoder = JSONDecoder()
        let heldDeltas = try decoder.decode([Delta].self, from: batch.deltasJSON)
        var bindings = try decoder.decode([String: UUID].self, from: batch.bindingsJSON)

        do {
            var deltasToApply = heldDeltas
            switch resolution {
            case .existing(let personId):
                guard batch.candidateIds.contains(personId) else {
                    throw MergeError.invalidResolution("Person \(personId) is not a candidate")
                }
                bindings[batch.ref] = personId
                // The held creation (if any) collapses into the existing person: apply its
                // profile additions as an id-update, never a second Person row.
                deltasToApply = heldDeltas.compactMap { delta in
                    guard case .upsertPerson(let create) = delta,
                          create.target == .ref(batch.ref) else { return delta }
                    return .upsertPerson(UpsertPersonDelta(
                        target: .id(personId), name: create.name, relation: create.relation,
                        mood: create.mood, roleFlags: create.roleFlags, rituals: create.rituals,
                        notesAppend: create.notesAppend, chapterRefs: create.chapterRefs
                    ))
                }
            case .newPerson:
                let hasCreation = heldDeltas.contains {
                    if case .upsertPerson(let create) = $0 { return create.target == .ref(batch.ref) }
                    return false
                }
                if !hasCreation {
                    // Model-flagged ambiguity with no creation in the envelope: the confirmed-new
                    // person is created from the mention.
                    deltasToApply.insert(
                        .upsertPerson(UpsertPersonDelta(target: .ref(batch.ref), name: batch.mention)),
                        at: 0
                    )
                }
            }

            let touched = try apply(
                deltasToApply, bindings: &bindings, surface: surface, clientTime: batch.clientTime
            )
            modelContext.delete(batch)
            try modelContext.save()
            return FilingSummary(
                utteranceId: batch.utteranceId, touchedChapterIds: touched,
                pendingQuestions: [], wasAlreadyApplied: false
            )
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    // MARK: - Validation (extraction.md §2)

    private func validate(
        _ deltas: [Delta], sentContext: ExtractionContext, ambiguousRefs: Set<String>
    ) throws {
        // Refs defined by a disambiguation exist from the start (binding pending); refs defined
        // by creation deltas exist from their array position on — forward references are invalid.
        // A person-creation MAY share its ref with a disambiguation: that is the "might be new"
        // shape — the creation itself is gated. Any other collision is a duplicate.
        var visible = ambiguousRefs
        var createdByDelta = Set<String>()

        func define(_ ref: String, mayBeAmbiguous: Bool = false) throws {
            guard !createdByDelta.contains(ref),
                  mayBeAmbiguous || !ambiguousRefs.contains(ref) else {
                throw MergeError.duplicateRef(ref)
            }
            createdByDelta.insert(ref)
            visible.insert(ref)
        }

        func check(_ handle: EntityHandle, in contextIds: [UUID], kind: String) throws {
            switch handle {
            case .id(let id):
                guard contextIds.contains(id) else {
                    throw MergeError.idNotInContext("\(kind) \(id)")
                }
            case .ref(let ref):
                guard visible.contains(ref) else { throw MergeError.forwardRef(ref) }
            }
        }

        let personIds = sentContext.people.map(\.id)
        let chapterIds = sentContext.chapters.map(\.id)
        let eventIds = sentContext.recentEvents.map(\.id)
        let commitmentIds = sentContext.openCommitments.map(\.id)

        // Chapter types by handle, for slot validation.
        var chapterTypesByRef: [String: ChapterType] = [:]
        let chapterTypesById = Dictionary(
            uniqueKeysWithValues: sentContext.chapters.map { ($0.id, $0.type) }
        )

        for delta in deltas {
            switch delta {
            case .upsertPerson(let d):
                switch d.target {
                case .ref(let ref): try define(ref, mayBeAmbiguous: true)
                case .id(let id):
                    guard personIds.contains(id) else {
                        throw MergeError.idNotInContext("person \(id)")
                    }
                }
                for chapterHandle in d.chapterRefs ?? [] {
                    try check(chapterHandle, in: chapterIds, kind: "chapter")
                }
            case .upsertChapter(let d):
                switch d.target {
                case .ref(let ref):
                    try define(ref)
                    chapterTypesByRef[ref] = d.type
                case .id(let id):
                    guard chapterIds.contains(id) else {
                        throw MergeError.idNotInContext("chapter \(id)")
                    }
                }
            case .addEvent(let d):
                try check(d.chapterRef, in: chapterIds, kind: "chapter")
                try define(d.ref)
            case .foldEvent(let d):
                guard eventIds.contains(d.eventId) else {
                    throw MergeError.idNotInContext("event \(d.eventId)")
                }
            case .addCommitment(let d):
                try check(d.chapterRef, in: chapterIds, kind: "chapter")
                if let personRef = d.personRef {
                    try check(personRef, in: personIds, kind: "person")
                }
                try define(d.ref)
            case .updateCommitmentStatus(let d):
                try check(d.commitmentRef, in: commitmentIds, kind: "commitment")
                if let evidence = d.evidenceEventRef {
                    try check(evidence, in: eventIds, kind: "event")
                }
            case .upsertGoal(let d):
                if let chapterRef = d.chapterRef {
                    try check(chapterRef, in: chapterIds, kind: "chapter")
                }
                if case .ref(let ref) = d.target { try define(ref) }
            case .setChapterState(let d):
                try check(d.chapterRef, in: chapterIds, kind: "chapter")
            case .setPersonMood(let d):
                try check(d.personRef, in: personIds, kind: "person")
            case .addCrossLink(let d):
                try check(d.fromChapterRef, in: chapterIds, kind: "chapter")
                try check(d.toChapterRef, in: chapterIds, kind: "chapter")
            case .fillSlots(let d):
                try check(d.chapterRef, in: chapterIds, kind: "chapter")
                let type: ChapterType?
                switch d.chapterRef {
                case .id(let id): type = chapterTypesById[id]
                case .ref(let ref): type = chapterTypesByRef[ref]
                }
                if let type {
                    for slot in d.slots where !AwarenessSchema.isValid(slot: slot, for: type) {
                        throw MergeError.invalidSlot(slot: slot, chapterType: type)
                    }
                }
                // A fillSlots aimed at an ambiguous... chapters are never ambiguous; a nil type
                // can only mean the ref belongs to a held upsertChapter — impossible (only person
                // refs are held) — or a duplicate-checked ref, both already rejected above.
            }
        }
    }

    // MARK: - Application (extraction.md §3 — fixed order, single transaction)

    private func apply(
        _ deltas: [Delta],
        bindings: inout [String: UUID],
        surface: Surface,
        clientTime: Date
    ) throws -> [UUID] {
        var touchedChapters: [UUID] = []
        func touch(_ chapter: Chapter) {
            if !touchedChapters.contains(chapter.id) { touchedChapters.append(chapter.id) }
            chapter.lastTouchedAt = .now
            noteBlobDirty(.chapter, chapter.id)
        }

        func chapter(for handle: EntityHandle) throws -> Chapter {
            try fetchChapterModel(resolve(handle))
        }

        let fallbackDate = WireDate(date: clientTime).date

        func resolve(_ handle: EntityHandle) throws -> UUID {
            switch handle {
            case .id(let id): return id
            case .ref(let ref):
                guard let id = bindings[ref] else { throw MergeError.unknownRef(ref) }
                return id
            }
        }

        // 1. Persons
        for case .upsertPerson(let d) in deltas {
            let person: Person
            switch d.target {
            case .ref(let ref):
                person = Person(name: d.name, relation: d.relation ?? "")
                modelContext.insert(person)
                bindings[ref] = person.id
            case .id(let id):
                person = try fetchPersonModel(id)
                person.name = d.name
                if let relation = d.relation { person.relation = relation }
            }
            if let mood = d.mood { person.mood = mood }
            if let roleFlags = d.roleFlags { person.roleFlags = roleFlags }
            if let rituals = d.rituals {
                for ritual in rituals where !person.rituals.contains(ritual) {
                    person.rituals.append(ritual)
                }
            }
            if let notesAppend = d.notesAppend, !notesAppend.isEmpty {
                person.notes = person.notes.isEmpty ? notesAppend : person.notes + "\n" + notesAppend
            }
            noteBlobDirty(.person, person.id)
        }

        // 2. Chapters
        for case .upsertChapter(let d) in deltas {
            switch d.target {
            case .ref(let ref):
                let chapter = Chapter(
                    type: d.type, chapterKind: d.chapterKind,
                    title: d.title ?? Self.defaultTitle(for: d.type),
                    iconRef: d.iconRef ?? Self.defaultIcon(for: d.type)
                )
                if let state = d.state { chapter.state = state }
                modelContext.insert(chapter)
                bindings[ref] = chapter.id
                touch(chapter)
                // F10 auto-resolve (M2-CONTRACTS §5): a chapter created through ANY capture
                // silently removes its type from the followupQueue — no completion copy.
                if let profile = try modelContext.fetch(FetchDescriptor<UserProfile>()).first,
                   let index = profile.followupQueue.firstIndex(of: d.type) {
                    profile.followupQueue.remove(at: index)
                    noteBlobDirty(.userProfile, profile.id)
                }
            case .id(let id):
                let chapter = try fetchChapterModel(id)
                if let title = d.title { chapter.title = title }
                if let iconRef = d.iconRef { chapter.iconRef = iconRef }
                if let state = d.state { chapter.state = state }
                touch(chapter)
            }
        }

        // 2b. Person↔chapter attachment (queued conceptually after chapters so a person can
        // attach to a chapter created later in the same envelope).
        for case .upsertPerson(let d) in deltas {
            guard let chapterRefs = d.chapterRefs else { continue }
            let personId = try resolve(d.target)
            let person = try fetchPersonModel(personId)
            for handle in chapterRefs {
                let target = try chapter(for: handle)
                if !target.people.contains(where: { $0.id == person.id }) {
                    target.people.append(person)
                }
                touch(target)
            }
        }

        // 3. Events — `source` is stamped from the surface, never model-set; a missing date
        // falls back to the utterance date at day precision.
        for case .addEvent(let d) in deltas {
            let target = try chapter(for: d.chapterRef)
            let event = Event(
                date: d.date?.date ?? fallbackDate,
                title: d.title, body: d.body, valence: d.valence,
                isOpen: d.isOpen, isUpcoming: d.isUpcoming,
                source: surface.eventSource
            )
            modelContext.insert(event)
            event.chapter = target
            bindings[d.ref] = event.id
            touch(target)
            noteBlobDirty(.event, event.id)
        }

        // 4. Commitments — "receipts matter": stated date, else utterance date.
        for case .addCommitment(let d) in deltas {
            let target = try chapter(for: d.chapterRef)
            let commitment = Commitment(text: d.text, dateMade: d.dateMade?.date ?? fallbackDate)
            modelContext.insert(commitment)
            commitment.chapter = target
            if let personRef = d.personRef {
                commitment.person = try fetchPersonModel(resolve(personRef))
            }
            bindings[d.ref] = commitment.id
            touch(target)
            noteBlobDirty(.commitment, commitment.id)
        }
        for case .updateCommitmentStatus(let d) in deltas {
            let commitment = try fetchCommitmentModel(resolve(d.commitmentRef))
            commitment.status = d.status
            if let evidenceRef = d.evidenceEventRef {
                let evidence = try fetchEventModel(resolve(evidenceRef))
                if !commitment.evidenceEvents.contains(where: { $0.id == evidence.id }) {
                    commitment.evidenceEvents.append(evidence)
                }
            }
            if let owner = commitment.chapter { touch(owner) }
            noteBlobDirty(.commitment, commitment.id)
        }

        // 5. Goals
        for case .upsertGoal(let d) in deltas {
            let goal: Goal
            switch d.target {
            case .ref(let ref):
                goal = Goal(text: d.text)
                modelContext.insert(goal)
                bindings[ref] = goal.id
            case .id(let id):
                goal = try fetchGoalModel(id)
                goal.text = d.text
            }
            if let chapterRef = d.chapterRef {
                let owner = try chapter(for: chapterRef)
                goal.chapter = owner
                touch(owner)
            }
            if let targetDate = d.targetDate { goal.targetDate = targetDate.date }
            if let progressNote = d.progressNote { goal.progressNote = progressNote }
            noteBlobDirty(.goal, goal.id)
        }

        // 6. Cross-links
        for case .addCrossLink(let d) in deltas {
            let link = CrossLink(note: d.note)
            modelContext.insert(link)
            link.fromChapter = try chapter(for: d.fromChapterRef)
            link.toChapter = try chapter(for: d.toChapterRef)
        }

        // 7. States — the soft vocabulary only (enforced by the enums at decode).
        for case .setChapterState(let d) in deltas {
            let target = try chapter(for: d.chapterRef)
            target.state = d.state
            touch(target)
        }
        for case .setPersonMood(let d) in deltas {
            let person = try fetchPersonModel(resolve(d.personRef))
            person.mood = d.mood
            noteBlobDirty(.person, person.id)
        }

        // 8. Folding — one-way, conservative: flips false→true only; refolding never
        // overwrites the original reason. Unfolding is a user tap, not a delta (C3).
        for case .foldEvent(let d) in deltas {
            let event = try fetchEventModel(d.eventId)
            if !event.isHealed {
                event.isHealed = true
                event.healedReason = d.reason
                if let owner = event.chapter { touch(owner) }
                noteBlobDirty(.event, event.id)
            }
        }

        // 9. Slots, then recompute stored numbers for touched chapters (C6).
        for case .fillSlots(let d) in deltas {
            let target = try chapter(for: d.chapterRef)
            for slot in d.slots where !target.filledSlots.contains(slot) {
                target.filledSlots.append(slot)
            }
            touch(target)
        }
        for chapterId in touchedChapters {
            let target = try fetchChapterModel(chapterId)
            target.awarenessPct = AwarenessSchema.awarenessPct(
                filledSlots: target.filledSlots, type: target.type
            )
        }

        return touchedChapters
    }

    // MARK: - Helpers

    private static func references(_ delta: Delta, anyOf refs: Set<String>) -> Bool {
        func hits(_ handle: EntityHandle?) -> Bool {
            if case .ref(let ref) = handle { return refs.contains(ref) }
            return false
        }
        switch delta {
        case .upsertPerson(let d):
            return hits(d.target) || (d.chapterRefs ?? []).contains(where: { hits($0) })
        case .upsertChapter(let d): return hits(d.target)
        case .addEvent(let d): return hits(d.chapterRef)
        case .foldEvent: return false
        case .addCommitment(let d): return hits(d.chapterRef) || hits(d.personRef)
        case .updateCommitmentStatus(let d): return hits(d.commitmentRef) || hits(d.evidenceEventRef)
        case .upsertGoal(let d): return hits(d.target) || hits(d.chapterRef)
        case .setChapterState(let d): return hits(d.chapterRef)
        case .setPersonMood(let d): return hits(d.personRef)
        case .addCrossLink(let d): return hits(d.fromChapterRef) || hits(d.toChapterRef)
        case .fillSlots(let d): return hits(d.chapterRef)
        }
    }

    private static func normalized(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func defaultTitle(for type: ChapterType) -> String {
        switch type {
        case .relationship: "Relationship"
        case .family: "Family"
        case .friendship: "Friends"
        case .work: "Work"
        case .health: "Health"
        case .money: "Money"
        case .passion: "Passion"
        case .privateCorner: "Private corner"
        case .growth: "Growth"
        case .grief: "Grief"
        }
    }

    private static func defaultIcon(for type: ChapterType) -> String {
        switch type {
        case .relationship: "heart"
        case .family: "house"
        case .friendship: "sparkles"
        case .work: "briefcase"
        case .health: "leaf"
        case .money: "banknote"
        case .passion: "flame"
        case .privateCorner: "lock"
        case .growth: "arrow.up.forward"
        case .grief: "moon"
        }
    }

    private func isApplied(_ utteranceId: UUID) throws -> Bool {
        try !modelContext.fetch(
            FetchDescriptor<AppliedUtterance>(predicate: #Predicate { $0.utteranceId == utteranceId })
        ).isEmpty
    }

    private func allPersons() throws -> [Person] {
        try modelContext.fetch(FetchDescriptor<Person>(sortBy: [SortDescriptor(\.name)]))
    }
}

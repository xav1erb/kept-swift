import Foundation
import SwiftData

/// The data seam (C7). Owns the encrypted SwiftData store; exposes typed reads (snapshots) and
/// typed commands. Nothing outside Services/Store/ touches ModelContext or @Model types (F11).
/// The M1 merge engine will be the primary writer through this surface.
@MainActor
@Observable
final class KeptStore {

    enum Configuration {
        case live
        case onDisk(URL)
        case inMemory
    }

    enum StoreError: Error {
        case notFound(String)
    }

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init(configuration: Configuration = .live) throws {
        let schema = Schema([
            UserProfile.self, Chapter.self, Person.self, Event.self, Commitment.self,
            Goal.self, Reminder.self, NotificationPrefs.self, Achievement.self, CrossLink.self,
            AppliedUtterance.self, HeldDeltaBatch.self,
        ])
        switch configuration {
        case .live:
            let url = try Self.liveStoreURL()
            container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, url: url)]
            )
            try Self.applyFileProtection(storeURL: url)
        case .onDisk(let url):
            container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, url: url)]
            )
            try Self.applyFileProtection(storeURL: url)
        case .inMemory:
            container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
        }
    }

    // MARK: - Encryption posture (M0: the local half of C2)

    private static func liveStoreURL() throws -> URL {
        let dir = URL.applicationSupportDirectory.appending(path: "KeptStore", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "kept.store")
    }

    /// NSFileProtectionComplete on the store files. Full enforcement is device-verified;
    /// the attribute itself is asserted by tests. Master-key/E2E work is the M1/M2 seam.
    static func applyFileProtection(storeURL: URL) throws {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let path = storeURL.path + suffix
            if fm.fileExists(atPath: path) {
                try fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: path)
            }
        }
    }

    // MARK: - Reads

    /// Fetch-or-create singleton (M0-CONTRACTS §8 ruling #3).
    func userProfile() throws -> UserProfileSnapshot {
        let profile = try fetchOrCreateProfile()
        return UserProfileSnapshot(
            id: profile.id, name: profile.name, age: profile.age, pronouns: profile.pronouns,
            city: profile.city, occupation: profile.occupation, theme: profile.theme,
            voiceProfile: profile.voiceProfile, streakCount: profile.streakCount,
            streakRestDayUsed: profile.streakRestDayUsed, onboardingMode: profile.onboardingMode,
            followupQueue: profile.followupQueue
        )
    }

    func notificationPrefs() throws -> NotificationPrefsSnapshot {
        let prefs = try fetchOrCreatePrefs()
        return NotificationPrefsSnapshot(
            frequency: prefs.frequency, quietStart: prefs.quietStart, quietEnd: prefs.quietEnd,
            exemptReminderIDs: prefs.exemptReminderIDs,
            genericLockScreenCopy: prefs.genericLockScreenCopy,
            monthlyRecapEnabled: prefs.monthlyRecapEnabled
        )
    }

    func chapterSummaries() throws -> [ChapterSummary] {
        try fetchAllChapters().map { chapter in
            ChapterSummary(
                id: chapter.id, type: chapter.type, chapterKind: chapter.chapterKind,
                title: chapter.title, iconRef: chapter.iconRef, state: chapter.state,
                awarenessPct: chapter.awarenessPct, isResting: chapter.isResting,
                personIds: chapter.people.map(\.id).sorted { $0.uuidString < $1.uuidString }
            )
        }
    }

    func people() throws -> [PersonSnapshot] {
        let descriptor = FetchDescriptor<Person>(sortBy: [SortDescriptor(\.name)])
        return try context.fetch(descriptor).map { person in
            PersonSnapshot(
                id: person.id, name: person.name, relation: person.relation, mood: person.mood,
                roleFlags: person.roleFlags, rituals: person.rituals, priority: person.priority,
                notes: person.notes,
                chapterIds: person.chapters.map(\.id).sorted { $0.uuidString < $1.uuidString }
            )
        }
    }

    /// Folded events are INCLUDED here — the River/timeline renders them folded. Extraction
    /// context also includes them, flagged `isHealed` (M1-CONTRACTS §8.3 ruling), so folded
    /// memories id-match instead of duplicating.
    func events(inChapter chapterId: UUID) throws -> [EventSnapshot] {
        let descriptor = FetchDescriptor<Event>(
            predicate: #Predicate { $0.chapter?.id == chapterId },
            sortBy: [SortDescriptor(\.date)]
        )
        return try context.fetch(descriptor).map(Self.snapshot(of:))
    }

    func commitments(inChapter chapterId: UUID) throws -> [CommitmentSnapshot] {
        let descriptor = FetchDescriptor<Commitment>(
            predicate: #Predicate { $0.chapter?.id == chapterId },
            sortBy: [SortDescriptor(\.dateMade)]
        )
        return try context.fetch(descriptor).map { commitment in
            CommitmentSnapshot(
                id: commitment.id, chapterId: commitment.chapter?.id,
                personId: commitment.person?.id, text: commitment.text,
                dateMade: commitment.dateMade, status: commitment.status,
                evidenceEventIds: commitment.evidenceEvents.map(\.id).sorted { $0.uuidString < $1.uuidString }
            )
        }
    }

    func goals() throws -> [GoalSnapshot] {
        let descriptor = FetchDescriptor<Goal>(sortBy: [SortDescriptor(\.text)])
        return try context.fetch(descriptor).map { goal in
            GoalSnapshot(
                id: goal.id, chapterId: goal.chapter?.id, text: goal.text,
                targetDate: goal.targetDate, progressNote: goal.progressNote
            )
        }
    }

    func crossLinks() throws -> [CrossLinkSnapshot] {
        let descriptor = FetchDescriptor<CrossLink>(sortBy: [SortDescriptor(\.note)])
        return try context.fetch(descriptor).map { link in
            CrossLinkSnapshot(
                id: link.id, fromChapterId: link.fromChapter?.id,
                toChapterId: link.toChapter?.id, note: link.note
            )
        }
    }

    /// Minimum-necessary context for the proxy (M1-CONTRACTS §4). Folded events travel WITH
    /// `isHealed: true` (§8.3 ruling). `recentEventLimit` bounds the event window — an event id
    /// outside this window is unknown to the model, and the merge validates ids against exactly
    /// what was sent.
    func extractionContext(recentEventLimit: Int = 20) throws -> ExtractionContext {
        let people = try context.fetch(FetchDescriptor<Person>(sortBy: [SortDescriptor(\.name)]))
            .map { ExtractionContext.PersonContext(id: $0.id, name: $0.name, relation: $0.relation) }
        let chapters = try fetchAllChapters().map {
            ExtractionContext.ChapterContext(
                id: $0.id, type: $0.type, title: $0.title, state: $0.state, filledSlots: $0.filledSlots
            )
        }
        // #Predicate can't express enum equality (Store CLAUDE.md gotcha class) — filter in Swift.
        let openCommitments = try context.fetch(FetchDescriptor<Commitment>(
            sortBy: [SortDescriptor(\.dateMade)]
        ))
        .filter { $0.status == .held }
        .map {
            ExtractionContext.CommitmentContext(
                id: $0.id, personId: $0.person?.id, text: $0.text, dateMade: WireDate(date: $0.dateMade)
            )
        }
        var eventDescriptor = FetchDescriptor<Event>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        eventDescriptor.fetchLimit = recentEventLimit
        let recentEvents = try context.fetch(eventDescriptor).map {
            ExtractionContext.EventContext(
                id: $0.id, chapterId: $0.chapter?.id, title: $0.title,
                date: WireDate(date: $0.date), isOpen: $0.isOpen, isHealed: $0.isHealed
            )
        }
        return ExtractionContext(
            people: people, chapters: chapters,
            openCommitments: openCommitments, recentEvents: recentEvents
        )
    }

    // MARK: - Commands (typed mutations; the M1 merge engine builds on these)

    func setUserName(_ name: String) throws {
        let profile = try fetchOrCreateProfile()
        profile.name = name
        try context.save()
    }

    /// Structured census answers (onboarding chips/fields) write directly — C1 governs
    /// *utterances*; a chip tap is not an utterance (M1-CONTRACTS §8 amendments).
    func setUserBasics(age: Int? = nil, city: String? = nil, occupation: String? = nil) throws {
        let profile = try fetchOrCreateProfile()
        if let age { profile.age = age }
        if let city { profile.city = city }
        if let occupation { profile.occupation = occupation }
        try context.save()
    }

    func setOnboardingMode(_ mode: OnboardingMode) throws {
        let profile = try fetchOrCreateProfile()
        profile.onboardingMode = mode
        try context.save()
    }

    func setTheme(_ theme: Theme) throws {
        let profile = try fetchOrCreateProfile()
        profile.theme = theme
        try context.save()
    }

    @discardableResult
    func createChapter(
        type: ChapterType,
        chapterKind: ChapterKind,
        title: String,
        iconRef: String
    ) throws -> UUID {
        let chapter = Chapter(type: type, chapterKind: chapterKind, title: title, iconRef: iconRef)
        context.insert(chapter)
        try context.save()
        return chapter.id
    }

    @discardableResult
    func addPerson(name: String, relation: String) throws -> UUID {
        let person = Person(name: name, relation: relation)
        context.insert(person)
        try context.save()
        return person.id
    }

    func attach(personId: UUID, toChapter chapterId: UUID) throws {
        let person = try fetchPerson(personId)
        let chapter = try fetchChapter(chapterId)
        if !chapter.people.contains(where: { $0.id == personId }) {
            chapter.people.append(person)
        }
        try context.save()
    }

    @discardableResult
    func addEvent(
        chapterId: UUID,
        date: Date,
        title: String,
        body: String,
        valence: Valence,
        isOpen: Bool,
        isUpcoming: Bool,
        source: EventSource
    ) throws -> UUID {
        let chapter = try fetchChapter(chapterId)
        let event = Event(
            date: date, title: title, body: body, valence: valence,
            isOpen: isOpen, isUpcoming: isUpcoming, source: source
        )
        context.insert(event)
        event.chapter = chapter
        chapter.lastTouchedAt = .now
        try context.save()
        return event.id
    }

    @discardableResult
    func addCommitment(chapterId: UUID, personId: UUID?, text: String, dateMade: Date) throws -> UUID {
        let chapter = try fetchChapter(chapterId)
        let commitment = Commitment(text: text, dateMade: dateMade)
        context.insert(commitment)
        commitment.chapter = chapter
        if let personId {
            commitment.person = try fetchPerson(personId)
        }
        try context.save()
        return commitment.id
    }

    func addEvidence(eventId: UUID, toCommitment commitmentId: UUID) throws {
        let commitment = try fetchCommitment(commitmentId)
        let event = try fetchEvent(eventId)
        if !commitment.evidenceEvents.contains(where: { $0.id == eventId }) {
            commitment.evidenceEvents.append(event)
        }
        try context.save()
    }

    func setCommitmentStatus(_ commitmentId: UUID, status: CommitmentStatus) throws {
        let commitment = try fetchCommitment(commitmentId)
        commitment.status = status
        try context.save()
    }

    @discardableResult
    func addGoal(chapterId: UUID?, text: String, targetDate: Date?, progressNote: String) throws -> UUID {
        let goal = Goal(text: text)
        context.insert(goal)
        if let chapterId {
            goal.chapter = try fetchChapter(chapterId)
        }
        goal.targetDate = targetDate
        goal.progressNote = progressNote
        try context.save()
        return goal.id
    }

    @discardableResult
    func addCrossLink(from fromChapterId: UUID, to toChapterId: UUID, note: String) throws -> UUID {
        let link = CrossLink(note: note)
        context.insert(link)
        link.fromChapter = try fetchChapter(fromChapterId)
        link.toChapter = try fetchChapter(toChapterId)
        try context.save()
        return link.id
    }

    func setChapterState(_ chapterId: UUID, state: ChapterState) throws {
        let chapter = try fetchChapter(chapterId)
        chapter.state = state
        chapter.lastTouchedAt = .now
        try context.save()
    }

    // MARK: - Merge-engine surface (internal to Services/Store — features never touch these; the
    // C7 boundary is the folder + review, and F11 bans @Query in views regardless)

    var modelContext: ModelContext { context }

    func fetchChapterModel(_ id: UUID) throws -> Chapter { try fetchChapter(id) }
    func fetchPersonModel(_ id: UUID) throws -> Person { try fetchPerson(id) }
    func fetchEventModel(_ id: UUID) throws -> Event { try fetchEvent(id) }
    func fetchCommitmentModel(_ id: UUID) throws -> Commitment { try fetchCommitment(id) }

    func fetchGoalModel(_ id: UUID) throws -> Goal {
        let descriptor = FetchDescriptor<Goal>(predicate: #Predicate { $0.id == id })
        guard let goal = try context.fetch(descriptor).first else {
            throw StoreError.notFound("Goal \(id)")
        }
        return goal
    }

    // MARK: - Private

    private func fetchOrCreateProfile() throws -> UserProfile {
        if let existing = try context.fetch(FetchDescriptor<UserProfile>()).first {
            return existing
        }
        let profile = UserProfile()
        context.insert(profile)
        try context.save()
        return profile
    }

    private func fetchOrCreatePrefs() throws -> NotificationPrefs {
        if let existing = try context.fetch(FetchDescriptor<NotificationPrefs>()).first {
            return existing
        }
        let prefs = NotificationPrefs()
        context.insert(prefs)
        try context.save()
        return prefs
    }

    private func fetchAllChapters() throws -> [Chapter] {
        try context.fetch(FetchDescriptor<Chapter>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    private func fetchChapter(_ id: UUID) throws -> Chapter {
        let descriptor = FetchDescriptor<Chapter>(predicate: #Predicate { $0.id == id })
        guard let chapter = try context.fetch(descriptor).first else {
            throw StoreError.notFound("Chapter \(id)")
        }
        return chapter
    }

    private func fetchPerson(_ id: UUID) throws -> Person {
        let descriptor = FetchDescriptor<Person>(predicate: #Predicate { $0.id == id })
        guard let person = try context.fetch(descriptor).first else {
            throw StoreError.notFound("Person \(id)")
        }
        return person
    }

    private func fetchEvent(_ id: UUID) throws -> Event {
        let descriptor = FetchDescriptor<Event>(predicate: #Predicate { $0.id == id })
        guard let event = try context.fetch(descriptor).first else {
            throw StoreError.notFound("Event \(id)")
        }
        return event
    }

    private func fetchCommitment(_ id: UUID) throws -> Commitment {
        let descriptor = FetchDescriptor<Commitment>(predicate: #Predicate { $0.id == id })
        guard let commitment = try context.fetch(descriptor).first else {
            throw StoreError.notFound("Commitment \(id)")
        }
        return commitment
    }

    private static func snapshot(of event: Event) -> EventSnapshot {
        EventSnapshot(
            id: event.id, chapterId: event.chapter?.id, date: event.date, title: event.title,
            body: event.body, valence: event.valence, isOpen: event.isOpen,
            isHealed: event.isHealed, healedReason: event.healedReason,
            isUpcoming: event.isUpcoming, source: event.source
        )
    }
}

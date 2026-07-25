import CryptoKit
import Foundation
import SwiftData

// Export/restore between the live store and sealed blobs (M2-CONTRACTS §7.3). Restore is
// two-pass: insert every record, then re-link relationships by id. Internal to Services/Store (C7).

extension KeptStore {

    /// Every record as a sealed blob — the initial full backup after sign-in.
    func sealAllRecords(key: SymmetricKey) throws -> [EncryptedBlob] {
        var blobs: [EncryptedBlob] = []
        if let profile = try modelContext.fetch(FetchDescriptor<UserProfile>()).first {
            blobs.append(try BlobEnvelope.seal(Self.blob(of: profile), type: .userProfile, blobId: profile.id, key: key))
        }
        if let prefs = try modelContext.fetch(FetchDescriptor<NotificationPrefs>()).first {
            blobs.append(try BlobEnvelope.seal(
                Self.blob(of: prefs), type: .notificationPrefs,
                blobId: BlobRecordType.notificationPrefsSingletonId, key: key
            ))
        }
        for chapter in try modelContext.fetch(FetchDescriptor<Chapter>()) {
            blobs.append(try BlobEnvelope.seal(Self.blob(of: chapter), type: .chapter, blobId: chapter.id, key: key))
        }
        for person in try modelContext.fetch(FetchDescriptor<Person>()) {
            blobs.append(try BlobEnvelope.seal(Self.blob(of: person), type: .person, blobId: person.id, key: key))
        }
        for event in try modelContext.fetch(FetchDescriptor<Event>()) {
            blobs.append(try BlobEnvelope.seal(Self.blob(of: event), type: .event, blobId: event.id, key: key))
        }
        for commitment in try modelContext.fetch(FetchDescriptor<Commitment>()) {
            blobs.append(try BlobEnvelope.seal(Self.blob(of: commitment), type: .commitment, blobId: commitment.id, key: key))
        }
        for goal in try modelContext.fetch(FetchDescriptor<Goal>()) {
            blobs.append(try BlobEnvelope.seal(Self.blob(of: goal), type: .goal, blobId: goal.id, key: key))
        }
        for reminder in try modelContext.fetch(FetchDescriptor<Reminder>()) {
            blobs.append(try BlobEnvelope.seal(Self.blob(of: reminder), type: .reminder, blobId: reminder.id, key: key))
        }
        for achievement in try modelContext.fetch(FetchDescriptor<Achievement>()) {
            blobs.append(try BlobEnvelope.seal(Self.blob(of: achievement), type: .achievement, blobId: achievement.id, key: key))
        }
        for link in try modelContext.fetch(FetchDescriptor<CrossLink>()) {
            blobs.append(try BlobEnvelope.seal(Self.blob(of: link), type: .crossLink, blobId: link.id, key: key))
        }
        for applied in try modelContext.fetch(FetchDescriptor<AppliedUtterance>()) {
            blobs.append(try BlobEnvelope.seal(
                AppliedUtteranceBlob(utteranceId: applied.utteranceId, appliedAt: applied.appliedAt),
                type: .appliedUtterance, blobId: applied.utteranceId, key: key
            ))
        }
        for held in try modelContext.fetch(FetchDescriptor<HeldDeltaBatch>()) {
            blobs.append(try BlobEnvelope.seal(Self.blob(of: held), type: .heldDeltaBatch, blobId: held.id, key: key))
        }
        for message in try modelContext.fetch(FetchDescriptor<ChatMessage>()) {
            blobs.append(try BlobEnvelope.seal(Self.blob(of: message), type: .chatMessage, blobId: message.id, key: key))
        }
        return blobs
    }

    /// Seals exactly one record by ref — the write-behind uploader's per-row path.
    func sealRecord(type: BlobRecordType, id: UUID, key: SymmetricKey) throws -> EncryptedBlob? {
        switch type {
        case .userProfile:
            guard let profile = try modelContext.fetch(FetchDescriptor<UserProfile>()).first, profile.id == id else { return nil }
            return try BlobEnvelope.seal(Self.blob(of: profile), type: type, blobId: id, key: key)
        case .notificationPrefs:
            guard let prefs = try modelContext.fetch(FetchDescriptor<NotificationPrefs>()).first else { return nil }
            return try BlobEnvelope.seal(Self.blob(of: prefs), type: type, blobId: id, key: key)
        case .chapter:
            guard let model = try? fetchChapterModel(id) else { return nil }
            return try BlobEnvelope.seal(Self.blob(of: model), type: type, blobId: id, key: key)
        case .person:
            guard let model = try? fetchPersonModel(id) else { return nil }
            return try BlobEnvelope.seal(Self.blob(of: model), type: type, blobId: id, key: key)
        case .event:
            guard let model = try? fetchEventModel(id) else { return nil }
            return try BlobEnvelope.seal(Self.blob(of: model), type: type, blobId: id, key: key)
        case .commitment:
            guard let model = try? fetchCommitmentModel(id) else { return nil }
            return try BlobEnvelope.seal(Self.blob(of: model), type: type, blobId: id, key: key)
        case .goal:
            guard let model = try? fetchGoalModel(id) else { return nil }
            return try BlobEnvelope.seal(Self.blob(of: model), type: type, blobId: id, key: key)
        case .chatMessage:
            guard let model = try? fetchChatMessageModel(id) else { return nil }
            return try BlobEnvelope.seal(Self.blob(of: model), type: type, blobId: id, key: key)
        case .reminder, .achievement, .crossLink, .appliedUtterance, .heldDeltaBatch:
            // Not written by any M2 surface; the full-backup path covers them.
            return nil
        }
    }

    /// Rebuild an EMPTY store from opened interiors (M2-CONTRACTS §7.3 restore). Pass 1 inserts,
    /// pass 2 links by id. Any undecodable interior fails the whole restore loudly (NN#7).
    func restore(interiors unordered: [(type: BlobRecordType, interior: Data)]) throws {
        // Chapters and people first so single-pass links (goal/reminder/achievement/crossLink →
        // chapter) always resolve; events/commitments link in pass 2.
        let precedence: [BlobRecordType: Int] = [.chapter: 0, .person: 1]
        let interiors = unordered.enumerated().sorted {
            (precedence[$0.element.type] ?? 2, $0.offset) < (precedence[$1.element.type] ?? 2, $1.offset)
        }.map(\.element)
        let decoder = BlobEnvelope.decoder()
        var chapters: [UUID: Chapter] = [:]
        var people: [UUID: Person] = [:]
        var events: [UUID: Event] = [:]
        var chapterPersonLinks: [(chapter: UUID, person: UUID)] = []
        var eventChapter: [UUID: UUID] = [:]
        var commitmentLinks: [(commitment: Commitment, chapter: UUID?, person: UUID?, evidence: [UUID])] = []

        for (type, interior) in interiors {
            switch type {
            case .userProfile:
                let blob = try decoder.decode(BlobInterior<UserProfileBlob>.self, from: interior).data
                let profile = UserProfile(id: blob.id, createdAt: blob.createdAt)
                profile.name = blob.name
                profile.age = blob.age
                profile.pronouns = blob.pronouns
                profile.city = blob.city
                profile.occupation = blob.occupation
                profile.theme = blob.theme
                profile.voiceProfile = blob.voiceProfile
                profile.streakCount = blob.streakCount
                profile.streakRestDayUsed = blob.streakRestDayUsed
                profile.onboardingMode = blob.onboardingMode
                profile.followupQueue = blob.followupQueue
                profile.hasCompletedOnboarding = blob.hasCompletedOnboarding
                profile.isMinor = blob.isMinor
                profile.aiConsentGrantedAt = blob.aiConsentGrantedAt
                modelContext.insert(profile)
            case .notificationPrefs:
                let blob = try decoder.decode(BlobInterior<NotificationPrefsBlob>.self, from: interior).data
                let prefs = NotificationPrefs()
                prefs.frequency = blob.frequency
                prefs.quietStart = blob.quietStart
                prefs.quietEnd = blob.quietEnd
                prefs.exemptReminderIDs = blob.exemptReminderIDs
                prefs.genericLockScreenCopy = blob.genericLockScreenCopy
                prefs.monthlyRecapEnabled = blob.monthlyRecapEnabled
                modelContext.insert(prefs)
            case .chapter:
                let blob = try decoder.decode(BlobInterior<ChapterBlob>.self, from: interior).data
                let chapter = Chapter(
                    id: blob.id, type: blob.type, chapterKind: blob.chapterKind,
                    title: blob.title, iconRef: blob.iconRef, createdAt: blob.createdAt
                )
                chapter.state = blob.state
                chapter.awarenessPct = blob.awarenessPct
                chapter.filledSlots = blob.filledSlots
                chapter.priority = blob.priority
                chapter.isResting = blob.isResting
                chapter.closingLetter = blob.closingLetter
                chapter.lastTouchedAt = blob.lastTouchedAt
                modelContext.insert(chapter)
                chapters[blob.id] = chapter
                for personId in blob.personIds {
                    chapterPersonLinks.append((chapter: blob.id, person: personId))
                }
            case .person:
                let blob = try decoder.decode(BlobInterior<PersonBlob>.self, from: interior).data
                let person = Person(id: blob.id, name: blob.name, relation: blob.relation)
                person.age = blob.age
                person.mood = blob.mood
                person.roleFlags = blob.roleFlags
                person.rituals = blob.rituals
                person.priority = blob.priority
                person.notes = blob.notes
                modelContext.insert(person)
                people[blob.id] = person
            case .event:
                let blob = try decoder.decode(BlobInterior<EventBlob>.self, from: interior).data
                let event = Event(
                    id: blob.id, date: blob.date, title: blob.title, body: blob.body,
                    valence: blob.valence, isOpen: blob.isOpen, isUpcoming: blob.isUpcoming,
                    source: blob.source
                )
                event.isHealed = blob.isHealed
                event.healedReason = blob.healedReason
                event.preparedAt = blob.preparedAt
                event.checkInArmed = blob.checkInArmed
                modelContext.insert(event)
                events[blob.id] = event
                if let chapterId = blob.chapterId { eventChapter[blob.id] = chapterId }
            case .commitment:
                let blob = try decoder.decode(BlobInterior<CommitmentBlob>.self, from: interior).data
                let commitment = Commitment(id: blob.id, text: blob.text, dateMade: blob.dateMade)
                commitment.status = blob.status
                modelContext.insert(commitment)
                commitmentLinks.append((commitment, blob.chapterId, blob.personId, blob.evidenceEventIds))
            case .goal:
                let blob = try decoder.decode(BlobInterior<GoalBlob>.self, from: interior).data
                let goal = Goal(id: blob.id, text: blob.text)
                goal.targetDate = blob.targetDate
                goal.progressNote = blob.progressNote
                modelContext.insert(goal)
                if let chapterId = blob.chapterId { goal.chapter = chapters[chapterId] }
            case .reminder:
                let blob = try decoder.decode(BlobInterior<ReminderBlob>.self, from: interior).data
                let reminder = Reminder(id: blob.id, title: blob.title, schedule: blob.schedule)
                reminder.enabled = blob.enabled
                modelContext.insert(reminder)
                if let chapterId = blob.chapterId { reminder.chapter = chapters[chapterId] }
            case .achievement:
                let blob = try decoder.decode(BlobInterior<AchievementBlob>.self, from: interior).data
                let achievement = Achievement(id: blob.id, key: blob.key, category: blob.category, isSecret: blob.isSecret)
                achievement.earnedAt = blob.earnedAt
                achievement.progress = blob.progress
                modelContext.insert(achievement)
                if let chapterId = blob.chapterId { achievement.chapter = chapters[chapterId] }
            case .crossLink:
                let blob = try decoder.decode(BlobInterior<CrossLinkBlob>.self, from: interior).data
                let link = CrossLink(id: blob.id, note: blob.note)
                modelContext.insert(link)
                if let fromId = blob.fromChapterId { link.fromChapter = chapters[fromId] }
                if let toId = blob.toChapterId { link.toChapter = chapters[toId] }
            case .appliedUtterance:
                let blob = try decoder.decode(BlobInterior<AppliedUtteranceBlob>.self, from: interior).data
                modelContext.insert(AppliedUtterance(utteranceId: blob.utteranceId, appliedAt: blob.appliedAt))
            case .heldDeltaBatch:
                let blob = try decoder.decode(BlobInterior<HeldDeltaBatchBlob>.self, from: interior).data
                modelContext.insert(HeldDeltaBatch(
                    id: blob.id, utteranceId: blob.utteranceId, ref: blob.ref, mention: blob.mention,
                    candidateIds: blob.candidateIds, question: blob.question, deltasJSON: blob.deltasJSON,
                    bindingsJSON: blob.bindingsJSON, surfaceRaw: blob.surfaceRaw,
                    clientTime: blob.clientTime, createdAt: blob.createdAt
                ))
            case .chatMessage:
                let blob = try decoder.decode(BlobInterior<ChatMessageBlob>.self, from: interior).data
                let message = ChatMessage(
                    id: blob.id, authorRaw: blob.authorRaw, text: blob.text,
                    cardJSON: blob.cardJSON, date: blob.date
                )
                modelContext.insert(message)
                if let chapterId = blob.chapterId { message.chapter = chapters[chapterId] }
            }
        }

        // Pass 2 — links (cross-link and goal/reminder/achievement links resolved inline above
        // because chapters decode in unknown order; re-resolve any that missed).
        for (chapterId, personId) in chapterPersonLinks {
            if let chapter = chapters[chapterId], let person = people[personId],
               !chapter.people.contains(where: { $0.id == personId }) {
                chapter.people.append(person)
            }
        }
        for (eventId, chapterId) in eventChapter {
            events[eventId]?.chapter = chapters[chapterId]
        }
        for link in commitmentLinks {
            if let chapterId = link.chapter { link.commitment.chapter = chapters[chapterId] }
            if let personId = link.person { link.commitment.person = people[personId] }
            link.commitment.evidenceEvents = link.evidence.compactMap { events[$0] }
        }
        try modelContext.save()
    }

    // MARK: - Model → payload

    private static func blob(of profile: UserProfile) -> UserProfileBlob {
        UserProfileBlob(
            id: profile.id, name: profile.name, age: profile.age, pronouns: profile.pronouns,
            city: profile.city, occupation: profile.occupation, theme: profile.theme,
            voiceProfile: profile.voiceProfile, streakCount: profile.streakCount,
            streakRestDayUsed: profile.streakRestDayUsed, onboardingMode: profile.onboardingMode,
            followupQueue: profile.followupQueue,
            hasCompletedOnboarding: profile.hasCompletedOnboarding, isMinor: profile.isMinor,
            aiConsentGrantedAt: profile.aiConsentGrantedAt, createdAt: profile.createdAt
        )
    }

    private static func blob(of prefs: NotificationPrefs) -> NotificationPrefsBlob {
        NotificationPrefsBlob(
            frequency: prefs.frequency, quietStart: prefs.quietStart, quietEnd: prefs.quietEnd,
            exemptReminderIDs: prefs.exemptReminderIDs,
            genericLockScreenCopy: prefs.genericLockScreenCopy,
            monthlyRecapEnabled: prefs.monthlyRecapEnabled
        )
    }

    private static func blob(of chapter: Chapter) -> ChapterBlob {
        ChapterBlob(
            id: chapter.id, type: chapter.type, chapterKind: chapter.chapterKind,
            title: chapter.title, iconRef: chapter.iconRef, state: chapter.state,
            awarenessPct: chapter.awarenessPct, filledSlots: chapter.filledSlots,
            priority: chapter.priority, isResting: chapter.isResting,
            closingLetter: chapter.closingLetter, createdAt: chapter.createdAt,
            lastTouchedAt: chapter.lastTouchedAt,
            personIds: chapter.people.map(\.id).sorted { $0.uuidString < $1.uuidString }
        )
    }

    private static func blob(of person: Person) -> PersonBlob {
        PersonBlob(
            id: person.id, name: person.name, relation: person.relation, age: person.age,
            mood: person.mood, roleFlags: person.roleFlags, rituals: person.rituals,
            priority: person.priority, notes: person.notes
        )
    }

    private static func blob(of event: Event) -> EventBlob {
        EventBlob(
            id: event.id, chapterId: event.chapter?.id, date: event.date, title: event.title,
            body: event.body, valence: event.valence, isOpen: event.isOpen,
            isHealed: event.isHealed, healedReason: event.healedReason,
            isUpcoming: event.isUpcoming, source: event.source,
            preparedAt: event.preparedAt, checkInArmed: event.checkInArmed
        )
    }

    private static func blob(of message: ChatMessage) -> ChatMessageBlob {
        ChatMessageBlob(
            id: message.id, chapterId: message.chapter?.id, authorRaw: message.authorRaw,
            text: message.text, cardJSON: message.cardJSON, date: message.date
        )
    }

    private static func blob(of commitment: Commitment) -> CommitmentBlob {
        CommitmentBlob(
            id: commitment.id, chapterId: commitment.chapter?.id, personId: commitment.person?.id,
            text: commitment.text, dateMade: commitment.dateMade, status: commitment.status,
            evidenceEventIds: commitment.evidenceEvents.map(\.id).sorted { $0.uuidString < $1.uuidString }
        )
    }

    private static func blob(of goal: Goal) -> GoalBlob {
        GoalBlob(id: goal.id, chapterId: goal.chapter?.id, text: goal.text, targetDate: goal.targetDate, progressNote: goal.progressNote)
    }

    private static func blob(of reminder: Reminder) -> ReminderBlob {
        ReminderBlob(id: reminder.id, chapterId: reminder.chapter?.id, title: reminder.title, schedule: reminder.schedule, enabled: reminder.enabled)
    }

    private static func blob(of achievement: Achievement) -> AchievementBlob {
        AchievementBlob(
            id: achievement.id, key: achievement.key, category: achievement.category,
            chapterId: achievement.chapter?.id, earnedAt: achievement.earnedAt,
            progress: achievement.progress, isSecret: achievement.isSecret
        )
    }

    private static func blob(of link: CrossLink) -> CrossLinkBlob {
        CrossLinkBlob(id: link.id, fromChapterId: link.fromChapter?.id, toChapterId: link.toChapter?.id, note: link.note)
    }

    private static func blob(of held: HeldDeltaBatch) -> HeldDeltaBatchBlob {
        HeldDeltaBatchBlob(
            id: held.id, utteranceId: held.utteranceId, ref: held.ref, mention: held.mention,
            candidateIds: held.candidateIds, question: held.question, deltasJSON: held.deltasJSON,
            bindingsJSON: held.bindingsJSON, surfaceRaw: held.surfaceRaw,
            clientTime: held.clientTime, createdAt: held.createdAt
        )
    }
}

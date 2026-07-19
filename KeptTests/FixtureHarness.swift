import Foundation
import Testing
@testable import Kept

/// Drives the transcript-fixture corpus (extraction.md §5) through the REAL pipeline tail:
/// context built from the live store → strict envelope decode → deterministic merge. Only the
/// network/model is faked — by the fixture envelope itself (fake the source, never the shape).
///
/// Fixture envelopes may reference entities created by earlier steps via tokens, resolved
/// against the store at step time (runtime UUIDs can't live in checked-in JSON):
///   "$person:Daniel"            unique person by name
///   "$person:Sara/colleague"    person by name + relation
///   "$chapter:Work"             chapter by title
///   "$event:The promise"        event by title
///   "$commitment:no following girls"  commitment by text
@MainActor
final class FixtureHarness {
    let store: KeptStore

    struct Step {
        let surface: Surface
        let clientTime: Date
        let envelopeJSON: [String: Any]
        let resolutions: [Resolution]
    }

    struct Resolution {
        let mention: String
        let chooseExisting: String?   // token; nil = confirmed-new person
    }

    enum HarnessError: Error {
        case fixtureNotFound(String)
        case malformed(String)
        case tokenUnresolved(String)
        case tokenAmbiguous(String)
    }

    init() throws {
        store = try KeptStore(configuration: .inMemory)
    }

    // MARK: - Loading

    private static func fixtureData(_ name: String) throws -> [String: Any] {
        guard let url = Bundle(for: FixtureHarness.self).url(forResource: name, withExtension: "json") else {
            throw HarnessError.fixtureNotFound(name)
        }
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        guard let dictionary = object as? [String: Any] else {
            throw HarnessError.malformed("\(name): top level is not an object")
        }
        return dictionary
    }

    func steps(named name: String) throws -> [Step] {
        let fixture = try Self.fixtureData(name)

        if let profile = fixture["profile"] as? [String: Any] {
            if let userName = profile["name"] as? String { try store.setUserName(userName) }
            if let mode = (profile["onboardingMode"] as? String).flatMap(OnboardingMode.init) {
                try store.setOnboardingMode(mode)
            }
            try store.setUserBasics(
                age: profile["age"] as? Int,
                city: profile["city"] as? String,
                occupation: profile["occupation"] as? String
            )
        }

        let formatter = ISO8601DateFormatter()
        return try (fixture["steps"] as? [[String: Any]] ?? []).map { raw in
            guard let surface = (raw["surface"] as? String).flatMap(Surface.init),
                  let clientTime = (raw["clientTime"] as? String).flatMap(formatter.date(from:)),
                  let envelope = raw["envelope"] as? [String: Any]
            else {
                throw HarnessError.malformed("\(name): step missing surface/clientTime/envelope")
            }
            let resolutions = (raw["resolutions"] as? [[String: Any]] ?? []).map {
                Resolution(
                    mention: $0["mention"] as? String ?? "",
                    chooseExisting: $0["person"] as? String
                )
            }
            return Step(
                surface: surface, clientTime: clientTime,
                envelopeJSON: envelope, resolutions: resolutions
            )
        }
    }

    /// fx-010's hostile envelopes: name → raw JSON data, no token substitution.
    static func poisonedEnvelopes(named name: String) throws -> [String: Data] {
        let fixture = try fixtureData(name)
        guard let poisoned = fixture["poisoned"] as? [String: Any] else {
            throw HarnessError.malformed("\(name): no 'poisoned' object")
        }
        return try poisoned.mapValues { try JSONSerialization.data(withJSONObject: $0) }
    }

    // MARK: - Running

    @discardableResult
    func apply(_ step: Step) throws -> FilingSummary {
        let sentContext = try store.extractionContext()
        // .withoutEscapingSlashes: "$person:Sara/colleague" must survive re-serialization intact.
        let substituted = try substituteTokens(
            in: String(
                data: JSONSerialization.data(
                    withJSONObject: step.envelopeJSON, options: [.withoutEscapingSlashes]
                ),
                encoding: .utf8
            )!
        )
        let envelope = try JSONDecoder().decode(ExtractionEnvelope.self, from: Data(substituted.utf8))
        var summary = try store.applyExtraction(
            envelope, sentContext: sentContext, surface: step.surface, clientTime: step.clientTime
        )
        for resolution in step.resolutions {
            guard let pending = try store.pendingDisambiguations()
                .first(where: { $0.mention == resolution.mention }) else {
                throw HarnessError.malformed("No pending disambiguation for '\(resolution.mention)'")
            }
            let outcome: PersonResolution
            if let token = resolution.chooseExisting {
                outcome = .existing(try resolveToken(token))
            } else {
                outcome = .newPerson
            }
            summary = try store.resolveDisambiguation(batchId: pending.id, resolution: outcome)
        }
        return summary
    }

    @discardableResult
    func run(_ name: String) throws -> [FilingSummary] {
        try steps(named: name).map { try apply($0) }
    }

    // MARK: - Tokens

    private func substituteTokens(in json: String) throws -> String {
        var result = json
        // JSONSerialization escapes nothing we use in tokens; tokens are whole string values.
        let pattern = #/\$(person|chapter|event|commitment):[^"]+/#
        while let match = result.firstMatch(of: pattern) {
            let token = String(match.output.0)
            let id = try resolveToken(token)
            result = result.replacingOccurrences(of: token, with: id.uuidString)
        }
        return result
    }

    func resolveToken(_ token: String) throws -> UUID {
        let parts = token.dropFirst().split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { throw HarnessError.malformed("Bad token '\(token)'") }
        let kind = String(parts[0])
        let key = String(parts[1])

        let matches: [UUID]
        switch kind {
        case "person":
            let nameAndRelation = key.split(separator: "/", maxSplits: 1)
            let name = String(nameAndRelation[0])
            let relation = nameAndRelation.count == 2 ? String(nameAndRelation[1]) : nil
            matches = try store.people()
                .filter { $0.name == name && (relation == nil || $0.relation == relation) }
                .map(\.id)
        case "chapter":
            matches = try store.chapterSummaries().filter { $0.title == key }.map(\.id)
        case "event":
            matches = try allEvents().filter { $0.title == key }.map(\.id)
        case "commitment":
            matches = try allCommitments().filter { $0.text == key }.map(\.id)
        default:
            throw HarnessError.malformed("Unknown token kind '\(kind)'")
        }

        guard let id = matches.first else { throw HarnessError.tokenUnresolved(token) }
        guard matches.count == 1 else { throw HarnessError.tokenAmbiguous(token) }
        return id
    }

    // MARK: - Whole-store reads for assertions

    func allEvents() throws -> [EventSnapshot] {
        try store.chapterSummaries().flatMap { try store.events(inChapter: $0.id) }
    }

    func allCommitments() throws -> [CommitmentSnapshot] {
        try store.chapterSummaries().flatMap { try store.commitments(inChapter: $0.id) }
    }

    /// One comparable value of everything a user could ever read back — fx-009's replay assert.
    func worldSnapshot() throws -> String {
        let chapters = try store.chapterSummaries()
        var parts: [String] = ["\(try store.userProfile())", "\(chapters)", "\(try store.people())"]
        for chapter in chapters {
            parts.append("\(try store.events(inChapter: chapter.id))")
            parts.append("\(try store.commitments(inChapter: chapter.id))")
        }
        parts.append("\(try store.goals())")
        parts.append("\(try store.crossLinks())")
        parts.append("\(try store.pendingDisambiguations())")
        return parts.joined(separator: "\n")
    }
}

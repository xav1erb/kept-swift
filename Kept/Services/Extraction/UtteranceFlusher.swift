import Dependencies
import Foundation

// The §8.1 flush (M2-CONTRACTS §7.1): after first sign-in, pending utterances drain FIFO through
// the M1 pipeline — context is assembled fresh per utterance (earlier filings enrich later
// context, exactly as live extraction would), the envelope merges atomically, and only then is
// the row removed. A crash between apply and remove replays as a no-op (AppliedUtterance gate).

@Observable
final class UtteranceFlusher {
    struct FlushResult: Equatable {
        var summaries: [FilingSummary] = []
        var pendingQuestions: [PendingDisambiguation] = []
        /// utteranceIds that failed extraction (kept in the queue for retry).
        var failedUtteranceIds: [UUID] = []
    }

    enum Phase: Equatable {
        case idle
        case flushing(done: Int, total: Int)
    }

    private(set) var phase: Phase = .idle

    private let store: KeptStore
    private let extraction: any ExtractionServicing

    init(store: KeptStore, extraction: any ExtractionServicing) {
        self.store = store
        self.extraction = extraction
    }

    /// Drains the queue in order. Transport/proxy failures keep the row queued and are reported —
    /// filing may lag, it never silently drops (NN#7: a swallowed delta is a lost piece of
    /// someone's life).
    func flush() async -> FlushResult {
        var result = FlushResult()
        guard let pending = try? store.pendingUtterances(), !pending.isEmpty else { return result }
        phase = .flushing(done: 0, total: pending.count)

        for (index, utterance) in pending.enumerated() {
            guard let surface = Surface(rawValue: utterance.surfaceRaw) else {
                result.failedUtteranceIds.append(utterance.utteranceId)
                continue
            }
            do {
                let context = try store.extractionContext(openChapterId: utterance.chapterId)
                let request = ExtractionRequest(
                    utteranceId: utterance.utteranceId,
                    surface: surface,
                    clientTime: utterance.clientTime,
                    locale: Locale.current.identifier,
                    utterance: utterance.text,
                    context: context
                )
                let envelope = try await extraction.extract(request)
                let summary = try store.applyExtraction(
                    envelope, sentContext: context, surface: surface, clientTime: utterance.clientTime
                )
                result.summaries.append(summary)
                try store.removePendingUtterance(utterance.utteranceId)
            } catch {
                result.failedUtteranceIds.append(utterance.utteranceId)
            }
            phase = .flushing(done: index + 1, total: pending.count)
        }

        result.pendingQuestions = (try? store.pendingDisambiguations()) ?? []
        phase = .idle
        return result
    }
}

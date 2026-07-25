import Foundation
import Observation

/// The composition root's network clients, passed down the environment so per-chapter models
/// (constructed lazily by their views) get the SAME instances the singleton models got in init.
/// Unconfigured until AppSecrets carries the anon key — every surface stays honestly offline.
@Observable
@MainActor
final class AppClients {
    let chat: any ChatServicing
    let extraction: any ExtractionServicing

    init(chat: any ChatServicing, extraction: any ExtractionServicing) {
        self.chat = chat
        self.extraction = extraction
    }
}

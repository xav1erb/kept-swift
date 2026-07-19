import Foundation
import Testing
@testable import Kept

/// C2/C5 audits as tests (M1-CONTRACTS §7.6): the app target must never contain an Anthropic
/// key, a direct Anthropic endpoint, a pinned model id, or prompt text — prompts are assembled
/// server-side, keys live only in Supabase secrets.
struct PrivacyAuditTests {

    @Test func appTargetCarriesNoKeysEndpointsModelIdsOrPrompts() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // KeptTests/
            .deletingLastPathComponent()   // repo root
        let appSources = repoRoot.appending(path: "Kept")
        #expect(FileManager.default.fileExists(atPath: appSources.path))

        let forbidden = [
            "api.anthropic.com",   // C5: the proxy owns AI — no direct calls
            "sk-ant",              // C2/C5: no key material, ever
            "x-api-key",
            "anthropic-version",
            "claude-haiku",        // model ids are server env config (§8.1 ruling)
            "claude-sonnet",
            "You are Pom",         // prompt text lives in prompts/, assembled server-side
        ]

        var offenders: [String] = []
        let enumerator = try #require(FileManager.default.enumerator(
            at: appSources, includingPropertiesForKeys: nil
        ))
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for needle in forbidden where text.contains(needle) {
                offenders.append("\(url.lastPathComponent) contains '\(needle)'")
            }
        }
        #expect(offenders.isEmpty, "C2/C5 audit failed: \(offenders)")

        // Prompt templates live in prompts/ (repo) + the deployed function — never in the app.
        #expect(!FileManager.default.fileExists(atPath: appSources.appending(path: "prompts").path))
    }
}

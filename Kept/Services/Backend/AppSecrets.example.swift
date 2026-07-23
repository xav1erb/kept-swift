import Foundation

// TEMPLATE — copy to Kept/Services/Backend/AppSecrets.swift (gitignored) and fill in the anon
// key from the Supabase dashboard (docs/PROVISIONING.md item 1.4). The anon key is a publishable
// client key protected by RLS — it still stays out of the repo by house rule. This example file
// is excluded from the build (project.yml).

nonisolated enum AppSecrets {
    static let supabaseURL = URL(string: "https://biwwvntcofpjjbqvfkby.supabase.co")!
    /// Empty = the app runs fully local; sign-in surfaces "not configured yet".
    static let supabaseAnonKey = ""
}

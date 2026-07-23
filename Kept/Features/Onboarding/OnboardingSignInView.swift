import AuthenticationServices
import CryptoKit
import SwiftUI

// 4.11 — sign-in, required, last thing asked of her (copy verbatim; §8.1 note: worldGenerating
// follows). Apple primary; magic link via kept://auth-callback. Loading/failed states ship
// (NN#6); unconfigured builds say so honestly instead of a dead button.

struct OnboardingSignInView: View {
    @Environment(OnboardingModel.self) private var model
    @Environment(ThemeModel.self) private var themeModel
    @State private var email = ""
    @State private var rawNonce = ""

    var body: some View {
        let tokens = themeModel.tokens
        VStack(spacing: 18) {
            Text("One last thing — a sign-in. Not so anyone can see your world (they can't — it's encrypted), but so you never lose it. New phone, lost phone — your story follows you. Still yours alone. Still sealed. Still deletable in one tap, forever, whenever you want.")
                .font(KeptFont.ui(16))
                .foregroundStyle(tokens.ink)
                .multilineTextAlignment(.leading)
            Spacer()
            switch model.signInPhase {
            case .working:
                ProgressView()
            case .linkSent:
                Text("Check your email — the link brings you right back here.")
                    .font(KeptFont.ui(15))
                    .foregroundStyle(tokens.inkSoft)
            case .failed(let message):
                Text(message)
                    .font(KeptFont.ui(14))
                    .foregroundStyle(tokens.inkSoft)
            case .idle:
                EmptyView()
            }
            SignInWithAppleButton(.continue) { request in
                rawNonce = Self.randomNonce()
                request.requestedScopes = []
                request.nonce = Self.sha256(rawNonce)
            } onCompletion: { result in
                if case .success(let authorization) = result,
                   let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                   let tokenData = credential.identityToken,
                   let idToken = String(data: tokenData, encoding: .utf8) {
                    let nonce = rawNonce
                    Task { await model.signInWithApple(idToken: idToken, nonce: nonce) }
                }
            }
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.radiusSmall))
            HStack(spacing: 10) {
                TextField("your@email.com", text: $email)
                    .font(KeptFont.ui(16))
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(tokens.card.opacity(tokens.cardOpacity))
                    .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.radiusSmall))
                Button {
                    Task { await model.sendMagicLink(email: email) }
                } label: {
                    Text("🔑 Email me a link")
                        .font(KeptFont.ui(15))
                        .foregroundStyle(tokens.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(tokens.card.opacity(tokens.cardOpacity))
                        .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.radiusSmall))
                }
                .disabled(email.isEmpty)
            }
            Text("Your sign-in is a key, not an identity — it unlocks your world, it never exposes it.")
                .font(KeptFont.ui(12))
                .foregroundStyle(tokens.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }

    private static func randomNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

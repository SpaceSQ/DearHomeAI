import SwiftUI
import AuthenticationServices

/// Shown when the account is signed out or freshly deleted. Signing in with Apple re-enters the
/// existing profile (after sign-out) or starts a brand-new one (after deletion).
struct AccountGateView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @State private var signInError: String?

    var body: some View {
        let paper = PaperPalette.resolve(scheme)
        let language = model.resolvedLanguage
        VStack(spacing: 24) {
            Spacer()

            HomeSpiritFaceView(state: .idle, size: 168)

            Text("Dear Home AI")
                .font(.system(.largeTitle, design: .serif))
                .foregroundStyle(paper.ink)

            Text(tr(
                "Sign in with Apple to give this house a private profile on this iPhone. Your rooms, memories, and family queue stay only on this device.",
                "使用 Apple 登录，让这所房子在这台 iPhone 上拥有一份私密的用户档案。你的房间、记忆与家庭队列都只留在这台设备上。",
                language: language
            ))
            .font(.subheadline)
            .foregroundStyle(paper.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)

            SignInWithAppleButton(
                .signIn,
                onRequest: { request in
                    request.requestedScopes = [.fullName, .email]
                },
                onCompletion: { result in
                    handleCompletion(result, language: language)
                }
            )
            .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
            .frame(height: 50)
            .frame(maxWidth: 340)
            .padding(.horizontal, 32)
            .accessibilityIdentifier("account.signInWithApple")

            if let signInError {
                Text(signInError)
                    .font(.footnote)
                    .foregroundStyle(paper.terracotta)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .notebookBackground()
    }

    private func handleCompletion(_ result: Result<ASAuthorization, Error>, language: ContentLanguage) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                signInError = tr("Apple did not return a credential.", "Apple 没有返回凭证。", language: language)
                return
            }
            signInError = nil
            let authorizationCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            model.bindAccount(
                appleUserID: credential.user,
                givenName: credential.fullName?.givenName,
                familyName: credential.fullName?.familyName,
                email: credential.email,
                authorizationCode: authorizationCode
            )
        case .failure(let error):
            let ns = error as NSError
            if ns.code == ASAuthorizationError.canceled.rawValue {
                signInError = nil
            } else {
                signInError = tr("Sign in failed: \(error.localizedDescription)",
                                 "登录失败：\(error.localizedDescription)", language: language)
            }
        }
    }
}

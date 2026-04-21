import SwiftUI
import AuthenticationServices
import OSLog

/// Sign-in step in the onboarding flow.
///
/// Uses Apple's `SignInWithAppleButton` (System-style) because:
///   • Zero password UX — Apple owns the credential store.
///   • No email / name collection on CarCam's side — Apple anonymises at
///     the user's option, and the backend only stores the stable
///     `applePrincipalId`. Privacy-wins + App Store policy wins.
///
/// A "Continue without account" escape keeps the flow open for drivers
/// who just want local dashcam recording (they stay on FREE tier, no
/// cloud sync, no server-side incident reports). They can sign in later
/// from Settings.
struct SignInView: View {
    @Environment(DependencyContainer.self) private var container

    let onSignedIn: () -> Void
    let onSkipped: () -> Void

    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        OnboardingFrame(step: 2, total: 6) {
            heroIcon
                .padding(.vertical, CCTheme.Space.md)

            OnboardingTitle(
                eyebrow: nil,
                title: "Sign in with Apple.",
                subtitle: "Signing in roams your clips, incident reports, and preferences across all your devices. We never see your email unless you choose to share it."
            )

            benefitList
        } footer: {
            VStack(spacing: CCTheme.Space.sm) {
                signInButton

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(CCTheme.red)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }

                OnboardingSecondaryButton(title: "Continue without account") {
                    onSkipped()
                }
                .disabled(isWorking)
            }
        }
    }

    // MARK: - Sections

    private var heroIcon: some View {
        Image(systemName: "person.badge.shield.checkmark.fill")
            .font(.system(size: 72, weight: .ultraLight))
            .foregroundStyle(CCTheme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var benefitList: some View {
        VStack(alignment: .leading, spacing: CCTheme.Space.md) {
            benefit(
                icon: "icloud.fill",
                title: "Cross-device sync",
                body: "Clips, incident reports, and settings follow your Apple ID."
            )
            benefit(
                icon: "hand.raised.fill",
                title: "Private by design",
                body: "Video never leaves your device unless you enable cloud backup."
            )
            benefit(
                icon: "shield.lefthalf.filled",
                title: "Proof-of-custody",
                body: "Incident-report PDFs are cryptographically signed on the server."
            )
        }
    }

    private func benefit(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: CCTheme.Space.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(CCTheme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(body)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Sign-in button

    private var signInButton: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            handleCompletion(result)
        }
        .signInWithAppleButtonStyle(.black)
        .frame(height: 52)
        .cornerRadius(CCTheme.radiusButton)
        .disabled(isWorking)
        .opacity(isWorking ? 0.5 : 1.0)
    }

    // MARK: - Sign-in handling

    private func handleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            // `ASAuthorizationError.canceled` isn't really a failure — the
            // user closed the sheet, leave them on this screen silently.
            if let asError = error as? ASAuthorizationError, asError.code == .canceled {
                return
            }
            errorMessage = error.localizedDescription
            AppLogger.ui.error("Sign in with Apple failed: \(error.localizedDescription)")

        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let identityTokenData = credential.identityToken,
                let identityToken = String(data: identityTokenData, encoding: .utf8)
            else {
                errorMessage = "Apple didn't return a valid identity token."
                return
            }

            let displayName = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)

            isWorking = true
            errorMessage = nil

            Task {
                defer { isWorking = false }
                do {
                    _ = try await container.apiClient.signInWithApple(
                        identityToken: identityToken,
                        displayName: displayName.isEmpty ? nil : displayName
                    )
                    EntitlementStore.shared.markSignedIn()
                    // Best-effort pull of current subscription so the paywall
                    // accurately reflects existing entitlements for returning
                    // users (e.g. they subscribed on another device).
                    await EntitlementStore.shared.refresh()
                    onSignedIn()
                } catch {
                    errorMessage = "Sign-in failed. \(error.localizedDescription)"
                    AppLogger.ui.error("APIClient.signInWithApple failed: \(error.localizedDescription)")
                }
            }
        }
    }
}

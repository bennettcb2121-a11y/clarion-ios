import Foundation
import SwiftUI

/// Ask Clarion transcript + send loop. The server holds no history (POST /api/chat is
/// stateless), so this store IS the conversation: turns persist locally in UserDefaults
/// and replay to the API as conversationHistory on every send.
@MainActor
final class AssistantStore: ObservableObject {

    struct Turn: Codable, Identifiable, Equatable {
        enum Role: String, Codable {
            case user, assistant
            /// Local-only rows (rate-limit / outage notices) — never sent to the API.
            case notice
        }
        var id: UUID = UUID()
        var role: Role
        var content: String
    }

    @Published private(set) var turns: [Turn] = []
    @Published private(set) var thinking = false
    /// 403 consent_required — render the inline consent card instead of the input row.
    @Published private(set) var needsConsent = false
    @Published private(set) var grantingConsent = false

    private let auth: SupabaseAuth
    /// Fresh snapshot per send so mid-session report loads are picked up.
    private let snapshotProvider: () -> String?
    /// The message that hit the consent wall — retried after a successful grant.
    private var pendingMessage: String?

    private static let storageKey = "clarion_chat_transcript_v1"
    private static let maxStoredTurns = 40
    private static let historyTurnsSent = 12

    init(auth: SupabaseAuth, snapshotProvider: @escaping () -> String?) {
        self.auth = auth
        self.snapshotProvider = snapshotProvider
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode([Turn].self, from: data) {
            turns = stored
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("UITEST_VITALS"), turns.isEmpty {
            turns = Self.demoTranscript
        }
        #endif
    }

    func send(_ text: String) async {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !thinking else { return }

        append(Turn(role: .user, content: message))
        thinking = true
        defer { thinking = false }

        await deliver(message)
    }

    /// Grant ai_processing consent (bearer-ready POST /api/consents/record), then retry
    /// the message that was blocked.
    func grantConsentAndRetry() async {
        guard !grantingConsent else { return }
        grantingConsent = true
        defer { grantingConsent = false }
        do {
            let token = try await auth.validAccessToken()
            try await ClarionAPI.recordConsent(type: "ai_processing", accessToken: token)
            needsConsent = false
            if let pending = pendingMessage {
                pendingMessage = nil
                thinking = true
                defer { thinking = false }
                await deliver(pending)
            }
        } catch {
            append(Turn(role: .notice, content: "Couldn't turn on AI insights — \(error.localizedDescription)"))
        }
    }

    func clear() {
        turns = []
        persist()
    }

    // MARK: - Internals

    private func deliver(_ message: String) async {
        do {
            let token = try await auth.validAccessToken()
            let history = turns
                .filter { $0.role != .notice }
                .dropLast() // the message being sent is already appended locally
                .suffix(Self.historyTurnsSent)
                .map { ChatWireTurn(role: $0.role.rawValue, content: $0.content) }
            let reply = try await ClarionAPI.chat(
                message: message,
                biomarkerSnapshot: snapshotProvider(),
                conversationHistory: Array(history),
                accessToken: token
            )
            needsConsent = false
            append(Turn(role: .assistant, content: reply))
        } catch ClarionAPI.APIError.consentRequired {
            pendingMessage = message
            needsConsent = true
        } catch ClarionAPI.APIError.http(let code, let msg) {
            // Honest error rows — the transcript never pretends a reply happened.
            let text: String
            switch code {
            case 429: text = "Too many messages — wait a minute and try again."
            case 503: text = "The assistant isn't configured right now. Try again later."
            case 500...599: text = "The assistant is temporarily unavailable. Try again in a bit."
            default: text = msg
            }
            append(Turn(role: .notice, content: text))
        } catch {
            append(Turn(role: .notice, content: "Couldn't reach Clarion — check your connection and try again."))
        }
    }

    private func append(_ turn: Turn) {
        turns.append(turn)
        if turns.count > Self.maxStoredTurns {
            turns.removeFirst(turns.count - Self.maxStoredTurns)
        }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(turns) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    #if DEBUG
    /// Screenshot-harness transcript — same demo persona as ReportStore.demo.
    static let demoTranscript: [Turn] = [
        Turn(role: .user, content: "My ferritin came back at 34 — should I be worried?"),
        Turn(
            role: .assistant,
            content: "A ferritin of 34 ng/mL sits inside most lab reference ranges, so on a standard slip it reads as \"normal.\" For an endurance athlete, though, many practitioners like to see iron stores closer to 50+ because training turnover and foot-strike losses drain them faster.\n\nIn general terms: levels in the 30s can go along with slower recovery and flatter energy even without anemia. Reasonable follow-ups people discuss with their clinician include a full iron panel, dietary iron timing (away from coffee and tea), and a retest in 8–10 weeks since ferritin moves slowly.\n\nThis is education, not a diagnosis — your clinician can weigh your full picture."
        ),
    ]
    #endif
}

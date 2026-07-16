import SwiftUI

/// The customizable cards on Home, below the fixed Brief hero. The Brief (eyebrow + insight
/// sentence) is deliberately NOT in this list — it's the fixed star of the screen. Order and
/// visibility are persona-defaulted and user-overridable (see `HomeLayoutStore`).
enum HomeCard: String, CaseIterable, Codable, Identifiable {
    case feeling
    case metrics
    case run
    case victory
    case doses
    case countdown
    case nudge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .feeling: return "How you feel"
        case .metrics: return "Metric row"
        case .run: return "Recent run"
        case .victory: return "Progress card"
        case .doses: return "Today's doses"
        case .countdown: return "Next-draw countdown"
        case .nudge: return "Daily nudge"
        }
    }

    var caption: String {
        switch self {
        case .feeling: return "A daily check-in — drives readiness when your wearable's quiet"
        case .metrics: return "Your key numbers, tuned to your goal"
        case .run: return "Your latest training session"
        case .victory: return "The biggest movement across draws"
        case .doses: return "Log today's protocol"
        case .countdown: return "Protocol days banked until your retest"
        case .nudge: return "One suggestion, once a day"
        }
    }

    /// The smart default — persona sets the starting order (mirrors how the web dashboard is
    /// "tuned for endurance"). Athletes lead with today's protocol adherence under the metric
    /// row; progress/trend-forward personas lead with the victory card. A user override wins.
    static func defaultOrder(for persona: Persona) -> [HomeCard] {
        switch persona {
        case .endurance, .strength:
            // Athletes lead with the daily self-check + their numbers + last session, then
            // adherence and progress. The feeling check-in sits up top so it's the first tap.
            return [.feeling, .metrics, .run, .doses, .victory, .countdown, .nudge]
        case .menopause, .general:
            return [.feeling, .metrics, .victory, .doses, .countdown, .nudge, .run]
        }
    }
}

/// Persists the Home layout locally, keyed by user id (server-sync — the vitals_widgets model —
/// is the follow-up). The stored value is the ordered list of VISIBLE cards; a hidden card is
/// simply absent, exactly like the Vitals CustomizeSheet's widget-key convention.
@MainActor
final class HomeLayoutStore: ObservableObject {
    @Published private(set) var order: [HomeCard]

    private let persona: Persona
    private let storeKey: String

    init(persona: Persona, userId: String?) {
        self.persona = persona
        self.storeKey = "clarion_home_layout_v1_\(userId ?? "demo")"
        if let raw = UserDefaults.standard.array(forKey: storeKey) as? [String], !raw.isEmpty {
            self.order = raw.compactMap { HomeCard(rawValue: $0) }
        } else {
            self.order = HomeCard.defaultOrder(for: persona)
        }
    }

    /// Cards not in the visible order — the "hidden" section of the Customize sheet.
    var hidden: [HomeCard] { HomeCard.allCases.filter { !order.contains($0) } }

    func apply(_ newOrder: [HomeCard]) {
        order = newOrder
        UserDefaults.standard.set(newOrder.map(\.rawValue), forKey: storeKey)
    }

    /// Back to the persona default — clears the local override.
    func reset() {
        UserDefaults.standard.removeObject(forKey: storeKey)
        order = HomeCard.defaultOrder(for: persona)
    }
}

/// Rearrange + show/hide the Home cards. Modeled on `Vitals/CustomizeSheet.swift`: drag to
/// reorder, minus to hide, plus to show. The Brief hero is pinned and shown as a locked row so
/// it's clear it can't be moved.
struct HomeCustomizeSheet: View {
    @ObservedObject var store: HomeLayoutStore
    @Environment(\.dismiss) private var dismiss

    @State private var order: [HomeCard] = []

    private var hidden: [HomeCard] { HomeCard.allCases.filter { !order.contains($0) } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill").foregroundStyle(Color.ink4)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Today").font(.clarionDisplay(15)).foregroundStyle(Color.ink)
                            Text("Your day at a glance — always at the top")
                                .font(.clarionBody(12)).foregroundStyle(Color.ink3)
                        }
                    }
                } header: {
                    Text("Pinned")
                }

                Section {
                    ForEach(order) { card in
                        HStack(spacing: 12) {
                            Image(systemName: "line.3.horizontal").foregroundStyle(Color.ink4)
                            cardLabel(card)
                            Spacer()
                            Button {
                                Haptics.tap()
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    order.removeAll { $0 == card }
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(Color.clay.opacity(0.85))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .onMove { from, to in
                        Haptics.selection()
                        order.move(fromOffsets: from, toOffset: to)
                    }
                } header: {
                    Text("Your Home — drag to reorder")
                }

                if !hidden.isEmpty {
                    Section {
                        ForEach(hidden) { card in
                            HStack(spacing: 12) {
                                Button {
                                    Haptics.tap()
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        order.append(card)
                                    }
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(Color.forest)
                                }
                                .buttonStyle(.plain)
                                cardLabel(card)
                            }
                        }
                    } header: {
                        Text("Hidden")
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Customize Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Haptics.success()
                        store.apply(order)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        Haptics.warning()
                        store.reset()
                        dismiss()
                    }
                    .foregroundStyle(Color.clay)
                }
            }
        }
        .onAppear { order = store.order }
        .presentationDetents([.large])
    }

    private func cardLabel(_ card: HomeCard) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(card.title).font(.clarionDisplay(15)).foregroundStyle(Color.ink)
            Text(card.caption).font(.clarionBody(12)).foregroundStyle(Color.ink3)
        }
    }
}

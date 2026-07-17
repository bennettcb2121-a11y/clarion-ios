import SwiftUI

/// The native plan: the lab-matched stack told the way Clarion tells it —
///  - the money story ("$X/mo · $Y backed by your blood") with the three-bucket bar
///  - today's protocol with one-tap dose logging (writes the same protocol_log the web reads)
///  - stack grouped by verdict: Lab-backed / Keep steady / Consider cutting
///  - retest windows pulled from the marker library
struct PlanView: View {
    @ObservedObject var store: ReportStore
    @ObservedObject var log: ProtocolLogStore
    @EnvironmentObject private var subscription: SubscriptionStore

    init(store: ReportStore, log: ProtocolLogStore) {
        self.store = store
        self.log = log
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if !subscription.entitled {
                    // Clarion+ gates the analysis surfaces (web parity) — the wall,
                    // never a purchase button. Fails open; see SubscriptionStore.
                    MembershipWall(surface: "plan")
                } else {
                    switch store.state {
                    case .loading:
                        ClarionLoadingView()
                    case .empty:
                        empty("Add bloodwork to get a lab-matched supplement plan.")
                    case .error(let m):
                        empty(m)
                    case .ready(let r):
                        content(r)
                    }
                }
            }
            .contentMargins(.bottom, 96, for: .scrollContent)
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle("Plan")
            .refreshable {
                await store.load()
                await log.load()
            }
        }
        .task {
            if case .loading = store.state { await store.load() }
            await log.load()
        }
    }

    @ViewBuilder
    private func content(_ r: ReportResponse) -> some View {
        let stack = r.stack ?? []
        if stack.isEmpty {
            empty("No supplements recommended right now — your panel looks well-covered.")
        } else {
            let need = stack.filter { $0.bucket == .need }
            let maintain = stack.filter { $0.bucket == .maintain }
            let cut = stack.filter { $0.bucket == .cut }
            let takeable = need + maintain
            let retestByMarker = retestNotes(r)

            VStack(spacing: Brand.s4) {
                moneyCard(r, need: need, maintain: maintain, cut: cut).entrance(0)

                if !takeable.isEmpty {
                    todayCard(takeable).entrance(1)
                }

                group(need, title: "Lab-backed", note: "Your blood asks for these.", startIndex: 2, retest: retestByMarker)
                group(maintain, title: "Keep steady", note: "Worth keeping — routine or training support.", startIndex: 2 + min(need.count, 1), retest: retestByMarker)
                group(cut, title: "Consider cutting", note: "Nothing in your labs needs these.", startIndex: 3, retest: retestByMarker)

                Text("Educational, not medical advice. Discuss changes with your clinician.")
                    .font(.clarionBody(12))
                    .foregroundStyle(Color.ink4)
                    .multilineTextAlignment(.center)
                    .padding(.top, Brand.s1)
            }
            .padding(Brand.s5)
        }
    }

    /// Marker → retest guidance from the report library (e.g. "Retest in 8–10 weeks").
    private func retestNotes(_ r: ReportResponse) -> [String: String] {
        var notes: [String: String] = [:]
        for result in r.results ?? [] {
            if let retest = result.retest, !retest.isEmpty {
                notes[result.name] = retest
            }
        }
        return notes
    }

    // MARK: - Money story

    @ViewBuilder
    private func moneyCard(_ r: ReportResponse, need: [StackItem], maintain: [StackItem], cut: [StackItem]) -> some View {
        let needCost = need.reduce(0) { $0 + $1.monthlyCost }
        let maintainCost = maintain.reduce(0) { $0 + $1.monthlyCost }
        let cutCost = cut.reduce(0) { $0 + $1.monthlyCost }
        let planCost = needCost + maintainCost

        // Stored recommendations don't always carry an estimated cost (older rows, or a
        // supplement the pricing table didn't match) — then every monthlyCost is 0. Showing
        // "$0/mo · $0 backed by your blood" with an empty bar reads as broken, so fall back to
        // the shape of the stack (how many are lab-backed vs kept) instead of a fake dollar hero.
        if planCost + cutCost <= 0 {
            VStack(alignment: .leading, spacing: Brand.s2) {
                Eyebrow("Your stack")
                Text(stackShapeHeadline(need: need.count, maintain: maintain.count))
                    .font(.clarionDisplay(22))
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Backed by your latest panel.")
                    .font(.clarionBody(13))
                    .foregroundStyle(Color.ink3)
            }
            .padding(Brand.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clarionCard(cornerRadius: Brand.rXL)
        } else {
            VStack(alignment: .leading, spacing: Brand.s3) {
                Eyebrow("Your stack")
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("$\(Int(planCost.rounded()))")
                        .font(.clarionDisplay(34))
                        .foregroundStyle(Color.ink)
                    Text("/mo")
                        .font(.clarionData(13))
                        .foregroundStyle(Color.ink3)
                    Spacer()
                    if cutCost > 0 {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("save $\(Int(cutCost.rounded()))/mo")
                                .font(.clarionData(13))
                                .foregroundStyle(Color.forest)
                            Text("by cutting")
                                .font(.clarionBody(11))
                                .foregroundStyle(Color.ink3)
                        }
                    }
                }

                MoneyBar(need: needCost, maintain: maintainCost, skip: max(cutCost, 0))

                HStack(spacing: Brand.s4) {
                    legend("$\(Int(needCost.rounded())) backed by your blood", color: .forest)
                    if maintainCost > 0 {
                        legend("$\(Int(maintainCost.rounded())) keep", color: .amber)
                    }
                    if cutCost > 0 {
                        legend("$\(Int(cutCost.rounded())) cut", color: .ink4)
                    }
                }
            }
            .padding(Brand.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clarionCard(cornerRadius: Brand.rXL)
        }
    }

    /// "3 lab-backed · 2 worth keeping" — the cost-free framing when no prices are on file.
    private func stackShapeHeadline(need: Int, maintain: Int) -> String {
        var parts: [String] = []
        if need > 0 { parts.append("\(need) lab-backed") }
        if maintain > 0 { parts.append("\(maintain) worth keeping") }
        return parts.isEmpty ? "Your current protocol" : parts.joined(separator: " · ")
    }

    private func legend(_ text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.clarionData(11))
                .foregroundStyle(Color.ink3)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: - Today's protocol (one-tap dose logging)

    private func todayCard(_ items: [StackItem]) -> some View {
        VStack(alignment: .leading, spacing: Brand.s3) {
            HStack {
                Eyebrow("Today")
                Spacer()
                let done = items.filter { log.isDone($0) }.count
                Text("\(done)/\(items.count)")
                    .font(.clarionData(13))
                    .foregroundStyle(done == items.count && !items.isEmpty ? Color.forest : Color.ink3)
            }
            ForEach(items) { item in
                DoseRow(item: item, done: log.isDone(item)) {
                    Haptics.commit()
                    Task { await log.toggle(item) }
                }
                if item.id != items.last?.id {
                    Divider().overlay(Color.line)
                }
            }
        }
        .padding(Brand.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clarionCard()
    }

    // MARK: - Verdict groups

    @ViewBuilder
    private func group(_ items: [StackItem], title: String, note: String, startIndex: Int, retest: [String: String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Eyebrow(title)
                Text(note)
                    .font(.clarionBody(13))
                    .foregroundStyle(Color.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Brand.s2)

            ForEach(items) { item in
                StackCard(item: item, retest: item.marker.flatMap { retest[$0] })
            }
        }
    }

    private func empty(_ m: String) -> some View {
        VStack(spacing: Brand.s3) {
            Image(systemName: "pills.fill").font(.largeTitle).foregroundStyle(Color.forest)
            Text(m).font(.clarionBody(15)).foregroundStyle(Color.ink3).multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

// MARK: - Rows

/// One dose row: spring-filling forest check circle + serif name + mono dose.
struct DoseRow: View {
    let item: StackItem
    let done: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Brand.s3) {
                ZStack {
                    Circle()
                        .strokeBorder(done ? Color.forest : Color.line2, lineWidth: 1.5)
                        .background(Circle().fill(done ? Color.forest : Color.clear))
                        .frame(width: 26, height: 26)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.65), value: done)

                Text(item.name)
                    .font(.clarionDisplay(15))
                    .foregroundStyle(done ? Color.ink3 : Color.ink)
                    .strikethrough(done, color: Color.ink4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer()

                Text(item.dose)
                    .font(.clarionData(13))
                    .foregroundStyle(Color.ink3)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(haptic: false))
    }
}

/// One stack card: serif name, mono dose right-aligned, marker + cost metadata row,
/// the lab-tied reason, and the retest window when the library publishes one.
struct StackCard: View {
    let item: StackItem
    let retest: String?

    private var isCut: Bool { item.bucket == .cut }

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.name)
                    .font(.clarionDisplay(17))
                    .foregroundStyle(isCut ? Color.ink3 : Color.ink)
                    .strikethrough(isCut, color: Color.ink4)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Brand.s2)
                Text(item.dose)
                    .font(.clarionData(14))
                    .foregroundStyle(isCut ? Color.ink4 : Color.ink)
            }

            HStack(spacing: Brand.s2) {
                if let marker = item.marker, !marker.isEmpty {
                    TagPill(marker, tone: .forestInk, wash: .forestWash)
                }
                if item.monthlyCost > 0 {
                    Text("~$\(Int(item.monthlyCost.rounded()))/mo")
                        .font(.clarionData(12))
                        .foregroundStyle(Color.ink3)
                }
                Spacer()
            }

            Text(item.reason)
                .font(.clarionBody(14))
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)

            if let retest, !isCut {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10, weight: .semibold))
                    Text(retest)
                        .font(.clarionBody(12.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Color.ink3)
                .padding(.top, 1)
            }
        }
        .padding(Brand.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clarionCard(cornerRadius: Brand.r)
        .opacity(isCut ? 0.75 : 1)
    }
}

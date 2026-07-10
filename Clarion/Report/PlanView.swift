import SwiftUI

/// Native supplement plan: the lab-matched stack with dose, why, and monthly cost. Reads the
/// same ReportStore (stack_snapshot) as the Report tab.
struct PlanView: View {
    @ObservedObject var store: ReportStore

    var body: some View {
        NavigationStack {
            ScrollView {
                switch store.state {
                case .loading:
                    ProgressView().padding(.top, 80)
                case .empty:
                    empty("Add bloodwork to get a lab-matched supplement plan.")
                case .error(let m):
                    empty(m)
                case .ready(let r):
                    content(r)
                }
            }
            .contentMargins(.bottom, 96, for: .scrollContent)
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle("Plan")
            .refreshable { await store.load() }
        }
        .task { if case .loading = store.state { await store.load() } }
    }

    @ViewBuilder
    private func content(_ r: ReportResponse) -> some View {
        let stack = r.stack ?? []
        if stack.isEmpty {
            empty("No supplements recommended right now — your panel looks well-covered.")
        } else {
            VStack(spacing: 14) {
                costHeader(monthly: r.stackMonthlyCost ?? 0, count: stack.count)
                ForEach(stack) { StackRow(item: $0) }
                Text("Educational, not medical advice. Discuss changes with your clinician.")
                    .font(.caption2).foregroundStyle(Color.inkMuted)
                    .multilineTextAlignment(.center).padding(.top, 4)
            }
            .padding(20)
        }
    }

    private func costHeader(monthly: Double, count: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your stack").font(.system(.headline, design: .serif)).foregroundStyle(Color.ink)
                Text("\(count) supplement\(count == 1 ? "" : "s"), lab-matched").font(.footnote).foregroundStyle(Color.inkMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("$\(Int(monthly.rounded()))").font(.system(.title2, weight: .semibold)).monospacedDigit().foregroundStyle(Color.forest)
                Text("/ month").font(.caption).foregroundStyle(Color.inkMuted)
            }
        }
        .padding(18)
        .background(Color.forestWash.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
    }

    private func empty(_ m: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "pills.fill").font(.largeTitle).foregroundStyle(Color.forest)
            Text(m).font(.subheadline).foregroundStyle(Color.inkMuted).multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

struct StackRow: View {
    let item: StackItem

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(item.name)
                .font(.system(.headline, design: .serif)).foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if let marker = item.marker {
                    Text(marker).font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.forestWash, in: Capsule()).foregroundStyle(Color.forestInk)
                }
                if item.monthlyCost > 0 {
                    Text("~$\(Int(item.monthlyCost.rounded()))/mo")
                        .font(.system(size: 12)).monospacedDigit().foregroundStyle(Color.inkMuted)
                }
                Spacer()
                Text(item.dose)
                    .font(.system(size: 14, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Color.ink)
            }
            Text(item.reason).font(.subheadline).foregroundStyle(Color.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clarionCard(cornerRadius: 16)
    }
}

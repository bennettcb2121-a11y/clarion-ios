import SwiftUI

/// The native Logbook — twin of the web month calendar (LogbookCalendar +
/// LogbookDayDetail): a Sunday-start 42-cell grid where each day shows its dose
/// dots, lab flask, and retest badge; header stat chips; a lab-days list; and a
/// per-day detail sheet. Read-first in v1 — dose edits still live on Home/Plan
/// (today) and the web logbook (past days).
struct LogbookView: View {
    @ObservedObject var store: LogbookStore
    /// Shared report store — the current stack names the day-detail dose rows.
    @ObservedObject var report: ReportStore

    @State private var selectedDay: LogbookDay? = nil

    private static let weekdayLabels = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        ScrollView {
            switch store.state {
            case .loading:
                ClarionLoadingView()
            case .error(let m):
                errorState(m)
            case .ready:
                content
            }
        }
        .background(Color.paper.ignoresSafeArea())
        .navigationTitle("Logbook")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await store.load() }
        .task { if case .loading = store.state { await store.load() } }
        .sheet(item: $selectedDay) { day in
            DayDetailSheet(day: day, stack: currentStack)
                .presentationDetents([.medium, .large])
        }
    }

    private var currentStack: [StackItem] {
        if case .ready(let r) = report.state { return r.stack ?? [] }
        return []
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: Brand.s5) {
            Text("Tap a day to see what you took, when you tested, and what's due next.")
                .font(.clarionBody(14.5))
                .foregroundStyle(Color.ink2)
                .entrance(0)

            statChips.entrance(0)

            if let month = store.month {
                calendarCard(month).entrance(1)
            }

            labsSection.entrance(2)
        }
        .padding(Brand.s5)
    }

    private var statChips: some View {
        let stats = store.monthStats
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Brand.s2) {
                TagPill("\(stats.daysLogged) day\(stats.daysLogged == 1 ? "" : "s") logged", tone: .forestInk, wash: .forestWash)
                TagPill("\(stats.totalChecks) items checked", tone: .ink2, wash: .paperDim)
                TagPill("Next retest \(store.nextRetestLabel ?? "—")", tone: .amber, wash: .amberWash)
            }
        }
    }

    // MARK: - Calendar

    private func calendarCard(_ month: LogbookMonth) -> some View {
        VStack(spacing: Brand.s3) {
            HStack {
                monthNavButton("chevron.left") { Task { await store.move(byMonths: -1) } }
                Spacer()
                Text(month.label)
                    .font(.clarionDisplay(17))
                    .tracking(-0.015 * 17)
                    .foregroundStyle(Color.ink)
                Spacer()
                monthNavButton("chevron.right") { Task { await store.move(byMonths: 1) } }
            }

            HStack(spacing: 0) {
                ForEach(Array(Self.weekdayLabels.enumerated()), id: \.offset) { _, l in
                    Text(l)
                        .font(.clarionLabel(10))
                        .tracking(0.8)
                        .foregroundStyle(Color.ink3)
                        .frame(maxWidth: .infinity)
                }
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(month.days) { day in
                    DayCell(day: day) { selectedDay = day }
                }
            }

            legend
        }
        .padding(Brand.s4)
        .clarionCard()
    }

    private func monthNavButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink2)
                .frame(width: 32, height: 32)
                .background(Color.surface2, in: RoundedRectangle(cornerRadius: Brand.rSM))
                .overlay(RoundedRectangle(cornerRadius: Brand.rSM).stroke(Color.line))
        }
        .buttonStyle(PressableStyle())
    }

    private var legend: some View {
        HStack(spacing: Brand.s4) {
            HStack(spacing: 4) {
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().fill(Color.forest).frame(width: 4, height: 4)
                    }
                }
                Text("Protocol logged")
            }
            HStack(spacing: 4) {
                Image(systemName: "testtube.2")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.forest)
                Text("Lab tested")
            }
            HStack(spacing: 4) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.amber)
                Text("Retest due")
            }
        }
        .font(.clarionBody(10.5))
        .foregroundStyle(Color.ink3)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Lab days list

    @ViewBuilder
    private var labsSection: some View {
        if let labs = store.labs, !labs.bloodworkSaves.isEmpty {
            VStack(alignment: .leading, spacing: Brand.s3) {
                Eyebrow("Lab days")
                VStack(spacing: 0) {
                    ForEach(Array(labs.bloodworkSaves.enumerated()), id: \.offset) { i, save in
                        labRow(save)
                        if i < labs.bloodworkSaves.count - 1 { Divider().overlay(Color.line) }
                    }
                }
                .clarionCard()
            }
        }
    }

    private func labRow(_ save: LabSaveMarker) -> some View {
        HStack(spacing: Brand.s3) {
            Image(systemName: "testtube.2")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.forest)
                .frame(width: 30, height: 30)
                .background(Color.forestWash, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(labDateLabel(save.createdAt))
                    .font(.clarionData(13.5))
                    .foregroundStyle(Color.ink)
                Text("\(save.markerCount) marker\(save.markerCount == 1 ? "" : "s")")
                    .font(.clarionBody(11.5))
                    .foregroundStyle(Color.ink3)
            }
            Spacer()
            if let score = save.score {
                Text("\(Int(score.rounded()))")
                    .font(.clarionData(16))
                    .foregroundStyle(Color.ink)
            }
        }
        .padding(.horizontal, Brand.s4)
        .padding(.vertical, Brand.s3)
    }

    private func labDateLabel(_ raw: String?) -> String {
        guard let iso = LocalDay.coerceToLocalIso(raw), let d = LocalDay.fromIso(iso) else { return "Unknown date" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        return fmt.string(from: d)
    }

    // MARK: - Error

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Brand.s3) {
            Text(message)
                .font(.clarionBody(14))
                .foregroundStyle(Color.ink2)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await store.load() } }
                .buttonStyle(SecondaryButtonStyle())
                .frame(maxWidth: 160)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(Brand.s5)
    }
}

// MARK: - Day cell

private struct DayCell: View {
    let day: LogbookDay
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                Text("\(day.dayOfMonth)")
                    .font(.clarionData(13))
                    .foregroundStyle(numberColor)

                // Up to 3 forest dots; none on empty days (placeholder dots on
                // empty days read as "things I missed").
                HStack(spacing: 2) {
                    if day.inMonth && day.checksCompleted > 0 {
                        ForEach(0..<min(3, day.checksCompleted), id: \.self) { _ in
                            Circle().fill(Color.forest).frame(width: 4, height: 4)
                        }
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(background, in: RoundedRectangle(cornerRadius: Brand.rXS))
            .overlay(
                RoundedRectangle(cornerRadius: Brand.rXS)
                    .stroke(day.isToday ? Color.forest : Color.clear, lineWidth: 1.5)
            )
            .overlay(alignment: .topTrailing) { badge }
            .opacity(day.inMonth ? 1 : 0.35)
        }
        .buttonStyle(PressableStyle(haptic: false))
        .accessibilityLabel(accessibilityText)
    }

    private var numberColor: Color {
        if day.isFuture { return .ink4 }
        return day.inMonth ? .ink : .ink3
    }

    private var background: Color {
        if day.isRetestWindow && !day.isRetestDay { return Color.amberWash.opacity(0.6) }
        if day.hasLab { return Color.forestWash.opacity(0.7) }
        return Color.clear
    }

    @ViewBuilder
    private var badge: some View {
        if day.hasLab {
            Image(systemName: "testtube.2")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Color.forest)
                .padding(2)
        } else if day.isRetestDay {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Color.amber)
                .padding(2)
        }
    }

    private var accessibilityText: String {
        var parts = [day.isoDate]
        parts.append(day.checksCompleted > 0 ? "\(day.checksCompleted) items checked" : "No items logged")
        if day.hasLab { parts.append("Bloodwork tested") }
        if day.isRetestDay { parts.append("Suggested retest day") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Day detail sheet

/// What a selected day holds: completion ring over the doses, the current-stack
/// rows with their checked state, archived keys ("no longer in stack"), the
/// day's logged inputs, and lab/retest callouts.
private struct DayDetailSheet: View {
    let day: LogbookDay
    let stack: [StackItem]

    @Environment(\.dismiss) private var dismiss

    private struct DoseRow: Identifiable {
        var id: String
        var name: String
        var dose: String
        var checked: Bool
        var archived: Bool
    }

    private var rows: [DoseRow] {
        let current = stack.map { item in
            DoseRow(
                id: item.protocolKey,
                name: item.name,
                dose: item.dose,
                checked: day.checks[item.protocolKey] == true || day.checks[item.name] == true,
                archived: false
            )
        }
        // Checked keys that match no current stack row — past stack items.
        let known = Set(stack.flatMap { [$0.protocolKey, $0.name] })
        let archived = day.checks
            .filter { $0.value && !known.contains($0.key) }
            .keys.sorted()
            .map { key in
                DoseRow(
                    id: "archived-\(key)",
                    name: key.hasPrefix("entry:") ? "Past stack item" : key,
                    dose: "",
                    checked: true,
                    archived: true
                )
            }
        return current + archived
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Brand.s4) {
                    header

                    if day.hasLab { labCallout }
                    if day.isRetestDay { retestCallout }

                    dosesSection

                    if let metrics = day.metrics, metrics.hasTrackedInputs {
                        inputsSection(metrics)
                    }
                }
                .padding(Brand.s5)
            }
            .background(Color.paper.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Brand.s1) {
            Eyebrow(day.isToday ? "Today" : day.isFuture ? "Upcoming" : "Logged")
            Text(humanDate)
                .font(.clarionDisplay(20))
                .tracking(-0.015 * 20)
                .foregroundStyle(Color.ink)
        }
    }

    private var humanDate: String {
        guard let d = LocalDay.fromIso(day.isoDate) else { return day.isoDate }
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMMM d, yyyy"
        return fmt.string(from: d)
    }

    private var labCallout: some View {
        HStack(spacing: Brand.s3) {
            Image(systemName: "testtube.2")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.forest)
            Text("Bloodwork tested this day.")
                .font(.clarionBody(13.5))
                .foregroundStyle(Color.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Brand.s3 + 2)
        .background(Color.forestWash, in: RoundedRectangle(cornerRadius: Brand.r))
    }

    private var retestCallout: some View {
        HStack(spacing: Brand.s3) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.amber)
            Text("Suggested retest day — book a draw and turn these protocol weeks into proof.")
                .font(.clarionBody(13.5))
                .foregroundStyle(Color.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Brand.s3 + 2)
        .background(Color.amberWash, in: RoundedRectangle(cornerRadius: Brand.r))
    }

    @ViewBuilder
    private var dosesSection: some View {
        let items = rows
        VStack(alignment: .leading, spacing: Brand.s3) {
            HStack {
                Eyebrow("Doses")
                Spacer()
                if !items.isEmpty && !day.isFuture {
                    completionRing(items)
                }
            }

            if items.isEmpty {
                Text(day.isFuture ? "Nothing scheduled yet — this day hasn't happened." : "No doses logged this day.")
                    .font(.clarionBody(13))
                    .foregroundStyle(Color.ink3)
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { row in
                        doseRow(row)
                        if row.id != items.last?.id { Divider().overlay(Color.line) }
                    }
                }
                .clarionCard()
            }
        }
    }

    private func completionRing(_ items: [DoseRow]) -> some View {
        let pct = Double(items.filter(\.checked).count) / Double(max(items.count, 1))
        return ZStack {
            Circle().stroke(Color.paperDim, lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(pct))
                .stroke(Color.forest, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((pct * 100).rounded()))%")
                .font(.clarionData(11))
                .foregroundStyle(Color.ink)
        }
        .frame(width: 44, height: 44)
        .accessibilityLabel("\(Int((pct * 100).rounded()))% of doses logged")
    }

    private func doseRow(_ row: DoseRow) -> some View {
        HStack(spacing: Brand.s3) {
            Image(systemName: row.checked ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(row.checked ? Color.forest : Color.ink4)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.name)
                    .font(.clarionBody(14))
                    .foregroundStyle(Color.ink)
                if row.archived {
                    Text("No longer in stack")
                        .font(.clarionBody(11))
                        .foregroundStyle(Color.ink3)
                } else if !row.dose.isEmpty {
                    Text(row.dose)
                        .font(.clarionData(11))
                        .foregroundStyle(Color.ink3)
                }
            }
            Spacer()
        }
        .padding(.horizontal, Brand.s4)
        .padding(.vertical, Brand.s3)
    }

    private func inputsSection(_ m: DailyMetrics) -> some View {
        VStack(alignment: .leading, spacing: Brand.s3) {
            Eyebrow("Inputs")
            let chips: [(String, String)] = [
                m.sleep_hours.map { ("Sleep", "\(TrackingData.trimNumber($0)) hrs") },
                m.sun_minutes.map { ("Sun", "\(TrackingData.trimNumber($0)) min") },
                m.hydration_cups.map { ("Hydration", "\(TrackingData.trimNumber($0)) cups") },
                m.activity_level.map { ("Training", TrackingData.formatActivity($0).primary + TrackingData.formatActivity($0).suffix) },
            ].compactMap { $0 }

            FlowChips(chips: chips)
        }
    }
}

/// Simple two-column chip layout for the day's logged inputs.
private struct FlowChips: View {
    let chips: [(String, String)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Brand.s2) {
            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                HStack(spacing: Brand.s2) {
                    Text(chip.0)
                        .font(.clarionLabel(11))
                        .foregroundStyle(Color.ink3)
                    Spacer()
                    Text(chip.1)
                        .font(.clarionData(12.5))
                        .foregroundStyle(Color.ink)
                }
                .padding(.horizontal, Brand.s3)
                .padding(.vertical, Brand.s2 + 2)
                .clarionCardQuiet(cornerRadius: Brand.rSM)
            }
        }
    }
}

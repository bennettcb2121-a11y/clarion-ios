import SwiftUI

/// Daily inputs — the native twin of the web tracking page (TrackingHandoff):
/// four drag-to-log inputs (sleep, sunlight, hydration, training), effect copy
/// under each bar, an "N/4 logged today" counter, and the Mon–Sun logged strip.
///
/// The slider FILL is the scoring-normalized pct (sleep peaks at 8h, sun at
/// 45 min…), while the drag GESTURE maps linearly to [0, max] snapped to step —
/// the web's exact split. Writes go through PUT /api/protocol-log/metrics with
/// replace semantics. This screen never shows a score and never says
/// "readiness" — that word belongs to the wearable on Vitals alone.
struct DailyInputsView: View {
    @ObservedObject var store: DailyMetricsStore

    private enum EditField {
        case sleep, sun, hydration, training
    }

    @State private var editing: EditField? = nil
    @State private var draft = ""
    @FocusState private var draftFocused: Bool

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
        .navigationTitle("Daily inputs")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await store.load() }
        .task { if case .loading = store.state { await store.load() } }
    }

    // MARK: - Content

    private var content: some View {
        let m = store.today
        return VStack(alignment: .leading, spacing: Brand.s5) {
            hero(m).entrance(0)

            if store.hasWearable {
                wearablePointer.entrance(1)
            }

            Eyebrow("Today's inputs").entrance(1)
            VStack(spacing: Brand.s3) {
                sleepCard(m)
                sunCard(m)
                hydrationCard(m)
                trainingCard(m)
            }
            .entrance(2)

            Eyebrow("This week").entrance(3)
            weekStrip.entrance(3)
        }
        .padding(Brand.s5)
    }

    private func hero(_ m: DailyMetrics) -> some View {
        HStack(alignment: .top, spacing: Brand.s4) {
            let bold = TrackingData.statusBold(m)
            (m.hasTrackedInputs
                ? Text("These feed your lab correlations — sunlight supports Vitamin D, training shifts iron and recovery markers. ") + Text(bold).bold()
                : Text("Sunlight, hydration, training — the things a wearable can't know. ") + Text(bold).bold())
                .font(.clarionBody(14.5))
                .foregroundStyle(Color.ink2)

            if !store.hasWearable {
                VStack(spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(m.trackedInputCount)")
                            .font(.clarionData(22))
                            .foregroundStyle(Color.ink)
                        Text("/\(TrackingData.inputCount)")
                            .font(.clarionData(13))
                            .foregroundStyle(Color.ink3)
                    }
                    Text("LOGGED TODAY")
                        .font(.clarionLabel(9))
                        .tracking(0.9)
                        .foregroundStyle(Color.ink3)
                }
                .padding(.horizontal, Brand.s3)
                .padding(.vertical, Brand.s2)
                .clarionCardQuiet(cornerRadius: Brand.r)
            }
        }
    }

    /// When a real wearable is connected the counter disappears and this card
    /// points at Vitals — sleep/HRV/RHR stream in live there.
    private var wearablePointer: some View {
        HStack(spacing: Brand.s3) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.forest)
            VStack(alignment: .leading, spacing: 2) {
                Text("From your wearable")
                    .font(.clarionLabel(12))
                    .foregroundStyle(Color.ink)
                Text("Sleep, HRV, and resting heart rate stream in live on the Vitals tab — log here only what it can't know.")
                    .font(.clarionBody(12.5))
                    .foregroundStyle(Color.ink3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Brand.s4)
        .clarionCardQuiet()
    }

    // MARK: - Input cards

    private func sleepCard(_ m: DailyMetrics) -> some View {
        inputCard(
            icon: "moon",
            label: "Sleep",
            value: m.sleep_hours.map(TrackingData.trimNumber) ?? "—",
            unit: " hrs",
            field: .sleep,
            fillPct: TrackingData.sleepFillPct(m.sleep_hours),
            max: 12, step: 0.5, warn: false,
            effect: TrackingData.sleepEffectLine(
                hours: m.sleep_hours,
                avgHours: TrackingData.avgSleep(store.history.map(\.metrics)),
                hasWearable: store.hasWearable
            ),
            editLabel: "Edit",
            onCommit: { v in Task { await store.update { $0.sleep_hours = v } } }
        )
    }

    private func sunCard(_ m: DailyMetrics) -> some View {
        inputCard(
            icon: "sun.max",
            label: "Sunlight",
            value: m.sun_minutes.map(TrackingData.trimNumber) ?? "—",
            unit: " min",
            field: .sun,
            fillPct: TrackingData.sunFillPct(m.sun_minutes),
            max: 120, step: 5, warn: false,
            effect: TrackingData.sunEffectLine(minutes: m.sun_minutes),
            editLabel: "Edit",
            onCommit: { v in Task { await store.update { $0.sun_minutes = v } } }
        )
    }

    private func hydrationCard(_ m: DailyMetrics) -> some View {
        let display = TrackingData.formatHydration(m.hydration_cups)
        let warn = (m.hydration_cups ?? 0) < 4
        return inputCard(
            icon: "drop",
            label: "Hydration",
            value: display.primary,
            unit: display.suffix,
            field: .hydration,
            fillPct: TrackingData.hydrationFillPct(m.hydration_cups),
            max: 12, step: 1, warn: warn,
            effect: TrackingData.hydrationEffectLine(cups: m.hydration_cups),
            editLabel: "Log",
            onCommit: { v in Task { await store.update { $0.hydration_cups = v } } }
        )
    }

    private func trainingCard(_ m: DailyMetrics) -> some View {
        let display = TrackingData.formatActivity(m.activity_level)
        return VStack(alignment: .leading, spacing: Brand.s3) {
            HStack(alignment: .center, spacing: Brand.s3) {
                inputIcon("figure.run")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Training")
                        .font(.clarionLabel(12))
                        .foregroundStyle(Color.ink2)
                    if editing == .training {
                        // Edit = five level buttons, never a keyboard.
                        HStack(spacing: Brand.s2) {
                            ForEach(1...5, id: \.self) { lvl in
                                levelButton(lvl, active: Int(m.activity_level ?? 0) == lvl)
                            }
                        }
                    } else {
                        valueLine(display.primary, unit: display.suffix)
                    }
                }
                Spacer()
                editButton(for: .training, label: "Edit", current: nil)
            }

            SliderBar(
                fillPct: TrackingData.trainingFillPct(m.activity_level),
                max: 5, step: 1, warn: false
            ) { v in
                Task { await store.update { $0.activity_level = Double(Swift.max(1, Int(v))) } }
            }

            effectCopy(TrackingData.trainingEffectLine(level: m.activity_level), warn: false)
        }
        .padding(Brand.s4)
        .clarionCard()
    }

    private func levelButton(_ lvl: Int, active: Bool) -> some View {
        Button {
            Task { await store.update { $0.activity_level = Double(lvl) } }
            editing = nil
        } label: {
            Text("\(lvl)")
                .font(.clarionData(14))
                .foregroundStyle(active ? Color.white : Color.ink2)
                .frame(width: 34, height: 30)
                .background(active ? Color.forest : Color.surface2, in: RoundedRectangle(cornerRadius: Brand.rXS))
                .overlay(RoundedRectangle(cornerRadius: Brand.rXS).stroke(active ? Color.clear : Color.line2))
        }
        .buttonStyle(PressableStyle())
    }

    private func inputCard(
        icon: String,
        label: String,
        value: String,
        unit: String,
        field: EditField,
        fillPct: Double,
        max: Double,
        step: Double,
        warn: Bool,
        effect: TrackingData.EffectLine,
        editLabel: String,
        onCommit: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: Brand.s3) {
            HStack(alignment: .center, spacing: Brand.s3) {
                inputIcon(icon)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.clarionLabel(12))
                        .foregroundStyle(Color.ink2)
                    if editing == field {
                        HStack(spacing: 4) {
                            TextField("0", text: $draft)
                                .keyboardType(.decimalPad)
                                .font(.clarionData(17))
                                .foregroundStyle(Color.ink)
                                .frame(width: 64)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.surface2, in: RoundedRectangle(cornerRadius: Brand.rXS))
                                .focused($draftFocused)
                            Text(unit.trimmingCharacters(in: .whitespaces))
                                .font(.clarionData(11))
                                .foregroundStyle(Color.ink3)
                        }
                    } else {
                        valueLine(value, unit: unit)
                    }
                }
                Spacer()
                editButton(for: field, label: editLabel, current: value == "—" ? nil : value)
            }

            SliderBar(fillPct: fillPct, max: max, step: step, warn: warn, onCommit: onCommit)

            effectCopy(effect, warn: warn)
        }
        .padding(Brand.s4)
        .clarionCard()
    }

    private func inputIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Color.forest)
            .frame(width: 34, height: 34)
            .background(Color.forestWash, in: RoundedRectangle(cornerRadius: Brand.rSM))
    }

    private func valueLine(_ value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(value)
                .font(.clarionData(17))
                .foregroundStyle(Color.ink)
            Text(unit)
                .font(.clarionData(11))
                .foregroundStyle(Color.ink3)
        }
    }

    private func editButton(for field: EditField, label: String, current: String?) -> some View {
        Button {
            if editing == field {
                commitDraft()
            } else {
                editing = field
                draft = current ?? ""
                if field != .training { draftFocused = true }
            }
        } label: {
            Text(editing == field ? "Done" : label)
                .font(.clarionLabel(12))
                .foregroundStyle(Color.forest)
        }
        .buttonStyle(PressableStyle())
    }

    /// The web's commitDraft clamps: sleep ≤24h, sun ≤600 min, hydration ≤30 cups.
    /// Clamp the RAW Double before any rounding — the decimal pad accepts values
    /// like 1e20 that would otherwise blow past integer range (jsRound saturates
    /// too, as a second line of defense).
    private func commitDraft() {
        defer { editing = nil; draftFocused = false }
        guard let field = editing, field != .training else { return }
        guard let num = Double(draft.replacingOccurrences(of: ",", with: ".")), num >= 0 else { return }
        switch field {
        case .sleep:
            Task { await store.update { $0.sleep_hours = Swift.min(24, num) } }
        case .sun:
            Task { await store.update { $0.sun_minutes = Double(MorningBrief.jsRound(Swift.min(600, num))) } }
        case .hydration:
            Task { await store.update { $0.hydration_cups = Double(MorningBrief.jsRound(Swift.min(30, num))) } }
        case .training:
            break
        }
    }

    private func effectCopy(_ line: TrackingData.EffectLine, warn: Bool) -> some View {
        (line.bold.map { Text($0).bold() + Text(" ") } ?? Text(""))
            .font(.clarionBody(12.5))
            .foregroundStyle(warn ? Color.amber : Color.ink3)
            + Text(line.text)
            .font(.clarionBody(12.5))
            .foregroundStyle(warn ? Color.amber : Color.ink3)
    }

    // MARK: - Week strip

    /// Mon–Sun dots: a day lights up when ANY input was logged. No score.
    private var weekStrip: some View {
        HStack(spacing: 0) {
            ForEach(TrackingData.weekLoggedDays(history: store.history)) { day in
                VStack(spacing: Brand.s2) {
                    Text(day.label)
                        .font(.clarionLabel(10))
                        .tracking(0.5)
                        .foregroundStyle(day.isToday ? Color.ink : Color.ink3)
                    Circle()
                        .fill(day.logged ? Color.forest : Color.paperDim)
                        .frame(width: 10, height: 10)
                        .opacity(day.isFuture ? 0.35 : 1)
                        .overlay(
                            Circle()
                                .stroke(day.isToday ? Color.forest : Color.clear, lineWidth: 1.5)
                                .frame(width: 16, height: 16)
                        )
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, Brand.s4)
        .padding(.horizontal, Brand.s3)
        .clarionCard()
        .accessibilityLabel("Days logged this week")
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

// MARK: - Drag-to-log bar

/// The fill IS the input: pointer down/drag anywhere maps linearly to [0, max]
/// snapped to step, committing on release. Displayed fill when idle is the
/// scoring-normalized pct passed in — NOT value/max (the web's exact behavior).
private struct SliderBar: View {
    /// Display fill when not dragging (scoring-normalized).
    let fillPct: Double
    let max: Double
    let step: Double
    var warn: Bool = false
    let onCommit: (Double) -> Void

    @State private var dragPct: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let pct = Swift.min(100, Swift.max(0, dragPct ?? fillPct))
            let thumbX = w * CGFloat(Swift.min(98, Swift.max(2, pct)) / 100)

            ZStack(alignment: .leading) {
                Capsule().fill(Color.paperDim).frame(height: 10)

                Capsule()
                    .fill(
                        warn
                            ? LinearGradient(colors: [Color.amberSoft, Color.amber], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [Color.forestBright, Color.forest], startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: Swift.max(0, w * CGFloat(pct / 100)), height: 10)

                Circle()
                    .fill(Color.surface)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(warn ? Color.amber : Color.forest, lineWidth: 2))
                    .shadow(color: Color.black.opacity(0.12), radius: 2, y: 1)
                    .position(x: thumbX, y: 12)
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        guard w > 0 else { return }
                        dragPct = (snappedValue(at: g.location.x, width: w) / max) * 100
                    }
                    .onEnded { g in
                        guard w > 0 else { dragPct = nil; return }
                        onCommit(snappedValue(at: g.location.x, width: w))
                        dragPct = nil
                        Haptics.tap()
                    }
            )
        }
        .frame(height: 24)
    }

    /// ratio × max snapped to step (the web's valueFromClientX).
    private func snappedValue(at x: CGFloat, width: CGFloat) -> Double {
        let ratio = Double(Swift.min(Swift.max(0, x / width), 1))
        return Double(MorningBrief.jsRound((ratio * max) / step)) * step
    }
}

import SwiftUI

// MARK: - Welcome (the web's STEP_HOOK, verbatim copy)

struct SurveyWelcomeStep: View {
    let onBegin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.s5) {
            Spacer(minLength: 0)
            SurveyKicker("The Clarion survey")
            (Text("Let's build ").font(.clarionDisplay(34))
             + Text("your").font(.clarionDisplayItalic(34)).foregroundStyle(Color.forest)
             + Text(" picture.").font(.clarionDisplay(34)))
                .tracking(-0.02 * 34)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            SurveySub("Six quick questions. By the end you'll see how your personalized ranges differ from the textbook — and what panel is worth your money.")
            Button {
                Haptics.commit()
                onBegin()
            } label: {
                HStack(spacing: 6) {
                    Text("Begin")
                    Image(systemName: "arrow.right")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, Brand.s2)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - About You (age · sex · height · weight — one facet at a time)
// Deliberately NOT the web's idle auto-advance: every facet advances on an explicit
// Next (or a sex pick). The settle-timer is the exact interaction that misfired and
// looped on mobile web; native gets the standard, predictable pattern instead.

struct SurveyAboutYouStep: View {
    @ObservedObject var state: SurveyState
    let onAdvance: () -> Void

    enum Facet: Int, CaseIterable { case age, sex, height, weight }
    /// Two-field facets (imperial height) need distinct focus identities — a single
    /// shared Bool focused the SECOND field first, so guided typing landed in inches.
    enum FocusSlot: Hashable { case primary, secondary }
    @State private var facet: Facet = .age
    @State private var imperial = true
    // Local drafts; committed to state on Next.
    @State private var feet = ""
    @State private var inches = ""
    @State private var pounds = ""
    @FocusState private var focusSlot: FocusSlot?

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.s5) {
            VStack(alignment: .leading, spacing: Brand.s2 + 2) {
                SurveyKicker("About you")
                SurveyPrompt(plain: facetPrompt.0, emphasis: facetPrompt.1)
            }

            facetBody
                .frame(maxWidth: .infinity)

            if facet != .sex {
                Button {
                    commitFacet()
                } label: {
                    Text(facet == .weight ? "Continue" : "Next").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!facetHasValue)
                .opacity(facetHasValue ? 1 : 0.4)
            }

            breadcrumbs
        }
        .onAppear { seedDrafts(); focusSlot = .primary }
        // The web's guided height entry: the moment feet fills, focus jumps to inches
        // so the flow can't advance before you reach the second field.
        .onChange(of: feet) { _, new in
            if facet == .height && imperial && !new.isEmpty { focusSlot = .secondary }
        }
    }

    private var facetPrompt: (String, String) {
        switch facet {
        case .age: return ("How old ", "are you?")
        case .sex: return ("Your ", "biological sex?")
        case .height: return ("How ", "tall?")
        case .weight: return ("And your ", "weight?")
        }
    }

    @ViewBuilder
    private var facetBody: some View {
        switch facet {
        case .age:
            bigField(text: $state.age, placeholder: "34", suffix: "years")
        case .sex:
            VStack(spacing: Brand.s2 + 2) {
                ForEach(SurveyCatalog.sexOptions, id: \.self) { opt in
                    SurveyOptionCard(label: opt, selected: state.sex == opt, compact: true) {
                        state.sex = opt
                        Haptics.selection()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { goNextFacet() }
                    }
                }
            }
        case .height:
            VStack(spacing: Brand.s3) {
                if imperial {
                    HStack(spacing: Brand.s3) {
                        bigField(text: $feet, placeholder: "5", suffix: "ft")
                        bigField(text: $inches, placeholder: "10", suffix: "in", slot: .secondary)
                    }
                } else {
                    bigField(text: $state.heightCm, placeholder: "178", suffix: "cm")
                }
                unitsToggle
            }
        case .weight:
            VStack(spacing: Brand.s3) {
                if imperial {
                    bigField(text: $pounds, placeholder: "165", suffix: "lb")
                } else {
                    bigField(text: $state.weightKg, placeholder: "75", suffix: "kg")
                }
                unitsToggle
            }
        }
    }

    private func bigField(text: Binding<String>, placeholder: String, suffix: String, slot: FocusSlot = .primary) -> some View {
        // Digits only, hard-capped: the software numberPad doesn't constrain hardware
        // keyboards or paste, so filter at the binding (age 27, not "a" or "270000").
        let filtered = Binding<String>(
            get: { text.wrappedValue },
            set: { text.wrappedValue = String($0.filter(\.isNumber).prefix(3)) }
        )
        return HStack(alignment: .firstTextBaseline, spacing: Brand.s2) {
            TextField(placeholder, text: filtered)
                .keyboardType(.numberPad)
                .focused($focusSlot, equals: slot)
                .font(.clarionData(44))
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
                .fixedSize()
                .frame(minWidth: 64)
            Text(suffix)
                .font(.clarionBody(15))
                .foregroundStyle(Color.ink3)
        }
        .padding(.horizontal, Brand.s5)
        .padding(.vertical, Brand.s4)
        .frame(maxWidth: .infinity)
        .clarionCardQuiet(cornerRadius: Brand.rXL)
    }

    private var unitsToggle: some View {
        HStack(spacing: Brand.s2) {
            ForEach(["Imperial", "Metric"], id: \.self) { u in
                let isOn = (u == "Imperial") == imperial
                Button {
                    Haptics.tap()
                    convertDrafts(toImperial: u == "Imperial")
                } label: {
                    Text(u)
                        .font(.clarionLabel(12))
                        .foregroundStyle(isOn ? Color.forestInk : Color.ink3)
                        .padding(.horizontal, Brand.s3)
                        .padding(.vertical, Brand.s1 + 2)
                        .background(
                            Capsule().fill(isOn ? Color.forestWash : Color.ink.opacity(0.045))
                        )
                }
                .buttonStyle(PressableStyle())
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Answered facets as tappable satellites — revisit any of them.
    private var breadcrumbs: some View {
        HStack(spacing: Brand.s2) {
            ForEach(Facet.allCases, id: \.rawValue) { f in
                let done = facetValue(f) != nil
                Button {
                    Haptics.tap()
                    facet = f
                    seedDrafts()
                    focusPrimarySoon()
                } label: {
                    Text(facetValue(f) ?? facetName(f))
                        .font(.clarionLabel(11))
                        .foregroundStyle(f == facet ? Color.forestInk : (done ? Color.ink2 : Color.ink4))
                        .padding(.horizontal, Brand.s2 + 2)
                        .padding(.vertical, Brand.s1 + 1)
                        .background(Capsule().fill(f == facet ? Color.forestWash : Color.ink.opacity(0.04)))
                }
                .buttonStyle(PressableStyle())
            }
            Spacer(minLength: 0)
        }
    }

    private func facetName(_ f: Facet) -> String {
        switch f {
        case .age: return "Age"
        case .sex: return "Sex"
        case .height: return "Height"
        case .weight: return "Weight"
        }
    }

    private func facetValue(_ f: Facet) -> String? {
        switch f {
        case .age: return Int(state.age).map { "\($0)" }
        case .sex: return state.sex.isEmpty ? nil : state.sex
        case .height:
            guard let cm = Double(state.heightCm), cm > 0 else { return nil }
            if imperial {
                let (ft, inch) = UnitsMath.feetInches(fromCm: cm)
                return "\(ft)′\(inch)″"
            }
            return "\(Int(cm)) cm"
        case .weight:
            guard let kg = Double(state.weightKg), kg > 0 else { return nil }
            return imperial ? "\(Int(UnitsMath.pounds(fromKg: kg))) lb" : "\(Int(kg)) kg"
        }
    }

    private var facetHasValue: Bool {
        switch facet {
        case .age: return (Int(state.age) ?? 0) > 0
        case .sex: return !state.sex.isEmpty
        case .height:
            if imperial { return (Int(feet) ?? 0) > 0 }
            return (Double(state.heightCm) ?? 0) > 0
        case .weight:
            if imperial { return (Double(pounds) ?? 0) > 0 }
            return (Double(state.weightKg) ?? 0) > 0
        }
    }

    private func commitFacet() {
        switch facet {
        case .height where imperial:
            let cm = UnitsMath.cm(fromFeet: Int(feet) ?? 0, inches: Int(inches) ?? 0)
            if cm > 0 { state.heightCm = String(Int(cm)) }
        case .weight where imperial:
            if let lb = Double(pounds), lb > 0 { state.weightKg = String(UnitsMath.kg(fromPounds: lb)) }
        default: break
        }
        Haptics.commit()
        goNextFacet()
    }

    private func goNextFacet() {
        if let next = Facet(rawValue: facet.rawValue + 1) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { facet = next }
            seedDrafts()
            focusPrimarySoon()
        } else {
            onAdvance()
        }
    }

    /// Focus must land AFTER the new facet's field exists — assigning mid-transition is
    /// silently dropped (the guided flow then types into nothing).
    private func focusPrimarySoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { focusSlot = .primary }
    }

    private func seedDrafts() {
        if let cm = Double(state.heightCm), cm > 0 {
            let (ft, inch) = UnitsMath.feetInches(fromCm: cm)
            feet = String(ft); inches = String(inch)
        }
        if let kg = Double(state.weightKg), kg > 0 {
            pounds = String(Int(UnitsMath.pounds(fromKg: kg)))
        }
    }

    private func convertDrafts(toImperial: Bool) {
        guard imperial != toImperial else { return }
        // Commit current entry into canonical metric first, then flip the display.
        if imperial {
            let cm = UnitsMath.cm(fromFeet: Int(feet) ?? 0, inches: Int(inches) ?? 0)
            if cm > 0 { state.heightCm = String(Int(cm)) }
            if let lb = Double(pounds), lb > 0 { state.weightKg = String(UnitsMath.kg(fromPounds: lb)) }
        }
        imperial = toImperial
        seedDrafts()
    }
}

// MARK: - Supplements (the web's shelf, phone-native: common chips + your shelf)

struct SurveySupplementsStep: View {
    @Binding var selection: [String]
    let onAdvance: () -> Void

    private let columns = [GridItem(.flexible(), spacing: Brand.s2 + 2), GridItem(.flexible(), spacing: Brand.s2 + 2)]

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.s5) {
            VStack(alignment: .leading, spacing: Brand.s2 + 2) {
                SurveyKicker("Your cabinet")
                SurveyPrompt(plain: "Taking anything ", emphasis: "today?")
                SurveySub("Tap what's on your shelf — we'll tell you what your labs actually support keeping.")
            }

            LazyVGrid(columns: columns, spacing: Brand.s2 + 2) {
                ForEach(SurveyCatalog.commonSupplements) { s in
                    let isOn = selection.contains(s.label)
                    Button {
                        Haptics.selection()
                        if let i = selection.firstIndex(of: s.label) { selection.remove(at: i) }
                        else { selection.append(s.label) }
                    } label: {
                        Text(s.label)
                            .font(.clarionDisplay(14.5))
                            .foregroundStyle(isOn ? Color.forestInk : Color.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Brand.s3)
                            .background(
                                RoundedRectangle(cornerRadius: Brand.r, style: .continuous)
                                    .fill(isOn ? Color.forestWash : Color.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Brand.r, style: .continuous)
                                    .stroke(isOn ? Color.forest.opacity(0.5) : Color.line, lineWidth: 1)
                            )
                    }
                    .buttonStyle(PressableStyle())
                }
            }

            if !selection.isEmpty {
                Text("\(selection.count) on your shelf")
                    .font(.clarionLabel(11))
                    .tracking(0.1 * 11)
                    .foregroundStyle(Color.forest)
            }

            Button {
                Haptics.commit()
                onAdvance()
            } label: {
                Text(selection.isEmpty ? "I don't take any" : "Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }
}

// MARK: - Spend (the web's slider, verbatim copy)

struct SurveySpendStep: View {
    @Binding var spend: Double
    let onAdvance: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.s5) {
            VStack(alignment: .leading, spacing: Brand.s2 + 2) {
                SurveyKicker("Monthly spend")
                SurveyPrompt(plain: "What do you ", emphasis: "spend a month?")
                SurveySub("On supplements today, roughly. We'll compare it with your lab-based plan.")
            }

            VStack(spacing: Brand.s3) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("$\(Int(spend))")
                        .font(.clarionData(52))
                        .foregroundStyle(Color.ink)
                        .contentTransition(.numericText())
                    if spend >= 300 {
                        Text("+").font(.clarionData(30)).foregroundStyle(Color.ink2)
                    }
                }
                .frame(maxWidth: .infinity)

                Slider(value: $spend, in: 0...300, step: 5)
                    .tint(Color.forest)
                    .onChange(of: spend) { _, _ in Haptics.tap() }

                HStack {
                    Text("$0").font(.clarionLabel(11)).foregroundStyle(Color.ink4)
                    Spacer()
                    Text("$300+").font(.clarionLabel(11)).foregroundStyle(Color.ink4)
                }
            }
            .padding(Brand.s5)
            .clarionCardQuiet(cornerRadius: Brand.rXL)

            Button {
                Haptics.commit()
                onAdvance()
            } label: {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }
}

// MARK: - Saving + Done

struct SurveySavingStep: View {
    @ObservedObject var state: SurveyState
    @State private var lineIndex = 0
    private let lines = [
        "Calibrating your ranges…",
        "Weighting markers for your goals…",
        "Checking what matters at your age…",
        "Setting up your picture…",
    ]

    var body: some View {
        VStack(spacing: Brand.s5) {
            Spacer()
            if let error = state.saveError {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Color.amber)
                Text(error)
                    .font(.clarionBody(15))
                    .foregroundStyle(Color.ink2)
                    .multilineTextAlignment(.center)
                Button {
                    Haptics.tap()
                    state.retrySave()
                } label: {
                    Text("Try again").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                ProgressView().controlSize(.large).tint(Color.forest)
                Text(lines[lineIndex])
                    .font(.clarionDisplayItalic(19))
                    .foregroundStyle(Color.ink2)
                    .transition(.opacity)
                    .id(lineIndex)
                    .task {
                        // Pure theater with a hard end — the save itself flips to .done;
                        // this only cycles copy while the request is in flight.
                        while !Task.isCancelled {
                            try? await Task.sleep(nanoseconds: 850_000_000)
                            withAnimation(.easeInOut(duration: 0.28)) {
                                lineIndex = (lineIndex + 1) % lines.count
                            }
                        }
                    }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct SurveyDoneStep: View {
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.s5) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(Color.forest)
            (Text("Your picture is ").font(.clarionDisplay(32))
             + Text("set.").font(.clarionDisplayItalic(32)).foregroundStyle(Color.forest))
                .tracking(-0.02 * 32)
                .foregroundStyle(Color.ink)
            SurveySub("Your ranges are calibrated to you — age, training, goals. Add bloodwork whenever you're ready and the full report lights up.")
            Button {
                Haptics.success()
                onFinish()
            } label: {
                HStack(spacing: 6) {
                    Text("See your dashboard")
                    Image(systemName: "arrow.right")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            Spacer()
            Spacer()
        }
    }
}

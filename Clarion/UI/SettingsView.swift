import SwiftUI

/// Native settings — parity with the web settings page, restyled off the stock List and
/// onto the card recipe (surface cards, 1px line dividers, tracked-caps eyebrows).
/// Profile fields read/write GET/PATCH /api/account/profile per-control (the web's
/// persistProfilePatch); a PATCH rejection surfaces inline next to the section it broke.
/// Units (imperial/metric) are local-only — height_cm/weight_kg stay canonical metric,
/// exactly like the web keeps units as unpersisted component state.
struct SettingsView: View {
    @EnvironmentObject private var auth: SupabaseAuth
    #if DEBUG
    @EnvironmentObject private var sync: SyncCoordinator
    @State private var seeding = false
    @State private var seedResult: String?
    @State private var confirmSeed = false
    #endif
    // Fresh SupabaseAuth shares the Keychain-persisted session (RootView pattern).
    @StateObject private var store = SettingsStore(auth: SupabaseAuth.shared)

    @AppStorage("clarion_units_imperial") private var unitsImperial = true

    // Text-field drafts (committed on focus loss / submit, like the web's Save).
    @State private var ageText = ""
    @State private var scoreGoalText = ""
    @State private var heightFeetText = ""
    @State private var heightInchesText = ""
    @State private var heightCmText = ""
    @State private var weightText = ""
    // What seedDrafts last wrote — body commits fire only when the text actually
    // changed. Focus loss alone must never PATCH: the ft/in representation is
    // quantized (inches are 2.54 cm apart), so re-deriving cm from an untouched
    // draft drifts ±1 cm for most stored values.
    @State private var seededHeightFeet = ""
    @State private var seededHeightInches = ""
    @State private var seededHeightCm = ""
    @State private var seededWeight = ""
    @State private var localErrors: [String: String] = [:]

    @State private var confirmingDelete = false
    @State private var deleting = false
    @State private var deleteError: String?
    @State private var openingWeb = false

    private enum Field: Hashable {
        case age, scoreGoal, heightFt, heightIn, heightCm, weight
    }
    @FocusState private var focus: Field?

    private var email: String { auth.session?.email ?? store.profile?.email ?? "" }
    private var initials: String {
        let name = email.split(separator: "@").first.map(String.init) ?? "C"
        return String(name.prefix(2)).uppercased()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Brand.s5) {
                    identityCard

                    switch store.state {
                    case .loading:
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, Brand.s7)
                    case .error(let m):
                        noticeCard(m)
                    case .ready(nil):
                        surveyCard
                    case .ready(.some):
                        aboutCard
                        preferencesCard
                        remindersCard
                    }

                    healthCard
                    #if DEBUG
                    developerCard
                    #endif
                    supportCard
                    privacyCard
                    accountCard
                    deleteCard.id("settings-bottom")
                }
                .padding(Brand.s5)
            }
            .onAppear {
                #if DEBUG
                // Screenshot harness: reveal the below-fold cards (preferences/reminders).
                if ProcessInfo.processInfo.arguments.contains("UITEST_SCROLL_BOTTOM") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        withAnimation { proxy.scrollTo("settings-bottom", anchor: .bottom) }
                    }
                }
                #endif
            }
        }
        .contentMargins(.bottom, 96, for: .scrollContent)
        .background(Color.paper.ignoresSafeArea())
        .navigationTitle("Settings")
        .refreshable { await store.load() }
        .task {
            if case .loading = store.state { await store.load() }
            seedDrafts()
        }
        .onChange(of: store.profile) { _, _ in
            // Server echo landed — refresh drafts unless the user is mid-edit.
            if focus == nil { seedDrafts() }
        }
        .onChange(of: focus) { old, _ in
            if let old { commit(old) }
        }
        .onChange(of: unitsImperial) { _, _ in seedDrafts() }
        .overlay {
            if deleting {
                ProgressView("Deleting…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .confirmationDialog(
            "Delete your Clarion account?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete everything", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your labs, wearable data, and profile. It can't be undone.")
        }
    }

    // MARK: - Identity

    private var identityCard: some View {
        HStack(spacing: 14) {
            Text(initials)
                .font(.clarionDisplay(17))
                .foregroundStyle(Color.forestInk)
                .frame(width: 52, height: 52)
                .background(Color.forestWash, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(email.isEmpty ? "Clarion member" : email)
                    .font(.clarionLabel(15))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                Text(memberLine)
                    .font(.clarionBody(13))
                    .foregroundStyle(Color.ink3)
            }
            Spacer(minLength: 0)
        }
        .padding(Brand.s4 + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clarionCard()
    }

    private var memberLine: String {
        switch store.profile?.planTier {
        case "full": return "Clarion member · full plan"
        case "lite": return "Clarion member · lite plan"
        default: return "Clarion member"
        }
    }

    // MARK: - Survey-less empty state

    private var surveyCard: some View {
        section("About you") {
            VStack(alignment: .leading, spacing: Brand.s3) {
                Text("Finish your survey to unlock these settings")
                    .font(.clarionDisplay(17))
                    .foregroundStyle(Color.ink)
                Text("Your profile calibrates every range, reminder, and recommendation. It takes about two minutes on the web.")
                    .font(.clarionBody(14))
                    .foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Haptics.tap()
                    UIApplication.shared.open(Config.apiBase.appendingPathComponent("survey"))
                } label: {
                    Text("Start the survey").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(Brand.s4 + 2)
        }
    }

    // MARK: - About you

    private var aboutCard: some View {
        section("About you") {
            VStack(alignment: .leading, spacing: 0) {
                menuRow("Profile focus", value: ProfileTypeCatalog.label(for: store.profile?.profileType)) {
                    profileTypeMenu
                }
                rowDivider
                fieldRow("Age") {
                    TextField("—", text: $ageText)
                        .keyboardType(.numberPad)
                        .focused($focus, equals: .age)
                        .onSubmit { commit(.age) }
                        .multilineTextAlignment(.trailing)
                        .font(.clarionData(15))
                        .foregroundStyle(Color.ink)
                        .frame(width: 80)
                }
                errorLine(for: "age")
                rowDivider
                pickerRow("Sex", selection: sexBinding, options: [("Female", "Female"), ("Male", "Male"), ("Other", "Other")])
                errorLine(for: "sex")
                rowDivider
                menuRow("Diet", value: DietCatalog.label(for: store.profile?.dietPreference)) {
                    dietMenu
                }
                errorLine(for: "diet_preference")
                rowDivider
                symptomsRows
                errorLine(for: "symptoms")
                rowDivider
                unitsRows
                errorLine(for: "body")
            }
        }
    }

    private var profileTypeMenu: some View {
        let groups = Dictionary(grouping: ProfileTypeCatalog.options, by: \.group)
        let order = ["Universal", "Performance", "Age & hormone", "Clinical"]
        return ForEach(order, id: \.self) { group in
            Section(group) {
                ForEach(groups[group] ?? []) { opt in
                    Button(opt.label) {
                        Haptics.selection()
                        Task { await store.save(["profile_type": opt.id], field: "profile_type") }
                    }
                }
            }
        }
    }

    private var dietMenu: some View {
        Group {
            Button("No preference") {
                Haptics.selection()
                Task { await store.save(["diet_preference": NSNull()], field: "diet_preference") }
            }
            ForEach(DietCatalog.options, id: \.id) { opt in
                Button(opt.label) {
                    Haptics.selection()
                    Task { await store.save(["diet_preference": opt.id], field: "diet_preference") }
                }
            }
        }
    }

    private var sexBinding: Binding<String> {
        Binding(
            get: { store.profile?.sex ?? "" },
            set: { v in Task { await store.save(["sex": v], field: "sex") } }
        )
    }

    private var selectedSymptoms: Set<String> {
        Set((store.profile?.symptoms ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
    }

    private var symptomsRows: some View {
        VStack(alignment: .leading, spacing: Brand.s2) {
            Text("Symptoms")
                .font(.clarionBody(15))
                .foregroundStyle(Color.ink)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: Brand.s2)], alignment: .leading, spacing: Brand.s2) {
                ForEach(SymptomCatalog.options, id: \.id) { opt in
                    let active = selectedSymptoms.contains(opt.id)
                    Button {
                        Haptics.tap()
                        var next = selectedSymptoms
                        if active { next.remove(opt.id) } else { next.insert(opt.id) }
                        let ordered = SymptomCatalog.options.map(\.id).filter { next.contains($0) }
                        let value: Any = ordered.isEmpty ? NSNull() : ordered.joined(separator: ",")
                        Task { await store.save(["symptoms": value], field: "symptoms") }
                    } label: {
                        Text(opt.label)
                            .font(.clarionLabel(12.5))
                            .foregroundStyle(active ? Color.forestInk : Color.ink2)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity)
                            .background(active ? Color.forestWash : Color.surface2, in: Capsule())
                            .overlay(Capsule().stroke(active ? Color.forest.opacity(0.35) : Color.line))
                    }
                    .buttonStyle(PressableStyle(haptic: false))
                }
            }
        }
        .padding(.horizontal, Brand.s4)
        .padding(.vertical, Brand.s3)
    }

    private var unitsRows: some View {
        VStack(alignment: .leading, spacing: Brand.s3) {
            HStack {
                Text("Body")
                    .font(.clarionBody(15))
                    .foregroundStyle(Color.ink)
                Spacer()
                Picker("Units", selection: $unitsImperial) {
                    Text("ft · lb").tag(true)
                    Text("cm · kg").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }
            if unitsImperial {
                HStack(spacing: Brand.s3) {
                    labeledField("Height (ft)", text: $heightFeetText, field: .heightFt)
                    labeledField("(in)", text: $heightInchesText, field: .heightIn)
                    labeledField("Weight (lb)", text: $weightText, field: .weight, decimal: true)
                }
            } else {
                HStack(spacing: Brand.s3) {
                    labeledField("Height (cm)", text: $heightCmText, field: .heightCm)
                    labeledField("Weight (kg)", text: $weightText, field: .weight, decimal: true)
                }
            }
        }
        .padding(.horizontal, Brand.s4)
        .padding(.vertical, Brand.s3)
    }

    private func labeledField(_ label: String, text: Binding<String>, field: Field, decimal: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.clarionBody(12))
                .foregroundStyle(Color.ink3)
            TextField("—", text: text)
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .focused($focus, equals: field)
                .onSubmit { commit(field) }
                .font(.clarionData(15))
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.surface2, in: RoundedRectangle(cornerRadius: Brand.rSM))
                .overlay(RoundedRectangle(cornerRadius: Brand.rSM).stroke(Color.line))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Preferences

    private var preferencesCard: some View {
        section("Preferences") {
            VStack(alignment: .leading, spacing: 0) {
                menuRow("Supplement form", value: formPrefLabel) {
                    Button("Any form — pick the best option") { saveFormPref("any") }
                    Button("I prefer gummies") { saveFormPref("gummy") }
                    Button("No pills — gummies, powders, or drinks") { saveFormPref("no_pills") }
                }
                // The web's per-value helper copy, verbatim.
                Text(formPrefNote)
                    .font(.clarionBody(12.5))
                    .foregroundStyle(Color.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Brand.s4)
                    .padding(.bottom, Brand.s3)
                errorLine(for: "supplement_form_preference")
                rowDivider
                menuRow("Improvement style", value: store.profile?.improvementPreference?.isEmpty == false ? store.profile!.improvementPreference! : "Not set") {
                    ForEach(["Supplements", "Diet", "Lifestyle", "Combination"], id: \.self) { v in
                        Button(v == "Combination" ? "Combination (recommended)" : v) {
                            Haptics.selection()
                            Task { await store.save(["improvement_preference": v], field: "improvement_preference") }
                        }
                    }
                }
                errorLine(for: "improvement_preference")
                rowDivider
                menuRow("Retest cadence", value: "Every \(Int(store.profile?.retestWeeks ?? 8)) weeks") {
                    ForEach([6, 8, 10, 12], id: \.self) { w in
                        Button("Every \(w) weeks") {
                            Haptics.selection()
                            Task { await store.save(["retest_weeks": w], field: "retest_weeks") }
                        }
                    }
                }
                errorLine(for: "retest_weeks")
                rowDivider
                fieldRow("Score goal (1–100)") {
                    TextField("None", text: $scoreGoalText)
                        .keyboardType(.numberPad)
                        .focused($focus, equals: .scoreGoal)
                        .onSubmit { commit(.scoreGoal) }
                        .multilineTextAlignment(.trailing)
                        .font(.clarionData(15))
                        .foregroundStyle(Color.ink)
                        .frame(width: 80)
                }
                errorLine(for: "score_goal")
            }
        }
    }

    private var formPrefLabel: String {
        switch store.profile?.supplementFormPreference {
        case "gummy": return "Gummies"
        case "no_pills": return "No pills"
        default: return "Any form"
        }
    }

    private var formPrefNote: String {
        switch store.profile?.supplementFormPreference {
        case "gummy":
            return "We'll lead with a gummy whenever one's available, and fall back to a non-pill form otherwise."
        case "no_pills":
            return "We'll prioritize gummies, powders, and drinks when available."
        default:
            return "We'll show the best option for each supplement."
        }
    }

    private func saveFormPref(_ v: String) {
        Haptics.selection()
        Task { await store.save(["supplement_form_preference": v], field: "supplement_form_preference") }
    }

    // MARK: - Reminders

    private var streakOn: Bool { store.profile?.streakMilestones != false }
    private var reminderOn: Bool { store.profile?.dailyReminder == true }
    private var reorderOn: Bool { store.profile?.notifyReorderEmail != false }

    private var remindersCard: some View {
        section("Reminders") {
            VStack(alignment: .leading, spacing: 0) {
                toggleRow("Streak milestones", subtitle: "Celebrate protocol streaks in your email digest.", isOn: Binding(
                    get: { streakOn },
                    set: { v in
                        Haptics.tap()
                        Task { await store.save(["streak_milestones": v], field: "streak_milestones") }
                    }
                ))
                errorLine(for: "streak_milestones")
                rowDivider
                toggleRow("Daily dose reminder", subtitle: "One nudge a day to log your protocol.", isOn: Binding(
                    get: { reminderOn },
                    set: { v in
                        Haptics.tap()
                        Task { await toggleDailyReminder(v) }
                    }
                ))
                if reminderOn {
                    reminderDetailRows
                }
                errorLine(for: "reminders")
                rowDivider
                toggleRow("Running-low emails", subtitle: "A heads-up before a supplement runs out.", isOn: Binding(
                    get: { reorderOn },
                    set: { v in
                        Haptics.tap()
                        Task { await store.save(["notify_reorder_email": v], field: "notify_reorder_email") }
                    }
                ))
                if reorderOn {
                    menuRow("Lead time", value: "\(Int(store.profile?.notifyReorderDays ?? 7)) days before") {
                        ForEach([3, 5, 7, 14], id: \.self) { d in
                            Button("\(d) days before") {
                                Haptics.selection()
                                Task { await store.save(["notify_reorder_days": d], field: "notify_reorder_days") }
                            }
                        }
                    }
                }
                errorLine(for: "notify_reorder_email")
                errorLine(for: "notify_reorder_days")
            }
        }
    }

    @ViewBuilder
    private var reminderDetailRows: some View {
        HStack {
            Text("Time")
                .font(.clarionBody(15))
                .foregroundStyle(Color.ink)
            Spacer()
            DatePicker("", selection: reminderTimeBinding, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
        }
        .padding(.horizontal, Brand.s4)
        .padding(.vertical, 6)
        HStack {
            Text("Channel")
                .font(.clarionBody(15))
                .foregroundStyle(Color.ink)
            Spacer()
            // email | sms only — web push can't reach a native app (APNs is Phase D).
            Picker("Channel", selection: reminderChannelBinding) {
                Text("Email").tag("email")
                Text("Text").tag("sms")
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
        }
        .padding(.horizontal, Brand.s4)
        .padding(.vertical, 6)
        if reminderChannelBinding.wrappedValue == "sms" {
            smsStatusRow
        }
        Text("Sent at your local time (\(TimeZone.current.identifier)).")
            .font(.clarionBody(12))
            .foregroundStyle(Color.ink4)
            .padding(.horizontal, Brand.s4)
            .padding(.bottom, Brand.s3)
    }

    @ViewBuilder
    private var smsStatusRow: some View {
        if let profile = store.profile, profile.smsVerified, let phone = profile.phone {
            Text("Texts go to \(phone).")
                .font(.clarionBody(12.5))
                .foregroundStyle(Color.ink3)
                .padding(.horizontal, Brand.s4)
                .padding(.bottom, 4)
        } else {
            HStack(spacing: Brand.s2) {
                Text("Verify your number on the web to receive texts.")
                    .font(.clarionBody(12.5))
                    .foregroundStyle(Color.amber)
                Button {
                    Haptics.tap()
                    Task { await openWebSettings() }
                } label: {
                    Text(openingWeb ? "Opening…" : "Verify")
                        .font(.clarionLabel(12.5))
                        .foregroundStyle(Color.forest)
                }
                .buttonStyle(PressableStyle(haptic: false))
                .disabled(openingWeb)
            }
            .padding(.horizontal, Brand.s4)
            .padding(.bottom, 4)
        }
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                let hhmm = store.profile?.dailyReminderTime ?? "08:00"
                let parts = hhmm.split(separator: ":").compactMap { Int($0) }
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                comps.hour = parts.count == 2 ? parts[0] : 8
                comps.minute = parts.count == 2 ? parts[1] : 0
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { date in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                let hhmm = String(format: "%02d:%02d", comps.hour ?? 8, comps.minute ?? 0)
                Task { await store.save(["daily_reminder_time": hhmm], field: "reminders") }
            }
        )
    }

    private var reminderChannelBinding: Binding<String> {
        Binding(
            get: {
                let c = store.profile?.dailyReminderChannel
                return c == "sms" ? "sms" : "email" // push (web-only) renders as email here
            },
            set: { v in
                Haptics.selection()
                Task { await store.save(["daily_reminder_channel": v], field: "reminders") }
            }
        )
    }

    /// Enabling seeds time + device timezone + channel, exactly like the web's toggle.
    private func toggleDailyReminder(_ on: Bool) async {
        guard let profile = store.profile else { return }
        if on {
            let channel = profile.dailyReminderChannel == "sms" ? "sms" : "email"
            await store.save([
                "daily_reminder": true,
                "daily_reminder_time": profile.dailyReminderTime ?? "08:00",
                "daily_reminder_timezone": TimeZone.current.identifier,
                "daily_reminder_channel": channel,
            ], field: "reminders")
        } else {
            await store.save(["daily_reminder": false], field: "reminders")
        }
    }

    // MARK: - Health / privacy / account (kept from v1, restyled onto cards)

    private var healthCard: some View {
        section("Health data") {
            VStack(alignment: .leading, spacing: 0) {
                Link(destination: URL(string: "x-apple-health://")!) {
                    linkRow("Manage Health permissions", system: "heart.text.square")
                }
                Text("Clarion only reads the metrics relevant to your goals, and never uses health data for advertising.")
                    .font(.clarionBody(13))
                    .foregroundStyle(Color.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Brand.s4)
                    .padding(.bottom, Brand.s3)
            }
        }
    }

    #if DEBUG
    /// Simulator helper: fill Apple Health with sample endurance data so the wearable dashboard
    /// populates without a real watch/Oura. Debug builds only.
    private var developerCard: some View {
        section("Developer") {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    confirmSeed = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform.path.ecg.rectangle")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.forest)
                            .frame(width: 24)
                        Text(seeding ? "Seeding sample Health…" : "Seed sample Health data")
                            .font(.clarionBody(16)).foregroundStyle(Color.ink)
                        Spacer()
                        if seeding { ProgressView().controlSize(.small) }
                    }
                    .padding(.horizontal, Brand.s4)
                    .padding(.vertical, Brand.s3)
                }
                .buttonStyle(PressableStyle())
                .disabled(seeding)
                .confirmationDialog(
                    "Seed sample Health data?",
                    isPresented: $confirmSeed,
                    titleVisibility: .visible
                ) {
                    Button("Seed & sync (test account only)", role: .destructive) {
                        Task {
                            seeding = true
                            seedResult = nil
                            do {
                                try await HealthSeeder.seed()
                                await sync.sync()
                                seedResult = "Seeded 14 days — pull to refresh Home."
                                Haptics.success()
                            } catch {
                                seedResult = "Seed failed: \(error.localizedDescription)"
                                Haptics.warning()
                            }
                            seeding = false
                        }
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This writes ~14 days of FAKE workouts, sleep, and HRV into Apple Health, then SYNCS them to \(email). Never do this on your real account — the fabricated data lands on your Clarion dashboard. Use a throwaway/test login.")
                }
                Text(seedResult ?? "Simulator only. Writes ~14 days of sample sleep, HRV, resting HR, VO₂max, and runs into Apple Health, then syncs — so it lands on whatever account is signed in. Test accounts only.")
                    .font(.clarionBody(13))
                    .foregroundStyle(seedResult == nil ? Color.ink3 : Color.forest)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Brand.s4)
                    .padding(.bottom, Brand.s3)
            }
        }
    }
    #endif

    private var supportCard: some View {
        section("Support") {
            VStack(alignment: .leading, spacing: 0) {
                // Settings is pushed inside Home's NavigationStack, so a plain
                // NavigationLink lands the native FAQ (chevron, not arrow.up.right —
                // this one stays in the app).
                NavigationLink {
                    FAQView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.forest)
                            .frame(width: 24)
                        Text("FAQ & support").font(.clarionBody(16)).foregroundStyle(Color.ink)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.ink4)
                    }
                    .padding(.horizontal, Brand.s4)
                    .padding(.vertical, Brand.s3)
                }
                .buttonStyle(PressableStyle())
                rowDivider
                Link(destination: URL(string: "mailto:support@clarionlabs.tech")!) {
                    linkRow("Email support", system: "envelope")
                }
            }
        }
    }

    private var privacyCard: some View {
        section("Privacy & legal") {
            VStack(alignment: .leading, spacing: 0) {
                Link(destination: Config.apiBase.appendingPathComponent("legal/privacy")) {
                    linkRow("Privacy policy", system: "lock")
                }
                rowDivider
                Link(destination: Config.apiBase.appendingPathComponent("legal/health-data-privacy")) {
                    linkRow("Health data privacy", system: "cross.case")
                }
                rowDivider
                Link(destination: Config.apiBase.appendingPathComponent("terms")) {
                    linkRow("Terms of service", system: "doc.text")
                }
            }
        }
    }

    private var accountCard: some View {
        section("Account") {
            Button {
                Haptics.warning()
                auth.signOut()
            } label: {
                HStack {
                    Text("Sign out")
                        .font(.clarionBody(16))
                        .foregroundStyle(Color.ink)
                    Spacer()
                }
                .padding(.horizontal, Brand.s4)
                .padding(.vertical, Brand.s3)
            }
            .buttonStyle(PressableStyle())
        }
    }

    private var deleteCard: some View {
        VStack(alignment: .leading, spacing: Brand.s2) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    Haptics.warning()
                    confirmingDelete = true
                } label: {
                    HStack {
                        Text("Delete my account")
                            .font(.clarionBody(16))
                            .foregroundStyle(Color.clay) // destructive routes through clay, never system red
                        Spacer()
                    }
                    .padding(.horizontal, Brand.s4)
                    .padding(.vertical, Brand.s3)
                }
                .buttonStyle(PressableStyle())
                .disabled(deleting)
                if let deleteError {
                    Text(deleteError)
                        .font(.clarionBody(13))
                        .foregroundStyle(Color.clay)
                        .padding(.horizontal, Brand.s4)
                        .padding(.bottom, Brand.s3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clarionCard()
            Text("Permanently removes your labs, wearable data, and profile from Clarion. This can't be undone.")
                .font(.clarionBody(12))
                .foregroundStyle(Color.ink4)
                .padding(.horizontal, Brand.s1)
        }
    }

    // MARK: - Card + row chrome

    private func section<Content: View>(_ eyebrow: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Brand.s2 + 2) {
            Eyebrow(eyebrow).padding(.horizontal, Brand.s1)
            VStack(alignment: .leading, spacing: 0) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .clarionCard()
        }
    }

    private var rowDivider: some View {
        Rectangle().fill(Color.line).frame(height: 1).padding(.leading, Brand.s4)
    }

    private func fieldRow<Content: View>(_ title: String, @ViewBuilder trailing: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(.clarionBody(15))
                .foregroundStyle(Color.ink)
            Spacer()
            trailing()
        }
        .padding(.horizontal, Brand.s4)
        .padding(.vertical, Brand.s3)
    }

    private func menuRow<MenuContent: View>(_ title: String, value: String, @ViewBuilder menu: () -> MenuContent) -> some View {
        HStack {
            Text(title)
                .font(.clarionBody(15))
                .foregroundStyle(Color.ink)
            Spacer()
            Menu {
                menu()
            } label: {
                HStack(spacing: 5) {
                    Text(value)
                        .font(.clarionLabel(13.5))
                        .foregroundStyle(Color.forestInk)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.ink4)
                }
            }
        }
        .padding(.horizontal, Brand.s4)
        .padding(.vertical, Brand.s3)
    }

    private func pickerRow(_ title: String, selection: Binding<String>, options: [(String, String)]) -> some View {
        HStack {
            Text(title)
                .font(.clarionBody(15))
                .foregroundStyle(Color.ink)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(options, id: \.0) { value, label in
                    Text(label).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 210)
        }
        .padding(.horizontal, Brand.s4)
        .padding(.vertical, Brand.s3)
    }

    private func toggleRow(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.clarionBody(15))
                    .foregroundStyle(Color.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.clarionBody(12.5))
                        .foregroundStyle(Color.ink3)
                }
            }
        }
        .tint(Color.forest)
        .padding(.horizontal, Brand.s4)
        .padding(.vertical, Brand.s3)
    }

    private func linkRow(_ title: String, system: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: system)
                .font(.system(size: 15))
                .foregroundStyle(Color.forest)
                .frame(width: 24)
            Text(title).font(.clarionBody(16)).foregroundStyle(Color.ink)
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.ink4)
        }
        .padding(.horizontal, Brand.s4)
        .padding(.vertical, Brand.s3)
    }

    /// Inline PATCH-rejection line for a control group (400 messages are user-surfaceable).
    @ViewBuilder
    private func errorLine(for field: String) -> some View {
        if let message = store.fieldErrors[field] ?? localErrors[field] {
            Text(message)
                .font(.clarionBody(12.5))
                .foregroundStyle(Color.clay)
                .padding(.horizontal, Brand.s4)
                .padding(.bottom, Brand.s2)
        }
    }

    private func noticeCard(_ m: String) -> some View {
        HStack(spacing: Brand.s2) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Color.amber)
            Text(m)
                .font(.clarionBody(14))
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Brand.s4 + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clarionCard()
    }

    // MARK: - Draft seeding + commits (text fields save on focus loss, like the web's Save)

    private func seedDrafts() {
        guard let p = store.profile else { return }
        ageText = p.age
        scoreGoalText = p.scoreGoal.map { String(Int($0)) } ?? ""
        if let cm = p.heightCm {
            heightCmText = String(Int(cm))
            let imp = UnitsMath.feetInches(fromCm: cm)
            heightFeetText = String(imp.feet)
            heightInchesText = String(imp.inches)
        } else {
            heightCmText = ""; heightFeetText = ""; heightInchesText = ""
        }
        if let kg = p.weightKg {
            weightText = unitsImperial ? trimNumber(UnitsMath.pounds(fromKg: kg)) : trimNumber(kg)
        } else {
            weightText = ""
        }
        seededHeightFeet = heightFeetText
        seededHeightInches = heightInchesText
        seededHeightCm = heightCmText
        seededWeight = weightText
    }

    private func trimNumber(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }

    private func commit(_ field: Field) {
        switch field {
        case .age:
            let v = ageText.trimmingCharacters(in: .whitespaces)
            guard v != store.profile?.age else { return }
            localErrors["age"] = nil
            Task { await store.save(["age": v], field: "age") }
        case .scoreGoal:
            let v = scoreGoalText.trimmingCharacters(in: .whitespaces)
            if v.isEmpty {
                localErrors["score_goal"] = nil
                if store.profile?.scoreGoal != nil {
                    Task { await store.save(["score_goal": NSNull()], field: "score_goal") }
                }
            } else if let n = Int(v), (1...100).contains(n) {
                localErrors["score_goal"] = nil
                if store.profile?.scoreGoal.map({ Int($0) }) != n {
                    Task { await store.save(["score_goal": n], field: "score_goal") }
                }
            } else {
                localErrors["score_goal"] = "Enter a number from 1 to 100."
            }
        case .heightFt, .heightIn, .heightCm:
            // No edit → no PATCH (tapping in and out must not re-derive a drifted cm).
            guard heightFeetText != seededHeightFeet
                || heightInchesText != seededHeightInches
                || heightCmText != seededHeightCm else { return }
            commitHeight()
        case .weight:
            guard weightText != seededWeight else { return }
            commitWeight()
        }
    }

    private func commitHeight() {
        localErrors["body"] = nil
        if unitsImperial {
            let ftEmpty = heightFeetText.trimmingCharacters(in: .whitespaces).isEmpty
            if ftEmpty && heightInchesText.trimmingCharacters(in: .whitespaces).isEmpty {
                if store.profile?.heightCm != nil {
                    Task { await store.save(["height_cm": NSNull()], field: "body") }
                }
                return
            }
            guard let ft = Int(heightFeetText), let inch = Int(heightInchesText.isEmpty ? "0" : heightInchesText),
                  ft >= 1, ft <= 8, inch >= 0, inch < 12 else {
                localErrors["body"] = "Enter a valid height."
                return
            }
            let cm = UnitsMath.cm(fromFeet: ft, inches: inch)
            if store.profile?.heightCm != cm {
                Task { await store.save(["height_cm": cm], field: "body") }
            }
        } else {
            let t = heightCmText.trimmingCharacters(in: .whitespaces)
            if t.isEmpty {
                if store.profile?.heightCm != nil {
                    Task { await store.save(["height_cm": NSNull()], field: "body") }
                }
                return
            }
            guard let cm = Double(t), cm >= 30, cm <= 300 else {
                localErrors["body"] = "Enter a valid height in cm."
                return
            }
            if store.profile?.heightCm != cm {
                Task { await store.save(["height_cm": cm], field: "body") }
            }
        }
    }

    private func commitWeight() {
        localErrors["body"] = nil
        let t = weightText.trimmingCharacters(in: .whitespaces)
        if t.isEmpty {
            if store.profile?.weightKg != nil {
                Task { await store.save(["weight_kg": NSNull()], field: "body") }
            }
            return
        }
        guard let raw = Double(t.replacingOccurrences(of: ",", with: ".")) else {
            localErrors["body"] = "Enter a valid weight."
            return
        }
        let kg = unitsImperial ? UnitsMath.kg(fromPounds: raw) : (raw * 10).rounded() / 10
        guard kg >= 20, kg <= 500 else {
            localErrors["body"] = "Enter a valid weight."
            return
        }
        if store.profile?.weightKg != kg {
            Task { await store.save(["weight_kg": kg], field: "body") }
        }
    }

    private func openWebSettings() async {
        openingWeb = true
        defer { openingWeb = false }
        let fallback = Config.apiBase.appendingPathComponent("dashboard/settings")
        guard let token = try? await auth.validAccessToken() else {
            await UIApplication.shared.open(fallback)
            return
        }
        let url = (try? await ClarionAPI.dashboardLoginLink(path: "/dashboard/settings", accessToken: token)) ?? fallback
        await UIApplication.shared.open(url)
    }

    private func deleteAccount() async {
        deleting = true
        deleteError = nil
        do {
            let token = try await auth.validAccessToken()
            try await ClarionAPI.deleteAccount(accessToken: token)
            auth.signOut() // account is gone; clear the local session
        } catch {
            deleteError = error.localizedDescription
        }
        deleting = false
    }
}

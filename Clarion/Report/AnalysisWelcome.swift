import SwiftUI

/// The two money moments, native — web parity with src/components/PaywallTeaser.tsx (1A lab
/// slip, blurred Clarion column) and AnalysisPaidWelcomeModal.tsx (2A one card). Data comes
/// from GET /api/analysis-welcome, built by the same engine as the web, so the number someone
/// sees before paying is the number they get after. `welcome` is only sent to entitled accounts.

// MARK: - Models

struct AnalysisWelcomeResponse: Decodable {
    var entitled: Bool
    var teaser: PaywallTeaserData?
    var welcome: AnalysisWelcomeData?
}

struct PaywallTeaserData: Decodable {
    struct Row: Decodable, Hashable {
        var marker: String
        var valueLabel: String
        /// The lab's own verdict — "Normal" | "Low" | "High" | "—". Never Clarion's.
        var lab: String
    }
    var score: Int
    var holdingBackCount: Int
    var saveUpToMonthly: Int?
    var needCount: Int
    var dropCount: Int
    var labNormalButOffCount: Int
    var profileLabel: String
    var rows: [Row]
    var totalMarkers: Int
}

struct AnalysisWelcomeData: Decodable {
    struct ScoreLine: Decodable, Hashable { var marker: String; var valueLabel: String; var statusWord: String; var pointsLost: Int }
    struct Problem: Decodable, Hashable {
        var marker: String
        var valueLabel: String
        var statusWord: String
        var tone: String
        var targetLabel: String?
        var fix: String
    }
    struct Pick: Decodable, Hashable { var name: String; var monthlyUsd: Double; var kind: String; var tag: String? }
    struct Money: Decodable { var currentMonthly: Double; var planMonthly: Double; var cutMonthly: Double; var netMonthly: Double }

    var score: Int
    var scoreLines: [ScoreLine]
    var inRangeCount: Int
    var problems: [Problem]
    var need: [Pick]
    var consider: [Pick]
    var drop: [Pick]
    var money: Money?
}

extension ClarionAPI {
    static func fetchAnalysisWelcome(accessToken: String) async throws -> AnalysisWelcomeResponse {
        var req = URLRequest(url: Config.apiBase.appendingPathComponent("api/analysis-welcome"))
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw APIError.decode }
        return try JSONDecoder().decode(AnalysisWelcomeResponse.self, from: data)
    }
}

private func usd(_ v: Double) -> String { "$\(Int(v.rounded()))" }

// MARK: - 1A · Paywall teaser (lab slip, blurred Clarion column)

struct PaywallTeaserCard: View {
    let t: PaywallTeaserData

    private var who: String {
        // "male endurance athlete, 34" → "34-year-old male endurance athlete"
        let parts = t.profileLabel.components(separatedBy: ", ")
        var core = parts.first ?? t.profileLabel
        if core.lowercased().hasPrefix("masters ") { core = String(core.dropFirst(8)) }
        if ["female", "female adult"].contains(core.lowercased()) { core = "woman" }
        if ["male", "male adult"].contains(core.lowercased()) { core = "man" }
        if parts.count == 2, Int(parts[1]) != nil { return "\(parts[1])-year-old \(core)" }
        return core
    }

    private var headline: (lead: String, turn: String?) {
        let off = t.holdingBackCount, hidden = t.labNormalButOffCount
        // Same rule as the web: no count when there aren't enough other results to hide among.
        let tested = t.rows.filter { $0.valueLabel != "Not tested" }.count
        if off > 0 && tested < off + 3 {
            return hidden > 0
                ? ("Your lab called this mostly normal.", "Clarion doesn't.")
                : ("Your lab flagged some of this.", "Clarion shows what it means for you.")
        }
        if off > 0 {
            let turn: String? = hidden == 0 ? nil
                : hidden == off ? "Your lab called \(off == 1 ? "it" : "every one") normal."
                : "Your lab called \(hidden) of them normal."
            return ("\(off) of your results \(off == 1 ? "is" : "are") holding you back.", turn)
        }
        if t.dropCount > 0 {
            return ("Your blood looks good.", "But \(t.dropCount) of your supplements \(t.dropCount == 1 ? "isn't" : "aren't") backed by it.")
        }
        return ("Your blood looks good.", "Here's how to keep it that way.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.s3) {
            Eyebrow("Read for a \(who)", color: .forest)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline.lead).foregroundStyle(Color.ink)
                if let turn = headline.turn { Text(turn).foregroundStyle(Color.forest) }
            }
            .font(.clarionDisplay(26))
            .tracking(-0.02 * 26)
            .fixedSize(horizontal: false, vertical: true)

            if let save = t.saveUpToMonthly {
                (Text("And you're spending about ") + Text("$\(save) a month").bold() + Text(" you don't need to."))
                    .font(.clarionBody(14.5))
                    .foregroundStyle(Color.ink2)
            }

            slip

            Text(cta)
                .font(.clarionLabel(14))
                .foregroundStyle(Color.forest)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }

    private var cta: String {
        var s = "Unlock Clarion's column"
        var bits: [String] = []
        if t.needCount > 0 { bits.append("what you need (\(t.needCount))") }
        if t.dropCount > 0 { bits.append("what to drop (\(t.dropCount))") }
        if !bits.isEmpty { s += " — " + bits.joined(separator: " · ") }
        return s + " ↓"
    }

    private var slip: some View {
        VStack(spacing: 0) {
            HStack {
                Eyebrow("Your results")
                Spacer()
                HStack(spacing: 4) {
                    Eyebrow("Clarion score")
                    Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Color.forest)
                }
            }
            .padding(.bottom, Brand.s2)
            HStack {
                colHead("Marker"); Spacer()
                colHead("Lab says").frame(width: 66, alignment: .leading)
                colHead("Clarion says").frame(width: 92, alignment: .leading)
            }
            .padding(.vertical, 6)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.line).frame(height: 1) }
            ForEach(t.rows, id: \.self) { r in
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.marker).font(.clarionLabel(14)).foregroundStyle(Color.ink).lineLimit(1)
                        Text(r.valueLabel).font(.clarionData(12)).foregroundStyle(r.valueLabel == "Not tested" ? Color.ink4 : Color.ink3)
                    }
                    Spacer(minLength: 6)
                    Text(r.lab)
                        .font(.clarionBody(13))
                        .foregroundStyle(r.lab == "Normal" ? Color.ink2 : r.lab == "—" ? Color.ink4 : Color.clay)
                        .frame(width: 66, alignment: .leading)
                    // Identical placeholder every row — nothing about the real verdict is here.
                    Text("Clarion's read")
                        .font(.clarionBody(13))
                        .foregroundStyle(Color.ink2)
                        .blur(radius: 4)
                        .accessibilityLabel("Locked")
                        .frame(width: 92, alignment: .leading)
                }
                .padding(.vertical, 9)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.line).frame(height: 1) }
            }
            if t.totalMarkers > t.rows.count {
                Text("+ \(t.totalMarkers - t.rows.count) more")
                    .font(.clarionBody(12.5))
                    .foregroundStyle(Color.ink3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Brand.s2)
            }
        }
        .padding(Brand.s4)
        .clarionCard()
    }

    private func colHead(_ s: String) -> some View {
        Text(s.uppercased()).font(.clarionLabel(9.5)).tracking(0.1 * 9.5).foregroundStyle(Color.ink3)
    }
}

// MARK: - 2A · Post-purchase pop-up (one card)

struct AnalysisWelcomeSheet: View {
    let w: AnalysisWelcomeData
    let firstName: String?
    var onOpenReport: () -> Void
    var onHome: () -> Void
    @State private var mathOpen = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Brand.s5) {
                VStack(alignment: .leading, spacing: Brand.s2) {
                    Eyebrow("Payment confirmed", color: .forest)
                    Text(firstName.map { "\($0), here's what your blood says." } ?? "Here's what your blood says.")
                        .font(.clarionDisplay(28))
                        .tracking(-0.02 * 28)
                        .foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                scoreCard

                if !w.problems.isEmpty {
                    VStack(alignment: .leading, spacing: Brand.s3) {
                        Eyebrow("What's off — and how to fix it")
                        ForEach(w.problems, id: \.self) { p in problemRow(p) }
                    }
                }

                VStack(spacing: Brand.s3) {
                    pickList("Need", tone: .forest, wash: .forestWash, picks: w.need, empty: "Nothing your blood demands.")
                    if !w.consider.isEmpty {
                        pickList("Consider", tone: .amber, wash: .amberWash, picks: w.consider, empty: "")
                    }
                    pickList("Consider dropping", tone: .clay, wash: .clayWash, picks: w.drop, empty: "Nothing — it all earns its place.")
                }

                if let m = w.money { moneyBand(m) }

                VStack(spacing: Brand.s2) {
                    Button("Open my full report", action: onOpenReport).buttonStyle(PrimaryButtonStyle())
                    Button("Go to Home", action: onHome)
                        .font(.clarionLabel(14))
                        .foregroundStyle(Color.ink3)
                        .padding(.vertical, Brand.s2)
                }
            }
            .padding(Brand.s5)
        }
        .background(Color.paper.ignoresSafeArea())
    }

    private var scoreCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.tap()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { mathOpen.toggle() }
            } label: {
                HStack(spacing: Brand.s4) {
                    ZStack {
                        Circle().stroke(Color.forestWash, lineWidth: 7)
                        Circle()
                            .trim(from: 0, to: CGFloat(w.score) / 100)
                            .stroke(Color.forest, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(w.score)").font(.clarionDisplay(24)).foregroundStyle(Color.ink)
                    }
                    .frame(width: 68, height: 68)
                    VStack(alignment: .leading, spacing: 3) {
                        (Text("Your score · ") + Text(ScoreEngine.label(for: w.score)).bold())
                            .font(.clarionBody(15)).foregroundStyle(Color.ink)
                        Text(scoreSub).font(.clarionBody(12.5)).foregroundStyle(Color.ink3)
                        HStack(spacing: 4) {
                            Text(mathOpen ? "Hide the math" : "See what went into it")
                            Image(systemName: mathOpen ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .bold))
                        }
                        .font(.clarionLabel(13)).foregroundStyle(Color.forest)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            if mathOpen {
                VStack(spacing: 6) {
                    mathRow("Everyone starts at", "100", bold: false)
                    ForEach(w.scoreLines, id: \.self) { l in
                        mathRow("\(l.marker) \(l.valueLabel)", "−\(l.pointsLost)", bold: false, tone: .clay)
                    }
                    Divider()
                    mathRow("Your score", "\(w.score)", bold: true)
                }
                .padding(.top, Brand.s3)
            }
        }
        .padding(Brand.s4)
        .background(Color.forestWash.opacity(0.5), in: RoundedRectangle(cornerRadius: Brand.rLG))
    }

    private var scoreSub: String {
        let lost = 100 - w.score
        let n = w.scoreLines.count
        return n > 0
            ? "\(n) marker\(n == 1 ? "" : "s") cost you \(lost) point\(lost == 1 ? "" : "s") · \(w.inRangeCount) in range"
            : "Every marker in range · \(w.inRangeCount) checked"
    }

    private func mathRow(_ l: String, _ r: String, bold: Bool, tone: Color = .ink) -> some View {
        HStack {
            Text(l).font(.clarionBody(13.5)).foregroundStyle(Color.ink2)
            Spacer()
            Text(r).font(.clarionData(13.5)).foregroundStyle(tone).fontWeight(bold ? .bold : .semibold)
        }
    }

    private func problemRow(_ p: AnalysisWelcomeData.Problem) -> some View {
        VStack(alignment: .leading, spacing: Brand.s2) {
            HStack(spacing: 6) {
                Text(p.marker).font(.clarionDisplay(17)).foregroundStyle(Color.ink)
                Text(p.valueLabel).font(.clarionData(13)).foregroundStyle(Color.ink3)
                Text(p.statusWord)
                    .font(.clarionLabel(11))
                    .foregroundStyle(p.tone == "low" ? Color.clay : Color.amber)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(p.tone == "low" ? Color.clayWash : Color.amberWash, in: Capsule())
            }
            if let target = p.targetLabel {
                Text(target.replacingOccurrences(of: "Your target: ", with: "Target "))
                    .font(.clarionBody(12.5)).foregroundStyle(Color.ink3)
            }
            HStack(alignment: .top, spacing: Brand.s2) {
                Text("FIX")
                    .font(.clarionLabel(10)).tracking(1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color.forest, in: RoundedRectangle(cornerRadius: 5))
                Text(p.fix).font(.clarionLabel(14)).foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Brand.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clarionCard()
    }

    private func pickList(_ title: String, tone: Color, wash: Color, picks: [AnalysisWelcomeData.Pick], empty: String) -> some View {
        VStack(alignment: .leading, spacing: Brand.s2) {
            HStack(spacing: 6) {
                Eyebrow(title, color: tone)
                if !picks.isEmpty {
                    Text("\(picks.count)").font(.clarionData(11)).foregroundStyle(tone)
                }
            }
            if picks.isEmpty {
                Text(empty).font(.clarionBody(13.5)).foregroundStyle(Color.ink3)
            } else {
                ForEach(picks.prefix(5), id: \.self) { p in
                    VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(p.name).font(.clarionLabel(14.5)).foregroundStyle(Color.ink)
                        if p.kind == "ask" {
                            Text("with your doctor").font(.clarionBody(12)).foregroundStyle(Color.ink3)
                        }
                        Spacer(minLength: 4)
                        if p.monthlyUsd > 0 {
                            Text("\(usd(p.monthlyUsd))/mo").font(.clarionData(12.5)).foregroundStyle(Color.ink3)
                        }
                    }
                    if let tag = p.tag, !tag.isEmpty {
                        Text(tag).font(.clarionBody(12)).foregroundStyle(Color.ink3)
                    }
                    }
                }
                if picks.count > 5 {
                    Text("+\(picks.count - 5) more in your report").font(.clarionBody(12.5)).foregroundStyle(Color.ink3)
                }
            }
        }
        .padding(Brand.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(wash.opacity(0.6), in: RoundedRectangle(cornerRadius: Brand.r))
    }

    private func moneyBand(_ m: AnalysisWelcomeData.Money) -> some View {
        let big: String, line: String
        if m.currentMonthly > 0 && m.netMonthly > 0 {
            big = "Save \(usd(m.netMonthly))/mo"
            line = "\(usd(m.currentMonthly))/mo now → \(usd(m.planMonthly))/mo on your plan."
        } else if m.cutMonthly > 0 {
            big = "Cut \(usd(m.cutMonthly))/mo"
            line = "Spent on supplements your blood doesn't back."
        } else {
            big = "\(usd(m.planMonthly))/mo"
            line = "Your whole plan. Nothing extra."
        }
        return VStack(alignment: .leading, spacing: 4) {
            Eyebrow("Your money", color: .forestInk)
            Text(big).font(.clarionDisplay(30)).foregroundStyle(Color.forestInk)
            Text(line).font(.clarionBody(13.5)).foregroundStyle(Color.ink2)
        }
        .padding(Brand.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.forestWash, in: RoundedRectangle(cornerRadius: Brand.rLG))
    }
}

// MARK: - Root presenter: fetch after purchase, show 2A (or the "add your labs" card)

struct PostPurchaseWelcome: View {
    let auth: SupabaseAuth
    var onOpenReport: () -> Void
    var onHome: () -> Void
    @State private var welcome: AnalysisWelcomeData?
    @State private var loaded = false

    var body: some View {
        Group {
            if let welcome {
                AnalysisWelcomeSheet(w: welcome, firstName: auth.firstName, onOpenReport: onOpenReport, onHome: onHome)
            } else if loaded {
                // Paid but no labs on file yet — same fallback as the web.
                VStack(alignment: .leading, spacing: Brand.s4) {
                    Eyebrow("Payment confirmed", color: .forest)
                    Text("Add your labs to see your analysis")
                        .font(.clarionDisplay(26)).foregroundStyle(Color.ink)
                    Text("Your unlock is active. Add your labs and you'll see what's off, how to fix it, what you need, and what to drop.")
                        .font(.clarionBody(15)).foregroundStyle(Color.ink2)
                    Button("Got it", action: onHome).buttonStyle(PrimaryButtonStyle())
                }
                .padding(Brand.s6)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Color.paper.ignoresSafeArea())
            } else {
                ClarionLoadingView().background(Color.paper.ignoresSafeArea())
            }
        }
        .task { await load() }
    }

    private func load() async {
        #if DEBUG
        if AnalysisWelcomeFixture.has("UITEST_WELCOME") { welcome = AnalysisWelcomeFixture.sample?.welcome; loaded = true; return }
        #endif
        // The purchase was just mirrored to the server; one retry covers a slow write.
        for attempt in 0..<2 {
            if let token = try? await auth.validAccessToken(),
               let r = try? await ClarionAPI.fetchAnalysisWelcome(accessToken: token),
               r.welcome != nil || attempt == 1 {
                welcome = r.welcome
                break
            }
            try? await Task.sleep(for: .seconds(1.5))
        }
        loaded = true
    }
}

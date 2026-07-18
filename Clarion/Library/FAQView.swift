import SwiftUI
import UIKit

/// Native FAQ — a build-time snapshot of the web's static FAQ page
/// (src/components/clarion-site/pages/ClarionSiteFaq.tsx: five groups, nine Q&As).
/// The content is static on the web too, so snapshotting it native costs nothing;
/// grouped expandable rows on the card recipe, serif questions, one support card
/// with mailto + the Terms/Privacy links. Web-only phrasing ("Help button,
/// bottom-left") is adapted to the app's surfaces.
struct FAQView: View {

    struct Item: Identifiable {
        let question: String
        let answer: String
        var id: String { question }
    }

    struct FAQGroup: Identifiable {
        let label: String
        let items: [Item]
        var id: String { label }
    }

    /// Snapshot of the web FAQ groups (faq page), lightly adapted for the app.
    static let groups: [FAQGroup] = [
        FAQGroup(label: "Getting started", items: [
            Item(question: "What is Clarion Labs?",
                 answer: "Clarion Labs helps you understand bloodwork in plain language, see a health score, and get structured next steps — including supplement and lifestyle context. It is for education and decision support, not a substitute for your doctor."),
            Item(question: "How do I create or access my account?",
                 answer: "Sign in with the same account you use on clarionlabs.tech — email, Google, or Apple. Your dashboard saves after you complete onboarding or purchase analysis access."),
        ]),
        FAQGroup(label: "Plans & billing", items: [
            Item(question: "How does billing work?",
                 answer: "Clarion+ and one-time analysis access are managed through your account. For receipt or billing questions, contact support with the email on this page."),
            Item(question: "What is Clarion Lite?",
                 answer: "Clarion Lite is a lower-priced subscription that gives you dashboard access and education based on your profile and symptoms — not on your lab results. It does not provide biomarker scoring, personalized lab interpretation, or lab-matched dosing. Full Clarion adds the one-time analysis and bloodwork-based personalization. Clarion Lite is for education and habit support only, not a substitute for labs or medical care."),
        ]),
        FAQGroup(label: "Your labs & dashboard", items: [
            Item(question: "How do I add or update my lab results?",
                 answer: "From Home, use \"Add labs\" — a photo or PDF of any panel works. After you have results saved, you can add new panels or updates any time; your report and plan recalibrate to the latest draw."),
            Item(question: "Where do I find my score, plan, and trends?",
                 answer: "Your score and daily brief live on Home. The Report and Plan tabs hold your full analysis and supplement stack; Labs history and Biomarkers (in the Library) track every panel and marker over time."),
        ]),
        FAQGroup(label: "Trust & safety", items: [
            Item(question: "Is this medical advice?",
                 answer: "No. Clarion provides education and decision support only. It does not diagnose or prescribe. Always talk to a qualified clinician about your results, supplements, and treatment."),
            Item(question: "How is my data handled?",
                 answer: "We use secure sign-in and store your profile and lab-related data to run the product. See our Terms for the full disclaimer and limitations. Do not share emergency health information through chat — call emergency services or your clinician."),
        ]),
        FAQGroup(label: "Support", items: [
            Item(question: "How can I contact support?",
                 answer: "Use Ask Clarion in the app for product and account questions, or browse this FAQ. For issues we can't resolve there, email the support address below."),
        ]),
    ]

    private static let supportEmail = "support@clarionlabs.tech"

    @State private var expanded: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Brand.s5) {
                Text("Quick answers about accounts, labs, the dashboard, and how Clarion fits alongside your clinician.")
                    .font(.clarionBody(14.5))
                    .foregroundStyle(Color.ink2)
                    .entrance(0)

                ForEach(Array(Self.groups.enumerated()), id: \.element.id) { i, group in
                    groupCard(group).entrance(1 + i)
                }

                supportCard.entrance(1 + Self.groups.count)
                legalLinks.entrance(2 + Self.groups.count)
            }
            .padding(Brand.s5)
        }
        .contentMargins(.bottom, 96, for: .scrollContent)
        .background(Color.paper.ignoresSafeArea())
        .navigationTitle("FAQ")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Q&A groups (grouped expandable rows, serif questions)

    private func groupCard(_ group: FAQGroup) -> some View {
        VStack(alignment: .leading, spacing: Brand.s2 + 2) {
            Eyebrow(group.label).padding(.horizontal, Brand.s1)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(group.items.enumerated()), id: \.element.id) { i, item in
                    if i > 0 {
                        Rectangle().fill(Color.line).frame(height: 1).padding(.leading, Brand.s4)
                    }
                    qaRow(item)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clarionCard()
        }
    }

    private func qaRow(_ item: Item) -> some View {
        let isOpen = expanded.contains(item.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.tap()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    if isOpen { expanded.remove(item.id) } else { expanded.insert(item.id) }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: Brand.s3) {
                    Text(item.question)
                        .font(.clarionDisplay(16))
                        .tracking(-0.015 * 16)
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.ink4)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(.horizontal, Brand.s4)
                .padding(.vertical, Brand.s3 + 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle(haptic: false))
            if isOpen {
                Text(item.answer)
                    .font(.clarionBody(14))
                    .foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Brand.s4)
                    .padding(.bottom, Brand.s4)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Support + legal

    private var supportCard: some View {
        VStack(alignment: .leading, spacing: Brand.s3) {
            Text("Still need a hand?")
                .font(.clarionDisplay(18))
                .tracking(-0.015 * 18)
                .foregroundStyle(Color.ink)
            Text("For billing, access, or bugs we can't resolve in the app, reach us directly.")
                .font(.clarionBody(14))
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Haptics.tap()
                if let url = URL(string: "mailto:\(Self.supportEmail)") {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: Brand.s3) {
                    Image(systemName: "envelope")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.forest)
                        .frame(width: 36, height: 36)
                        .background(Color.forestWash, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Contact support")
                            .font(.clarionLabel(14))
                            .foregroundStyle(Color.ink)
                        Text(Self.supportEmail)
                            .font(.clarionBody(12.5))
                            .foregroundStyle(Color.ink3)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.ink4)
                }
                .padding(Brand.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clarionCardQuiet(cornerRadius: Brand.r)
            }
            .buttonStyle(PressableStyle(haptic: false))
        }
        .padding(Brand.s4 + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clarionCard()
    }

    private var legalLinks: some View {
        HStack(spacing: Brand.s4) {
            Link(destination: Config.apiBase.appendingPathComponent("terms")) {
                Text("Terms & Disclaimer")
            }
            Text("·").foregroundStyle(Color.ink4)
            Link(destination: Config.apiBase.appendingPathComponent("legal/privacy")) {
                Text("Privacy")
            }
        }
        .font(.clarionBody(13))
        .foregroundStyle(Color.ink3)
        .frame(maxWidth: .infinity)
    }
}

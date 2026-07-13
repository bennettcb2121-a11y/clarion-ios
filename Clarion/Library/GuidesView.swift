import SwiftUI

/// Guides — native browse cards over a static catalog, with the DETAIL handed
/// off to the web (the parity spec's recommendation: guide bodies are authored
/// HTML stitched from seven content libs and change without an app release, so
/// porting them natively buys little on a low-traffic surface).
///
/// The catalog below is a build-time snapshot of src/lib/guides.ts +
/// guidesHandoffData.ts (5 guides, stable slugs). New guides appear natively on
/// the next app update; the web list is always complete.
struct GuidesView: View {
    let auth: SupabaseAuth

    struct GuideCard: Identifiable {
        var slug: String
        var title: String
        var description: String
        var topics: [Topic]
        var readMinutes: Int

        var id: String { slug }
    }

    enum Topic: String, CaseIterable {
        case labs, supplements, endurance, money, longevity

        /// Chip labels (GUIDE_TOPIC_CHIPS, guidesHandoffData.ts:8).
        var chipLabel: String {
            switch self {
            case .labs: return "Reading your labs"
            case .supplements: return "Supplements"
            case .endurance: return "Endurance"
            case .money: return "Saving money"
            case .longevity: return "Longevity"
            }
        }

        /// Card tag labels (topicTagLabel).
        var tagLabel: String {
            switch self {
            case .labs: return "Labs"
            case .supplements: return "Supplements"
            case .endurance: return "Endurance"
            case .money: return "Money"
            case .longevity: return "Longevity"
            }
        }
    }

    /// Snapshot of GUIDES + SLUG_TOPICS + SLUG_READ_MINUTES.
    static let catalog: [GuideCard] = [
        GuideCard(slug: "iron",
                  title: "How to improve your iron and ferritin",
                  description: "Diet, supplements, and timing to support healthy iron stores.",
                  topics: [.supplements, .endurance, .labs], readMinutes: 7),
        GuideCard(slug: "vitamin-d",
                  title: "How to improve your vitamin D",
                  description: "Sun, food, and supplements to reach and maintain a healthy level.",
                  topics: [.supplements, .longevity, .money], readMinutes: 6),
        GuideCard(slug: "magnesium-sleep",
                  title: "Magnesium and sleep",
                  description: "How magnesium supports sleep, recovery, and when to take it.",
                  topics: [.supplements, .endurance, .longevity], readMinutes: 5),
        GuideCard(slug: "b12-absorption",
                  title: "Understanding B12 absorption",
                  description: "Why B12 can be low and how to improve absorption.",
                  topics: [.supplements, .labs, .money], readMinutes: 7),
        GuideCard(slug: "gut-health",
                  title: "Gut health basics",
                  description: "Diet, fiber, and habits that support a healthy gut.",
                  topics: [.longevity, .supplements, .money], readMinutes: 4),
    ]

    @State private var topic: Topic? = nil
    @State private var openingWeb = false

    private var filtered: [GuideCard] {
        guard let topic else { return Self.catalog }
        return Self.catalog.filter { $0.topics.contains(topic) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Brand.s5) {
                Text("Short, sourced reads on moving the markers that matter — written to pair with your panel.")
                    .font(.clarionBody(14.5))
                    .foregroundStyle(Color.ink2)
                    .entrance(0)

                topicChips.entrance(1)

                VStack(spacing: Brand.s3) {
                    ForEach(filtered) { guide in
                        guideCard(guide)
                    }
                }
                .entrance(2)

                Text("Guides open in your browser.")
                    .font(.clarionBody(11.5))
                    .foregroundStyle(Color.ink4)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(Brand.s5)
        }
        .background(Color.paper.ignoresSafeArea())
        .navigationTitle("Guides")
        .navigationBarTitleDisplayMode(.large)
    }

    private var topicChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Brand.s2) {
                chip("All", active: topic == nil) { topic = nil }
                ForEach(Topic.allCases, id: \.self) { t in
                    chip(t.chipLabel, active: topic == t) { topic = t }
                }
            }
        }
    }

    private func chip(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.clarionLabel(12))
                .foregroundStyle(active ? Color.white : Color.ink2)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(active ? Color.forest : Color.surface2, in: Capsule())
                .overlay(Capsule().stroke(active ? Color.clear : Color.line2))
        }
        .buttonStyle(PressableStyle())
    }

    private func guideCard(_ guide: GuideCard) -> some View {
        Button {
            openGuide(guide)
        } label: {
            VStack(alignment: .leading, spacing: Brand.s2) {
                // Tag = active filter topic when narrowed, else primary topic.
                let tag = (topic.flatMap { guide.topics.contains($0) ? $0 : nil } ?? guide.topics.first)
                if let tag {
                    Eyebrow(tag.tagLabel, color: .forest)
                }
                Text(guide.title)
                    .font(.clarionDisplay(17))
                    .tracking(-0.015 * 17)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.leading)
                Text(guide.description)
                    .font(.clarionBody(13))
                    .foregroundStyle(Color.ink3)
                    .multilineTextAlignment(.leading)
                HStack {
                    Text("\(guide.readMinutes) min read")
                        .font(.clarionData(11.5))
                        .foregroundStyle(Color.ink3)
                    Spacer()
                    HStack(spacing: 3) {
                        Text("Read")
                            .font(.clarionLabel(12))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(Color.forest)
                }
                .padding(.top, Brand.s1)
            }
            .padding(Brand.s4 + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clarionCard()
        }
        .buttonStyle(PressableStyle())
        .disabled(openingWeb)
    }

    private func openGuide(_ guide: GuideCard) {
        Task {
            openingWeb = true
            defer { openingWeb = false }
            // /guides isn't on the app-login-link whitelist (dashboard paths
            // only), so this opens the plain URL — LibraryWeb falls back
            // automatically. Widening the whitelist server-side would land
            // these signed-in.
            await LibraryWeb.open(path: "/guides/\(guide.slug)", auth: auth)
        }
    }
}

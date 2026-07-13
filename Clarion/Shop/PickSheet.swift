import SwiftUI
import SafariServices

/// The Clarion Pick sheet — the native ClarionPickPanel: a one-line lab status built
/// from the user's own result, the suppression notice when labs argue against buying,
/// the hero + alternatives as selectable radio options, and one buy action for the
/// selection.
///
/// Buying ALWAYS opens buy.url in SFSafariViewController. The URL is our own
/// /go/amazon redirect on clarionlabs.tech — never amazon.com directly — so the first
/// tap stays on our domain and the Amazon app can't intercept it and strip the
/// affiliate tag. The route serves mobile UAs an HTML interstitial designed for
/// exactly this in-app webview case.
struct PickSheet: View {
    let card: ShopCard

    @Environment(\.dismiss) private var dismiss
    @State private var selectedId = "hero"
    @State private var safari: SafariItem?

    private var selected: ShopOption {
        card.options.first { $0.id == selectedId } ?? card.options[0]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Brand.s4) {
                    Text(card.overview)
                        .font(.clarionBody(13.5))
                        .foregroundStyle(Color.ink2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let gap = card.labGap {
                        statusLine(gap)
                    }

                    if card.suppressPurchase {
                        suppressNote
                    }

                    VStack(spacing: Brand.s2) {
                        ForEach(card.options) { option in
                            optionRow(option)
                        }
                    }

                    buyArea

                    if let caution = card.caution {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.shield")
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.top, 2)
                            Text(caution)
                                .font(.clarionBody(12))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(Color.ink3)
                    }

                    Text(selected.buy.fulfillmentNote)
                        .font(.clarionBody(12))
                        .foregroundStyle(Color.ink3)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                .padding(Brand.s5)
            }
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle(card.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.ink3)
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .sheet(item: $safari) { item in
            SafariView(url: item.url).ignoresSafeArea()
        }
    }

    // MARK: - Lab status line

    /// Calm one-line lab status — a tone dot, not a red box: "Your Ferritin 34 — below
    /// your 50–150 target", with the retest cadence tucked underneath.
    private func statusLine(_ gap: ShopLabGap) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Circle()
                    .fill(dotTone(gap.direction))
                    .frame(width: 8, height: 8)
                (
                    Text("Your \(gap.markerName) ")
                    + Text(gap.valueLabel).font(.clarionData(13.5)).foregroundStyle(Color.ink)
                    + Text(" — \(gap.clause)")
                )
                .font(.clarionBody(13.5))
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
            }
            if let retest = gap.retest {
                Text(retest)
                    .font(.clarionBody(12.5))
                    .foregroundStyle(Color.ink3)
                    .padding(.leading, 17)
            }
        }
    }

    private func dotTone(_ direction: String) -> Color {
        switch direction {
        case "below": return .clay
        case "above": return .amber
        case "in_band": return .forest
        default: return .ink3
        }
    }

    // MARK: - Suppression notice

    /// Why the buy CTA is demoted — the honest "your labs argue against this" box.
    private var suppressNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.clay)
                .padding(.top, 1)
            Text(card.warning.detail)
                .font(.clarionBody(13))
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Brand.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.clayWash, in: RoundedRectangle(cornerRadius: Brand.r))
        .overlay(RoundedRectangle(cornerRadius: Brand.r).stroke(Color.clay.opacity(0.5)))
    }

    // MARK: - Selectable options

    /// One radio option — same card DNA as the grid. The Clarion Pick is expressed by
    /// its tier eyebrow only, never a different card build; forest border = SELECTION.
    private func optionRow(_ option: ShopOption) -> some View {
        let isSel = option.id == selectedId
        return Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                selectedId = option.id
            }
        } label: {
            HStack(alignment: .top, spacing: Brand.s3) {
                ZStack {
                    Circle()
                        .strokeBorder(isSel ? Color.forest : Color.line2, lineWidth: 2)
                        .background(Circle().fill(isSel ? Color.forest : Color.clear))
                        .frame(width: 20, height: 20)
                    if isSel {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Eyebrow(option.tierLabel, color: option.isHero ? .forestInk : .ink3)
                    Text(option.fullName)
                        .font(.clarionDisplay(15.5))
                        .tracking(-0.01 * 15.5)
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let dose = option.dose {
                        Text(dose)
                            .font(.clarionData(12))
                            .foregroundStyle(Color.ink3)
                    }
                    if let why = option.why {
                        Text(why)
                            .font(.clarionBody(12.5))
                            .foregroundStyle(Color.ink2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                }

                Spacer(minLength: Brand.s2)

                Text(option.priceLabel)
                    .font(.clarionData(14))
                    .foregroundStyle(Color.ink)
            }
            .padding(Brand.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSel ? Color.forestWash : Color.surface,
                in: RoundedRectangle(cornerRadius: Brand.rLG)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Brand.rLG)
                    .stroke(isSel ? Color.forest : Color.line, lineWidth: isSel ? 1.5 : 1)
            )
            .shadow(color: Color.shadowE1, radius: 2, y: 1)
            .contentShape(RoundedRectangle(cornerRadius: Brand.rLG))
        }
        .buttonStyle(PressableStyle(haptic: false))
    }

    // MARK: - Buy

    /// The buy action for the SELECTED option. suppressPurchase demotes the forest CTA
    /// to a ghost "Buy anyway" — the choice stays with the user, the emphasis doesn't.
    @ViewBuilder
    private var buyArea: some View {
        let buy = selected.buy
        if buy.isExternalLink, let url = buy.resolvedURL {
            if card.suppressPurchase {
                Button {
                    Haptics.tap()
                    safari = SafariItem(url: url)
                } label: {
                    buyLabel("Buy anyway")
                }
                .buttonStyle(SecondaryButtonStyle())
            } else {
                Button {
                    Haptics.commit()
                    safari = SafariItem(url: url)
                } label: {
                    buyLabel(buy.label.isEmpty ? "Buy on Amazon" : buy.label)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        } else {
            // in_app_cart (dropship) has no native cart yet — surface the fulfillment
            // note instead of a dead button; the web dashboard handles these SKUs.
            Text(buy.fulfillmentNote)
                .font(.clarionBody(12.5))
                .foregroundStyle(Color.ink3)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }

    private func buyLabel(_ text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.up.right.square")
                .font(.system(size: 13, weight: .semibold))
            Text(text)
        }
    }
}

// MARK: - Safari handoff

/// Identifiable wrapper so `.sheet(item:)` can present a URL.
private struct SafariItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// In-app Safari for the /go/amazon affiliate handoff. NEVER swap this for
/// UIApplication.open on an amazon.com URL — the whole point is that the first
/// navigation happens on our domain, inside our webview.
private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

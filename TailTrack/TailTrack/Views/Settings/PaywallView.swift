import SwiftUI
import StoreKit

/// TailTrack Pro upgrade sheet.
struct PaywallView: View {
    @Environment(ProStore.self) private var pro
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    hero
                    featureList
                    productButtons
                    madeByCard
                    footerLinks
                }
                .padding()
                .readableContentWidth()
            }
            .background(Theme.paper)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: pro.isPro) { _, isPro in
                if isPro { dismiss() }
            }
            .sensoryFeedback(.success, trigger: pro.isPro) { _, isPro in isPro }
            .task { await pro.loadProducts() }
        }
    }

    private var hero: some View {
        VStack(spacing: 10) {
            Image(systemName: "airplane.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.proGold)
            Text("TailTrack Pro")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .tracking(-0.8)
                .foregroundStyle(.white)
            Text(pro.trialLength.map { "Try everything free for \($0)." }
                 ?? "For pilots who fly more than one plane —\nand want their data everywhere.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Theme.sky, in: RoundedRectangle(cornerRadius: 24))
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 14) {
            feature("airplane", "Unlimited aircraft", "Free covers one plane; Pro covers the whole hangar and rentals.")
            feature("person.2.fill", "Crew Mode", "Track any airline flight by callsign — DAL, AAL, UAL, and everyone else.")
            feature("chart.bar.fill", "Pilot Stats", "Hours by month, personal records, most-visited airports.")
            feature("doc.viewfinder", "Logbook page scanning", "Photograph your paper logbook — on-device recognition imports the entries.")
            feature("point.topleft.down.to.point.bottomright.curvepath", "Past flight paths", "TailTrack finds the real ADS-B track of flights you flew before you had the app, back as far as the archives go.")
            feature("square.and.arrow.up", "Exports & share cards", "GPX and CSV per flight, your whole logbook as one CSV, and shareable flight cards.")
            feature("globe.americas.fill", "Satellite maps", "Hybrid satellite imagery with realistic terrain on the live map.")
            feature("paintpalette.fill", "Customize TailTrack", "Five more accent colors and three alternate app icons.")
            feature("person.3.fill", "Family Sharing", "One purchase covers everyone in your family group.")
        }
        .padding(18)
        .cardSurface(18)
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var productButtons: some View {
        if pro.products.isEmpty {
            VStack(spacing: 8) {
                if pro.isLoading {
                    ProgressView()
                }
                Text(pro.purchaseError ?? "Products unavailable. If you're running a local build, select TailTrack.storekit in the scheme's StoreKit Configuration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        } else {
            VStack(spacing: 10) {
                ForEach(pro.products, id: \.id) { product in
                    Button {
                        Task { await pro.purchase(product) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(product.displayName)
                                    .font(.headline)
                                Text(subtitle(for: product))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(product.displayPrice)
                                .font(.system(.headline, design: .rounded))
                        }
                        .padding(14)
                        .cardSurface(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(isBestValue(product) ? Theme.proGold : .clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.pressable)
                    .foregroundStyle(.primary)
                }
                if let error = pro.purchaseError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func subtitle(for product: Product) -> String {
        if let trial = pro.freeTrial(for: product) {
            let per = product.id == ProStore.ProductID.monthly ? "month" : "year"
            return "\(ProStore.length(of: trial)) free, then \(product.displayPrice) a \(per)"
        }
        switch product.id {
        case ProStore.ProductID.monthly: return "Billed monthly · cancel anytime"
        case ProStore.ProductID.yearly: return "Best value — under $2/month"
        case ProStore.ProductID.lifetime: return "One purchase, yours forever"
        default: return ""
        }
    }

    /// Apple requires the trial and renewal terms next to the purchase
    /// buttons.
    private var renewalTerms: String {
        let renewal = "Subscriptions renew automatically until cancelled in Settings → your name → Subscriptions. Prices shown in your local currency at purchase."
        guard let trial = pro.trialLength else { return renewal }
        return "The free trial is for new subscribers. After \(trial), the subscription starts at the price shown unless you cancel at least 24 hours before the trial ends. " + renewal
    }

    private func isBestValue(_ product: Product) -> Bool {
        product.id == ProStore.ProductID.yearly
    }

    private var madeByCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("By a pilot, for pilots", systemImage: "graduationcap.fill")
                .font(.headline)
            Text("TailTrack is designed and built by a high school student pilot. Subscribing supports a student's work and keeps TailTrack independent, ad-free and growing, for student pilots, seasoned pilots and anyone who just loves to fly.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(18)
    }

    private var footerLinks: some View {
        VStack(spacing: 8) {
            Button("Restore Purchases") {
                Task { await pro.restorePurchases() }
            }
            .font(.callout)
            HStack(spacing: 14) {
                NavigationLink("Terms of Service") {
                    LegalDocumentView(title: "Terms of Service",
                                      text: LegalDocuments.termsOfService)
                }
                NavigationLink("Privacy Policy") {
                    LegalDocumentView(title: "Privacy Policy",
                                      text: LegalDocuments.privacyPolicy)
                }
            }
            .font(.caption.weight(.semibold))
            Text(renewalTerms)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }
}

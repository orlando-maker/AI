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
                    footerLinks
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: pro.isPro) { _, isPro in
                if isPro { dismiss() }
            }
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
                .foregroundStyle(.white)
            Text("For pilots who fly more than one plane —\nand want their data everywhere.")
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
            feature("square.and.arrow.up", "GPX & CSV export", "Pull any flight into ForeFlight, Google Earth, or a spreadsheet.")
            feature("globe.americas.fill", "Satellite maps", "Hybrid satellite imagery with realistic terrain on the live map.")
            feature("heart.fill", "Support development", "Keeps TailTrack improving — and the core tracker free for everyone.")
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
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
                        .background(.background, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(isBestValue(product) ? Theme.proGold : .clear, lineWidth: 2)
                        )
                    }
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
        switch product.id {
        case ProStore.ProductID.monthly: return "Billed monthly · cancel anytime"
        case ProStore.ProductID.yearly: return "Best value — under $2/month"
        case ProStore.ProductID.lifetime: return "One purchase, yours forever"
        default: return ""
        }
    }

    private func isBestValue(_ product: Product) -> Bool {
        product.id == ProStore.ProductID.yearly
    }

    private var footerLinks: some View {
        VStack(spacing: 8) {
            Button("Restore Purchases") {
                Task { await pro.restorePurchases() }
            }
            .font(.callout)
            Text("Subscriptions renew automatically until cancelled in Settings. Prices shown in your local currency at purchase.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }
}

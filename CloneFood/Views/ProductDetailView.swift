//
//  ProductDetailView.swift
//  CloneFood
//
//  Created by Demex on 18/12/2025
//

import SwiftUI
import UIKit

struct ProductDetailView: View {
    let product: Product
    @ObservedObject var viewModel: FoodScannerViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab = 0
    @State private var isVisible = false
    @State private var scoreCardScale: CGFloat = 0.8
    @State private var scoreCardOpacity: CGFloat = 0
    @State private var hasPlayedHaptic = false
    @State private var actionBarVisible = false
    @Namespace private var tabControlNamespace

    private var tabTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal: .opacity.combined(with: .move(edge: .leading))
        )
    }

    var body: some View {
        ZStack {
            AppBackdrop()

            ScrollView {
                VStack(spacing: 0) {
                    if viewModel.isShowingCachedProduct {
                        OfflineBanner(
                            lastSeenDate: viewModel.lastSeenDate(for: product.code),
                            isRefreshing: viewModel.isRefreshing,
                            onRefresh: {
                                Task {
                                    await viewModel.refreshCurrentProduct()
                                }
                            }
                        )
                        .padding(.top, 20)
                    }
                    // Header with close button
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(.title2, design: .default))
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Close product details")
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .padding(.bottom, 10)
                    
                    // Product image and basic info
                    VStack(spacing: 20) {
                        VStack(spacing: 20) {
                            // Product image
                            HeroProductArtwork(product: product)
                            
                            // Product name and brand
                            VStack(spacing: 8) {
                                Text(product.displayName)
                                    .font(.system(.title2, design: .rounded).weight(.bold))
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                
                                if !product.brand.isEmpty {
                                    Text(product.brand)
                                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                                        .foregroundColor(.secondary)
                                }

                                SummaryChip(label: product.score.summaryLabel, color: product.score.summaryColor)

                                VerdictBanner(score: product.score, reasons: product.scoreReasons)

                                DietaryConflictBanner(conflicts: viewModel.conflictsForCurrentProfile(product))
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.bottom, 30)
                        
                        // Confidence assessment card
                        ConfidenceCard(score: product.score)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                            .scaleEffect(scoreCardScale)
                            .opacity(scoreCardOpacity)
                            .animation(reduceMotion ? nil : .spring(response: 0.8, dampingFraction: 0.7).delay(0.3), value: scoreCardScale)

                        ProductInsightSummaryCard(
                            score: product.score,
                            alertCount: HealthAlertsCard.alerts(for: product).count,
                            highlightCount: NutritionHighlightsCard.highlights(for: product).count,
                            alternativeCount: viewModel.betterAlternatives(for: product, limit: 3).count
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                        // Tab selector
                        DetailSegmentControl(
                            selectedTab: $selectedTab,
                            namespace: tabControlNamespace,
                            reduceMotion: reduceMotion
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                        .transition(.opacity)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: selectedTab)
                        
                        // Tab content
                        Group {
                            if selectedTab == 0 {
                                ScoresTabView(
                                    product: product,
                                    previousProduct: viewModel.previousProduct,
                                    alternatives: viewModel.betterAlternatives(for: product, limit: 3),
                                    onSelectAlternative: { selected in
                                        viewModel.selectProduct(selected)
                                    }
                                )
                                .transition(tabTransition)
                            } else if selectedTab == 1 {
                                NutritionTabView(
                                    product: product,
                                    alerts: HealthAlertsCard.alerts(for: product),
                                    highlights: NutritionHighlightsCard.highlights(for: product)
                                )
                                .transition(tabTransition)
                            } else {
                                IngredientsTabView(product: product, watchedTerms: viewModel.watchlistTerms)
                                    .transition(tabTransition)
                            }
                        }
                        .padding(.bottom, 100)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: selectedTab)
                    }
                    .opacity(isVisible ? 1 : 0)
                    .offset(y: isVisible ? 0 : 30)
                    .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.8).delay(0.1), value: isVisible)
                }
                .overlay(alignment: .bottom) {
                    // Bottom action bar
                    HStack(spacing: 16) {
                        Button(action: {
                            viewModel.markScanAgainRequested()
                            dismiss()
                        }) {
                            Label("Scan Again", systemImage: "barcode.viewfinder")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    Capsule()
                                        .fill(Color(.secondarySystemBackground))
                                )
                        }
                        .accessibilityLabel("Scan another product")

                        Button(action: {
                            viewModel.toggleFavorite(product)
                        }) {
                            Image(systemName: viewModel.isFavorite(product) ? "heart.fill" : "heart")
                                .font(.system(.title3, design: .default))
                                .foregroundColor(viewModel.isFavorite(product) ? .red : .secondary)
                                .padding(16)
                                .background(
                                    Circle()
                                        .fill(Color(.secondarySystemBackground))
                                        .background(
                                            Circle()
                                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                        )
                                        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                                )
                        }
                        .accessibilityLabel(viewModel.isFavorite(product) ? "Remove from favorites" : "Add to favorites")

                        if let url = product.productURL {
                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(.title3, design: .default))
                                    .foregroundColor(.secondary)
                                    .padding(16)
                                    .background(
                                        Circle()
                                            .fill(Color(.secondarySystemBackground))
                                            .background(
                                                Circle()
                                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                            )
                                            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                                    )
                            }
                            .accessibilityLabel("Share product")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .glassCard(cornerRadius: 28)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                    .opacity(actionBarVisible ? 1 : 0)
                    .offset(y: actionBarVisible ? 0 : 24)
                    .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.84).delay(0.22), value: actionBarVisible)
                }
                .onAppear {
                    if reduceMotion {
                        isVisible = true
                        scoreCardScale = 1.0
                        scoreCardOpacity = 1.0
                        actionBarVisible = true
                    } else {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            isVisible = true
                        }
                        withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.2)) {
                            scoreCardScale = 1.0
                            scoreCardOpacity = 1.0
                        }
                        withAnimation(.spring(response: 0.52, dampingFraction: 0.84).delay(0.22)) {
                            actionBarVisible = true
                        }
                    }
                    playScoreHapticIfNeeded()
                }
                .onChange(of: selectedTab) { _, _ in
                    guard !reduceMotion else { return }
                    AppHaptics.selectionChanged()
                }
            }
        }
    }
}

extension ProductDetailView {
    private func playScoreHapticIfNeeded() {
        guard !hasPlayedHaptic else { return }
        hasPlayedHaptic = true

        switch product.score.overallScore {
        case 80...100:
            AppHaptics.notify(.success)
        case 60...79:
            AppHaptics.notify(.success)
        case 40...59:
            AppHaptics.notify(.warning)
        default:
            AppHaptics.notify(.error)
        }
    }
}

struct HeroProductArtwork: View {
    let product: Product
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floatUp = false
    @State private var pressed = false

    var body: some View {
        Group {
            if let imageURL = product.imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        placeholder(progress: true)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 156, height: 156)
                            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                            .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 8)
                    case .failure:
                        placeholder(progress: false)
                    @unknown default:
                        placeholder(progress: false)
                    }
                }
            } else {
                placeholder(progress: false)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.4), lineWidth: 0.8)
                )
        )
        .scaleEffect(pressed ? 0.97 : 1)
        .offset(y: floatUp ? -4 : 4)
        .animation(reduceMotion ? nil : .easeInOut(duration: 2.7).repeatForever(autoreverses: true), value: floatUp)
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.78), value: pressed)
        .onAppear {
            floatUp = true
        }
        .onTapGesture {
            AppHaptics.impact(.soft)
            pressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                pressed = false
            }
        }
    }

    private func placeholder(progress: Bool) -> some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.gray.opacity(0.18))
            .frame(width: 156, height: 156)
            .overlay {
                if progress {
                    ProgressView()
                } else {
                    Image(systemName: "photo")
                        .font(.system(.title, design: .default))
                        .foregroundColor(.gray)
                }
            }
    }
}

struct DetailSegmentControl: View {
    @Binding var selectedTab: Int
    var namespace: Namespace.ID
    let reduceMotion: Bool

    private let titles: [(String, Int)] = [
        ("Scores", 0),
        ("Nutrition", 1),
        ("Ingredients", 2)
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(titles, id: \.1) { item in
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.84)) {
                        selectedTab = item.1
                    }
                } label: {
                    Text(item.0)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundColor(selectedTab == item.1 ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if selectedTab == item.1 {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.thickMaterial)
                                    .matchedGeometryEffect(id: "detail-tab", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 0.8)
                )
        )
    }
}

struct SummaryChip: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.system(.footnote, design: .rounded).weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
            .accessibilityLabel("Overall rating \(label)")
    }
}

struct VerdictBanner: View {
    let score: ProductScore
    let reasons: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: score.summaryLabel == "Excellent" ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(score.summaryColor)
                Text(score.summaryLabel)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundColor(.primary)
            }

            Text(reasons.joined(separator: " · "))
                .font(.system(.subheadline, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(score.summaryColor.opacity(0.25), lineWidth: 1)
                )
        )
        .accessibilityLabel("Overall verdict \(score.summaryLabel). \(reasons.joined(separator: ", "))")
    }
}

struct DietaryConflictBanner: View {
    let conflicts: [DietaryPreference]

    var body: some View {
        if conflicts.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Profile warning", systemImage: "exclamationmark.shield.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.orange)

                Text("This product may conflict with your dietary profile.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    ForEach(conflicts.prefix(3)) { conflict in
                        Label(conflict.title, systemImage: conflict.symbol)
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(conflict.tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(conflict.tint.opacity(0.14))
                            )
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                    )
            )
            .accessibilityLabel("Dietary profile warning")
        }
    }
}

struct OfflineBanner: View {
    let lastSeenDate: Date?
    let isRefreshing: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.system(.footnote, design: .default).weight(.semibold))

            VStack(alignment: .leading, spacing: 2) {
                Text("Offline — showing last scanned data")
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundColor(.secondary)

                if let lastSeenDate {
                    Text("Last updated \(lastSeenDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button(action: onRefresh) {
                if isRefreshing {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text("Update")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .disabled(isRefreshing)
            .accessibilityLabel("Update product data")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
        )
        .padding(.horizontal, 20)
    }
}

struct ProductInsightSummaryCard: View {
    let score: ProductScore
    let alertCount: Int
    let highlightCount: Int
    let alternativeCount: Int

    var body: some View {
        HStack(spacing: 12) {
            InsightMiniPill(symbol: "gauge.with.needle", title: "Score", value: "\(score.overallScore)", tint: score.summaryColor)
            InsightMiniPill(symbol: "exclamationmark.triangle", title: "Alerts", value: "\(alertCount)", tint: alertCount > 0 ? .orange : .green)
            InsightMiniPill(symbol: "sparkles", title: "Highlights", value: "\(highlightCount)", tint: .blue)
            InsightMiniPill(symbol: "arrow.triangle.branch", title: "Alternatives", value: "\(alternativeCount)", tint: .mint)
        }
        .padding(14)
        .glassCard(cornerRadius: 16)
    }
}

struct InsightMiniPill: View {
    let symbol: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
            Text(title)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(tint.opacity(0.12))
        )
    }
}

struct CompareCard: View {
    let current: Product
    let previous: Product

    var body: some View {
        let delta = current.score.overallScore - previous.score.overallScore
        let deltaText = delta == 0 ? "Same score as last scan" : "\(abs(delta)) points \(delta > 0 ? "healthier" : "less healthy") than last scan"
        let deltaColor: Color = delta == 0 ? .secondary : (delta > 0 ? .green : .red)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Compare to last scan")
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundColor(.primary)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(current.displayName)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                    Text("\(current.score.overallScore) points")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(previous.displayName)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                    Text("\(previous.score.overallScore) points")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }

            Text(deltaText)
                .font(.system(.caption, design: .rounded))
                .foregroundColor(deltaColor)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
        .accessibilityLabel("Comparison. \(deltaText).")
    }
}

struct HealthAlertsCard: View {
    struct AlertItem: Hashable {
        let title: String
        let detail: String
        let color: Color
    }

    let alerts: [AlertItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Health Alerts")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundColor(.primary)
            }

            ForEach(alerts, id: \.self) { alert in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(alert.color)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(alert.title)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundColor(.primary)
                        Text(alert.detail)
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func alerts(for product: Product) -> [AlertItem] {
        guard let nutriments = product.product.nutriments else { return [] }
        var items: [AlertItem] = []

        if let sugars = nutriments.sugars, sugars >= 15 {
            items.append(AlertItem(title: "High Sugar", detail: "\(String(format: "%.1f", sugars))g per 100g", color: .red))
        }
        if let saturatedFat = nutriments.saturatedFat, saturatedFat >= 5 {
            items.append(AlertItem(title: "High Saturated Fat", detail: "\(String(format: "%.1f", saturatedFat))g per 100g", color: .orange))
        }
        if let salt = nutriments.salt, salt >= 1.5 {
            items.append(AlertItem(title: "High Salt", detail: "\(String(format: "%.1f", salt))g per 100g", color: .orange))
        }
        if let novaGroup = product.product.novaGroup, novaGroup >= 4 {
            items.append(AlertItem(title: "Ultra-Processed", detail: "NOVA group \(novaGroup)", color: .red))
        }

        return items
    }
}

struct NutritionHighlightsCard: View {
    struct Highlight: Hashable {
        let title: String
        let detail: String
        let color: Color
    }

    let highlights: [Highlight]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(.blue)
                Text("Nutrition Highlights")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundColor(.primary)
            }

            ForEach(highlights, id: \.self) { item in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(item.color)
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundColor(.primary)
                        Text(item.detail)
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.blue.opacity(0.15), lineWidth: 1)
                )
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func highlights(for product: Product) -> [Highlight] {
        guard let nutriments = product.product.nutriments else { return [] }
        var items: [Highlight] = []

        if let fiber = nutriments.fiber, fiber >= 3 {
            items.append(Highlight(title: "Good Fiber", detail: "\(String(format: "%.1f", fiber))g per 100g", color: .green))
        }
        if let proteins = nutriments.proteins, proteins >= 5 {
            items.append(Highlight(title: "Protein Source", detail: "\(String(format: "%.1f", proteins))g per 100g", color: .blue))
        }
        if let sugars = nutriments.sugars, sugars <= 5 {
            items.append(Highlight(title: "Low Sugar", detail: "\(String(format: "%.1f", sugars))g per 100g", color: .teal))
        }
        if let salt = nutriments.salt, salt <= 0.3 {
            items.append(Highlight(title: "Low Salt", detail: "\(String(format: "%.1f", salt))g per 100g", color: .teal))
        }

        return items
    }
}

struct BetterAlternativesCard: View {
    let alternatives: [Product]
    let onSelect: (Product) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Better Alternatives")
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundColor(.primary)

            VStack(spacing: 10) {
                ForEach(alternatives) { product in
                    Button {
                        onSelect(product)
                    } label: {
                        HStack(spacing: 12) {
                            if let imageURL = product.imageURL {
                                AsyncImage(url: imageURL) { phase in
                                    switch phase {
                                    case .empty:
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(width: 44, height: 44)
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 44, height: 44)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    case .failure:
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(width: 44, height: 44)
                                            .overlay(
                                                Image(systemName: "photo")
                                                    .font(.system(.caption, design: .default))
                                                    .foregroundColor(.gray)
                                            )
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                            } else {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Image(systemName: "photo")
                                            .font(.system(.caption, design: .default))
                                            .foregroundColor(.gray)
                                    )
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(product.displayName)
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .foregroundColor(.primary)
                                    .lineLimit(2)

                                Text("\(product.score.overallScore) points · \(product.score.summaryLabel)")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(.footnote, design: .default).weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.gray.opacity(0.12), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.gray.opacity(0.12), lineWidth: 1)
                )
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ConfidenceCard: View {
            let score: ProductScore

            var confidenceLevel: ConfidenceLevel {
                switch score.overallScore {
                case 80...100: return .excellent
                case 60...79: return .good
                case 40...59: return .moderate
                case 20...39: return .poor
                default: return .poor
                }
            }

            var body: some View {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground))
                        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)

                    VStack(spacing: 16) {
                        // Confidence indicator
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(confidenceLevel.color.opacity(0.15))
                                    .frame(width: 48, height: 48)

                                Image(systemName: confidenceLevel.icon)
                                    .font(.system(.headline, design: .default).weight(.semibold))
                                    .foregroundColor(confidenceLevel.color)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(confidenceLevel.title)
                                    .font(.system(.headline, design: .default).weight(.semibold))
                                    .foregroundColor(.primary)

                                Text(confidenceLevel.subtitle)
                                    .font(.system(.subheadline, design: .default))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }

                        // Optional detailed score for advanced users
                        if confidenceLevel.showScore {
                            HStack {
                                Text("Overall Score")
                                    .font(.system(.caption, design: .default).weight(.medium))
                                    .foregroundColor(.secondary)

                                Spacer()

                                Text("\(score.overallScore)%")
                                    .font(.system(.caption, design: .default).weight(.semibold))
                                    .foregroundColor(confidenceLevel.color)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(20)
                }
                .frame(height: 120)
            }
        }

        enum ConfidenceLevel {
            case excellent, good, moderate, poor

            var title: String {
                switch self {
                case .excellent: return "Excellent choice"
                case .good: return "Good option"
                case .moderate: return "Consider alternatives"
                case .poor: return "Poor choice"
                }
            }

            var subtitle: String {
                switch self {
                case .excellent: return "Highly recommended"
                case .good: return "Reasonable choice"
                case .moderate: return "Look for better options"
                case .poor: return "Not recommended"
                }
            }

            var icon: String {
                switch self {
                case .excellent: return "checkmark.circle.fill"
                case .good: return "hand.thumbsup.circle.fill"
                case .moderate: return "exclamationmark.circle.fill"
                case .poor: return "xmark.circle.fill"
                }
            }

            var color: Color {
                switch self {
                case .excellent: return .green
                case .good: return .blue
                case .moderate: return .orange
                case .poor: return .red
                }
            }

            var showScore: Bool {
                // Only show detailed score for borderline cases
                switch self {
                case .moderate: return true
                default: return false
                }
            }
        }
        
        struct ScoresTabView: View {
            let product: Product
            let previousProduct: Product?
            let alternatives: [Product]
            let onSelectAlternative: (Product) -> Void
            @State private var showCards = false

            var body: some View {
                VStack(spacing: 14) {
                    ScoreHeadlineCard(score: product.score)

                    ForEach(Array(scoreCards.enumerated()), id: \.offset) { index, card in
                        ScoreCard(
                            title: card.title,
                            grade: card.grade,
                            color: card.color,
                            description: card.description,
                            delay: Double(index) * 0.08,
                            isVisible: showCards
                        )
                    }

                    if let previousProduct,
                       previousProduct.code != product.code {
                        CompareCard(current: product, previous: previousProduct)
                    }

                    if !alternatives.isEmpty {
                        BetterAlternativesCard(alternatives: alternatives, onSelect: onSelectAlternative)
                    }
                }
                .padding(.horizontal, 20)
                .onAppear {
                    showCards = true
                }
            }

            private var scoreCards: [(title: String, grade: String, color: Color, description: String)] {
                [
                    (
                        title: "Nutri-Score",
                        grade: product.score.nutriscore.rawValue.uppercased(),
                        color: product.score.nutriscore.color,
                        description: "Nutritional quality"
                    ),
                    (
                        title: "Eco-Score",
                        grade: product.score.ecoscore.rawValue.uppercased(),
                        color: product.score.ecoscore.color,
                        description: "Environmental impact"
                    ),
                    (
                        title: "NOVA Group",
                        grade: "\(product.score.novaGroup.rawValue)",
                        color: product.score.novaGroup.color,
                        description: product.score.novaGroup.description
                    )
                ]
            }
        }

        struct ScoreHeadlineCard: View {
            let score: ProductScore
            @Environment(\.accessibilityReduceMotion) private var reduceMotion
            @State private var animatedScore: Double = 0

            var body: some View {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.25), lineWidth: 9)
                            .frame(width: 84, height: 84)

                        Circle()
                            .trim(from: 0, to: animatedScore / 100)
                            .stroke(
                                AngularGradient(
                                    colors: [score.summaryColor.opacity(0.7), score.summaryColor],
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 9, lineCap: .round)
                            )
                            .frame(width: 84, height: 84)
                            .rotationEffect(.degrees(-90))

                        Text("\(Int(animatedScore))")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .contentTransition(.numericText())
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Overall Food Score")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundColor(.secondary)
                        Text(score.recommendation)
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundColor(.primary)
                        Text("Combined from Nutri, Eco, and processing quality")
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding(16)
                .glassCard(cornerRadius: 18)
                .onAppear {
                    let animation = reduceMotion ? nil : Animation.easeOut(duration: 0.7)
                    withAnimation(animation) {
                        animatedScore = Double(score.overallScore)
                    }
                }
            }
        }

        struct ScoreCard: View {
            let title: String
            let grade: String
            let color: Color
            let description: String
            let delay: Double
            let isVisible: Bool

            @State private var isPressed = false
            @Environment(\.accessibilityReduceMotion) private var reduceMotion

            var body: some View {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(color.opacity(0.14))
                            .frame(width: 56, height: 56)
                        Text(grade)
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundColor(color)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(.headline, design: .rounded).weight(.semibold))
                            .foregroundColor(.primary)
                        Text(description)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()
                }
                .padding(16)
                .glassCard(cornerRadius: 18)
                .scaleEffect(isPressed ? 0.985 : 1)
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 14)
                .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85).delay(delay), value: isVisible)
                .onTapGesture {
                    AppHaptics.impact(.light)
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                        isPressed = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            isPressed = false
                        }
                    }
                }
            }
        }

        struct NutritionTabView: View {
            let product: Product
            let alerts: [HealthAlertsCard.AlertItem]
            let highlights: [NutritionHighlightsCard.Highlight]
            @State private var reveal = false

            private var metrics: [NutritionMetric] {
                guard let n = product.product.nutriments else { return [] }
                var items: [NutritionMetric] = []

                if let energy = n.energyKcal {
                    items.append(.init(label: "Energy", value: energy, unit: "kcal", emphasis: .neutral, reference: 550))
                }
                if let fat = n.fat {
                    items.append(.init(label: "Fat", value: fat, unit: "g", emphasis: fat > 17.5 ? .high : .neutral, reference: 35))
                }
                if let saturatedFat = n.saturatedFat {
                    items.append(.init(label: "Saturated Fat", value: saturatedFat, unit: "g", emphasis: saturatedFat > 5 ? .high : .neutral, reference: 10))
                }
                if let carbohydrates = n.carbohydrates {
                    items.append(.init(label: "Carbohydrates", value: carbohydrates, unit: "g", emphasis: .neutral, reference: 70))
                }
                if let sugars = n.sugars {
                    items.append(.init(label: "Sugars", value: sugars, unit: "g", emphasis: sugars > 15 ? .high : .neutral, reference: 30))
                }
                if let fiber = n.fiber {
                    items.append(.init(label: "Fiber", value: fiber, unit: "g", emphasis: fiber >= 3 ? .good : .neutral, reference: 10))
                }
                if let proteins = n.proteins {
                    items.append(.init(label: "Proteins", value: proteins, unit: "g", emphasis: proteins >= 5 ? .good : .neutral, reference: 20))
                }
                if let salt = n.salt {
                    items.append(.init(label: "Salt", value: salt, unit: "g", emphasis: salt > 1.5 ? .high : .neutral, reference: 3))
                }

                return items
            }

            var body: some View {
                VStack(spacing: 14) {
                    if metrics.isEmpty {
                        EmptyGlassState(
                            title: "No nutrition information",
                            subtitle: "This product is missing nutrition values in the source dataset.",
                            symbol: "fork.knife"
                        )
                    } else {
                        NutritionHeaderCard(totalItems: metrics.count)

                        ForEach(Array(metrics.enumerated()), id: \.offset) { index, item in
                            NutritionRow(
                                metric: item,
                                delay: Double(index) * 0.05,
                                reveal: reveal
                            )
                        }

                        if !alerts.isEmpty {
                            HealthAlertsCard(alerts: alerts)
                        }

                        if !highlights.isEmpty {
                            NutritionHighlightsCard(highlights: highlights)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .onAppear {
                    reveal = true
                }
            }
        }

        struct NutritionMetric {
            enum Emphasis {
                case high
                case good
                case neutral

                var color: Color {
                    switch self {
                    case .high: return .orange
                    case .good: return .green
                    case .neutral: return .blue
                    }
                }

                var label: String {
                    switch self {
                    case .high: return "Watch"
                    case .good: return "Good"
                    case .neutral: return "Info"
                    }
                }
            }

            let label: String
            let value: Double
            let unit: String
            let emphasis: Emphasis
            let reference: Double

            var formatted: String {
                if unit == "kcal" {
                    return "\(Int(value)) \(unit)"
                }
                return "\(String(format: "%.1f", value))\(unit)"
            }

            var normalizedProgress: CGFloat {
                CGFloat(min(max(value / max(reference, 1), 0), 1))
            }
        }

        struct NutritionHeaderCard: View {
            let totalItems: Int

            var body: some View {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Nutrition Details")
                            .font(.system(.headline, design: .rounded).weight(.semibold))
                        Text("Per 100g · \(totalItems) metrics")
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chart.xyaxis.line")
                        .foregroundColor(.blue)
                }
                .padding(16)
                .glassCard(cornerRadius: 18)
            }
        }

        struct NutritionRow: View {
            let metric: NutritionMetric
            let delay: Double
            let reveal: Bool
            @State private var animateBar = false
            @Environment(\.accessibilityReduceMotion) private var reduceMotion

            var body: some View {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(metric.label)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundColor(.primary)

                        Spacer()

                        Text(metric.formatted)
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundColor(.primary)
                            .contentTransition(.numericText())

                        Text(metric.emphasis.label)
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundColor(metric.emphasis.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(metric.emphasis.color.opacity(0.14), in: Capsule())
                    }

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.24))
                            Capsule()
                                .fill(metric.emphasis.color.opacity(0.9))
                                .frame(width: proxy.size.width * (animateBar ? metric.normalizedProgress : 0))
                        }
                    }
                    .frame(height: 7)
                }
                .padding(14)
                .glassCard(cornerRadius: 16)
                .opacity(reveal ? 1 : 0)
                .offset(y: reveal ? 0 : 10)
                .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.86).delay(delay), value: reveal)
                .onAppear {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.6).delay(delay + 0.08)) {
                        animateBar = true
                    }
                }
            }
        }
        
struct IngredientsTabView: View {
    let product: Product
    let watchedTerms: [String]

    private var ingredientCount: Int {
        guard let ingredients = product.product.ingredientsText else { return 0 }
        return ingredients
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let ingredients = product.product.ingredientsText, !ingredients.isEmpty {
                IngredientOverviewCard(
                    ingredientCount: ingredientCount,
                    additivesCount: product.product.additivesTags?.count ?? 0,
                    hasAllergens: !(product.product.allergens?.isEmpty ?? true),
                    watchedMatches: watchedTerms.filter { term in
                        ingredients.lowercased().contains(term.lowercased())
                    }
                )
                IngredientsBreakdownCard(ingredientsText: ingredients)
                IngredientsCard(text: ingredients, watchedTerms: watchedTerms)
            } else {
                EmptyIngredientsCard()
            }

            if let allergens = product.product.allergens, !allergens.isEmpty {
                AllergensCard(allergens: allergens)
            }

            AdditivesCard(additives: product.product.additivesTags ?? [])

            ProductInfoCard(code: product.code)

            if let categories = product.product.categories, !categories.isEmpty {
                DetailCard(title: "Category", value: categories)
            }

            if let labels = product.product.labels, !labels.isEmpty {
                DetailCard(title: "Labels", value: labels)
            }
        }
        .padding(.horizontal, 20)
    }
}

struct IngredientOverviewCard: View {
    let ingredientCount: Int
    let additivesCount: Int
    let hasAllergens: Bool
    let watchedMatches: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Ingredient Snapshot", systemImage: "list.bullet.rectangle")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundColor(.primary)
                Spacer()
            }

            HStack(spacing: 10) {
                IngredientMetricPill(title: "Ingredients", value: "\(ingredientCount)", tint: .blue, symbol: "leaf")
                IngredientMetricPill(title: "Additives", value: "\(additivesCount)", tint: .purple, symbol: "flask")
                IngredientMetricPill(title: "Allergens", value: hasAllergens ? "Yes" : "None", tint: hasAllergens ? .orange : .green, symbol: hasAllergens ? "exclamationmark.triangle" : "checkmark.circle")
            }

            if !watchedMatches.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "eye.trianglebadge.exclamationmark")
                        .foregroundColor(.orange)
                    Text("Watchlist matches: \(watchedMatches.prefix(3).map { $0.capitalized }.joined(separator: ", "))")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.12))
                )
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct IngredientMetricPill: View {
    let title: String
    let value: String
    let tint: Color
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(tint)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundColor(.primary)
            Text(title)
                .font(.system(.caption2, design: .rounded))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(tint.opacity(0.12))
        )
    }
}

struct IngredientsCard: View {
    let text: String
    let watchedTerms: [String]
    @State private var expanded = false
    @State private var displayMode: IngredientDisplayMode = .structured
    @State private var focusMode: IngredientFocusMode = .all
    @State private var searchText = ""

    private let allergenKeywords = [
        "milk", "soy", "soya", "egg", "wheat", "gluten", "peanut", "nuts", "almond", "hazelnut", "sesame", "mustard", "fish", "shellfish"
    ]

    private var ingredients: [String] {
        text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var filteredIngredients: [String] {
        ingredients.filter { ingredient in
            let matchesSearch = searchText.isEmpty || ingredient.localizedCaseInsensitiveContains(searchText)
            let normalized = ingredient.lowercased()
            let matchesFocus: Bool
            switch focusMode {
            case .all:
                matchesFocus = true
            case .allergenMentions:
                matchesFocus = allergenKeywords.contains(where: { normalized.contains($0) })
            case .additiveLike:
                matchesFocus = hasAdditivePattern(normalized)
            }
            return matchesSearch && matchesFocus
        }
    }

    private var visibleIngredients: [String] {
        expanded ? filteredIngredients : Array(filteredIngredients.prefix(8))
    }

    private var likelyAllergenMentions: [String] {
        ingredients.filter { ingredient in
            let normalized = ingredient.lowercased()
            return allergenKeywords.contains(where: { normalized.contains($0) })
        }
    }

    private var watchlistMatches: [String] {
        guard !watchedTerms.isEmpty else { return [] }
        return ingredients.filter { ingredient in
            watchedTerms.contains { ingredient.lowercased().contains($0.lowercased()) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Ingredients", systemImage: "text.justify.left")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundColor(.primary)

                Spacer()

                Text("\(filteredIngredients.count) shown")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
            }

            Picker("Display mode", selection: $displayMode) {
                ForEach(IngredientDisplayMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Picker("Ingredient focus", selection: $focusMode) {
                ForEach(IngredientFocusMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Filter ingredients", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.thinMaterial)
            )

            if displayMode == .structured {
                VStack(spacing: 8) {
                    if visibleIngredients.isEmpty {
                        Text("No ingredients match this filter.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(Array(visibleIngredients.enumerated()), id: \.offset) { index, item in
                            let isMatch = !searchText.isEmpty && item.localizedCaseInsensitiveContains(searchText)

                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.system(.caption, design: .rounded).weight(.bold))
                                    .foregroundColor(.blue)
                                    .frame(width: 22, height: 22)
                                    .background(Color.blue.opacity(0.12), in: Circle())

                                Text(item)
                                    .font(.system(.callout, design: .rounded))
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(index.isMultiple(of: 2) ? Color(.systemBackground).opacity(0.9) : Color(.secondarySystemBackground).opacity(0.7))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(isMatch ? Color.blue.opacity(0.55) : Color.clear, lineWidth: 1.2)
                                    )
                            )
                        }
                    }
                }
            } else {
                ScrollView {
                    Text(text)
                        .font(.system(.body, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 180)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.thinMaterial)
                )
            }

            if !likelyAllergenMentions.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Potential allergen mentions detected in ingredients list.")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.12))
                )
            }

            if !watchlistMatches.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "eye.trianglebadge.exclamationmark")
                        .foregroundColor(.red)
                    Text("Matches your watchlist: \(watchlistMatches.prefix(4).joined(separator: ", "))")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.red.opacity(0.12))
                )
            }

            if filteredIngredients.count > 8 {
                Button(expanded ? "Show less" : "Show all ingredients") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        expanded.toggle()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hasAdditivePattern(_ text: String) -> Bool {
        if text.contains("additive") || text.contains("emulsifier") || text.contains("preservative") || text.contains("stabilizer") || text.contains("color") || text.contains("colour") || text.contains("flavour") || text.contains("flavor") {
            return true
        }

        let pattern = #"\be\s?\d{3}[a-z]?\b"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}

enum IngredientDisplayMode: CaseIterable {
    case structured
    case raw

    var title: String {
        switch self {
        case .structured: return "Structured"
        case .raw: return "Raw"
        }
    }
}

enum IngredientFocusMode: CaseIterable {
    case all
    case allergenMentions
    case additiveLike

    var title: String {
        switch self {
        case .all: return "All"
        case .allergenMentions: return "Allergens"
        case .additiveLike: return "Additives"
        }
    }
}

struct IngredientsBreakdownCard: View {
    let ingredientsText: String

    private var ingredients: [String] {
        ingredientsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var parsed: [(name: String, percent: Double?)] {
        ingredients.map { item in
            let percent = extractPercent(from: item)
            return (name: cleanName(item), percent: percent)
        }
    }

    private var hasPercents: Bool {
        parsed.contains { $0.percent != nil }
    }

    private var primary: [String] {
        if hasPercents {
            return parsed
                .filter { ($0.percent ?? 0) >= 10 }
                .map { $0.name }
        }
        return Array(ingredients.prefix(5))
    }

    private var secondary: [String] {
        if hasPercents {
            return parsed
                .filter { ($0.percent ?? 0) < 10 && ($0.percent ?? 0) >= 3 }
                .map { $0.name }
        }
        let start = min(ingredients.count, 5)
        let end = min(ingredients.count, 10)
        return Array(ingredients[start..<end])
    }

    private var trace: [String] {
        if hasPercents {
            return parsed
                .filter { ($0.percent ?? 0) < 3 }
                .map { $0.name }
        }
        return ingredients.count > 10 ? Array(ingredients.dropFirst(10)) : []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Ingredient Mix", systemImage: "chart.bar.xaxis")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundColor(.primary)
                Spacer()
                Text("\(ingredients.count) total")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
            }

            IngredientCompositionBar(
                primaryCount: primary.count,
                secondaryCount: secondary.count,
                traceCount: trace.count
            )

            IngredientTierRow(title: "Primary", subtitle: "Most prominent", color: .blue, items: primary)
            IngredientTierRow(title: "Secondary", subtitle: "Notable", color: .teal, items: secondary)
            IngredientTierRow(title: "Trace", subtitle: "Small amounts", color: .orange, items: trace)
        }
        .padding(16)
        .glassCard(cornerRadius: 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func extractPercent(from text: String) -> Double? {
        let pattern = #"(?:^|[^0-9])(\d+(?:[.,]\d+)?)\s*%"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let valueRange = Range(match.range(at: 1), in: text)
        else { return nil }
        let raw = text[valueRange].replacingOccurrences(of: ",", with: ".")
        return Double(raw)
    }

    private func cleanName(_ text: String) -> String {
        let cleaned = text.replacingOccurrences(of: #"\(.*?\)"#, with: "", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct IngredientCompositionBar: View {
    let primaryCount: Int
    let secondaryCount: Int
    let traceCount: Int

    private var total: CGFloat {
        CGFloat(max(primaryCount + secondaryCount + traceCount, 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.24))
                        .frame(height: 10)

                    HStack(spacing: 0) {
                        Capsule()
                            .fill(Color.blue.opacity(0.85))
                            .frame(width: max(8, CGFloat(primaryCount) / total * proxy.size.width), height: 10)
                        Capsule()
                            .fill(Color.teal.opacity(0.85))
                            .frame(width: max(8, CGFloat(secondaryCount) / total * proxy.size.width), height: 10)
                        Capsule()
                            .fill(Color.orange.opacity(0.85))
                            .frame(width: max(8, CGFloat(traceCount) / total * proxy.size.width), height: 10)
                    }
                }
            }
            .frame(height: 10)

            HStack(spacing: 10) {
                compositionLegend(title: "Primary", count: primaryCount, color: .blue)
                compositionLegend(title: "Secondary", count: secondaryCount, color: .teal)
                compositionLegend(title: "Trace", count: traceCount, color: .orange)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.thinMaterial)
        )
    }

    private func compositionLegend(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(title) \(count)")
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundColor(.secondary)
        }
    }
}

struct IngredientTierRow: View {
    let title: String
    let subtitle: String
    let color: Color
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.8), color.opacity(0.35)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 42, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }

            if items.isEmpty {
                Text("No ingredients listed")
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.secondary)
            } else {
                FlexibleTagGrid(items: items) { item in
                    Text(item)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundColor(color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(color.opacity(0.12))
                        )
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct FlexibleTagGrid<TagContent: View>: View {
    let items: [String]
    let content: (String) -> TagContent

    private let columns = [GridItem(.adaptive(minimum: 90), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
    }
}

struct AdditivesCard: View {
    let additives: [String]

    private var normalized: [String] {
        additives
            .map { $0.replacingOccurrences(of: "en:", with: "") }
            .map { $0.replacingOccurrences(of: "-", with: " ") }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Additives")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundColor(.primary)
                Spacer()
                Text(additives.isEmpty ? "0" : "\(normalized.count)")
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.secondary)
            }

            if normalized.isEmpty {
                Text("No additives listed")
                    .font(.system(.callout, design: .rounded))
                    .foregroundColor(.secondary)
            } else {
                FlexibleTagGrid(items: normalized) { item in
                    Text(item.capitalized)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundColor(.purple)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.purple.opacity(0.12))
                        )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.gray.opacity(0.12), lineWidth: 1)
                )
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyIngredientsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Ingredients", systemImage: "text.justify.left")
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundColor(.primary)

            Text("No ingredients information is available for this product yet.")
                .font(.system(.callout, design: .rounded))
                .foregroundColor(.secondary)

            Text("Try another item or check the product page for updates.")
                .font(.system(.caption, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding(16)
        .glassCard(cornerRadius: 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AllergensCard: View {
    let allergens: String

    private var tokens: [String] {
        allergens
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Allergens")
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundColor(.primary)

            if tokens.isEmpty {
                Text(allergens)
                    .font(.system(.callout, design: .rounded))
                    .foregroundColor(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                    ForEach(tokens, id: \.self) { token in
                        AllergenChip(text: token)
                    }
                }
            }

            Text("Based on the manufacturer label.")
                .font(.system(.caption, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                )
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AllergenChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundColor(.orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.orange.opacity(0.12))
            )
    }
}

struct ProductInfoCard: View {
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Product Info")
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundColor(.primary)

            HStack {
                Text("Barcode")
                    .font(.system(.callout, design: .rounded))
                    .foregroundColor(.secondary)

                Spacer()

                Text(code)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 12) {
                Button("Copy Barcode") {
                    UIPasteboard.general.string = code
                    AppHaptics.impact(.light)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if let url = URL(string: "https://world.openfoodfacts.org/product/\(code)") {
                    Link("Open Product Page", destination: url)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.gray.opacity(0.12), lineWidth: 1)
                )
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DetailCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundColor(.primary)

            Text(value)
                .font(.system(.callout, design: .rounded))
                .foregroundColor(.secondary)
                .lineSpacing(4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.gray.opacity(0.12), lineWidth: 1)
                )
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
        
        #Preview {
            let sampleProduct = Product(
                code: "3017620422003",
                product: ProductDetails(
                    productName: "Nutella",
                    brands: "Ferrero",
                    imageUrl: nil,
                    ingredientsText: "Sugar, Palm Oil, Hazelnuts, Cocoa, Skimmed Milk Powder, Whey Powder, Lecithin, Vanillin",
                    nutriscoreGrade: "e",
                    ecoscoreGrade: "c",
                    novaGroup: 4,
                    nutriments: Nutriments(
                        energyKcal: 539.0,
                        energyKj: nil,
                        fat: 30.9,
                        saturatedFat: 10.6,
                        carbohydrates: 57.5,
                        sugars: 56.3,
                        fiber: 0.0,
                        proteins: 6.3,
                        salt: 0.107,
                        sodium: nil
                    ),
                    categories: nil,
                    categoriesTags: nil,
                    labels: nil,
                    labelsTags: nil,
                    allergens: "Milk, Nuts",
                    additivesTags: nil
                )
            )
            
            ProductDetailView(product: sampleProduct, viewModel: FoodScannerViewModel())
        }
    

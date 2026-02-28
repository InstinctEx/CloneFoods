import SwiftUI
import UIKit

struct SearchView: View {
    @ObservedObject var viewModel: FoodScannerViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var searchText = ""
    @State private var sortMode: SortMode = .health
    @State private var minimumScore: Double = 0
    @State private var hideLowQuality = false
    @State private var excludeWatchlistMatches = false
    @State private var onlyProfileCompatible = false
    @State private var hasAppeared = false

    private var suggestionTerms: [String] {
        let candidates = Array(viewModel.recentSearches.prefix(8)) +
            viewModel.scannedProducts.prefix(8).map { $0.displayName } +
            viewModel.favoriteProducts.prefix(8).map { $0.displayName }

        var seen = Set<String>()
        var ordered: [String] = []
        for term in candidates {
            let normalized = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            let key = normalized.lowercased()
            guard seen.insert(key).inserted else { continue }
            ordered.append(normalized)
            if ordered.count == 10 { break }
        }
        return ordered
    }

    var body: some View {
        ZStack {
            AppBackdrop()

            List {
                if searchText.isEmpty {
                    if !suggestionTerms.isEmpty {
                        Section {
                            suggestionsCard
                                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                                .listRowBackground(Color.clear)
                        }
                    }

                    Section {
                        EmptyGlassState(
                            title: "Search products",
                            subtitle: "Find by name, brand, or category.",
                            symbol: "magnifyingglass"
                        )
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                        .listRowBackground(Color.clear)
                    }
                } else if viewModel.isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("Searching...")
                            Spacer()
                        }
                        .padding(16)
                        .glassCard()
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                        .listRowBackground(Color.clear)
                    }
                } else if filteredResults.isEmpty {
                    Section {
                        EmptyGlassState(
                            title: "No matching products",
                            subtitle: "Try another term or relax filters.",
                            symbol: "line.3.horizontal.decrease.circle"
                        )
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        SearchRefineCard(
                            sortMode: $sortMode,
                            minimumScore: $minimumScore,
                            hideLowQuality: $hideLowQuality,
                            excludeWatchlistMatches: $excludeWatchlistMatches,
                            onlyProfileCompatible: $onlyProfileCompatible,
                            hasDietaryProfile: !viewModel.dietaryPreferences.isEmpty
                        )
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                        .listRowBackground(Color.clear)
                    }

                    ForEach(Array(filteredResults.enumerated()), id: \.element.id) { index, product in
                        ProductRow(product: product, viewModel: viewModel)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .opacity(hasAppeared ? 1 : 0)
                            .offset(y: hasAppeared ? 0 : 10)
                            .animation(
                                reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.86).delay(Double(index) * 0.02),
                                value: hasAppeared
                            )
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: viewModel.isFavorite(product) ? .destructive : .none) {
                                    viewModel.toggleFavorite(product)
                                } label: {
                                    Label(
                                        viewModel.isFavorite(product) ? "Unfavorite" : "Favorite",
                                        systemImage: viewModel.isFavorite(product) ? "heart.slash" : "heart"
                                    )
                                }
                                .tint(viewModel.isFavorite(product) ? .red : .pink)
                            }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search products")
        .onSubmit(of: .search) {
            viewModel.recordSearchQuery(searchText)
            viewModel.searchProducts(query: searchText, immediate: true)
        }
        .onChange(of: searchText) { _, newValue in
            viewModel.searchProducts(query: newValue)
        }
        .alert("Search Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
        .onAppear {
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                    hasAppeared = true
                }
            }
        }
        .onChange(of: filteredResults.count) { _, _ in
            guard !reduceMotion else {
                hasAppeared = true
                return
            }
            hasAppeared = false
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                hasAppeared = true
            }
        }
    }

    private var suggestionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitleRow(
                title: "Suggestions",
                subtitle: "Recent and personalized",
                actionTitle: viewModel.recentSearches.isEmpty ? nil : "Clear",
                action: {
                    viewModel.clearRecentSearches()
                }
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestionTerms, id: \.self) { term in
                        Button(term) {
                            searchText = term
                            viewModel.recordSearchQuery(term)
                            viewModel.searchProducts(query: term)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .contextMenu {
                            if viewModel.recentSearches.contains(where: { $0 == term }) {
                                Button("Remove from recent") {
                                    viewModel.removeRecentSearch(term)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 16)
    }

    private var filteredResults: [Product] {
        let minimum = hideLowQuality ? max(minimumScore, 40) : minimumScore
        var qualityFiltered = viewModel.searchResults.filter { Double($0.score.overallScore) >= minimum }

        if excludeWatchlistMatches {
            qualityFiltered = qualityFiltered.filter { viewModel.productMatchesWatchlist($0).isEmpty }
        }

        if onlyProfileCompatible && !viewModel.dietaryPreferences.isEmpty {
            qualityFiltered = qualityFiltered.filter { viewModel.isCompatibleWithCurrentProfile($0) }
        }

        switch sortMode {
        case .health:
            return qualityFiltered.sorted { $0.score.overallScore > $1.score.overallScore }
        case .relevance:
            return qualityFiltered
        }
    }
}

enum SortMode: String, CaseIterable {
    case health = "Health"
    case relevance = "Relevance"
}

struct SearchRefineCard: View {
    @Binding var sortMode: SortMode
    @Binding var minimumScore: Double
    @Binding var hideLowQuality: Bool
    @Binding var excludeWatchlistMatches: Bool
    @Binding var onlyProfileCompatible: Bool
    let hasDietaryProfile: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitleRow(title: "Filters")

            Picker("Sort", selection: $sortMode) {
                ForEach(SortMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Minimum score")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(minimumScore))")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $minimumScore, in: 0...100, step: 5)
                    .tint(.blue)
            }

            Toggle("Hide low-quality products", isOn: $hideLowQuality)
                .font(.system(.subheadline, design: .rounded))

            Toggle("Exclude watchlist matches", isOn: $excludeWatchlistMatches)
                .font(.system(.subheadline, design: .rounded))

            if hasDietaryProfile {
                Toggle("Only profile-compatible", isOn: $onlyProfileCompatible)
                    .font(.system(.subheadline, design: .rounded))
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 16)
    }
}

struct ProductRow: View {
    let product: Product
    @ObservedObject var viewModel: FoodScannerViewModel
    @State private var isPressed = false
    @Environment(\.openURL) private var openURL

    private var profileConflicts: [DietaryPreference] {
        viewModel.conflictsForCurrentProfile(product)
    }

    var body: some View {
        Button {
            AppHaptics.impact(.light)
            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                viewModel.selectProduct(product)
                isPressed = false
            }
        } label: {
            HStack(spacing: 12) {
                productImage

                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName)
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if !product.brand.isEmpty {
                        Text(product.brand)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 6) {
                        Circle()
                            .fill(scoreColor(for: product.score.overallScore))
                            .frame(width: 8, height: 8)
                        Text(product.score.summaryLabel)
                            .font(.system(.caption, design: .rounded).weight(.medium))
                            .foregroundStyle(.secondary)
                        Text("· \(product.score.overallScore)")
                            .font(.system(.caption, design: .rounded).weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    if !profileConflicts.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(profileConflicts.prefix(2)) { conflict in
                                    Label(conflict.title, systemImage: conflict.symbol)
                                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                                        .foregroundStyle(conflict.tint)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(conflict.tint.opacity(0.14))
                                        )
                                }
                            }
                            .padding(.top, 1)
                        }
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .glassCard(cornerRadius: 16)
            .scaleEffect(isPressed ? 0.985 : 1)
        }
        .buttonStyle(BouncyGlassButtonStyle())
        .contextMenu {
            Button(viewModel.isFavorite(product) ? "Remove from Favorites" : "Add to Favorites") {
                viewModel.toggleFavorite(product)
            }

            Button("Copy Barcode") {
                UIPasteboard.general.string = product.code
                AppHaptics.impact(.light)
            }

            if let url = product.productURL {
                Button("Open Product Page") {
                    openURL(url)
                }
            }
        }
    }

    private var productImage: some View {
        Group {
            if let imageURL = product.imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        placeholderImage
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 58, height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    case .failure:
                        placeholderImage
                    @unknown default:
                        placeholderImage
                    }
                }
            } else {
                placeholderImage
            }
        }
    }

    private var placeholderImage: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.gray.opacity(0.2))
            .frame(width: 58, height: 58)
            .overlay {
                Image(systemName: "photo")
                    .foregroundStyle(.gray)
            }
    }

    private func scoreColor(for score: Int) -> Color {
        if score > 70 { return .green }
        if score > 40 { return .orange }
        return .red
    }
}

#Preview {
    SearchView(viewModel: FoodScannerViewModel())
}

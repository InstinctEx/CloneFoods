import SwiftUI

struct FavoritesView: View {
    @ObservedObject var viewModel: FoodScannerViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sortMode: FavoriteSortMode = .healthiest
    @State private var showContent = false

    private var sortedFavorites: [Product] {
        switch sortMode {
        case .healthiest:
            return viewModel.favoriteProducts.sorted { $0.score.overallScore > $1.score.overallScore }
        case .recentlyAdded:
            return viewModel.favoriteProducts
        case .name:
            return viewModel.favoriteProducts.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }
    }

    private var averageFavoriteScore: Int {
        let values = viewModel.favoriteProducts.map { $0.score.overallScore }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / values.count
    }

    var body: some View {
        ZStack {
            AppBackdrop()

            List {
                if viewModel.favoriteProducts.isEmpty {
                    Section {
                        EmptyGlassState(
                            title: "No favorites yet",
                            subtitle: "Tap heart on any product to save it.",
                            symbol: "heart"
                        )
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        summaryCard
                            .motionStage(visible: showContent, index: 0, reduceMotion: reduceMotion)
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                            .listRowBackground(Color.clear)

                        sortCard
                            .motionStage(visible: showContent, index: 1, reduceMotion: reduceMotion)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowBackground(Color.clear)
                    }

                    ForEach(Array(sortedFavorites.enumerated()), id: \.element.id) { index, product in
                        ProductRow(product: product, viewModel: viewModel)
                            .motionStage(visible: showContent, index: index + 2, reduceMotion: reduceMotion)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    viewModel.toggleFavorite(product)
                                } label: {
                                    Label("Remove", systemImage: "heart.slash")
                                }
                            }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Favorites")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if reduceMotion {
                showContent = true
            } else {
                withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) {
                    showContent = true
                }
            }
        }
        .onChange(of: viewModel.favoriteProducts.count) { _, _ in
            guard !reduceMotion else {
                showContent = true
                return
            }
            showContent = false
            withAnimation(.spring(response: 0.46, dampingFraction: 0.86)) {
                showContent = true
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitleRow(title: "Saved Products", subtitle: "Your curated picks")

            HStack(spacing: 10) {
                StatPill(title: "Count", value: "\(viewModel.favoriteProducts.count)", symbol: "heart.fill", tint: .pink)
                StatPill(title: "Avg Score", value: "\(averageFavoriteScore)", symbol: "waveform.path.ecg", tint: .green)
            }

            if let healthiest = sortedFavorites.max(by: { $0.score.overallScore < $1.score.overallScore }) {
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .foregroundStyle(.yellow)
                    Text("Top favorite: \(healthiest.displayName) (\(healthiest.score.overallScore))")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(16)
        .glassCard()
    }

    private var sortCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitleRow(title: "Sort")
            Picker("Sort favorites", selection: $sortMode) {
                ForEach(FavoriteSortMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(14)
        .glassCard(cornerRadius: 16)
    }
}

enum FavoriteSortMode: String, CaseIterable {
    case healthiest = "Healthiest"
    case recentlyAdded = "Recent"
    case name = "Name"
}

#Preview {
    FavoritesView(viewModel: FoodScannerViewModel())
}

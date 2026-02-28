import SwiftUI

struct HistoryView: View {
    @ObservedObject var viewModel: FoodScannerViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showClearConfirmation = false
    @State private var showContent = false

    private var todayItems: [Product] {
        viewModel.scannedProducts.filter { isToday(product: $0) }
    }

    private var earlierItems: [Product] {
        viewModel.scannedProducts.filter { !isToday(product: $0) }
    }

    private var averageScore: Int {
        let all = viewModel.scannedProducts.map { $0.score.overallScore }
        guard !all.isEmpty else { return 0 }
        return all.reduce(0, +) / all.count
    }

    private var healthiestScan: Product? {
        viewModel.scannedProducts.max(by: { $0.score.overallScore < $1.score.overallScore })
    }

    var body: some View {
        ZStack {
            AppBackdrop()

            List {
                if viewModel.scannedProducts.isEmpty {
                    Section {
                        EmptyGlassState(
                            title: "No history yet",
                            subtitle: "Scanned products will appear here.",
                            symbol: "clock.arrow.circlepath"
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
                    }

                    if !todayItems.isEmpty {
                        Section("Today") {
                            ForEach(Array(todayItems.enumerated()), id: \.element.id) { index, product in
                                historyRow(for: product, index: index)
                            }
                        }
                    }

                    if !earlierItems.isEmpty {
                        Section("Earlier") {
                            ForEach(Array(earlierItems.enumerated()), id: \.element.id) { index, product in
                                historyRow(for: product, index: index + todayItems.count)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !viewModel.scannedProducts.isEmpty {
                Button("Clear") {
                    showClearConfirmation = true
                }
                .foregroundStyle(.red)
            }
        }
        .confirmationDialog("Clear History", isPresented: $showClearConfirmation, titleVisibility: .visible) {
            Button("Clear All", role: .destructive) {
                viewModel.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all scanned products from history.")
        }
        .onAppear {
            if reduceMotion {
                showContent = true
            } else {
                withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) {
                    showContent = true
                }
            }
        }
        .onChange(of: viewModel.scannedProducts.count) { _, _ in
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
            SectionTitleRow(title: "Insights", subtitle: "Your recent scanning behavior")

            HStack(spacing: 10) {
                StatPill(title: "Total", value: "\(viewModel.scannedProducts.count)", symbol: "barcode.viewfinder", tint: .blue)
                StatPill(title: "Avg Score", value: "\(averageScore)", symbol: "chart.bar.xaxis", tint: .green)
            }

            if let healthiestScan {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.mint)
                    Text("Top: \(healthiestScan.displayName) (\(healthiestScan.score.overallScore))")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            WeeklyActivityCard(
                streak: viewModel.currentStreak(),
                weeklyCounts: viewModel.scansByDay(lastDays: 7)
            )
        }
        .padding(16)
        .glassCard()
    }

    private func historyRow(for product: Product, index: Int) -> some View {
        ProductRow(product: product, viewModel: viewModel)
            .motionStage(visible: showContent, index: index + 1, reduceMotion: reduceMotion)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    viewModel.removeFromHistory(product)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
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

    private func isToday(product: Product) -> Bool {
        guard let date = viewModel.lastSeenDate(for: product.code) else { return false }
        return Calendar.current.isDateInToday(date)
    }
}

#Preview {
    HistoryView(viewModel: FoodScannerViewModel())
}

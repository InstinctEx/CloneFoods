import SwiftUI

struct HomeScreen: View {
    @ObservedObject var viewModel: FoodScannerViewModel
    @Binding var startScanRequested: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showLiveScan = false
    @State private var showPhotoScan = false
    @State private var showManualEntry = false
    @State private var showWatchlistEditor = false
    @State private var manualBarcode = ""
    @State private var newWatchTerm = ""
    @State private var showCards = false

    private let dailyGoal = 3

    private var todayScans: Int {
        viewModel.scannedProducts.filter {
            guard let date = viewModel.lastSeenDate(for: $0.code) else { return false }
            return Calendar.current.isDateInToday(date)
        }.count
    }

    private var progress: CGFloat {
        CGFloat(todayScans) / CGFloat(max(dailyGoal, 1))
    }

    private var avgHistoryScore: Int {
        let scores = viewModel.scannedProducts.map { $0.score.overallScore }
        guard !scores.isEmpty else { return 0 }
        return scores.reduce(0, +) / scores.count
    }

    private var bestProduct: Product? {
        (viewModel.favoriteProducts + viewModel.scannedProducts)
            .max(by: { $0.score.overallScore < $1.score.overallScore })
    }

    var body: some View {
        ZStack {
            AppBackdrop()

            ScrollView {
                VStack(spacing: 14) {
                    headerCard
                        .motionStage(visible: showCards, index: 0, reduceMotion: reduceMotion)
                    quickActionsCard
                        .motionStage(visible: showCards, index: 1, reduceMotion: reduceMotion)
                    watchlistCard
                        .motionStage(visible: showCards, index: 2, reduceMotion: reduceMotion)
                    dietaryProfileCard
                        .motionStage(visible: showCards, index: 3, reduceMotion: reduceMotion)
                    progressCard
                        .motionStage(visible: showCards, index: 4, reduceMotion: reduceMotion)

                    if let last = viewModel.scannedProducts.first {
                        LastScannedCard(product: last, subtitle: lastSeenText(for: last)) {
                            viewModel.selectProduct(last)
                        }
                        .motionStage(visible: showCards, index: 5, reduceMotion: reduceMotion)
                    }

                    if let bestProduct {
                        SpotlightCard(product: bestProduct) {
                            viewModel.selectProduct(bestProduct)
                        }
                        .motionStage(visible: showCards, index: 6, reduceMotion: reduceMotion)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showLiveScan) {
            ActiveScanScreen(viewModel: viewModel, isPresented: $showLiveScan)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showPhotoScan) {
            PhotoScanView(viewModel: viewModel, isPresented: $showPhotoScan)
        }
        .sheet(isPresented: $showManualEntry) {
            ManualEntryView(
                barcode: $manualBarcode,
                isPresented: $showManualEntry,
                isLoading: viewModel.isLoading,
                onSubmit: {
                    guard !manualBarcode.isEmpty else { return }
                    Task {
                        await viewModel.scanProduct(barcode: manualBarcode)
                        manualBarcode = ""
                    }
                }
            )
        }
        .sheet(isPresented: $showWatchlistEditor) {
            watchlistEditor
        }
        .onChange(of: startScanRequested) { _, newValue in
            guard newValue else { return }
            showLiveScan = true
            startScanRequested = false
        }
        .onAppear {
            if reduceMotion {
                showCards = true
            } else {
                withAnimation(.spring(response: 0.52, dampingFraction: 0.86)) {
                    showCards = true
                }
            }
        }
    }

    private var headerCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ready to scan")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text("Simple, fast nutrition insights with live scan or photo detection.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
            DailyGoalRing(progress: progress, current: todayScans, goal: dailyGoal)
        }
        .padding(16)
        .glassCard()
    }

    private var quickActionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitleRow(title: "Scan", subtitle: "Choose how you want to identify a product")

            HStack(spacing: 10) {
                Button {
                    showLiveScan = true
                } label: {
                    Label("Live", systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showPhotoScan = true
                } label: {
                    Label("Photo", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Button {
                showManualEntry = true
            } label: {
                Label("Type Barcode", systemImage: "number")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .glassCard()
    }

    private var watchlistCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitleRow(
                title: "Watchlist",
                subtitle: "Terms you want to avoid",
                actionTitle: "Manage",
                action: { showWatchlistEditor = true }
            )

            if viewModel.watchlistTerms.isEmpty {
                Text("No terms yet. Add ingredients like palm oil, glucose syrup, or artificial flavor.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                    ForEach(viewModel.watchlistTerms.prefix(10), id: \.self) { term in
                        Text(term.capitalized)
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.orange.opacity(0.14))
                            )
                    }
                }
            }
        }
        .padding(16)
        .glassCard()
    }

    private var dietaryProfileCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitleRow(
                title: "Dietary Profile",
                subtitle: viewModel.dietaryPreferences.isEmpty
                    ? "Choose preferences for personalized warnings"
                    : "\(viewModel.dietaryPreferences.count) preference\(viewModel.dietaryPreferences.count == 1 ? "" : "s") active"
            )

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
                ForEach(DietaryPreference.allCases) { preference in
                    DietaryPreferenceChip(
                        preference: preference,
                        isSelected: viewModel.dietaryPreferences.contains(preference)
                    ) {
                        viewModel.toggleDietaryPreference(preference)
                    }
                }
            }
        }
        .padding(16)
        .glassCard()
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitleRow(title: "Progress", subtitle: "Your weekly momentum")

            HStack(spacing: 10) {
                StatPill(
                    title: "Streak",
                    value: "\(viewModel.currentStreak()) day",
                    symbol: "flame.fill",
                    tint: .orange
                )
                StatPill(
                    title: "Avg Score",
                    value: avgHistoryScore == 0 ? "-" : "\(avgHistoryScore)",
                    symbol: "chart.bar.fill",
                    tint: .blue
                )
            }

            WeeklyActivityCard(
                streak: viewModel.currentStreak(),
                weeklyCounts: viewModel.scansByDay(lastDays: 7)
            )
        }
        .padding(16)
        .glassCard()
    }

    private var watchlistEditor: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                VStack(spacing: 14) {
                    HStack(spacing: 8) {
                        TextField("Add term", text: $newWatchTerm)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .textFieldStyle(.roundedBorder)

                        Button("Add") {
                            viewModel.addWatchlistTerm(newWatchTerm)
                            newWatchTerm = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(newWatchTerm.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                    }

                    List {
                        if viewModel.watchlistTerms.isEmpty {
                            Text("No watch terms")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(viewModel.watchlistTerms, id: \.self) { term in
                                HStack {
                                    Text(term.capitalized)
                                    Spacer()
                                    Button(role: .destructive) {
                                        viewModel.removeWatchlistTerm(term)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                }
                .padding(16)
            }
            .navigationTitle("Watchlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        showWatchlistEditor = false
                    }
                }
            }
        }
    }

    private func lastSeenText(for product: Product) -> String {
        guard let date = viewModel.lastSeenDate(for: product.code) else { return "Recently scanned" }
        return "Last scanned \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}

struct LastScannedCard: View {
    let product: Product
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                scoreBadge(for: product.score.overallScore)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Last scanned")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(product.displayName)
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .glassCard(cornerRadius: 16)
        }
        .buttonStyle(BouncyGlassButtonStyle())
    }

    private func scoreBadge(for score: Int) -> some View {
        let tint: Color = score >= 80 ? .green : (score >= 60 ? .blue : (score >= 40 ? .orange : .red))
        return ZStack {
            Circle().fill(tint.opacity(0.14))
            Text("\(score)")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(tint)
        }
        .frame(width: 40, height: 40)
    }
}

struct SpotlightCard: View {
    let product: Product
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Best Pick", systemImage: "sparkles")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.blue)
                    Spacer()
                    Text("\(product.score.overallScore)")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                }

                Text(product.displayName)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .lineLimit(2)

                Text(product.brand.isEmpty ? "Open details" : product.brand)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .glassCard(cornerRadius: 16)
        }
        .buttonStyle(BouncyGlassButtonStyle())
    }
}

struct WeeklyActivityCard: View {
    let streak: Int
    let weeklyCounts: [(date: Date, count: Int)]

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "E"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(streak == 0 ? "Start your streak" : "\(streak)-day streak")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Spacer()
                Image(systemName: "flame.fill")
                    .foregroundStyle(streak > 0 ? .orange : .secondary)
            }

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(weeklyCounts, id: \.date) { entry in
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(entry.count == 0 ? Color.gray.opacity(0.2) : Color.blue.opacity(0.85))
                            .frame(width: 11, height: max(10, CGFloat(entry.count) * 8))

                        Text(Self.weekdayFormatter.string(from: entry.date))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 14)
    }
}

struct DietaryPreferenceChip: View {
    let preference: DietaryPreference
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: preference.symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(preference.title)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? preference.tint : .secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? preference.tint.opacity(0.16) : Color(.secondarySystemBackground).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? preference.tint.opacity(0.35) : Color.white.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct ManualEntryView: View {
    @Binding var barcode: String
    @Binding var isPresented: Bool
    let isLoading: Bool
    let onSubmit: () -> Void

    @FocusState private var isBarcodeFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                VStack(spacing: 18) {
                    Image(systemName: "number.circle.fill")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.blue)

                    VStack(spacing: 5) {
                        Text("Manual Barcode Entry")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                        Text("Type the barcode digits from the package.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    TextField("e.g. 3017620422003", text: $barcode)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .focused($isBarcodeFocused)
                        .padding(14)
                        .glassCard(cornerRadius: 14)

                    VStack(spacing: 10) {
                        Button {
                            onSubmit()
                            isPresented = false
                        } label: {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                                    .frame(maxWidth: .infinity)
                            } else {
                                Label("Find Product", systemImage: "magnifyingglass")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(barcode.isEmpty || isLoading)

                        Button("Cancel") {
                            isPresented = false
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    isBarcodeFocused = true
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    HomeScreen(viewModel: FoodScannerViewModel(), startScanRequested: .constant(false))
}

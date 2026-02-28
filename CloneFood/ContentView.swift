import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var viewModel = FoodScannerViewModel()
    @State private var showWelcome: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab = 0
    @State private var startScanRequested = false

    private let hasShownWelcomeKey = "hasShownWelcome"

    init() {
        let hasShown = UserDefaults.standard.bool(forKey: hasShownWelcomeKey)
        _showWelcome = State(initialValue: !hasShown)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeScreen(viewModel: viewModel, startScanRequested: $startScanRequested)
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(0)

            NavigationStack {
                SearchView(viewModel: viewModel)
            }
            .tabItem { Label("Search", systemImage: "magnifyingglass") }
            .tag(1)

            NavigationStack {
                HistoryView(viewModel: viewModel)
            }
            .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            .tag(2)

            NavigationStack {
                FavoritesView(viewModel: viewModel)
            }
            .tabItem { Label("Favorites", systemImage: "heart.fill") }
            .tag(3)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: selectedTab)
        .tint(.blue)
        .overlay {
            if showWelcome {
                welcomeOverlay
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                dismissWelcome()
            }
        }
        .onChange(of: selectedTab) { _, _ in
            guard !reduceMotion else { return }
            AppHaptics.selectionChanged()
        }
        .onChange(of: viewModel.requestScanAgain) { _, newValue in
            guard newValue else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85)) {
                selectedTab = 0
                startScanRequested = true
            }
            viewModel.consumeScanAgainRequest()
        }
        .fullScreenCover(isPresented: $viewModel.isShowingProductDetail) {
            if let product = viewModel.currentProduct {
                ProductDetailView(product: product, viewModel: viewModel)
            }
        }
    }

    private var welcomeOverlay: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { dismissWelcome() }

            VStack(spacing: 14) {
                Image(systemName: "leaf.circle.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(.green)

                Text("Welcome to CloneFood")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)

                Text("Scan products, compare quality, and build better choices with a clean flow.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("Tap anywhere to continue")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .glassCard(cornerRadius: 26)
            .padding(.horizontal, 26)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.82), value: showWelcome)
        }
    }

    private func dismissWelcome() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8)) {
            showWelcome = false
        }
        UserDefaults.standard.set(true, forKey: hasShownWelcomeKey)
    }
}

#Preview {
    ContentView()
}

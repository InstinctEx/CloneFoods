//
//  FoodScannerViewModel.swift
//  CloneFood
//
//  Created by Demex on 18/12/2025
//

import SwiftUI
import AVFoundation
import Combine

@MainActor
class FoodScannerViewModel: ObservableObject {
    @Published var scannedProducts: [Product] = []
    @Published var favoriteProducts: [Product] = []
    @Published var searchResults: [Product] = []
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var currentProduct: Product?
    @Published var previousProduct: Product?
    @Published var isShowingProductDetail = false
    @Published var isShowingCachedProduct = false
    @Published var requestScanAgain = false
    @Published var watchlistTerms: [String] = []
    @Published var recentSearches: [String] = []
    @Published var dietaryPreferences: Set<DietaryPreference> = []

    private let userDefaults = UserDefaults.standard
    private let favoritesKey = "favoriteProducts"
    private let historyKey = "scanHistory"
    private let lastSeenKey = "lastSeenTimestamps"
    private let watchlistKey = "watchlistTerms"
    private let recentSearchesKey = "recentSearches"
    private let dietaryPreferencesKey = "dietaryPreferences"
    private var searchTask: Task<Void, Never>?
    private var activeSearchRequestID = UUID()
    private var searchCache: [String: [Product]] = [:]

    init() {
        loadFavorites()
        loadHistory()
        loadWatchlist()
        loadRecentSearches()
        loadDietaryPreferences()
    }

    deinit {
        searchTask?.cancel()
    }

    func scanProduct(barcode: String) async {
        let trimmedBarcode = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBarcode.isEmpty else {
            errorMessage = "Invalid barcode"
            showError = true
            return
        }

        clearError()
        isShowingCachedProduct = false
        isLoading = true
        defer { isLoading = false }

        do {
            let product = try await OpenFoodFactsAPI.getProduct(by: trimmedBarcode)
            setCurrentProduct(product)
            isShowingProductDetail = true
        } catch let error as OpenFoodFactsAPI.APIError {
            if case .networkError = error, let cachedProduct = cachedProduct(for: trimmedBarcode) {
                presentCachedProduct(cachedProduct)
            } else {
                errorMessage = error.errorDescription ?? "Scan failed"
                showError = true
            }
        } catch {
            if let cachedProduct = cachedProduct(for: trimmedBarcode) {
                presentCachedProduct(cachedProduct)
            } else {
                errorMessage = "Network error. Please check your connection."
                showError = true
            }
        }
    }

    func searchProducts(query: String, immediate: Bool = false) {
        searchTask?.cancel()

        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        guard !normalizedQuery.isEmpty else {
            activeSearchRequestID = UUID()
            searchResults = []
            isLoading = false
            clearError()
            return
        }

        guard normalizedQuery.count >= 2 else {
            activeSearchRequestID = UUID()
            searchResults = []
            isLoading = false
            clearError()
            return
        }

        let requestID = UUID()
        activeSearchRequestID = requestID

        let cacheKey = normalizedQuery.lowercased()
        let cachedResults = searchCache[cacheKey] ?? []
        if !cachedResults.isEmpty {
            searchResults = cachedResults
        }

        searchTask = Task {
            isLoading = cachedResults.isEmpty
            clearError()

            if !immediate {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            guard !Task.isCancelled, requestID == activeSearchRequestID else { return }

            do {
                let products = try await OpenFoodFactsAPI.searchProducts(query: normalizedQuery)
                guard !Task.isCancelled, requestID == activeSearchRequestID else { return }
                searchCache[cacheKey] = products
                searchResults = products
                isLoading = false
            } catch let error as OpenFoodFactsAPI.APIError {
                guard !Task.isCancelled, requestID == activeSearchRequestID else { return }
                if cachedResults.isEmpty {
                    errorMessage = error.errorDescription ?? "Search failed"
                    showError = true
                    searchResults = []
                }
                isLoading = false
            } catch {
                guard !Task.isCancelled, requestID == activeSearchRequestID else { return }
                if cachedResults.isEmpty {
                    errorMessage = "Network error. Please check your connection."
                    showError = true
                    searchResults = []
                }
                isLoading = false
            }
        }
    }

    func selectProduct(_ product: Product) {
        setCurrentProduct(product)
        isShowingCachedProduct = false
        isShowingProductDetail = true
        clearError()
    }

    func clearError() {
        errorMessage = nil
        showError = false
    }

    func clearHistory() {
        scannedProducts.removeAll()
        saveHistory()
    }

    func removeFromHistory(_ product: Product) {
        scannedProducts.removeAll { $0.code == product.code }
        saveHistory()
    }

    func toggleFavorite(_ product: Product) {
        if let index = favoriteProducts.firstIndex(where: { $0.code == product.code }) {
            favoriteProducts.remove(at: index)
        } else {
            favoriteProducts.append(product)
        }
        saveFavorites()
    }

    func isFavorite(_ product: Product) -> Bool {
        favoriteProducts.contains(where: { $0.code == product.code })
    }

    private func addToHistory(_ product: Product) {
        // Remove if already exists to avoid duplicates
        scannedProducts.removeAll(where: { $0.code == product.code })
        // Add to beginning of history
        scannedProducts.insert(product, at: 0)
        // Keep only last 50 items
        if scannedProducts.count > 50 {
            scannedProducts = Array(scannedProducts.prefix(50))
        }
        updateLastSeen(for: product.code)
        saveHistory()
    }

    func refreshCurrentProduct() async {
        guard let product = currentProduct else { return }
        clearError()
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let updatedProduct = try await OpenFoodFactsAPI.getProduct(by: product.code)
            setCurrentProduct(updatedProduct)
            isShowingCachedProduct = false
        } catch let error as OpenFoodFactsAPI.APIError {
            errorMessage = error.errorDescription ?? "Refresh failed"
            showError = true
        } catch {
            errorMessage = "Network error. Please check your connection."
            showError = true
        }
    }

    func markScanAgainRequested() {
        requestScanAgain = true
    }

    func consumeScanAgainRequest() {
        requestScanAgain = false
    }

    func lastSeenDate(for code: String) -> Date? {
        let timestamps = lastSeenTimestamps()
        guard let timeInterval = timestamps[code] else { return nil }
        return Date(timeIntervalSince1970: timeInterval)
    }

    func betterAlternatives(for product: Product, limit: Int = 3) -> [Product] {
        let combined = scannedProducts + favoriteProducts + searchResults
        var seen: Set<String> = []
        let unique = combined.filter { item in
            guard item.code != product.code else { return false }
            return seen.insert(item.code).inserted
        }

        let better = unique.filter {
            $0.score.overallScore > product.score.overallScore &&
            isCompatibleWithCurrentProfile($0)
        }
        return Array(better.sorted { $0.score.overallScore > $1.score.overallScore }.prefix(limit))
    }

    func recordSearchQuery(_ query: String) {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 2 else { return }

        recentSearches.removeAll { $0.caseInsensitiveCompare(normalized) == .orderedSame }
        recentSearches.insert(normalized, at: 0)
        if recentSearches.count > 12 {
            recentSearches = Array(recentSearches.prefix(12))
        }
        saveRecentSearches()
    }

    func removeRecentSearch(_ query: String) {
        recentSearches.removeAll { $0 == query }
        saveRecentSearches()
    }

    func clearRecentSearches() {
        recentSearches.removeAll()
        saveRecentSearches()
    }

    func addWatchlistTerm(_ term: String) {
        let normalized = term
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard normalized.count >= 2 else { return }
        guard !watchlistTerms.contains(normalized) else { return }

        watchlistTerms.append(normalized)
        watchlistTerms.sort()
        saveWatchlist()
    }

    func removeWatchlistTerm(_ term: String) {
        watchlistTerms.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
        saveWatchlist()
    }

    func productMatchesWatchlist(_ product: Product) -> [String] {
        guard !watchlistTerms.isEmpty else { return [] }

        let haystack = [
            product.displayName,
            product.product.ingredientsText ?? "",
            product.product.allergens ?? "",
            product.product.labels ?? ""
        ].joined(separator: " ").lowercased()

        return watchlistTerms.filter { haystack.contains($0) }
    }

    func toggleDietaryPreference(_ preference: DietaryPreference) {
        if dietaryPreferences.contains(preference) {
            dietaryPreferences.remove(preference)
        } else {
            dietaryPreferences.insert(preference)
        }
        saveDietaryPreferences()
    }

    func conflictsForCurrentProfile(_ product: Product) -> [DietaryPreference] {
        product.dietaryConflicts(for: dietaryPreferences)
    }

    func isCompatibleWithCurrentProfile(_ product: Product) -> Bool {
        product.matchesDietaryPreferences(dietaryPreferences)
    }

    struct Achievement: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let symbol: String
        let tint: Color
        let unlocked: Bool
    }

    func achievements() -> [Achievement] {
        let totalScans = scannedProducts.count
        let streak = currentStreak()
        let avgScore = scannedProducts.isEmpty ? 0 : scannedProducts.map(\.score.overallScore).reduce(0, +) / scannedProducts.count

        return [
            Achievement(
                id: "first_scan",
                title: "First Scan",
                subtitle: "Scan your first product",
                symbol: "1.circle.fill",
                tint: .blue,
                unlocked: totalScans >= 1
            ),
            Achievement(
                id: "consistency",
                title: "Consistency",
                subtitle: "Reach a 3-day streak",
                symbol: "flame.fill",
                tint: .orange,
                unlocked: streak >= 3
            ),
            Achievement(
                id: "quality_hunter",
                title: "Quality Hunter",
                subtitle: "Keep average score above 70",
                symbol: "sparkles",
                tint: .green,
                unlocked: avgScore >= 70 && totalScans >= 5
            ),
            Achievement(
                id: "favorites_builder",
                title: "Favorites Builder",
                subtitle: "Save 5 products",
                symbol: "heart.fill",
                tint: .pink,
                unlocked: favoriteProducts.count >= 5
            )
        ]
    }

    func scansByDay(lastDays: Int = 7) -> [(date: Date, count: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days = (0..<lastDays).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let dateCounts = Dictionary(grouping: scanDates()) { calendar.startOfDay(for: $0) }
            .mapValues { $0.count }

        return days.reversed().map { date in
            (date: date, count: dateCounts[date] ?? 0)
        }
    }

    func currentStreak() -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let scanSet = Set(scanDates().map { calendar.startOfDay(for: $0) })
        var streak = 0

        while let date = calendar.date(byAdding: .day, value: -streak, to: today),
              scanSet.contains(date) {
            streak += 1
        }

        return streak
    }

    private func cachedProduct(for barcode: String) -> Product? {
        if let product = scannedProducts.first(where: { $0.code == barcode }) {
            return product
        }

        return favoriteProducts.first(where: { $0.code == barcode })
    }

    private func scanDates() -> [Date] {
        scannedProducts.compactMap { lastSeenDate(for: $0.code) }
    }

    private func presentCachedProduct(_ product: Product) {
        setCurrentProduct(product)
        isShowingCachedProduct = true
        isShowingProductDetail = true
    }

    private func setCurrentProduct(_ product: Product) {
        if currentProduct?.code != product.code {
            previousProduct = currentProduct
        }
        currentProduct = product
        addToHistory(product)
        requestScanAgain = false
    }

    private func lastSeenTimestamps() -> [String: TimeInterval] {
        guard let data = userDefaults.data(forKey: lastSeenKey) else { return [:] }
        return (try? JSONDecoder().decode([String: TimeInterval].self, from: data)) ?? [:]
    }

    private func updateLastSeen(for code: String) {
        var timestamps = lastSeenTimestamps()
        timestamps[code] = Date().timeIntervalSince1970
        if let data = try? JSONEncoder().encode(timestamps) {
            userDefaults.set(data, forKey: lastSeenKey)
        }
    }

    private func loadFavorites() {
        do {
            guard let data = userDefaults.data(forKey: favoritesKey) else { return }
            let decoder = JSONDecoder()
            favoriteProducts = try decoder.decode([Product].self, from: data)
        } catch {
            print("Error loading favorites: \(error.localizedDescription)")
            // Clear corrupted data
            userDefaults.removeObject(forKey: favoritesKey)
        }
    }

    private func saveFavorites() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(favoriteProducts)
            userDefaults.set(data, forKey: favoritesKey)
        } catch {
            print("Error saving favorites: \(error.localizedDescription)")
        }
    }

    private func loadHistory() {
        do {
            guard let data = userDefaults.data(forKey: historyKey) else { return }
            let decoder = JSONDecoder()
            scannedProducts = try decoder.decode([Product].self, from: data)
        } catch {
            print("Error loading history: \(error.localizedDescription)")
            // Clear corrupted data
            userDefaults.removeObject(forKey: historyKey)
        }
    }

    private func saveHistory() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(scannedProducts)
            userDefaults.set(data, forKey: historyKey)
        } catch {
            print("Error saving history: \(error.localizedDescription)")
        }
    }

    private func loadWatchlist() {
        guard let saved = userDefaults.array(forKey: watchlistKey) as? [String] else { return }
        watchlistTerms = saved
    }

    private func saveWatchlist() {
        userDefaults.set(watchlistTerms, forKey: watchlistKey)
    }

    private func loadRecentSearches() {
        guard let saved = userDefaults.array(forKey: recentSearchesKey) as? [String] else { return }
        recentSearches = saved
    }

    private func saveRecentSearches() {
        userDefaults.set(recentSearches, forKey: recentSearchesKey)
    }

    private func loadDietaryPreferences() {
        guard let saved = userDefaults.array(forKey: dietaryPreferencesKey) as? [String] else { return }
        dietaryPreferences = Set(saved.compactMap(DietaryPreference.init(rawValue:)))
    }

    private func saveDietaryPreferences() {
        userDefaults.set(dietaryPreferences.map(\.rawValue), forKey: dietaryPreferencesKey)
    }
}

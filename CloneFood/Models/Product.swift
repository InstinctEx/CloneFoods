//
//  Product.swift
//  CloneFood
//
//  Created by Demex on 18/12/2025
//

import Foundation
import SwiftUI

struct Product: Codable, Identifiable, Hashable {
    let code: String
    let product: ProductDetails

    // Computed property for Identifiable conformance
    var id: String { code }

    enum CodingKeys: String, CodingKey {
        case code
        case product
    }

    init(code: String, product: ProductDetails) {
        self.code = code
        self.product = product
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)

        // Search responses are flat while product responses are nested under `product`.
        if let nestedProduct = try container.decodeIfPresent(ProductDetails.self, forKey: .product) {
            product = nestedProduct
        } else {
            product = try ProductDetails(from: decoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encode(product, forKey: .product)
    }

    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Product, rhs: Product) -> Bool {
        lhs.id == rhs.id
    }
}

struct ProductDetails: Codable {
    let productName: String?
    let brands: String?
    let imageUrl: String?
    let ingredientsText: String?
    let nutriscoreGrade: String?
    let ecoscoreGrade: String?
    let novaGroup: Int?
    let nutriments: Nutriments?
    let categories: String?
    let categoriesTags: [String]?
    let labels: String?
    let labelsTags: [String]?
    let allergens: String?
    let additivesTags: [String]?

    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case brands
        case imageUrl = "image_url"
        case ingredientsText = "ingredients_text"
        case nutriscoreGrade = "nutriscore_grade"
        case ecoscoreGrade = "ecoscore_grade"
        case novaGroup = "nova_group"
        case nutriments
        case categories
        case categoriesTags = "categories_tags"
        case labels
        case labelsTags = "labels_tags"
        case allergens
        case additivesTags = "additives_tags"
    }
}

struct Nutriments: Codable {
    let energyKcal: Double?
    let energyKj: Double?
    let fat: Double?
    let saturatedFat: Double?
    let carbohydrates: Double?
    let sugars: Double?
    let fiber: Double?
    let proteins: Double?
    let salt: Double?
    let sodium: Double?

    enum CodingKeys: String, CodingKey {
        case energyKcal = "energy-kcal"
        case energyKj = "energy-kj"
        case fat
        case saturatedFat = "saturated-fat"
        case carbohydrates
        case sugars
        case fiber
        case proteins
        case salt
        case sodium
    }
}

struct ProductScore {
    let nutriscore: NutriscoreGrade
    let ecoscore: EcoscoreGrade
    let novaGroup: NovaGroup
    let overallScore: Int // 0-100 scale
    let recommendation: String

    enum NutriscoreGrade: String, CaseIterable, Hashable {
        case a, b, c, d, e

        var color: Color {
            switch self {
            case .a: return .green
            case .b: return .green.opacity(0.8)
            case .c: return .yellow
            case .d: return .orange
            case .e: return .red
            }
        }

        var score: Int {
            switch self {
            case .a: return 100
            case .b: return 80
            case .c: return 60
            case .d: return 40
            case .e: return 20
            }
        }
    }

    enum EcoscoreGrade: String, CaseIterable, Hashable {
        case a, b, c, d, e

        var color: Color {
            switch self {
            case .a: return .green
            case .b: return .green.opacity(0.8)
            case .c: return .yellow
            case .d: return .orange
            case .e: return .red
            }
        }

        var score: Int {
            switch self {
            case .a: return 100
            case .b: return 80
            case .c: return 60
            case .d: return 40
            case .e: return 20
            }
        }
    }

    enum NovaGroup: Int, CaseIterable, Hashable {
        case one = 1, two = 2, three = 3, four = 4

        var description: String {
            switch self {
            case .one: return "Unprocessed or minimally processed foods"
            case .two: return "Processed culinary ingredients"
            case .three: return "Processed foods"
            case .four: return "Ultra-processed food and drink products"
            }
        }

        var color: Color {
            switch self {
            case .one: return .green
            case .two: return .yellow
            case .three: return .orange
            case .four: return .red
            }
        }

        var score: Int {
            switch self {
            case .one: return 100
            case .two: return 75
            case .three: return 50
            case .four: return 25
            }
        }
    }
}

extension Product {
    var displayName: String {
        product.productName ?? "Unknown Product"
    }

    var brand: String {
        product.brands ?? ""
    }

    var imageURL: URL? {
        guard let urlString = product.imageUrl else { return nil }
        return URL(string: urlString)
    }

    var productURL: URL? {
        URL(string: "https://world.openfoodfacts.org/product/\(code)")
    }

    var score: ProductScore {
        let nutriscore = ProductScore.NutriscoreGrade(rawValue: product.nutriscoreGrade?.lowercased() ?? "c") ?? .c
        let ecoscore = ProductScore.EcoscoreGrade(rawValue: product.ecoscoreGrade?.lowercased() ?? "c") ?? .c
        let nova = ProductScore.NovaGroup(rawValue: product.novaGroup ?? 3) ?? .three

        // Calculate overall score based on nutriscore, ecoscore, and nova group
        let nutriscoreWeight = 0.5
        let ecoscoreWeight = 0.3
        let novaWeight = 0.2

        let nutriscorePoints = Double(nutriscore.score)
        let ecoscorePoints = Double(ecoscore.score)
        let novaPoints = Double(nova.score)

        let overallScore = Int((nutriscorePoints * nutriscoreWeight) + (ecoscorePoints * ecoscoreWeight) + (novaPoints * novaWeight))

        let recommendation: String
        switch overallScore {
        case 80...100: recommendation = "Excellent choice!"
        case 60...79: recommendation = "Good choice"
        case 40...59: recommendation = "Moderate"
        case 20...39: recommendation = "Not the best choice"
        default: recommendation = "Poor choice"
        }

        return ProductScore(
            nutriscore: nutriscore,
            ecoscore: ecoscore,
            novaGroup: nova,
            overallScore: overallScore,
            recommendation: recommendation
        )
    }

    var scoreReasons: [String] {
        var reasons: [String] = []
        if let nutriments = product.nutriments {
            if let sugars = nutriments.sugars, sugars >= 15 {
                reasons.append("High sugar")
            }
            if let saturatedFat = nutriments.saturatedFat, saturatedFat >= 5 {
                reasons.append("High saturated fat")
            }
            if let salt = nutriments.salt, salt >= 1.5 {
                reasons.append("High salt")
            }
        }

        if let novaGroup = product.novaGroup, novaGroup >= 4 {
            reasons.append("Ultra-processed")
        }

        if reasons.isEmpty {
            reasons.append("Balanced profile")
        }

        return Array(reasons.prefix(2))
    }
}

extension ProductScore {
    var summaryLabel: String {
        switch overallScore {
        case 80...100: return "Excellent"
        case 60...79: return "Good"
        case 40...59: return "Caution"
        default: return "Avoid"
        }
    }

    var summaryColor: Color {
        switch overallScore {
        case 80...100: return .green
        case 60...79: return .blue
        case 40...59: return .orange
        default: return .red
        }
    }
}

enum DietaryPreference: String, Codable, CaseIterable, Identifiable {
    case vegan
    case vegetarian
    case glutenFree
    case lactoseFree
    case palmOilFree
    case porkFree
    case soyFree
    case sulfiteFree

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vegan: return "Vegan"
        case .vegetarian: return "Vegetarian"
        case .glutenFree: return "Gluten-Free"
        case .lactoseFree: return "Lactose-Free"
        case .palmOilFree: return "Palm Oil-Free"
        case .porkFree: return "Pork-Free"
        case .soyFree: return "Soy-Free"
        case .sulfiteFree: return "Sulfite-Free"
        }
    }

    var symbol: String {
        switch self {
        case .vegan: return "leaf.fill"
        case .vegetarian: return "carrot.fill"
        case .glutenFree: return "checkmark.shield"
        case .lactoseFree: return "drop"
        case .palmOilFree: return "hand.raised.fill"
        case .porkFree: return "fork.knife"
        case .soyFree: return "bolt.slash.fill"
        case .sulfiteFree: return "exclamationmark.shield"
        }
    }

    var tint: Color {
        switch self {
        case .vegan, .vegetarian, .glutenFree: return .green
        case .lactoseFree, .palmOilFree: return .blue
        case .porkFree, .soyFree: return .orange
        case .sulfiteFree: return .red
        }
    }

    fileprivate var blockedTerms: [String] {
        switch self {
        case .vegan:
            return ["milk", "egg", "honey", "gelatin", "meat", "fish", "cheese", "butter", "whey", "casein"]
        case .vegetarian:
            return ["meat", "fish", "gelatin", "chicken", "beef", "pork"]
        case .glutenFree:
            return ["gluten", "wheat", "barley", "rye", "malt", "spelt"]
        case .lactoseFree:
            return ["lactose", "milk", "whey", "casein", "cream", "butter"]
        case .palmOilFree:
            return ["palm oil", "palm fat", "huile de palme"]
        case .porkFree:
            return ["pork", "ham", "bacon", "gelatin", "lard"]
        case .soyFree:
            return ["soy", "soja", "soybean", "lecithin (soya)"]
        case .sulfiteFree:
            return ["sulfite", "sulphite", "sulfur dioxide", "e220", "e221", "e222", "e223", "e224", "e226", "e227", "e228"]
        }
    }
}

extension Product {
    private var searchableFoodText: String {
        [
            displayName,
            brand,
            product.ingredientsText ?? "",
            product.allergens ?? "",
            product.labels ?? "",
            product.categories ?? "",
            (product.labelsTags ?? []).joined(separator: " "),
            (product.categoriesTags ?? []).joined(separator: " "),
            (product.additivesTags ?? []).joined(separator: " ")
        ]
        .joined(separator: " ")
        .lowercased()
    }

    var dietaryConflicts: [DietaryPreference] {
        DietaryPreference.allCases.filter { searchableFoodText.containsAny(of: $0.blockedTerms) }
    }

    func dietaryConflicts(for selectedPreferences: Set<DietaryPreference>) -> [DietaryPreference] {
        dietaryConflicts.filter { selectedPreferences.contains($0) }
    }

    func matchesDietaryPreferences(_ selectedPreferences: Set<DietaryPreference>) -> Bool {
        dietaryConflicts(for: selectedPreferences).isEmpty
    }
}

private extension String {
    func containsAny(of terms: [String]) -> Bool {
        terms.contains { term in
            contains(term.lowercased())
        }
    }
}

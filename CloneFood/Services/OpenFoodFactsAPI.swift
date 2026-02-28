//
//  OpenFoodFactsAPI.swift
//  CloneFood
//
//  Created by Demex on 18/12/2025
//

import Foundation

class OpenFoodFactsAPI {
    static let baseURL = "https://world.openfoodfacts.org/api/v2"
    static let textSearchURL = "https://world.openfoodfacts.org/cgi/search.pl"

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 18
        config.waitsForConnectivity = true
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpAdditionalHeaders = [
            "User-Agent": "CloneFood - iOS - 1.0"
        ]
        return URLSession(configuration: config)
    }()

    enum APIError: Error, LocalizedError {
        case invalidURL
        case networkError(Error)
        case decodingError(Error)
        case noData
        case productNotFound
        case serverError(Int)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid URL"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .decodingError:
                return "Failed to parse response"
            case .noData:
                return "No data received"
            case .productNotFound:
                return "Product not found"
            case .serverError(let code):
                return "Server error: \(code)"
            }
        }
    }

    enum Endpoint {
        case product(code: String)
        case search(query: String, page: Int)

        var path: String {
            switch self {
            case .product(let code):
                return "/product/\(code)"
            case .search:
                return "/search"
            }
        }

        var queryItems: [URLQueryItem] {
            switch self {
            case .product:
                return [
                    URLQueryItem(name: "fields", value: "code,product_name,brands,image_url,ingredients_text,nutriscore_grade,ecoscore_grade,nova_group,nutriments,categories,categories_tags,labels,labels_tags,allergens,additives_tags")
                ]
            case .search(let query, let page):
                return [
                    URLQueryItem(name: "query", value: query),
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "fields", value: "code,product_name,brands,image_url,nutriscore_grade,ecoscore_grade,nova_group,nutriments,categories,categories_tags,labels,labels_tags,allergens,additives_tags")
                ]
            }
        }
    }

    static func searchProducts(query: String, page: Int = 1) async throws -> [Product] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        do {
            let primary = try await runSearchRequest(query: trimmedQuery, page: page)
            if !primary.isEmpty {
                return rankProducts(primary, for: trimmedQuery)
            }

            // Fallback for broad/noisy terms: try shorter phrase.
            let tokens = trimmedQuery.split(separator: " ").map(String.init)
            if tokens.count > 1 {
                let fallbackQuery = tokens.prefix(2).joined(separator: " ")
                if fallbackQuery.caseInsensitiveCompare(trimmedQuery) != .orderedSame {
                    let fallback = try await runSearchRequest(query: fallbackQuery, page: page)
                    return rankProducts(fallback, for: fallbackQuery)
                }
            }

            return []
        } catch let error as APIError {
            throw error
        } catch let error as DecodingError {
            throw APIError.decodingError(error)
        } catch {
            throw APIError.networkError(error)
        }
    }

    private static func runSearchRequest(query: String, page: Int) async throws -> [Product] {
        guard var urlComponents = URLComponents(string: textSearchURL) else {
            throw APIError.invalidURL
        }

        urlComponents.queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page_size", value: "20"),
            URLQueryItem(name: "fields", value: "code,product_name,brands,image_url,ingredients_text,nutriscore_grade,ecoscore_grade,nova_group,nutriments,categories,categories_tags,labels,labels_tags,allergens,additives_tags")
        ]

        guard let url = urlComponents.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10

        let (data, httpResponse) = try await fetchData(for: request)

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(SearchResponse.self, from: data).products
    }

    private static func rankProducts(_ products: [Product], for query: String) -> [Product] {
        let normalizedQuery = query.lowercased()

        return products.sorted { lhs, rhs in
            let lhsName = lhs.displayName.lowercased()
            let rhsName = rhs.displayName.lowercased()

            let lhsStarts = lhsName.hasPrefix(normalizedQuery)
            let rhsStarts = rhsName.hasPrefix(normalizedQuery)
            if lhsStarts != rhsStarts { return lhsStarts && !rhsStarts }

            let lhsContains = lhsName.contains(normalizedQuery)
            let rhsContains = rhsName.contains(normalizedQuery)
            if lhsContains != rhsContains { return lhsContains && !rhsContains }

            return lhs.score.overallScore > rhs.score.overallScore
        }
    }

    static func getProduct(by barcode: String) async throws -> Product {
        let endpoint = Endpoint.product(code: barcode)

        guard var urlComponents = URLComponents(string: baseURL + endpoint.path) else {
            throw APIError.invalidURL
        }

        urlComponents.queryItems = endpoint.queryItems

        guard let url = urlComponents.url else {
            throw APIError.invalidURL
        }

        let (data, httpResponse) = try await fetchData(from: url)

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(httpResponse.statusCode)
        }

        do {
            let productResponse = try JSONDecoder().decode(ProductResponse.self, from: data)
            if productResponse.status == 0 {
                throw APIError.productNotFound
            }
            guard let productDetails = productResponse.product else {
                throw APIError.decodingError(DecodingError.valueNotFound(
                    ProductDetails.self,
                    .init(codingPath: [], debugDescription: "Missing product details")
                ))
            }
            let code = productResponse.code ?? barcode
            return Product(code: code, product: productDetails)
        } catch let error as DecodingError {
            throw APIError.decodingError(error)
        } catch {
            throw APIError.networkError(error)
        }
    }

    private static func fetchData(from url: URL) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.networkError(NSError(domain: "Invalid response", code: -1))
            }
            return (data, httpResponse)
        } catch let error as URLError where shouldRetry(error) {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.networkError(NSError(domain: "Invalid response", code: -1))
            }
            return (data, httpResponse)
        } catch {
            throw APIError.networkError(error)
        }
    }

    private static func fetchData(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.networkError(NSError(domain: "Invalid response", code: -1))
            }
            return (data, httpResponse)
        } catch let error as URLError where shouldRetry(error) {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.networkError(NSError(domain: "Invalid response", code: -1))
            }
            return (data, httpResponse)
        } catch {
            throw APIError.networkError(error)
        }
    }

    private static func shouldRetry(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }
}

struct SearchResponse: Codable {
    let products: [Product]
    let count: Int
    let page: Int
    let pageCount: Int

    enum CodingKeys: String, CodingKey {
        case products
        case count
        case page
        case pageCount = "page_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        products = try container.decodeIfPresent([Product].self, forKey: .products) ?? []
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? products.count
        page = try container.decodeIfPresent(Int.self, forKey: .page) ?? 1
        pageCount = try container.decodeIfPresent(Int.self, forKey: .pageCount) ?? 1
    }
}

private struct ProductResponse: Codable {
    let code: String?
    let product: ProductDetails?
    let status: Int?
}

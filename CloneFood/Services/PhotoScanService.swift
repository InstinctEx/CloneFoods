import Foundation
import UIKit
@preconcurrency import Vision

struct PhotoScanResult {
    let barcode: String?
    let labels: [String]
    let suggestedProducts: [Product]
}

enum PhotoScanError: LocalizedError {
    case imageUnavailable
    case noBarcodeOrLabels

    var errorDescription: String? {
        switch self {
        case .imageUnavailable:
            return "Could not read the selected photo."
        case .noBarcodeOrLabels:
            return "No barcode or recognizable food labels were found."
        }
    }
}

final class PhotoScanService {
    func analyze(image: UIImage) async throws -> PhotoScanResult {
        guard let cgImage = image.cgImage else {
            throw PhotoScanError.imageUnavailable
        }

        if let barcode = await detectBarcode(in: cgImage) {
            return PhotoScanResult(barcode: barcode, labels: [], suggestedProducts: [])
        }

        let labels = await classifyLabels(in: cgImage)
        guard !labels.isEmpty else {
            throw PhotoScanError.noBarcodeOrLabels
        }

        let suggestions = try await fetchSuggestions(for: labels)
        return PhotoScanResult(barcode: nil, labels: labels, suggestedProducts: suggestions)
    }

    private func detectBarcode(in cgImage: CGImage) async -> String? {
        await withCheckedContinuation { continuation in
            let request = VNDetectBarcodesRequest { request, _ in
                let observations = request.results as? [VNBarcodeObservation]
                let first = observations?.first?.payloadStringValue
                continuation.resume(returning: first)
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    private func classifyLabels(in cgImage: CGImage) async -> [String] {
        await withCheckedContinuation { continuation in
            let request = VNClassifyImageRequest { request, _ in
                guard let observations = request.results as? [VNClassificationObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let labels = observations
                    .filter { $0.confidence >= 0.1 }
                    .map { $0.identifier.lowercased() }
                    .filter { Self.isFoodLikeLabel($0) }

                let unique = Array(Set(labels)).prefix(6)
                continuation.resume(returning: Array(unique))
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    private func fetchSuggestions(for labels: [String]) async throws -> [Product] {
        var uniqueByCode: [String: Product] = [:]

        for label in labels {
            let products = try await OpenFoodFactsAPI.searchProducts(query: label)
            for product in products.prefix(5) {
                uniqueByCode[product.code] = product
                if uniqueByCode.count >= 12 {
                    break
                }
            }
            if uniqueByCode.count >= 12 {
                break
            }
        }

        return Array(uniqueByCode.values)
            .sorted { $0.score.overallScore > $1.score.overallScore }
    }

    private static func isFoodLikeLabel(_ label: String) -> Bool {
        let foodKeywords = [
            "food", "meal", "dish", "fruit", "vegetable", "salad", "bread", "pizza", "burger", "sandwich", "soup", "pasta", "rice", "noodle", "meat", "chicken", "beef", "fish", "dessert", "cake", "cookie", "snack", "drink", "beverage", "juice", "milk", "coffee", "tea", "chocolate", "cheese", "egg", "yogurt"
        ]

        return foodKeywords.contains(where: { label.contains($0) })
    }
}

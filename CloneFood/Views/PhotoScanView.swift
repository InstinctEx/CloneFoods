import SwiftUI
import PhotosUI

struct PhotoScanView: View {
    @ObservedObject var viewModel: FoodScannerViewModel
    @Binding var isPresented: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isAnalyzing = false
    @State private var suggestions: [Product] = []
    @State private var labels: [String] = []
    @State private var statusMessage: String?
    @State private var showContent = false

    private let service = PhotoScanService()

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackdrop()

                ScrollView {
                    VStack(spacing: 16) {
                        headerCard
                            .motionStage(visible: showContent, index: 0, reduceMotion: reduceMotion)

                        photoPreviewCard
                            .motionStage(visible: showContent, index: 1, reduceMotion: reduceMotion)

                        actionCard
                            .motionStage(visible: showContent, index: 2, reduceMotion: reduceMotion)

                        if !labels.isEmpty {
                            labelsCard
                                .motionStage(visible: showContent, index: 3, reduceMotion: reduceMotion)
                        }

                        if !suggestions.isEmpty {
                            suggestionsCard
                                .motionStage(visible: showContent, index: 4, reduceMotion: reduceMotion)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Photo Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
            .onChange(of: selectedPhoto) { _, _ in
                Task {
                    await loadSelectedPhoto()
                }
            }
            .onAppear {
                if reduceMotion {
                    showContent = true
                } else {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                        showContent = true
                    }
                }
            }
            .onChange(of: suggestions.count) { _, _ in
                guard !reduceMotion else {
                    showContent = true
                    return
                }
                showContent = false
                withAnimation(.spring(response: 0.46, dampingFraction: 0.86)) {
                    showContent = true
                }
            }
            .alert("Photo Scan", isPresented: Binding(
                get: { statusMessage != nil },
                set: { if !$0 { statusMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(statusMessage ?? "")
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scan From a Food Photo")
                .font(.system(.title3, design: .rounded).weight(.bold))
            Text("We first try to detect a barcode in the image. If no barcode is found, we analyze the food and suggest likely products.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .glassCard()
    }

    private var photoPreviewCard: some View {
        VStack(spacing: 12) {
            if let selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.18))
                    .frame(height: 220)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("Choose a photo to start")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
            }

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label(selectedImage == nil ? "Choose Photo" : "Replace Photo", systemImage: "photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .glassCard()
    }

    private var actionCard: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    await analyzeSelectedPhoto()
                }
            } label: {
                if isAnalyzing {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Analyze Photo", systemImage: "sparkles.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedImage == nil || isAnalyzing)

            Text("Tip: include barcode and packaging for best accuracy.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .glassCard()
    }

    private var labelsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Detected Food Labels")
                .font(.system(.headline, design: .rounded).weight(.semibold))

            FlexibleTagGrid(items: labels) { label in
                Text(label.capitalized)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.blue.opacity(0.12))
                    )
            }
        }
        .padding(16)
        .glassCard()
    }

    private var suggestionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Possible Matches")
                .font(.system(.headline, design: .rounded).weight(.semibold))

            ForEach(suggestions) { product in
                Button {
                    viewModel.selectProduct(product)
                    isPresented = false
                } label: {
                    HStack(spacing: 10) {
                        Text(product.displayName)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .lineLimit(2)
                            .foregroundStyle(.primary)

                        Spacer()

                        Text("\(product.score.overallScore)")
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.thinMaterial)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .glassCard()
    }

    private func loadSelectedPhoto() async {
        guard let selectedPhoto else { return }
        guard let data = try? await selectedPhoto.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else {
            statusMessage = "Could not load that image."
            return
        }

        selectedImage = image
        suggestions = []
        labels = []
    }

    private func analyzeSelectedPhoto() async {
        guard let selectedImage else { return }

        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            let result = try await service.analyze(image: selectedImage)

            if let barcode = result.barcode {
                await viewModel.scanProduct(barcode: barcode)
                isPresented = false
                return
            }

            labels = result.labels
            suggestions = result.suggestedProducts

            if suggestions.isEmpty {
                statusMessage = "We recognized food labels, but couldn't find strong product matches. Try a clearer packaging photo."
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

#Preview {
    PhotoScanView(viewModel: FoodScannerViewModel(), isPresented: .constant(true))
}

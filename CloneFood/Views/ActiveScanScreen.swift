//
//  ActiveScanScreen.swift
//  CloneFood
//
//  Polished sci-fi scan UX:
//  - Full-bleed camera (UIKit is camera-only; SwiftUI owns UI)
//  - FaceID-like micro-freeze (120ms) before success snap
//  - Dynamic reticle size based on proximity (barcode box size → 0..1)
//  - Adaptive glow based on ambient light (0..1 dark→bright)
//
//  NOTE: This file expects BarcodeScannerView to have the initializer:
//  BarcodeScannerView(viewModel:isScanning:proximity:ambientLight:)
//

import SwiftUI
import AVFoundation
import UIKit

struct ActiveScanScreen: View {
    @ObservedObject var viewModel: FoodScannerViewModel
    @Binding var isPresented: Bool

    @State private var isScanning = true
    @State private var cameraPermissionGranted = false
    @State private var showPermissionAlert = false
    @State private var isTorchOn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    private var isCameraAvailable: Bool {
        AVCaptureDevice.default(for: .video) != nil
    }

    private var cameraUnavailableDescription: String? {
        guard !isCameraAvailable else { return nil }
        #if targetEnvironment(simulator)
        return "Camera is unavailable in the iPhone Simulator. Use a physical iPhone to scan barcodes."
        #else
        return "No camera device is currently available."
        #endif
    }

    // Live signals from camera pipeline
    @State private var proximity: CGFloat = 0.25        // 0..1 (far..near)
    @State private var ambientLight: CGFloat = 0.50     // 0..1 (dark..bright)

    // Success motion
    @State private var showSuccessAnimation = false
    @State private var didTriggerSuccess = false

    @Namespace private var reticleNS

    var body: some View {
        ZStack {
            // Camera background
            if cameraPermissionGranted {
                BarcodeScannerView(
                    viewModel: viewModel,
                    isScanning: $isScanning,
                    proximity: $proximity,
                    ambientLight: $ambientLight
                )
                .ignoresSafeArea()
            } else {
                permissionView
                    .ignoresSafeArea()
            }

            // Minimal overlay UI
            if cameraPermissionGranted {
                overlayUI
                    .ignoresSafeArea()
            }
        }
        .onAppear { checkCameraPermission() }
        .alert("Scan Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
        .onChange(of: viewModel.isShowingProductDetail) { _, newValue in
            // When product detail is ready, play success + dismiss
            guard newValue, !viewModel.isLoading, !didTriggerSuccess else { return }
            didTriggerSuccess = true

            AppHaptics.impact(.medium)

            // ✅ FaceID-like micro-freeze before success snap
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.86, blendDuration: 0.10)) {
                    showSuccessAnimation = true
                }
            }

            // Dismiss after success beat (lets snap + pulse be visible)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.70) {
                isPresented = false
            }
        }
        .onChange(of: isPresented) { _, presented in
            if presented {
                didTriggerSuccess = false
                showSuccessAnimation = false
                isScanning = true
            }
        }
        .alert("Camera access needed", isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enable camera access in Settings to scan barcodes.")
        }
    }

    // MARK: - Views

    private var overlayUI: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 16)
                .padding(.top, 14)

            Spacer()

            // Reticle + animation (always active while scanning)
            ZStack {
                AnimatedScanFrame(
                    isLoading: viewModel.isLoading,
                    ambientLight: ambientLight,
                    isAnimated: !reduceMotion
                )
                .frame(width: 280, height: 180)

                if showSuccessAnimation {
                    SuccessReticle()
                        .matchedGeometryEffect(id: "reticle", in: reticleNS)
                        .frame(width: 240, height: 150)
                        .transition(.opacity)
                } else {
                    SciFiScanReticle(
                        isLoading: viewModel.isLoading,
                        proximity: proximity,
                        ambientLight: ambientLight,
                        isAnimated: !reduceMotion
                    )
                    .matchedGeometryEffect(id: "reticle", in: reticleNS)
                    .frame(width: 260, height: 170)
                    .transition(.opacity)
                }
            }
            // subtle depth separation from camera
            .compositingGroup()
            .shadow(color: .black.opacity(0.35), radius: 22, x: 0, y: 14)

            // Minimal processing indicator (only if loading)
            if viewModel.isLoading && !showSuccessAnimation {
                ProcessingDots()
                    .padding(.top, 12)
                    .transition(.opacity)
            }

            Spacer()
        }
    }

    private var topBar: some View {
        HStack {
            Button { isPresented = false } label: {
                Image(systemName: "xmark")
                    .font(.system(.subheadline, design: .default).weight(.semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.28))
                    .clipShape(Circle())
            }

            Spacer()

            Button { toggleTorch() } label: {
                Image(systemName: isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.system(.subheadline, design: .default).weight(.semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.28))
                    .clipShape(Circle())
            }
        }
    }

    private var permissionView: some View {
        Color.black
            .overlay(
                VStack(spacing: 18) {
                    Image(systemName: "camera")
                        .font(.system(.largeTitle, design: .default).weight(.light))
                        .foregroundColor(.white.opacity(0.85))

                    Text(cameraUnavailableDescription == nil ? "Camera access needed to scan barcodes" : "Camera unavailable")
                        .font(.system(.body, design: .default))
                        .foregroundColor(.white.opacity(0.92))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)

                    if let cameraUnavailableDescription {
                        Text(cameraUnavailableDescription)
                            .font(.system(.callout, design: .default))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    } else {
                        Button { checkCameraPermission() } label: {
                            Text("Continue")
                                .font(.system(.headline, design: .default).weight(.semibold))
                                .foregroundColor(.white)
                                .frame(height: 44)
                                .frame(maxWidth: 220)
                                .background(.white.opacity(0.18))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 24)
            )
    }

    // MARK: - Permission + Torch

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPermissionGranted = isCameraAvailable
            isScanning = isCameraAvailable
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    let cameraAvailable = isCameraAvailable
                    cameraPermissionGranted = granted && cameraAvailable
                    if granted && cameraAvailable {
                        isScanning = true
                    } else if !granted {
                        showPermissionAlert = true
                    } else {
                        isScanning = false
                    }
                }
            }
        case .denied, .restricted:
            cameraPermissionGranted = false
            showPermissionAlert = true
        @unknown default:
            break
        }
    }

    private func toggleTorch() {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = isTorchOn ? .off : .on
            isTorchOn.toggle()
            device.unlockForConfiguration()
        } catch {
            print("Unable to toggle torch: \(error)")
        }
    }
}

// MARK: - Sci-Fi Reticle (dynamic size + adaptive glow)

/// Sci-fi feel without UI clutter:
/// - Neon corners (no box)
/// - Soft energy band sweep (not a harsh line)
/// - Very faint shimmer in zone (no crisp border)
/// - Dynamic size based on proximity
/// - Glow strength based on ambient light
struct SciFiScanReticle: View {
    let isLoading: Bool
    let proximity: CGFloat       // 0..1 (far..near)
    let ambientLight: CGFloat    // 0..1 (dark..bright)
    let isAnimated: Bool

    var body: some View {
        Group {
            if isAnimated {
                TimelineView(.animation) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    reticleBody(time: t, breathe: (cos(t * 1.05) + 1) / 2)
                }
            } else {
                reticleBody(time: 0, breathe: 0)
            }
        }
        .allowsHitTesting(false)
    }

    private func reticleBody(time t: TimeInterval, breathe: Double) -> some View {
        // Clamp signals
        let p = min(max(proximity, 0), 1)
        let a = min(max(ambientLight, 0), 1)

        // ✅ Distance feel:
        // Farther -> slightly larger guide; closer -> slightly smaller
        let distanceScale: CGFloat = 1.0

        // ✅ Ambient glow:
        // Darker -> stronger glow; brighter -> calmer glow
        let glowBoost = 0.70 + (1.0 - a) * 0.85       // a=1 -> 0.70, a=0 -> 1.55
        let focusBoost = 0.85 + (p * 0.25)

        // Base glow/opacity
        let glowBase = (0.26 + breathe * 0.42) * glowBoost * focusBoost
        let opacity = 0.30 + breathe * 0.22

        // Add “loading energy”
        let loadingBoost: CGFloat = isLoading ? 1.0 : 0.78

        return ZStack {
            // faint shimmer texture (no crisp outline)
            ScanZoneShimmer(time: t)
                .opacity((isLoading ? 0.20 : 0.12) * glowBoost)

            // corners
            CornerBracketsShape(inset: 18, corner: 24)
                .stroke(style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .foregroundStyle(.white.opacity(0.92))
                .opacity(opacity + (isLoading ? 0.10 : 0.00))
                .shadow(color: .blue.opacity(glowBase), radius: 10)
                .shadow(color: .blue.opacity(glowBase * 0.65), radius: 22)
                .shadow(color: .cyan.opacity(glowBase * 0.35), radius: 34)

            // energy sweep band
            EnergyBandSweep(
                progress: sweepProgress(time: t),
                intensity: loadingBoost
            )
            .opacity(0.95)
        }
        .scaleEffect((1.0 + CGFloat(breathe) * 0.018) * distanceScale)
        .animation(nil, value: t)
    }

    private func sweepProgress(time t: Double) -> CGFloat {
        // Repeat period tuned for “scanner” feel
        let period = 1.70
        let p = t.truncatingRemainder(dividingBy: period) / period

        // Smoothstep easing to avoid mechanical linear motion
        let eased = p * p * (3 - 2 * p)
        return CGFloat(eased)
    }
}

// MARK: - Success Reticle (snap + subtle radial pulse outward)

struct AnimatedScanFrame: View {
    let isLoading: Bool
    let ambientLight: CGFloat
    let isAnimated: Bool

    var body: some View {
        Group {
            if isAnimated {
                TimelineView(.animation) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    frameBody(time: t)
                }
            } else {
                frameBody(time: 0)
            }
        }
        .allowsHitTesting(false)
    }

    private func frameBody(time t: TimeInterval) -> some View {
        let a = min(max(ambientLight, 0), 1)
        let breathe = (cos(t * 1.3) + 1) / 2
        let glowBoost = 0.65 + (1.0 - a) * 0.75
        let glow = (0.22 + breathe * 0.35) * glowBoost
        let strokeOpacity = 0.55 + breathe * 0.25

        return ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            .cyan.opacity(0.2),
                            .white.opacity(0.7),
                            .blue.opacity(0.6),
                            .white.opacity(0.7),
                            .cyan.opacity(0.2)
                        ]),
                        center: .center,
                        angle: .degrees(t * 20)
                    ),
                    lineWidth: 2.0
                )
                .opacity(strokeOpacity)
                .shadow(color: .cyan.opacity(glow), radius: 10)
                .shadow(color: .blue.opacity(glow * 0.7), radius: 20)

            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(isLoading ? 0.35 : 0.2), lineWidth: 1)
                .blur(radius: 0.6)
                .opacity(0.8)
        }
    }
}

struct SuccessReticle: View {
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Radial pulse outward (subtle)
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.green.opacity(0.42), lineWidth: 2)
                .scaleEffect(pulse ? 1.22 : 1.00)
                .opacity(pulse ? 0.0 : 0.42)
                .blur(radius: pulse ? 2.0 : 0.6)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: pulse)

            // Main success “frame”
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                .foregroundStyle(.white.opacity(0.95))
                .shadow(color: .green.opacity(0.85), radius: 10)
                .shadow(color: .green.opacity(0.55), radius: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.green.opacity(0.80), lineWidth: 1.0)
                        .blur(radius: 0.7)
                )

            Image(systemName: "checkmark")
                .font(.system(.headline, design: .default).weight(.bold))
                .foregroundColor(.white.opacity(0.93))
                .shadow(color: .green.opacity(0.85), radius: 10)
        }
        .onAppear {
            pulse = true
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }
}

// MARK: - Building blocks

/// Only corners (no box). Scales cleanly.
struct CornerBracketsShape: Shape {
    var inset: CGFloat = 18
    var corner: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        var p = Path()

        let left = rect.minX + inset
        let right = rect.maxX - inset
        let top = rect.minY + inset
        let bottom = rect.maxY - inset

        // Top-left
        p.move(to: CGPoint(x: left + corner, y: top))
        p.addLine(to: CGPoint(x: left, y: top))
        p.addLine(to: CGPoint(x: left, y: top + corner))

        // Top-right
        p.move(to: CGPoint(x: right - corner, y: top))
        p.addLine(to: CGPoint(x: right, y: top))
        p.addLine(to: CGPoint(x: right, y: top + corner))

        // Bottom-left
        p.move(to: CGPoint(x: left, y: bottom - corner))
        p.addLine(to: CGPoint(x: left, y: bottom))
        p.addLine(to: CGPoint(x: left + corner, y: bottom))

        // Bottom-right
        p.move(to: CGPoint(x: right, y: bottom - corner))
        p.addLine(to: CGPoint(x: right, y: bottom))
        p.addLine(to: CGPoint(x: right - corner, y: bottom))

        return p
    }
}

/// Soft energy band sweep (the “sci-fi” read).
struct EnergyBandSweep: View {
    let progress: CGFloat     // 0..1
    let intensity: CGFloat    // 0..1

    var body: some View {
        GeometryReader { geo in
            let y = geo.size.height * progress
            let bandHeight: CGFloat = 14

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            .cyan.opacity(0.14 * intensity),
                            .blue.opacity(0.32 * intensity),
                            .cyan.opacity(0.18 * intensity),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: bandHeight)
                .blur(radius: 8)
                .overlay(
                    Rectangle()
                        .fill(.blue.opacity(0.26 * intensity))
                        .frame(height: 2.2)
                        .blur(radius: 2.6)
                )
                .shadow(color: .blue.opacity(0.35 * intensity), radius: 16)
                .shadow(color: .cyan.opacity(0.20 * intensity), radius: 30)
                .offset(y: y - bandHeight / 2)
        }
        .allowsHitTesting(false)
    }
}

/// Faint shimmer inside scan zone without creating a crisp border.
/// (Only moving light band clipped to the rounded rect.)
struct ScanZoneShimmer: View {
    let time: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let phase = CGFloat((time * 0.18).truncatingRemainder(dividingBy: 1.0))
            let x = (-w) + (w * 2.0 * phase)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            .cyan.opacity(0.12),
                            .blue.opacity(0.10),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: w * 0.70)
                .blur(radius: 18)
                .offset(x: x)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Minimal loading indicator

struct ProcessingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                HStack(spacing: 6) {
                    dot(shift: 0, phase: 0)
                    dot(shift: 1, phase: 0)
                    dot(shift: 2, phase: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.black.opacity(0.22))
                .clipShape(Capsule())
            } else {
                TimelineView(.animation) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    let phase = t * 3.2

                    HStack(spacing: 6) {
                        dot(shift: 0, phase: phase)
                        dot(shift: 1, phase: phase)
                        dot(shift: 2, phase: phase)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.22))
                    .clipShape(Capsule())
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func dot(shift: Double, phase: Double) -> some View {
        let v = (sin(phase - shift * 0.7) + 1) / 2  // 0..1
        return Circle()
            .fill(.white.opacity(0.48 + v * 0.38))
            .frame(width: 6, height: 6)
            .scaleEffect(0.92 + v * 0.26)
    }
}

#Preview {
    ActiveScanScreen(viewModel: FoodScannerViewModel(), isPresented: .constant(true))
        .ignoresSafeArea()
}

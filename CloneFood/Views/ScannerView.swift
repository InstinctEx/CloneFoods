//
//  ScannerView.swift
//  CloneFood
//
//  Created by Demex on 18/12/2025
//

import SwiftUI
import AVFoundation
import UIKit

struct ScannerView: View {
    @ObservedObject var viewModel: FoodScannerViewModel
    @State private var isScanning = false
    @State private var cameraPermissionGranted = false
    @State private var showPermissionAlert = false
    @State private var cameraReady = false
    @State private var showSplash = true
    @State private var proximity: CGFloat = 0.25
    @State private var ambientLight: CGFloat = 0.5
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


    var body: some View {
        ZStack {
            // Full screen camera background
            if cameraPermissionGranted {
                BarcodeScannerView(
                        viewModel: viewModel,
                        isScanning: $isScanning,
                        proximity: $proximity,
                        ambientLight: $ambientLight
                    )
                    .ignoresSafeArea()
                    .scaleEffect(cameraReady ? 1.0 : 1.1)
                    .opacity(cameraReady ? 1.0 : 0.3)
                    .animation(reduceMotion ? nil : .spring(response: 0.8, dampingFraction: 0.7).delay(0.2), value: cameraReady)
            } else {
                // Camera not available - show placeholder
                Color.gray.opacity(0.1)
                    .edgesIgnoringSafeArea(.all)
                    .overlay(
                        VStack {
                            Image(systemName: "camera.circle")
                                .font(.system(.largeTitle, design: .default))
                                .foregroundColor(.red.opacity(0.6))

                            Text(cameraUnavailableDescription == nil ? "Camera access required" : "Camera unavailable")
                                .font(.system(.subheadline, design: .rounded).weight(.medium))
                                .foregroundColor(.secondary)
                                .padding(.top, 8)

                            if let cameraUnavailableDescription {
                                Text(cameraUnavailableDescription)
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 28)
                                    .padding(.top, 4)
                            } else {
                                Button(action: {
                                    checkCameraPermission()
                                }) {
                                    Text("Grant Permission")
                                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.blue.opacity(0.1))
                                        )
                                }
                                .padding(.top, 16)
                            }
                        }
                    )
            }

            // Splash screen overlay
            if showSplash {
                ZStack {
                    Color.black
                        .ignoresSafeArea()
                    VStack(spacing: 20) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(.largeTitle, design: .default))
                            .foregroundColor(.white)
                        Text("CloneFood Scanner")
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .foregroundColor(.white)
                        Text("Scan food products for nutritional insights")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)
                            .padding(.top, 20)
                    }
                }
                .transition(.opacity)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: showSplash)
            }

            // UI Overlay positioned over camera (full screen)
            VStack(spacing: 0) {
                // Top safe area with header
                VStack(spacing: 0) {
                    Spacer().frame(height: 20) // Top padding

                    HStack(alignment: .center, spacing: 8) {
                        Text("Food Scanner")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .opacity(cameraReady ? 1.0 : 0.0)
                            .offset(y: cameraReady ? 0 : -20)
                            .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.8).delay(0.8), value: cameraReady)

                        Spacer(minLength: 4)

                        #if DEBUG
                        HStack(spacing: 4) {
                            Button(action: {
                                AppHaptics.impact(.medium)
                                Task {
                                    await viewModel.scanProduct(barcode: "3017620422003")
                                }
                            }) {
                                Text("Nutella")
                                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                                    .foregroundColor(.orange)
                                    .lineLimit(1)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.black.opacity(0.3))
                                            .background(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(Color.orange.opacity(0.5), lineWidth: 1)
                                            )
                                    )
                            }
                            .accessibilityLabel("Test scan Nutella")

                            Button(action: {
                                AppHaptics.impact(.medium)
                                Task {
                                    await viewModel.scanProduct(barcode: "5449000000996")
                                }
                            }) {
                                Text("Cola")
                                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                                    .foregroundColor(.red)
                                    .lineLimit(1)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.black.opacity(0.3))
                                            .background(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(Color.red.opacity(0.5), lineWidth: 1)
                                            )
                                    )
                            }
                            .accessibilityLabel("Test scan Coca Cola")
                        }
                        .opacity(cameraReady ? 1.0 : 0.0)
                        .scaleEffect(cameraReady ? 1.0 : 0.8)
                        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.7).delay(1.2), value: cameraReady)
                        #endif

                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }

                Spacer() // Push instructions to bottom

                // Bottom instructions with proper background
                ZStack {
                    Color.black.opacity(0.3)
                        .blur(radius: 1)

                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            InstructionRow(icon: "1.circle.fill", text: "Point your camera at the product barcode")
                            InstructionRow(icon: "2.circle.fill", text: "Make sure the barcode is well lit")
                            InstructionRow(icon: "3.circle.fill", text: "Hold steady until the scan completes")
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 20)
                }
                .opacity(cameraReady ? 1.0 : 0.0)
                .offset(y: cameraReady ? 0 : 30)
                .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.8).delay(1.0), value: cameraReady)
            }
            .ignoresSafeArea()

            // Loading overlay when scanning (full screen on top of everything)
            if viewModel.isLoading {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                    .overlay(
                        VStack {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(1.5)
                            Text("Scanning product...")
                                .font(.system(.subheadline, design: .rounded).weight(.medium))
                                .foregroundColor(.white)
                                .padding(.top, 8)
                        }
                    )
                    .transition(.opacity)
                    .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: viewModel.isLoading)
            }
        }
        .onAppear {
            // Show splash for 1.5 seconds, then check camera permission
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) {
                    showSplash = false
                }
                // Check camera permission after splash
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    checkCameraPermission()
                    // Trigger camera animation after permission check
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.8, dampingFraction: 0.7)) {
                            cameraReady = true
                        }
                    }
                }
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
        .alert("Scan Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
    }

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
}

struct InstructionRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(.subheadline, design: .default).weight(.medium))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 0)
                .frame(width: 24, height: 24)

            Text(text)
                .font(.system(.body, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 0)
                .lineSpacing(4)

            Spacer()
        }
    }
}


#Preview {
    ScannerView(viewModel: FoodScannerViewModel())
}

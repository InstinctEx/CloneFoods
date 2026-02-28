//
//  BarcodeScannerView.swift
//  CloneFood
//
//  Camera-only scanner (UIKit) + live signals for SwiftUI:
//  - proximity (0..1) from detected barcode bounding box size
//  - ambientLight (0..1) from throttled frame luminance sampling
//
//  SwiftUI owns all overlays/animations.
//

import SwiftUI
import AVFoundation
import CoreImage

struct BarcodeScannerView: UIViewControllerRepresentable {
    @ObservedObject var viewModel: FoodScannerViewModel
    @Binding var isScanning: Bool

    // Live signals for SwiftUI reticle
    @Binding var proximity: CGFloat        // 0..1 (far..near)
    @Binding var ambientLight: CGFloat     // 0..1 (dark..bright)

    func makeUIViewController(context: Context) -> ScannerViewController {
        let scannerVC = ScannerViewController()
        scannerVC.delegate = context.coordinator
        return scannerVC
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {
        if isScanning {
            uiViewController.startScanning()
        } else {
            uiViewController.stopScanning()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            viewModel: viewModel,
            isScanning: $isScanning,
            proximity: $proximity,
            ambientLight: $ambientLight
        )
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, ScannerViewControllerDelegate {
        @ObservedObject var viewModel: FoodScannerViewModel
        @Binding var isScanning: Bool
        @Binding var proximity: CGFloat
        @Binding var ambientLight: CGFloat

        init(viewModel: FoodScannerViewModel,
             isScanning: Binding<Bool>,
             proximity: Binding<CGFloat>,
             ambientLight: Binding<CGFloat>) {
            self.viewModel = viewModel
            self._isScanning = isScanning
            self._proximity = proximity
            self._ambientLight = ambientLight
        }

        func didFind(barcode: String) {
            // Freeze scanning but DO NOT dismiss UI here
            isScanning = false

            Task {
                await viewModel.scanProduct(barcode: barcode)
            }
        }

        func didUpdateProximity(_ value: CGFloat) {
            proximity = value
        }

        func didUpdateAmbientLight(_ value: CGFloat) {
            ambientLight = value
        }

        func didFail(reason: String) {
            DispatchQueue.main.async {
                self.viewModel.errorMessage = reason
                self.viewModel.showError = true
                self.isScanning = false
            }
        }
    }
}

// MARK: - Scanner VC

protocol ScannerViewControllerDelegate: AnyObject {
    func didFind(barcode: String)
    func didUpdateProximity(_ value: CGFloat)      // 0..1
    func didUpdateAmbientLight(_ value: CGFloat)   // 0..1
    func didFail(reason: String)
}

final class ScannerViewController: UIViewController,
                                  AVCaptureMetadataOutputObjectsDelegate,
                                  AVCaptureVideoDataOutputSampleBufferDelegate {

    weak var delegate: ScannerViewControllerDelegate?

    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    // Ambient light sampling (throttled)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "clonefood.camera.video.queue")
    private let ciContext = CIContext(options: nil)
    private var lastLightUpdate: CFTimeInterval = 0

    // Proximity update throttling (optional, keeps UI stable)
    private var lastProximityUpdate: CFTimeInterval = 0
    private var smoothedProximity: CGFloat = 0.25

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        guard let videoDevice = AVCaptureDevice.default(for: .video) else {
            delegate?.didFail(reason: "Camera not available")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: videoDevice)
            guard captureSession.canAddInput(input) else {
                delegate?.didFail(reason: "Unable to add camera input")
                return
            }
            captureSession.addInput(input)
        } catch {
            delegate?.didFail(reason: "Camera access error")
            return
        }

        // Metadata output for barcodes
        let metadataOutput = AVCaptureMetadataOutput()
        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: .main)

            // ✅ Keep ALL barcode types
            metadataOutput.metadataObjectTypes = [
                .ean8, .ean13, .upce,
                .code39, .code93, .code128,
                .pdf417
            ]
        } else {
            delegate?.didFail(reason: "Unable to configure scanner")
            return
        }

        // Video output for ambient light sampling
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        // Preview layer
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        self.previewLayer = previewLayer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    // MARK: - Control

    func startScanning() {
        guard !captureSession.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }

    func stopScanning() {
        guard captureSession.isRunning else { return }
        captureSession.stopRunning()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopScanning()
    }

    // MARK: - Barcode detection + proximity

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {

        guard let readable = metadataObjects.first as? AVMetadataMachineReadableCodeObject else { return }

        // Proximity (0..1) from transformed bounding box size
        if let previewLayer,
           let transformed = previewLayer.transformedMetadataObject(for: readable) {
            let box = transformed.bounds

            // Normalize box width by screen width
            // Tune min/max if needed; these are safe defaults
            let normalized = min(max(box.width / max(view.bounds.width, 1), 0.08), 0.70)
            let raw = (normalized - 0.08) / (0.70 - 0.08) // 0..1

            // Throttle + smooth to avoid jitter
            let now = CACurrentMediaTime()
            if now - lastProximityUpdate > 0.05 { // ~20 Hz max
                lastProximityUpdate = now
                smoothedProximity = smoothedProximity * 0.82 + CGFloat(raw) * 0.18
                DispatchQueue.main.async {
                    self.delegate?.didUpdateProximity(self.smoothedProximity)
                }
            }
        }

        // Barcode value
        guard let value = readable.stringValue else { return }
        delegate?.didFind(barcode: value)
    }

    // MARK: - Ambient light sampling (throttled)

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        // Throttle to ~6 Hz (smooth but cheap)
        let now = CACurrentMediaTime()
        guard now - lastLightUpdate > 0.16 else { return }
        lastLightUpdate = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let input = CIImage(cvPixelBuffer: pixelBuffer)

        // Average brightness using CIAreaAverage (fast)
        let extent = input.extent
        guard let filter = CIFilter(name: "CIAreaAverage",
                                    parameters: [
                                        kCIInputImageKey: input,
                                        kCIInputExtentKey: CIVector(cgRect: extent)
                                    ]),
              let outputImage = filter.outputImage
        else { return }

        var rgba = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            outputImage,
            toBitmap: &rgba,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        // Luma approximation
        let r = CGFloat(rgba[0]) / 255.0
        let g = CGFloat(rgba[1]) / 255.0
        let b = CGFloat(rgba[2]) / 255.0
        let luma = min(max(0.2126 * r + 0.7152 * g + 0.0722 * b, 0), 1)

        DispatchQueue.main.async {
            self.delegate?.didUpdateAmbientLight(luma)
        }
    }
}

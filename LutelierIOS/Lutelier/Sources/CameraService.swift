import AVFoundation
import SwiftUI

struct CaptureResult { var processed: Data; var raw: Data?; var depth: AVDepthData?; var portrait: AVPortraitEffectsMatte? = nil; var hair: AVSemanticSegmentationMatte? = nil; var orientedMattes: PortraitMattes? = nil; var liveMovie: URL? = nil; var initialRecipe: Recipe? = nil }

final class CameraService: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "lutelier.capture")
    private let output = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let meterQueue = DispatchQueue(label: "lutelier.meter")
    private var lastMeterTime = 0.0
    private var device: AVCaptureDevice?
    private var input: AVCaptureDeviceInput?
    private var pendingProcessed: Data?
    private var pendingRaw: Data?
    private var pendingDepth: AVDepthData?
    private var pendingPortrait: AVPortraitEffectsMatte?
    private var pendingLiveMovie: URL?
    private var pendingHair: AVSemanticSegmentationMatte?
    @Published var livePhotoAvailable = false
    @Published var useLivePhoto = false
    @Published var useHEIF = true
    @Published var flashAvailable = false
    @Published var aperture = 1.8
    @Published var apertureStops: [Double] = []
    @Published var autoAperture = true
    @Published var autoExposure = true
    @Published var autoFocus = true
    @Published var autoWhiteBalance = true
    @Published var shutterBounds = (1.0/8000)...1.0
    @Published var exposureBiasBounds = -2.0...2.0
    @Published var ready = false
    @Published var error: String?
    @Published var rawAvailable = false
    @Published var depthAvailable = false
    @Published var portraitAvailable = false
    @Published var hairAvailable = false
    @Published var capturing = false
    @Published var lenses: [AVCaptureDevice] = []
    @Published var selectedLens = ""
    @Published var manual = false
    @Published var iso = 100.0
    @Published var shutter = 1.0 / 125.0
    @Published var focus = 0.5
    @Published var kelvin = 5500.0
    @Published var tint = 0.0
    @Published var zoom = 1.0
    @Published var zoomLimit = 5.0
    @Published var histogram = [Double](repeating: 0, count: 48)
    @Published var bias = 0.0
    @Published var useRAW = false
    @Published var useDepth = true
    @Published var flash = false
    @Published var isoBounds = 25.0...1600.0
    @Published var focusAvailable = false
    @Published var exposureAvailable = false
    @Published var whiteBalanceAvailable = false
    var onCapture: ((CaptureResult) -> Void)?

    func start() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        guard granted else { await MainActor.run { error = "Camera access is off. Enable Lutelier in Settings → Privacy & Security → Camera." }; return }
        queue.async { [weak self] in self?.configure() }
    }
    func stop() { queue.async { [weak self] in self?.session.stopRunning() } }

    private func configure() {
        if input != nil { session.startRunning(); return }
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTripleCamera, .builtInDualCamera, .builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera, .builtInTrueDepthCamera], mediaType: .video, position: .unspecified)
        guard let camera = discovery.devices.first(where: { $0.position == .back && ($0.deviceType == .builtInTripleCamera || $0.deviceType == .builtInDualCamera) }) ?? discovery.devices.first else { publishError("No camera available on this device."); return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        do {
            let newInput = try AVCaptureDeviceInput(device: camera)
            guard session.canAddInput(newInput), session.canAddOutput(output) else { throw LutelierError.message("Unable to configure photo capture.") }
            session.addInput(newInput); input = newInput; device = camera
            session.addOutput(output)
            if session.canAddOutput(videoOutput) {
                videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                videoOutput.alwaysDiscardsLateVideoFrames = true
                videoOutput.setSampleBufferDelegate(self, queue: meterQueue)
                session.addOutput(videoOutput)
            }
            configureOutput(camera)
            session.commitConfiguration()
            session.startRunning()
            DispatchQueue.main.async { self.lenses = discovery.devices; self.ready = true }
        } catch { session.commitConfiguration(); publishError(error.localizedDescription) }
    }

    private func configureOutput(_ camera: AVCaptureDevice) {
        output.isLivePhotoCaptureEnabled = output.isLivePhotoCaptureSupported
        output.maxPhotoQualityPrioritization = .quality
        output.isAppleProRAWEnabled = output.isAppleProRAWSupported
        output.isDepthDataDeliveryEnabled = output.isDepthDataDeliverySupported
        output.isPortraitEffectsMatteDeliveryEnabled = output.isDepthDataDeliveryEnabled && output.isPortraitEffectsMatteDeliverySupported
        output.enabledSemanticSegmentationMatteTypes = output.availableSemanticSegmentationMatteTypes.filter { $0 == .hair }
        let raw = !output.availableRawPhotoPixelFormatTypes.isEmpty
        DispatchQueue.main.async {
            self.rawAvailable = raw
            self.livePhotoAvailable = self.output.isLivePhotoCaptureSupported
            self.flashAvailable = camera.hasFlash
            self.aperture = Double(camera.lensAperture)
            self.apertureStops = camera.activeFormat.maxLensAperture > camera.activeFormat.minLensAperture
                ? [1.4, 1.8, 2.8, 4.0].filter { $0 >= Double(camera.activeFormat.minLensAperture) && $0 <= Double(camera.activeFormat.maxLensAperture) } : []
            self.shutter = CMTimeGetSeconds(camera.exposureDuration)
            self.shutterBounds = max(0.00001, CMTimeGetSeconds(camera.activeFormat.minExposureDuration))...max(0.00002, CMTimeGetSeconds(camera.activeFormat.maxExposureDuration))
            self.exposureBiasBounds = Double(camera.minExposureTargetBias)...Double(camera.maxExposureTargetBias)
            if !self.livePhotoAvailable { self.useLivePhoto = false }
            self.depthAvailable = self.output.isDepthDataDeliverySupported
            self.portraitAvailable = self.output.isPortraitEffectsMatteDeliveryEnabled
            self.hairAvailable = self.output.enabledSemanticSegmentationMatteTypes.contains(.hair)
            self.isoBounds = Double(camera.activeFormat.minISO)...Double(camera.activeFormat.maxISO)
            self.iso = Double(camera.iso)
            self.selectedLens = camera.uniqueID
            self.focusAvailable = camera.isFocusModeSupported(.locked) && camera.isLockingFocusWithCustomLensPositionSupported
            self.exposureAvailable = camera.isExposureModeSupported(.custom)
            self.whiteBalanceAvailable = camera.isWhiteBalanceModeSupported(.locked) && camera.isLockingWhiteBalanceWithCustomDeviceGainsSupported
            self.zoomLimit = min(Double(camera.activeFormat.videoMaxZoomFactor), 10)
            self.zoom = 1
            if !raw { self.useRAW = false }
        }
    }

    func selectLens(_ id: String) {
        queue.async {
            guard let camera = self.lenses.first(where: { $0.uniqueID == id }), let old = self.input else { return }
            self.session.beginConfiguration()
            do {
                let new = try AVCaptureDeviceInput(device: camera)
                self.session.removeInput(old)
                if self.session.canAddInput(new) { self.session.addInput(new); self.input = new; self.device = camera; self.configureOutput(camera) }
                else { self.session.addInput(old) }
            } catch { self.publishError(error.localizedDescription) }
            self.session.commitConfiguration()
        }
    }

    func applyControls() {
        let values = (iso, shutter, focus, kelvin, bias, tint, zoom, aperture)
        let modes = (manual && !autoExposure, manual && !autoFocus, manual && !autoWhiteBalance, !autoAperture)
        queue.async {
            guard let d = self.device else { return }
            do {
                try d.lockForConfiguration(); defer { d.unlockForConfiguration() }
                d.videoZoomFactor = min(max(CGFloat(values.6), 1), d.activeFormat.videoMaxZoomFactor)
                let duration = CMTime(seconds: min(max(values.1, CMTimeGetSeconds(d.activeFormat.minExposureDuration)), CMTimeGetSeconds(d.activeFormat.maxExposureDuration)), preferredTimescale: 1_000_000_000)
                let iso = min(max(Float(values.0), d.activeFormat.minISO), d.activeFormat.maxISO)
                if modes.0 || modes.3 {
                    let aperture = modes.3 ? min(max(Float(values.7), d.activeFormat.minLensAperture), d.activeFormat.maxLensAperture) : AVCaptureDevice.currentLensAperture
                    let requestedDuration = modes.0 ? duration : AVCaptureDevice.autoExposureDuration
                    let requestedISO = modes.0 ? iso : AVCaptureDevice.autoISO
                    if d.activeFormat.supportsExposureModeCustom(lensAperture: aperture, duration: requestedDuration, iso: requestedISO) {
                        d.setExposureModeCustom(lensAperture: aperture, duration: requestedDuration, iso: requestedISO, completionHandler: nil)
                    } else if modes.0 && d.isExposureModeSupported(.custom) {
                        d.setExposureModeCustom(duration: duration, iso: iso, completionHandler: nil)
                    }
                } else if d.isExposureModeSupported(.continuousAutoExposure) { d.exposureMode = .continuousAutoExposure }
                if !modes.0 { d.setExposureTargetBias(min(max(Float(values.4), d.minExposureTargetBias), d.maxExposureTargetBias), completionHandler: nil) }
                if modes.1 && d.isLockingFocusWithCustomLensPositionSupported && d.isFocusModeSupported(.locked) {
                    d.setFocusModeLocked(lensPosition: min(max(Float(values.2), 0), 1), completionHandler: nil)
                } else if d.isFocusModeSupported(.continuousAutoFocus) { d.focusMode = .continuousAutoFocus }
                if modes.2 && d.isLockingWhiteBalanceWithCustomDeviceGainsSupported && d.isWhiteBalanceModeSupported(.locked) {
                    var gains = d.deviceWhiteBalanceGains(for: AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: Float(values.3), tint: Float(values.5)))
                    gains.redGain = min(max(gains.redGain, 1), d.maxWhiteBalanceGain)
                    gains.greenGain = min(max(gains.greenGain, 1), d.maxWhiteBalanceGain)
                    gains.blueGain = min(max(gains.blueGain, 1), d.maxWhiteBalanceGain)
                    d.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
                } else if d.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { d.whiteBalanceMode = .continuousAutoWhiteBalance }
            } catch { self.publishError(error.localizedDescription) }
        }
    }

    func switchCamera() {
        guard let current = lenses.first(where: { $0.uniqueID == selectedLens }),
              let next = lenses.first(where: { $0.position != current.position }) else { return }
        selectLens(next.uniqueID)
    }

    func focusAt(_ point: CGPoint) {
        guard !manual || autoFocus else { return }
        queue.async {
            guard let d = self.device else { return }
            do {
                try d.lockForConfiguration(); defer { d.unlockForConfiguration() }
                if d.isFocusPointOfInterestSupported, d.isFocusModeSupported(.autoFocus) { d.focusPointOfInterest = point; d.focusMode = .autoFocus }
                if d.isExposurePointOfInterestSupported, d.isExposureModeSupported(.autoExpose) { d.exposurePointOfInterest = point; d.exposureMode = .autoExpose }
            } catch { self.publishError(error.localizedDescription) }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        guard timestamp - lastMeterTime > 0.15, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastMeterTime = timestamp
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let bytes = base.assumingMemoryBound(to: UInt8.self), row = CVPixelBufferGetBytesPerRow(buffer)
        var bins = [Double](repeating: 0, count: 48)
        for y in stride(from: 0, to: CVPixelBufferGetHeight(buffer), by: 12) {
            for x in stride(from: 0, to: CVPixelBufferGetWidth(buffer), by: 12) {
                let offset = y * row + x * 4
                let luminance = 0.2126 * Double(bytes[offset + 2]) + 0.7152 * Double(bytes[offset + 1]) + 0.0722 * Double(bytes[offset])
                bins[min(47, Int(luminance / 256 * 48))] += 1
            }
        }
        let peak = max(bins.max() ?? 1, 1), normalized = bins.map { $0 / peak }
        DispatchQueue.main.async { self.histogram = normalized }
    }

    func capture() {
        guard ready, !capturing else { return }
        capturing = true
        let options = (useRAW, useDepth, flash, useLivePhoto, useHEIF)
        queue.async {
            self.pendingRaw = nil; self.pendingProcessed = nil; self.pendingDepth = nil; self.pendingLiveMovie = nil
            let codec: AVVideoCodecType = options.4 && self.output.availablePhotoCodecTypes.contains(.hevc) ? .hevc : .jpeg
            self.pendingPortrait = nil; self.pendingHair = nil
            let settings: AVCapturePhotoSettings
            if options.0, let format = self.output.availableRawPhotoPixelFormatTypes.first(where: { AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) }) ?? self.output.availableRawPhotoPixelFormatTypes.first {
                settings = AVCapturePhotoSettings(rawPixelFormatType: format, processedFormat: [AVVideoCodecKey: codec])
            } else { settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: codec]) }
            if options.3 && !options.0 && self.output.isLivePhotoCaptureEnabled {
                settings.livePhotoMovieFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
            }
            settings.photoQualityPrioritization = .quality
            // RAW/depth simultaneous delivery varies by device; request depth for processed mode.
            settings.isDepthDataDeliveryEnabled = !options.0 && options.1 && self.output.isDepthDataDeliveryEnabled
            settings.embedsDepthDataInPhoto = settings.isDepthDataDeliveryEnabled
            settings.isPortraitEffectsMatteDeliveryEnabled = settings.isDepthDataDeliveryEnabled && self.output.isPortraitEffectsMatteDeliveryEnabled
            settings.embedsPortraitEffectsMatteInPhoto = settings.isPortraitEffectsMatteDeliveryEnabled
            // RAW combinations vary by camera; request semantic mattes only for processed depth capture.
            settings.enabledSemanticSegmentationMatteTypes = !options.0 ? self.output.enabledSemanticSegmentationMatteTypes : []
            settings.embedsSemanticSegmentationMattesInPhoto = !settings.enabledSemanticSegmentationMatteTypes.isEmpty
            if self.output.supportedFlashModes.contains(.on) { settings.flashMode = options.2 ? .on : .off }
            if let connection = self.output.connection(with: .video), connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error { publishError(error.localizedDescription); return }
        if photo.isRawPhoto { pendingRaw = photo.fileDataRepresentation() }
        else {
            pendingProcessed = photo.fileDataRepresentation(); pendingDepth = photo.depthData
            pendingPortrait = photo.portraitEffectsMatte
            pendingHair = photo.semanticSegmentationMatte(for: .hair)
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL, duration: CMTime, photoDisplayTime: CMTime, resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if error == nil { pendingLiveMovie = outputFileURL }
        else { try? FileManager.default.removeItem(at: outputFileURL); publishError(error!.localizedDescription) }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        let result = pendingProcessed.map { CaptureResult(processed: $0, raw: pendingRaw, depth: pendingDepth, portrait: pendingPortrait, hair: pendingHair, liveMovie: pendingLiveMovie) }
        DispatchQueue.main.async {
            self.capturing = false
            if let error { self.error = error.localizedDescription }
            else if let result { self.onCapture?(result) }
            else { self.error = "The camera did not deliver a photograph." }
        }
    }
    private func publishError(_ text: String) { DispatchQueue.main.async { self.error = text } }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var onFocus: ((CGPoint) -> Void)?
    class Preview: UIView {
        var onFocus: ((CGPoint) -> Void)?
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        override init(frame: CGRect) {
            super.init(frame: frame)
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        @objc func tapped(_ gesture: UITapGestureRecognizer) { onFocus?(previewLayer.captureDevicePointConverted(fromLayerPoint: gesture.location(in: self))) }
        override func layoutSubviews() {
            super.layoutSubviews()
            if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        }
    }
    func makeUIView(context: Context) -> Preview { let view = Preview(); view.previewLayer.session = session; view.previewLayer.videoGravity = .resizeAspectFill; view.onFocus = onFocus; return view }
    func updateUIView(_ view: Preview, context: Context) { view.onFocus = onFocus }
}

import Foundation
import Network
import CoreGraphics
import Combine
import ImageIO
import AppKit
import ScreenCaptureKit
import AVFoundation
import CoreAudio
import AudioToolbox

enum CaptureMode: String, CaseIterable {
    case fullDisplay = "Full Display"
    case singleWindow = "Single Window"
}

struct WindowInfo: Identifiable, Hashable {
    let id: CGWindowID
    let title: String
    let ownerName: String
    let window: SCWindow
}

struct DisplayInfo: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    let width: Int
    let height: Int
    let display: SCDisplay
}

struct AudioSettings {
    let sampleRate: Double = 44100.0
    let channels: UInt32 = 2
    let bitDepth: UInt32 = 16
    let bufferSize: UInt32 = 1024
    
    var bytesPerFrame: UInt32 {
        return channels * (bitDepth / 8)
    }
    
    var bufferSizeBytes: UInt32 {
        return bufferSize * bytesPerFrame
    }
}

class MirroringServer: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var connectedClients = 0
    @Published var currentFPS: Int = 60
    @Published var currentQuality: Float = 0.4
    @Published var networkLatency: TimeInterval = 0
    @Published var estimatedNetworkLatency: TimeInterval = 0
    
    @Published var captureMode: CaptureMode = .fullDisplay
    @Published var availableWindows: [WindowInfo] = []
    @Published var selectedWindow: WindowInfo?
    @Published var isLoadingWindows = false
    @Published var availableDisplays: [DisplayInfo] = []
    @Published var selectedDisplay: DisplayInfo?
    @Published var isLoadingDisplays = false
    
    @Published var isAudioEnabled = true
    @Published var audioQuality: Float = 0.8
    @Published var audioLatency: TimeInterval = 0
    @Published var totalDataSent: Int64 = 0
    @Published var totalFramesSent: Int64 = 0
    @Published var averageQuality: Float = 0.5

    @Published var isBackgroundMode = false
    @Published var backgroundStartTime: Date?
    @Published var totalConnectionTime: TimeInterval = 0
    @Published var sessionCount = 0
    
    @Published var isAudioCapturing = false
    
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var screenCaptureTimer: Timer?
    private var netService: NetService?
    private var frameCounter = 0
    private var captureQueue = DispatchQueue(label: "ScreenCapture", qos: .userInteractive)
    private var encodeQueue = DispatchQueue(label: "ImageEncode", qos: .userInteractive)
    private var isCapturing = false
    
    private var audioEngine: AVAudioEngine?
    private var audioPlayerNode: AVAudioPlayerNode?
    private var audioMixer: AVAudioMixerNode?
    private var audioSettings = AudioSettings()
    private var audioQueue = DispatchQueue(label: "AudioCapture", qos: .userInteractive)
    private var audioBuffer = CircularBuffer<Float>(capacity: 8192)
    private var lastAudioSendTime: TimeInterval = 0
    private var audioFrameCounter = 0
    
    private var frameStartTime: CFTimeInterval = 0
    private var averageFrameTime: TimeInterval = 0
    private var frameTimes: [TimeInterval] = []
    private var lastQualityAdjustment: Date = Date()
    private var droppedFrames = 0
    
    private var targetFrameTime: TimeInterval = 1.0/60.0
    private var maxFrameTime: TimeInterval = 1.0/45.0
    private var minQuality: Float = 0.2
    private var maxQuality: Float = 0.6
    
    private var lastFrameSentTime: [ObjectIdentifier: TimeInterval] = [:]
    private var roundTripTimes: [TimeInterval] = []
    private var networkLatencyThreshold: TimeInterval = 0.040
    
    private var memoryWarningCount = 0
    private weak var memoryTimer: Timer?
    private var performanceMetrics = PerformanceMetrics()
    private var backgroundMonitorTimer: Timer?
    private var persistentServer = true // Always keep server running
    private var performanceTimer: Timer?
    
    private var userRequestedFPS: Int = 15
    private var userRequestedQuality: Float = 0.25
    private var isUserSettingsActive = false

    override init() {
        super.init()
        startMemoryMonitoring()
        requestAudioPermissions()
        startListening()
        startBackgroundMonitoring()
        setupPersistentOperation()
    }
    
    deinit {
        cleanup()
    }
    
    private func cleanup() {
        connections.forEach { $0.cancel() }
        connections.removeAll()
        stopScreenCapture()
        stopAudioCapture()
        memoryTimer?.invalidate()
        memoryTimer = nil
        backgroundMonitorTimer?.invalidate()
        backgroundMonitorTimer = nil
        autoreleasepool { }
    }
    
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        audioMixer = audioEngine?.mainMixerNode
        
        guard let engine = audioEngine,
              let _ = audioMixer else {
            print("❌ Failed to create audio components")
            return
        }
        
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        // Create format for our audio settings
        let _ = AVAudioFormat(standardFormatWithSampleRate: audioSettings.sampleRate, channels: AVAudioChannelCount(audioSettings.channels))!
        
        // Install tap on input node to capture system audio
        inputNode.installTap(onBus: 0, bufferSize: audioSettings.bufferSize, format: inputFormat) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer, time: time)
        }
        
        print("🎵 Audio engine configured for system capture: \(audioSettings.sampleRate)Hz, \(audioSettings.channels) channels")
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        guard isAudioCapturing, !connections.isEmpty else { return }
        
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }
        
        var interleavedData: [Float] = []
        
        // Handle different audio formats from input
        if let floatChannelData = buffer.floatChannelData {
            let inputChannelCount = Int(buffer.format.channelCount)
            let outputChannelCount = Int(audioSettings.channels)
            
            interleavedData.reserveCapacity(frameCount * outputChannelCount)
            
            for frame in 0..<frameCount {
                for channel in 0..<outputChannelCount {
                    // If input has fewer channels than output, duplicate mono to stereo
                    let inputChannel = min(channel, inputChannelCount - 1)
                    let sample = inputChannel < inputChannelCount ? floatChannelData[inputChannel][frame] : 0.0
                    interleavedData.append(sample)
                }
            }
        } else if let int16ChannelData = buffer.int16ChannelData {
            // Convert from Int16 to Float if needed
            let inputChannelCount = Int(buffer.format.channelCount)
            let outputChannelCount = Int(audioSettings.channels)
            
            interleavedData.reserveCapacity(frameCount * outputChannelCount)
            
            for frame in 0..<frameCount {
                for channel in 0..<outputChannelCount {
                    let inputChannel = min(channel, inputChannelCount - 1)
                    let sample = inputChannel < inputChannelCount ? Float(int16ChannelData[inputChannel][frame]) / 32767.0 : 0.0
                    interleavedData.append(sample)
                }
            }
        } else {
            // Fallback: create silence if we can't process the format
            interleavedData = Array(repeating: 0.0, count: frameCount * Int(audioSettings.channels))
        }
        
        // Apply audio quality scaling
        if audioQuality < 1.0 {
            let scaleFactor = audioQuality
            interleavedData = interleavedData.map { $0 * scaleFactor }
        }
        
        audioBuffer.write(interleavedData)
        
        let currentTime = CFAbsoluteTimeGetCurrent()
        if currentTime - lastAudioSendTime > 0.02 { // Send every 20ms
            sendAudioData()
            lastAudioSendTime = currentTime
        }
    }
    
    private func sendAudioData() {
        let samplesToSend = min(Int(audioSettings.bufferSize), audioBuffer.availableToRead)
        guard samplesToSend > 0 else { return }
        
        let audioSamples = audioBuffer.read(samplesToSend)
        
        // Apply dynamic range compression for better audio quality
        let compressedSamples = audioSamples.map { sample in
            let normalizedSample = max(-1.0, min(1.0, sample))
            // Apply soft compression
            let compressed = normalizedSample * audioQuality
            return Int16(max(-32767, min(32767, compressed * 32767)))
        }
        
        // Convert to Data
        let audioData = compressedSamples.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
        
        // Create detailed audio packet info
        let audioPacketInfo = [
            "type": "audio",
            "sampleRate": audioSettings.sampleRate,
            "channels": audioSettings.channels,
            "samples": samplesToSend / Int(audioSettings.channels), // Actual frame count
            "timestamp": CFAbsoluteTimeGetCurrent(),
            "quality": audioQuality,
            "format": "int16"
        ] as [String: Any]
        
        guard let infoData = try? JSONSerialization.data(withJSONObject: audioPacketInfo) else {
            print("❌ Failed to serialize audio packet info")
            return
        }
        
        let infoLength = UInt16(infoData.count)
        let audioLength = UInt32(audioData.count)
        
        // Create audio packet with proper header
        let packet = Data([0xFA]) +
                    withUnsafeBytes(of: infoLength.bigEndian) { Data($0) } +
                    withUnsafeBytes(of: audioLength.bigEndian) { Data($0) } +
                    infoData + audioData
        
        // Send to all connected clients
        for connection in connections {
            connection.send(content: packet, completion: .contentProcessed { error in
                if let error = error {
                    print("❌ Audio send error: \(error)")
                } else if self.audioFrameCounter % 200 == 0 {
                    print("🎵 Audio packet sent: \(audioData.count) bytes, \(samplesToSend / Int(self.audioSettings.channels)) frames")
                }
            })
        }
        
        audioFrameCounter += 1
    }
    
    private func startAudioCapture() {
        guard let engine = audioEngine, isAudioEnabled else { return }
        
        do {
            // Stop engine if it's already running
            if engine.isRunning {
                engine.stop()
            }
            
            // Prepare and start the engine
            try engine.start()
            isAudioCapturing = true
            print("🎵 Started system audio capture")
            
            // Log audio input details
            let inputNode = engine.inputNode
            let inputFormat = inputNode.inputFormat(forBus: 0)
            print("🎵 Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) channels")
            
        } catch {
            print("❌ Failed to start audio engine: \(error)")
            
            // Try alternative approach for system audio
            setupAlternativeAudioCapture()
        }
    }
    
    private func setupAlternativeAudioCapture() {
        print("🎵 Attempting alternative audio capture method...")
        
        // Create a separate audio engine for output capture
        let outputEngine = AVAudioEngine()
        let outputMixer = outputEngine.mainMixerNode
        
        // Try to tap the output mixer
        do {
            let outputFormat = AVAudioFormat(standardFormatWithSampleRate: audioSettings.sampleRate, channels: AVAudioChannelCount(audioSettings.channels))!
            
            outputMixer.installTap(onBus: 0, bufferSize: audioSettings.bufferSize, format: outputFormat) { [weak self] buffer, time in
                self?.processAudioBuffer(buffer, time: time)
            }
            
            try outputEngine.start()
            
            // Replace the main audio engine
            audioEngine?.stop()
            audioEngine = outputEngine
            audioMixer = outputMixer
            
            isAudioCapturing = true
            print("🎵 Alternative audio capture started successfully")
            
        } catch {
            print("❌ Alternative audio capture also failed: \(error)")
            print("🎵 Audio capture disabled - system audio may not be available")
            isAudioCapturing = false
        }
    }
    
    private func stopAudioCapture() {
        isAudioCapturing = false
        audioEngine?.stop()
        audioBuffer.clear()
        print("🔇 Stopped audio capture")
    }
    
    private func startMemoryMonitoring() {
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.checkMemoryUsage()
        }
    }
    
    private func checkMemoryUsage() {
        let memoryInfo = getMemoryInfo()
        performanceMetrics.updateMemoryUsage(memoryInfo.memoryMB)
        
        if memoryInfo.memoryMB > 400 {
            memoryWarningCount += 1
            print("⚠️ Memory usage: \(memoryInfo.memoryMB)MB (Warning level \(memoryWarningCount))")
            
            autoreleasepool {
                // Force garbage collection
            }
            
            if memoryWarningCount > 2 {
                DispatchQueue.main.async {
                    if self.currentQuality > 0.2 {
                        self.currentQuality = max(0.2, self.currentQuality - 0.05)
                        print("🔥 Memory management: Reduced quality to \(String(format: "%.2f", self.currentQuality))")
                    } else if self.currentFPS > 15 {
                        self.currentFPS = max(15, self.currentFPS - 2)
                        self.updateScreenCaptureTimer()
                        print("🔥 Memory management: Reduced FPS to \(self.currentFPS)")
                    }
                    else if self.audioQuality > 0.4 {
                        self.audioQuality = max(0.4, self.audioQuality - 0.1)
                        print("🔥 Memory management: Reduced audio quality to \(String(format: "%.2f", self.audioQuality))")
                    }
                }
            }
        } else {
            if memoryWarningCount > 0 {
                memoryWarningCount = max(0, memoryWarningCount - 1)
            }
        }
        
        if frameCounter % 100 == 0 {
            print("📊 Performance: \(performanceMetrics.summary)")
        }
    }
    
    private func getMemoryInfo() -> MemoryInfo {
        var memoryInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let result: kern_return_t = withUnsafeMutablePointer(to: &memoryInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let memoryMB = memoryInfo.resident_size / (1024 * 1024)
            return MemoryInfo(memoryMB: Int(memoryMB), isValid: true)
        } else {
            return MemoryInfo(memoryMB: 0, isValid: false)
        }
    }
    
    private func requestAudioPermissions() {
        #if os(macOS)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            print("🎵 Audio capture already authorized")
            setupAudioEngine()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        print("🎵 Audio capture permission granted")
                        self?.setupAudioEngine()
                    } else {
                        print("❌ Audio capture permission denied")
                        self?.isAudioEnabled = false
                    }
                }
            }
        case .denied, .restricted:
            print("❌ Audio capture permission denied or restricted")
            isAudioEnabled = false
        @unknown default:
            print("❌ Unknown audio capture authorization status")
            isAudioEnabled = false
        }
        #endif
    }
    
    func startListening() {
        do {
            let parameters = NWParameters.tcp
            parameters.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
            if let tcpOptions = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
                tcpOptions.noDelay = true
                tcpOptions.connectionTimeout = 2
                tcpOptions.maximumSegmentSize = 1400
            }
            
            parameters.serviceClass = .responsiveData
            parameters.requiredInterfaceType = .wifi
            
            listener = try NWListener(using: parameters, on: 8080)
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            
            listener?.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        self?.startBonjourAdvertising()
                        let mode = self?.isBackgroundMode == true ? "background" : "foreground"
                        print("🚀 Persistent server ready in \(mode) mode - always available for iPhone connections")
                    case .failed(let error):
                        print("❌ Listener failed: \(error) - attempting restart...")
                        self?.isRunning = false
                        
                        // Auto-restart server after failure
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                            if self?.persistentServer == true {
                                print("🔄 Auto-restarting server...")
                                self?.startListening()
                            }
                        }
                    default:
                        break
                    }
                }
            }
            
            listener?.start(queue: .main)
        } catch {
            print("❌ Failed to start listener: \(error)")
            
            // Retry after delay for persistent operation
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                if self.persistentServer {
                    print("🔄 Retrying server start...")
                    self.startListening()
                }
            }
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        let connectionID = ObjectIdentifier(connection)
        lastFrameSentTime[connectionID] = 0
        sessionCount += 1

        if let tcpOptions = connection.parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcpOptions.noDelay = true
            tcpOptions.maximumSegmentSize = 1400
        }

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let strongSelf = self, let strongConnection = connection else { return }
            let currentConnectionID = ObjectIdentifier(strongConnection)

            DispatchQueue.main.async {
                switch state {
                case .ready:
                    strongSelf.connections.append(strongConnection)
                    strongSelf.connectedClients = strongSelf.connections.count
                    print("📱 iPhone connected! Session #\(strongSelf.sessionCount)")
                    print("🔄 Server mode: \(strongSelf.isBackgroundMode ? "Background" : "Foreground")")
                    
                    strongSelf.startScreenCapture()
                    strongSelf.startAudioCapture()
                    
                    // Resume full performance monitoring when client connects
                    if strongSelf.isBackgroundMode {
                        strongSelf.startPerformanceMonitoring()
                    }
                    
                    strongSelf.receiveClientFeedback(on: strongConnection)
                case .cancelled, .failed:
                    strongSelf.connections.removeAll { $0 === strongConnection }
                    strongSelf.lastFrameSentTime.removeValue(forKey: currentConnectionID)
                    strongSelf.connectedClients = strongSelf.connections.count
                    print("📱 iPhone disconnected! Remaining clients: \(strongSelf.connectedClients)")
                    
                    if strongSelf.connectedClients == 0 {
                        strongSelf.stopScreenCapture()
                        strongSelf.stopAudioCapture()
                        print("🔄 No active connections - server idle but ready")
                        
                        // Return to background monitoring if in background mode
                        if strongSelf.isBackgroundMode {
                            strongSelf.enableBackgroundMode()
                        }
                    }
                default:
                    break
                }
            }
        }
        
        connection.start(queue: self.captureQueue)
    }
    
    private func startScreenCapture() {
        currentFPS = 30
        currentQuality = 0.5
        userRequestedFPS = 30
        userRequestedQuality = 0.5
        isUserSettingsActive = false
        updateScreenCaptureTimer()
        print("🎬 Started screen capture with default Balanced settings: \(currentFPS) FPS, \(Int(currentQuality * 100))% quality")
        print("⏳ Waiting for iPhone to send streaming preferences...")
    }
    
    private func updateScreenCaptureTimer() {
        screenCaptureTimer?.invalidate()
        screenCaptureTimer = nil
        
        targetFrameTime = 1.0 / Double(currentFPS)
        
        screenCaptureTimer = Timer.scheduledTimer(withTimeInterval: targetFrameTime, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task {
                await self.captureAndSendScreen()
            }
        }
    }
    
    private func stopScreenCapture() {
        screenCaptureTimer?.invalidate()
        screenCaptureTimer = nil
        isCapturing = false
        
        autoreleasepool {
            frameTimes.removeAll()
            roundTripTimes.removeAll()
        }
        
        print("⏹️ Screen capture stopped - no active iPhone connections")
    }
    
    func stop() {
        cleanup()
    }
    
    private func startPerformanceMonitoring() {
        performanceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.adjustQualityBasedOnPerformance()
        }
        
        RunLoop.main.add(performanceTimer!, forMode: .common)
    }
    
    private func captureAndSendScreen() async {
        guard !connections.isEmpty else {
            print("⏹️ No active connections, skipping capture")
            return
        }
        
        guard !isCapturing else {
            droppedFrames += 1
            return
        }
        
        isCapturing = true
        let captureStartTime = CFAbsoluteTimeGetCurrent()
        
        defer {
            isCapturing = false
            recordFrameTime(startTime: captureStartTime)
        }
        
        let memoryPressure = ProcessInfo.processInfo.thermalState
        if memoryPressure == .critical || memoryPressure == .serious || memoryWarningCount > 2 {
            print("⚠️ High memory pressure or warnings, skipping frame")
            droppedFrames += 1
            return
        }
        
        let captureTask = Task {
            return await captureScreen()
        }
        
        do {
            let screenCGImage = try await withTimeout(seconds: 0.5) {
                await captureTask.value
            }
            
            guard let cgImage = screenCGImage else {
                let fallbackData = createFallbackPattern()
                await sendFrameData(fallbackData, captureStartTime: captureStartTime)
                return
            }
            
            let imageData = autoreleasepool {
                return MirroringServer.convertCGImageToJPEG(cgImage, quality: currentQuality) ?? Data()
            }
            
            await sendFrameData(imageData, captureStartTime: captureStartTime)
        } catch {
            print("⏰ Screen capture timeout, using fallback")
            let fallbackData = createFallbackPattern()
            await sendFrameData(fallbackData, captureStartTime: captureStartTime)
        }
    }
    
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                return try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            
            guard let result = try await group.next() else {
                throw TimeoutError()
            }
            
            group.cancelAll()
            return result
        }
    }
    
    private struct TimeoutError: Error {}

    private func captureScreen() async -> CGImage? {
        do {
            let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            
            let filter: SCContentFilter
            let configuration = SCStreamConfiguration()
            
            switch captureMode {
            case .fullDisplay:
                let targetDisplay: SCDisplay
                if let selectedDisplay = selectedDisplay {
                    if let display = availableContent.displays.first(where: { $0.displayID == selectedDisplay.id }) {
                        targetDisplay = display
                    } else {
                        print("Selected display not found, using primary")
                        guard let display = availableContent.displays.first else { return nil }
                        targetDisplay = display
                    }
                } else {
                    guard let display = availableContent.displays.first else { return nil }
                    targetDisplay = display
                }
                
                filter = SCContentFilter(display: targetDisplay, excludingWindows: [])
                
                let scaleFactor = calculateOptimalScaleFactor()
                configuration.width = Int(CGFloat(targetDisplay.width) * scaleFactor)
                configuration.height = Int(CGFloat(targetDisplay.height) * scaleFactor)
                
            case .singleWindow:
                guard let selectedWindow = selectedWindow else {
                    print("No window selected for single window capture")
                    return nil
                }
                
                guard let currentWindow = availableContent.windows.first(where: { $0.windowID == selectedWindow.id }) else {
                    print("Selected window not found in current content")
                    return nil
                }
                
                filter = SCContentFilter(desktopIndependentWindow: currentWindow)
                
                let scaleFactor = calculateOptimalScaleFactor()
                configuration.width = Int(CGFloat(currentWindow.frame.width) * scaleFactor)
                configuration.height = Int(CGFloat(currentWindow.frame.height) * scaleFactor)
            }
            
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: Int32(max(currentFPS, 10)))
            configuration.queueDepth = 2
            configuration.showsCursor = true
            configuration.scalesToFit = false
            configuration.colorSpaceName = CGColorSpace.sRGB
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            
            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            return cgImage
            
        } catch {
            print("Screen capture failed: \(error)")
            performanceMetrics.recordCaptureError()
            return nil
        }
    }
    
    static private func convertCGImageToJPEG(_ cgImage: CGImage, quality: Float) -> Data? {
        return autoreleasepool {
            let mutableData = CFDataCreateMutable(nil, 0)!
            guard let destination = CGImageDestinationCreateWithData(mutableData, "public.jpeg" as CFString, 1, nil) else {
                print("Error: Could not create mutable data for JPEG")
                return nil
            }
            
            let options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: quality
            ]
            
            CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
            
            guard CGImageDestinationFinalize(destination) else {
                print("Error: Could not finalize JPEG destination")
                return nil
            }
            
            return mutableData as Data
        }
    }
    
    private func sendFrameData(_ imageData: Data, captureStartTime: CFTimeInterval) async {
        let status = [
            "fps": currentFPS,
            "quality": Int(currentQuality * 100),
            "latency": Int(estimatedNetworkLatency * 1000),
            "audioEnabled": isAudioEnabled,
            "audioLatency": Int(audioLatency * 1000)
        ] as [String : Any]

        guard let statusJsonData = try? JSONSerialization.data(withJSONObject: status, options: []) else {
            return
        }

        let statusLength = UInt8(statusJsonData.count)
        let imageLengthData = withUnsafeBytes(of: UInt32(imageData.count).bigEndian) { Data($0) }
        let statusLengthData = Data([statusLength])
        let frameData = imageLengthData + statusLengthData + statusJsonData + imageData
        
        let sendTime = CFAbsoluteTimeGetCurrent()

        for connection in connections {
            let connectionID = ObjectIdentifier(connection)
            lastFrameSentTime[connectionID] = sendTime
            
            connection.send(content: frameData, completion: .contentProcessed { error in
                if let error = error {
                    print("Send error: \(error)")
                }
            })
        }
        
        totalDataSent += Int64(imageData.count)
        totalFramesSent += 1
        averageQuality = (averageQuality * Float(totalFramesSent - 1) + currentQuality) / Float(totalFramesSent)
        
        if frameCounter % 30 == 0 {
            print("📤 Sent frame: \(imageData.count) bytes, processing time: \(String(format: "%.1f", (sendTime - captureStartTime) * 1000))ms")
        }
        frameCounter += 1
    }
    
    private func createFallbackPattern() -> Data {
        let size = CGSize(width: 640, height: 480)
        let rect = CGRect(origin: .zero, size: size)
        
        guard let imageRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return Data() }
        
        let context = NSGraphicsContext(bitmapImageRep: imageRep)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        
        NSColor.systemBlue.setFill()
        rect.fill()
        
        let text = "Mac Screen Mirroring\nFPS: \(currentFPS) | Quality: \(Int(currentQuality * 100))%\nAudio: \(isAudioEnabled ? "ON" : "OFF")"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 24),
            .foregroundColor: NSColor.white
        ]
        
        let textSize = text.size(withAttributes: attributes)
        let textRect = CGRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)
        
        NSGraphicsContext.restoreGraphicsState()
        
        return MirroringServer.convertCGImageToJPEG(imageRep.cgImage!, quality: currentQuality) ?? Data()
    }
    
    private func recordFrameTime(startTime: CFTimeInterval) {
        let frameProcessingTime = CFAbsoluteTimeGetCurrent() - startTime
        frameTimes.append(frameProcessingTime)
        
        if frameTimes.count > 60 {
            frameTimes.removeFirst()
        }
        
        if !frameTimes.isEmpty {
            averageFrameTime = frameTimes.reduce(0, +) / Double(frameTimes.count)
        }
    }
    
    private func adjustQualityBasedOnPerformance() {
        let now = Date()
        guard now.timeIntervalSince(lastQualityAdjustment) > 3.0 else { return }
        
        DispatchQueue.main.async {
            if (self.averageFrameTime > self.maxFrameTime * 1.5 || self.droppedFrames > 5) && self.estimatedNetworkLatency > 0.060 {
                if self.currentQuality > self.minQuality + 0.1 {
                    self.currentQuality = max(self.minQuality, self.currentQuality - 0.05)
                    print("⚡ Auto-reducing quality to \(String(format: "%.2f", self.currentQuality)) for severe performance issues")
                } else if self.currentFPS > max(10, self.userRequestedFPS - 8) {
                    self.currentFPS = max(max(10, self.userRequestedFPS - 8), self.currentFPS - 1)
                    self.updateScreenCaptureTimer()
                    print("⚡ Auto-reducing FPS to \(self.currentFPS) for severe performance issues")
                }
                else if self.audioQuality > 0.4 {
                    self.audioQuality = max(0.4, self.audioQuality - 0.1)
                    print("⚡ Auto-reducing audio quality to \(String(format: "%.2f", self.audioQuality)) for performance")
                }
            }
            else if self.averageFrameTime < self.targetFrameTime * 0.5 && self.droppedFrames == 0 && self.estimatedNetworkLatency < self.networkLatencyThreshold * 0.6 {
                if self.isUserSettingsActive {
                    if self.currentFPS < self.userRequestedFPS {
                        self.currentFPS = min(self.userRequestedFPS, self.currentFPS + 1)
                        self.updateScreenCaptureTimer()
                        print("⚡ Restoring FPS to \(self.currentFPS) (target: \(self.userRequestedFPS))")
                    }
                    if self.currentQuality < self.userRequestedQuality {
                        self.currentQuality = min(self.userRequestedQuality, self.currentQuality + 0.03)
                        print("⚡ Restoring quality to \(String(format: "%.2f", self.currentQuality)) (target: \(String(format: "%.2f", self.userRequestedQuality)))")
                    }
                    if self.audioQuality < 0.8 {
                        self.audioQuality = min(0.8, self.audioQuality + 0.05)
                        print("⚡ Restoring audio quality to \(String(format: "%.2f", self.audioQuality))")
                    }
                }
            }

            self.droppedFrames = 0
            self.lastQualityAdjustment = now
        }
    }
    
    private func calculateOptimalScaleFactor() -> CGFloat {
        if averageFrameTime == 0 { return 0.5 }

        let performanceRatio = targetFrameTime / averageFrameTime
        let latencyFactor = min(1.0, networkLatencyThreshold / max(estimatedNetworkLatency, 0.001))
        
        let combinedFactor = (performanceRatio + latencyFactor) / 2.0
        
        if combinedFactor < 0.6 {
            return 0.3
        } else if combinedFactor < 0.8 {
            return 0.4
        } else if combinedFactor > 1.3 {
            return 0.7
        }
        return 0.5
    }

    private func receiveClientFeedback(on connection: NWConnection) {
        connection.receiveMessage { [weak self, weak connection] (content, context, isComplete, error) in
            guard let strongSelf = self, let strongConnection = connection else { return }
            let currentConnectionID = ObjectIdentifier(strongConnection)

            if let data = content, !data.isEmpty {
                if data.first == 0xFF && data.count > 1 {
                    let settingsData = data.dropFirst()
                    strongSelf.processSettingsCommand(settingsData)
                } else if data.first == 0xFE && data.count > 1 {
                    let requestData = data.dropFirst()
                    strongSelf.processWindowsDisplaysRequest(requestData, connection: strongConnection)
                } else if let sendTime = strongSelf.lastFrameSentTime[currentConnectionID], sendTime > 0 {
                     let rtt = CFAbsoluteTimeGetCurrent() - sendTime
                     strongSelf.roundTripTimes.append(rtt)
                     strongSelf.lastFrameSentTime[currentConnectionID] = 0
                     
                     DispatchQueue.main.async {
                         strongSelf.updateEstimatedLatency()
                     }
                }
            }
            if let error = error {
                print("Client feedback receive error: \(error)")
                return
            }
            if isComplete {
                print("Client feedback stream completed for connection \(String(describing: strongConnection))")
                return
            }
            strongSelf.receiveClientFeedback(on: strongConnection)
        }
    }

    private func processSettingsCommand(_ settingsData: Data) {
        do {
            if let json = try JSONSerialization.jsonObject(with: settingsData, options: []) as? [String: Any] {
                print("📱 Received settings from iPhone: \(json)")
                
                DispatchQueue.main.async {
                    if let audioEnabled = json["audioEnabled"] as? Bool {
                        self.isAudioEnabled = audioEnabled
                        if audioEnabled {
                            self.startAudioCapture()
                        } else {
                            self.stopAudioCapture()
                        }
                        print("🎵 Audio streaming: \(audioEnabled ? "enabled" : "disabled")")
                    }
                    
                    if let audioQuality = json["audioQuality"] as? Float {
                        self.audioQuality = max(0.1, min(1.0, audioQuality))
                        print("🎵 Audio quality set to: \(String(format: "%.2f", self.audioQuality))")
                    }
                    
                    if let streamingMode = json["streamingMode"] as? String {
                        print("📱 iPhone requested streaming mode: \(streamingMode)")
                        
                        self.isUserSettingsActive = true
                        
                        switch streamingMode {
                        case "Performance":
                            self.userRequestedFPS = 45
                            self.userRequestedQuality = 0.3
                            self.currentFPS = 45
                            self.currentQuality = 0.3
                            self.audioQuality = 0.6
                            self.maxFrameTime = 1.0/30.0
                            print("🚀 Applied Performance mode: 45 FPS, 30% quality, 60% audio")
                        case "Balanced":
                            self.userRequestedFPS = 30
                            self.userRequestedQuality = 0.5
                            self.currentFPS = 30
                            self.currentQuality = 0.5
                            self.audioQuality = 0.8
                            self.maxFrameTime = 1.0/25.0
                            print("⚖️ Applied Balanced mode: 30 FPS, 50% quality, 80% audio")
                        case "Fidelity":
                            self.userRequestedFPS = 20
                            self.userRequestedQuality = 0.7
                            self.currentFPS = 20
                            self.currentQuality = 0.7
                            self.audioQuality = 1.0
                            self.maxFrameTime = 1.0/15.0
                            print("🎨 Applied Fidelity mode: 20 FPS, 70% quality, 100% audio")
                        default:
                            break
                        }
                        
                        self.updateScreenCaptureTimer()
                        
                        if let preferredFPS = json["preferredFPS"] as? Int {
                            self.userRequestedFPS = min(45, max(10, preferredFPS))
                            self.currentFPS = self.userRequestedFPS
                            self.updateScreenCaptureTimer()
                            print("📱 Override FPS to \(self.currentFPS)")
                        }
                        
                        if let preferredQuality = json["preferredQuality"] as? Int {
                            self.userRequestedQuality = Float(preferredQuality) / 100.0
                            self.userRequestedQuality = min(0.8, max(0.2, self.userRequestedQuality))
                            self.currentQuality = self.userRequestedQuality
                            print("📱 Override quality to \(String(format: "%.2f", self.currentQuality))")
                        }
                    }
                    
                    if let captureSource = json["captureSource"] as? String {
                        if captureSource == "Full Display" {
                            self.captureMode = .fullDisplay
                            print("📱 Switched to Full Display mode")
                        } else if captureSource == "Single Window" {
                            self.captureMode = .singleWindow
                            print("📱 Switched to Single Window mode")
                        }
                    }
                    
                    if let windowId = json["selectedWindowId"] as? UInt32, windowId > 0 {
                        if let window = self.availableWindows.first(where: { $0.id == windowId }) {
                            self.selectedWindow = window
                            self.captureMode = .singleWindow
                            print("📱 Selected window: \(window.title) by \(window.ownerName)")
                        }
                    }
                    
                    if let displayId = json["selectedDisplayId"] as? UInt32, displayId > 0 {
                        if let display = self.availableDisplays.first(where: { $0.id == displayId }) {
                            self.selectedDisplay = display
                            self.captureMode = .fullDisplay
                            print("📱 Selected display: \(display.name)")
                        }
                    }
                }
            }
        } catch {
            print("Failed to parse settings JSON: \(error)")
        }
    }
    
    private func processWindowsDisplaysRequest(_ requestData: Data, connection: NWConnection) {
        do {
            if let json = try JSONSerialization.jsonObject(with: requestData, options: []) as? [String: Any],
               json["action"] as? String == "getWindowsDisplays" {
                
                Task { [weak self] in
                    guard let self = self else { return }
                    
                    await self.loadAvailableWindows()
                    await self.loadAvailableDisplays()
                    
                    await MainActor.run { [weak self, connection] in
                        self?.sendWindowsDisplaysResponse(to: connection)
                    }
                }
            }
        } catch {
            print("Failed to parse windows/displays request: \(error)")
        }
    }
    
    private func sendWindowsDisplaysResponse(to connection: NWConnection) {
        let windowsData = availableWindows.map { window in
            [
                "id": window.id,
                "title": window.title,
                "ownerName": window.ownerName
            ] as [String: Any]
        }
        
        let displaysData = availableDisplays.map { display in
            [
                "id": display.id,
                "name": display.name,
                "width": display.width,
                "height": display.height
            ] as [String: Any]
        }
        
        let response = [
            "windows": windowsData,
            "displays": displaysData
        ] as [String: Any]
        
        guard let responseData = try? JSONSerialization.data(withJSONObject: response) else { return }
        
        let lengthData = withUnsafeBytes(of: UInt32(responseData.count).bigEndian) { Data($0) }
        let fullResponse = Data([0xFD]) + lengthData + responseData
        
        connection.send(content: fullResponse, completion: .contentProcessed { error in
            if let error = error {
                print("Failed to send windows/displays response: \(error)")
            } else {
                print("📤 Sent \(windowsData.count) windows and \(displaysData.count) displays to iPhone")
            }
        })
    }
    
    private func updateEstimatedLatency() {
        if !roundTripTimes.isEmpty {
            estimatedNetworkLatency = roundTripTimes.reduce(0, +) / Double(roundTripTimes.count)
            audioLatency = estimatedNetworkLatency
            if roundTripTimes.count > 30 {
                roundTripTimes.removeFirst(roundTripTimes.count - 30)
            }
        }
    }

    @MainActor
    func loadAvailableWindows() async {
        isLoadingWindows = true
        
        do {
            let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            
            let windowInfos = availableContent.windows
                .filter { window in
                    return window.frame.width > 100 &&
                           window.frame.height > 100 &&
                           !(window.title?.isEmpty ?? true) &&
                           window.owningApplication?.applicationName != "Window Server"
                }
                .map { window in
                    WindowInfo(
                        id: window.windowID,
                        title: window.title ?? "Untitled",
                        ownerName: window.owningApplication?.applicationName ?? "Unknown",
                        window: window
                    )
                }
                .sorted { $0.ownerName < $1.ownerName }
            
            self.availableWindows = windowInfos
            self.isLoadingWindows = false
            print("Loaded \(windowInfos.count) windows")
        } catch {
            print("Failed to load windows: \(error)")
            self.isLoadingWindows = false
        }
    }

    @MainActor
    func loadAvailableDisplays() async {
        isLoadingDisplays = true
        
        do {
            let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            
            let displayInfos = availableContent.displays.enumerated().map { index, display in
                DisplayInfo(
                    id: display.displayID,
                    name: "Display \(index + 1) (\(display.width)×\(display.height))",
                    width: display.width,
                    height: display.height,
                    display: display
                )
            }
            
            self.availableDisplays = displayInfos
            
            if self.selectedDisplay == nil, let firstDisplay = displayInfos.first {
                self.selectedDisplay = firstDisplay
            }
            
            self.isLoadingDisplays = false
            print("Loaded \(displayInfos.count) displays")
        } catch {
            print("Failed to load displays: \(error)")
            self.isLoadingDisplays = false
        }
    }
    
    private func startBackgroundMonitoring() {
        backgroundMonitorTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.logBackgroundStatus()
        }
    }
    
    private func logBackgroundStatus() {
        if isBackgroundMode {
            let uptimeHours = backgroundStartTime.map { Date().timeIntervalSince($0) / 3600 } ?? 0
            print("🌙 Background server uptime: \(String(format: "%.1f", uptimeHours)) hours, \(connectedClients) clients")
        }
    }
    
    func enableBackgroundMode() {
        isBackgroundMode = true
        backgroundStartTime = Date()
        
        // Reduce resource usage in background
        if connectedClients == 0 {
            // Keep server running but reduce performance monitoring frequency
            performanceTimer?.invalidate()
            performanceTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
                self?.updateBackgroundMetrics()
            }
        }
        
        print("🌙 Background mode enabled - server remains active")
    }
    
    func disableBackgroundMode() {
        isBackgroundMode = false
        backgroundStartTime = nil
        
        // Resume normal performance monitoring
        performanceTimer?.invalidate()
        performanceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.adjustQualityBasedOnPerformance()
        }
        
        print("☀️ Returning to foreground mode")
    }
    
    private func updateBackgroundMetrics() {
        // Light background monitoring
        let memoryInfo = getMemoryInfo()
        if memoryInfo.memoryMB > 200 {
            print("🌙 Background memory usage: \(memoryInfo.memoryMB)MB")
        }
        
        // Keep network service alive
        if !isRunning && persistentServer {
            print("🔄 Restarting server in background...")
            startListening()
        }
    }
    
    private func setupPersistentOperation() {
        // Prevent app termination when all windows are closed
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("🔄 App terminating - cleaning up server...")
            self?.cleanup()
        }
        
        // Handle window close events
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let window = notification.object as? NSWindow,
               window.isMainWindow {
                print("🔄 Main window closing - server continues in background")
                self?.enableBackgroundMode()
            }
        }
        
        print("🔄 Persistent server operation configured")
    }
    
    private func startBonjourAdvertising() {
        netService?.stop()
        
        let serviceName = isBackgroundMode ? "Mac Screen (Background)" : "Mac Screen"
        netService = NetService(domain: "local.", type: "_macmirror._tcp.", name: serviceName, port: 8080)
        netService?.delegate = self
        netService?.publish()
        
        print("📡 Bonjour advertising: \(serviceName) - always discoverable")
    }
    
    func getServerStatistics() -> [String: Any] {
        let uptime = backgroundStartTime.map { Date().timeIntervalSince($0) } ?? 0
        
        return [
            "isBackgroundMode": isBackgroundMode,
            "uptimeHours": uptime / 3600,
            "totalSessions": sessionCount,
            "currentConnections": connectedClients,
            "serverStatus": isRunning ? "Running" : "Stopped",
            "memoryUsage": getMemoryInfo().memoryMB,
            "audioCapture": isAudioCapturing ? "Active" : "Inactive"
        ]
    }
}

extension MirroringServer: NetServiceDelegate {
    func netServiceDidPublish(_ sender: NetService) {
        print("✅ Bonjour service published successfully: \(sender.name).\(sender.type)\(sender.domain)")
    }
    
    func netService(_ sender: NetService, didNotPublish errorDict: [String : NSNumber]) {
        print("❌ Failed to publish Bonjour service: \(errorDict)")
    }
    
    func netServiceDidStop(_ sender: NetService) {
        print("🛑 Bonjour service stopped: \(sender.name)")
    }
}

struct PerformanceMetrics {
    private var captureErrors = 0
    private var totalFrames = 0
    private var memoryPeakMB = 0
    private var memoryCurrentMB = 0
    
    mutating func updateMemoryUsage(_ memoryMB: Int) {
        memoryCurrentMB = memoryMB
        memoryPeakMB = max(memoryPeakMB, memoryMB)
    }
    
    mutating func recordCaptureError() {
        captureErrors += 1
    }
    
    mutating func recordFrame() {
        totalFrames += 1
    }
    
    var summary: String {
        let errorRate = totalFrames > 0 ? Double(captureErrors) / Double(totalFrames) * 100 : 0
        return "Memory: \(memoryCurrentMB)MB (peak: \(memoryPeakMB)MB), Errors: \(String(format: "%.1f", errorRate))%"
    }
}

struct MemoryInfo {
    let memoryMB: Int
    let isValid: Bool
}

class CircularBuffer<T> {
    private var buffer: [T?]
    private var writeIndex = 0
    private var readIndex = 0
    private var count = 0
    private let capacity: Int
    
    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = Array(repeating: nil, count: capacity)
    }
    
    func write(_ elements: [T]) {
        for element in elements {
            buffer[writeIndex] = element
            writeIndex = (writeIndex + 1) % capacity
            
            if count < capacity {
                count += 1
            } else {
                readIndex = (readIndex + 1) % capacity
            }
        }
    }
    
    func read(_ count: Int) -> [T] {
        let elementsToRead = min(count, self.count)
        var result: [T] = []
        
        for _ in 0..<elementsToRead {
            if let element = buffer[readIndex] {
                result.append(element)
            }
            readIndex = (readIndex + 1) % capacity
            self.count -= 1
        }
        
        return result
    }
    
    var availableToRead: Int {
        return count
    }
    
    func clear() {
        writeIndex = 0
        readIndex = 0
        count = 0
        // Clear the buffer
        for i in 0..<capacity {
            buffer[i] = nil
        }
    }
}

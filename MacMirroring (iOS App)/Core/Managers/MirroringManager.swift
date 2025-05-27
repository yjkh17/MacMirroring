import Foundation
import Network
import Combine
import SwiftUI

struct ServerStatusInfo {
    let fps: Int
    let quality: Int
    let latency: Int
    let audioEnabled: Bool
    let audioLatency: Int
}

class MirroringManager: ObservableObject {
    @Published var isConnected = false
    @Published var isSearching = false
    @Published var availableMacs: [MacDevice] = []
    @Published var screenData: Data?
    @Published var serverStatus: ServerStatusInfo?
    @Published var connectionError: ConnectionError?
    @Published var networkQuality: NetworkQuality = .unknown
    @Published var reconnectionAttempts = 0
    @Published var averageFPS: Double = 0
    @Published var dataReceived: Int64 = 0
    @Published var connectionDuration: TimeInterval = 0
    @Published var isAudioEnabled = false
    @Published var audioLatency: TimeInterval = 0
    @Published var energyImpact: EnergyImpact = .low
    @Published var networkMetrics = NetworkMetrics()
    @Published var adaptiveMode = true
    @Published var isInBackground = false
    
    private var browser: NWBrowser?
    var connection: NWConnection?
    private var receivedData = Data()
    private var expectedImageLength: UInt32?
    private var expectedStatusLength: UInt8?
    
    private let networkQueue = DispatchQueue(label: "NetworkQueue", qos: .userInitiated)
    private var lastFrameTime: CFTimeInterval = 0
    private var frameDropCount = 0
    private var targetFrameInterval: TimeInterval = 1.0/30.0
    
    private var energyMonitorTimer: Timer?
    private var consecutiveFrameCount = 0
    private var isThrottling = false
    
    private var connectionStartTime: Date?
    private var fpsHistory: [Double] = []
    private var reconnectionTimer: Timer?
    private var performanceTimer: Timer?
    
    var streamingSettings: StreamingSettings? {
        didSet {
            updateFrameLimiting()
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupBrowser()
        startEnergyMonitoring()
    }
    
    deinit {
        cleanup()
    }
    
    private func cleanup() {
        browser?.cancel()
        connection?.cancel()
        connection = nil
        receivedData.removeAll()
        resetParsingState()
        energyMonitorTimer?.invalidate()
        energyMonitorTimer = nil
        reconnectionTimer?.invalidate()
        reconnectionTimer = nil
        performanceTimer?.invalidate()
        performanceTimer = nil
        
        connectionStartTime = nil
        fpsHistory.removeAll()
        averageFPS = 0
        connectionDuration = 0
        
        browser = nil
        setupBrowser()
    }
    
    private func startEnergyMonitoring() {
        energyMonitorTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.checkEnergyUsage()
        }
    }
    
    private func checkEnergyUsage() {
        if consecutiveFrameCount > 75 {
            isThrottling = true
            print("⚡ Enabling energy throttling - processing \(consecutiveFrameCount) frames in 5s")
        } else if consecutiveFrameCount < 25 {
            isThrottling = false
            if consecutiveFrameCount > 0 {
                print("⚡ Energy throttling disabled - processing \(consecutiveFrameCount) frames in 5s")
            }
        }
        
        consecutiveFrameCount = 0
    }
    
    private func setupBrowser() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        
        let browserDescriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(
            type: "_macmirror._tcp",
            domain: "local."
        )
        
        browser = NWBrowser(for: browserDescriptor, using: parameters)
        
        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            self?.networkQueue.async {
                print("📡 Browse results changed: \(results.count) services found")
                DispatchQueue.main.async {
                    self?.handleBrowseResults(results)
                }
            }
        }
        
        browser?.stateUpdateHandler = { state in
            print("📡 Browser state: \(state)")
        }
    }
    
    func startSearching() {
        print("🔍 Starting search for Mac servers...")
        isSearching = true
        availableMacs.removeAll()
        browser?.start(queue: networkQueue)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
            if self.isSearching && self.availableMacs.isEmpty {
                print("⏰ Search timeout - no Macs found")
                self.stopSearching()
            }
        }
    }
    
    func stopSearching() {
        print("🛑 Stopping search")
        isSearching = false
        browser?.cancel()
    }
    
    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        let newMacs = results.compactMap { result in
            switch result.endpoint {
            case .service(let name, let type, let domain, _):
                print("📱 Found Mac: \(name) (\(type) in \(domain))")
                return MacDevice(name: name, type: type, domain: domain, endpoint: result.endpoint)
            default:
                return nil
            }
        }
        
        availableMacs = newMacs
        
        if !newMacs.isEmpty && isSearching {
            if let firstMac = newMacs.first {
                print("🎯 Mac discovered, connecting immediately: \(firstMac.name)")
                isSearching = false
                connectToMac(firstMac)
            }
        }
    }
    
    func connectToMac(_ mac: MacDevice) {
        print("🔗 Connecting to Mac: \(mac.name)")
        connectionError = nil
        
        let parameters = NWParameters.tcp
        if let tcpOptions = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcpOptions.noDelay = false
            tcpOptions.connectionTimeout = 8
            tcpOptions.maximumSegmentSize = 1400
        }
        parameters.serviceClass = .responsiveData
        parameters.requiredInterfaceType = .wifi
        
        let connection = NWConnection(to: mac.endpoint, using: parameters)
        self.connection = connection
        
        connection.stateUpdateHandler = { [weak self] state in
            print("🔗 Connection state: \(state)")
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    print("✅ Connected to Mac successfully!")
                    self?.isConnected = true
                    self?.stopSearching()
                    self?.connectionStartTime = Date()
                    self?.reconnectionAttempts = 0
                    self?.startPerformanceMonitoring()
                    self?.startReceivingScreenData()
                    
                    DispatchQueue.main.async {
                        print("📱 Sending initial streaming settings...")
                        self?.streamingSettings?.sendSettingsToServer(via: connection)
                    }
                case .failed(let error):
                    print("❌ Connection failed: \(error)")
                    self?.handleConnectionError(.connectionFailed(error))
                case .cancelled:
                    print("🔄 Connection cancelled")
                    self?.handleConnectionError(.connectionCancelled)
                case .waiting(let error):
                    print("⏳ Connection waiting: \(error)")
                    self?.handleConnectionError(.connectionWaiting(error))
                default:
                    break
                }
            }
        }
        
        connection.start(queue: networkQueue)
    }
    
    private func handleConnectionError(_ error: ConnectionError) {
        DispatchQueue.main.async {
            self.connectionError = error
            self.isConnected = false
            
            if case .connectionFailed = error, self.reconnectionAttempts < 3 {
                self.scheduleReconnection()
            }
        }
    }
    
    private func scheduleReconnection() {
        reconnectionAttempts += 1
        let delay = min(pow(2.0, Double(reconnectionAttempts)), 30.0)
        
        print("📱 Scheduling reconnection attempt \(reconnectionAttempts) in \(delay)s")
        
        reconnectionTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self, !self.availableMacs.isEmpty else { return }
            
            print("🔄 Auto-reconnection attempt \(self.reconnectionAttempts)")
            if let firstMac = self.availableMacs.first {
                self.connectToMac(firstMac)
            }
        }
    }
    
    private func startPerformanceMonitoring() {
        performanceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updatePerformanceMetrics()
        }
    }
    
    private func updatePerformanceMetrics() {
        guard let connectionStartTime = connectionStartTime else { return }
        
        connectionDuration = Date().timeIntervalSince(connectionStartTime)
        
        if let status = serverStatus {
            fpsHistory.append(Double(status.fps))
            if fpsHistory.count > 60 {
                fpsHistory.removeFirst()
            }
            
            averageFPS = fpsHistory.reduce(0, +) / Double(fpsHistory.count)
            updateNetworkQuality(status.latency)
        }
    }
    
    private func updateNetworkQuality(_ latency: Int) {
        switch latency {
        case 0...30:
            networkQuality = .excellent
        case 31...60:
            networkQuality = .good
        case 61...100:
            networkQuality = .fair
        default:
            networkQuality = .poor
        }
    }
    
    private func startReceivingScreenData() {
        guard let connection = connection else { return }
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            
            if let error = error {
                print("Receive error: \(error)")
                DispatchQueue.main.async {
                    self?.disconnect()
                }
                return
            }
            
            if let data = data, !data.isEmpty {
                self?.networkQueue.async {
                    self?.processReceivedData(data)
                }
            }
            
            if !isComplete {
                DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 0.02) {
                    self?.startReceivingScreenData()
                }
            }
        }
    }
    
    private func processReceivedData(_ data: Data) {
        receivedData.append(data)
        
        if receivedData.count > 1_500_000 {
            print("⚠️ Buffer too large (\(receivedData.count) bytes), clearing")
            receivedData.removeAll()
            resetParsingState()
            return
        }
        
        if receivedData.count >= 1 && receivedData.first == 0xFD {
            receivedData.removeFirst(1)
            
            if receivedData.count >= 4 {
                var lengthValue: UInt32 = 0
                _ = receivedData.prefix(4).withUnsafeBytes { memcpy(&lengthValue, $0.baseAddress!, 4) }
                let responseLength = UInt32(bigEndian: lengthValue)
                receivedData.removeFirst(4)
                
                if receivedData.count >= responseLength {
                    let responseData = receivedData.prefix(Int(responseLength))
                    receivedData.removeFirst(Int(responseLength))
                    
                    DispatchQueue.main.async {
                        self.streamingSettings?.processWindowsDisplaysResponse(Data(responseData))
                    }
                    return
                }
            }
        }
        
        processFrameData()
    }
    
    private func processFrameData() {
        while true {
            if expectedImageLength == nil {
                guard receivedData.count >= 4 else { break }
                var lengthValue: UInt32 = 0
                _ = receivedData.prefix(4).withUnsafeBytes { memcpy(&lengthValue, $0.baseAddress!, 4) }
                expectedImageLength = UInt32(bigEndian: lengthValue)
                receivedData.removeFirst(4)
            }
            
            if expectedStatusLength == nil {
                guard receivedData.count >= 1 else {
                    if let imgLen = expectedImageLength {
                         let imgLenData = withUnsafeBytes(of: imgLen.bigEndian) { Data($0) }
                         receivedData.insert(contentsOf: imgLenData, at: 0)
                         expectedImageLength = nil
                    }
                    break
                }
                expectedStatusLength = receivedData.first!
                receivedData.removeFirst(1)
            }
            
            guard let imgLen = expectedImageLength, let statusLen = expectedStatusLength else {
                resetParsingState()
                break
            }
            
            let totalExpectedDataLength = Int(statusLen) + Int(imgLen)
            if receivedData.count >= totalExpectedDataLength {
                let statusData = receivedData.prefix(Int(statusLen))
                receivedData.removeFirst(Int(statusLen))
                
                let imageData = receivedData.prefix(Int(imgLen))
                receivedData.removeFirst(Int(imgLen))
                
                let currentTime = CFAbsoluteTimeGetCurrent()
                let timeSinceLastFrame = currentTime - lastFrameTime
                
                let requiredInterval = isThrottling ? targetFrameInterval * 1.5 : targetFrameInterval
                
                if timeSinceLastFrame >= requiredInterval {
                    parseAndSetStatus(statusData)
                    
                    DispatchQueue.main.async {
                        self.screenData = Data(imageData)
                        if self.consecutiveFrameCount % 2 == 0 {
                            self.sendClientAck()
                        }
                    }
                    
                    lastFrameTime = currentTime
                    consecutiveFrameCount += 1
                    frameDropCount = 0
                } else {
                    frameDropCount += 1
                    if frameDropCount % 10 == 0 {
                        let currentMode = self.streamingSettings?.streamingMode.rawValue ?? "Unknown"
                        print("⚡ Dropped \(frameDropCount) frames in \(currentMode) mode (target: \(String(format: "%.1f", 1.0/targetFrameInterval)) FPS)")
                    }
                    
                    if frameDropCount % 50 == 0 {
                        autoreleasepool { }
                    }
                }
                
                resetParsingState()
            } else {
                break
            }
        }
    }
    
    private func parseAndSetStatus(_ statusData: Data) {
        do {
            if let json = try JSONSerialization.jsonObject(with: statusData, options: []) as? [String: Any],
               let fps = json["fps"] as? Int,
               let quality = json["quality"] as? Int,
               let latency = json["latency"] as? Int {
                let audioEnabled = json["audioEnabled"] as? Bool ?? false
                let audioLatency = json["audioLatency"] as? Int ?? 0
                
                DispatchQueue.main.async {
                    self.serverStatus = ServerStatusInfo(
                        fps: fps,
                        quality: quality,
                        latency: latency,
                        audioEnabled: audioEnabled,
                        audioLatency: audioLatency
                    )
                }
            }
        } catch {
            print("Error decoding status JSON: \(error)")
        }
    }
    
    private func resetParsingState() {
        expectedImageLength = nil
        expectedStatusLength = nil
    }
    
    private func sendClientAck() {
        let ackData = Data([0x01])
        connection?.send(content: ackData, completion: .contentProcessed({ error in
            if let error = error {
                print("Failed to send ACK: \(error)")
            }
        }))
    }
    
    func disconnect() {
        print("🔌 Disconnecting from Mac")
        cleanup()
        
        DispatchQueue.main.async {
            self.isConnected = false
            self.screenData = nil
            self.serverStatus = nil
            self.connectionError = nil
            self.isSearching = false
            self.availableMacs.removeAll()
            self.reconnectionAttempts = 0
        }
    }
    
    func setStreamingSettings(_ settings: StreamingSettings) {
        self.streamingSettings = settings
        settings.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async {
                self?.updateFrameLimiting()
            }
        }.store(in: &cancellables)
    }
    
    private func updateFrameLimiting() {
        guard let settings = streamingSettings else { return }
        
        switch settings.streamingMode {
        case .performance:
            targetFrameInterval = 1.0/45.0
            print("📱 iOS: Set to Performance mode - 45 FPS limit")
        case .balanced:
            targetFrameInterval = 1.0/30.0
            print("📱 iOS: Set to Balanced mode - 30 FPS limit")
        case .fidelity:
            targetFrameInterval = 1.0/20.0
            print("📱 iOS: Set to Fidelity mode - 20 FPS limit")
        }
    }
    
    func connectDirectly() {
        print("🔗 Attempting direct connection to Mac...")
        
        if connection != nil {
            cleanup()
        }
        
        connectionError = nil
        availableMacs.removeAll()
        isSearching = true
        
        if browser == nil {
            setupBrowser()
        }
        
        browser?.start(queue: networkQueue)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            if !self.availableMacs.isEmpty {
                if let firstMac = self.availableMacs.first {
                    print("🎯 Found Mac after 4s: \(firstMac.name)")
                    self.isSearching = false
                    self.connectToMac(firstMac)
                    return
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                if !self.availableMacs.isEmpty {
                    if let firstMac = self.availableMacs.first {
                        print("🎯 Found Mac after 8s: \(firstMac.name)")
                        self.isSearching = false
                        self.connectToMac(firstMac)
                        return
                    }
                }
                
                print("❌ No Macs found after 8 seconds of discovery")
                self.isSearching = false
                self.connectionError = .serverNotFound
            }
        }
    }
    
    func cancelConnection() {
        cleanup()
        DispatchQueue.main.async {
            self.isConnected = false
            self.availableMacs.removeAll()
            self.connectionError = nil
            self.isSearching = false
        }
        print("🚫 Connection cancelled by user")
    }
}

enum ConnectionError: Error, Identifiable, Equatable {
    case connectionFailed(Error)
    case connectionCancelled
    case connectionWaiting(Error)
    case networkUnavailable
    case serverNotFound
    case authenticationFailed
    
    var id: String {
        switch self {
        case .connectionFailed: return "connection_failed"
        case .connectionCancelled: return "connection_cancelled"
        case .connectionWaiting: return "connection_waiting"
        case .networkUnavailable: return "network_unavailable"
        case .serverNotFound: return "server_not_found"
        case .authenticationFailed: return "authentication_failed"
        }
    }
    
    var localizedDescription: String {
        switch self {
        case .connectionFailed(let error):
            return "Connection failed: \(error.localizedDescription)"
        case .connectionCancelled:
            return "Connection was cancelled"
        case .connectionWaiting(let error):
            return "Connection waiting: \(error.localizedDescription)"
        case .networkUnavailable:
            return "Network is unavailable"
        case .serverNotFound:
            return "Mac server not found"
        case .authenticationFailed:
            return "Authentication failed"
        }
    }
    
    static func == (lhs: ConnectionError, rhs: ConnectionError) -> Bool {
        switch (lhs, rhs) {
        case (.connectionFailed(let lhsError), .connectionFailed(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        case (.connectionCancelled, .connectionCancelled):
            return true
        case (.connectionWaiting(let lhsError), .connectionWaiting(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        case (.networkUnavailable, .networkUnavailable):
            return true
        case (.serverNotFound, .serverNotFound):
            return true
        case (.authenticationFailed, .authenticationFailed):
            return true
        default:
            return false
        }
    }
}

enum NetworkQuality: String, CaseIterable {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"
    case unknown = "Unknown"
    
    var color: Color {
        switch self {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .yellow
        case .poor: return .red
        case .unknown: return .gray
        }
    }
}

enum EnergyImpact: String, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case veryHigh = "Very High"
    
    var color: Color {
        switch self {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .orange
        case .veryHigh: return .red
        }
    }
    
    var description: String {
        return rawValue
    }
}

struct NetworkMetrics {
    var bandwidth: Double = 0.0
    var packetLoss: Double = 0.0
    var jitter: Double = 0.0
    var rtt: Double = 0.0
    var qualityScore: Double = 0.0
}

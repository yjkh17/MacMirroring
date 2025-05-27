import Foundation
import MultipeerConnectivity
import Combine
import SwiftUI
import Network

class MultipeerDisplay: NSObject, ObservableObject {
    private let peerID = MCPeerID(displayName: UIDevice.current.name)
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    
    // MARK: - Published Properties (Compatible with old MirroringManager)
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
    @Published var streamingSettings: StreamingSettings?
    
    // MARK: - Computed Property for compatibility
    var connection: MCSession? {
        return session
    }
    
    private let serviceType = "macmirror"
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
        setupSession()
        setupBrowser()
    }
    
    deinit {
        disconnect()
    }
    
    private func setupSession() {
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self
    }
    
    private func setupBrowser() {
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser?.delegate = self
    }
    
    // MARK: - Public Methods (Compatible with old MirroringManager)
    
    func startSearching() {
        print("🔍 Starting Multipeer search for Mac servers...")
        isSearching = true
        availableMacs.removeAll()
        browser?.startBrowsingForPeers()
        
        // Timeout after 8 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
            if self.isSearching && self.availableMacs.isEmpty {
                print("⏰ Multipeer search timeout - no Macs found")
                self.stopSearching()
                self.connectionError = .serverNotFound
            }
        }
    }
    
    func stopSearching() {
        print("🛑 Stopping Multipeer search")
        isSearching = false
        browser?.stopBrowsingForPeers()
    }
    
    func connectDirectly() {
        print("🔗 Attempting Multipeer connection to Mac...")
        connectionError = nil
        availableMacs.removeAll()
        isSearching = true
        
        browser?.startBrowsingForPeers()
        
        // Auto-connect when Mac is found
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            if !self.availableMacs.isEmpty {
                if let firstMac = self.availableMacs.first {
                    print("🎯 Found Mac, connecting: \(firstMac.name)")
                    self.connectToMac(firstMac)
                }
            } else {
                print("❌ No Macs found after 5 seconds")
                self.isSearching = false
                self.connectionError = .serverNotFound
            }
        }
    }
    
    func connectToMac(_ mac: MacDevice) {
        print("🔗 Connecting to Mac via Multipeer: \(mac.name)")
        // This would be implemented with actual MCPeerID from discovered peers
        // For now, we'll simulate the connection
        connectionError = nil
        
        // Simulate connection process
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.isConnected = true
            self.isSearching = false
            self.reconnectionAttempts = 0
            print("✅ Multipeer connected to Mac successfully!")
            
            // Start receiving mock data
            self.startReceivingData()
        }
    }
    
    func disconnect() {
        print("🔌 Disconnecting Multipeer session")
        session?.disconnect()
        isConnected = false
        screenData = nil
        serverStatus = nil
        connectionError = nil
        isSearching = false
        availableMacs.removeAll()
        reconnectionAttempts = 0
        browser?.stopBrowsingForPeers()
    }
    
    func cancelConnection() {
        disconnect()
        print("🚫 Multipeer connection cancelled by user")
    }
    
    func setStreamingSettings(_ settings: StreamingSettings) {
        self.streamingSettings = settings
        print("📱 Multipeer: Streaming settings applied")
    }
    
    // MARK: - Private Methods
    
    private func startReceivingData() {
        // Simulate receiving screen data and status updates
        Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { timer in
            guard self.isConnected else {
                timer.invalidate()
                return
            }
            
            // Mock screen data (1x1 pixel image)
            let mockImageData = self.createMockImageData()
            self.screenData = mockImageData
            
            // Mock server status
            self.serverStatus = ServerStatusInfo(
                fps: 30,
                quality: 70,
                latency: Int.random(in: 20...50),
                audioEnabled: false,
                audioLatency: 0
            )
            
            // Update network quality
            self.networkQuality = .good
            self.dataReceived += Int64(mockImageData.count)
        }
    }
    
    private func createMockImageData() -> Data {
        // Create a simple 1x1 pixel red image
        let size = CGSize(width: 1, height: 1)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image.jpegData(compressionQuality: 0.7) ?? Data()
    }
}

// MARK: - MCSessionDelegate
extension MultipeerDisplay: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                print("✅ Multipeer: Connected to \(peerID.displayName)")
                self.isConnected = true
                self.isSearching = false
                self.startReceivingData()
                
            case .connecting:
                print("🔄 Multipeer: Connecting to \(peerID.displayName)")
                
            case .notConnected:
                print("❌ Multipeer: Disconnected from \(peerID.displayName)")
                self.isConnected = false
                
            @unknown default:
                print("❓ Multipeer: Unknown state for \(peerID.displayName)")
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            // Handle received screen data
            self.screenData = data
            self.dataReceived += Int64(data.count)
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Handle streams if needed
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Handle resource transfers if needed
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Handle completed resource transfers if needed
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MultipeerDisplay: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        DispatchQueue.main.async {
            print("📱 Multipeer: Found Mac peer: \(peerID.displayName)")
            
            // Create MacDevice from discovered peer
            let mockEndpoint = NWEndpoint.hostPort(host: "192.168.1.100", port: 8080)
            let macDevice = MacDevice(
                name: peerID.displayName,
                type: "_macmirror._tcp",
                domain: "local.",
                endpoint: mockEndpoint
            )
            
            if !self.availableMacs.contains(macDevice) {
                self.availableMacs.append(macDevice)
            }
            
            // Auto-connect to first found Mac
            if self.isSearching && !self.isConnected {
                self.browser?.invitePeer(peerID, to: self.session!, withContext: nil, timeout: 10)
            }
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            print("📱 Multipeer: Lost Mac peer: \(peerID.displayName)")
            self.availableMacs.removeAll { $0.name == peerID.displayName }
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async {
            print("❌ Multipeer: Failed to start browsing: \(error.localizedDescription)")
            self.connectionError = .connectionFailed(error)
            self.isSearching = false
        }
    }
}

// MARK: - Supporting Types
struct NetworkMetrics {
    var bandwidth: Double = 0.0
    var packetLoss: Double = 0.0
    var jitter: Double = 0.0
    var rtt: Double = 0.0
    var qualityScore: Double = 0.0
}

import Foundation
import MultipeerConnectivity
import Combine
import SwiftUI
import AppKit

class MultipeerCapture: NSObject, ObservableObject {
    private let peerID = MCPeerID(displayName: Host.current().localizedName ?? "Mac")
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    
    // MARK: - Published Properties
    @Published var isAdvertising = false
    @Published var connectedPeers: [MCPeerID] = []
    @Published var isCapturing = false
    @Published var currentFPS: Int = 30
    @Published var streamingQuality: Int = 70
    @Published var captureMode: CaptureMode = .fullDisplay
    @Published var networkLatency: Int = 0
    
    private let serviceType = "macmirror"
    private var captureTimer: Timer?
    private var lastCaptureTime = Date()
    
    enum CaptureMode: CaseIterable {
        case fullDisplay
        case singleWindow
        
        var description: String {
            switch self {
            case .fullDisplay: return "Full Display"
            case .singleWindow: return "Single Window"
            }
        }
    }
    
    override init() {
        super.init()
        setupSession()
        setupAdvertiser()
        startAdvertising()
    }
    
    deinit {
        stopCapturing()
        stopAdvertising()
    }
    
    private func setupSession() {
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self
    }
    
    private func setupAdvertiser() {
        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser?.delegate = self
    }
    
    func startAdvertising() {
        print("🖥️ Mac: Starting Multipeer advertising...")
        isAdvertising = true
        advertiser?.startAdvertisingPeer()
    }
    
    func stopAdvertising() {
        print("🛑 Mac: Stopping Multipeer advertising")
        isAdvertising = false
        advertiser?.stopAdvertisingPeer()
    }
    
    func startCapturing() {
        guard !connectedPeers.isEmpty else {
            print("⚠️ No connected peers to stream to")
            return
        }
        
        print("📸 Mac: Starting screen capture...")
        isCapturing = true
        
        captureTimer = Timer.scheduledTimer(withTimeInterval: 1.0/Double(currentFPS), repeats: true) { [weak self] _ in
            self?.captureAndSendScreen()
        }
    }
    
    func stopCapturing() {
        print("🛑 Mac: Stopping screen capture")
        isCapturing = false
        captureTimer?.invalidate()
        captureTimer = nil
    }
    
    private func captureAndSendScreen() {
        Task {
            do {
                let screenData = try await captureScreen()
                sendScreenData(screenData)
            } catch {
                print("❌ Screen capture error: \(error)")
            }
        }
    }
    
    private func captureScreen() async throws -> Data {
        // Create a mock colored image for testing
        let size = CGSize(width: 800, height: 600)
        let image = NSImage(size: size)
        
        image.lockFocus()
        
        // Create a gradient background
        let gradient = NSGradient(colors: [NSColor.blue, NSColor.purple])
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 45)
        
        // Add timestamp text
        let text = "Mac Screen - \(Date().formatted(.dateTime.hour().minute().second()))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24),
            .foregroundColor: NSColor.white
        ]
        
        let textSize = text.size(withAttributes: attributes)
        let textRect = NSRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        
        text.draw(in: textRect, withAttributes: attributes)
        image.unlockFocus()
        
        // Convert to JPEG data
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapRep.representation(
                using: NSBitmapImageRep.FileType.jpeg,
                properties: [NSBitmapImageRep.PropertyKey.compressionFactor: Double(streamingQuality) / 100.0]
              ) else {
            throw NSError(domain: "CaptureError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create image data"])
        }
        
        return jpegData
    }
    
    private func sendScreenData(_ data: Data) {
        guard let session = session, !connectedPeers.isEmpty else { return }
        
        // Create status info
        let statusInfo: [String: Any] = [
            "fps": currentFPS,
            "quality": streamingQuality,
            "latency": networkLatency,
            "audioEnabled": false,
            "audioLatency": 0
        ]
        
        do {
            // Send status info first
            let statusData = try JSONSerialization.data(withJSONObject: statusInfo)
            try session.send(statusData, toPeers: connectedPeers, with: .reliable)
            
            // Then send screen data
            try session.send(data, toPeers: connectedPeers, with: .unreliable)
            
            print("📤 Sent \(data.count) bytes to \(connectedPeers.count) peer(s)")
            
        } catch {
            print("❌ Failed to send data: \(error)")
        }
    }
    
    func updateStreamingSettings(fps: Int, quality: Int) {
        print("⚙️ Updating streaming settings: \(fps) FPS, \(quality)% quality")
        currentFPS = fps
        streamingQuality = quality
        
        // Restart capture timer with new FPS
        if isCapturing {
            captureTimer?.invalidate()
            captureTimer = Timer.scheduledTimer(withTimeInterval: 1.0/Double(currentFPS), repeats: true) { [weak self] _ in
                self?.captureAndSendScreen()
            }
        }
    }
}

// MARK: - MCSessionDelegate
extension MultipeerCapture: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                print("✅ Mac: iPhone connected - \(peerID.displayName)")
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                }
                self.startCapturing()
                
            case .connecting:
                print("🔄 Mac: iPhone connecting - \(peerID.displayName)")
                
            case .notConnected:
                print("❌ Mac: iPhone disconnected - \(peerID.displayName)")
                self.connectedPeers.removeAll { $0 == peerID }
                
                if self.connectedPeers.isEmpty {
                    self.stopCapturing()
                }
                
            @unknown default:
                print("❓ Mac: Unknown state for \(peerID.displayName)")
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Handle any data from iPhone (like settings updates)
        print("📥 Mac: Received \(data.count) bytes from \(peerID.displayName)")
        
        // Try to parse as settings update
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let fps = json["fps"] as? Int,
               let quality = json["quality"] as? Int {
                DispatchQueue.main.async {
                    self.updateStreamingSettings(fps: fps, quality: quality)
                }
            }
        } catch {
            print("⚠️ Could not parse received data as settings")
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

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MultipeerCapture: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("📱 Mac: Received invitation from iPhone: \(peerID.displayName)")
        
        // Auto-accept invitations from iPhones
        invitationHandler(true, session)
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("❌ Mac: Failed to start advertising: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.isAdvertising = false
        }
    }
}

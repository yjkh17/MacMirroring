import Foundation
import Network
import CoreGraphics
import Combine
import ImageIO
import AppKit

class MirroringServer: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var connectedClients = 0
    
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var screenCaptureTimer: Timer?
    private var netService: NetService?
    
    func start() {
        do {
            // Create listener for _macmirror._tcp service
            let parameters = NWParameters.tcp
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
                        self?.startScreenCapture()
                        print("Server ready and listening on port 8080")
                    case .failed(let error):
                        print("Listener failed: \(error)")
                        self?.isRunning = false
                    default:
                        break
                    }
                }
            }
            
            listener?.start(queue: .main)
        } catch {
            print("Failed to start listener: \(error)")
        }
    }
    
    func stop() {
        listener?.cancel()
        connections.forEach { $0.cancel() }
        connections.removeAll()
        screenCaptureTimer?.invalidate()
        screenCaptureTimer = nil
        netService?.stop()
        netService = nil
        
        DispatchQueue.main.async {
            self.isRunning = false
            self.connectedClients = 0
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.connections.append(connection)
                    self?.connectedClients = self?.connections.count ?? 0
                    print("iPhone connected! Total clients: \(self?.connectedClients ?? 0)")
                case .cancelled, .failed:
                    self?.connections.removeAll { $0 === connection }
                    self?.connectedClients = self?.connections.count ?? 0
                    print("iPhone disconnected! Total clients: \(self?.connectedClients ?? 0)")
                default:
                    break
                }
            }
        }
        
        connection.start(queue: .main)
    }
    
    private func startBonjourAdvertising() {
        // Stop any existing service
        netService?.stop()
        
        // Create and configure NetService
        netService = NetService(domain: "local.", type: "_macmirror._tcp.", name: "Mac Screen", port: 8080)
        netService?.delegate = self
        
        // Publish the service
        netService?.publish()
        print("Starting Bonjour advertising for _macmirror._tcp service")
    }
    
    private func startScreenCapture() {
        screenCaptureTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            self?.captureAndSendScreen()
        }
    }
    
    private func captureAndSendScreen() {
        guard let screenImage = captureScreen() else { return }
        
        // Send to all connected clients
        for connection in connections {
            connection.send(content: screenImage, completion: .contentProcessed { error in
                if let error = error {
                    print("Failed to send screen data: \(error)")
                }
            })
        }
    }
    
    private func captureScreen() -> Data? {
        guard let screen = NSScreen.main else {
            print("No main screen found")
            return nil
        }
        
        let rect = screen.frame
        let screenRect = CGRect(x: 0, y: 0, width: rect.width, height: rect.height)
        
        // Create a bitmap representation of the screen
        guard let imageRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(rect.width),
            pixelsHigh: Int(rect.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            print("Failed to create bitmap representation")
            return nil
        }
        
        // Create a graphics context
        let context = NSGraphicsContext(bitmapImageRep: imageRep)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        
        // Fill with a test pattern for now (since we can't capture screen without permissions)
        let colors: [NSColor] = [.red, .green, .blue, .yellow, .purple, .orange]
        let stripHeight = rect.height / CGFloat(colors.count)
        
        for (index, color) in colors.enumerated() {
            color.setFill()
            let stripRect = CGRect(x: 0, y: CGFloat(index) * stripHeight, width: rect.width, height: stripHeight)
            stripRect.fill()
        }
        
        // Add some text
        let text = "Mac Screen Mirror Test - \(Date().formatted(date: .omitted, time: .standard))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24),
            .foregroundColor: NSColor.white
        ]
        text.draw(at: CGPoint(x: 50, y: rect.height / 2), withAttributes: attributes)
        
        NSGraphicsContext.restoreGraphicsState()
        
        // Convert to JPEG data
        guard let jpegData = imageRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            print("Failed to create JPEG data")
            return nil
        }
        
        return jpegData
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

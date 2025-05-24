import Foundation
import Network
import CoreGraphics
import Combine
import ImageIO
import AppKit
import ScreenCaptureKit

class MirroringServer: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var connectedClients = 0
    
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var screenCaptureTimer: Timer?
    private var netService: NetService?
    private var frameCounter = 0
    
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
        // 5 FPS for real screen capture
        screenCaptureTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task {
                await self?.captureAndSendScreen()
            }
        }
    }
    
    private func captureAndSendScreen() async {
        guard let screenImage = await captureScreen() else { return }
        
        let lengthData = withUnsafeBytes(of: UInt32(screenImage.count).bigEndian) { Data($0) }
        let frameData = lengthData + screenImage
        
        // Send to all connected clients
        for connection in connections {
            connection.send(content: frameData, completion: .contentProcessed { error in
                if let error = error {
                    print("Failed to send screen data: \(error)")
                }
            })
        }
    }
    
    private func captureScreen() async -> Data? {
        do {
            // Get available content
            let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            
            guard let display = availableContent.displays.first else {
                print("No displays found")
                return nil
            }
            
            // Create filter to capture the entire display
            let filter = SCContentFilter(display: display, excludingWindows: [])
            
            // Configure screen capture
            let configuration = SCStreamConfiguration()
            configuration.width = Int(display.width)
            configuration.height = Int(display.height)
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 5) // 5 FPS
            configuration.queueDepth = 5
            
            // Capture a single frame
            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            
            // Convert to JPEG data
            return convertCGImageToJPEG(cgImage)
            
        } catch {
            print("Screen capture failed: \(error)")
            // Fallback to test pattern if screen capture fails
            return createTestPattern()
        }
    }
    
    private func convertCGImageToJPEG(_ cgImage: CGImage) -> Data? {
        let mutableData = CFDataCreateMutable(nil, 0)!
        guard let destination = CGImageDestinationCreateWithData(mutableData, "public.jpeg" as CFString, 1, nil) else {
            print("Failed to create image destination")
            return nil
        }
        
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.7
        ]
        
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        
        guard CGImageDestinationFinalize(destination) else {
            print("Failed to finalize image destination")
            return nil
        }
        
        return mutableData as Data
    }
    
    // Fallback test pattern if screen capture fails
    private func createTestPattern() -> Data? {
        guard let screen = NSScreen.main else { return nil }
        
        let rect = screen.frame
        
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
        ) else { return nil }
        
        let context = NSGraphicsContext(bitmapImageRep: imageRep)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        
        // Simple test pattern
        NSColor.systemRed.setFill()
        NSRect(x: 0, y: 0, width: rect.width, height: rect.height).fill()
        
        let text = "Screen Capture Not Available\nUsing Test Pattern"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 48),
            .foregroundColor: NSColor.white
        ]
        
        let textSize = text.size(withAttributes: attributes)
        let textRect = NSRect(
            x: (rect.width - textSize.width) / 2,
            y: (rect.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)
        
        NSGraphicsContext.restoreGraphicsState()
        
        return imageRep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
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

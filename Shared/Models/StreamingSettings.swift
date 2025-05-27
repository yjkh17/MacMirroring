import Foundation
import Network

enum StreamingMode: String, CaseIterable, Identifiable {
    case performance = "Performance"
    case balanced = "Balanced"
    case fidelity = "Fidelity"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .performance:
            return "Lower quality, higher framerate, minimal latency"
        case .balanced:
            return "Balanced quality and performance"
        case .fidelity:
            return "Higher quality, may have higher latency"
        }
    }
    
    var preferredFPS: Int {
        switch self {
        case .performance: return 45
        case .balanced: return 30
        case .fidelity: return 20
        }
    }
    
    var preferredQuality: Float {
        switch self {
        case .performance: return 0.3
        case .balanced: return 0.5
        case .fidelity: return 0.7
        }
    }
    
    var preferredAudioQuality: Float {
        switch self {
        case .performance: return 0.6
        case .balanced: return 0.8
        case .fidelity: return 1.0
        }
    }
}

enum CaptureSource: String, CaseIterable, Identifiable {
    case fullDisplay = "Full Display"
    case singleWindow = "Single Window"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .fullDisplay:
            return "Stream entire Mac screen"
        case .singleWindow:
            return "Stream a specific application window"
        }
    }
}

struct MacWindow: Identifiable, Codable {
    let id: UInt32
    let title: String
    let ownerName: String
}

struct MacDisplay: Identifiable, Codable {
    let id: UInt32
    let name: String
    let width: Int
    let height: Int
}

class StreamingSettings: ObservableObject {
    @Published var streamingMode: StreamingMode = .balanced
    @Published var captureSource: CaptureSource = .fullDisplay
    @Published var selectedWindowName: String?
    @Published var selectedDisplayName: String?
    
    @Published var availableWindows: [MacWindow] = []
    @Published var availableDisplays: [MacDisplay] = []
    @Published var selectedWindow: MacWindow?
    @Published var selectedDisplay: MacDisplay?
    @Published var isLoadingWindowsDisplays = false
    
    @Published var isAudioEnabled = true
    @Published var audioQuality: Float = 0.8
    @Published var audioLatency: Float = 0.02
    
    func sendSettingsToServer(via connection: NWConnection?) {
        let settings = [
            "streamingMode": streamingMode.rawValue,
            "captureSource": captureSource.rawValue,
            "preferredFPS": streamingMode.preferredFPS,
            "preferredQuality": Int(streamingMode.preferredQuality * 100),
            "selectedWindow": selectedWindowName ?? "",
            "selectedDisplay": selectedDisplayName ?? "",
            "selectedWindowId": selectedWindow?.id ?? 0,
            "selectedDisplayId": selectedDisplay?.id ?? 0,
            "audioEnabled": isAudioEnabled,
            "audioQuality": audioQuality,
            "audioLatency": audioLatency,
            "audioSampleRate": 44100.0,
            "audioChannels": 2,
            "audioBitDepth": 16,
            "audioFormat": "int16"
        ] as [String: Any]
        
        guard let settingsData = try? JSONSerialization.data(withJSONObject: settings),
              let connection = connection else { return }
        
        let settingsCommand = Data([0xFF]) + settingsData
        
        print("📱 Sending \(streamingMode.rawValue) settings: \(streamingMode.preferredFPS) FPS, \(Int(streamingMode.preferredQuality * 100))% quality, Audio: \(isAudioEnabled ? "ON" : "OFF") (\(String(format: "%.1f", audioQuality * 100))%)")
        
        connection.send(content: settingsCommand, contentContext: .defaultMessage, isComplete: true, completion: .contentProcessed({ error in
            if let error = error {
                print("Failed to send settings: \(error)")
            } else {
                print("✅ Settings sent to Mac server including audio config")
                // Notify UI about streaming mode change
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name("StreamingModeChanged"), object: nil)
                }
            }
        }))
    }
    
    func requestWindowsAndDisplays(via connection: NWConnection?) {
        guard let connection = connection else { return }
        
        let request = ["action": "getWindowsDisplays"]
        guard let requestData = try? JSONSerialization.data(withJSONObject: request) else { return }
        
        let requestCommand = Data([0xFE]) + requestData
        
        isLoadingWindowsDisplays = true
        
        connection.send(content: requestCommand, contentContext: .defaultMessage, isComplete: true, completion: .contentProcessed({ error in
            if let error = error {
                print("Failed to request windows/displays: \(error)")
                DispatchQueue.main.async {
                    self.isLoadingWindowsDisplays = false
                }
            }
        }))
    }
    
    func processWindowsDisplaysResponse(_ data: Data) {
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let windowsArray = json["windows"] as? [[String: Any]] {
                    let windows = windowsArray.compactMap { windowDict -> MacWindow? in
                        guard let id = windowDict["id"] as? UInt32,
                              let title = windowDict["title"] as? String,
                              let ownerName = windowDict["ownerName"] as? String else { return nil }
                        return MacWindow(id: id, title: title, ownerName: ownerName)
                    }
                    
                    DispatchQueue.main.async {
                        self.availableWindows = windows
                    }
                }
                
                if let displaysArray = json["displays"] as? [[String: Any]] {
                    let displays = displaysArray.compactMap { displayDict -> MacDisplay? in
                        guard let id = displayDict["id"] as? UInt32,
                              let name = displayDict["name"] as? String,
                              let width = displayDict["width"] as? Int,
                              let height = displayDict["height"] as? Int else { return nil }
                        return MacDisplay(id: id, name: name, width: width, height: height)
                    }
                    
                    DispatchQueue.main.async {
                        self.availableDisplays = displays
                        if self.selectedDisplay == nil, let firstDisplay = displays.first {
                            self.selectedDisplay = firstDisplay
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    self.isLoadingWindowsDisplays = false
                }
            }
        } catch {
            print("Failed to parse windows/displays response: \(error)")
            DispatchQueue.main.async {
                self.isLoadingWindowsDisplays = false
            }
        }
    }
    
    func toggleAudio() {
        isAudioEnabled.toggle()
        
        audioQuality = streamingMode.preferredAudioQuality
        
        print("🎵 Audio streaming: \(isAudioEnabled ? "enabled" : "disabled")")
    }
    
    func setAudioQuality(_ quality: Float) {
        audioQuality = max(0.1, min(1.0, quality))
        print("🎵 Audio quality set to: \(String(format: "%.1f", audioQuality * 100))%")
    }
    
    func setAudioLatency(_ latency: Float) {
        audioLatency = max(0.01, min(0.1, latency))
        print("🎵 Audio latency target: \(String(format: "%.0f", audioLatency * 1000))ms")
    }
    
    func applyPreset(_ preset: StreamingPreset) {
        switch preset {
        case .gaming:
            streamingMode = .performance
            isAudioEnabled = true
            audioQuality = 0.6
            audioLatency = 0.015
        case .productivity:
            streamingMode = .balanced
            isAudioEnabled = true
            audioQuality = 0.8
            audioLatency = 0.02
        case .mediaConsumption:
            streamingMode = .fidelity
            isAudioEnabled = true
            audioQuality = 1.0
            audioLatency = 0.03
        case .presentation:
            streamingMode = .balanced
            isAudioEnabled = true
            audioQuality = 0.9
            audioLatency = 0.025
        }
        
        print("📱 Applied \(preset.rawValue) preset")
    }
    
    func validateAudioSettings() -> Bool {
        guard audioQuality >= 0.1 && audioQuality <= 1.0 else {
            print("❌ Invalid audio quality: \(audioQuality)")
            return false
        }
        
        guard audioLatency >= 0.01 && audioLatency <= 0.1 else {
            print("❌ Invalid audio latency: \(audioLatency)")
            return false
        }
        
        return true
    }
    
    func getAudioDiagnostics() -> [String: Any] {
        return [
            "audioEnabled": isAudioEnabled,
            "audioQuality": String(format: "%.1f%%", audioQuality * 100),
            "audioLatency": String(format: "%.0fms", audioLatency * 1000),
            "audioSampleRate": "44.1kHz",
            "audioChannels": "Stereo",
            "audioBitDepth": "16-bit",
            "audioFormat": "PCM Int16"
        ]
    }
}

enum StreamingPreset: String, CaseIterable, Identifiable {
    case gaming = "Gaming"
    case productivity = "Productivity"
    case mediaConsumption = "Media"
    case presentation = "Presentation"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .gaming:
            return "Optimized for low latency gaming and interactive applications"
        case .productivity:
            return "Balanced settings for work and general productivity"
        case .mediaConsumption:
            return "High quality for watching videos and media content"
        case .presentation:
            return "Optimized for presentations and screen sharing"
        }
    }
    
    var icon: String {
        switch self {
        case .gaming: return "gamecontroller"
        case .productivity: return "laptopcomputer"
        case .mediaConsumption: return "tv"
        case .presentation: return "projector"
        }
    }
}

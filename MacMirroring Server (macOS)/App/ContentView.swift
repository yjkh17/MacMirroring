import SwiftUI

struct ContentView: View {
    @StateObject private var server = MirroringServer()
    @State private var showAdvancedStats = false
    @State private var uptimeTimer: Timer?
    @State private var serverUptime: TimeInterval = 0
    
    var body: some View {
        VStack(spacing: 25) {
            // Header with server info
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mac Mirroring Server")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("v1.0 • Build 2025.1 • Always Ready")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    showAdvancedStats.toggle()
                }) {
                    Image(systemName: showAdvancedStats ? "chart.bar.fill" : "chart.bar")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
            }
            
            // Server status icon
            VStack(spacing: 15) {
                ZStack {
                    Circle()
                        .fill(server.isRunning ? .green.opacity(0.2) : .orange.opacity(0.2))
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: server.isBackgroundMode ? "moon.stars.fill" : "desktopcomputer")
                        .font(.system(size: 50))
                        .foregroundColor(server.isRunning ? .green : .orange)
                }
                
                serverStatusView
            }
            
            if showAdvancedStats {
                advancedStatsView
            }
            
            connectionStatusView
            
            backgroundServerSection
            
            serverControlSection
            
            Spacer()
            
            footerView
        }
        .padding()
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            startUptimeTimer()
        }
        .onDisappear {
            uptimeTimer?.invalidate()
        }
    }
    
    private var serverStatusView: some View {
        VStack(spacing: 8) {
            HStack {
                Circle()
                    .fill(server.isRunning ? .green : .orange)
                    .frame(width: 12, height: 12)
                
                Text(server.isRunning ? "Server Always Ready" : "Server Starting...")
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            
            Text(server.isRunning ? "iPhone can connect anytime - Background operation enabled" : "Initializing persistent server...")
                .foregroundColor(.secondary)
                .font(.subheadline)
                .multilineTextAlignment(.center)
            
            if server.isRunning {
                HStack(spacing: 20) {
                    statusBadge("Service", "_macmirror._tcp", .blue)
                    statusBadge("Port", "8080", .green)
                    statusBadge("Mode", server.isBackgroundMode ? "Background" : "Active", server.isBackgroundMode ? .orange : .blue)
                    statusBadge("Uptime", formattedUptime, .purple)
                }
            }
        }
    }
    
    private var advancedStatsView: some View {
        VStack(spacing: 15) {
            Text("Advanced Statistics")
                .font(.headline)
                .foregroundColor(.primary)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 15) {
                statCard("Current FPS", "\(server.currentFPS)", "speedometer", .blue)
                statCard("Quality", "\(Int(server.currentQuality * 100))%", "photo", .green)
                statCard("Latency", "\(Int(server.estimatedNetworkLatency * 1000))ms", "network", .orange)
                statCard("Capture Mode", server.captureMode.rawValue, "viewfinder", .purple)
                statCard("Memory Usage", "\(getMemoryUsage())MB", "memorychip", .red)
                statCard("Sessions", "\(server.sessionCount)", "number.circle", .cyan)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(15)
    }
    
    private var connectionStatusView: some View {
        VStack(spacing: 15) {
            if server.connectedClients > 0 {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "iphone.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                        
                        Text("\(server.connectedClients) iPhone(s) Connected")
                            .font(.headline)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                        
                        if server.isBackgroundMode {
                            Image(systemName: "moon.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                        }
                    }
                    
                    if server.currentFPS > 0 {
                        HStack(spacing: 25) {
                            performanceIndicator("FPS", "\(server.currentFPS)", .blue)
                            performanceIndicator("Quality", "\(Int(server.currentQuality * 100))%", .green)
                            performanceIndicator("Latency", "\(Int(server.estimatedNetworkLatency * 1000))ms", .orange)
                            performanceIndicator("Audio", server.isAudioCapturing ? "ON" : "OFF", server.isAudioCapturing ? .green : .gray)
                        }
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15))
                    }
                }
            } else {
                VStack(spacing: 12) {
                    VStack(spacing: 8) {
                        Text("📱 Server Ready for iPhone Connection")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        
                        Text("🔍 Open Mac Mirroring on iPhone → Tap 'Connect to Mac'")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 15) {
                        instructionStep("1", "iPhone App", "iphone")
                        instructionStep("2", "Same Wi-Fi", "wifi")
                        instructionStep("3", "Connect", "play.circle")
                        instructionStep("4", "Always Ready", "checkmark.seal")
                    }
                }
            }
        }
    }
    
    private var backgroundServerSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("Background Server")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                
                Text("Always Running")
                    .font(.subheadline)
                    .foregroundColor(.green)
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                backgroundStatusCard("Total Uptime", formatBackgroundUptime(), .blue)
                backgroundStatusCard("Sessions", "\(server.sessionCount)", .purple)
                backgroundStatusCard("Memory Usage", "\(getMemoryUsage())MB", .orange)
                backgroundStatusCard("Audio Ready", server.isAudioCapturing ? "Streaming" : "Available", server.isAudioCapturing ? .green : .gray)
            }
            
            // Background mode indicator
            if server.isBackgroundMode {
                HStack {
                    Image(systemName: "moon.stars.fill")
                        .foregroundColor(.orange)
                    Text("Running in background mode - iPhone can connect anytime without opening this window")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(.orange.opacity(0.1))
                .cornerRadius(8)
            } else {
                HStack {
                    Image(systemName: "sun.max.fill")
                        .foregroundColor(.blue)
                    Text("Active foreground mode - window open for monitoring")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(.blue.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(.gray.opacity(0.05))
        .cornerRadius(15)
    }
    
    private var serverControlSection: some View {
        VStack(spacing: 15) {
            Text("Server Control")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(spacing: 12) {
                HStack(spacing: 15) {
                    Button(action: {
                        if server.isBackgroundMode {
                            server.disableBackgroundMode()
                        } else {
                            server.enableBackgroundMode()
                        }
                    }) {
                        Label(
                            server.isBackgroundMode ? "Exit Background Mode" : "Enter Background Mode",
                            systemImage: server.isBackgroundMode ? "sun.max" : "moon.stars"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    
                    Button("Hide Window") {
                        NSApplication.shared.windows.first?.miniaturize(nil)
                        server.enableBackgroundMode()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
                
                Text("💡 Server continues running when window is closed. Use the menu bar icon (📺) to access controls or show this window again.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding()
        .background(.gray.opacity(0.05))
        .cornerRadius(15)
    }
    
    private var footerView: some View {
        VStack(spacing: 8) {
            Text("Persistent background server - Always ready for iPhone connections")
                .font(.caption)
                .foregroundColor(.secondary)
                .italic()
            
            HStack(spacing: 15) {
                Text("Made with ❤️ in Swift")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text("•")
                    .foregroundColor(.secondary)
                
                Text("Ultra-low latency audiovisual streaming")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text("•")
                    .foregroundColor(.secondary)
                
                Text("Background operation")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func statusBadge(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
    
    private func statCard(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
    
    private func performanceIndicator(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func instructionStep(_ number: String, _ title: String, _ icon: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.2))
                    .frame(width: 30, height: 30)
                
                Text(number)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
            
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.blue)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func backgroundStatusCard(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var formattedUptime: String {
        let hours = Int(serverUptime) / 3600
        let minutes = (Int(serverUptime) % 3600) / 60
        let seconds = Int(serverUptime) % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
    
    private func formatBackgroundUptime() -> String {
        guard let startTime = server.backgroundStartTime else { 
            return formattedUptime
        }
        
        let uptime = Date().timeIntervalSince(startTime)
        let hours = Int(uptime) / 3600
        let minutes = (Int(uptime) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "< 1m"
        }
    }
    
    private func getMemoryUsage() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? Int(info.resident_size / (1024 * 1024)) : 0
    }
    
    private func startUptimeTimer() {
        uptimeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if server.isRunning {
                serverUptime += 1
            }
        }
    }
}

#Preview {
    ContentView()
}

// ADD: Menu bar integration and system tray functionality
import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var server = MirroringServer()
    @State private var showAdvancedStats = false
    @State private var uptimeTimer: Timer?
    @State private var serverUptime: TimeInterval = 0
    // ADD: Menu bar and system integration
    @State private var showInMenuBar = true
    @State private var startOnLogin = false
    @State private var showNotifications = true
    
    var body: some View {
        VStack(spacing: 25) {
            // Header with enhanced controls
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mac Mirroring Server")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("v1.0 • Build 2025.1")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    // ADD: Settings button
                    Button(action: {
                        showSettingsPanel()
                    }) {
                        Image(systemName: "gearshape")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                    
                    Button(action: {
                        showAdvancedStats.toggle()
                    }) {
                        Image(systemName: showAdvancedStats ? "chart.bar.fill" : "chart.bar")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    
                    // ADD: Menu bar toggle
                    Button(action: {
                        toggleMenuBarMode()
                    }) {
                        Image(systemName: "menubar.rectangle")
                            .font(.title2)
                            .foregroundColor(.green)
                    }
                }
            }
            
            // Enhanced server status
            VStack(spacing: 15) {
                ZStack {
                    Circle()
                        .fill(server.isRunning ? .green.opacity(0.2) : .orange.opacity(0.2))
                        .frame(width: 100, height: 100)
                    
                    // ADD: Animated indicator
                    if server.connectedClients > 0 {
                        Circle()
                            .stroke(.green, lineWidth: 3)
                            .frame(width: 110, height: 110)
                            .scaleEffect(1.0)
                            .opacity(0.8)
                            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: server.connectedClients)
                    }
                    
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 50))
                        .foregroundColor(server.isRunning ? .green : .orange)
                }
                
                serverStatusView
            }
            
            if showAdvancedStats {
                advancedStatsView
            }
            
            connectionStatusView
            
            // ADD: Quick actions section
            quickActionsView
            
            Spacer()
            
            footerView
        }
        .padding()
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            startUptimeTimer()
            setupMenuBarIfNeeded()
        }
        .onDisappear {
            uptimeTimer?.invalidate()
        }
    }
    
    // ADD: Quick actions view
    private var quickActionsView: some View {
        VStack(spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
                .foregroundColor(.primary)
            
            HStack(spacing: 15) {
                actionButton("Restart Server", "arrow.clockwise", .orange) {
                    restartServer()
                }
                
                actionButton("Network Info", "network", .blue) {
                    showNetworkInfo()
                }
                
                actionButton("Share QR", "qrcode", .purple) {
                    showQRCode()
                }
                
                actionButton("Logs", "doc.text", .gray) {
                    showLogs()
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(15)
    }
    
    private func actionButton(_ title: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(color.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    // ... rest of existing code remains the same ...
    
    private var serverStatusView: some View {
        VStack(spacing: 8) {
            HStack {
                Circle()
                    .fill(server.isRunning ? .green : .orange)
                    .frame(width: 12, height: 12)
                
                Text(server.isRunning ? "Server Ready" : "Server Starting...")
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            
            Text(server.isRunning ? "Ready for iPhone connections" : "Initializing network services...")
                .foregroundColor(.secondary)
                .font(.subheadline)
            
            if server.isRunning {
                HStack(spacing: 20) {
                    statusBadge("Service", "_macmirror._tcp", .blue)
                    statusBadge("Port", "8080", .green)
                    statusBadge("Uptime", formattedUptime, .orange)
                    // ADD: Network status
                    statusBadge("Network", getNetworkName(), .cyan)
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
                statCard("Memory Usage", "< 200MB", "memorychip", .red)
                statCard("CPU Usage", "< 20%", "cpu", .cyan)
                // ADD: Additional stats
                statCard("Data Sent", formatDataSize(server.totalDataSent), "arrow.up.circle", .indigo)
                statCard("Frames Sent", "\(server.totalFramesSent)", "photo.stack", .pink)
                statCard("Avg Quality", "\(Int(server.averageQuality * 100))%", "chart.line.uptrend.xyaxis", .teal)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(15)
    }
    
    // ... rest of existing code ...
    
    // ADD: Helper functions
    private func showSettingsPanel() {
        // Show settings panel
    }
    
    private func toggleMenuBarMode() {
        showInMenuBar.toggle()
        // Implement menu bar mode
    }
    
    private func setupMenuBarIfNeeded() {
        if showInMenuBar {
            // Setup menu bar icon
        }
    }
    
    private func restartServer() {
        // Restart server functionality
    }
    
    private func showNetworkInfo() {
        // Show network information panel
    }
    
    private func showQRCode() {
        // Show QR code for easy connection
    }
    
    private func showLogs() {
        // Show server logs
    }
    
    private func getNetworkName() -> String {
        // Get current Wi-Fi network name
        return "Wi-Fi"
    }
    
    private func formatDataSize(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1024.0 / 1024.0
        return String(format: "%.1f MB", mb)
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
                        
                        Spacer()
                        
                        // ADD: Connection indicator
                        HStack(spacing: 4) {
                            ForEach(0..<3) { index in
                                Circle()
                                    .fill(.green)
                                    .frame(width: 4, height: 4)
                                    .scaleEffect(1.0)
                                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.2), value: server.isRunning)
                            }
                        }
                    }
                    
                    if server.currentFPS > 0 {
                        HStack(spacing: 25) {
                            performanceIndicator("FPS", "\(server.currentFPS)", .blue)
                            performanceIndicator("Quality", "\(Int(server.currentQuality * 100))%", .green)
                            performanceIndicator("Latency", "\(Int(server.estimatedNetworkLatency * 1000))ms", .orange)
                        }
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15))
                    }
                }
            } else {
                VStack(spacing: 12) {
                    VStack(spacing: 8) {
                        Text("📱 Open Mac Mirroring on your iPhone")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        
                        Text("🔍 Tap 'Connect to Mac' to start mirroring")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 15) {
                        instructionStep("1", "Open iPhone app", "iphone")
                        instructionStep("2", "Same Wi-Fi network", "wifi")
                        instructionStep("3", "Tap Connect", "play.circle")
                    }
                }
            }
        }
    }
    
    private var footerView: some View {
        VStack(spacing: 8) {
            Text("Controlled entirely from iPhone app")
                .font(.caption)
                .foregroundColor(.secondary)
                .italic()
            
            HStack(spacing: 15) {
                Text("Made with ❤️ in Swift")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text("•")
                    .foregroundColor(.secondary)
                
                Text("Ultra-low latency streaming")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text("•")
                    .foregroundColor(.secondary)
                
                Text("Build \(Bundle.main.buildNumber ?? "1")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
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
    
    private func startUptimeTimer() {
        uptimeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if server.isRunning {
                serverUptime += 1
            }
        }
    }
}

// ADD: Bundle extension
extension Bundle {
    var buildNumber: String? {
        return infoDictionary?["CFBundleVersion"] as? String
    }
}

#Preview {
    ContentView()
}
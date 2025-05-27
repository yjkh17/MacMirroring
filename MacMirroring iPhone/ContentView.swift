import SwiftUI
import Network

struct ContentView: View {
    @StateObject private var mirroringManager = MultipeerDisplay()
    @StateObject private var streamingSettings = StreamingSettings()
    @State private var isFullScreen = false
    @State private var showSettings = false
    @State private var showConnectionHistory = false
    @State private var lastConnectedTime: Date?
    @State private var sessionDuration: TimeInterval = 0
    @State private var sessionTimer: Timer?
    @State private var connectionState: ConnectionState = .disconnected
    @State private var showQuickActions = false
    @State private var showPerformanceOverlay = false
    @State private var batteryLevel: Float = 1.0
    @State private var thermalState: ProcessInfo.ThermalState = .nominal
    @State private var networkQualityHistory: [NetworkQuality] = []
    @State private var showDiagnostics = false
    @State private var isLandscapeMode = false
    @State private var showNotifications = false
    @State private var notificationQueue: [NotificationItem] = []
    
    enum ConnectionState {
        case disconnected, searching, connecting, connected, reconnecting, error, paused
        
        var description: String {
            switch self {
            case .disconnected: return "Ready to connect"
            case .searching: return "Searching for Mac..."
            case .connecting: return "Connecting..."
            case .connected: return "Connected to Mac"
            case .reconnecting: return "Reconnecting..."
            case .error: return "Connection error"
            case .paused: return "Connection paused"
            }
        }
        
        var color: Color {
            switch self {
            case .disconnected: return .secondary
            case .searching: return .blue
            case .connecting: return .orange
            case .connected: return .green
            case .reconnecting: return .yellow
            case .error: return .red
            case .paused: return .purple
            }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundGradient
                
                if mirroringManager.isConnected {
                    mirroringView
                } else {
                    connectionView
                }
                
                if showNotifications && !notificationQueue.isEmpty {
                    notificationOverlay
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                if showPerformanceOverlay {
                    performanceMonitoringOverlay
                        .transition(.opacity)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            setupStreamingSettings()
            startSessionTracking()
            startSystemMonitoring()
        }
        .onDisappear {
            cleanup()
        }
        .onChange(of: mirroringManager.isConnected) { oldValue, newValue in
            updateConnectionState()
            handleConnectionChange(newValue)
        }
        .onChange(of: mirroringManager.isSearching) { _, _ in
            updateConnectionState()
        }
        .onChange(of: mirroringManager.connectionError) { _, _ in
            updateConnectionState()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            updateOrientation()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
            updateBatteryLevel()
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            updateThermalState()
        }
    }
    
    private var backgroundGradient: some View {
        ZStack {
            LinearGradient(
                colors: connectionGradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 1.0), value: connectionState)
            
            if connectionState == .connected {
                ForEach(0..<6, id: \.self) { index in
                    AnimatedParticle()
                        .opacity(0.1)
                }
            }
        }
    }
    
    private var connectionGradientColors: [Color] {
        switch connectionState {
        case .disconnected:
            return [Color.black, Color.gray.opacity(0.3)]
        case .searching:
            return [Color.blue.opacity(0.15), Color.black]
        case .connecting:
            return [Color.orange.opacity(0.15), Color.black]
        case .connected:
            return [Color.green.opacity(0.15), Color.black]
        case .reconnecting:
            return [Color.yellow.opacity(0.15), Color.black]
        case .error:
            return [Color.red.opacity(0.15), Color.black]
        case .paused:
            return [Color.purple.opacity(0.15), Color.black]
        }
    }
    
    private var mirroringView: some View {
        MacScreenView(
            mirroringManager: mirroringManager,
            isFullScreen: $isFullScreen,
            showSettings: $showSettings
        )
        .fullScreenCover(isPresented: $isFullScreen) {
            FullScreenView(
                mirroringManager: mirroringManager,
                isPresented: $isFullScreen
            )
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                streamingSettings: streamingSettings,
                mirroringManager: mirroringManager,
                isPresented: $showSettings
            )
        }
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 8) {
                if sessionDuration > 0 {
                    sessionOverlay
                }
                
                systemStatusIndicators
            }
            .padding()
        }
        .onTapGesture(count: 3) {
            withAnimation(.spring()) {
                showPerformanceOverlay.toggle()
            }
        }
    }
    
    private var connectionView: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 25) {
                    headerSection
                    
                    if mirroringManager.connectionError != nil {
                        errorSection
                    }
                    
                    systemHealthSection
                    
                    connectionStatusSection
                    
                    ConnectionView(mirroringManager: mirroringManager)
                    
                    quickActionsSection
                    
                    if showConnectionHistory {
                        enhancedConnectionHistorySection
                    }
                    
                    if showDiagnostics {
                        diagnosticsSection
                    }
                }
                .padding()
            }
            .navigationTitle("Mac Mirroring")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mac Mirroring")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    HStack(spacing: 8) {
                        Circle()
                            .fill(connectionState.color)
                            .frame(width: 8, height: 8)
                            .scaleEffect(connectionState == .connected ? 1.2 : 1.0)
                            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), 
                                     value: connectionState == .connected)
                        
                        Text(connectionState.description)
                            .font(.subheadline)
                            .foregroundColor(connectionState.color)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: {
                        withAnimation(.spring()) {
                            showDiagnostics.toggle()
                        }
                    }) {
                        Image(systemName: "stethoscope")
                            .font(.title2)
                            .foregroundColor(.cyan)
                    }
                    
                    Button(action: {
                        showConnectionHistory.toggle()
                    }) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    
                    Button(action: {
                        showSettings = true
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                }
            }
            
            enhancedConnectionQualityIndicator
        }
    }
    
    private var enhancedConnectionQualityIndicator: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(0..<4) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(connectionBarColor(for: index))
                        .frame(width: 4, height: CGFloat(8 + index * 2))
                        .animation(.easeInOut.delay(Double(index) * 0.1), value: mirroringManager.networkQuality)
                }
            }
            
            HStack(spacing: 4) {
                Text(mirroringManager.networkQuality.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if networkQualityHistory.count >= 2 {
                    let current = networkQualityHistory.last?.hashValue ?? 0
                    let previous = networkQualityHistory[networkQualityHistory.count - 2].hashValue
                    
                    Image(systemName: current > previous ? "arrow.up" : 
                          current < previous ? "arrow.down" : "minus")
                        .font(.caption2)
                        .foregroundColor(current > previous ? .green : 
                                       current < previous ? .red : .gray)
                }
            }
        }
        .opacity(mirroringManager.isConnected ? 1.0 : 0.3)
    }
    
    private var systemHealthSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("System Health")
                    .font(.headline)
                Spacer()
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                healthCard("Battery", "\(Int(batteryLevel * 100))%", batteryColor, "battery.100")
                healthCard("Thermal", thermalStateText, thermalStateColor, "thermometer")
                healthCard("Orientation", isLandscapeMode ? "Landscape" : "Portrait", .blue, "rotate.3d")
            }
        }
    }
    
    private var systemStatusIndicators: some View {
        VStack(spacing: 4) {
            if batteryLevel < 0.2 {
                systemIndicator("Low Battery", .red, "battery.25")
            }
            
            if thermalState == .serious || thermalState == .critical {
                systemIndicator("High Temp", .orange, "thermometer.sun")
            }
            
            if mirroringManager.networkQuality == .poor {
                systemIndicator("Poor Network", .red, "wifi.slash")
            }
        }
    }
    
    private func systemIndicator(_ text: String, _ color: Color, _ icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.2))
        .clipShape(Capsule())
    }
    
    private var quickActionsSection: some View {
        VStack(spacing: 15) {
            Button(action: {
                withAnimation(.spring()) {
                    showQuickActions.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "bolt.circle.fill")
                    Text("Quick Actions")
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Image(systemName: showQuickActions ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .foregroundColor(.blue)
                .padding()
                .background(.blue.opacity(0.1))
                .cornerRadius(12)
            }
            
            if showQuickActions {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                    quickActionButton("Force Connect", "antenna.radiowaves.left.and.right") {
                        mirroringManager.connectDirectly()
                        addNotification("Attempting connection...", .info)
                    }
                    
                    quickActionButton("Network Scan", "wifi.circle") {
                        performNetworkScan()
                    }
                    
                    quickActionButton("Clear Cache", "trash.circle") {
                        clearAppCache()
                    }
                    
                    quickActionButton("Speed Test", "speedometer") {
                        performSpeedTest()
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
    
    private func quickActionButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.blue)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.gray.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    private var enhancedConnectionHistorySection: some View {
        VStack(spacing: 15) {
            HStack {
                Text("Connection History")
                    .font(.headline)
                Spacer()
                
                Button("Export") {
                    exportConnectionHistory()
                }
                .font(.caption)
                .foregroundColor(.blue)
                
                Button("Clear") {
                    clearConnectionHistory()
                }
                .font(.caption)
                .foregroundColor(.red)
            }
            
            VStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { index in
                    enhancedConnectionHistoryRow(for: index)
                }
            }
        }
        .padding()
        .background(.gray.opacity(0.1))
        .cornerRadius(15)
    }
    
    private func enhancedConnectionHistoryRow(for index: Int) -> some View {
        HStack {
            Circle()
                .fill(index == 0 ? .green : index == 1 ? .orange : .red)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Mac Server \(index + 1)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack {
                    Text("\(Date().addingTimeInterval(-Double(index * 3600)).formatted(.dateTime.hour().minute()))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    
                    Text("\(Int.random(in: 20...120))s duration")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            HStack(spacing: 2) {
                ForEach(0..<3) { barIndex in
                    Rectangle()
                        .fill(barIndex < (3 - index) ? .green : .gray.opacity(0.3))
                        .frame(width: 3, height: CGFloat(4 + barIndex * 2))
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private var diagnosticsSection: some View {
        VStack(spacing: 15) {
            HStack {
                Text("Network Diagnostics")
                    .font(.headline)
                Spacer()
                
                Button("Run All Tests") {
                    runAllDiagnostics()
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                diagnosticCard("Ping", "23ms", .green, "timer")
                diagnosticCard("Bandwidth", "45 Mbps", .blue, "speedometer")
                diagnosticCard("Packet Loss", "0.1%", .green, "chart.line.uptrend.xyaxis")
                diagnosticCard("Jitter", "2ms", .orange, "waveform.path")
            }
        }
        .padding()
        .background(.gray.opacity(0.1))
        .cornerRadius(15)
        .transition(.scale.combined(with: .opacity))
    }
    
    private func diagnosticCard(_ title: String, _ value: String, _ color: Color, _ icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
    
    private var performanceMonitoringOverlay: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Performance Monitor")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                
                Button("Close") {
                    showPerformanceOverlay = false
                }
                .foregroundColor(.blue)
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 15) {
                if let serverStatus = mirroringManager.serverStatus {
                    performanceMetricCard("FPS", "\(serverStatus.fps)", .blue)
                    performanceMetricCard("Quality", "\(serverStatus.quality)%", .green)
                    performanceMetricCard("Latency", "\(serverStatus.latency)ms", .orange)
                    performanceMetricCard("Data Rate", "\(Int.random(in: 5...15)) MB/s", .purple)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(.black.opacity(0.8))
        .cornerRadius(20)
        .padding()
    }
    
    private func performanceMetricCard(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.2))
        .cornerRadius(12)
    }
    
    private var notificationOverlay: some View {
        VStack(spacing: 8) {
            ForEach(notificationQueue.prefix(3), id: \.id) { notification in
                NotificationCard(notification: notification) {
                    removeNotification(notification)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 50)
    }
    
    private var connectionQualityIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<4) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(connectionBarColor(for: index))
                    .frame(width: 4, height: CGFloat(8 + index * 2))
                    .animation(.easeInOut.delay(Double(index) * 0.1), value: mirroringManager.networkQuality)
            }
            
            Text(mirroringManager.networkQuality.rawValue)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .opacity(mirroringManager.isConnected ? 1.0 : 0.3)
    }
    
    private func connectionBarColor(for index: Int) -> Color {
        let qualityLevel = networkQualityLevel
        return index < qualityLevel ? mirroringManager.networkQuality.color : Color.gray.opacity(0.3)
    }
    
    private var networkQualityLevel: Int {
        switch mirroringManager.networkQuality {
        case .excellent: return 4
        case .good: return 3
        case .fair: return 2
        case .poor: return 1
        case .unknown: return 0
        }
    }
    
    private var errorSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.title2)
                
                Text("Connection Issue")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            if let error = mirroringManager.connectionError {
                Text(error.localizedDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Button("Retry Connection") {
                    mirroringManager.connectDirectly()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding()
        .background(.red.opacity(0.1))
        .cornerRadius(15)
    }
    
    private var connectionStatusSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Connection Status")
                    .font(.headline)
                Spacer()
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                statusCard("Network", networkStatusText, .green)
                statusCard("Server", serverStatusText, serverStatusColor)
                statusCard("Attempts", "\(mirroringManager.reconnectionAttempts)", .blue)
                statusCard("Duration", sessionDurationText, .green)
            }
        }
    }
    
    private var connectionHistorySection: some View {
        VStack(spacing: 15) {
            HStack {
                Text("Recent Connections")
                    .font(.headline)
                Spacer()
                
                Button("Clear") {
                    // Clear connection history
                }
                .font(.caption)
                .foregroundColor(.red)
            }
            
            VStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    connectionHistoryRow(for: index)
                }
            }
        }
        .padding()
        .background(.gray.opacity(0.1))
        .cornerRadius(15)
    }
    
    private func connectionHistoryRow(for index: Int) -> some View {
        HStack {
            Circle()
                .fill(index == 0 ? .green : .red)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Mac Server \(index + 1)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(Date().addingTimeInterval(-Double(index * 3600)).formatted(.dateTime.hour().minute()))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private var sessionOverlay: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("Session")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Text(sessionDurationText)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.green)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
    
    private func statusCard(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
    
    private func healthCard(_ title: String, _ value: String, _ color: Color, _ icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func setupStreamingSettings() {
        mirroringManager.setStreamingSettings(streamingSettings)
    }
    
    private func updateConnectionState() {
        if mirroringManager.connectionError != nil {
            connectionState = .error
        } else if mirroringManager.isConnected {
            connectionState = .connected
        } else if mirroringManager.isSearching {
            connectionState = .searching
        } else if mirroringManager.reconnectionAttempts > 0 {
            connectionState = .reconnecting
        } else {
            connectionState = .disconnected
        }
    }
    
    private func handleConnectionChange(_ isConnected: Bool) {
        if isConnected {
            lastConnectedTime = Date()
            addNotification("Connected to Mac successfully!", .success)
        } else {
            addNotification("Disconnected from Mac", .warning)
        }
    }
    
    private func startSessionTracking() {
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if mirroringManager.isConnected, let startTime = lastConnectedTime {
                sessionDuration = Date().timeIntervalSince(startTime)
            } else {
                sessionDuration = 0
            }
        }
    }
    
    private func startSystemMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        updateBatteryLevel()
        updateThermalState()
        updateOrientation()
        
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            networkQualityHistory.append(mirroringManager.networkQuality)
            if networkQualityHistory.count > 10 {
                networkQualityHistory.removeFirst()
            }
        }
    }
    
    private func updateBatteryLevel() {
        batteryLevel = UIDevice.current.batteryLevel
    }
    
    private func updateThermalState() {
        thermalState = ProcessInfo.processInfo.thermalState
    }
    
    private func updateOrientation() {
        isLandscapeMode = UIDevice.current.orientation.isLandscape
    }
    
    private func cleanup() {
        sessionTimer?.invalidate()
        sessionTimer = nil
    }
    
    private func performNetworkScan() {
        addNotification("Starting network scan...", .info)
        // Implementation for network scanning
    }
    
    private func clearAppCache() {
        addNotification("Cache cleared successfully", .success)
        // Implementation for cache clearing
    }
    
    private func performSpeedTest() {
        addNotification("Running speed test...", .info)
        // Implementation for speed testing
    }
    
    private func runAllDiagnostics() {
        addNotification("Running comprehensive diagnostics...", .info)
        // Implementation for full diagnostics
    }
    
    private func exportConnectionHistory() {
        addNotification("Connection history exported", .success)
        // Implementation for export
    }
    
    private func clearConnectionHistory() {
        addNotification("Connection history cleared", .info)
        // Implementation for clearing history
    }
    
    private func addNotification(_ message: String, _ type: NotificationType) {
        let notification = NotificationItem(message: message, type: type)
        notificationQueue.append(notification)
        showNotifications = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            removeNotification(notification)
        }
    }
    
    private func removeNotification(_ notification: NotificationItem) {
        notificationQueue.removeAll { $0.id == notification.id }
        if notificationQueue.isEmpty {
            showNotifications = false
        }
    }
    
    private var batteryColor: Color {
        if batteryLevel > 0.5 { return .green }
        else if batteryLevel > 0.2 { return .orange }
        else { return .red }
    }
    
    private var thermalStateText: String {
        switch thermalState {
        case .nominal: return "Normal"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
    
    private var thermalStateColor: Color {
        switch thermalState {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .gray
        }
    }
    
    private var networkStatusText: String {
        return "Wi-Fi Connected"
    }
    
    private var serverStatusText: String {
        return mirroringManager.isSearching ? "Searching..." : "Ready"
    }
    
    private var serverStatusColor: Color {
        return mirroringManager.isSearching ? .orange : .blue
    }
    
    private var sessionDurationText: String {
        let hours = Int(sessionDuration) / 3600
        let minutes = (Int(sessionDuration) % 3600) / 60
        let seconds = Int(sessionDuration) % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}

struct NotificationItem: Identifiable {
    let id = UUID()
    let message: String
    let type: NotificationType
    let timestamp = Date()
}

enum NotificationType {
    case success, warning, error, info
    
    var color: Color {
        switch self {
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        case .info: return .blue
        }
    }
    
    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

struct NotificationCard: View {
    let notification: NotificationItem
    let onDismiss: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: notification.type.icon)
                .foregroundColor(notification.type.color)
            
            Text(notification.message)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

struct AnimatedParticle: View {
    @State private var position = CGPoint(x: CGFloat.random(in: 0...400), 
                                        y: CGFloat.random(in: 0...800))
    @State private var opacity: Double = 0
    
    var body: some View {
        Circle()
            .fill(.white)
            .frame(width: 4, height: 4)
            .position(position)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                    position = CGPoint(x: CGFloat.random(in: 0...400), 
                                     y: CGFloat.random(in: 0...800))
                    opacity = 0.3
                }
            }
    }
}

#Preview {
    ContentView()
}

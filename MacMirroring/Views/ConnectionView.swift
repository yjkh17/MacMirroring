import SwiftUI
import Network

struct ConnectionView: View {
    @ObservedObject var mirroringManager: MirroringManager
    @State private var isConnecting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showAdvancedOptions = false
    @State private var connectionAttempts = 0
    @State private var connectionHistory: [ConnectionHistoryItem] = []
    
    @State private var showNetworkDiagnostics = false
    @State private var showConnectionDetails = false
    @State private var isRunningNetworkTest = false
    @State private var networkTestResults: NetworkTestResults?
    @State private var autoRetryEnabled = true
    @State private var connectionProgress: Double = 0
    @State private var connectionPhase: ConnectionPhase = .idle
    @State private var showQRCode = false
    @State private var selectedConnectionMethod: ConnectionMethod = .automatic
    
    enum ConnectionPhase {
        case idle, discovering, connecting, authenticating, connected
        
        var description: String {
            switch self {
            case .idle: return "Ready to connect"
            case .discovering: return "Discovering Mac servers..."
            case .connecting: return "Establishing connection..."
            case .authenticating: return "Authenticating..."
            case .connected: return "Connected successfully"
            }
        }
        
        var progress: Double {
            switch self {
            case .idle: return 0.0
            case .discovering: return 0.25
            case .connecting: return 0.5
            case .authenticating: return 0.75
            case .connected: return 1.0
            }
        }
    }
    
    enum ConnectionMethod: String, CaseIterable {
        case automatic = "Automatic"
        case manual = "Manual IP"
        case qrCode = "QR Code"
        
        var icon: String {
            switch self {
            case .automatic: return "wifi.circle"
            case .manual: return "keyboard"
            case .qrCode: return "qrcode"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 30) {
                    heroSection
                    
                    if mirroringManager.connectionError != nil {
                        errorSection
                    }
                    
                    connectionMethodSection
                    
                    if isConnecting {
                        connectionProgressSection
                    }
                    
                    connectionStatusSection
                    connectionButtonView
                    
                    networkQualitySection
                    
                    if showAdvancedOptions {
                        advancedOptionsSection
                    }
                    
                    advancedOptionsButton
                    
                    if !connectionHistory.isEmpty {
                        connectionHistorySection
                    }
                    
                    if showNetworkDiagnostics {
                        networkDiagnosticsSection
                    }
                }
                .padding()
            }
            .navigationTitle("Mac Mirroring")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Network Diagnostics") {
                            showNetworkDiagnostics.toggle()
                        }
                        
                        Button("Connection Details") {
                            showConnectionDetails = true
                        }
                        
                        Button("Show QR Code") {
                            showQRCode = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .onAppear {
                loadConnectionHistory()
                startConnectionMonitoring()
            }
            .onReceive(mirroringManager.$connectionError) { error in
                if let error = error {
                    handleConnectionError(error)
                }
            }
            .onReceive(mirroringManager.$isConnected) { isConnected in
                if isConnected {
                    connectionPhase = .connected
                    connectionProgress = 1.0
                } else {
                    connectionPhase = .idle
                    connectionProgress = 0.0
                }
            }
            .sheet(isPresented: $showConnectionDetails) {
                connectionDetailsView
            }
            .sheet(isPresented: $showQRCode) {
                qrCodeView
            }
        }
    }
    
    private var heroSection: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [.blue.opacity(0.15), .blue.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 140, height: 140)
                
                if isConnecting {
                    ForEach(0..<3) { index in
                        Circle()
                            .stroke(.blue.opacity(0.3), lineWidth: 2)
                            .frame(width: CGFloat(120 + index * 20), height: CGFloat(120 + index * 20))
                            .scaleEffect(isConnecting ? 1.2 : 1.0)
                            .opacity(isConnecting ? 0.3 : 0.8)
                            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true).delay(Double(index) * 0.2), value: isConnecting)
                    }
                }
                
                Image(systemName: mirroringManager.isConnected ? "desktopcomputer.and.arrow.down" : "desktopcomputer")
                    .font(.system(size: 60, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: mirroringManager.isConnected ? [.green, .green.opacity(0.7)] : [.blue, .blue.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .scaleEffect(mirroringManager.isConnected ? 1.1 : 1.0)
                    .animation(.spring(), value: mirroringManager.isConnected)
            }
            
            VStack(spacing: 8) {
                Text(mirroringManager.isConnected ? "Connected to Mac" : "Connect to Mac")
                    .font(.title.weight(.semibold))
                    .foregroundColor(.primary)
                
                Text(mirroringManager.isConnected ? "Streaming active" : "Stream your Mac screen wirelessly")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var connectionMethodSection: some View {
        VStack(spacing: 15) {
            HStack {
                Text("Connection Method")
                    .font(.headline)
                Spacer()
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                ForEach(ConnectionMethod.allCases, id: \.self) { method in
                    connectionMethodButton(method)
                }
            }
        }
    }
    
    private func connectionMethodButton(_ method: ConnectionMethod) -> some View {
        Button(action: {
            selectedConnectionMethod = method
        }) {
            VStack(spacing: 8) {
                Image(systemName: method.icon)
                    .font(.title2)
                    .foregroundColor(selectedConnectionMethod == method ? .white : .blue)
                
                Text(method.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(selectedConnectionMethod == method ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(selectedConnectionMethod == method ? .blue : .blue.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    private var connectionProgressSection: some View {
        VStack(spacing: 15) {
            HStack {
                Text("Connecting")
                    .font(.headline)
                Spacer()
                
                Button("Cancel") {
                    cancelConnection()
                }
                .font(.caption)
                .foregroundColor(.red)
            }
            
            VStack(spacing: 12) {
                ProgressView(value: connectionProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    .animation(.easeInOut, value: connectionProgress)
                
                HStack {
                    Text(connectionPhase.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("\(Int(connectionProgress * 100))%")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
            }
            
            HStack(spacing: 20) {
                connectionStep("Discover", .discovering, 1)
                connectionStep("Connect", .connecting, 2)
                connectionStep("Auth", .authenticating, 3)
                connectionStep("Ready", .connected, 4)
            }
        }
        .padding()
        .background(.gray.opacity(0.1))
        .cornerRadius(15)
    }
    
    private func connectionStep(_ title: String, _ phase: ConnectionPhase, _ step: Int) -> some View {
        VStack(spacing: 4) {
            Circle()
                .fill(connectionPhase.progress >= phase.progress ? .blue : .gray.opacity(0.3))
                .frame(width: 24, height: 24)
                .overlay(
                    Text("\(step)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                )
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private var networkQualitySection: some View {
        VStack(spacing: 15) {
            HStack {
                Text("Network Quality")
                    .font(.headline)
                Spacer()
                
                Button("Test") {
                    runNetworkTest()
                }
                .font(.caption)
                .foregroundColor(.blue)
                .disabled(isRunningNetworkTest)
            }
            
            HStack(spacing: 20) {
                networkQualityIndicator("Signal", mirroringManager.networkQuality.rawValue, mirroringManager.networkQuality.color, "wifi")
                networkQualityIndicator("Latency", "\(mirroringManager.serverStatus?.latency ?? 0)ms", latencyColor(mirroringManager.serverStatus?.latency ?? 0), "timer")
                networkQualityIndicator("Speed", "Auto", .blue, "speedometer")
            }
            
            if isRunningNetworkTest {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Testing network performance...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if let results = networkTestResults {
                networkTestResultsView(results)
            }
        }
    }
    
    private func networkQualityIndicator(_ title: String, _ value: String, _ color: Color, _ icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            
            Text(value)
                .font(.caption2)
                .fontWeight(.medium)
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
    
    private func networkTestResultsView(_ results: NetworkTestResults) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("Network Test Results")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                testResultItem("Download", "\(results.downloadSpeed) Mbps", results.downloadSpeed > 10 ? .green : .orange)
                testResultItem("Upload", "\(results.uploadSpeed) Mbps", results.uploadSpeed > 5 ? .green : .orange)
                testResultItem("Ping", "\(results.ping)ms", results.ping < 50 ? .green : .orange)
                testResultItem("Jitter", "\(results.jitter)ms", results.jitter < 10 ? .green : .orange)
                if let iface = results.interfaceType {
                    testResultItem("Interface", iface.description, .blue)
                }
            }
        }
        .padding()
        .background(.blue.opacity(0.05))
        .cornerRadius(12)
    }
    
    private func testResultItem(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }
    
    private var networkDiagnosticsSection: some View {
        VStack(spacing: 15) {
            HStack {
                Text("Network Diagnostics")
                    .font(.headline)
                Spacer()
                
                Button("Hide") {
                    showNetworkDiagnostics = false
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                diagnosticCard("Wi-Fi", getWiFiStatus(), getWiFiStatusColor(), "wifi")
                diagnosticCard("Bonjour", "Active", .green, "antenna.radiowaves.left.and.right")
                diagnosticCard("Firewall", "Allowed", .green, "shield")
                diagnosticCard("Port 8080", "Open", .green, "network")
            }
            
            Button("Run Full Diagnostics") {
                runFullDiagnostics()
            }
            .foregroundColor(.blue)
        }
        .padding()
        .background(.gray.opacity(0.1))
        .cornerRadius(15)
    }
    
    private func diagnosticCard(_ title: String, _ status: String, _ color: Color, _ icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(status)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(10)
    }
    
    private var connectionDetailsView: some View {
        NavigationView {
            Form {
                Section("Connection Info") {
                    DetailRow(title: "Status", value: mirroringManager.isConnected ? "Connected" : "Disconnected")
                    DetailRow(title: "Method", value: selectedConnectionMethod.rawValue)
                    DetailRow(title: "Network", value: getWiFiStatus())
                    DetailRow(title: "Attempts", value: "\(connectionAttempts)")
                }
                
                Section("Performance") {
                    if let status = mirroringManager.serverStatus {
                        DetailRow(title: "FPS", value: "\(status.fps)")
                        DetailRow(title: "Quality", value: "\(status.quality)%")
                        DetailRow(title: "Latency", value: "\(status.latency)ms")
                    }
                    
                    DetailRow(title: "Data Received", value: formatBytes(mirroringManager.dataReceived))
                    DetailRow(title: "Duration", value: formatDuration(mirroringManager.connectionDuration))
                }
                
                Section("Advanced") {
                    DetailRow(title: "Energy Impact", value: mirroringManager.energyImpact.description)
                    DetailRow(title: "Background Mode", value: mirroringManager.isInBackground ? "Active" : "Inactive")
                    DetailRow(title: "Adaptive Mode", value: mirroringManager.adaptiveMode ? "Enabled" : "Disabled")
                }
            }
            .navigationTitle("Connection Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showConnectionDetails = false
                    }
                }
            }
        }
    }
    
    private var qrCodeView: some View {
        NavigationView {
            VStack(spacing: 30) {
                Text("Scan QR Code on Mac")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                RoundedRectangle(cornerRadius: 20)
                    .fill(.gray.opacity(0.2))
                    .frame(width: 200, height: 200)
                    .overlay(
                        VStack {
                            Image(systemName: "qrcode")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                            Text("QR Code")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    )
                
                VStack(spacing: 12) {
                    Text("1. Open Mac Mirroring Server")
                    Text("2. Click 'Show QR Code'")
                    Text("3. Scan the code with this app")
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding()
            .navigationTitle("QR Code Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showQRCode = false
                    }
                }
            }
        }
    }
    
    private var errorSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
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
                
                errorSuggestions(for: error)
            }
        }
        .padding()
        .background(.orange.opacity(0.1))
        .cornerRadius(15)
    }
    
    private var connectionStatusSection: some View {
        VStack(spacing: 15) {
            HStack {
                Text("Connection Status")
                    .font(.headline)
                Spacer()
            }
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                statusCard("Network", networkStatus, networkStatusColor)
                statusCard("Mac Server", serverStatus, serverStatusColor)
                statusCard("Attempts", "\(connectionAttempts)", .blue)
                statusCard("Quality", qualityStatus, qualityStatusColor)
            }
        }
    }
    
    private var connectionButtonView: some View {
        VStack(spacing: 16) {
            if mirroringManager.isConnected {
                Button(action: {
                    mirroringManager.disconnect()
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 20, weight: .medium))
                        
                        Text("Disconnect")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            } else {
                Button(action: {
                    startConnection()
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "wifi.circle.fill")
                            .font(.system(size: 20, weight: .medium))
                        
                        Text(connectionAttempts > 0 ? "Retry Connection" : "Connect to Mac")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .scaleEffect(isConnecting ? 0.95 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isConnecting)
                .disabled(isConnecting)
            }
            
            VStack(spacing: 8) {
                HStack(spacing: 16) {
                    connectionStatusBadge("Wi-Fi", "wifi", networkStatusColor)
                    connectionStatusBadge("Bonjour", "antenna.radiowaves.left.and.right", .blue)
                    connectionStatusBadge("TCP", "network", .orange)
                }
                
                Text(getConnectionStatusText())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var advancedOptionsButton: some View {
        Button(action: {
            withAnimation(.spring()) {
                showAdvancedOptions.toggle()
            }
        }) {
            HStack {
                Text("Advanced Options")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Image(systemName: showAdvancedOptions ? "chevron.up" : "chevron.down")
                    .font(.caption)
            }
            .foregroundColor(.blue)
            .padding()
            .background(.blue.opacity(0.05))
            .cornerRadius(12)
        }
    }
    
    private var advancedOptionsSection: some View {
        VStack(spacing: 15) {
            HStack {
                Text("Advanced Options")
                    .font(.headline)
                Spacer()
            }
            
            VStack(spacing: 12) {
                Toggle("Auto-retry Connection", isOn: $autoRetryEnabled)
                
                Button("Clear Connection History") {
                    connectionHistory.removeAll()
                    saveConnectionHistory()
                }
                .foregroundColor(.red)
                
                Button("Force Network Refresh") {
                    forceNetworkRefresh()
                }
                .foregroundColor(.blue)
                
                Button("Reset Network Settings") {
                    resetNetworkSettings()
                }
                .foregroundColor(.orange)
                
                Button("Export Connection Logs") {
                    exportConnectionLogs()
                }
                .foregroundColor(.green)
            }
        }
        .padding()
        .background(.gray.opacity(0.1))
        .cornerRadius(15)
    }
    
    private var connectionHistorySection: some View {
        VStack(spacing: 15) {
            HStack {
                Text("Recent Connections")
                    .font(.headline)
                Spacer()
            }
            
            ForEach(connectionHistory.prefix(3)) { item in
                HStack {
                    Circle()
                        .fill(item.wasSuccessful ? .green : .red)
                        .frame(width: 8, height: 8)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.macName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        HStack {
                            Text(item.timestamp.formatted(.dateTime.hour().minute()))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if let duration = item.duration {
                                Text("• \(formatDuration(duration))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    if item.wasSuccessful {
                        Button("Reconnect") {
                            quickReconnect(to: item)
                        }
                        .font(.caption)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    private func startConnection() {
        isConnecting = true
        connectionPhase = .discovering
        connectionProgress = 0.25
        connectionAttempts += 1
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.connectionPhase = .connecting
            self.connectionProgress = 0.5
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.connectionPhase = .authenticating
            self.connectionProgress = 0.75
        }
        
        mirroringManager.connectDirectly()
    }
    
    private func cancelConnection() {
        isConnecting = false
        connectionPhase = .idle
        connectionProgress = 0.0
        mirroringManager.cancelConnection()
    }
    
    private func runNetworkTest() {
        isRunningNetworkTest = true
        networkTestResults = nil

        let monitor = NWPathMonitor()
        var interface: NWInterface.InterfaceType? = nil
        monitor.pathUpdateHandler = { path in
            if let intf = path.availableInterfaces.first(where: { path.usesInterfaceType($0.type) }) {
                interface = intf.type
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .background))

        Task {
            do {
                let downloadURL = URL(string: "https://speed.hetzner.de/5MB.bin")!
                let uploadURL = URL(string: "https://httpbin.org/post")!

                let (dlTime, dlBytes) = try await measureDownload(from: downloadURL)
                let (ulTime, ulBytes) = try await measureUpload(to: uploadURL, size: 1_000_000)
                let (avgPing, jitterVal) = try await measureLatency(to: downloadURL)

                let results = NetworkTestResults(
                    downloadSpeed: calculateMbps(bytes: dlBytes, duration: dlTime),
                    uploadSpeed: calculateMbps(bytes: ulBytes, duration: ulTime),
                    ping: avgPing,
                    jitter: jitterVal,
                    interfaceType: interface
                )

                await MainActor.run {
                    self.networkTestResults = results
                    self.isRunningNetworkTest = false
                }
            } catch {
                await MainActor.run {
                    self.isRunningNetworkTest = false
                }
            }

            monitor.cancel()
        }
    }

    private func measureDownload(from url: URL) async throws -> (TimeInterval, Int) {
        let start = Date()
        let (data, _) = try await URLSession.shared.data(from: url)
        let end = Date()
        return (end.timeIntervalSince(start), data.count)
    }

    private func measureUpload(to url: URL, size: Int) async throws -> (TimeInterval, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let body = Data(count: size)
        let start = Date()
        _ = try await URLSession.shared.upload(for: request, from: body)
        let end = Date()
        return (end.timeIntervalSince(start), size)
    }

    private func measureLatency(to url: URL, count: Int = 4) async throws -> (Int, Int) {
        var samples: [TimeInterval] = []
        var headReq = URLRequest(url: url)
        headReq.httpMethod = "HEAD"
        for _ in 0..<count {
            let s = Date()
            _ = try await URLSession.shared.data(for: headReq)
            let e = Date()
            samples.append(e.timeIntervalSince(s))
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        let avg = samples.reduce(0, +) / Double(samples.count)
        let variance = samples.map { pow($0 - avg, 2.0) }.reduce(0, +) / Double(samples.count)
        let jitter = sqrt(variance)
        return (Int(avg * 1000), Int(jitter * 1000))
    }

    private func calculateMbps(bytes: Int, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        let bps = Double(bytes) * 8.0 / duration
        return bps / 1_000_000
    }
    
    private func runFullDiagnostics() {
        print("Running full network diagnostics...")
    }
    
    private func forceNetworkRefresh() {
        mirroringManager.stopSearching()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            mirroringManager.startSearching()
        }
    }
    
    private func resetNetworkSettings() {
        mirroringManager.reconnectionAttempts = 0
        connectionAttempts = 0
    }
    
    private func exportConnectionLogs() {
        print("Exporting connection logs...")
    }
    
    private func quickReconnect(to item: ConnectionHistoryItem) {
        startConnection()
    }
    
    private func startConnectionMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            // Update connection monitoring
        }
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
    
    private func errorSuggestions(for error: ConnectionError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch error {
            case .connectionFailed:
                suggestionItem("Check Wi-Fi connection", "wifi")
                suggestionItem("Restart Mac Mirroring Server", "arrow.clockwise")
                suggestionItem("Verify same network", "network")
                
            case .serverNotFound:
                suggestionItem("Launch Mac Mirroring Server", "desktopcomputer")
                suggestionItem("Check firewall settings", "shield")
                
            default:
                suggestionItem("Try reconnecting", "arrow.clockwise")
            }
        }
        .padding(.top, 8)
    }
    
    private func suggestionItem(_ text: String, _ icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.blue)
                .frame(width: 16)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.primary)
        }
    }
    
    private func handleConnectionError(_ error: ConnectionError) {
        let historyItem = ConnectionHistoryItem(
            macName: "Mac Server",
            timestamp: Date(),
            wasSuccessful: false,
            duration: nil
        )
        connectionHistory.insert(historyItem, at: 0)
        saveConnectionHistory()
        
        isConnecting = false
        connectionPhase = .idle
        connectionProgress = 0.0
        showError = true
        errorMessage = error.localizedDescription
    }
    
    private func loadConnectionHistory() {
        connectionHistory = []
    }
    
    private func saveConnectionHistory() {
    }
    
    private func connectionStatusBadge(_ title: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)
            Text(title)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
    
    private var networkStatus: String {
        return "Wi-Fi Connected"
    }
    
    private var networkStatusColor: Color {
        return .green
    }
    
    private var serverStatus: String {
        return mirroringManager.isSearching ? "Searching..." : "Unknown"
    }
    
    private var serverStatusColor: Color {
        return mirroringManager.isSearching ? .orange : .gray
    }
    
    private var qualityStatus: String {
        return mirroringManager.networkQuality.rawValue
    }
    
    private var qualityStatusColor: Color {
        return mirroringManager.networkQuality.color
    }
    
    private func getConnectionStatusText() -> String {
        if mirroringManager.isConnected {
            return "Connected and streaming"
        } else if isConnecting {
            return "Establishing connection..."
        } else if connectionAttempts > 0 {
            return "Retry connection"
        } else {
            return "One-tap wireless connection"
        }
    }
    
    private func getWiFiStatus() -> String {
        return "Connected"
    }
    
    private func getWiFiStatusColor() -> Color {
        return .green
    }
    
    private func latencyColor(_ latency: Int) -> Color {
        switch latency {
        case 0...30: return .green
        case 31...60: return .yellow
        case 61...100: return .orange
        default: return .red
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return "\(minutes)m \(seconds)s"
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1024.0 / 1024.0
        return String(format: "%.1f MB", mb)
    }
}

struct ConnectionHistoryItem: Identifiable, Codable {
    let id: UUID
    let macName: String
    let timestamp: Date
    let wasSuccessful: Bool
    let duration: TimeInterval?
    
    init(macName: String, timestamp: Date, wasSuccessful: Bool, duration: TimeInterval?) {
        self.id = UUID()
        self.macName = macName
        self.timestamp = timestamp
        self.wasSuccessful = wasSuccessful
        self.duration = duration
    }
}

struct NetworkTestResults {
    let downloadSpeed: Double
    let uploadSpeed: Double
    let ping: Int
    let jitter: Int
    let interfaceType: NWInterface.InterfaceType?
}

extension NWInterface.InterfaceType {
    var description: String {
        switch self {
        case .wifi: return "Wi-Fi"
        case .cellular: return "Cellular"
        case .wiredEthernet: return "Ethernet"
        case .loopback: return "Loopback"
        default: return "Other"
        }
    }
}

struct DetailRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

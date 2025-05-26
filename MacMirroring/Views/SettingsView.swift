import SwiftUI
import Network

struct SettingsView: View {
    @ObservedObject var streamingSettings: StreamingSettings
    @ObservedObject var mirroringManager: MirroringManager
    @Binding var isPresented: Bool
    
    @State private var selectedTab = 0
    @State private var showingResetAlert = false
    @State private var showingExportSheet = false
    @State private var isRunningDiagnostics = false
    @State private var diagnosticResults: [String] = []
    
    private let tabs = ["General", "Advanced", "Diagnostics"]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Enhanced header with connection status
                headerView
                
                // Tab selector
                Picker("Settings Tab", selection: $selectedTab) {
                    ForEach(0..<tabs.count, id: \.self) { index in
                        Text(tabs[index]).tag(index)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                // Tab content
                TabView(selection: $selectedTab) {
                    generalSettingsView.tag(0)
                    advancedSettingsView.tag(1)
                    diagnosticsView.tag(2)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Reset Settings", action: {
                            showingResetAlert = true
                        })
                        
                        Button("Export Settings", action: {
                            showingExportSheet = true
                        })
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .alert("Reset Settings", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetToDefaults()
            }
        } message: {
            Text("This will reset all settings to their default values.")
        }
        .sheet(isPresented: $showingExportSheet) {
            exportSettingsView
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: mirroringManager.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(mirroringManager.isConnected ? .green : .red)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(mirroringManager.isConnected ? "Connected to Mac" : "Not Connected")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    if let serverStatus = mirroringManager.serverStatus {
                        Text("\(serverStatus.fps) FPS • \(serverStatus.quality)% Quality • \(serverStatus.latency)ms")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            Divider()
        }
        .background(.ultraThinMaterial)
    }
    
    private var generalSettingsView: some View {
        Form {
            Section("Streaming Quality") {
                VStack(spacing: 16) {
                    // Streaming mode picker
                    HStack {
                        Text("Mode")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Picker("Streaming Mode", selection: $streamingSettings.streamingMode) {
                            ForEach(StreamingMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .onChange(of: streamingSettings.streamingMode) { _, newValue in
                            // Update audio quality based on streaming mode
                            streamingSettings.audioQuality = newValue.preferredAudioQuality
                            streamingSettings.sendSettingsToServer(via: mirroringManager.connection)
                            
                            // Haptic feedback
                            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                            impactFeedback.impactOccurred()
                        }
                    }
                    
                    // Mode description
                    Text(streamingSettings.streamingMode.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider()
                    
                    // Quick presets
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quick Presets")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                            ForEach(StreamingPreset.allCases) { preset in
                                presetButton(preset)
                            }
                        }
                    }
                }
            }
            
            Section("Capture Source") {
                VStack(spacing: 16) {
                    // Capture source picker
                    HStack {
                        Text("Source")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Picker("Capture Source", selection: $streamingSettings.captureSource) {
                            ForEach(CaptureSource.allCases) { source in
                                Text(source.rawValue).tag(source)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .onChange(of: streamingSettings.captureSource) { oldValue, newValue in
                            streamingSettings.sendSettingsToServer(via: mirroringManager.connection)
                            
                            if newValue == .singleWindow && streamingSettings.availableWindows.isEmpty {
                                streamingSettings.requestWindowsAndDisplays(via: mirroringManager.connection)
                            }
                        }
                    }
                    
                    // Source description
                    Text(streamingSettings.captureSource.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Window/Display selection
                    if streamingSettings.captureSource == .singleWindow {
                        windowSelectionView
                    } else {
                        displaySelectionView
                    }
                }
            }
            
            Section("Audio Settings") {
                VStack(spacing: 16) {
                    // Audio toggle
                    HStack {
                        Image(systemName: streamingSettings.isAudioEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .foregroundColor(streamingSettings.isAudioEnabled ? .green : .red)
                            .font(.title2)
                        
                        VStack(alignment: .leading) {
                            Text("Audio Streaming")
                                .font(.headline)
                            
                            Text(streamingSettings.isAudioEnabled ? "Mac audio is being streamed" : "Audio streaming is disabled")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $streamingSettings.isAudioEnabled)
                            .onChange(of: streamingSettings.isAudioEnabled) { _, newValue in
                                if newValue {
                                    streamingSettings.audioQuality = streamingSettings.streamingMode.preferredAudioQuality
                                }
                                streamingSettings.sendSettingsToServer(via: mirroringManager.connection)
                                mirroringManager.isAudioEnabled = newValue
                                
                                if newValue && mirroringManager.isConnected {
                                    // Restart audio playback
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        // Audio will be handled by MirroringManager
                                    }
                                }
                            }
                    }
                    
                    if streamingSettings.isAudioEnabled {
                        Divider()
                        
                        // Audio quality slider
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Audio Quality")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Spacer()
                                
                                Text("\(Int(streamingSettings.audioQuality * 100))%")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                                    .fontWeight(.semibold)
                            }
                            
                            HStack {
                                Image(systemName: "speaker.wave.1")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                                
                                Slider(value: $streamingSettings.audioQuality, in: 0.1...1.0, step: 0.1)
                                    .onChange(of: streamingSettings.audioQuality) { _, newValue in
                                        streamingSettings.sendSettingsToServer(via: mirroringManager.connection)
                                    }
                                
                                Image(systemName: "speaker.wave.3")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            
                            Text(audioQualityDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        // Audio latency settings
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Audio Latency")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Spacer()
                                
                                Text("\(Int(streamingSettings.audioLatency * 1000))ms")
                                    .font(.subheadline)
                                    .foregroundColor(.orange)
                                    .fontWeight(.semibold)
                            }
                            
                            HStack {
                                Image(systemName: "bolt.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                
                                Slider(value: $streamingSettings.audioLatency, in: 0.01...0.1, step: 0.005)
                                    .onChange(of: streamingSettings.audioLatency) { _, newValue in
                                        streamingSettings.sendSettingsToServer(via: mirroringManager.connection)
                                    }
                                
                                Image(systemName: "hifispeaker")
                                    .foregroundColor(.blue)
                                    .font(.caption)
                            }
                            
                            Text(audioLatencyDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Audio status indicators
                        if let serverStatus = mirroringManager.serverStatus {
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Audio Status")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                HStack {
                                    Label("Server Audio", systemImage: serverStatus.audioEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(serverStatus.audioEnabled ? .green : .red)
                                        .font(.caption)
                                    
                                    Spacer()
                                    
                                    Label("\(serverStatus.audioLatency)ms", systemImage: "timer")
                                        .foregroundColor(serverStatus.audioLatency < 50 ? .green : serverStatus.audioLatency < 100 ? .orange : .red)
                                        .font(.caption)
                                }
                                
                                HStack {
                                    Label("Buffer Health", systemImage: "waveform")
                                        .foregroundColor(.blue)
                                        .font(.caption)
                                    
                                    Spacer()
                                    
                                    Text(mirroringManager.isAudioEnabled && mirroringManager.isConnected ? "Good" : "Inactive")
                                        .font(.caption)
                                        .foregroundColor(mirroringManager.isAudioEnabled && mirroringManager.isConnected ? .green : .orange)
                                }
                                
                                // Real-time audio format info
                                HStack {
                                    Label("Format", systemImage: "music.note")
                                        .foregroundColor(.purple)
                                        .font(.caption)
                                    
                                    Spacer()
                                    
                                    Text("44.1kHz, 16-bit, Stereo")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                // Audio quality indicator
                                HStack {
                                    Label("Quality", systemImage: "speaker.wave.2")
                                        .foregroundColor(.cyan)
                                        .font(.caption)
                                    
                                    Spacer()
                                    
                                    Text("\(Int(streamingSettings.audioQuality * 100))%")
                                        .font(.caption)
                                        .foregroundColor(.cyan)
                                        .fontWeight(.medium)
                                }
                            }
                        }
                    }
                }
            }
            
            // Audio presets section
            Section("Audio Presets") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                    audioPresetButton("Gaming", "gamecontroller", .green) {
                        streamingSettings.audioQuality = 0.6
                        streamingSettings.audioLatency = 0.015
                        streamingSettings.sendSettingsToServer(via: mirroringManager.connection)
                    }
                    
                    audioPresetButton("Music", "music.note", .blue) {
                        streamingSettings.audioQuality = 1.0
                        streamingSettings.audioLatency = 0.03
                        streamingSettings.sendSettingsToServer(via: mirroringManager.connection)
                    }
                    
                    audioPresetButton("Calls", "phone", .purple) {
                        streamingSettings.audioQuality = 0.5
                        streamingSettings.audioLatency = 0.02
                        streamingSettings.sendSettingsToServer(via: mirroringManager.connection)
                    }
                    
                    audioPresetButton("Default", "speaker.2", .gray) {
                        streamingSettings.audioQuality = 0.8
                        streamingSettings.audioLatency = 0.02
                        streamingSettings.sendSettingsToServer(via: mirroringManager.connection)
                    }
                }
            }
        }
    }
    
    private var windowSelectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Available Windows")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Refresh") {
                    streamingSettings.requestWindowsAndDisplays(via: mirroringManager.connection)
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            if streamingSettings.isLoadingWindowsDisplays {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading windows...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if streamingSettings.availableWindows.isEmpty {
                Text("No windows available")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(streamingSettings.availableWindows.prefix(5), id: \.id) { window in
                    windowRow(window)
                }
                
                if streamingSettings.availableWindows.count > 5 {
                    Text("... and \(streamingSettings.availableWindows.count - 5) more")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var displaySelectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Available Displays")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Refresh") {
                    streamingSettings.requestWindowsAndDisplays(via: mirroringManager.connection)
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            if streamingSettings.isLoadingWindowsDisplays {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading displays...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if streamingSettings.availableDisplays.isEmpty {
                Text("No displays available")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(streamingSettings.availableDisplays, id: \.id) { display in
                    displayRow(display)
                }
            }
        }
    }
    
    private func windowRow(_ window: MacWindow) -> some View {
        Button(action: {
            streamingSettings.selectedWindow = window
            streamingSettings.selectedWindowName = "\(window.ownerName): \(window.title)"
            streamingSettings.sendSettingsToServer(via: mirroringManager.connection)
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(window.title.isEmpty ? "Untitled Window" : window.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(window.ownerName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if streamingSettings.selectedWindow?.id == window.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
    
    private func displayRow(_ display: MacDisplay) -> some View {
        Button(action: {
            streamingSettings.selectedDisplay = display
            streamingSettings.selectedDisplayName = display.name
            streamingSettings.sendSettingsToServer(via: mirroringManager.connection)
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(display.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text("\(display.width) × \(display.height)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if streamingSettings.selectedDisplay?.id == display.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
    
    private var advancedSettingsView: some View {
        Form {
            Section("Performance") {
                VStack(spacing: 12) {
                    performanceMetric("Average FPS", "\(String(format: "%.1f", mirroringManager.averageFPS))", .blue)
                    performanceMetric("Data Received", formatBytes(mirroringManager.dataReceived), .green)
                    performanceMetric("Network Quality", mirroringManager.networkQuality.rawValue, mirroringManager.networkQuality.color)
                    performanceMetric("Energy Impact", mirroringManager.energyImpact.description, mirroringManager.energyImpact.color)
                }
            }
            
            Section("Network") {
                VStack(spacing: 12) {
                    networkMetric("Bandwidth", "\(String(format: "%.1f", mirroringManager.networkMetrics.bandwidth)) Mbps", .blue)
                    networkMetric("Packet Loss", "\(String(format: "%.1f", mirroringManager.networkMetrics.packetLoss))%", .orange)
                    networkMetric("Jitter", "\(String(format: "%.1f", mirroringManager.networkMetrics.jitter)) ms", .purple)
                    networkMetric("RTT", "\(String(format: "%.0f", mirroringManager.networkMetrics.rtt)) ms", .red)
                    networkMetric("Quality Score", "\(Int(mirroringManager.networkMetrics.qualityScore))/100", qualityScoreColor)
                }
            }
            
            Section("Adaptive Settings") {
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Adaptive Mode")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text("Automatically adjust quality based on performance")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $mirroringManager.adaptiveMode)
                    }
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Background Mode")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text(mirroringManager.isInBackground ? "App is in background" : "App is active")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: mirroringManager.isInBackground ? "moon.fill" : "sun.max.fill")
                            .foregroundColor(mirroringManager.isInBackground ? .blue : .orange)
                    }
                }
            }
        }
    }
    
    private var diagnosticsView: some View {
        Form {
            Section("Connection Analysis") {
                VStack(spacing: 12) {
                    if isRunningDiagnostics {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Running diagnostics...")
                                .font(.subheadline)
                        }
                    } else {
                        Button("Run Network Diagnostics") {
                            runNetworkDiagnostics()
                        }
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                    }
                    
                    if !diagnosticResults.isEmpty {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Diagnostic Results")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            ForEach(diagnosticResults, id: \.self) { result in
                                Text(result)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            
            troubleshootingSection
            advancedTroubleshootingSection
        }
    }
    
    private var troubleshootingSection: some View {
        Section {
            VStack(spacing: 16) {
                troubleshootingTip(
                    "Connection Issues",
                    "Ensure both devices are on the same Wi-Fi network",
                    "wifi.exclamationmark"
                )
                
                troubleshootingTip(
                    "Audio Problems",
                    "Check audio settings and system volume levels",
                    "speaker.slash"
                )
                
                troubleshootingTip(
                    "Performance Issues",
                    "Try reducing quality or switching to Performance mode",
                    "speedometer"
                )
                
                troubleshootingTip(
                    "High Latency",
                    "Move closer to router or reduce network congestion",
                    "network.badge.shield.half.filled"
                )
            }
        } header: {
            Text("Troubleshooting")
        }
    }
    
    private var advancedTroubleshootingSection: some View {
        Section {
            VStack(spacing: 16) {
                troubleshootingTip(
                    "Audio Not Working",
                    "Check Mac System Preferences → Security & Privacy → Microphone permissions",
                    "mic.slash"
                )
                
                troubleshootingTip(
                    "Audio Delay/Echo",
                    "Reduce audio latency in settings or use Gaming preset",
                    "speaker.wave.1"
                )
                
                troubleshootingTip(
                    "Choppy Audio",
                    "Switch to Performance mode or check Wi-Fi signal strength",
                    "wifi.slash"
                )
                
                troubleshootingTip(
                    "Mac Not Found",
                    "Ensure both devices are on same network and Mac firewall allows connections",
                    "network.slash"
                )
            }
        } header: {
            Text("Advanced Troubleshooting")
        }
    }
    
    private var exportSettingsView: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Export Settings")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Export your current settings to share or backup")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Spacer()
                
                Button("Export as JSON") {
                    // Export functionality
                    showingExportSheet = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button("Cancel") {
                    showingExportSheet = false
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func presetButton(_ preset: StreamingPreset) -> some View {
        Button(action: {
            streamingSettings.applyPreset(preset)
            streamingSettings.sendSettingsToServer(via: mirroringManager.connection)
            
            // Haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        }) {
            VStack(spacing: 8) {
                Image(systemName: preset.icon)
                    .font(.title2)
                    .foregroundColor(.blue)
                
                Text(preset.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.blue.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    private func performanceMetric(_ title: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }
    
    private func networkMetric(_ title: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }
    
    private func troubleshootingTip(_ title: String, _ description: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.orange)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(.orange.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var qualityScoreColor: Color {
        let score = mirroringManager.networkMetrics.qualityScore
        if score >= 80 { return .green }
        else if score >= 60 { return .yellow }
        else if score >= 40 { return .orange }
        else { return .red }
    }
    
    private var audioQualityDescription: String {
        switch streamingSettings.audioQuality {
        case 0.1...0.3:
            return "Low quality - minimal bandwidth usage"
        case 0.3...0.6:
            return "Good quality - balanced performance"
        case 0.6...0.8:
            return "High quality - excellent audio fidelity"
        case 0.8...1.0:
            return "Maximum quality - best audio experience"
        default:
            return "Custom quality setting"
        }
    }
    
    private var audioLatencyDescription: String {
        switch streamingSettings.audioLatency {
        case 0.01...0.02:
            return "Ultra-low latency - ideal for gaming and interactive use"
        case 0.02...0.04:
            return "Low latency - good for general use and calls"
        case 0.04...0.07:
            return "Moderate latency - acceptable for media consumption"
        case 0.07...0.1:
            return "Higher latency - prioritizes audio quality over speed"
        default:
            return "Custom latency setting"
        }
    }
    
    private func audioPresetButton(_ title: String, _ icon: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: {
            action()
            // Haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        }) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1024.0 / 1024.0
        return String(format: "%.1f MB", mb)
    }
    
    private func runNetworkDiagnostics() {
        isRunningDiagnostics = true
        diagnosticResults.removeAll()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.diagnosticResults = [
                "Network latency: \(Int(self.mirroringManager.networkMetrics.rtt))ms",
                "Bandwidth: \(String(format: "%.1f", self.mirroringManager.networkMetrics.bandwidth)) Mbps",
                "Packet loss: \(String(format: "%.1f", self.mirroringManager.networkMetrics.packetLoss))%",
                "Connection quality: \(self.mirroringManager.networkQuality.rawValue)",
                "Audio latency: \(Int(self.mirroringManager.audioLatency * 1000))ms"
            ]
            self.isRunningDiagnostics = false
        }
    }
    
    private func resetToDefaults() {
        streamingSettings.streamingMode = .balanced
        streamingSettings.captureSource = .fullDisplay
        streamingSettings.isAudioEnabled = true
        streamingSettings.audioQuality = 0.8
        streamingSettings.audioLatency = 0.02
        
        streamingSettings.sendSettingsToServer(via: mirroringManager.connection)
    }
}

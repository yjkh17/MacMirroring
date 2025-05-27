import SwiftUI

struct ServerContentView: View {
    @EnvironmentObject var multipeerCapture: MultipeerCapture
    @State private var showAdvancedSettings = false
    
    var body: some View {
        VStack(spacing: 20) {
            headerSection
            
            statusSection
            
            settingsSection
            
            if showAdvancedSettings {
                advancedSettingsSection
            }
            
            controlsSection
            
            Spacer()
        }
        .padding()
        .frame(minWidth: 400, minHeight: 500)
    }
    
    private var headerSection: some View {
        VStack {
            Text("Mac Mirroring Server")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Ready to stream to iPhone")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var statusSection: some View {
        GroupBox("Connection Status") {
            VStack(spacing: 12) {
                HStack {
                    Circle()
                        .fill(multipeerCapture.isAdvertising ? .green : .red)
                        .frame(width: 12, height: 12)
                    
                    Text(multipeerCapture.isAdvertising ? "Advertising" : "Not Advertising")
                        .fontWeight(.medium)
                    
                    Spacer()
                }
                
                HStack {
                    Text("Connected Devices:")
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text("\(multipeerCapture.connectedPeers.count)")
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
                
                if !multipeerCapture.connectedPeers.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(multipeerCapture.connectedPeers, id: \.displayName) { peer in
                            HStack {
                                Image(systemName: "iphone")
                                    .foregroundColor(.blue)
                                Text(peer.displayName)
                                    .font(.caption)
                                Spacer()
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                
                HStack {
                    Text("Capturing:")
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text(multipeerCapture.isCapturing ? "Active" : "Inactive")
                        .fontWeight(.bold)
                        .foregroundColor(multipeerCapture.isCapturing ? .green : .orange)
                }
            }
        }
    }
    
    private var settingsSection: some View {
        GroupBox("Streaming Settings") {
            VStack(spacing: 16) {
                HStack {
                    Text("Frame Rate:")
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Picker("FPS", selection: Binding(
                        get: { multipeerCapture.currentFPS },
                        set: { (newFPS: Int) in
                            multipeerCapture.updateStreamingSettings(
                                fps: newFPS,
                                quality: multipeerCapture.streamingQuality
                            )
                        }
                    )) {
                        Text("15 FPS").tag(15)
                        Text("30 FPS").tag(30)
                        Text("45 FPS").tag(45)
                        Text("60 FPS").tag(60)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
                
                HStack {
                    Text("Quality:")
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Picker("Quality", selection: Binding(
                        get: { multipeerCapture.streamingQuality },
                        set: { (newQuality: Int) in
                            multipeerCapture.updateStreamingSettings(
                                fps: multipeerCapture.currentFPS,
                                quality: newQuality
                            )
                        }
                    )) {
                        Text("30%").tag(30)
                        Text("50%").tag(50)
                        Text("70%").tag(70)
                        Text("90%").tag(90)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }
                
                HStack {
                    Text("Capture Mode:")
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Picker("Mode", selection: $multipeerCapture.captureMode) {
                        Text("Full Display").tag(MultipeerCapture.CaptureMode.fullDisplay)
                        Text("Single Window").tag(MultipeerCapture.CaptureMode.singleWindow)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
            }
        }
    }
    
    private var advancedSettingsSection: some View {
        GroupBox("Advanced Settings") {
            VStack(spacing: 12) {
                HStack {
                    Text("Network Latency:")
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text("\(multipeerCapture.networkLatency)ms")
                        .foregroundColor(.secondary)
                }
                
                Button("Reset to Defaults") {
                    multipeerCapture.updateStreamingSettings(fps: 30, quality: 70)
                }
                .buttonStyle(.bordered)
            }
        }
    }
    
    private var controlsSection: some View {
        HStack {
            Button(multipeerCapture.isAdvertising ? "Stop Server" : "Start Server") {
                if multipeerCapture.isAdvertising {
                    multipeerCapture.stopAdvertising()
                } else {
                    multipeerCapture.startAdvertising()
                }
            }
            .buttonStyle(.borderedProminent)
            
            Button("Advanced") {
                showAdvancedSettings.toggle()
            }
            .buttonStyle(.bordered)
        }
    }
}

#Preview {
    ServerContentView()
        .environmentObject(MultipeerCapture())
}
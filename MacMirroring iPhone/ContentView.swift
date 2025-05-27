import SwiftUI
import Network

// MARK: - Type Alias for Compatibility
typealias MirroringManager = MultipeerDisplay

struct ContentView: View {
    @StateObject private var mirroringManager = MultipeerDisplay()
    @StateObject private var streamingSettings = StreamingSettings()
    
    var body: some View {
        VStack(spacing: 30) {
            Text("Mac Mirroring")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            if mirroringManager.isConnected {
                VStack {
                    Text("Connected to Mac")
                        .font(.title2)
                        .foregroundColor(.green)
                    
                    if let screenData = mirroringManager.screenData,
                       let uiImage = UIImage(data: screenData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 300)
                            .cornerRadius(12)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.gray.opacity(0.3))
                            .frame(height: 200)
                            .overlay(
                                Text("Waiting for screen data...")
                                    .foregroundColor(.secondary)
                            )
                    }
                    
                    Button("Disconnect") {
                        mirroringManager.disconnect()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            } else {
                VStack(spacing: 20) {
                    if mirroringManager.isSearching {
                        ProgressView("Searching for Mac...")
                    } else {
                        Text("Ready to connect")
                            .foregroundColor(.secondary)
                    }
                    
                    if let error = mirroringManager.connectionError {
                        Text("Error: \(error.localizedDescription)")
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                    
                    Button("Connect to Mac") {
                        mirroringManager.connectDirectly()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(mirroringManager.isSearching)
                }
            }
            
            // Status info
            if let status = mirroringManager.serverStatus {
                VStack {
                    Text("Performance")
                        .font(.headline)
                    
                    HStack {
                        VStack {
                            Text("\(status.fps)")
                                .font(.title3)
                            Text("FPS")
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        
                        VStack {
                            Text("\(status.quality)%")
                                .font(.title3)
                            Text("Quality")
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        
                        VStack {
                            Text("\(status.latency)ms")
                                .font(.title3)
                            Text("Latency")
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding()
                    .background(.gray.opacity(0.1))
                    .cornerRadius(12)
                }
            }
        }
        .padding()
        .onAppear {
            mirroringManager.setStreamingSettings(streamingSettings)
        }
    }
}

#Preview {
    ContentView()
}

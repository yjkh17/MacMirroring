import SwiftUI

struct ContentView: View {
    @StateObject private var server = MirroringServer()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Mac Mirroring Server")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Image(systemName: "desktopcomputer")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            if server.isRunning {
                VStack(spacing: 10) {
                    Text("Server Running")
                        .font(.title2)
                        .foregroundColor(.green)
                    
                    Text("Broadcasting _macmirror._tcp service")
                        .foregroundColor(.secondary)
                    
                    if server.connectedClients > 0 {
                        Text("\(server.connectedClients) iPhone(s) connected")
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                    } else {
                        Text("Waiting for iPhone connections...")
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("Server Stopped")
                    .font(.title2)
                    .foregroundColor(.red)
            }
            
            Button(server.isRunning ? "Stop Server" : "Start Server") {
                if server.isRunning {
                    server.stop()
                } else {
                    server.start()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
    }
}

#Preview {
    ContentView()
}

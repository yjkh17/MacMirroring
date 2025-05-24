import SwiftUI
import Network

struct ContentView: View {
    @StateObject private var mirroringManager = MirroringManager()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Mac Mirroring")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                if mirroringManager.isConnected {
                    MacScreenView(mirroringManager: mirroringManager)
                } else {
                    ConnectionView(mirroringManager: mirroringManager)
                }
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
}

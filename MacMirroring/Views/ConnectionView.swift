import SwiftUI

struct ConnectionView: View {
    @ObservedObject var mirroringManager: MirroringManager
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            Text("Connect to your Mac")
                .font(.title2)
                .fontWeight(.medium)
            
            if mirroringManager.isSearching {
                ProgressView("Searching for Macs...")
                    .progressViewStyle(CircularProgressViewStyle())
            } else {
                Button("Search for Macs") {
                    mirroringManager.startSearching()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            
            if !mirroringManager.availableMacs.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Available Macs:")
                        .font(.headline)
                    
                    ForEach(mirroringManager.availableMacs) { mac in
                        Button(action: {
                            mirroringManager.connectToMac(mac)
                        }) {
                            HStack {
                                Image(systemName: "desktopcomputer")
                                Text(mac.name)
                                Spacer()
                                Image(systemName: "arrow.right.circle.fill")
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onDisappear {
            mirroringManager.stopSearching()
        }
    }
}
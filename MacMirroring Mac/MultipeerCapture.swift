import MultipeerConnectivity

class MultipeerCapture: NSObject {
    private let peerID = MCPeerID(displayName: Host.current().localizedName ?? "Mac")
    private var session: MCSession?
}

import MultipeerConnectivity

class MultipeerDisplay: NSObject, ObservableObject {
    private let peerID = MCPeerID(displayName: UIDevice.current.name)
    private var session: MCSession?
}

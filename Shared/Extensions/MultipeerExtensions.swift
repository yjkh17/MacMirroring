import MultipeerConnectivity

extension MCSessionState {
    var isConnected: Bool {
        self == .connected
    }
}

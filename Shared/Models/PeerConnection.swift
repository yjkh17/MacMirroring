import Foundation

struct PeerConnection: Identifiable {
    let id = UUID()
    var name: String
    var isTrusted: Bool
}

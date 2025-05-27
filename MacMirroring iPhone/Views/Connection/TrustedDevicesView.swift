import SwiftUI

struct TrustedDevicesView: View {
    var trustedDevices: [PeerConnection]
    var body: some View {
        List(trustedDevices) { peer in
            Text(peer.name)
        }
    }
}

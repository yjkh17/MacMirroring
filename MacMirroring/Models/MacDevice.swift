import Foundation
import Network

struct MacDevice: Identifiable {
    let id = UUID()
    let name: String
    let type: String
    let domain: String
    let endpoint: NWEndpoint
}
import Foundation
import Network

struct MacDevice: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let type: String
    let domain: String
    let endpoint: NWEndpoint
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(type)
        hasher.combine(domain)
    }
    
    static func == (lhs: MacDevice, rhs: MacDevice) -> Bool {
        return lhs.name == rhs.name && lhs.type == rhs.type && lhs.domain == rhs.domain
    }
}

// MARK: - Shared Enums and Types
enum NetworkQuality: String, CaseIterable {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"
    case unknown = "Unknown"
    
    var color: Color {
        switch self {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .yellow
        case .poor: return .red
        case .unknown: return .gray
        }
    }
}

enum ConnectionError: Error, Identifiable, Equatable {
    case connectionFailed(Error)
    case connectionCancelled
    case connectionWaiting(Error)
    case networkUnavailable
    case serverNotFound
    case authenticationFailed
    
    var id: String {
        switch self {
        case .connectionFailed: return "connection_failed"
        case .connectionCancelled: return "connection_cancelled"
        case .connectionWaiting: return "connection_waiting"
        case .networkUnavailable: return "network_unavailable"
        case .serverNotFound: return "server_not_found"
        case .authenticationFailed: return "authentication_failed"
        }
    }
    
    var localizedDescription: String {
        switch self {
        case .connectionFailed(let error):
            return "Connection failed: \(error.localizedDescription)"
        case .connectionCancelled:
            return "Connection was cancelled"
        case .connectionWaiting(let error):
            return "Connection waiting: \(error.localizedDescription)"
        case .networkUnavailable:
            return "Network is unavailable"
        case .serverNotFound:
            return "Mac server not found"
        case .authenticationFailed:
            return "Authentication failed"
        }
    }
    
    static func == (lhs: ConnectionError, rhs: ConnectionError) -> Bool {
        switch (lhs, rhs) {
        case (.connectionFailed(let lhsError), .connectionFailed(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        case (.connectionCancelled, .connectionCancelled):
            return true
        case (.connectionWaiting(let lhsError), .connectionWaiting(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        case (.networkUnavailable, .networkUnavailable):
            return true
        case (.serverNotFound, .serverNotFound):
            return true
        case (.authenticationFailed, .authenticationFailed):
            return true
        default:
            return false
        }
    }
}

enum EnergyImpact: String, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case veryHigh = "Very High"
    
    var color: Color {
        switch self {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .orange
        case .veryHigh: return .red
        }
    }
    
    var description: String {
        return rawValue
    }
}

struct ServerStatusInfo {
    let fps: Int
    let quality: Int
    let latency: Int
    let audioEnabled: Bool
    let audioLatency: Int
}

// MARK: - Import SwiftUI for Color
import SwiftUI

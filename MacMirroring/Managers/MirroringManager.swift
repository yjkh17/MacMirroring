import Foundation
import Network
import Combine

class MirroringManager: ObservableObject {
    @Published var isConnected = false
    @Published var isSearching = false
    @Published var availableMacs: [MacDevice] = []
    @Published var screenData: Data?
    
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var receivedData = Data()
    private var expectedLength: UInt32?
    
    init() {
        setupBrowser()
    }
    
    private func setupBrowser() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        
        let browserDescriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(
            type: "_macmirror._tcp",
            domain: "local."
        )
        
        browser = NWBrowser(for: browserDescriptor, using: parameters)
        
        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            DispatchQueue.main.async {
                self?.handleBrowseResults(results)
            }
        }
    }
    
    func startSearching() {
        isSearching = true
        availableMacs.removeAll()
        browser?.start(queue: .main)
    }
    
    func stopSearching() {
        isSearching = false
        browser?.cancel()
    }
    
    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        availableMacs = results.compactMap { result in
            switch result.endpoint {
            case .service(let name, let type, let domain, _):
                return MacDevice(name: name, type: type, domain: domain, endpoint: result.endpoint)
            default:
                return nil
            }
        }
    }
    
    func connectToMac(_ mac: MacDevice) {
        let connection = NWConnection(to: mac.endpoint, using: .tcp)
        self.connection = connection
        
        connection.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isConnected = true
                    self?.startReceivingScreenData()
                case .failed, .cancelled:
                    self?.isConnected = false
                case .waiting(let error):
                    print("Connection waiting: \(error)")
                default:
                    break
                }
            }
        }
        
        connection.start(queue: .main)
    }
    
    private func startReceivingScreenData() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                self?.processReceivedData(data)
            }
            
            if let error = error {
                print("Receive error: \(error)")
                return
            }
            
            if !isComplete {
                self?.startReceivingScreenData()
            }
        }
    }
    
    private func processReceivedData(_ data: Data) {
        receivedData.append(data)
        
        while receivedData.count >= 4 {
            if expectedLength == nil {
                let lengthBytes = receivedData.prefix(4)
                var lengthValue: UInt32 = 0
                _ = lengthBytes.withUnsafeBytes { bytes in
                    memcpy(&lengthValue, bytes.baseAddress!, 4)
                }
                expectedLength = UInt32(bigEndian: lengthValue)
                receivedData.removeFirst(4)
            }
            
            if let expectedLength = expectedLength, receivedData.count >= expectedLength {
                let imageData = receivedData.prefix(Int(expectedLength))
                receivedData.removeFirst(Int(expectedLength))
                
                DispatchQueue.main.async {
                    self.screenData = Data(imageData)
                }
                
                self.expectedLength = nil
            } else {
                break
            }
        }
    }
    
    func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
        screenData = nil
        receivedData.removeAll()
        expectedLength = nil
    }
}

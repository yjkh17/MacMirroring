import SwiftUI

struct MacScreenView: View {
    @ObservedObject var mirroringManager: MirroringManager
    @Binding var isFullScreen: Bool
    @Binding var showSettings: Bool
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var showControls: Bool = true
    @State private var controlsTimer: Timer?
    @State private var displayedScreenData: Data?
    @State private var lastUIUpdateTime: CFTimeInterval = 0
    @State private var uiUpdateTimer: Timer?
    @State private var frameSkipCount = 0
    @State private var currentUIUpdateInterval: TimeInterval = 1.0/15.0
    
    private var uiUpdateInterval: TimeInterval {
        return currentUIUpdateInterval
    }
    
    private var floatingControls: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        
                        Text("Connected to Mac")
                            .font(.caption)
                            .foregroundColor(.green)
                            .fontWeight(.medium)
                    }
                    
                    if let serverStatus = mirroringManager.serverStatus, showControls {
                        HStack(spacing: 12) {
                            performanceIndicator("FPS", "\(serverStatus.fps)", "speedometer", .blue)
                            performanceIndicator("Quality", "\(serverStatus.quality)%", "photo", .green)
                            
                            performanceIndicator(
                                "Latency", 
                                "\(serverStatus.latency)ms", 
                                "network", 
                                latencyColor(serverStatus.latency)
                            )
                            
                            if frameSkipCount > 0 {
                                performanceIndicator("Dropped", "\(frameSkipCount)", "exclamationmark.triangle", .orange)
                            }
                        }
                        .animation(.none, value: serverStatus.fps)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: {
                        // Future: Implement PiP mode
                        showControlsTemporarily()
                    }) {
                        Image(systemName: "pip.enter")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    
                    Button(action: {
                        scale = 1.0
                        offset = .zero
                        showControlsTemporarily()
                    }) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    
                    Button(action: {
                        isFullScreen = true
                    }) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    
                    Button(action: {
                        showSettings = true
                        showControlsTemporarily()
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    
                    Button(action: {
                        mirroringManager.disconnect()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.red.opacity(0.8))
                            .clipShape(Circle())
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        }
        .opacity(showControls ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.3), value: showControls)
    }
    
    private func performanceIndicator(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func latencyColor(_ latency: Int) -> Color {
        switch latency {
        case 0...30: return .green
        case 31...60: return .yellow
        case 61...100: return .orange
        default: return .red
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea()
                
                if let screenData = displayedScreenData,
                   let uiImage = UIImage(data: screenData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            SimultaneousGesture(
                                MagnificationGesture(minimumScaleDelta: 0.1)
                                    .onChanged { value in
                                        scale = value
                                        showControlsTemporarily()
                                    },
                                DragGesture(minimumDistance: 5)
                                    .onChanged { value in
                                        offset = value.translation
                                        showControlsTemporarily()
                                    }
                            )
                        )
                        .onTapGesture {
                            showControlsTemporarily()
                        }
                        .animation(.none, value: scale)
                        .animation(.none, value: offset)
                } else {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        
                        VStack(spacing: 8) {
                            Text("Loading Mac Screen...")
                                .foregroundColor(.white)
                                .font(.headline)
                            
                            Text("Establishing connection...")
                                .foregroundColor(.white.opacity(0.7))
                                .font(.caption)
                        }
                    }
                }
                
                if showControls {
                    VStack {
                        floatingControls
                            .padding(.top, geometry.safeAreaInsets.top + 10)
                            .padding(.horizontal, 16)
                        
                        Spacer()
                    }
                }
            }
        }
        .onAppear {
            setupEnergyAwareUI()
            showControlsTemporarily()
        }
        .onDisappear {
            cleanupTimers()
        }
        .onChange(of: mirroringManager.screenData) { oldValue, newValue in
            handleNewScreenData(newValue)
        }
    }
    
    private func setupEnergyAwareUI() {
        updateUITimer()
        
        if mirroringManager.streamingSettings != nil {
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("StreamingModeChanged"),
                object: nil,
                queue: .main
            ) { _ in
                self.updateUITimer()
            }
        }
    }
    
    private func updateUITimer() {
        guard let settings = mirroringManager.streamingSettings else { 
            currentUIUpdateInterval = 1.0/15.0 
            return
        }
        
        switch settings.streamingMode {
        case .performance:
            currentUIUpdateInterval = 1.0/30.0 
        case .balanced:
            currentUIUpdateInterval = 1.0/20.0 
        case .fidelity:
            currentUIUpdateInterval = 1.0/15.0 
        }
        
        uiUpdateTimer?.invalidate()
        uiUpdateTimer = Timer.scheduledTimer(withTimeInterval: currentUIUpdateInterval, repeats: true) { _ in
            updateUIIfNeeded()
        }
        
        let currentMode = mirroringManager.streamingSettings?.streamingMode.rawValue ?? "Default"
        print("📱 UI: Updated refresh rate for \(currentMode) mode - \(String(format: "%.1f", 1.0/currentUIUpdateInterval)) FPS")
    }
    
    private func handleNewScreenData(_ newData: Data?) {
        guard let newData = newData else { return }
        
        let currentTime = CFAbsoluteTimeGetCurrent()
        
        if currentTime - lastUIUpdateTime >= currentUIUpdateInterval {
            displayedScreenData = newData
            lastUIUpdateTime = currentTime
            frameSkipCount = 0
        } else {
            frameSkipCount += 1
            if frameSkipCount % 15 == 0 {
                let currentMode = mirroringManager.streamingSettings?.streamingMode.rawValue ?? "Unknown"
                print("⚡ UI: Skipped \(frameSkipCount) frames in \(currentMode) mode")
            }
        }
    }
    
    private func updateUIIfNeeded() {
        if let newData = mirroringManager.screenData,
           displayedScreenData != newData,
           CFAbsoluteTimeGetCurrent() - lastUIUpdateTime >= currentUIUpdateInterval {
            
            displayedScreenData = newData
            lastUIUpdateTime = CFAbsoluteTimeGetCurrent()
        }
    }
    
    private func cleanupTimers() {
        controlsTimer?.invalidate()
        controlsTimer = nil
        uiUpdateTimer?.invalidate()
        uiUpdateTimer = nil
    }
    
    private func showControlsTemporarily() {
        showControls = true
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: false) { _ in
            showControls = false
        }
    }
}

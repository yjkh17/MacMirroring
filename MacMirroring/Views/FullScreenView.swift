import SwiftUI

struct FullScreenView: View {
    @ObservedObject var mirroringManager: MirroringManager
    @Binding var isPresented: Bool
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var showControls: Bool = false
    @State private var controlsTimer: Timer?
    @State private var isZoomed = false
    @State private var lastTapTime: Date = Date()
    @State private var tapCount = 0
    @GestureState private var magnifyAmount: CGFloat = 1.0
    @GestureState private var panAmount: CGSize = .zero
    
    @State private var showWindowSelector = false
    @State private var showSourceInfo = false
    @State private var windowRefreshTimer: Timer?
    @State private var lastWindowUpdate: Date = Date()
    
    @State private var isControlsVisible = false
    @State private var lastInteractionTime = Date()
    @State private var autoHideTimer: Timer?
    @State private var hapticFeedback = UIImpactFeedbackGenerator(style: .medium)
    @State private var isWindowSelectorAnimating = false
    @State private var selectedWindowPreview: MacWindow?
    @State private var showPerformanceOverlay = false
    @State private var performanceOverlayTimer: Timer?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea(.all)
                    .overlay(
                        Rectangle()
                            .fill(.black.opacity(0.02))
                            .ignoresSafeArea()
                    )
                
                if let screenData = mirroringManager.screenData,
                   let uiImage = UIImage(data: screenData) {
                    
                    screenContentView(uiImage: uiImage, geometry: geometry)
                } else {
                    loadingStateView
                }
                
                if showSourceInfo {
                    windowSourceIndicator
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity.combined(with: .move(edge: .top))
                        ))
                }
                
                if showPerformanceOverlay {
                    performanceOverlayView
                        .transition(.opacity.combined(with: .scale))
                }
                
                if showControls {
                    VStack {
                        Spacer()
                        fullScreenControls
                            .padding(.bottom, geometry.safeAreaInsets.bottom + 20)
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .opacity.combined(with: .move(edge: .bottom))
                    ))
                }
                
                if showWindowSelector {
                    windowSelectorOverlay
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.9)),
                            removal: .opacity.combined(with: .scale(scale: 0.9))
                        ))
                }
                
                if scale != 1.0 {
                    zoomIndicator
                        .transition(.opacity.combined(with: .scale))
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .ignoresSafeArea(.all)
        .onAppear {
            setupView()
        }
        .onDisappear {
            cleanup()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StreamingModeChanged"))) { _ in
            showSourceInfoTemporarily()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            handleOrientationChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            handleAppBackground()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            handleAppForeground()
        }
    }
    
    private func screenContentView(uiImage: UIImage, geometry: GeometryProxy) -> some View {
        Image(uiImage: uiImage)
            .resizable()
            .aspectRatio(contentMode: getAspectRatio())
            .scaleEffect(scale * magnifyAmount)
            .offset(
                x: offset.width + panAmount.width,
                y: offset.height + panAmount.height
            )
            .gesture(
                SimultaneousGesture(
                    MagnificationGesture()
                        .updating($magnifyAmount) { value, state, _ in
                            state = value
                            updateLastInteraction()
                            showControlsTemporarily()
                            
                            if abs(value - 1.0) > 0.5 {
                                hapticFeedback.impactOccurred()
                            }
                        }
                        .onEnded { value in
                            let newScale = scale * value
                            scale = max(0.5, min(newScale, 5.0))
                            
                            if scale < 0.8 {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    scale = getOptimalScale(for: geometry)
                                    offset = .zero
                                }
                                hapticFeedback.impactOccurred()
                            }
                        },
                    
                    DragGesture()
                        .updating($panAmount) { value, state, _ in
                            state = value.translation
                            updateLastInteraction()
                            showControlsTemporarily()
                        }
                        .onEnded { value in
                            let newOffset = CGSize(
                                width: offset.width + value.translation.width,
                                height: offset.height + value.translation.height
                            )
                            
                            let maxOffsetX = geometry.size.width * (scale - 1) * 0.5
                            let maxOffsetY = geometry.size.height * (scale - 1) * 0.5
                            
                            offset = CGSize(
                                width: max(-maxOffsetX, min(maxOffsetX, newOffset.width)),
                                height: max(-maxOffsetY, min(maxOffsetY, newOffset.height))
                            )
                        }
                )
            )
            .onTapGesture(count: 2) {
                handleDoubleTap(geometry: geometry)
            }
            .onTapGesture(count: 1) {
                handleSingleTap()
            }
            .onTapGesture(count: 3) {
                handleTripleTap()
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: scale)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: offset)
    }
    
    private var windowSourceIndicator: some View {
        VStack {
            HStack {
                Spacer()
                
                VStack(alignment: .trailing, spacing: 6) {
                    if let settings = mirroringManager.streamingSettings {
                        HStack(spacing: 10) {
                            Image(systemName: settings.captureSource == .singleWindow ? "macwindow" : "display")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                            
                            Text(getCurrentSourceName())
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.black.opacity(0.8))
                                .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
                        )
                        
                        if settings.captureSource == .singleWindow {
                            Text("Window Mode")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.top, 2)
                        }
                    }
                }
                .padding(.trailing, 24)
                .padding(.top, 70)
            }
            
            Spacer()
        }
    }
    
    private var windowSelectorOverlay: some View {
        VStack(spacing: 25) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Select Window")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("Choose what to stream from your Mac")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                Button("Close") {
                    dismissWindowSelector()
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.blue)
            }
            
            if let settings = mirroringManager.streamingSettings {
                HStack(spacing: 20) {
                    sourceButton("Full Display", .fullDisplay, settings)
                    sourceButton("Single Window", .singleWindow, settings)
                }
                
                if settings.captureSource == .singleWindow {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Available Windows")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            Button("Refresh") {
                                refreshWindows()
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                        }
                        
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                if settings.isLoadingWindowsDisplays {
                                    loadingWindowsView
                                } else if settings.availableWindows.isEmpty {
                                    emptyWindowsView
                                } else {
                                    ForEach(settings.availableWindows) { window in
                                        windowSelectionRow(window: window, settings: settings)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 300)
                    }
                }
            }
            
            HStack(spacing: 20) {
                Button("Refresh All") {
                    refreshWindows()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                
                Button("Fit to Screen") {
                    fitToScreen()
                    dismissWindowSelector()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.black.opacity(0.95))
                .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
        )
        .padding(20)
    }
    
    private func sourceButton(_ title: String, _ source: CaptureSource, _ settings: StreamingSettings) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                settings.captureSource = source
                settings.sendSettingsToServer(via: mirroringManager.connection)
                
                if source == .singleWindow && settings.availableWindows.isEmpty {
                    refreshWindows()
                }
            }
            hapticFeedback.impactOccurred()
        }) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(settings.captureSource == source ? .black : .white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(settings.captureSource == source ? .white : .white.opacity(0.2))
                        .shadow(color: settings.captureSource == source ? .white.opacity(0.3) : .clear, radius: 5)
                )
        }
        .scaleEffect(settings.captureSource == source ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: settings.captureSource == source)
    }
    
    private func windowSelectionRow(window: MacWindow, settings: StreamingSettings) -> some View {
        Button(action: {
            selectWindow(window, settings: settings)
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(window.title.isEmpty ? "Untitled Window" : window.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    Text(window.ownerName)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                if settings.selectedWindow?.id == window.id {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                        .scaleEffect(1.1)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(settings.selectedWindow?.id == window.id ? .blue.opacity(0.3) : .white.opacity(0.1))
                    .shadow(color: settings.selectedWindow?.id == window.id ? .blue.opacity(0.3) : .clear, radius: 5)
            )
        }
        .scaleEffect(settings.selectedWindow?.id == window.id ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: settings.selectedWindow?.id == window.id)
    }
    
    private var loadingWindowsView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                .scaleEffect(0.9)
            
            Text("Loading windows...")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.05))
        .cornerRadius(12)
    }
    
    private var emptyWindowsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "macwindow.badge.plus")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.white.opacity(0.6))
            
            VStack(spacing: 8) {
                Text("No windows available")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.8))
                
                Text("Make sure Mac Mirroring Server is running and has windows to share")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            
            Button("Refresh Windows") {
                refreshWindows()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.05))
        .cornerRadius(16)
    }
    
    private var loadingStateView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(2.0)
            
            VStack(spacing: 8) {
                Text("Loading Mac Screen...")
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                if let settings = mirroringManager.streamingSettings {
                    Text(settings.captureSource == .singleWindow ? "Capturing window..." : "Capturing display...")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            
            HStack(spacing: 8) {
                Image(systemName: "wifi")
                    .font(.caption)
                    .foregroundColor(mirroringManager.networkQuality.color)
                
                Text(mirroringManager.networkQuality.rawValue)
                    .font(.caption)
                    .foregroundColor(mirroringManager.networkQuality.color)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.white.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    private var fullScreenControls: some View {
        HStack(spacing: 24) {
            if let serverStatus = mirroringManager.serverStatus {
                HStack(spacing: 12) {
                    performanceButton("\(serverStatus.fps)", "speedometer", .blue)
                        .onTapGesture(count: 3) {
                            showPerformanceOverlay.toggle()
                        }
                    performanceButton("\(serverStatus.quality)%", "photo", .green)
                    performanceButton("\(serverStatus.latency)ms", "network", latencyColor(serverStatus.latency))
                }
            }
            
            Spacer()
            
            HStack(spacing: 18) {
                if let settings = mirroringManager.streamingSettings {
                    controlButton(
                        icon: settings.captureSource == .singleWindow ? "macwindow" : "display",
                        color: .purple,
                        action: {
                            showWindowSelector = true
                            showControlsTemporarily()
                        }
                    )
                }
                
                controlButton(
                    icon: scale > 1.2 ? "minus.magnifyingglass" : "plus.magnifyingglass",
                    color: .gray,
                    action: {
                        handleZoomToggle()
                        showControlsTemporarily()
                    }
                )
                
                controlButton(
                    icon: "arrow.up.left.and.arrow.down.right",
                    color: .gray,
                    action: {
                        fitToScreen()
                        showControlsTemporarily()
                    }
                )
                
                controlButton(
                    icon: "xmark",
                    color: .red,
                    action: {
                        isPresented = false
                    }
                )
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(.ultraThinMaterial.opacity(0.4))
                .shadow(color: .black.opacity(0.4), radius: 15, x: 0, y: 8)
        )
    }
    
    private func controlButton(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: {
            action()
            hapticFeedback.impactOccurred()
        }) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 52, height: 52)
                .background(color.opacity(0.8))
                .clipShape(Circle())
                .shadow(color: color.opacity(0.3), radius: 5, x: 0, y: 2)
        }
        .scaleEffect(1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: showControls)
    }
    
    private var performanceOverlayView: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Performance Monitor")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button("Close") {
                    showPerformanceOverlay = false
                }
                .foregroundColor(.blue)
            }
            
            if let serverStatus = mirroringManager.serverStatus {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                    performanceMetric("FPS", "\(serverStatus.fps)", .blue, "speedometer")
                    performanceMetric("Quality", "\(serverStatus.quality)%", .green, "photo")
                    performanceMetric("Latency", "\(serverStatus.latency)ms", latencyColor(serverStatus.latency), "network")
                    performanceMetric("Energy", mirroringManager.energyImpact.description, mirroringManager.energyImpact.color, "bolt")
                }
            }
            
            Spacer()
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.black.opacity(0.9))
                .shadow(color: .black.opacity(0.5), radius: 20)
        )
        .padding(20)
    }
    
    private func performanceMetric(_ title: String, _ value: String, _ color: Color, _ icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(color.opacity(0.2))
        .cornerRadius(16)
    }
    
    private var zoomIndicator: some View {
        VStack {
            HStack {
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(Int(scale * 100))%")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    
                    if let settings = mirroringManager.streamingSettings,
                       settings.captureSource == .singleWindow {
                        Text("Window Zoom")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.black.opacity(0.8))
                        .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
                )
                .padding(.trailing, 24)
                .padding(.top, 70)
            }
            
            Spacer()
        }
    }
    
    private func setupView() {
        showControlsTemporarily()
        startWindowMonitoring()
        hapticFeedback.prepare()
    }
    
    private func selectWindow(_ window: MacWindow, settings: StreamingSettings) {
        selectedWindowPreview = window
        settings.selectedWindow = window
        settings.selectedWindowName = "\(window.ownerName): \(window.title)"
        settings.sendSettingsToServer(via: mirroringManager.connection)
        
        hapticFeedback.impactOccurred()
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showWindowSelector = false
            showSourceInfoTemporarily()
        }
        
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            scale = 1.0
            offset = .zero
        }
    }
    
    private func dismissWindowSelector() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showWindowSelector = false
        }
    }
    
    private func refreshWindows() {
        mirroringManager.streamingSettings?.requestWindowsAndDisplays(via: mirroringManager.connection)
        lastWindowUpdate = Date()
        hapticFeedback.impactOccurred()
    }
    
    private func getCurrentSourceName() -> String {
        guard let settings = mirroringManager.streamingSettings else { return "Unknown" }
        
        switch settings.captureSource {
        case .fullDisplay:
            return settings.selectedDisplayName ?? "Main Display"
        case .singleWindow:
            if let windowName = settings.selectedWindowName, !windowName.isEmpty {
                return windowName.count > 30 ? String(windowName.prefix(27)) + "..." : windowName
            } else {
                return "Select Window"
            }
        }
    }
    
    private func getAspectRatio() -> ContentMode {
        return .fit
    }
    
    private func getOptimalScale(for geometry: GeometryProxy) -> CGFloat {
        guard let settings = mirroringManager.streamingSettings else { return 1.0 }
        
        if settings.captureSource == .singleWindow {
            return 1.2
        } else {
            return 1.0
        }
    }
    
    private func handleDoubleTap(geometry: GeometryProxy) {
        hapticFeedback.impactOccurred()
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            if scale > 1.2 {
                scale = 1.0
                offset = .zero
            } else {
                scale = getOptimalScale(for: geometry) * 1.5
            }
        }
        showControlsTemporarily()
    }
    
    private func handleSingleTap() {
        updateLastInteraction()
        
        let now = Date()
        let timeSinceLastTap = now.timeIntervalSince(lastTapTime)
        
        if timeSinceLastTap < 0.3 {
            tapCount += 1
        } else {
            tapCount = 1
        }
        
        lastTapTime = now
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if self.tapCount == 1 {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    self.showControls.toggle()
                }
                if self.showControls {
                    self.showControlsTemporarily()
                }
            }
            self.tapCount = 0
        }
    }
    
    private func handleTripleTap() {
        hapticFeedback.impactOccurred()
        showWindowSelector = true
        showControlsTemporarily()
    }
    
    private func handleZoomToggle() {
        hapticFeedback.impactOccurred()
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            if scale > 1.2 {
                scale = 1.0
                offset = .zero
            } else {
                scale = 2.0
            }
        }
    }
    
    private func fitToScreen() {
        hapticFeedback.impactOccurred()
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            scale = 1.0
            offset = .zero
        }
    }
    
    private func startWindowMonitoring() {
        windowRefreshTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            if let settings = mirroringManager.streamingSettings,
               settings.captureSource == .singleWindow,
               Date().timeIntervalSince(lastWindowUpdate) > 30 {
                refreshWindows()
            }
        }
    }
    
    private func showSourceInfoTemporarily() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showSourceInfo = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showSourceInfo = false
            }
        }
    }
    
    private func updateLastInteraction() {
        lastInteractionTime = Date()
    }
    
    private func handleOrientationChange() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            scale = 1.0
            offset = .zero
        }
    }
    
    private func handleAppBackground() {
        showControls = false
        showWindowSelector = false
        showSourceInfo = false
    }
    
    private func handleAppForeground() {
        showControlsTemporarily()
    }
    
    private func performanceButton(_ text: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.7))
                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
        )
    }
    
    private func showControlsTemporarily() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showControls = true
        }
        
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showControls = false
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
    
    private func cleanup() {
        controlsTimer?.invalidate()
        controlsTimer = nil
        windowRefreshTimer?.invalidate()
        windowRefreshTimer = nil
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        performanceOverlayTimer?.invalidate()
        performanceOverlayTimer = nil
    }
}

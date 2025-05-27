//
//  MacMirriring_ServerApp.swift
//  Mac Mirroring Server
//
//  Created by Yousef Jawdat on 24/05/2025.
//

import SwiftUI
import AppKit

@main
struct MacMirriringMacApp: App {
    @StateObject private var multipeerCapture = MultipeerCapture()
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ServerContentView()
                .environmentObject(multipeerCapture)
        }
        .windowStyle(DefaultWindowStyle())
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(newPhase)
        }
        
        MenuBarExtra("Mac Mirroring Server", systemImage: "display.trianglebadge.exclamationmark") {
            MenuBarView()
                .environmentObject(multipeerCapture)
        }
        .menuBarExtraStyle(.window)
    }
    
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            print(" App entering background - server continues running")
        case .inactive:
            print(" App inactive")
        case .active:
            print(" App active")
        @unknown default:
            break
        }
    }
}

class MultipeerCapture: ObservableObject {
    @Published var isAdvertising = false
    @Published var connectedPeers = [String]()
    @Published var isCapturing = false
    
    init() {
    }
}

struct MenuBarView: View {
    @EnvironmentObject var multipeerCapture: MultipeerCapture
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "display.trianglebadge.exclamationmark")
                    .foregroundColor(.blue)
                Text("Mac Mirroring Server")
                    .font(.headline)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Status:")
                    Spacer()
                    Text(multipeerCapture.isAdvertising ? "Active" : "Inactive")
                        .foregroundColor(multipeerCapture.isAdvertising ? .green : .orange)
                }
                
                HStack {
                    Text("Connected:")
                    Spacer()
                    Text("\(multipeerCapture.connectedPeers.count) devices")
                        .foregroundColor(.blue)
                }
                
                HStack {
                    Text("Capturing:")
                    Spacer()
                    Text(multipeerCapture.isCapturing ? "Yes" : "No")
                        .foregroundColor(multipeerCapture.isCapturing ? .green : .gray)
                }
            }
            .font(.caption)
            
            Divider()
            
            Button("Show Main Window") {
                showMainWindow()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            Button("Quit Server") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .foregroundColor(.red)
        }
        .padding()
        .frame(width: 200)
    }
    
    private func showMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        for window in NSApplication.shared.windows {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

//
//  MacMirriring_ServerApp.swift
//  Mac Mirroring Server
//
//  Created by Yousef Jawdat on 24/05/2025.
//

import SwiftUI
import AppKit

@main
struct MacMirriring_ServerApp: App {
    @StateObject private var serverManager = BackgroundServerManager()
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(serverManager)
        }
        .windowStyle(DefaultWindowStyle())
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(newPhase)
        }
        
        MenuBarExtra("Mac Mirroring Server", systemImage: "display.trianglebadge.exclamationmark") {
            MenuBarView()
                .environmentObject(serverManager)
        }
        .menuBarExtraStyle(.window)
    }
    
    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            print(" App entering background - server continues running")
            serverManager.enableBackgroundMode()
        case .inactive:
            print(" App inactive")
        case .active:
            print(" App active")
            serverManager.disableBackgroundMode()
        @unknown default:
            break
        }
    }
}

class BackgroundServerManager: ObservableObject {
    @Published var isBackgroundMode = false
    @Published var serverStatus = "Ready"
    @Published var connectedDevices = 0
    
    private var mirroringServer: MirroringServer?
    private var statusBarItem: NSStatusItem?
    
    init() {
        setupBackgroundServer()
        setupStatusBarItem()
    }
    
    private func setupBackgroundServer() {
        mirroringServer = MirroringServer()
        print(" Background server initialized")
    }
    
    private func setupStatusBarItem() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusBarItem?.button?.image = NSImage(systemSymbolName: "display.trianglebadge.exclamationmark", accessibilityDescription: "Mac Mirroring Server")
        statusBarItem?.button?.toolTip = "Mac Mirroring Server - Always Ready"
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Mac Mirroring Server", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Status: Ready", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Connected Devices: 0", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Show Window", action: #selector(showMainWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusBarItem?.menu = menu
    }
    
    @objc public func showMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        for window in NSApplication.shared.windows {
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    func enableBackgroundMode() {
        isBackgroundMode = true
        updateStatusBarMenu()
        print(" Background mode enabled - server continues running")
    }
    
    func disableBackgroundMode() {
        isBackgroundMode = false
        updateStatusBarMenu()
        print(" Foreground mode - full UI available")
    }
    
    private func updateStatusBarMenu() {
        guard let menu = statusBarItem?.menu else { return }
        
        menu.item(at: 2)?.title = "Status: \(isBackgroundMode ? "Background" : "Foreground")"
        menu.item(at: 3)?.title = "Connected Devices: \(connectedDevices)"
    }
}

struct MenuBarView: View {
    @EnvironmentObject var serverManager: BackgroundServerManager
    
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
                    Text(serverManager.isBackgroundMode ? "Background" : "Active")
                        .foregroundColor(serverManager.isBackgroundMode ? .orange : .green)
                }
                
                HStack {
                    Text("Connected:")
                    Spacer()
                    Text("\(serverManager.connectedDevices) devices")
                        .foregroundColor(.blue)
                }
                
                HStack {
                    Text("Server:")
                    Spacer()
                    Text("Always Running")
                        .foregroundColor(.green)
                }
            }
            .font(.caption)
            
            Divider()
            
            Button("Show Main Window") {
                serverManager.showMainWindow()
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
}

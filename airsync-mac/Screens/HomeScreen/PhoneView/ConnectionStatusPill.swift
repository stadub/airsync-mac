//
//  ConnectionStatusPill.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2026-03-11.
//

import SwiftUI

struct ConnectionStatusPill: View {
    @ObservedObject var appState = AppState.shared
    @ObservedObject var bleManager = BLECentralManager.shared
    @State private var showingPopover = false
    @State private var isHovered = false
    @ObservedObject private var quickShareManager = QuickShareManager.shared
    @State private var expanded = false
    var expandable = false
    var useGlass = true
    var showWiFi = true
    var showStatuses = true

    var body: some View {
        HStack(spacing: 8) {
            Button { showingPopover.toggle() } label: {
                HStack(spacing: 8) {
                    if showWiFi {
                        Image(systemName: appState.isConnectedOverLocalNetwork ? "wifi" : "globe")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    if !expandable && showStatuses { statusIcons }
                }
                .contentShape(Rectangle())
            }
            .help("Connection details")
            .accessibilityLabel("Connection details")
            .popover(isPresented: $showingPopover, arrowEdge: .top) { ConnectionPillPopover() }

            if expandable {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .focusable(false)
                .help(expanded ? "Hide connection status" : "Show connection status")
                .accessibilityLabel(expanded ? "Hide connection status" : "Show connection status")
                if expanded {
                    statusIcons
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Divider().frame(height: 20)
                    PhoneQuickActionsView(compact: true)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, useGlass ? 10 : 0)
        .padding(.vertical, useGlass ? 6 : 0)
        .applyGlassViewIfAvailable(enabled: useGlass)
        .fixedSize(horizontal: true, vertical: false)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: appState.adbConnected)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: appState.adbConnectionMode)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: bleManager.connectionStatus)
    }

    @ViewBuilder
    private var statusIcons: some View {
                if appState.isPlus {
                    if appState.adbConnecting {
                        ProgressView()
                            .controlSize(.small)
                            .help("ADB Connecting...")
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .opacity
                            ))
                    } else if appState.adbConnected {
                        // ADB Indicator
                        HStack(spacing: 6) {
                            Image(systemName: "iphone.gen3.crop.circle")
                                .contentTransition(.symbolEffect(.replace))
                                .help("ADB Connected")
                            
                            // ADB Mode Icon
                            Image(systemName: adbModeIcon)
                                .contentTransition(.symbolEffect(.replace))
                                .help(adbModeHelp)
                        }
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .opacity
                        ))
                    }

                    if QuickShareManager.shared.isEnabled && QuickShareManager.shared.isRunning {
                        Image(systemName: "laptopcomputer.and.arrow.down")
                            .contentTransition(.symbolEffect(.replace))
                            .help("Quick Share Ready")
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
                
                if bleManager.isAuthenticated {
                    Image("logo.bluetooth")
                        .help("BLE Connected")
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .opacity
                        ))
                }
    }

    private var adbModeIcon: String {
        switch appState.adbConnectionMode {
        case .wired:
            return "cable.connector"
        case .wireless, .none:
            return "airplay.audio"
        }
    }
    
    private var adbModeHelp: String {
        switch appState.adbConnectionMode {
        case .wired:
            return "Wired ADB Connection"
        case .wireless, .none:
            return "Wireless ADB Connection"
        }
    }
}

struct ConnectionPillPopover: View {
    @ObservedObject var appState = AppState.shared
    @ObservedObject var quickShareManager = QuickShareManager.shared
    @ObservedObject var bleManager = BLECentralManager.shared
    @State private var currentIPAddress: String = "N/A"
    
    @State private var availableWiredDevices: [WiredADBDevice] = []
    
    var bleStatusText: String {
        switch bleManager.connectionStatus {
        case .scanning: return "Scanning..."
        case .connected: return "Authenticating..."
        case .authenticated: return "Connected"
        case .disconnected: return "Disconnected"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            if let device = appState.device {
                VStack(alignment: .leading, spacing: 12) {
                    ConnectionInfoText(
                        label: "Device",
                        icon: "iphone.gen3",
                        text: device.name
                    )
                    
                    ConnectionInfoText(
                        label: "IP Address",
                        icon: "wifi",
                        text: appState.device?.ipAddress == "BLE" ? "BLE only" : currentIPAddress,
                        activeIp: appState.device?.ipAddress == "BLE" ? nil : appState.activeMacIp
                    )
                    
                    if appState.isPlus {
                        if appState.wiredAdbEnabled {
                            HStack {
                                Label(L("connection.wiredAdb"), systemImage: "cable.connector")
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { appState.selectedWiredSerial ?? "" },
                                    set: { newSerial in
                                        appState.selectedWiredSerial = newSerial
                                        if let deviceId = appState.device?.deviceId {
                                            appState.deviceAdbSerials[deviceId] = newSerial
                                        }
                                        appState.adbConnectionResult = "Switched to Wired ADB Serial: \(newSerial)"
                                    }
                                )) {
                                    Text(loc: "connection.selectDevice").tag("")
                                    ForEach(availableWiredDevices, id: \.serial) { dev in
                                        Text("\(dev.model) (\(dev.serial))").tag(dev.serial)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .frame(width: 140)
                            }
                        }
                        
                        if appState.adbConnected && appState.adbConnectionMode == .wireless {
                            ConnectionInfoText(
                                label: "ADB Connection",
                                icon: "airplay.audio",
                                text: L("connection.wireless")
                            )
                        }
                    }

                    HStack {
                        Label("QuickShare", systemImage: "laptopcomputer.and.arrow.down")
                        Spacer()
                        Toggle("", isOn: $quickShareManager.isEnabled)
                            .toggleStyle(.switch)
                    }

                    if appState.isBLEEnabled {
                        ConnectionInfoText(
                            label: "Bluetooth LE",
                            icon: "logo.bluetooth",
                            text: bleStatusText
                        )
                    }
                }
                .padding(.bottom, 4)
                
                HStack(alignment: .center, spacing: 8) {
                    Spacer()
                    if appState.isPlus {
                        GlassButtonView(
                            label: appState.adbConnected ? "Disconnect ADB" : (appState.adbConnecting ? "Connecting ADB..." : "Connect ADB"),
                            systemImage: appState.adbConnected ? "cable.connector.slash" : (appState.adbConnecting ? nil : "cable.connector"),
                            iconOnly: false,
                            primary: false,
                            isLoading: appState.adbConnecting,
                            action: {
                                if appState.adbConnected {
                                    ADBConnector.disconnectADB()
                                } else if !appState.adbConnecting {
                                    appState.adbConnectionResult = "" // Clear console
                                    appState.manualAdbConnectionPending = true
                                    appState.userInitiatedAdbConnect = true
                                    WebSocketServer.shared.sendRefreshAdbPortsRequest()
                                    appState.adbConnectionResult = "Refreshing latest ADB ports from device..."
                                }
                            }
                        )
                        .focusable(false)
                    }
                    
                    GlassButtonView(
                        label: "Disconnect Device",
                        systemImage: "iphone.slash",
                        iconOnly: false,
                        primary: true,
                        action: {
                            appState.disconnectDevice(manual: true)
                            if appState.isPlus {
                                ADBConnector.disconnectADB()
                            }
                            appState.adbConnected = false
                        }
                    )
                    .focusable(false)
                    Spacer()
                }
            } else {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(loc: "settings.connectionMode")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)

                    Picker("", selection: $appState.connectionMode) {
                        ForEach(AppState.AppConnectionMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.large)
                }

                HStack {
                    Label("Auto-connect", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12))
                    Spacer()
                    Toggle("", isOn: $appState.isBLEAutoConnectEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(!appState.isBLEEnabled)
                }

                HStack {
                    Label("Auto switch with nearby", systemImage: "arrow.triangle.swap")
                        .font(.system(size: 12))
                    Spacer()
                    Toggle("", isOn: $appState.isAutoSwitchWithBLEEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(!appState.isBLEEnabled)
                }
            }
            .frame(width: 240)
            }
        }
        .padding()
        .frame(minWidth: 380)
        .onAppear {
            currentIPAddress = WebSocketServer.shared.getLocalIPAddress(adapterName: appState.selectedNetworkAdapterName) ?? "N/A"
            ADBConnector.getWiredDevices { devices in
                DispatchQueue.main.async {
                    self.availableWiredDevices = devices
                }
            }
        }
    }
}


#Preview {
    ConnectionStatusPill()
        .padding()
        .background(Color.black.opacity(0.1))
}

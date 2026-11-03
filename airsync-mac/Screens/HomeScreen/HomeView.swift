//
//  HomeView.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-27.
//

import SwiftUI
import AppKit

struct HomeView: View {
    @ObservedObject var appState = AppState.shared
    @ObservedObject private var mirrorStreamClient = ScrcpyStreamClient.shared
    @State private var targetOpacity: Double = 0
    @AppStorage("hasPairedDeviceOnce") private var hasPairedDeviceOnce: Bool = false
    @State var showOnboarding = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    private var needsOnboarding: Bool {
        // Show onboarding if either:
        // 1. User has never paired a device (first time user)
        // 2. User's lastOnboarding doesn't match current ForceUpdateKey
        return !hasPairedDeviceOnce || UserDefaults.standard.needsOnboarding
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    ZStack {
                        if appState.selectedTab == .settings {
                            SettingsSidebarView()
                        } else if appState.device == nil {
                            QRScannerSidebarView()
                        } else {
                            SidebarView()
                        }
                    }
                    .frame(minWidth: sidebarWidth(in: geometry.size))
                    .navigationSplitViewColumnWidth(
                        min: sidebarWidth(in: geometry.size),
                        ideal: sidebarWidth(in: geometry.size),
                        max: max(270, geometry.size.width * 0.45)
                    )
                } detail: {
                    AppContentView()
                }
                .navigationTitle("")
                .background(.background.opacity(appState.windowOpacity))
                .toolbarBackground(
                    .clear,
                    for: .windowToolbar
                )
                // Show onboarding sheet when needed
                .onAppear {
                    if needsOnboarding {
                        showOnboarding = true
                        appState.isOnboardingActive = true
                    }
                    updateSidebarVisibility()
                }
                .onChange(of: appState.device) { _, _ in
                    updateSidebarVisibility()
                }
                .sheet(isPresented: $showOnboarding) {
                    OnboardingView()
                        .frame(minWidth: 640, minHeight: 420)
                }
                .onChange(of: showOnboarding) { oldValue, newValue in
                    if !newValue {
                        appState.isOnboardingActive = false
                    }
                }
                .onChange(of: appState.isOnboardingActive) { oldValue, newValue in
                    // Force view update to refresh window properties
                }

                if appState.isConnectionWeak && appState.device != nil {
                    VStack {
                        Spacer()
                        ConnectionWeakOverlay(appState: appState)
                            .padding(.bottom, 20)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                }
            }
        }
    }

    private func sidebarWidth(in size: CGSize) -> CGFloat {
        guard appState.isSidebarMirroring, appState.selectedTab != .settings else { return 270 }
        let ratio: CGFloat = mirrorStreamClient.videoWidth > 0 && mirrorStreamClient.videoHeight > 0
            ? CGFloat(mirrorStreamClient.videoWidth) / CGFloat(mirrorStreamClient.videoHeight)
            : 9.0 / 19.5
        return max(270, min(size.width * 0.42, max(1, size.height - 160) * ratio + 24))
    }

    private func updateSidebarVisibility() {
        withAnimation(.easeInOut(duration: 0.3)) {
            columnVisibility = .all
        }
    }
}

struct ConnectionWeakOverlay: View {
    @ObservedObject var appState: AppState
    @State private var pulse = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.accentColor)

            Text("Looking for \(appState.device?.name ?? "device")...")
                .font(.subheadline)
                .fontWeight(.medium)


            GlassButtonView(
                label: "Disconnect",
                systemImage: "iphone.slash",
                size: .large,
                primary: true,
                action: {
                    withAnimation {
                        appState.disconnectDevice(manual: true)
                    }
                }
            )
        }
        .padding(12)
        .glassBoxIfAvailable(radius: 24)
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
    }
}

#Preview {
    HomeView()
}

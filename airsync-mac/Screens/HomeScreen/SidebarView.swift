//
//  SidebarView.swift
//  airsync-mac
//
//  Created by Sameera Sandakelum on 2025-07-28.
//

import SwiftUI
import AppKit

struct SidebarView: View {
    @ObservedObject var appState = AppState.shared
    @ObservedObject var discoveryManager = DiscoveryManager.shared
    @State private var isExpandedAllSeas: Bool = false
    @State private var showingPlusDesktopPopover = false
    private var preferredMirrorTitle: String {
        switch appState.preferredScreenMirrorMode {
        case .embedded: return "Mirror Here"
        case .native: return "Android Mirror"
        case .scrcpy: return "scrcpy Mirror"
        default: return "Mirror"
        }
    }

    var body: some View {
        VStack {
            PhoneMirrorHeader(showsMirrorControls: appState.isSidebarMirroring).padding(.horizontal, 8)

            if let deviceVersion = appState.device?.version,
               appState.device?.ipAddress != "BLE",
               isVersion(deviceVersion, lessThan: appState.minAndroidVersion) {
                Label("Your Android app is outdated", systemImage: "iphone.badge.exclamationmark")
                    .padding(4)
            }

            PhoneView()
                .transition(.scale)
                .opacity(appState.device != nil ? 1 : 0.5)

            Spacer()

        }
        .animation(.easeInOut(duration: 0.5), value: appState.status != nil)
        .frame(minWidth: 250, minHeight: 400)
        .safeAreaInset(edge: .bottom) {

            if appState.adbConnected {
                HStack(spacing: 12) {
                    Menu {
                        Button("Mirror Here", systemImage: "iphone") { appState.openScreenMirroring(.embedded) }
                            .appShortcut(AppShortcuts.mirrorHere, appState: appState)
                        Button("Android Mirror", systemImage: "macwindow") { appState.openScreenMirroring(.native) }
                        Button("scrcpy Mirror", systemImage: "rectangle.on.rectangle") { appState.openScreenMirroring(.scrcpy) }
                        if appState.isScreenMirroring {
                            Divider()
                            Button("Close Mirror", systemImage: "xmark.circle") { appState.closeScreenMirroring() }
                        }
                    } label: {
                        Label(appState.isScreenMirroring ? "Close" : preferredMirrorTitle,
                              systemImage: appState.isScreenMirroring ? "xmark.circle" : "apps.iphone")
                    } primaryAction: {
                        if appState.isScreenMirroring {
                            appState.closeScreenMirroring()
                        } else {
                            appState.openScreenMirroring(appState.preferredScreenMirrorMode)
                        }
                    }
                    .disabled(appState.switchingScreenMirror)
                    .menuStyle(.button)
                    .controlSize(.large)
                    .glassButtonIfAvailable()
                    .transition(.identity)
                    .appShortcut(AppShortcuts.mirrorPrimary, appState: appState)

                    Menu {
                        if appState.useNativeDesktopMirroringByDefault {
                            Button("Native Desktop", systemImage: "desktopcomputer") {
                                if appState.isPlus && appState.licenseCheck {
                                    appState.isNativeDesktopMirroring = true
                                } else {
                                    showingPlusDesktopPopover = true
                                }
                            }
                            .appShortcut(AppShortcuts.desktopPrimary, appState: appState)

                            Button("scrcpy Desktop", systemImage: "display") {
                                if appState.isPlus && appState.licenseCheck {
                                    ADBConnector.startScrcpy(
                                        ip: appState.device?.ipAddress ?? "",
                                        port: appState.adbPort,
                                        deviceName: appState.device?.name ?? "My Phone",
                                        desktop: true
                                    )
                                } else {
                                    showingPlusDesktopPopover = true
                                }
                            }
                            .appShortcut(AppShortcuts.desktopAlternate, appState: appState)
                        } else {
                            Button("scrcpy Desktop", systemImage: "display") {
                                if appState.isPlus && appState.licenseCheck {
                                    ADBConnector.startScrcpy(
                                        ip: appState.device?.ipAddress ?? "",
                                        port: appState.adbPort,
                                        deviceName: appState.device?.name ?? "My Phone",
                                        desktop: true
                                    )
                                } else {
                                    showingPlusDesktopPopover = true
                                }
                            }
                            .appShortcut(AppShortcuts.desktopPrimary, appState: appState)

                            Button("Native Desktop", systemImage: "desktopcomputer") {
                                if appState.isPlus && appState.licenseCheck {
                                    appState.isNativeDesktopMirroring = true
                                } else {
                                    showingPlusDesktopPopover = true
                                }
                            }
                            .appShortcut(AppShortcuts.desktopAlternate, appState: appState)
                        }
                    } label: {
                        Label("Desktop", systemImage: "desktopcomputer")
                    } primaryAction: {
                        if appState.isPlus && appState.licenseCheck {
                            if appState.useNativeDesktopMirroringByDefault {
                                appState.isNativeDesktopMirroring = true
                            } else {
                                ADBConnector.startScrcpy(
                                    ip: appState.device?.ipAddress ?? "",
                                    port: appState.adbPort,
                                    deviceName: appState.device?.name ?? "My Phone",
                                    desktop: true
                                )
                            }
                        } else {
                            showingPlusDesktopPopover = true
                        }
                    }
                    .menuStyle(.button)
                    .controlSize(.large)
                    .glassButtonIfAvailable()
                    .transition(.identity)
                    .appShortcut(AppShortcuts.desktopPrimary, appState: appState)
                    .popover(isPresented: $showingPlusDesktopPopover, arrowEdge: .top) {
                        PlusFeaturePopover(message: "Desktop Mode is an AirSync+ feature")
                    }
                    .whatsNewPopover(item: .desktopMode, arrowEdge: .top)

                }
                .padding(.top, 8)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .onAppear {
            WhatsNewTourManager.shared.evaluateActiveItem()
        }
        .onChange(of: appState.adbConnected) { _, _ in
            WhatsNewTourManager.shared.evaluateActiveItem()
        }
        .onChange(of: appState.selectedTab) { _, _ in
            WhatsNewTourManager.shared.evaluateActiveItem()
        }
    }
}

#Preview {
    SidebarView()
}

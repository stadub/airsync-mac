//
//  ScreenView.swift
//  AirSync
//
//  Created by Sameera Sandakelum on 2025-09-20.
//

import SwiftUI
import AppKit

struct ScreenView: View {
    @ObservedObject var appState = AppState.shared
    @State private var showingPlusPopover = false

    var body: some View {
        VStack {
            ConnectionStatusPill()
                .padding(.top, 4)
                .whatsNewPopover(item: .connectionPill, arrowEdge: .top)
            
            ConnectionStateView()
                .padding(.top, 4)

            Spacer()

                TimeView()
            Spacer()

            if appState.adbConnected {
                RecentAppsGridView()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.9)),
                        removal: .opacity.combined(with: .scale(scale: 1.1))
                    ))
            }
            


            if appState.device != nil {
                PhoneQuickActionsView()
            }
            if (appState.status != nil){
                DeviceStatusView()
                    .transition(.scale.combined(with: .opacity))
                    .animation(.interpolatingSpring(stiffness: 200, damping: 30), value: appState.isMusicCardHidden)
            }

        }
        .padding(8)
        .onAppear {
            WhatsNewTourManager.shared.evaluateActiveItem()
        }
        .onChange(of: appState.device) { _, _ in
            WhatsNewTourManager.shared.evaluateActiveItem()
        }
        .onChange(of: appState.selectedTab) { _, _ in
            WhatsNewTourManager.shared.evaluateActiveItem()
        }
        .animation(
            .easeInOut(duration: 0.35),
            value: AppState.shared.adbConnected
        )
        .animation(
            .easeInOut(duration: 0.28),
            value: appState.isMusicCardHidden
        )
    }


}

#Preview {
    ScreenView()
}

/// The phone card's existing actions, also available above embedded mirroring.
enum PhoneQuickAction: String, CaseIterable {
    case sendFiles, browseFiles, muteNotifications, clipboard
}

struct PhoneQuickActionsView: View {
    @ObservedObject var appState = AppState.shared
    @State private var showingPlusPopover = false
    var compact = false
    var actions = Set(PhoneQuickAction.allCases)

    var body: some View {
                HStack(spacing: compact ? 6 : 10){
                    if actions.contains(.sendFiles) {
                    GlassButtonView(
                        label: "Send",
                        systemImage: "square.and.arrow.up",
                        iconOnly: true,
                        circleSize: compact ? 24 : nil,
                        fixedIconSize: 16,
                        action: {
                            let panel = NSOpenPanel()
                            panel.allowsMultipleSelection = true
                            panel.canChooseDirectories = false
                            panel.canChooseFiles = true
                            
                            if panel.runModal() == .OK {
                                QuickShareManager.shared.transferURLs = panel.urls
                                QuickShareManager.shared.startDiscovery()
                                appState.showingQuickShareTransfer = true
                            }
                        }
                    )
                    .help("Send Files")
                    .transition(.identity)
                    .keyboardShortcut(
                        "f",
                        modifiers: .command
                     )

                    }
                    if actions.contains(.browseFiles), appState.device?.ipAddress != "BLE" {
                        GlassButtonView(
                            label: "Browse",
                            systemImage: "folder",
                            iconOnly: true,
                            circleSize: compact ? 24 : nil,
                        fixedIconSize: 16,
                            action: {
                                if appState.isPlus && appState.licenseCheck {
                                    appState.openFileBrowser()
                                } else {
                                    showingPlusPopover = true
                                }
                            }
                        )
                        .help("Browse Files")
                        .transition(.identity)
                        .keyboardShortcut(
                            "b",
                            modifiers: .command
                        )
                        .popover(isPresented: $showingPlusPopover, arrowEdge: .bottom) {
                            PlusFeaturePopover(message: "Browse files with AirSync+")
                        }
                    }

                    if actions.contains(.muteNotifications) {
                    GlassButtonView(
                        label: "Mute",
                        systemImage: appState.silenceAllNotifications ? "bell.slash.fill" : "bell.badge",
                        iconOnly: true,
                        circleSize: compact ? 24 : nil,
                        fixedIconSize: 16,
                        action: {
                            appState.silenceAllNotifications.toggle()
                        }
                    )
                    .help(appState.silenceAllNotifications ? "Unmute Notifications" : "Mute Notifications")
                    .transition(.identity)

                    }
                    if actions.contains(.clipboard) {
                    GlassButtonView(
                        label: "Clipboard",
                        systemImage: "clipboard",
                        iconOnly: true,
                        circleSize: compact ? 24 : nil,
                        fixedIconSize: 16,
                        action: {
                            sendClipboard()
                        }
                    )
                    .help("Send Clipboard")
                    .transition(.identity)
                    }
                }
    }
    private func sendClipboard() {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let firstUrl = urls.first {
            if appState.device?.ipAddress != "BLE" {
                DispatchQueue.global(qos: .userInitiated).async {
                    WebSocketServer.shared.sendFile(url: firstUrl, isClipboard: true)
                }
            } else {
                print("[ScreenView] Cannot send files over BLE")
            }
        } else if let image = NSImage(pasteboard: pasteboard) {
            if appState.device?.ipAddress != "BLE" {
                let tempDir = FileManager.default.temporaryDirectory
                let tempUrl = tempDir.appendingPathComponent("clipboard_image_\(Int(Date().timeIntervalSince1970)).png")
                if let tiffData = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmap.representation(using: .png, properties: [:]) {
                    do {
                        try pngData.write(to: tempUrl)
                        DispatchQueue.global(qos: .userInitiated).async {
                            WebSocketServer.shared.sendFile(url: tempUrl, isClipboard: true)
                        }
                    } catch {
                        print("[ScreenView] Failed to save clipboard image: \(error)")
                    }
                }
            } else {
                print("[ScreenView] Cannot send images over BLE")
            }
        } else if let text = pasteboard.string(forType: .string) {
            appState.sendClipboardToAndroid(text: text)
        }
    }
}

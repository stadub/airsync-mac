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


enum EmbeddedHeaderAction: String, CaseIterable, Identifiable {
    case battery, sound, nowPlaying, wifi, sendFiles, browseFiles, muteNotifications, clipboard
    static let defaults = "battery,sound,nowPlaying,wifi"
    var id: String { rawValue }
    var quickAction: PhoneQuickAction? { PhoneQuickAction(rawValue: rawValue) }
    var label: (title: String, icon: String) {
        switch self {
        case .battery: return ("Battery", "battery.100")
        case .sound: return ("Sound", "speaker.wave.2")
        case .nowPlaying: return ("Now Playing", "music.note")
        case .wifi: return ("Wi-Fi connection", "wifi")
        case .sendFiles: return ("Send Files", "square.and.arrow.up")
        case .browseFiles: return ("Browse Files", "folder")
        case .muteNotifications: return ("Mute notifications", "bell.slash")
        case .clipboard: return ("Send Clipboard", "clipboard")
        }
    }
    static func selected(in value: String) -> [Self] {
        var seen = Set<Self>()
        return value.split(separator: ",").compactMap { raw in
            guard let action = Self(rawValue: String(raw)), seen.insert(action).inserted else { return nil }
            return action
        }
    }
}

struct EmbeddedHeaderEditor: View {
    let desktopMode: Bool
    var onDone: (() -> Void)?
    init(desktopMode: Bool = false, onDone: (() -> Void)? = nil) {
        self.desktopMode = desktopMode
        self.onDone = onDone
        _visible = AppStorage(wrappedValue: EmbeddedHeaderAction.defaults, desktopMode ? "desktopHeaderVisibleButtons" : "embeddedHeaderVisibleButtons")
        _order = AppStorage(wrappedValue: EmbeddedHeaderAction.allCases.map(\.rawValue).joined(separator: ","), desktopMode ? "desktopHeaderButtonOrder" : "embeddedHeaderButtonOrder")
    }

    @Environment(\.dismiss) private var dismiss
    @AppStorage("embeddedHeaderVisibleButtons") private var visible = EmbeddedHeaderAction.defaults
    @AppStorage("embeddedHeaderButtonOrder") private var order = EmbeddedHeaderAction.allCases.map(\.rawValue).joined(separator: ",")
    private var orderedActions: [EmbeddedHeaderAction] {
        let saved = EmbeddedHeaderAction.selected(in: order)
        return saved + EmbeddedHeaderAction.allCases.filter { !saved.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(desktopMode ? "Desktop header buttons" : "Edit header buttons").font(.title2)
            Text("Check buttons to keep them on the top row. Other buttons stay in the section below the expander. Drag rows or use the arrows to change their order.")
                .font(.callout).foregroundStyle(.secondary)
            List {
                ForEach(orderedActions) { action in
                    HStack {
                        Toggle(isOn: selection(for: action)) {
                            HStack(spacing: 10) {
                                Image(systemName: action.label.icon).frame(width: 22)
                                Text(action.label.title)
                            }
                        }
                        .toggleStyle(.checkbox)
                        Spacer()
                        orderButton(action, direction: -1)
                        orderButton(action, direction: 1)
                        Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
                .onMove(perform: move)
            }
            .listStyle(.plain)
            Divider()
            HStack {
                Button("Restore defaults") {
                    visible = EmbeddedHeaderAction.defaults
                    order = EmbeddedHeaderAction.allCases.map(\.rawValue).joined(separator: ",")
                }
                Spacer()
                Button("Done") { if let onDone { onDone() } else { dismiss() } }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 410, height: 490)
    }
    private func orderButton(_ action: EmbeddedHeaderAction, direction: Int) -> some View {
        let index = orderedActions.firstIndex(of: action) ?? 0
        return Button {
            move(from: IndexSet(integer: index), to: index + (direction < 0 ? -1 : 2))
        } label: {
            Image(systemName: direction < 0 ? "arrow.up" : "arrow.down")
                .frame(width: 18, height: 20)
        }
        .buttonStyle(.borderless)
        .disabled(direction < 0 ? index == 0 : index == orderedActions.count - 1)
        .help(direction < 0 ? "Move up" : "Move down")
        .accessibilityLabel("Move \(action.label.title) \(direction < 0 ? "up" : "down")")
    }

    private func selection(for action: EmbeddedHeaderAction) -> Binding<Bool> {
        Binding(get: { EmbeddedHeaderAction.selected(in: visible).contains(action) }, set: { enabled in
            var selected = Set(EmbeddedHeaderAction.selected(in: visible))
            if enabled { selected.insert(action) } else { selected.remove(action) }
            visible = orderedActions.filter { selected.contains($0) }.map(\.rawValue).joined(separator: ",")
        })
    }
    private func move(from source: IndexSet, to destination: Int) {
        var actions = orderedActions
        actions.move(fromOffsets: source, toOffset: destination)
        order = actions.map(\.rawValue).joined(separator: ",")
    }
}

/// The same header is used by embedded and separate phone mirrors.
struct PhoneMirrorHeader: View {
    let desktopMode: Bool
    init(desktopMode: Bool = false, showsMirrorControls: Bool = true, dragWindow: NSWindow? = nil) {
        self.desktopMode = desktopMode
        self.dragWindow = dragWindow
        self.showsMirrorControls = showsMirrorControls
        _headerVisible = AppStorage(wrappedValue: EmbeddedHeaderAction.defaults, desktopMode ? "desktopHeaderVisibleButtons" : "embeddedHeaderVisibleButtons")
        _headerOrder = AppStorage(wrappedValue: EmbeddedHeaderAction.allCases.map(\.rawValue).joined(separator: ","), desktopMode ? "desktopHeaderButtonOrder" : "embeddedHeaderButtonOrder")
    }

    let dragWindow: NSWindow?
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var discoveryManager = DiscoveryManager.shared
    var showsMirrorControls = true
    @State private var showingHeaderControls = false
    @State private var showingHeaderEditor = false
    @AppStorage("embeddedHeaderVisibleButtons") private var headerVisible = EmbeddedHeaderAction.defaults
    @AppStorage("embeddedHeaderButtonOrder") private var headerOrder = EmbeddedHeaderAction.allCases.map(\.rawValue).joined(separator: ",")

    private var orderedHeaderActions: [EmbeddedHeaderAction] {
        let saved = EmbeddedHeaderAction.selected(in: headerOrder)
        return saved + EmbeddedHeaderAction.allCases.filter { !saved.contains($0) }
    }

    private var phoneNameBubble: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    let name = appState.device?.name ?? "AirSync"
                    Text(name.count > 16 ? String(name.prefix(16)) + "..." : name)
                        .font(.title3).help(name)
                    if showsMirrorControls {
                        ForEach(orderedHeaderActions.filter { EmbeddedHeaderAction.selected(in: headerVisible).contains($0) }) { action in
                            headerButton(action)
                        }
                        if !desktopMode {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { showingHeaderControls.toggle() }
                            } label: {
                                Image(systemName: "chevron.down")
                                    .rotationEffect(.degrees(showingHeaderControls ? 180 : 0))
                                    .frame(width: 20, height: 24)
                            }
                            .buttonStyle(.plain).focusable(false)
                            .help("More header controls")
                            .accessibilityLabel("More header controls")
                        }
                    }
                    if let wifiDevice = discoveryManager.availableWifiDeviceForCurrentBLE {
                        GlassButtonView(label: "Switch", systemImage: "wifi") {
                            QuickConnectManager.shared.connect(to: wifiDevice)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.center)
            .frame(height: dragWindow == nil ? 36 : 44)
                if desktopMode && showsMirrorControls {
                    Button { MirrorLayoutEditorWindow.shared.showHeader(desktopMode: true) } label: {
                        Image(systemName: "pencil").frame(width: 24, height: 24).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).focusable(false)
                    .help("Edit desktop header buttons")
                    .accessibilityLabel("Edit desktop header buttons")
                    .padding(.trailing, 8)
                }
            }

            if showsMirrorControls && showingHeaderControls {
                Divider().padding(.horizontal, 10)
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ConnectionStatusPill(useGlass: false, showWiFi: false)
                        ForEach(orderedHeaderActions.filter { !EmbeddedHeaderAction.selected(in: headerVisible).contains($0) }) { action in
                            headerButton(action)
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(.center)
                .frame(height: 28)
                Button { MirrorLayoutEditorWindow.shared.showHeader(desktopMode: desktopMode) } label: {
                    Label("Edit header buttons", systemImage: "slider.horizontal.3")
                        .font(.caption)
                }
                .buttonStyle(.plain).padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .applyGlassViewIfAvailable()
    }

    @ViewBuilder
    private func headerButton(_ action: EmbeddedHeaderAction) -> some View {
        if let quickAction = action.quickAction {
            PhoneQuickActionsView(compact: true, actions: [quickAction])
        } else {
            switch action {
            case .battery:
                DeviceStatusView(showMediaToggle: false, useGlass: false, compact: true, showMediaCard: false, showSound: false)
            case .sound:
                DeviceStatusView(showMediaToggle: false, useGlass: false, compact: true, showMediaCard: false, showBattery: false)
            case .nowPlaying:
                DeviceStatusView(showMediaToggle: true, useGlass: false, compact: true, showMediaCard: false, showBattery: false, showSound: false)
            case .wifi:
                ConnectionStatusPill(showStatuses: false)
            default: EmptyView()
            }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            phoneNameBubble
            if showsMirrorControls, !appState.isMusicCardHidden,
               let music = appState.status?.music,
               !music.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                MediaPlayerView(music: music)
                    .padding(.horizontal, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

        }

    }
}

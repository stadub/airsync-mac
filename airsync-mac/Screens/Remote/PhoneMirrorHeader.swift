import SwiftUI
import AppKit

enum MirrorHeaderAction: String, CaseIterable, Identifiable {
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

struct MirrorHeaderEditor: View {
    var desktopMode = false
    var onDone: (() -> Void)?
    var body: some View {
        let profile: MirrorProfile = desktopMode ? .desktop : .phone
        MirrorButtonEditor(
            title: desktopMode ? "Desktop header buttons" : "Edit header buttons",
            explanation: "Check buttons to keep them on the top row. Other buttons stay in the section below the expander. Drag rows or use the arrows to change their order.",
            actions: MirrorHeaderAction.allCases.map { MirrorButtonDescriptor(id: $0.rawValue, title: $0.label.title, icon: $0.label.icon) },
            defaults: MirrorHeaderAction.defaults,
            visibleKey: profile.headerVisibleKey, orderKey: profile.headerOrderKey,
            height: 490, onDone: onDone
        )
    }
}

/// The same header is used by embedded and separate phone mirrors.
struct PhoneMirrorHeader: View {
    let desktopMode: Bool
    init(desktopMode: Bool = false, showsMirrorControls: Bool = true, dragWindow: NSWindow? = nil) {
        self.desktopMode = desktopMode
        self.dragWindow = dragWindow
        self.showsMirrorControls = showsMirrorControls
        _headerVisible = AppStorage(wrappedValue: MirrorHeaderAction.defaults, (desktopMode ? MirrorProfile.desktop : .phone).headerVisibleKey)
        _headerOrder = AppStorage(wrappedValue: MirrorHeaderAction.allCases.map(\.rawValue).joined(separator: ","), (desktopMode ? MirrorProfile.desktop : .phone).headerOrderKey)
    }

    let dragWindow: NSWindow?
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var discoveryManager = DiscoveryManager.shared
    var showsMirrorControls = true
    @State private var showingHeaderControls = false
    @AppStorage("embeddedHeaderVisibleButtons") private var headerVisible = MirrorHeaderAction.defaults
    @AppStorage("embeddedHeaderButtonOrder") private var headerOrder = MirrorHeaderAction.allCases.map(\.rawValue).joined(separator: ",")

    private var orderedHeaderActions: [MirrorHeaderAction] {
        let saved = MirrorHeaderAction.selected(in: headerOrder)
        return saved + MirrorHeaderAction.allCases.filter { !saved.contains($0) }
    }

    private var phoneNameBubble: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    let name = appState.device?.name ?? "AirSync"
                    if let dragWindow {
                        MirrorNameDragLabel(name: name.count > 16 ? String(name.prefix(16)) + "..." : name, mirror: dragWindow,
                                            onMoved: { MirrorWindowControls.shared.refresh() })
                            .frame(width: 140, height: 28)
                    } else {
                        Text(name.count > 16 ? String(name.prefix(16)) + "..." : name)
                            .font(.title3).help(name)
                    }
                    if showsMirrorControls {
                        ForEach(orderedHeaderActions.filter { MirrorHeaderAction.selected(in: headerVisible).contains($0) }) { action in
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
                        ForEach(orderedHeaderActions.filter { !MirrorHeaderAction.selected(in: headerVisible).contains($0) }) { action in
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
    private func headerButton(_ action: MirrorHeaderAction) -> some View {
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

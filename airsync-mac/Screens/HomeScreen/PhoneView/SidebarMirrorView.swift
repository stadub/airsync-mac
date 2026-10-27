//
//  SidebarMirrorView.swift
//  AirSync
//
//  Created by Sameera Wijerathna on 2026-06-04.
//

import SwiftUI
import MetalKit

struct SidebarMirrorView: View {
    @ObservedObject var appState = AppState.shared
    @StateObject private var streamClient = ScrcpyStreamClient.shared
    @State private var isMirroring = false
    @State private var errorMessage: String?

    private var safeRatio: CGFloat {
        if streamClient.videoWidth > 0 && streamClient.videoHeight > 0 {
            return CGFloat(streamClient.videoWidth) / CGFloat(streamClient.videoHeight)
        }
        return 9.0 / 19.5
    }

    var body: some View {
        ZStack {
            if isMirroring {
                MetalVideoView(streamClient: streamClient)
                    .overlay {
                        if streamClient.videoWidth == 0 {
                            ProgressView()
                        }
                    }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    } else {
                        Text("Connecting...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            startMirroring()
        }
        .onDisappear {
            stopMirroring()
        }
    }

    private func startMirroring() {
        errorMessage = nil
        ScrcpyServerManager.shared.startMirroringSession(appState: AppState.shared, streamClient: streamClient) { success, errorMsg in
            if success {
                self.isMirroring = true
            } else {
                self.errorMessage = errorMsg
            }
        }
    }

    private func stopMirroring() {
        ScrcpyServerManager.shared.stopMirroringSession(streamClient: streamClient)
        isMirroring = false
    }
}


/// Android navigation stays outside the phone image and does not take typing focus.
enum EmbeddedNavigationAction: String, CaseIterable, Identifiable {
    case back, home, recent, notifications, quickSettings, collapsePanels, rotateDevice
    case sendFiles, browseFiles, muteNotifications, clipboard

    static let defaults = "back,home,recent"
    var id: String { rawValue }
    var label: (title: String, icon: String) {
        switch self {
        case .back: return ("Back", "chevron.left")
        case .home: return ("Home", "circle")
        case .recent: return ("Recent Apps", "square")
        case .notifications: return ("Open notifications", "bell")
        case .quickSettings: return ("Quick Settings", "slider.horizontal.3")
        case .collapsePanels: return ("Collapse panels", "chevron.up")
        case .rotateDevice: return ("Rotate screen", "rotate.right")
        case .sendFiles: return ("Send Files", "square.and.arrow.up")
        case .browseFiles: return ("Browse Files", "folder")
        case .muteNotifications: return ("Mute notifications", "bell.slash")
        case .clipboard: return ("Send Clipboard", "clipboard")
        }
    }
    var keycode: UInt32? {
        switch self {
        case .back: return 4
        case .home: return 3
        case .recent: return 187
        default: return nil
        }
    }
    var systemCommand: ScrcpyControlClient.SystemCommand? {
        switch self {
        case .notifications: return .notifications
        case .quickSettings: return .quickSettings
        case .collapsePanels: return .collapsePanels
        case .rotateDevice: return .rotateDevice
        default: return nil
        }
    }
    var quickAction: PhoneQuickAction? { PhoneQuickAction(rawValue: rawValue) }

    static func selected(in value: String) -> [Self] {
        var seen = Set<Self>()
        return value.split(separator: ",").compactMap { raw in
            guard let action = Self(rawValue: String(raw)), seen.insert(action).inserted else { return nil }
            return action
        }
    }
}

struct EmbeddedMirrorNavigationBar: View {
    let desktopMode: Bool
    init(desktopMode: Bool = false, commandHandler: ((EmbeddedNavigationAction) -> Void)? = nil) {
        self.desktopMode = desktopMode
        self.commandHandler = commandHandler
        _buttons = AppStorage(wrappedValue: EmbeddedNavigationAction.defaults, desktopMode ? "desktopNavigationButtons" : "embeddedNavigationButtons")

    }

    @AppStorage("embeddedNavigationButtons") private var buttons = EmbeddedNavigationAction.defaults
    @State private var showingSystemControls = false
    @State private var showingEditor = false
    var commandHandler: ((EmbeddedNavigationAction) -> Void)? = nil

    var body: some View {
        HStack(spacing: 4) {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(EmbeddedNavigationAction.selected(in: buttons)) { action in
                    actionButton(action)
                }
                if !desktopMode {
                Button { showingSystemControls.toggle() } label: {
                    Image(systemName: "chevron.down")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel("More phone controls")
                .help("More phone controls and edit navigation buttons")
                .popover(isPresented: $showingSystemControls, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Phone controls").font(.headline)
                            Spacer()
                            Button { showingSystemControls = false } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Close phone controls")
                            .help("Close")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        Divider()
                        ForEach([EmbeddedNavigationAction.notifications, .quickSettings, .collapsePanels, .rotateDevice]) { action in
                            menuAction(action.label.title, icon: action.label.icon) { perform(action) }
                        }
                        Divider()
                        menuAction("Edit navigation buttons", icon: "slider.horizontal.3") { MirrorLayoutEditorWindow.shared.showNavigation(desktopMode: desktopMode) }
                    }
                    .padding(10)
                    .frame(width: 240)
                    .onExitCommand { showingSystemControls = false }
                }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(.center)
        .frame(height: 44)
            if desktopMode {
                Button { MirrorLayoutEditorWindow.shared.showNavigation(desktopMode: true) } label: {
                    Image(systemName: "pencil").frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain).focusable(false)
                .help("Edit desktop navigation buttons")
                .accessibilityLabel("Edit desktop navigation buttons")
                .padding(.trailing, 8)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))

    }

    @ViewBuilder
    private func actionButton(_ action: EmbeddedNavigationAction) -> some View {
        if let quickAction = action.quickAction {
            PhoneQuickActionsView(compact: true, actions: [quickAction])
        } else {
            Button { perform(action) } label: {
                Image(systemName: action.label.icon)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel(action.label.title)
            .help(action.label.title)
        }
    }

    private func perform(_ action: EmbeddedNavigationAction) {
        if let commandHandler { commandHandler(action); return }
        if let keycode = action.keycode {
            ScrcpyControlClient.shared.sendKeyEvent(action: 0, keycode: keycode)
            ScrcpyControlClient.shared.sendKeyEvent(action: 1, keycode: keycode)
        } else if let command = action.systemCommand {
            ScrcpyControlClient.shared.sendSystemCommand(command)
        }
    }

    private func menuAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            showingSystemControls = false
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 20)
                Text(title)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

struct EmbeddedNavigationEditor: View {
    let desktopMode: Bool
    var onDone: (() -> Void)?
    init(desktopMode: Bool = false, onDone: (() -> Void)? = nil) {
        self.desktopMode = desktopMode
        self.onDone = onDone

        _buttons = AppStorage(wrappedValue: EmbeddedNavigationAction.defaults, desktopMode ? "desktopNavigationButtons" : "embeddedNavigationButtons")
        _order = AppStorage(wrappedValue: EmbeddedNavigationAction.allCases.map(\.rawValue).joined(separator: ","), desktopMode ? "desktopNavigationOrder" : "embeddedNavigationOrder")
    }

    @Environment(\.dismiss) private var dismiss
    @AppStorage("embeddedNavigationButtons") private var buttons = EmbeddedNavigationAction.defaults
    @AppStorage("embeddedNavigationOrder") private var order = EmbeddedNavigationAction.allCases.map(\.rawValue).joined(separator: ",")

    private var orderedActions: [EmbeddedNavigationAction] {
        let saved = EmbeddedNavigationAction.selected(in: order)
        return saved + EmbeddedNavigationAction.allCases.filter { !saved.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(desktopMode ? "Desktop navigation buttons" : "Edit navigation buttons").font(.title2)
            Text("Check buttons to show them below your phone. Drag rows or use the arrows to change their order. Share actions also remain in the header expander.")
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
                    buttons = EmbeddedNavigationAction.defaults
                    order = EmbeddedNavigationAction.allCases.map(\.rawValue).joined(separator: ",")
                }
                Spacer()
                Button("Done") { if let onDone { onDone() } else { dismiss() } }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 410, height: 520)
    }

    private func orderButton(_ action: EmbeddedNavigationAction, direction: Int) -> some View {
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

    private func move(from source: IndexSet, to destination: Int) {
        var actions = orderedActions
        let visible = Set(EmbeddedNavigationAction.selected(in: buttons))
        actions.move(fromOffsets: source, toOffset: destination)
        order = actions.map(\.rawValue).joined(separator: ",")
        buttons = actions.filter { visible.contains($0) }.map(\.rawValue).joined(separator: ",")
    }

    private func selection(for action: EmbeddedNavigationAction) -> Binding<Bool> {
        Binding(
            get: { EmbeddedNavigationAction.selected(in: buttons).contains(action) },
            set: { enabled in
                var selected = Set(EmbeddedNavigationAction.selected(in: buttons))
                if enabled { selected.insert(action) } else { selected.remove(action) }
                buttons = orderedActions.filter { selected.contains($0) }.map(\.rawValue).joined(separator: ",")
            }
        )
    }
}

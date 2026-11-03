import SwiftUI

/// Android navigation stays outside the phone image and does not take typing focus.
enum MirrorNavigationAction: String, CaseIterable, Identifiable {
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

struct MirrorNavigationBar: View {
    let desktopMode: Bool
    init(desktopMode: Bool = false, commandHandler: ((MirrorNavigationAction) -> Void)? = nil) {
        self.desktopMode = desktopMode
        self.commandHandler = commandHandler
        _buttons = AppStorage(wrappedValue: MirrorNavigationAction.defaults, (desktopMode ? MirrorProfile.desktop : .phone).navigationButtonsKey)

    }

    @AppStorage("embeddedNavigationButtons") private var buttons = MirrorNavigationAction.defaults
    @State private var showingSystemControls = false
    var commandHandler: ((MirrorNavigationAction) -> Void)? = nil

    var body: some View {
        HStack(spacing: 4) {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(MirrorNavigationAction.selected(in: buttons)) { action in
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
                        ForEach([MirrorNavigationAction.notifications, .quickSettings, .collapsePanels, .rotateDevice]) { action in
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
    private func actionButton(_ action: MirrorNavigationAction) -> some View {
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

    private func perform(_ action: MirrorNavigationAction) {
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

struct MirrorNavigationEditor: View {
    var desktopMode = false
    var onDone: (() -> Void)?
    var body: some View {
        let profile: MirrorProfile = desktopMode ? .desktop : .phone
        MirrorButtonEditor(
            title: desktopMode ? "Desktop navigation buttons" : "Edit navigation buttons",
            explanation: "Check buttons to show them below your phone. Drag rows or use the arrows to change their order. Share actions also remain in the header expander.",
            actions: MirrorNavigationAction.allCases.map { MirrorButtonDescriptor(id: $0.rawValue, title: $0.label.title, icon: $0.label.icon) },
            defaults: MirrorNavigationAction.defaults,
            visibleKey: profile.navigationButtonsKey, orderKey: profile.navigationOrderKey,
            height: 520, onDone: onDone
        )
    }
}

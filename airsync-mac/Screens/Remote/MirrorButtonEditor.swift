import SwiftUI

struct MirrorButtonDescriptor: Identifiable {
    let id: String
    let title: String
    let icon: String
}

struct MirrorButtonEditor: View {
    let title: String
    let explanation: String
    let actions: [MirrorButtonDescriptor]
    let defaults: String
    let height: CGFloat
    let onDone: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @AppStorage private var visible: String
    @AppStorage private var order: String

    init(title: String, explanation: String, actions: [MirrorButtonDescriptor], defaults: String,
         visibleKey: String, orderKey: String, height: CGFloat, onDone: (() -> Void)?) {
        self.title = title
        self.explanation = explanation
        self.actions = actions
        self.defaults = defaults
        self.height = height
        self.onDone = onDone
        _visible = AppStorage(wrappedValue: defaults, visibleKey)
        _order = AppStorage(wrappedValue: actions.map(\.id).joined(separator: ","), orderKey)
    }

    private var layout: MirrorButtonLayout {
        MirrorButtonLayout(actions: actions.map(\.id), order: order, visible: visible)
    }
    private var orderedActions: [MirrorButtonDescriptor] {
        layout.order.compactMap { id in actions.first { $0.id == id } }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2)
            Text(explanation).font(.callout).foregroundStyle(.secondary)
            List {
                ForEach(orderedActions) { action in
                    HStack {
                        Toggle(isOn: Binding(get: { layout.visible.contains(action.id) }, set: { enabled in
                            var updated = layout
                            if enabled { updated.visible.insert(action.id) } else { updated.visible.remove(action.id) }
                            visible = updated.savedVisible
                        })) {
                            HStack(spacing: 10) {
                                Image(systemName: action.icon).frame(width: 22)
                                Text(action.title)
                            }
                        }.toggleStyle(.checkbox)
                        Spacer()
                        orderButton(action, direction: -1)
                        orderButton(action, direction: 1)
                        Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                    }.padding(.vertical, 3)
                }.onMove(perform: move)
            }.listStyle(.plain)
            Divider()
            HStack {
                Button("Restore defaults") {
                    visible = defaults
                    order = actions.map(\.id).joined(separator: ",")
                }
                Spacer()
                Button("Done") { if let onDone { onDone() } else { dismiss() } }
                    .keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 410, height: height)
    }
    private func orderButton(_ action: MirrorButtonDescriptor, direction: Int) -> some View {
        let index = layout.order.firstIndex(of: action.id) ?? 0
        return Button {
            move(from: IndexSet(integer: index), to: index + (direction < 0 ? -1 : 2))
        } label: {
            Image(systemName: direction < 0 ? "arrow.up" : "arrow.down").frame(width: 18, height: 20)
        }
        .buttonStyle(.borderless)
        .disabled(direction < 0 ? index == 0 : index == orderedActions.count - 1)
        .help(direction < 0 ? "Move up" : "Move down")
        .accessibilityLabel("Move \(action.title) \(direction < 0 ? "up" : "down")")
    }
    private func move(from source: IndexSet, to destination: Int) {
        var updated = layout
        updated.move(from: source, to: destination)
        order = updated.savedOrder
        visible = updated.savedVisible
    }
}

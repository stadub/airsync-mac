import Foundation

/// Normalizes saved identifiers against the current action set, preserving order.
nonisolated struct MirrorButtonLayout {
    let actions: [String]
    var order: [String]
    var visible: Set<String>

    init(actions: [String], order: String, visible: String) {
        self.actions = actions
        var seen = Set<String>()
        self.order = (order.split(separator: ",").map(String.init) + actions)
            .filter { actions.contains($0) && seen.insert($0).inserted }
        self.visible = Set(visible.split(separator: ",").map(String.init)).intersection(actions)
    }

    mutating func move(from source: IndexSet, to destination: Int) {
        let moving = order.enumerated().filter { source.contains($0.offset) }.map(\.element)
        let remaining = order.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let index = min(remaining.count, max(0, destination - source.filter { $0 < destination }.count))
        order = Array(remaining.prefix(index)) + moving + Array(remaining.dropFirst(index))
    }

    var savedOrder: String { order.joined(separator: ",") }
    var savedVisible: String { order.filter { visible.contains($0) }.joined(separator: ",") }
}

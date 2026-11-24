import AppKit

struct HistoryBrowsePosition: Equatable {
    static let start = Self(entryID: "", index: 0, fraction: 0)
    let entryID: String
    let index: Int
    let fraction: CGFloat

    func resolvedIndex(in ids: [String]) -> Int? {
        guard !ids.isEmpty else { return nil }
        return ids.firstIndex(of: entryID) ?? min(index, ids.count - 1)
    }
}

/// Session-only state survives panel destruction and temporary screen removal.
final class HistoryBrowseMemory {
    static let shared = HistoryBrowseMemory()
    static let didChange = Notification.Name("HistoryBrowseMemoryDidChange")
    private var positions: [HistoryPanelFilter: HistoryBrowsePosition] = [:]
    private(set) var selectedFilter: HistoryPanelFilter = .all
    private var latestAddedFilter: HistoryPanelFilter?

    subscript(filter: HistoryPanelFilter) -> HistoryBrowsePosition? { positions[filter] }

    func noteAddition(_ filter: HistoryPanelFilter) {
        latestAddedFilter = filter
    }

    /// Consume once for all screens. Without a new addition, keep the user's bookmark.
    @discardableResult
    func prepareForOpening(source: AnyObject) -> Bool {
        guard let filter = latestAddedFilter else { return false }
        latestAddedFilter = nil
        selectedFilter = filter
        // An absent ID intentionally resolves to index zero, including after an async reload.
        positions[filter] = .start
        notify(source: source)
        return true
    }

    func select(_ filter: HistoryPanelFilter, source: AnyObject) {
        guard selectedFilter != filter else { return }
        selectedFilter = filter
        notify(source: source)
    }

    func remember(_ position: HistoryBrowsePosition, for filter: HistoryPanelFilter, source: AnyObject) {
        guard positions[filter] != position else { return }
        positions[filter] = position
        notify(source: source)
    }

    private func notify(source: AnyObject) {
        NotificationCenter.default.post(name: Self.didChange, object: self, userInfo: ["source": source])
    }
}

struct HistoryPreviewSchedule: Equatable {
    let range: ClosedRange<Int>?
    let forward: Bool
    let pixelSize: Int
    let generation: Int
}

struct HistoryPreviewLoadGate {
    private var previous: HistoryPreviewSchedule?

    mutating func reset() { previous = nil }

    mutating func update(_ next: HistoryPreviewSchedule, force: Bool) -> (visible: Bool, prefetch: Bool) {
        let visible = force || previous?.range != next.range || previous?.pixelSize != next.pixelSize
            || previous?.generation != next.generation
        let prefetch = force || previous != next
        previous = next
        return (visible, prefetch)
    }
}

enum HistorySamplingPolicy {
    static func interval(hasPanels: Bool, hoverEnabled: Bool, active: Bool,
                         nearEntry: Bool, suspended: Bool) -> TimeInterval? {
        guard hasPanels, !suspended, hoverEnabled || active else { return nil }
        return active || nearEntry ? 0.035 : 0.1
    }
}

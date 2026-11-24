import AppKit

/// Shared category selection; scroll positions are deliberately not retained.
final class HistoryFilterState {
    static let shared = HistoryFilterState()
    static let didChange = Notification.Name("HistoryFilterStateDidChange")
    private(set) var selectedFilter: HistoryPanelFilter = .all
    private var latestAddedFilter: HistoryPanelFilter?

    func noteAddition(_ filter: HistoryPanelFilter) {
        latestAddedFilter = filter
    }

    /// Every opening starts at the newest content on all screens.
    @discardableResult
    func prepareForOpening(source: AnyObject) -> Bool {
        let hasAddition = latestAddedFilter != nil
        if let filter = latestAddedFilter {
            selectedFilter = filter
            latestAddedFilter = nil
        }
        notify(source: source)
        return hasAddition
    }

    func select(_ filter: HistoryPanelFilter, source: AnyObject) {
        guard selectedFilter != filter else { return }
        selectedFilter = filter
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

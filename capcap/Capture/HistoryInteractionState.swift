import AppKit

/// A cancellable dwell, shared by all filter buttons in one panel.
final class HistoryFilterDwell {
    private var work: DispatchWorkItem?
    private var generation = 0

    func schedule(after delay: TimeInterval = 0.2, action: @escaping () -> Void) {
        cancel()
        let expected = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == expected else { return }
            self.work = nil
            action()
        }
        self.work = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func cancel() {
        generation += 1
        work?.cancel()
        work = nil
    }

    deinit { work?.cancel() }
}

struct HistoryBrowsePosition {
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
    private var positions: [String: HistoryBrowsePosition] = [:]

    subscript(context: String, filter: HistoryPanelFilter) -> HistoryBrowsePosition? {
        get { positions["\(context)/\(filter)"] }
        set { positions["\(context)/\(filter)"] = newValue }
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

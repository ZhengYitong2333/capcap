import AppKit

protocol HistoryHoverSamplingClient: AnyObject {
    var needsActiveSampling: Bool { get }
    func isNearEntry(_ point: NSPoint) -> Bool
    func suspendPointerSampling()
    func samplePointer(_ point: NSPoint, moved: Bool)
}

/// One timer for every screen, owned by the history controller.
final class HistoryHoverSampler {
    private struct Client {
        weak var value: HistoryHoverSamplingClient?
    }
    private var clients: [ObjectIdentifier: Client] = [:]
    private var timer: DispatchSourceTimer?
    private var interval: TimeInterval?
    private var previousPoint: NSPoint?
    private var suspended = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observe(workspace, name) { [weak self] in self?.setSuspended(true) }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observe(workspace, name) { [weak self] in self?.setSuspended(false) }
        }
        observe(.default, .historyNotchTriggerDidChange) { [weak self] in self?.refresh() }
        observe(.default, .historyPanelDisplayModesDidChange) { [weak self] in self?.refresh() }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { [weak self] in self?.setSuspended(true) }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in self?.setSuspended(false) }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, action: @escaping () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in action() }
        observers.append((center, token))
    }

    deinit {
        timer?.cancel()
        observers.forEach { $0.0.removeObserver($0.1) }
    }

    func register(_ client: HistoryHoverSamplingClient) {
        clients[ObjectIdentifier(client)] = Client(value: client)
        refresh()
    }

    func unregister(_ client: HistoryHoverSamplingClient) {
        clients.removeValue(forKey: ObjectIdentifier(client))
        refresh()
    }

    private func setSuspended(_ value: Bool) {
        suspended = value
        if value { clients.values.compactMap(\.value).forEach { $0.suspendPointerSampling() } }
        previousPoint = nil
        refresh()
    }

    func refresh() { tick(force: true) }

    private func tick(force: Bool = false) {
        clients = clients.filter { $0.value.value != nil }
        let point = NSEvent.mouseLocation
        let live = clients.values.compactMap(\.value)
        let moved = force || point != previousPoint
        previousPoint = point
        if !suspended {
            live.forEach { $0.samplePointer(point, moved: moved) }
        }
        let next = HistorySamplingPolicy.interval(
            hasPanels: !live.isEmpty, hoverEnabled: Defaults.historyNotchTriggerMode == .hover,
            active: live.contains { $0.needsActiveSampling },
            nearEntry: live.contains { $0.isNearEntry(point) }, suspended: suspended)
        guard next != interval else { return }
        timer?.cancel()
        timer = nil
        interval = next
        guard let next else { return }
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + next, repeating: next, leeway: .milliseconds(8))
        source.setEventHandler { [weak self] in self?.tick() }
        timer = source
        source.resume()
    }
}

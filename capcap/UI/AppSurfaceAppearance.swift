import AppKit

/// Surface palettes share background transparency without fading their controls.
enum AppSurfaceAppearance {
    private static let accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
    ) { _ in NotificationCenter.default.post(name: .historyPanelAppearanceDidChange, object: nil) }

    static var colors: [NSColor] {
        palette(transparency: Defaults.historyPanelTransparencyPercent,
                reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
    }

    static func palette(transparency: Int, reduceTransparency: Bool) -> [NSColor] {
        let alpha: CGFloat = reduceTransparency ? 1 : 1 - CGFloat(min(100, max(0, transparency))) / 100
        return [
            NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.17, alpha: alpha),
            NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.14, alpha: alpha),
            NSColor(calibratedRed: 0.11, green: 0.10, blue: 0.10, alpha: alpha),
        ]
    }

    static func update(_ gradient: CAGradientLayer) {
        _ = accessibilityObserver
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.colors = colors.map(\.cgColor)
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        CATransaction.commit()
    }
}

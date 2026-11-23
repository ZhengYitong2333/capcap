import AppKit

/// Surface palettes share background transparency without fading their controls.
enum AppSurfaceAppearance {
    static var colors: [NSColor] {
        let alpha = 1 - CGFloat(Defaults.historyPanelTransparencyPercent) / 100
        return [
            NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.17, alpha: alpha),
            NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.14, alpha: alpha),
            NSColor(calibratedRed: 0.11, green: 0.10, blue: 0.10, alpha: alpha),
        ]
    }

    static func update(_ gradient: CAGradientLayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.colors = colors.map(\.cgColor)
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        CATransaction.commit()
    }
}

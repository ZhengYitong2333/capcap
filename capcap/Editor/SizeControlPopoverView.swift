import AppKit

/// Adjusts the shared toolbar scale without changing annotation state or undo.
final class SizeControlPopoverView: NSView {
    static let preferredSize = NSSize(width: 292, height: 118)

    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let slider: HUDSlider
    private var chips: [SizePresetChip] = []

    init() {
        slider = HUDSlider(
            frame: .zero,
            value: Double(Defaults.toolbarSizePercent),
            minValue: Double(Defaults.toolbarSizeRange.lowerBound),
            maxValue: Double(Defaults.toolbarSizeRange.upperBound),
            target: nil,
            action: nil
        )
        super.init(frame: NSRect(origin: .zero, size: Self.preferredSize))
        wantsLayer = true
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .labelColor
        addSubview(titleLabel)
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        addSubview(valueLabel)

        for value: CGFloat in [75, 100, 125, 150, 200] {
            let chip = SizePresetChip(value: value)
            chip.onPress = { [weak self] value in self?.setScale(value) }
            chips.append(chip)
            addSubview(chip)
        }
        slider.isContinuous = true
        slider.keyboardStep = Double(Defaults.toolbarSizeStep)
        slider.target = self
        slider.action = #selector(sliderChanged)
        addSubview(slider)
        NotificationCenter.default.addObserver(self, selector: #selector(syncScale),
                                               name: .toolbarSizeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateLocalization),
                                               name: .languageDidChange, object: nil)
        updateLocalization()
        syncScale()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func layout() {
        super.layout()
        let padding: CGFloat = 16
        let contentWidth = max(1, bounds.width - padding * 2)
        let titleY = bounds.height - padding - 18
        titleLabel.frame = NSRect(x: padding, y: titleY, width: contentWidth - 60, height: 18)
        valueLabel.frame = NSRect(x: bounds.width - padding - 60, y: titleY, width: 60, height: 18)
        let chipHeight: CGFloat = 22
        let chipY = titleY - 10 - chipHeight
        let gap: CGFloat = 6
        let chipWidth = (contentWidth - gap * CGFloat(chips.count - 1)) / CGFloat(chips.count)
        for (index, chip) in chips.enumerated() {
            chip.frame = NSRect(x: padding + CGFloat(index) * (chipWidth + gap),
                                y: chipY, width: chipWidth, height: chipHeight)
        }
        slider.frame = NSRect(x: padding, y: chipY - 8 - HUDSlider.preferredHeight,
                              width: contentWidth, height: HUDSlider.preferredHeight)
    }

    @objc private func updateLocalization() {
        titleLabel.stringValue = L10n.toolbarSize
        slider.setAccessibilityLabel(L10n.toolbarSize)
    }

    @objc private func sliderChanged() { setScale(CGFloat(slider.doubleValue)) }

    private func setScale(_ value: CGFloat) {
        // Defaults normalizes both settings and popover edits to the same step.
        Defaults.toolbarSizePercent = Int(value.rounded())
        syncScale()
    }

    @objc private func syncScale() {
        let value = Defaults.toolbarSizePercent
        slider.doubleValue = Double(value)
        valueLabel.stringValue = "\(value)%"
        for chip in chips { chip.isSelected = Int(chip.sizeValue) == value }
    }
}

/// Rounded numeric preset button that matches the editor's floating HUD.
private final class SizePresetChip: NSButton {
    let sizeValue: CGFloat
    var onPress: ((CGFloat) -> Void)?
    var isSelected = false {
        didSet { needsDisplay = true }
    }

    init(value: CGFloat) {
        sizeValue = value
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        title = Self.format(value)
        target = self
        action = #selector(pressed)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func pressed() {
        onPress?(sizeValue)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        if isSelected {
            accentGreen.withAlphaComponent(0.22).setFill()
        } else {
            AdaptiveChrome.subtleFill.setFill()
        }
        path.fill()
        if isSelected {
            accentGreen.withAlphaComponent(0.55).setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: isSelected ? NSColor.labelColor : NSColor.secondaryLabelColor,
        ]
        let text = Self.format(sizeValue)
        let textSize = (text as NSString).size(withAttributes: attributes)
        let textRect = NSRect(
            x: floor((bounds.width - textSize.width) / 2),
            y: floor((bounds.height - textSize.height) / 2),
            width: textSize.width,
            height: textSize.height
        )
        (text as NSString).draw(in: textRect, withAttributes: attributes)
    }

    private static func format(_ value: CGFloat) -> String {
        "\(Int(value))%"
    }
}

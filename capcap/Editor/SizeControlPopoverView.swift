import AppKit

/// Everything the size popover needs for the currently active annotation tool.
struct SizeControlConfiguration {
    let title: String
    let detail: String?
    let minimum: CGFloat
    let maximum: CGFloat
    let currentValue: CGFloat
    let presets: [CGFloat]
}

/// Compact popover content for adjusting the active tool's line width, badge
/// size, font size, or mosaic strength. Preset chips and the slider both report
/// through the same began/changed/ended callbacks so drags stay one undo step.
final class SizeControlPopoverView: NSView {
    static let preferredSize = NSSize(width: 292, height: 118)

    var onEditingBegan: (() -> Void)?
    var onValueChanged: ((CGFloat) -> Void)?
    var onEditingEnded: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let slider: HUDSlider
    private var chips: [SizePresetChip] = []
    private var isEditing = false

    init(configuration: SizeControlConfiguration) {
        slider = HUDSlider(
            frame: .zero,
            value: Double(configuration.currentValue),
            minValue: Double(configuration.minimum),
            maxValue: Double(configuration.maximum),
            target: nil,
            action: nil
        )
        super.init(frame: NSRect(origin: .zero, size: Self.preferredSize))
        wantsLayer = true

        titleLabel.stringValue = configuration.title
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .labelColor
        addSubview(titleLabel)

        if let detail = configuration.detail, !detail.isEmpty {
            detailLabel.stringValue = detail
            detailLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            detailLabel.textColor = .secondaryLabelColor
            detailLabel.alignment = .right
            addSubview(detailLabel)
        }

        for value in configuration.presets {
            let chip = SizePresetChip(value: value)
            chip.onPress = { [weak self] value in self?.selectPreset(value) }
            chips.append(chip)
            addSubview(chip)
        }

        slider.isContinuous = true
        slider.onEditingBegan = { [weak self] in self?.beginEditing() }
        slider.onEditingEnded = { [weak self] in self?.endEditing() }
        slider.target = self
        slider.action = #selector(sliderChanged)
        addSubview(slider)

        updateSelectedChip(configuration.currentValue)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let padding: CGFloat = 16
        let contentWidth = max(1, bounds.width - padding * 2)
        let titleY = bounds.height - padding - 18
        titleLabel.frame = NSRect(x: padding, y: titleY, width: contentWidth, height: 18)
        detailLabel.frame = NSRect(x: padding, y: titleY + 2, width: contentWidth, height: 14)

        let chipHeight: CGFloat = 22
        let chipY = titleY - 10 - chipHeight
        if !chips.isEmpty {
            let gap: CGFloat = 6
            let available = contentWidth - gap * CGFloat(chips.count - 1)
            let chipWidth = max(24, available / CGFloat(chips.count))
            var x = padding
            for chip in chips {
                chip.frame = NSRect(x: x, y: chipY, width: chipWidth, height: chipHeight)
                x += chipWidth + gap
            }
        }

        let sliderY = chipY - 8 - HUDSlider.preferredHeight
        slider.frame = NSRect(x: padding, y: sliderY, width: contentWidth, height: HUDSlider.preferredHeight)
    }

    @objc private func sliderChanged() {
        let value = CGFloat(slider.doubleValue)
        updateSelectedChip(value)
        onValueChanged?(value)
    }

    private func selectPreset(_ value: CGFloat) {
        beginEditing()
        slider.doubleValue = Double(value)
        updateSelectedChip(value)
        onValueChanged?(value)
        endEditing()
    }

    private func beginEditing() {
        guard !isEditing else { return }
        isEditing = true
        onEditingBegan?()
    }

    private func endEditing() {
        guard isEditing else { return }
        isEditing = false
        onEditingEnded?()
    }

    private func updateSelectedChip(_ value: CGFloat) {
        for chip in chips {
            chip.isSelected = abs(chip.sizeValue - value) < 0.001
        }
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
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

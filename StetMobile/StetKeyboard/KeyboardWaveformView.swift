import UIKit

final class KeyboardWaveformView: UIView {
    private static let barCount = 9
    private static let minimumLevel: CGFloat = 0.1

    private var levels = Array(repeating: minimumLevel, count: barCount)
    private var smoothedLevel: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 92, height: 28)
    }

    override func draw(_ rect: CGRect) {
        guard !bounds.isEmpty else { return }

        tintColor.setFill()
        let spacing: CGFloat = 4
        let totalSpacing = spacing * CGFloat(levels.count - 1)
        let barWidth = max(2, (bounds.width - totalSpacing) / CGFloat(levels.count))

        for (index, level) in levels.enumerated() {
            let height = max(3, bounds.height * level)
            let origin = CGPoint(
                x: CGFloat(index) * (barWidth + spacing),
                y: (bounds.height - height) / 2
            )
            let barRect = CGRect(origin: origin, size: CGSize(width: barWidth, height: height))
            UIBezierPath(
                roundedRect: barRect,
                cornerRadius: min(barWidth, height) / 2
            ).fill()
        }
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        setNeedsDisplay()
    }

    func update(level: Float) {
        let normalizedLevel = min(max(CGFloat(level), 0), 1)
        let smoothing: CGFloat = normalizedLevel > smoothedLevel ? 0.48 : 0.18
        smoothedLevel += (normalizedLevel - smoothedLevel) * smoothing

        levels.removeFirst()
        levels.append(max(Self.minimumLevel, smoothedLevel))
        setNeedsDisplay()
    }

    func reset() {
        smoothedLevel = 0
        levels = Array(repeating: Self.minimumLevel, count: Self.barCount)
        setNeedsDisplay()
    }

    private func configure() {
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        contentMode = .redraw
    }
}

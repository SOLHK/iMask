import SwiftUI
import UIKit

/// Small custom PiP content updated at the reference project's 60 FPS cadence.
final class RefreshSurfaceView: UIView {
    private var phase: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false
        clipsToBounds = true
        contentMode = .redraw
        accessibilityElementsHidden = true
    }

    required init?(coder: NSCoder) { return nil }

    func advance(to timestamp: CFTimeInterval) {
        phase = CGFloat(timestamp.truncatingRemainder(dividingBy: 2.4) / 2.4)
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let count = 40
        let spacing = bounds.width / CGFloat(count)
        let center = bounds.midY
        context.setFillColor(UIColor.systemBlue.cgColor)
        for index in 0..<count {
            let wave = sin(CGFloat(index) * 0.32 - phase * .pi * 2)
            let height = max(0.1, (0.22 + 0.68 * abs(wave)) * bounds.height)
            let bar = CGRect(x: CGFloat(index) * spacing + 1, y: center - height / 2,
                             width: max(1, spacing - 3), height: height)
            context.addPath(UIBezierPath(roundedRect: bar, cornerRadius: 2).cgPath)
            context.fillPath()
        }
    }
}

struct RefreshPreview: UIViewRepresentable {
    let session: RefreshSession

    func makeUIView(context: Context) -> RefreshSurfaceView {
        let view = RefreshSurfaceView(frame: CGRect(x: 0, y: 0, width: 300, height: 44))
        session.attach(view)
        return view
    }

    func updateUIView(_ view: RefreshSurfaceView, context: Context) {
        session.attach(view)
    }
}

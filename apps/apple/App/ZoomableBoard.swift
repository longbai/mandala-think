import SwiftUI
import UIKit

final class BoardZoomInteraction {
    private var isPinching = false
    private var lastPinchEnd = -Double.infinity

    var allowsSelection: Bool {
        !isPinching && ProcessInfo.processInfo.systemUptime - lastPinchEnd > 0.15
    }

    func pinchBegan() { isPinching = true }

    func pinchEnded() {
        isPinching = false
        lastPinchEnd = ProcessInfo.processInfo.systemUptime
    }
}

struct ZoomableBoard<Content: View>: UIViewControllerRepresentable {
    let side: CGFloat
    let resetToken: Int
    let interaction: BoardZoomInteraction
    let content: Content

    init(side: CGFloat, resetToken: Int, interaction: BoardZoomInteraction, @ViewBuilder content: () -> Content) {
        self.side = side
        self.resetToken = resetToken
        self.interaction = interaction
        self.content = content()
    }

    func makeUIViewController(context: Context) -> Controller {
        Controller(content: content, side: side, resetToken: resetToken, interaction: interaction)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.update(content: content, resetToken: resetToken)
    }

    final class Controller: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        private let scroll = UIScrollView()
        private let host: UIHostingController<Content>
        private let side: CGFloat
        private let interaction: BoardZoomInteraction
        private var resetToken: Int
        private var viewport = CGSize.zero
        private var startingScale: CGFloat = 1
        private var focalPoint = CGPoint.zero
        private lazy var pinch = UIPinchGestureRecognizer(target: self, action: #selector(zoom(_:)))

        init(content: Content, side: CGFloat, resetToken: Int, interaction: BoardZoomInteraction) {
            host = UIHostingController(rootView: content)
            self.side = side
            self.resetToken = resetToken
            self.interaction = interaction
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("Use init(content:side:resetToken:)") }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            scroll.backgroundColor = .clear
            scroll.delegate = self
            scroll.contentInsetAdjustmentBehavior = .never
            scroll.showsHorizontalScrollIndicator = false
            scroll.showsVerticalScrollIndicator = false
            scroll.accessibilityIdentifier = "expanded-canvas"
            scroll.translatesAutoresizingMaskIntoConstraints = false
            pinch.cancelsTouchesInView = true
            pinch.delegate = self
            view.addGestureRecognizer(pinch)
            view.addSubview(scroll)
            NSLayoutConstraint.activate([
                scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                scroll.topAnchor.constraint(equalTo: view.topAnchor),
                scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            addChild(host)
            host.view.backgroundColor = .clear
            host.view.frame = CGRect(x: 0, y: 0, width: side, height: side)
            scroll.addSubview(host.view)
            scroll.contentSize = host.view.bounds.size
            host.didMove(toParent: self)
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            let size = scroll.bounds.size
            guard size.width > 0, size.height > 0, size != viewport else { return }
            let previousScale = scroll.zoomScale
            let previousFit = scroll.minimumZoomScale
            let wasFitted = viewport == .zero || abs(previousScale - previousFit) < 0.001
            let oldCenter = CGPoint(x: (scroll.contentOffset.x + viewport.width / 2) / previousScale,
                                    y: (scroll.contentOffset.y + viewport.height / 2) / previousScale)
            viewport = size

            let fit = min(size.width, size.height) / side
            scroll.maximumZoomScale = max(3, fit * 4)
            scroll.minimumZoomScale = fit
            scroll.pinchGestureRecognizer?.isEnabled = false
            if wasFitted {
                fitCanvas()
            } else {
                scroll.setZoomScale(min(scroll.maximumZoomScale, fit * previousScale / previousFit), animated: false)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                place(oldCenter, at: center)
            }
        }

        func update(content: Content, resetToken: Int) {
            host.rootView = content
            if self.resetToken != resetToken {
                self.resetToken = resetToken
                if viewport != .zero { fitCanvas() }
            }
        }

        @objc private func zoom(_ gesture: UIPinchGestureRecognizer) {
            let point = gesture.location(in: scroll)
            switch gesture.state {
            case .began:
                interaction.pinchBegan()
                startingScale = scroll.zoomScale
                focalPoint = CGPoint(x: point.x / startingScale, y: point.y / startingScale)
            case .changed:
                let location = CGPoint(x: point.x - scroll.contentOffset.x, y: point.y - scroll.contentOffset.y)
                let scale = max(scroll.minimumZoomScale, min(scroll.maximumZoomScale, startingScale * gesture.scale))
                scroll.setZoomScale(scale, animated: false)
                place(focalPoint, at: location)
            case .ended, .cancelled:
                interaction.pinchEnded()
            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            gestureRecognizer === pinch
        }

        private func place(_ point: CGPoint, at position: CGPoint) {
            centerCanvas()
            let scale = scroll.zoomScale
            let inset = scroll.contentInset
            let size = scroll.bounds.size
            let offset = CGPoint(
                x: min(max(-inset.left, point.x * scale - position.x),
                       max(-inset.left, scroll.contentSize.width - size.width + inset.right)),
                y: min(max(-inset.top, point.y * scale - position.y),
                       max(-inset.top, scroll.contentSize.height - size.height + inset.bottom))
            )
            scroll.setContentOffset(offset, animated: false)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { host.view }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerCanvas()
            updateZoomAccessibility()
        }

        private func updateZoomAccessibility() {
            scroll.accessibilityValue = Double(scroll.zoomScale / scroll.minimumZoomScale).formatted(.percent)
        }

        private func fitCanvas() {
            scroll.setZoomScale(scroll.minimumZoomScale, animated: false)
            centerCanvas()
            scroll.setContentOffset(CGPoint(x: -scroll.contentInset.left, y: -scroll.contentInset.top), animated: false)
            updateZoomAccessibility()
        }

        private func centerCanvas() {
            let x = max(0, (scroll.bounds.width - host.view.frame.width) / 2)
            let y = max(0, (scroll.bounds.height - host.view.frame.height) / 2)
            scroll.contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
        }
    }
}

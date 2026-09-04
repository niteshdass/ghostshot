import AppKit
import Foundation

/// A borderless, non-activating panel that is absent from screen shares and
/// recordings because its `sharingType` is `.none`.
final class OverlayPanel: NSPanel {
    private let textView = NSTextView()
    private let scrollView = NSScrollView()
    private let statusLabel = NSTextField(labelWithString: "")

    /// Called whenever the user drags or resizes the panel, so the frame persists.
    var onFrameChange: ((CGRect) -> Void)?

    init(initialFrame: CGRect?) {
        let frame = initialFrame ?? OverlayPanel.defaultFrame()
        super.init(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        // The stealth properties. sharingType = .none keeps this window out of
        // ScreenCaptureKit output, which is what every screen-share app uses.
        sharingType = .none
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        isMovableByWindowBackground = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        buildContentView()
        delegate = self
        orderOut(nil)
    }

    // A panel with .nonactivatingPanel must opt in to being key, or the text
    // view can never be scrolled or selected.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private static func defaultFrame() -> CGRect {
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let width: CGFloat = 460
        let height: CGFloat = 520
        return CGRect(
            x: visible.maxX - width - 24,
            y: visible.maxY - height - 24,
            width: width,
            height: height
        )
    }

    private func buildContentView() {
        let container = NSVisualEffectView()
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textColor = .labelColor
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 10, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(scrollView)
        container.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -4),

            statusLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            statusLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            statusLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])

        contentView = container
    }

    // MARK: - Content

    func setStatus(_ text: String) {
        assertMain()
        statusLabel.stringValue = text
    }

    func setAnswer(_ text: String, status: String) {
        assertMain()
        textView.string = text
        statusLabel.stringValue = status
        textView.scroll(NSPoint(x: 0, y: 0))
    }

    // MARK: - Visibility

    /// Shows without stealing focus from whatever the user is doing.
    func showWithoutFocus() {
        assertMain()
        orderFrontRegardless()
    }

    func toggleVisibility() {
        assertMain()
        if isVisible {
            orderOut(nil)
        } else {
            showWithoutFocus()
        }
    }

    private func assertMain() {
        dispatchPrecondition(condition: .onQueue(.main))
    }
}

extension OverlayPanel: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        onFrameChange?(frame)
    }

    func windowDidResize(_ notification: Notification) {
        onFrameChange?(frame)
    }
}

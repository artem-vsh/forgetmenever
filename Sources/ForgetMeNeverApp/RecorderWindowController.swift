import AppKit
import SwiftUI

final class RecorderWindowController: NSWindowController, NSWindowDelegate {
    private let viewModel: RecorderViewModel
    private let onCancel: () -> Void
    private let onSend: () -> Void

    init(viewModel: RecorderViewModel, hotKeyHint: String, onCancel: @escaping () -> Void, onSend: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onCancel = onCancel
        self.onSend = onSend

        let contentView = RecorderView(viewModel: viewModel, hotKeyHint: hotKeyHint, sendAction: onSend, cancelAction: onCancel)
        let window = RecorderWindow(contentRect: Self.defaultFrame, styleMask: [.titled], backing: .buffered, defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.animationBehavior = .documentWindow
        window.collectionBehavior = [.canJoinAllSpaces, .transient]
        window.backgroundColor = NSColor.windowBackgroundColor
        window.sendHandler = onSend
        window.cancelHandler = onCancel
        super.init(window: window)

        window.contentView = NSHostingView(rootView: contentView)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        onCancel()
    }

    private static var defaultFrame: NSRect {
        NSRect(x: 0, y: 0, width: 420, height: 320)
    }
}

private final class RecorderWindow: NSPanel {
    var cancelHandler: (() -> Void)?
    var sendHandler: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49: // Space
            sendHandler?()
        case 53: // Escape
            cancelHandler?()
        default:
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        cancelHandler?()
    }
}

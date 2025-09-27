import AppKit
import SwiftUI
import Darwin

@main
@MainActor
final class ForgetMeNeverApplication: NSObject, NSApplicationDelegate {
    private static var sharedDelegate: ForgetMeNeverApplication?

    static func main() {
        let delegate = ForgetMeNeverApplication()
        sharedDelegate = delegate
        let application = NSApplication.shared
        application.delegate = delegate
        setbuf(stdout, nil)
        print("[ForgetMeNever] Bootstrapping application…")
        application.run()
        sharedDelegate = nil
    }

    private var statusItem: NSStatusItem?
    private var hotKeyManager: GlobalHotKeyManager?
    private var windowController: RecorderWindowController?
    private var viewModel: RecorderViewModel?
    private var config: AppConfig?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        do {
            let config = try AppConfig.load()
            self.config = config
            let audioRecorder = AudioRecorder()
            let backendClient = BackendAPIClient(config: config)
            let viewModel = RecorderViewModel(audioRecorder: audioRecorder, backendClient: backendClient)
            self.viewModel = viewModel

            windowController = RecorderWindowController(
                viewModel: viewModel,
                hotKeyHint: config.hotkey.displayName,
                onCancel: { [weak self] in self?.handleCancel() },
                onSend: { [weak self] in self?.handleSend() }
            )

            try registerHotKey(using: config)
            configureStatusItem(hotKeyDescription: config.hotkey.displayName)
            print("[ForgetMeNever] Backend endpoint: \(config.transcriptEndpoint.absoluteString)")
            viewModel.bootstrap()
            print("[ForgetMeNever] Ready. Menu bar icon added. Shortcut: \(config.hotkey.displayName)")
        } catch {
            print("[ForgetMeNever] Failed to launch: \(error.localizedDescription)")
            presentStartupError(error)
        }
    }

    @objc private func captureNoteViaMenu(_ sender: Any?) {
        presentCaptureWindow()
    }

    @objc private func quitApplication(_ sender: Any?) {
        NSApp.terminate(sender)
    }

    private func registerHotKey(using config: AppConfig) throws {
        hotKeyManager = try GlobalHotKeyManager(hotKey: config.hotkey) { [weak self] in
            DispatchQueue.main.async {
                self?.presentCaptureWindow()
            }
        }
    }

    private func configureStatusItem(hotKeyDescription: String) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "ForgetMeNever")
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "ForgetMeNever — shortcut: \(hotKeyDescription)"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Capture note (\(hotKeyDescription))", action: #selector(captureNoteViaMenu(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit ForgetMeNever", action: #selector(quitApplication(_:)), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }

        statusItem.menu = menu
        self.statusItem = statusItem
    }

    private func presentCaptureWindow() {
        guard let viewModel, let windowController else { return }
        viewModel.cancelSession(resetState: true)
        viewModel.startSession()
        windowController.present()
        print("[ForgetMeNever] Recording session started")
    }

    private func handleSend() {
        print("[ForgetMeNever] Send triggered")
        viewModel?.stopAndTranscribe()
    }

    private func handleCancel() {
        print("[ForgetMeNever] Recording cancelled")
        viewModel?.cancelSession()
        windowController?.hide()
    }

    func applicationWillTerminate(_ notification: Notification) {
        print("[ForgetMeNever] Shutting down")
    }

    private func presentStartupError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(error: error)
        alert.messageText = "Unable to start ForgetMeNever"
        alert.informativeText = error.localizedDescription
        alert.runModal()
        NSApp.terminate(nil)
    }
}

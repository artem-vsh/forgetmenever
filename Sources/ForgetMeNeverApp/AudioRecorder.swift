import AVFoundation
import Foundation

@MainActor
final class AudioRecorder {
    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?

    var isRecording: Bool {
        engine?.isRunning ?? false
    }

    func startRecording() async throws -> URL {
        let granted = await requestMicrophoneAccess()
        guard granted else {
            throw RecorderError.permissionDenied
        }

        stopCurrentEngineIfNeeded()

        let engine = AVAudioEngine()
        self.engine = engine

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        enableVoiceIsolationIfAvailable(on: inputNode)

        let url = makeRecordingURL()
        recordingURL = url
        audioFile = try AVAudioFile(forWriting: url, settings: format.settings)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            do {
                try self.audioFile?.write(from: buffer)
            } catch {
                print("[ForgetMeNever] Audio write error: \(error.localizedDescription)")
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            self.engine = nil
            throw RecorderError.failedToStart
        }

        return url
    }

    func stopRecording() -> URL? {
        guard let engine else {
            let url = recordingURL
            recordingURL = nil
            audioFile = nil
            return url
        }

        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }

        let url = recordingURL
        recordingURL = nil
        audioFile = nil
        self.engine = nil
        return url
    }

    func cancelRecording() {
        if let url = stopRecording() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func stopCurrentEngineIfNeeded() {
        if let engine, engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        audioFile = nil
        recordingURL = nil
    }

    private func enableVoiceIsolationIfAvailable(on inputNode: AVAudioInputNode) {
        guard inputNode.responds(to: #selector(AVAudioInputNode.setVoiceProcessingEnabled(_:))) else { return }
        do {
            try inputNode.setVoiceProcessingEnabled(true)
            print("[ForgetMeNever] Voice isolation enabled")
        } catch {
            print("[ForgetMeNever] Voice isolation unavailable: \(error.localizedDescription)")
        }
    }

    private func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func makeRecordingURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForgetMeNever", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
    }

    enum RecorderError: Error {
        case permissionDenied
        case failedToStart
    }
}

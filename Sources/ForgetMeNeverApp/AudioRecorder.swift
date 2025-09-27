import AVFoundation
import Foundation

@MainActor
final class AudioRecorder {
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    var isRecording: Bool {
        recorder?.isRecording ?? false
    }

    func startRecording() async throws -> URL {
        let granted = await requestMicrophoneAccess()
        guard granted else {
            throw RecorderError.permissionDenied
        }

        let url = makeRecordingURL()
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.prepareToRecord()
            guard recorder.record() else {
                throw RecorderError.failedToStart
            }
            self.recorder = recorder
            self.recordingURL = url
            return url
        } catch {
            throw RecorderError.underlying(error)
        }
    }

    func stopRecording() -> URL? {
        guard let recorder else {
            return recordingURL
        }
        recorder.stop()
        let url = recordingURL
        recordingURL = nil
        self.recorder = nil
        return url
    }

    func cancelRecording() {
        if let url = stopRecording() {
            try? FileManager.default.removeItem(at: url)
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
        case underlying(Error)
    }
}

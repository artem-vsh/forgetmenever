import Foundation

@MainActor
final class RecorderViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        case processing
        case finished
        case failed
    }

    @Published var phase: Phase = .idle
    @Published var recognizedText: String = ""
    @Published var errorMessage: String?
    @Published var statusMessage: String = ""

    private let audioRecorder: AudioRecorder
    private let apiClient: TranscriptionAPIClient
    private var activeRecordingURL: URL?
    private var task: Task<Void, Never>?

    init(audioRecorder: AudioRecorder, apiClient: TranscriptionAPIClient) {
        self.audioRecorder = audioRecorder
        self.apiClient = apiClient
    }

    func startSession() {
        task?.cancel()
        recognizedText = ""
        errorMessage = nil
        statusMessage = "Ready"
        phase = .idle

        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                self.statusMessage = "Preparing microphone…"
                let url = try await self.audioRecorder.startRecording()
                self.activeRecordingURL = url
                self.statusMessage = "Recording…"
                self.phase = .recording
                print("[ForgetMeNever] Recording audio to \(url.lastPathComponent)")
            } catch {
                self.phase = .failed
                self.errorMessage = self.describe(error)
                self.statusMessage = "Unable to start recording"
                print("[ForgetMeNever] Failed to start recording: \(error.localizedDescription)")
            }
        }
    }

    func stopAndTranscribe() {
        guard phase == .recording else { return }
        statusMessage = "Processing…"
        phase = .processing
        guard let recordingURL = audioRecorder.stopRecording() ?? activeRecordingURL else {
            phase = .failed
            errorMessage = "Recording is not available."
            return
        }

        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                try? FileManager.default.removeItem(at: recordingURL)
                self.activeRecordingURL = nil
            }
            do {
                let transcription = try await self.apiClient.transcribe(audioFileURL: recordingURL)
                self.recognizedText = transcription
                self.statusMessage = "Completed"
                self.phase = .finished
                print("[ForgetMeNever] Transcription received (\(transcription.count) chars)")
            } catch {
                self.errorMessage = self.describe(error)
                self.statusMessage = "Recognition failed"
                self.phase = .failed
                print("[ForgetMeNever] Transcription failed: \(error.localizedDescription)")
            }
        }
    }

    func cancelSession(resetState: Bool = true) {
        task?.cancel()
        audioRecorder.cancelRecording()
        if resetState {
            phase = .idle
            statusMessage = ""
            recognizedText = ""
            errorMessage = nil
            activeRecordingURL = nil
        }
    }

    var isRecording: Bool {
        phase == .recording
    }

    var isProcessing: Bool {
        phase == .processing
    }

    private func describe(_ error: Error) -> String {
        if let recorderError = error as? AudioRecorder.RecorderError {
            switch recorderError {
            case .permissionDenied:
                return "Microphone permission is required."
            case .failedToStart:
                return "Unable to start recording. Please check your input device."
            case let .underlying(underlyingError):
                return "Recorder error: \(underlyingError.localizedDescription)"
            }
        }
        if let apiError = error as? TranscriptionAPIClient.TranscriptionError {
            switch apiError {
            case .invalidResponse:
                return "Invalid response from transcription service."
            case let .server(status, body):
                return "Server error (\(status)): \(body)"
            }
        }
        if (error as NSError).code == NSUserCancelledError {
            return "Operation cancelled."
        }
        return error.localizedDescription
    }
}

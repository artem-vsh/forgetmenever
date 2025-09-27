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

    struct TodoDisplayItem: Identifiable, Equatable {
        let id: String
        let text: String
        let dueDisplay: String?
        let isHighlighted: Bool
    }

    @Published var phase: Phase = .idle
    @Published var recognizedText: String = ""
    @Published var errorMessage: String?
    @Published var statusMessage: String = ""
    @Published var todoItems: [TodoDisplayItem] = []

    private let audioRecorder: AudioRecorder
    private let backendClient: BackendAPIClient
    private var activeRecordingURL: URL?
    private var task: Task<Void, Never>?

    private static let backendDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    init(audioRecorder: AudioRecorder, backendClient: BackendAPIClient) {
        self.audioRecorder = audioRecorder
        self.backendClient = backendClient
    }

    func bootstrap() {
        refreshTodoList(highlightedKeys: [])
    }

    func startSession() {
        task?.cancel()
        recognizedText = ""
        errorMessage = nil
        statusMessage = "Ready"
        phase = .idle
        refreshTodoList(highlightedKeys: [])

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
                let transcription = try await self.backendClient.transcribe(audioFileURL: recordingURL)
                self.recognizedText = transcription
                self.statusMessage = "Updating to-do list…"

                let event = try await self.backendClient.process(prompt: transcription)
                self.applyTodoListEvent(event)
                self.statusMessage = self.statusMessage(for: event.type)
                self.phase = .finished
                print("[ForgetMeNever] Transcription received (\(transcription.count) chars)")
            } catch {
                self.errorMessage = self.describe(error)
                self.statusMessage = "Operation failed"
                self.phase = .failed
                print("[ForgetMeNever] Processing pipeline failed: \(error.localizedDescription)")
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

    // MARK: - Private helpers

    private func refreshTodoList(highlightedKeys: Set<String>) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let items = try await self.backendClient.fetchTodoList()
                self.applyTodoItems(items, highlightedKeys: highlightedKeys)
            } catch {
                print("[ForgetMeNever] Failed to fetch to-do list: \(error.localizedDescription)")
            }
        }
    }

    private func applyTodoListEvent(_ event: BackendAPIClient.TodoListEventResponse) {
        let highlighted = Set((event.updated ?? []).map(key(for:)))
        applyTodoItems(event.newList.items, highlightedKeys: highlighted)
        refreshTodoList(highlightedKeys: highlighted)
    }

    private func applyTodoItems(_ items: [BackendAPIClient.TodoItemDTO], highlightedKeys: Set<String>) {
        todoItems = items.map { item in
            let key = key(for: item)
            let dueDisplay = formattedDue(item.due)
            return TodoDisplayItem(id: key, text: item.text, dueDisplay: dueDisplay, isHighlighted: highlightedKeys.contains(key))
        }
    }

    private func formattedDue(_ due: String?) -> String? {
        guard let due, !due.isEmpty else { return nil }
        if let date = Self.backendDateFormatter.date(from: due) {
            return "Due: \(Self.displayDateFormatter.string(from: date))"
        }
        return "Due: \(due)"
    }

    private func key(for item: BackendAPIClient.TodoItemDTO) -> String {
        "\(item.text.lowercased())|\(item.due?.lowercased() ?? "<none>")"
    }

    private func statusMessage(for eventType: String) -> String {
        switch eventType {
        case "updated":
            return "To-do list updated"
        case "removed":
            return "Items removed"
        case "retrieved":
            return "Current to-do list"
        default:
            return "Done"
        }
    }

    private func describe(_ error: Error) -> String {
        if let recorderError = error as? AudioRecorder.RecorderError {
            switch recorderError {
            case .permissionDenied:
                return "Microphone permission is required."
            case .failedToStart:
                return "Unable to start recording. Please check your input device."
            }
        }
        if let apiError = error as? BackendAPIClient.APIError {
            switch apiError {
            case .invalidResponse:
                return "Invalid response from backend service."
            case let .server(status, body):
                return "Backend error (\(status)): \(body)"
            }
        }
        if (error as NSError).code == NSUserCancelledError {
            return "Operation cancelled."
        }
        return error.localizedDescription
    }
}

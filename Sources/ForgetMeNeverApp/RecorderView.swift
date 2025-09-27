import SwiftUI

struct RecorderView: View {
    @ObservedObject var viewModel: RecorderViewModel
    let hotKeyHint: String
    let sendAction: () -> Void
    let cancelAction: () -> Void

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 20) {
                leftPane
                    .frame(width: max(geometry.size.width * 0.33, 260))
                Divider()
                rightPane
                    .frame(width: geometry.size.width * 0.67, alignment: .top)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 720, minHeight: 380)
    }

    private var leftPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(statusLine)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if !viewModel.recognizedText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recognized text")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    ScrollView {
                        Text(viewModel.recognizedText)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.08))
                            )
                    }
                    .frame(maxHeight: 180)
                }
            }

            if viewModel.isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Sending audio for transcription…")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Send", action: sendAction)
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(!viewModel.isRecording)
                Button("Close", action: cancelAction)
                    .keyboardShortcut(.escape, modifiers: [])
            }
        }
    }

    private var rightPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("To-do list")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
            }

            if viewModel.todoItems.isEmpty {
                Text("No to-do items yet.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(viewModel.todoItems) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.text)
                                    .font(.body)
                                if let due = item.dueDisplay {
                                    Text(due)
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(item.isHighlighted ? Color.blue.opacity(0.18) : Color.gray.opacity(0.08))
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer()
        }
    }

    private var title: String {
        switch viewModel.phase {
        case .idle:
            return "Ready to record"
        case .recording:
            return "Listening…"
        case .processing:
            return "Processing…"
        case .finished:
            return "Transcription ready"
        case .failed:
            return "Something went wrong"
        }
    }

    private var statusLine: String {
        if !viewModel.statusMessage.isEmpty {
            return viewModel.statusMessage
        }
        return "Global shortcut: \(hotKeyHint). Press Space to send, Esc to cancel."
    }
}

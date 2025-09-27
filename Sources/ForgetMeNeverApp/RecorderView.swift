import SwiftUI

struct RecorderView: View {
    @ObservedObject var viewModel: RecorderViewModel
    let hotKeyHint: String
    let sendAction: () -> Void
    let cancelAction: () -> Void

    var body: some View {
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
                    }
                    .frame(maxHeight: 150)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2))
                    )
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

            HStack {
                Spacer()
                Button("Send", action: sendAction)
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(!viewModel.isRecording)
                Button("Close", action: cancelAction)
                    .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .padding(24)
        .frame(minWidth: 380, minHeight: 260)
    }

    private var title: String {
        switch viewModel.phase {
        case .idle:
            return "Ready to record"
        case .recording:
            return "Listening…"
        case .processing:
            return "Sending to model…"
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

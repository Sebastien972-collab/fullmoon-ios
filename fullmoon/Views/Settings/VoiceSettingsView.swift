#if os(iOS)
import SwiftUI

struct VoiceSettingsView: View {
    @Environment(NoctisVoiceModel.self) private var model
    @Environment(\.replySpeaker) private var speaker
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("noctis.voice.useKokoro") private var useNoctisVoice = false
    @State private var previewID = UUID()
    @State private var hasPreviewed = false

    private var isPreviewing: Bool { speaker?.currentMessageID == previewID }

    var body: some View {
        Form {
            Section {
                if case .ready = model.state {
                    Picker(selection: $useNoctisVoice) {
                        Text("System voice", tableName: "Settings").tag(false)
                        Text("Noctis voice", tableName: "Settings").tag(true)
                    } label: {
                        Text("Reply voice", tableName: "Settings")
                    }
                    .pickerStyle(.inline)
                } else {
                    LabeledContent {
                        Text("System voice", tableName: "Settings")
                    } label: {
                        Text("Reply voice", tableName: "Settings")
                    }
                }
            }

            Section {
                switch model.state {
                case .notInstalled:
                    Button(action: model.download) {
                        HStack {
                            Text("Download voice", tableName: "Settings")
                            Spacer()
                            Text(NoctisVoiceModel.downloadSize, format: .byteCount(style: .file, allowedUnits: .mb))
                                .foregroundStyle(.secondary)
                        }
                    }
                case .downloading(let fraction):
                    ProgressView(value: fraction) {
                        Text("Installing voice…", tableName: "Settings")
                    } currentValueLabel: {
                        if let fraction { Text(fraction, format: .percent.precision(.fractionLength(0))) }
                    }
                    Button(role: .cancel, action: model.cancelDownload) {
                        Text("Cancel download", tableName: "Settings")
                    }
                case .failed(let reason):
                    Text(verbatim: reason)
                        .foregroundStyle(.secondary)
                    Button(action: model.download) {
                        Text("Retry download", tableName: "Settings")
                    }
                case .ready:
                    previewButton
                }
            } header: {
                Text("French Noctis voice", tableName: "Settings")
            } footer: {
                Text("After download, this voice reads replies directly on your device.", tableName: "Settings")
            }
        }
        .modifier(ThemedForm())
        .navigationTitle(Text("Voice", tableName: "Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear(perform: stopPreview)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { stopPreview() }
        }
    }

    @ViewBuilder private var previewButton: some View {
        if let speaker {
            Button {
                if isPreviewing {
                    speaker.stop()
                } else {
                    hasPreviewed = true
                    speaker.previewNoctis(
                        text: "Bonjour, je suis Noctis. De quoi aimerais-tu parler ?",
                        messageID: previewID
                    )
                }
            } label: {
                Label {
                    if isPreviewing {
                        Text("Stop sample", tableName: "Settings")
                    } else {
                        Text("Listen to sample", tableName: "Settings")
                    }
                } icon: {
                    Image(systemName: isPreviewing ? "stop.fill" : "play.fill")
                }
            }
            .disabled(speaker.isDictating)
            if hasPreviewed, let error = speaker.previewError {
                Text(verbatim: error)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stopPreview() {
        if isPreviewing { speaker?.stop() }
    }
}
#endif

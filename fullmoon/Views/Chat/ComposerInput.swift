#if os(iOS)
import AVFoundation
import NoctisChatUI
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ComposerInput: View {
    @Binding var prompt: String
    var isEnabled: Bool
    var isSending: Bool
    var isStopping: Bool
    var isLoading: Bool
    var modelName: String
    var status: LocalizedStringResource
    var onSend: (ChatInputOrigin) -> Void
    var onStop: (() -> Void)?
    var focus: FocusState<Bool>.Binding

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isEnabled) private var controlsEnabled
    @Environment(AppManager.self) private var appManager
    @Environment(\.composerRequest) private var externalAction
    @Environment(\.composerProjectTitle) private var projectTitle
    @Environment(\.composerThreadID) private var threadID
    @Environment(\.composerIsWorkspaceDraft) private var isWorkspaceDraft
    @Environment(\.composerDrafts) private var sharedDrafts
    @Environment(\.handsFreeConversation) private var handsFree
    @Environment(\.replySpeaker) private var replySpeaker
    @State private var localDrafts = ComposerDrafts()
    @ScaledMetric(relativeTo: .body) private var fontScale = 1.0
    @State private var attachments = [ComposerAttachmentContent]()
    @State private var style = ComposerStyle.standard
    @State private var action: ComposerAction?
    @State private var photo: PhotosPickerItem?
    @State private var error: String?
    @State private var pending: Task<Void, Never>?
    @State private var requestID: UUID?
    @State private var voice = ComposerDictation()
    @State private var voiceLocation: ComposerDrafts.Location?
    @State private var sendAfterDictation = false
    @State private var dictatedDraft: ComposerDraftKey?

    private var drafts: ComposerDrafts { sharedDrafts ?? localDrafts }

    private var location: ComposerDrafts.Location {
        if isWorkspaceDraft { return .workspace }
        if let threadID { return .thread(threadID) }
        return .newThread(project: projectTitle)
    }

    private var hasContent: Bool {
        !attachments.isEmpty || !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var readyToSend: Bool { isEnabled && !isSending && !isLoading && requestID == nil }
    private var canSend: Bool { readyToSend && hasContent }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !attachments.isEmpty {
                ComposerAttachmentRow(attachments: attachments) { item in
                    attachments.removeAll { $0.id == item.id }
                    cacheDraft()
                }
            }
            HStack(alignment: .bottom, spacing: 4) {
                if let handsFree, handsFree.isActive {
                    HandsFreeComposerBar(session: handsFree, submit: { send(speech: $0) }, reportError: { error = $0 })
                } else {
                    standardControls
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .background {
            NoctisFloatingSurface(
                cornerRadius: DesignTokens.composerRadius,
                style: appManager.appearance.useGlass ? .standard : .opaque
            )
        }
        .simultaneousGesture(DragGesture(minimumDistance: 32).onEnded { value in
            if value.translation.height < -45 && abs(value.translation.width) < -value.translation.height / 2 {
                present(.context)
            }
        })
        .photosPicker(isPresented: presented(.photo), selection: $photo, matching: .images)
        .fileImporter(isPresented: presented(.file), allowedContentTypes: ComposerExtraction.allowedTypes) { result in
            switch result {
            case .success(let url):
                load { try await Task.detached(priority: .userInitiated) { try ComposerExtraction.file(url) }.value }
            case .failure(let failure):
                if !ComposerAttachmentError.isCancellation(failure) { error = failure.localizedDescription }
            }
        }
        .onChange(of: photo) { _, selected in
            guard let selected else { return }
            photo = nil
            load {
                guard let transfer = try await selected.loadTransferable(type: ComposerPhotoTransfer.self) else {
                    throw ComposerAttachmentError.unsupported
                }
                return transfer.content
            }
        }
        .fullScreenCover(isPresented: presented(.camera)) {
            ComposerCamera { image in
                action = nil
                guard let image else { return }
                load {
                    try await Task.detached(priority: .userInitiated) {
                        guard let data = image.jpegData(compressionQuality: 0.8) else {
                            throw ComposerAttachmentError.unsupported
                        }
                        return try ComposerExtraction.photo(data)
                    }.value
                }
            }
            .ignoresSafeArea()
            .noctisAppLock()
        }
        .sheet(isPresented: presented(.context)) {
            ComposerContextPanel(
                modelName: modelName, projectTitle: projectTitle, attachments: attachments,
                style: Binding(get: { style }, set: { style = $0; cacheDraft() })
            )
            .noctisAppLock()
        }
        .alert(composerCopy("Composer"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("common.button.ok") { error = nil }
        } message: { Text(verbatim: error ?? "") }
        .onChange(of: ComposerDraftKey(location: location, text: prompt), initial: true) { old, new in
            if dictatedDraft != new { dictatedDraft = nil }
            if old.location != new.location {
                cancelPending()
                cancelDictation()
                action = nil
                error = nil
            }
            if old.location != new.location || old == new { restoreDraft(for: new.location) }
            let components = ComposerAttachmentContent.split(new.text)
            if !components.attachments.isEmpty {
                attachments = components.attachments
                prompt = components.prompt
                style = .standard
                cacheDraft()
            }
        }
        .onChange(of: externalAction?.wrappedValue, initial: true) { _, requested in
            guard let requested else { return }
            externalAction?.wrappedValue = nil
            present(requested)
        }
        .onChange(of: voice.completion) {
            if voice.phase == .idle { finishDictation() }
        }
        .onChange(of: controlsEnabled) { _, enabled in
            if !enabled { pauseDictation() }
        }
        .onChange(of: isSending) { _, sending in
            if sending { pauseDictation() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || (phase == .inactive && voice.phase == .listening) { pauseDictation() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if type == AVAudioSession.InterruptionType.began.rawValue { pauseDictation() }
        }
        .onDisappear {
            cancelPending()
            cancelDictation()
        }
    }

    @ViewBuilder
    private var standardControls: some View {
        if voiceLocation != nil {
            Button { cancelDictation() } label: {
                NoctisIcon(.close, size: 18).frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(composerCopy("Cancel dictation"))
            ComposerListeningIndicator(voice: voice)
        } else {
            ComposerActionsMenu(canStartConversation: canStartConversation, present: present)
                .disabled(isSending || requestID != nil)
            editor
        }
        sendButton
    }

    private var canStartConversation: Bool {
        handsFree != nil && readyToSend
    }

    private func presented(_ value: ComposerAction) -> Binding<Bool> {
        Binding(get: { action == value }, set: { shown in
            if shown { action = value } else if action == value { action = nil }
        })
    }

    private var editor: some View {
        TextField("chat.input.placeholder", text: $prompt, axis: .vertical)
            .font(.system(size: appManager.appearance.fontSize * fontScale))
            .lineLimit(1...5)
            .textFieldStyle(.plain)
            .focused(focus)
            .padding(.vertical, 10)
            .accessibilityIdentifier("noctis.messageComposer")
            .accessibilityLabel("chat.input.accessibility.label")
            .accessibilityHint(status)
            .onKeyPress(.return, phases: .down) { press in
                guard press.modifiers == .command, canSend else { return .ignored }
                appManager.playHaptic()
                send()
                return .handled
            }
    }

    private var sendButton: some View {
        ComposerPrimaryButton(mode: primaryMode, disabled: primaryDisabled) {
            if isSending {
                onStop?()
            } else if voice.phase == .listening {
                sendAfterDictation = isEnabled && !isLoading
                voice.finish()
            } else if hasContent {
                send()
            } else {
                present(.voice)
            }
        }
    }

    private var primaryMode: ComposerPrimaryButton.Mode {
        if isSending { return isStopping ? .stopping : .stop }
        switch voice.phase {
        case .authorizing: return .authorizing
        case .finishing: return .finishing
        case .listening: return isEnabled && !isLoading ? .sendDictation : .insert
        case .idle: return hasContent ? .send : .microphone
        }
    }

    private var primaryDisabled: Bool {
        if isSending { return isStopping || onStop == nil }
        if voiceLocation != nil { return voice.phase != .listening }
        return (hasContent && !canSend) || requestID != nil
    }
}

extension ComposerInput {
    private func present(_ selected: ComposerAction) {
        guard voiceLocation == nil, handsFree?.isActive != true, controlsEnabled,
              !isSending || selected == .context else { return }
        if selected == .handsFree {
            guard canStartConversation else { return }
            focus.wrappedValue = false
            handsFree?.start()
            return
        }
        if selected == .voice {
            guard requestID == nil, replySpeaker?.isDictating != true else { return }
            focus.wrappedValue = false
            voiceLocation = location
            sendAfterDictation = false
            replySpeaker?.setDictating(true)
            voice.start()
            return
        }
        focus.wrappedValue = false
        if [.file, .photo, .camera].contains(selected), attachments.count >= 3 {
            error = ComposerAttachmentError.maximum.localizedDescription
            return
        }
        if selected == .camera {
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                error = composerCopy("No camera is available.")
                return
            }
            cancelPending()
            let ticket = UUID()
            requestID = ticket
            pending = Task {
                let allowed = await AVCaptureDevice.requestAccess(for: .video)
                guard requestID == ticket, !Task.isCancelled else { return }
                requestID = nil
                if allowed {
                    action = .camera
                } else {
                    error = composerCopy("Allow camera access in Settings to capture a document.")
                }
            }
        } else {
            action = selected
        }
    }

    private func cancelDictation() {
        guard voiceLocation != nil else { return }
        voiceLocation = nil
        sendAfterDictation = false
        voice.cancel()
        replySpeaker?.setDictating(false)
    }

    private func pauseDictation() {
        guard voiceLocation != nil else { return }
        sendAfterDictation = false
        voice.cancel()
        finishDictation(wasInterrupted: true)
    }

    private func finishDictation(wasInterrupted: Bool = false) {
        guard let origin = voiceLocation else { return }
        voiceLocation = nil
        replySpeaker?.setDictating(false)
        let shouldSend = sendAfterDictation
        sendAfterDictation = false
        guard origin == location else { return }
        let words = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !words.isEmpty {
            if !prompt.isEmpty, prompt.last?.isWhitespace == false { prompt.append(" ") }
            prompt.append(contentsOf: words)
        }
        if let failure = voice.error {
            error = failure
        } else if !words.isEmpty, !wasInterrupted {
            dictatedDraft = ComposerDraftKey(location: location, text: prompt)
            if shouldSend, controlsEnabled, scenePhase == .active { send() }
        }
    }

    private func load(_ operation: @escaping () async throws -> ComposerAttachmentContent) {
        cancelPending()
        guard attachments.count < 3 else { error = ComposerAttachmentError.maximum.localizedDescription; return }
        let ticket = UUID()
        requestID = ticket
        pending = Task {
            defer { if requestID == ticket { requestID = nil } }
            do {
                let content = try await operation()
                guard requestID == ticket, !Task.isCancelled else { return }
                attachments.append(content)
                cacheDraft()
            } catch {
                if requestID == ticket, !Task.isCancelled, !ComposerAttachmentError.isCancellation(error) {
                    self.error = error.localizedDescription
                }
            }
        }
    }

    private func restoreDraft(for location: ComposerDrafts.Location) {
        let saved = drafts.values[location]
        attachments = saved?.attachments ?? []
        style = saved?.style ?? .standard
    }

    private func cacheDraft() {
        if attachments.isEmpty && style == .standard {
            drafts.values.removeValue(forKey: location)
        } else {
            drafts.values[location] = .init(attachments: attachments, style: style)
        }
    }

    private func cancelPending() {
        pending?.cancel()
        requestID = nil
        pending = nil
    }

    private func send(speech: String? = nil) {
        guard readyToSend, speech != nil || hasContent else { return }
        let original = prompt
        let wasDictated = dictatedDraft == ComposerDraftKey(location: location, text: original)
        let origin: ChatInputOrigin = speech == nil ? (wasDictated ? .dictation : .keyboard) : .handsFree
        let question = (speech ?? original).trimmingCharacters(in: .whitespacesAndNewlines)
        let text = question.isEmpty ? composerCopy("Summarize the attached text.") : question
        do {
            let request = [text, style.instruction].compactMap { $0 }.joined(separator: "\n\n")
            prompt = try ComposerAttachmentContent.combine(request, with: attachments)
            onSend(origin)
            if prompt.isEmpty {
                dictatedDraft = nil
                attachments.removeAll()
                if speech != nil { prompt = original }
                cacheDraft()
            } else {
                prompt = original
            }
        } catch { self.error = error.localizedDescription }
    }
}
#endif

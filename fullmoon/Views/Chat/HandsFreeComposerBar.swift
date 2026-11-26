#if os(iOS)
import AVFAudio
import SwiftUI

struct HandsFreeComposerBar: View {
    let session: HandsFreeConversation
    let submit: (String) -> Void
    let reportError: (String) -> Void

    @Environment(\.replySpeaker) private var speaker
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isEnabled) private var enabled
    @State private var voice = ComposerDictation()
    @State private var ownsMicrophone = false

    var body: some View {
        HStack(spacing: 8) {
            if session.phase == .listening {
                ComposerListeningIndicator(voice: voice)
            } else {
                Label(composerCopy("Noctis is responding…"), systemImage: "waveform")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(role: .destructive, action: end) {
                Label(composerCopy("End voice conversation"), systemImage: "phone.down.fill")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("noctis.voice.end")
        }
        .padding(.leading, 12)
        .task(id: session.phase) {
            guard !Task.isCancelled, session.phase == .listening else { return }
            guard enabled, scenePhase == .active, speaker?.isDictating != true else { end(); return }
            ownsMicrophone = true
            speaker?.setDictating(true)
            voice.start(finishAfterSilence: true)
        }
        .onChange(of: voice.completion) { completeTurn() }
        .onChange(of: enabled) { _, enabled in if !enabled { end() } }
        .onChange(of: scenePhase) { _, phase in
            // Speech and microphone permission dialogs temporarily make the scene inactive.
            if phase == .background || (phase == .inactive && voice.phase != .authorizing) { end() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notice in
            let type = notice.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if type == AVAudioSession.InterruptionType.began.rawValue { end() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notice in
            let reason = notice.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { end() }
        }
        .onDisappear(perform: end)
    }

    private func completeTurn() {
        guard ownsMicrophone, session.phase == .listening else { return }
        releaseMicrophone()
        guard enabled, scenePhase == .active || voice.error != nil else { end(); return }
        let words = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard voice.error == nil, !words.isEmpty else {
            let message = voice.error ?? composerCopy("No speech detected. Voice conversation ended.")
            end()
            reportError(message)
            return
        }
        submit(words)
        // A rejected send or a persistence error must never leave the microphone armed.
        if session.phase == .listening { end() }
    }

    private func releaseMicrophone() {
        guard ownsMicrophone else { return }
        ownsMicrophone = false
        speaker?.setDictating(false)
    }

    private func end() {
        session.end()
        voice.cancel()
        releaseMicrophone()
    }
}
#endif

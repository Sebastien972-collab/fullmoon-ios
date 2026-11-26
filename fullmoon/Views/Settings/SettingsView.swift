//
//  SettingsView.swift
//  fullmoon
//
//  Created by Jordan Singer on 10/4/24.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppManager.self) private var appManager
    @Binding var currentThread: Thread?
    @Bindable var viewModel: ChatView.ViewModel
    let onBack: () -> Void

    private var modelStatus: ModelStatus {
        ModelStatus(
            isConnected: viewModel.isConnected,
            isLoading: viewModel.isLoading,
            isDownloading: viewModel.loadPhase == .downloading,
            error: viewModel.submissionError
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink(destination: AppearanceSettingsView()) {
                        Label("settings.row.appearance", systemImage: "paintpalette")
                    }

                    NavigationLink(destination: ChatsSettingsView(currentThread: $currentThread)) {
                        Label("settings.row.conversations", systemImage: "message")
                    }

                    #if os(iOS)
                    NavigationLink(destination: VoiceSettingsView()) {
                        Label {
                            Text("Voice", tableName: "Settings")
                        } icon: {
                            Image(systemName: "waveform")
                        }
                    }
                    #endif
                }

                Section {
                    NavigationLink(destination: NoctisIdentitySettingsView()) {
                        Label("identity.title", systemImage: "person.crop.circle")
                    }
                    NavigationLink(destination: NoctisPrivacySettingsView()) {
                        Label("privacy.title", systemImage: "lock.icloud")
                    }
                }

                Section {
                    LabeledContent("model.runtime.label") {
                        Text(viewModel.modelRuntime.title)
                    }
                    LabeledContent("État") {
                        HStack {
                            if modelStatus.isBusy {
                                ProgressView()
                                    .controlSize(.small)
                                    .accessibilityHidden(true)
                            }
                            Text(modelStatus.title)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("modelStatus")
                        }
                    }
                    #if os(iOS)
                    if let reason = viewModel.modelFallbackReason {
                        Text(reason)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    #endif
                    if case .failed(let message) = modelStatus {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    if modelStatus.canLoad {
                        Button(viewModel.submissionError == nil ? "Charger le modèle" : "Réessayer") {
                            Task { await viewModel.loadModel() }
                        }
                    }
                } header: {
                    Text("Modèle IA")
                } footer: {
                    Text("model.runtime.settings.description")
                }

                Section {
                    NavigationLink(destination: CreditsView()) {
                        Text("settings.row.credits")
                    }
                }

                Section {} footer: {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Image(systemName: appManager.getMoonPhaseIcon())
                                .foregroundStyle(.quaternary)
                            Text(
                                verbatim: """
                                v\(Bundle.main.releaseVersionNumber ?? "0").\
                                \(Bundle.main.buildVersionNumber ?? "0")
                                """
                            )
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .padding(.vertical)
                }
            }
            .modifier(ThemedForm())
            .navigationTitle("settings.navigation.title")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button(action: onBack) {
                        Label {
                            Text("Back to conversation", tableName: "Settings")
                        } icon: {
                            Image(systemName: "chevron.backward")
                        }
                    }
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("noctis.settings.back")
                }
            }
            .accessibilityAction(.escape, onBack)
        }
    }
}

struct ThemedForm: ViewModifier {
    @Environment(AppManager.self) private var appManager

    func body(content: Content) -> some View {
        content
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(appManager.appearance.theme.background)
    }
}

extension Bundle {
    var releaseVersionNumber: String? {
        return infoDictionary?["CFBundleShortVersionString"] as? String
    }

    var buildVersionNumber: String? {
        return infoDictionary?["CFBundleVersion"] as? String
    }
}

#Preview {
    SettingsView(currentThread: .constant(nil), viewModel: ChatView.ViewModel(), onBack: {})
        .environment(AppManager())
        .environment(NoctisCloudSync())
        .environment(NoctisLockController())
        #if os(iOS)
        .environment(NoctisVoiceModel.shared)
        #endif
}

//
//  SettingsView.swift
//  fullmoon
//
//  Created by Jordan Singer on 10/4/24.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppManager.self) private var appManager
    @Environment(\.dismiss) var dismiss
    @Binding var currentThread: Thread?
    @Bindable var viewModel: ChatView.ViewModel

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
                }

                Section {
                    LabeledContent("Moteur", value: "Noctis")
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
                    Text("Le modèle est défini par Noctis et ne peut pas être changé ici.")
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
            .formStyle(.grouped)
            .navigationTitle("settings.navigation.title")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    #if os(iOS) || os(visionOS)
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .accessibilityLabel("common.button.close")
                        }
                    }
                    #elseif os(macOS)
                    ToolbarItem(placement: .destructiveAction) {
                        Button(action: { dismiss() }) {
                            Text("common.button.close")
                        }
                    }
                    #endif
                }
        }
        #if !os(visionOS)
        .tint(appManager.appTintColor.getColor())
        #endif
        .modifier(AppearanceRoot())
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
    SettingsView(currentThread: .constant(nil), viewModel: ChatView.ViewModel())
        .environment(AppManager())
}

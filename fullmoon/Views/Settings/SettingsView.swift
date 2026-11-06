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
    SettingsView(currentThread: .constant(nil))
        .environment(AppManager())
}

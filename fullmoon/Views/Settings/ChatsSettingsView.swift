//
//  ChatsSettingsView.swift
//  fullmoon
//
//  Created by Jordan Singer on 10/6/24.
//

import SwiftData
import SwiftUI

struct ChatsSettingsView: View {
    @Environment(AppManager.self) private var appManager
    @Environment(\.modelContext) var modelContext
    @State var systemPrompt = ""
    @State var deleteAllChats = false
    @Binding var currentThread: Thread?
    
    var body: some View {
        @Bindable var appManager = appManager

        Form {
            Section(header: Text("chat_settings.system_prompt.title")) {
                TextEditor(text: $appManager.systemPrompt)
                    .textEditorStyle(.plain)
            }
            
            if appManager.userInterfaceIdiom == .phone {
                Section {
                    Toggle("chat_settings.toggle.haptics", isOn: $appManager.shouldPlayHaptics)
                        .tint(.green)
                }
            }
            
            Section {
                Button {
                    deleteAllChats.toggle()
                } label: {
                    Label("chat_settings.button.delete_all", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .alert("chat_settings.delete_all.confirmation.title", isPresented: $deleteAllChats) {
                    Button("common.button.cancel", role: .cancel) {
                        deleteAllChats = false
                    }
                    Button("common.button.delete", role: .destructive) {
                        deleteChats()
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("chat_settings.navigation.title")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
    
    func deleteChats() {
        do {
            currentThread = nil
            try modelContext.delete(model: Thread.self)
            try modelContext.delete(model: Message.self)
        } catch {
            print("Failed to delete.")
        }
    }
}

#Preview {
    ChatsSettingsView(currentThread: .constant(nil))
        .environment(AppManager())
}

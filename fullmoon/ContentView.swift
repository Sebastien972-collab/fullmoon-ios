//
//  ContentView.swift
//  fullmoon
//
//  Created by Jordan Singer on 10/4/24.
//

import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(AppManager.self) private var appManager
    @Environment(\.modelContext) var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(NoctisCloudSync.self) private var cloud
    @State private var syncClientID = UUID()
    @State var showSettings = false
    @State var showChats = false
    @State var currentThread: Thread?
    @State private var chatViewModel = ChatView.ViewModel()
    #if os(iOS)
    @State private var replySpeaker = ReplySpeaker()
    #endif
    @FocusState var isPromptFocused: Bool

    var body: some View {
        ZStack {
            // Keep the conversation mounted so navigation preserves drafts and active responses.
            cloudManagedContent
                .opacity(showSettings ? 0 : 1)
                .disabled(showSettings)
                .accessibilityHidden(showSettings)

            if showSettings {
                SettingsView(currentThread: $currentThread, viewModel: chatViewModel) {
                    showSettings = false
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(appManager.appearance.theme.background)
            }
        }
        .environment(appManager)
        #if os(iOS)
        .environment(\.replySpeaker, replySpeaker)
        .environment(NoctisVoiceModel.shared)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { replySpeaker.stop() }
        }
        #endif
        .onChange(of: appManager.hasCompletedOnboarding) { _, completed in
            isPromptFocused = completed
        }
        .onChange(of: showSettings) { _, isOpen in
            if isOpen { isPromptFocused = false }
        }
        #if !os(iOS)
        .sheet(isPresented: $showChats) {
            ChatsListView(currentThread: $currentThread, isPromptFocused: $isPromptFocused)
                .noctisAppLock()
                .environment(appManager)
                .presentationDragIndicator(.hidden)
        }
        #endif
        .fontDesign(appManager.appFontDesign.getFontDesign())
        .modifier(AppearanceRoot())
        .fontWidth(appManager.appFontWidth.getFontWidth())
    }

    private var cloudManagedContent: some View {
        appContent
        .task(id: scenePhase) { await synchronizeCloud() }
        .onChange(of: chatViewModel.isSending) { _, sending in
            cloud.setGenerating(sending, client: syncClientID)
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            cloud.refreshStatus()
        }
        .onDisappear {
            cloud.setGenerating(false, client: syncClientID)
            Task { await cloud.pause() }
        }
    }

    @ViewBuilder
    private var appContent: some View {
        if !appManager.hasCompletedOnboarding {
            OnboardingView(viewModel: chatViewModel)
        } else {
            #if os(iOS)
            NoctisChatWorkspace(
                currentThread: $currentThread,
                showSettings: $showSettings,
                viewModel: chatViewModel,
                speaker: replySpeaker
            )
            #else
            NavigationSplitView {
                ChatsListView(
                    currentThread: $currentThread,
                    isPromptFocused: $isPromptFocused,
                    onSettings: { showSettings = true }
                )
                #if os(macOS)
                    .navigationSplitViewColumnWidth(min: 240, ideal: 240, max: 320)
                #endif
            } detail: {
                ChatView(
                    currentThread: $currentThread,
                    isPromptFocused: $isPromptFocused,
                    showChats: $showChats,
                    showSettings: $showSettings,
                    viewModel: chatViewModel
                )
            }
            #endif
        }
    }

    @MainActor
    private func synchronizeCloud() async {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
        guard scenePhase == .active else {
            await cloud.pause()
            return
        }
        cloud.configure(context: modelContext)
        while !Task.isCancelled {
            await cloud.synchronize()
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                break
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Thread.self, Message.self, NoctisUserProfile.self, NoctisSyncRecord.self], inMemory: true)
        .environment(AppManager())
        .environment(NoctisCloudSync())
        .environment(NoctisLockController())
}

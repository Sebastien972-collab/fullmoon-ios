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
    @FocusState var isPromptFocused: Bool

    var body: some View {
        cloudManagedContent
        .environment(appManager)
        .onChange(of: appManager.hasCompletedOnboarding) { _, completed in
            isPromptFocused = completed
        }
        #if !os(iOS)
        .sheet(isPresented: $showChats) {
            ChatsListView(currentThread: $currentThread, isPromptFocused: $isPromptFocused)
                .noctisAppLock()
                .environment(appManager)
                .presentationDragIndicator(.hidden)
        }
        #endif
        .sheet(isPresented: $showSettings) { settingsSheet }
        #if !os(visionOS)
        .tint(appManager.appTintColor.getColor())
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
                viewModel: chatViewModel
            )
            #else
            NavigationSplitView {
                ChatsListView(currentThread: $currentThread, isPromptFocused: $isPromptFocused)
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

    private var settingsSheet: some View {
        SettingsView(currentThread: $currentThread, viewModel: chatViewModel)
            .noctisAppLock()
            .environment(appManager)
            .presentationDragIndicator(.hidden)
            .if(appManager.userInterfaceIdiom == .phone) { view in
                view.presentationDetents([.medium, .large])
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

extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
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

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
        Group {
            if appManager.userInterfaceIdiom == .pad || appManager.userInterfaceIdiom == .mac || appManager.userInterfaceIdiom == .vision {
                // iPad
                NavigationSplitView {
                    ChatsListView(currentThread: $currentThread, isPromptFocused: $isPromptFocused)
                    #if os(macOS)
                    .navigationSplitViewColumnWidth(min: 240, ideal: 240, max: 320)
                    #endif
                } detail: {
                    ChatView(currentThread: $currentThread, isPromptFocused: $isPromptFocused, showChats: $showChats, showSettings: $showSettings, viewModel: chatViewModel)
                }
            } else {
                // iPhone
                ChatView(currentThread: $currentThread, isPromptFocused: $isPromptFocused, showChats: $showChats, showSettings: $showSettings, viewModel: chatViewModel)
            }
        }
        .environment(appManager)
        .task(id: scenePhase) {
            guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
            guard scenePhase == .active else {
                await cloud.pause()
                return
            }
            cloud.configure(context: modelContext)
            while !Task.isCancelled {
                await cloud.synchronize()
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
            }
        }
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
        .if(appManager.userInterfaceIdiom == .phone) { view in
            view
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            if !showChats && gesture.startLocation.x < 20 && gesture.translation.width > 100 {
                                appManager.playHaptic()
                                showChats = true
                            }
                        }
                )
        }
        .sheet(isPresented: $showChats) {
            ChatsListView(currentThread: $currentThread, isPromptFocused: $isPromptFocused)
                .noctisAppLock()
                .environment(appManager)
                .presentationDragIndicator(.hidden)
                .if(appManager.userInterfaceIdiom == .phone) { view in
                    view.presentationDetents([.medium, .large])
                }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(currentThread: $currentThread)
                .noctisAppLock()
                .environment(appManager)
                .presentationDragIndicator(.hidden)
                .if(appManager.userInterfaceIdiom == .phone) { view in
                    view.presentationDetents([.medium, .large])
                }
        }
        #if !os(visionOS)
        .tint(appManager.appTintColor.getColor())
        #endif
        .fontDesign(appManager.appFontDesign.getFontDesign())
        .modifier(AppearanceRoot())
        .fontWidth(appManager.appFontWidth.getFontWidth())
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

// Created by Sébastien DAGUIN

import SwiftUI

struct NoctisPrivacySettingsView: View {
    @Environment(NoctisLockController.self) private var lock
    @Environment(NoctisCloudSync.self) private var cloud
    @State private var confirmEnable = false
    @State private var confirmErase = false

    var body: some View {
        @Bindable var cloud = cloud
        Form {
            Section {
                Toggle("security.enable", isOn: Binding(
                    get: { lock.enabled }, set: { value in Task { await lock.setEnabled(value) } }
                )).disabled(lock.authenticating)
                LabeledContent("security.available", value: lock.mode)
                if let error = lock.errorMessage { Text(error).foregroundStyle(.red) }
            } header: { Text("security.title") } footer: { Text("security.explanation") }

            Section {
                Toggle("cloud.enable", isOn: Binding(
                    get: { cloud.enabled }, set: { value in
                        if value {
                            Task { if await cloud.checkAvailability() { confirmEnable = true } }
                        } else { Task { await cloud.disable() } }
                    }
                ))
                .disabled(cloud.isWorking && !cloud.enabled)
                Toggle("cloud.include.profile", isOn: $cloud.includeProfile).disabled(cloud.isWorking)
                Text("cloud.profile.explanation").font(.footnote).foregroundStyle(.secondary)
                LabeledContent("cloud.state", value: cloud.state.title)
                if let date = cloud.lastSuccess {
                    LabeledContent("cloud.last.success") { Text(date, format: .dateTime) }
                }
                if cloud.state == .syncing {
                    if cloud.total > 0 {
                        ProgressView(value: Double(cloud.completed), total: Double(cloud.total))
                    } else { ProgressView() }
                }
                Button("cloud.sync.now") { Task { await cloud.synchronize() } }
                    .disabled(!cloud.enabled || cloud.isWorking || cloud.isGenerating)
                Button("cloud.erase", role: .destructive) { confirmErase = true }
                    .disabled(cloud.isWorking)
            } header: { Text("cloud.title") } footer: { Text("cloud.explanation") }
        }
        .formStyle(.grouped)
        .navigationTitle("privacy.title")
        .confirmationDialog("cloud.enable.confirm", isPresented: $confirmEnable, titleVisibility: .visible) {
            Button("common.confirm") { Task { await cloud.enable() } }
            Button("common.cancel", role: .cancel) {}
        } message: { Text("cloud.enable.explanation") }
        .confirmationDialog("cloud.erase.confirm", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("cloud.erase", role: .destructive) { Task { await cloud.eraseRemote() } }
            Button("common.cancel", role: .cancel) {}
        } message: { Text("cloud.erase.explanation") }
    }
}

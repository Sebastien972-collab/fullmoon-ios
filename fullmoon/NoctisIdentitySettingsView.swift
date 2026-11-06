// Created by Sébastien DAGUIN

import SwiftData
import SwiftUI

struct NoctisIdentitySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var draft = NoctisProfileSnapshot()
    @State private var loadedSnapshot = NoctisProfileSnapshot()
    @State private var errorMessage: String?
    @State private var saved = false
    @State private var confirmClear = false
    @State private var hasConflict = false
    #if os(iOS) || os(visionOS)
    @State private var showingContactPicker = false
    @State private var contact: NoctisContactImport?
    @State private var showingImportConfirmation = false
    #endif

    var body: some View {
        Form {
            Section {
                TextField("identity.given.name", text: $draft.givenName).textContentType(.givenName)
                TextField("identity.family.name", text: $draft.familyName).textContentType(.familyName)
                TextField("identity.legacy.name", text: $draft.displayName)
                TextField("identity.preferred.name", text: $draft.preferredName)
                Picker("identity.language", selection: $draft.preferredLanguage) {
                    Text("Français").tag("fr")
                    Text("English").tag("en")
                }
                TextField("identity.profession", text: $draft.profession)
            } header: { Text("identity.title") }
            #if os(iOS) || os(visionOS)
            Section {
                Button("identity.import.contact", systemImage: "person.crop.rectangle") { showingContactPicker = true }
                Text("identity.contact.explanation").font(.footnote).foregroundStyle(.secondary)
            }
            #endif
            Section {
                Text("identity.instructions")
                TextEditor(text: $draft.personalInstructions).frame(minHeight: 90)
                Text("identity.personal.information")
                TextEditor(text: $draft.personalInformation).frame(minHeight: 90)
            } header: { Text("identity.preferences") }
            Section {
                Toggle("identity.personalization", isOn: $draft.personalizationEnabled)
                Toggle("identity.allow.name", isOn: $draft.allowName)
                Toggle("identity.allow.language", isOn: $draft.allowLanguage)
                Toggle("identity.allow.profession", isOn: $draft.allowProfession)
                Toggle("identity.allow.instructions", isOn: $draft.allowInstructions)
                Toggle("identity.allow.information", isOn: $draft.allowPersonalInformation)
            } header: { Text("identity.authorizations") } footer: {
                Text("identity.authorization.explanation")
            }
            Section {
                Button("identity.save") { save() }
                Button("identity.clear", role: .destructive) { confirmClear = true }
                if hasConflict {
                    Button("identity.restore.conflict") {
                        do {
                            try NoctisSyncStore(context: modelContext, device: "").restoreProfileConflict()
                            load()
                        } catch { errorMessage = NoctisText.value("identity.save.error") }
                    }
                }
                if saved { Label("identity.saved", systemImage: "checkmark.circle") }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("identity.title")
        .onAppear(perform: load)
        .onChange(of: draft) { _, value in
            if value != loadedSnapshot { saved = false }
        }
        .confirmationDialog("identity.clear.confirm", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("identity.clear", role: .destructive) {
                draft = NoctisProfileSnapshot()
                save(clearArchive: true)
            }
            Button("common.cancel", role: .cancel) {}
        }
        #if os(iOS) || os(visionOS)
        .sheet(isPresented: $showingContactPicker, onDismiss: {
            if contact != nil { showingImportConfirmation = true }
        }, content: {
            NoctisContactPicker { selection in
                contact = selection
                showingContactPicker = false
            } onCancel: { contact = nil; showingContactPicker = false }
        })
        .sheet(isPresented: $showingImportConfirmation, onDismiss: { contact = nil }, content: {
            importConfirmation
        })
        #endif
        .alert("common.error", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("common.ok", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    #if os(iOS) || os(visionOS)
    private var importConfirmation: some View {
        NavigationStack {
            Form {
                if let selection = contact {
                    Toggle(selection.givenName, isOn: Binding(
                        get: { contact?.useGivenName ?? false }, set: { contact?.useGivenName = $0 }
                    ))
                    Toggle(selection.familyName, isOn: Binding(
                        get: { contact?.useFamilyName ?? false }, set: { contact?.useFamilyName = $0 }
                    ))
                    Toggle(selection.nickname, isOn: Binding(
                        get: { contact?.useNickname ?? false }, set: { contact?.useNickname = $0 }
                    ))
                }
                Text("identity.contact.confirm.explanation")
                Button("common.confirm") {
                    if let contact { draft = contact.applying(to: draft) }
                    showingImportConfirmation = false
                }.disabled(contact?.hasSelection != true)
                Button("common.cancel", role: .cancel) { showingImportConfirmation = false }
            }
            .navigationTitle("identity.contact.confirm")
        }
    }
    #endif

    private func load() {
        do {
            if let profile = try NoctisUserIdentity.existingProfile(in: modelContext) {
                draft = NoctisProfileSnapshot(profile: profile)
            } else {
                draft = NoctisProfileSnapshot()
            }
            loadedSnapshot = draft
            hasConflict = try NoctisSyncStore(context: modelContext, device: "")
                .entries(includeProfile: true)["profile"]?.conflicts.isEmpty == false
        } catch { errorMessage = NoctisText.value("identity.save.error") }
    }

    private func save(clearArchive: Bool = false) {
        do {
            let profile = try NoctisUserIdentity.getOrCreateProfile(in: modelContext)
            let current = NoctisProfileSnapshot(profile: profile)
            if current != loadedSnapshot && !clearArchive {
                try NoctisSyncStore(context: modelContext, device: "").archiveProfile(current)
                hasConflict = true
            }
            draft.apply(to: profile)
            try modelContext.container.mainContext.save()
            if clearArchive {
                let device = UserDefaults.standard.string(forKey: "noctis.cloud.device") ?? UUID().uuidString
                try NoctisSyncStore(context: modelContext, device: device).clearProfileArchive()
                hasConflict = false
            }
            loadedSnapshot = draft
            saved = true
        } catch { errorMessage = NoctisText.value("identity.save.error") }
    }
}

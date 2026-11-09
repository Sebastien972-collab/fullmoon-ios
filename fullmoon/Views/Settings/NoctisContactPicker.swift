// Created by Sébastien DAGUIN

import Foundation

struct NoctisContactImport: Equatable, Sendable {
    var givenName: String
    var familyName: String
    var nickname: String
    var useGivenName = false
    var useFamilyName = false
    var useNickname = false

    var hasSelection: Bool { useGivenName || useFamilyName || useNickname }

    func applying(to draft: NoctisProfileSnapshot) -> NoctisProfileSnapshot {
        var result = draft
        if useGivenName { result.givenName = givenName }
        if useFamilyName { result.familyName = familyName }
        if useNickname { result.preferredName = nickname }
        return result
    }
}

#if os(iOS) || os(visionOS)
import Contacts
import ContactsUI
import SwiftUI

struct NoctisContactPicker: UIViewControllerRepresentable {
    let onSelect: (NoctisContactImport) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.predicateForSelectionOfContact = NSPredicate(value: true)
        picker.displayedPropertyKeys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey]
        return picker
    }

    func updateUIViewController(_ controller: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onSelect: (NoctisContactImport) -> Void
        let onCancel: () -> Void

        init(onSelect: @escaping (NoctisContactImport) -> Void, onCancel: @escaping () -> Void) {
            self.onSelect = onSelect
            self.onCancel = onCancel
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onSelect(NoctisContactImport(
                givenName: contact.isKeyAvailable(CNContactGivenNameKey) ? contact.givenName : "",
                familyName: contact.isKeyAvailable(CNContactFamilyNameKey) ? contact.familyName : "",
                nickname: contact.isKeyAvailable(CNContactNicknameKey) ? contact.nickname : ""
            ))
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) { onCancel() }
    }
}
#endif

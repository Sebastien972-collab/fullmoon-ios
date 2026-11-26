#if os(iOS)
import SwiftUI
import UIKit

struct ComposerCamera: UIViewControllerRepresentable {
    var complete: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(complete: complete) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let complete: (UIImage?) -> Void
        init(complete: @escaping (UIImage?) -> Void) { self.complete = complete }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { complete(nil) }
        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            complete(info[.originalImage] as? UIImage)
        }
    }
}
#endif

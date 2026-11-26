#if os(iOS)
import SwiftUI
import UIKit

/// Adapted from the upstream UIKit composer; the host owns its text and focus.
@MainActor
struct NoctisComposerTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    @ScaledMetric(relativeTo: .body) private var maximumHeight: CGFloat = 160

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.textColor = .label
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.contentInset = .zero
        view.isScrollEnabled = false
        view.keyboardDismissMode = .interactive
        view.autocorrectionType = .default
        view.autocapitalizationType = .sentences
        view.delegate = context.coordinator
        view.accessibilityIdentifier = "noctis.messageComposer"
        view.accessibilityLabel = NoctisStrings.text("composer.message")
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        let font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: view.traitCollection)
        if view.font != font {
            view.font = font
            view.invalidateIntrinsicContentSize()
        }
        if view.text != text && view.markedTextRange == nil {
            let selection = view.selectedRange
            view.text = text
            let length = (text as NSString).length
            let location = min(selection.location, length)
            view.selectedRange = NSRange(location: location, length: min(selection.length, length - location))
            view.invalidateIntrinsicContentSize()
        }
        if focused && !view.isFirstResponder { view.becomeFirstResponder() }
        if !focused && view.isFirstResponder { view.resignFirstResponder() }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let content = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let lineHeight = uiView.font?.lineHeight ?? 24
        let limit = min(maximumHeight, 240)
        let height = min(limit, max(lineHeight, ceil(content.height)))
        uiView.isScrollEnabled = content.height > limit
        return CGSize(width: width, height: height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NoctisComposerTextView

        init(parent: NoctisComposerTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            textView.invalidateIntrinsicContentSize()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.focused { parent.focused = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.focused { parent.focused = false }
        }
    }
}
#endif

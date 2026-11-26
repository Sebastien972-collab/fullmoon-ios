import SwiftUI

struct MessagePromptView: View {
    let content: String

    var body: some View {
        let parts = ComposerAttachmentContent.split(content)
        VStack(alignment: .leading, spacing: 8) {
            if !parts.prompt.isEmpty {
                Text(verbatim: parts.prompt)
                    .textSelection(.enabled)
            }
            ForEach(parts.attachments.indices, id: \.self) { index in
                let attachment = parts.attachments[index]
                DisclosureGroup {
                    Text(verbatim: attachment.text)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                } label: {
                    Label(attachment.name, systemImage: "doc.text")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                }
                .padding(10)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

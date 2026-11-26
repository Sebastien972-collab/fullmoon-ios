//
//  CreditsView.swift
//  fullmoon
//
//  Created by Jordan Singer on 10/6/24.
//

import SwiftUI
#if os(iOS)
import NoctisChatUI
#endif

struct CreditsView: View {
    var body: some View {
        Form {
            Section {
                Link(destination: URL(string: "https://github.com/ml-explore/mlx-swift")!) {
                    Text(verbatim: "MLX Swift")
                }
                    .badge(Text(Image(systemName: "arrow.up.right")))
                Link(destination: URL(string: "https://mainfra.me")!) {
                    Text(verbatim: "Mainframe")
                }
                    .badge(Text(Image(systemName: "arrow.up.right")))
            }
            #if os(iOS)
            Section("credits.chat_ui.title") {
                if let url = URL(string: NoctisChatAttribution.sourceURL) {
                    Link(destination: url) {
                        Text(verbatim: "ChatGPT iOS UI · Bryan Ramirez-Gonzalez")
                    }
                }
                NavigationLink {
                    ScrollView {
                        Text(verbatim: NoctisChatAttribution.licenseText)
                            .font(.footnote)
                            .textSelection(.enabled)
                            .padding()
                    }
                    .navigationTitle("credits.chat_ui.license")
                } label: {
                    Text("credits.chat_ui.license")
                }
            }
            #endif
        }
        .formStyle(.grouped)
        .navigationTitle("credits.navigation.title")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview {
    CreditsView()
}

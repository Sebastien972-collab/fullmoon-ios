//
//  CreditsView.swift
//  fullmoon
//
//  Created by Jordan Singer on 10/6/24.
//

import NoctisChatUI
import SwiftUI

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
                licenseLink(NoctisChatAttribution.licenseText)
            }
            #endif
            Section("credits.icons.title") {
                if let url = URL(string: NoctisChatAttribution.iconSourceURL) {
                    Link("Tabler Icons · Paweł Kuna", destination: url)
                }
                licenseLink(NoctisChatAttribution.iconLicenseText)
            }
            Section("credits.themes.title") {
                if let url = Bundle.main.url(forResource: "Theme-Licenses", withExtension: "txt"),
                   let text = try? String(contentsOf: url, encoding: .utf8) {
                    licenseLink(text)
                }
            }
        }
        .modifier(ThemedForm())
        .navigationTitle("credits.navigation.title")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func licenseLink(_ text: String) -> some View {
        NavigationLink {
            ScrollView {
                Text(verbatim: text)
                    .font(.footnote)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("credits.chat_ui.license")
        } label: {
            Text("credits.chat_ui.license")
        }
    }
}

#Preview {
    CreditsView().environment(AppManager())
}

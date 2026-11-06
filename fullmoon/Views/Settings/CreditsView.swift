//
//  CreditsView.swift
//  fullmoon
//
//  Created by Jordan Singer on 10/6/24.
//

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

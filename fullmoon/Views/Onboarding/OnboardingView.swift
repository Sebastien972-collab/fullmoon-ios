//
//  OnboardingView.swift
//  fullmoon
//
//  Created by Sébastien DAGUIN on 06/11/2026.
//
//  Adapted from the Fullmoon onboarding by Jordan Singer (Mainframe Computer, Inc., MIT).

import NoctisChatUI
import SwiftUI

struct OnboardingView: View {
    @Environment(AppManager.self) private var appManager
    @Bindable var viewModel: ChatView.ViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        VStack(spacing: 12) {
                            NoctisEmblem(tint: appManager.resolvedAccent)
                            Text("onboarding.welcome.title")
                                .font(.largeTitle.weight(.semibold))
                                .multilineTextAlignment(.center)
                            Text("onboarding.welcome.subtitle")
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)

                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("onboarding.local_model.title").font(.headline)
                                #if os(iOS)
                                Text("onboarding.ios.local_model.description")
                                    .foregroundStyle(.secondary)
                                #else
                                Text("onboarding.local_model.description")
                                    .foregroundStyle(.secondary)
                                #endif
                            }
                        } icon: {
                            #if os(iOS)
                            Image(systemName: "iphone")
                                .frame(width: 28)
                            #else
                            Image(systemName: "desktopcomputer")
                                .frame(width: 28)
                            #endif
                        }

                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("onboarding.privacy.title").font(.headline)
                                Text("onboarding.privacy.description")
                                .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "checkmark.shield")
                                .frame(width: 28)
                        }

                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("onboarding.appearance.title").font(.headline)
                                Text("onboarding.appearance.description")
                                .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "paintpalette")
                                .frame(width: 28)
                        }

                        NavigationLink("onboarding.appearance.button.discover") {
                            AppearanceSettingsView()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(24)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)

                NavigationLink {
                    OnboardingInstallModelView(viewModel: viewModel)
                } label: {
                    Text("common.button.continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .frame(maxWidth: 460)
                .padding(24)
            }
            .background(appManager.appearance.theme.background)
        }
    }
}

#Preview {
    OnboardingView(viewModel: ChatView.ViewModel())
        .environment(AppManager())
}

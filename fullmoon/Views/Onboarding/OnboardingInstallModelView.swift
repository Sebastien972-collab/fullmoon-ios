//
//  OnboardingInstallModelView.swift
//  fullmoon
//
//  Created by Sébastien DAGUIN on 06/11/2026.
//
//  Adapted from the Fullmoon model installation flow by Jordan Singer (Mainframe Computer, Inc., MIT).

import Metal
import Noctis
import SwiftUI

struct OnboardingInstallModelView: View {
    @Environment(AppManager.self) private var appManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var viewModel: ChatView.ViewModel
    private let supportsMetal = MTLCreateSystemDefaultDevice() != nil

    private var status: LocalizedStringResource {
        if viewModel.isConnected { return "onboarding.install.status.ready" }
        if !supportsMetal { return "onboarding.install.status.unavailable" }
        if viewModel.submissionError != nil { return "onboarding.install.status.failed" }
        guard viewModel.isLoading else { return "onboarding.install.status.prepare" }
        switch viewModel.loadPhase {
        case .downloading: return "onboarding.install.status.downloading"
        case .loading: return "onboarding.install.status.loading"
        case .ready: return "onboarding.install.status.finalizing"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: viewModel.isConnected ? "checkmark.circle.fill" : "moon.stars.fill")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(viewModel.isConnected ? Color.green : appManager.appTintColor.getColor())
                        .symbolEffect(.pulse, options: .repeating, isActive: viewModel.isLoading
                                      && !reduceMotion && !appManager.appearance.reduceAnimations)
                        .accessibilityHidden(true)

                    Text(status)
                        .font(.title.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.updatesFrequently)

                    if !supportsMetal {
                        Label("onboarding.install.metal_unavailable.description",
                              systemImage: "exclamationmark.triangle")
                    } else if viewModel.isConnected {
                        Text("onboarding.install.ready.description")
                            .foregroundStyle(.secondary)
                    } else {
                        preparationDetails
                    }
                }
                .multilineTextAlignment(.center)
                .padding(24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)

            if supportsMetal {
                Button(action: prepareOrFinish) {
                    Text(
                        viewModel.isConnected
                            ? LocalizedStringResource("onboarding.install.button.start")
                            : LocalizedStringResource("onboarding.install.button.prepare")
                    )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(viewModel.isLoading)
                .frame(maxWidth: 460)
                .padding(24)
            }
        }
        .background(appManager.appearance.theme.background)
        .navigationTitle("onboarding.install.navigation.title")
        .navigationBarBackButtonHidden(viewModel.isLoading)
        #if os(iOS) || os(visionOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var preparationDetails: some View {
        VStack(spacing: 16) {
            Text("onboarding.install.model.description")
                .foregroundStyle(.secondary)
            Text("onboarding.install.download.description")
            if viewModel.isLoading {
                ProgressView()
                    .accessibilityLabel(status)
                Text("onboarding.install.duration.description")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let error = viewModel.submissionError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text("onboarding.install.retry.description")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Label("onboarding.install.offline.description",
                      systemImage: "wifi.slash")
                Text("onboarding.install.web_search.description")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func prepareOrFinish() {
        if viewModel.isConnected {
            appManager.hasCompletedOnboarding = true
            appManager.playHaptic()
        } else {
            Task { await viewModel.loadModel() }
        }
    }
}

#Preview {
    NavigationStack {
        OnboardingInstallModelView(viewModel: ChatView.ViewModel())
    }
    .environment(AppManager())
}

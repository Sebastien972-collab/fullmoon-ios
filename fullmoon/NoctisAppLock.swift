// Created by Sébastien DAGUIN

import SwiftUI

struct NoctisAppLock: ViewModifier {
    @Environment(NoctisLockController.self) private var lock
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        ZStack {
            if !lock.enabled || lock.unlocked {
                content
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "lock.shield").font(.system(size: 42))
                    Text("security.locked").font(.title2.bold())
                    Button("security.unlock") { Task { await lock.unlock() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(lock.authenticating)
                    if let error = lock.errorMessage { Text(error).font(.footnote) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Authentication can make the scene inactive. Shield it without
            // invalidating a successful unlock or starting another prompt.
            if lock.enabled && scenePhase != .active {
                Rectangle().fill(.background).ignoresSafeArea()
                    .overlay { Image(systemName: "lock.shield").font(.largeTitle) }
                    .accessibilityHidden(true)
            }
        }
        .background(.background)
        .task { await lock.unlock(automatically: true) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { lock.enterBackground() }
            if phase == .active { Task { await lock.unlock(automatically: true) } }
        }
    }
}

extension View {
    func noctisAppLock() -> some View { modifier(NoctisAppLock()) }
}

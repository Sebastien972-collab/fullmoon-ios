#!/bin/sh
# Created by Sébastien DAGUIN
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
noctis="${NOCTIS_SOURCE_ROOT:-$root/../NoctisAi}"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/noctis-identity-XXXXXX")
trap 'rm -rf "$scratch"' EXIT INT TERM
compiler="${SWIFTC:-$(xcrun --find swiftc)}"
sdk="${NOCTIS_TEST_SDK:-$(xcrun --show-sdk-path --sdk macosx)}"

cd "$root"
# Compile a stable snapshot outside a potentially synchronized Documents folder.
cp tests/LegacyStoreFixture.swift tests/NoctisIdentityTests.swift "$scratch/"
cp fullmoon/Domain/Thread.swift fullmoon/Domain/Message.swift "$scratch/"
cp fullmoon/Domain/NoctisUserProfile.swift fullmoon/Domain/NoctisDeviceAuthenticator.swift "$scratch/"
cp fullmoon/Domain/NoctisSyncDocument.swift fullmoon/Domain/NoctisSyncStore.swift "$scratch/"
cp fullmoon/Domain/NoctisCloudTransport.swift fullmoon/Domain/NoctisCloudSync.swift "$scratch/"
cp fullmoon/Domain/NoctisPersistence.swift fullmoon/Domain/NoctisIdentitySession.swift "$scratch/"
cp fullmoon/Views/Settings/NoctisContactPicker.swift fullmoon/Views/Settings/NoctisAppLock.swift "$scratch/"
cp fullmoon/Views/Settings/NoctisIdentitySettingsView.swift fullmoon/Views/Settings/NoctisPrivacySettingsView.swift "$scratch/"
# Use the existing Noctis protocol sources, not a replacement API or an MLX model.
cp "$noctis/Sources/Noctis/Core/AI/Domain/AIChatMessage.swift" "$scratch/"
cp "$noctis/Sources/Noctis/Core/AI/AIModelService.swift" "$scratch/"
cp "$noctis/Sources/Noctis/Core/Enum/AIModelLoadPhase.swift" "$scratch/"
cd "$scratch"
"$compiler" -parse-as-library -swift-version 6 -strict-concurrency=complete \
    -target arm64-apple-macos14.0 -sdk "$sdk" -module-name NoctisIdentityTests \
    -Xfrontend -disable-sandbox -module-cache-path "$scratch/cache" \
    LegacyStoreFixture.swift -o "$scratch/legacy"
"$scratch/legacy" "$scratch/legacy.store"
"$scratch/legacy" "$scratch/conversations-only.store" --without-profile
"$compiler" -emit-module -emit-library -swift-version 6 -strict-concurrency=complete \
    -target arm64-apple-macos14.0 -sdk "$sdk" -module-name Noctis \
    -module-cache-path "$scratch/cache" -emit-module-path "$scratch/Noctis.swiftmodule" \
    AIChatMessage.swift AIModelService.swift AIModelLoadPhase.swift -o "$scratch/libNoctis.dylib"
"$compiler" -parse-as-library -swift-version 6 -strict-concurrency=complete \
    -target arm64-apple-macos14.0 -sdk "$sdk" -module-name NoctisIdentityTests \
    -Xfrontend -disable-sandbox -module-cache-path "$scratch/cache" \
    Thread.swift Message.swift \
    NoctisUserProfile.swift NoctisDeviceAuthenticator.swift \
    NoctisSyncDocument.swift NoctisSyncStore.swift \
    NoctisCloudTransport.swift NoctisCloudSync.swift \
    NoctisPersistence.swift NoctisContactPicker.swift NoctisIdentitySession.swift \
    NoctisAppLock.swift NoctisIdentitySettingsView.swift NoctisPrivacySettingsView.swift \
    -I "$scratch" -L "$scratch" -lNoctis -Xlinker -rpath -Xlinker "$scratch" \
    NoctisIdentityTests.swift -o "$scratch/tests"
"$scratch/tests" "$scratch/legacy.store" "$scratch/conversations-only.store"

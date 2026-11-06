#!/bin/sh
# Created by Sébastien DAGUIN
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
compiler="${SWIFTC:-$(xcrun --find swiftc)}"
sdk="${NOCTIS_TEST_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
noctis="${NOCTIS_SOURCE_ROOT:-$root/../NoctisAi}"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/noctis-identity-tests.XXXXXX")
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
cd "$root"
# Compile a stable snapshot outside a potentially synchronized Documents folder.
cp tests/LegacyStoreFixture.swift tests/NoctisIdentityTests.swift "$scratch/"
cp fullmoon/Domain/Thread.swift fullmoon/Domain/Message.swift "$scratch/"
cp fullmoon/NoctisUserProfile.swift fullmoon/NoctisDeviceAuthenticator.swift "$scratch/"
cp fullmoon/NoctisSyncDocument.swift fullmoon/NoctisSyncStore.swift "$scratch/"
cp fullmoon/NoctisCloudTransport.swift fullmoon/NoctisCloudSync.swift "$scratch/"
cp fullmoon/NoctisPersistence.swift fullmoon/NoctisContactPicker.swift "$scratch/"
cp fullmoon/NoctisIdentitySession.swift fullmoon/NoctisAppLock.swift "$scratch/"
cp fullmoon/NoctisIdentitySettingsView.swift fullmoon/NoctisPrivacySettingsView.swift "$scratch/"
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
"$scratch/tests" "$scratch/legacy.store"

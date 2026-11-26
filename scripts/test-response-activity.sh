#!/bin/bash
# Created by Sébastien DAGUIN
set -euo pipefail

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
noctis_source="${NOCTIS_SOURCE_ROOT:-$project_root/../NoctisAi}"
test_directory=$(mktemp -d "${TMPDIR:-/tmp}/noctis-response-activity-XXXXXX")
trap 'rm -rf "$test_directory"' EXIT INT TERM
platform_options=()

if [ "$(uname -s)" = Darwin ]; then
    compiler="${SWIFTC:-$(xcrun --find swiftc)}"
    sdk="${NOCTIS_TEST_SDK:-$(xcrun --show-sdk-path --sdk macosx)}"
    platform_options=(-sdk "$sdk")
    library_name=libNoctis.dylib
else
    compiler="${SWIFTC:-$(command -v swiftc || true)}"
    if [ -z "$compiler" ]; then
        echo 'Swift 6 is required to run response activity tests.' >&2
        exit 1
    fi
    library_name=libNoctis.so
fi

cp "$noctis_source/Sources/Noctis/Core/AI/AIResponseEvent.swift" "$test_directory/"
cp "$project_root/fullmoon/Domain/NoctisResponseActivity.swift" "$test_directory/"
cp "$project_root/fullmoon/Domain/NoctisToolActivitySummary.swift" "$test_directory/"
cp "$project_root/tests/NoctisResponseActivityTests.swift" "$test_directory/"
cd "$test_directory"

"$compiler" -emit-module -emit-library -swift-version 6 -strict-concurrency=complete \
    "${platform_options[@]}" -module-name Noctis -module-cache-path "$test_directory/cache" \
    -emit-module-path "$test_directory/Noctis.swiftmodule" \
    AIResponseEvent.swift -o "$test_directory/$library_name"
"$compiler" -parse-as-library -swift-version 6 -strict-concurrency=complete \
    "${platform_options[@]}" -module-name NoctisResponseActivityTests -module-cache-path "$test_directory/cache" \
    NoctisResponseActivity.swift NoctisToolActivitySummary.swift NoctisResponseActivityTests.swift \
    -I "$test_directory" -L "$test_directory" -lNoctis -Xlinker -rpath -Xlinker "$test_directory" \
    -o "$test_directory/tests"
"$test_directory/tests"

#!/bin/sh
# Created by Sébastien DAGUIN
set -eu

if [ "${CI_XCODE_CLOUD:-}" != "TRUE" ]; then
    echo "error: This script must run in Xcode Cloud." >&2
    exit 1
fi
: "${CI_PRIMARY_REPOSITORY_PATH:?CI_PRIMARY_REPOSITORY_PATH is required}"
: "${CI_PRODUCT_PLATFORM:?CI_PRODUCT_PLATFORM is required}"

case "$CI_PRODUCT_PLATFORM" in
    iOS|macOS) ;;
    *)
        echo "error: Unsupported Xcode Cloud platform: $CI_PRODUCT_PLATFORM" >&2
        exit 1
        ;;
esac
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
    echo "error: Preparing the Noctis runtimes requires an Apple Silicon Mac." >&2
    exit 1
fi

fullmoon_directory=$(CDPATH= cd -- "$CI_PRIMARY_REPOSITORY_PATH" && pwd -P)
noctis_directory="$(dirname "$fullmoon_directory")/NoctisAi"
noctis_repository=https://github.com/Sebastien972-collab/NoctisAi.git
mac_runtime="$fullmoon_directory/build/SearXNG"
ios_runtime="$fullmoon_directory/build/SearXNG-iOS"

# Read Xcode's committed resolution without invoking SwiftPM or changing its pins.
noctis_revision=$(/usr/bin/python3 - "$fullmoon_directory" "$noctis_repository" <<'PY'
import json
from pathlib import Path
import re
import subprocess
import sys

root = Path(sys.argv[1])
repository = sys.argv[2]
project_path = root / "fullmoon.xcodeproj/project.pbxproj"
lock_path = root / "fullmoon.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

try:
    lock = json.loads(lock_path.read_text())
    project = json.loads(subprocess.check_output(
        ["plutil", "-convert", "json", "-o", "-", str(project_path)], text=True
    ))
except (OSError, ValueError, subprocess.CalledProcessError) as error:
    raise SystemExit(f"error: Unable to read the committed package resolution: {error}")

pins = [pin for pin in lock.get("pins", []) if pin.get("identity") == "noctisai"]
if len(pins) != 1:
    raise SystemExit("error: Package.resolved must contain exactly one NoctisAi pin.")
pin = pins[0]
revision = pin.get("state", {}).get("revision", "")
if (pin.get("kind") != "remoteSourceControl" or pin.get("location") != repository
        or not isinstance(revision, str) or not re.fullmatch(r"[0-9a-f]{40}", revision)):
    raise SystemExit("error: The resolved NoctisAi source or revision is invalid.")

references = [item for item in project.get("objects", {}).values()
              if item.get("isa") == "XCRemoteSwiftPackageReference"
              and item.get("repositoryURL") == repository]
if len(references) != 1:
    raise SystemExit("error: The Xcode project must contain exactly one NoctisAi reference.")
requirement = references[0].get("requirement", {})
if requirement.get("kind") != "revision" or requirement.get("revision") != revision:
    raise SystemExit("error: The NoctisAi pin differs between Package.resolved and the Xcode project.")
print(revision)
PY
)

require_new_runtime() {
    if [ -e "$1" ] || [ -L "$1" ]; then
        echo "error: Refusing to overwrite an existing runtime: $1" >&2
        exit 1
    fi
}
require_new_runtime "$mac_runtime"
if [ "$CI_PRODUCT_PLATFORM" = iOS ]; then
    require_new_runtime "$ios_runtime"
fi

if [ -e "$noctis_directory" ] || [ -L "$noctis_directory" ]; then
    if [ ! -e "$noctis_directory/.git" ] \
        || [ "$(git -C "$noctis_directory" remote get-url origin)" != "$noctis_repository" ] \
        || [ "$(git -C "$noctis_directory" rev-parse HEAD)" != "$noctis_revision" ] \
        || [ -n "$(git -C "$noctis_directory" status --porcelain)" ]; then
        echo "error: The existing NoctisAi checkout must be clean and match $noctis_revision." >&2
        exit 1
    fi
else
    git init "$noctis_directory"
    git -C "$noctis_directory" remote add origin "$noctis_repository"
    git -C "$noctis_directory" fetch --depth=1 origin "$noctis_revision"
    git -C "$noctis_directory" checkout --detach FETCH_HEAD
fi
if [ "$(git -C "$noctis_directory" rev-parse HEAD)" != "$noctis_revision" ]; then
    echo "error: The NoctisAi checkout does not match the resolved revision." >&2
    exit 1
fi

# Match the noninteractive plugin and macro settings used by GitHub Actions.
defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES
defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES
if xcrun --sdk macosx metal --version >/dev/null 2>&1; then
    echo "The Metal compiler is available."
else
    echo "Installing the Metal toolchain."
    xcodebuild -downloadComponent MetalToolchain
    xcrun --sdk macosx metal --version
fi

if ! command -v uv >/dev/null 2>&1; then
    brew install uv
fi

echo "Preparing $CI_PRODUCT_PLATFORM runtimes with Noctis $noctis_revision."
uv run --no-project --python 3.13.13 \
    "$noctis_directory/infrastructure/searxng/setup_runtime.py" \
    --standalone --destination "$mac_runtime"

if [ "$CI_PRODUCT_PLATFORM" = iOS ]; then
    "$mac_runtime/python/bin/python3" \
        "$noctis_directory/infrastructure/searxng/setup_ios_runtime.py" \
        --mac-runtime "$mac_runtime" --destination "$ios_runtime"
fi

#!/usr/bin/env python3
# Created by Sébastien DAGUIN

"""Run deterministic chat tests against an existing Debug macOS build, without model weights."""

import argparse
import pathlib
import shlex
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build_log", type=pathlib.Path, help="Log from a successful macOS xcodebuild")
    parser.add_argument("--check-swift6", action="store_true", help="Also typecheck all app sources in Swift 6")
    options = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parent.parent
    lines = options.build_log.read_text().splitlines()
    commands = [line for line in lines if "builtin-SwiftDriver -- " in line and "-module-name fullmoon " in line]
    if not commands:
        parser.error("Log must contain a fullmoon Swift compilation; build with a fresh derived data folder if needed")
    args = shlex.split(commands[-1].split("builtin-SwiftDriver -- ", 1)[1])
    flags = []
    index = 1
    while index < len(args):
        if args[index] in ("-I", "-F", "-sdk", "-target", "-Xcc"):
            flags.extend(args[index:index + 2])
            index += 2
        else:
            index += 1
    products = next(pathlib.Path(args[i + 1]) for i, arg in enumerate(args[:-1])
                    if arg == "-I" and args[i + 1].endswith("/Build/Products/Debug"))
    library = products / "fullmoon.app/Contents/MacOS/fullmoon.debug.dylib"
    with tempfile.TemporaryDirectory(prefix="noctis-performance-") as scratch:
        flags += ["-module-cache-path", scratch + "/cache", "-swift-version", "6",
                  "-strict-concurrency=complete", "-Xfrontend", "-disable-sandbox", "-parse-as-library"]
        if options.check_swift6:
            source_list = next(arg for arg in args if arg.startswith("@") and arg.endswith(".SwiftFileList"))
            subprocess.run(["xcrun", "swiftc", *flags, "-DDEBUG", "-module-name", "fullmoon", "-typecheck",
                            source_list], cwd=root, check=True)
        binary = scratch + "/tests"
        subprocess.run(["xcrun", "swiftc", *flags, str(root / "tests/ChatPerformanceTests.swift"), str(library),
                        "-Xlinker", "-rpath", "-Xlinker", str(library.parent), "-o", binary], cwd=root, check=True)
        subprocess.run([binary], cwd=root, check=True)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
# Generate the native Mac GLSL resources from the Android engine shaders.
#
# Usage: scripts/sync-macos-shaders.py [--check]
# --check verifies the committed resources without changing files.
# Requires Python 3.8+. No third-party dependencies.

import argparse
from pathlib import Path
import re
import sys


def translated_shaders(source):
    shaders = dict(re.findall(r'const val (\w+) = """(.*?)"""', source, re.S))
    expected = {"QUAD_VERT", "STAMP_FRAG", "WARP_VERT", "WARP_FRAG"}
    if shaders.keys() != expected:
        raise ValueError("The Android shader set changed; review the native engine bindings.")
    result = {}
    for name, code in shaders.items():
        if not code.startswith("#version 300 es\n"):
            raise ValueError("Unexpected GLSL version in " + name)
        code = code.replace("#version 300 es", "#version 150", 1)
        code = re.sub(r"^precision \w+ \w+;\n", "", code, flags=re.M)
        code = re.sub(r"\b(highp|mediump|lowp)\s+", "", code)
        # GLSL 150 binds a_pos to location 0 through glBindAttribLocation.
        code = code.replace("layout(location = 0) ", "")
        result[name.lower() + ".glsl"] = code
    return result


def main():
    parser = argparse.ArgumentParser(description="Synchronize the Android and native Mac shader math.")
    parser.add_argument("--check", action="store_true", help="fail if generated shaders differ")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    source = root / "app/src/main/java/ch/lkmc/goo/engine/gl/GlShaders.kt"
    destination = root / "macos/Sources/MeltoramaMac/Resources/Shaders"
    try:
        shaders = translated_shaders(source.read_text())
        if args.check:
            stale = [name for name, code in shaders.items()
                     if not (destination / name).exists() or (destination / name).read_text() != code]
            stale.extend(path.name for path in destination.glob("*.glsl") if path.name not in shaders)
            if stale:
                print("!! Mac shaders are out of date: " + ", ".join(stale), file=sys.stderr)
                print("-- Run scripts/sync-macos-shaders.py", file=sys.stderr)
                return 1
            print("==> All four native Mac shaders match the Android engine")
            return 0
        destination.mkdir(parents=True, exist_ok=True)
        for name, code in shaders.items():
            (destination / name).write_text(code)
        print("==> Regenerated four native Mac shaders")
        return 0
    except (OSError, ValueError) as error:
        print("!! " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Compile production path/config decisions on macOS; create fixtures only in tmp.

No app fixture is executed, no device is accessed and no repository source is
modified. The C/ObjC units under test are blacklist.m, _configuration.c,
_wantsInject.c, _whitelist.c and app_isolation_policy.c. Only JBROOT's provider,
logging and the immutable app-container prefix are host substitutions.
"""
from pathlib import Path
import argparse
import json
import os
import platform
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sanitizer", choices=("none", "address"), default="none")
    args = parser.parse_args()
    if platform.system() != "Darwin":
        raise SystemExit("Requires macOS Foundation/XPC and xcrun clang; no test was run.")

    repo = Path(__file__).resolve().parents[1]
    production = repo / "BaseBin/libroothider/src"
    tests = repo / "tests"
    compiler = ["xcrun", "--sdk", "macosx", "clang"]
    flags = ["-fblocks", "-O1", "-g", "-Wall", "-Wextra",
             "-Werror=implicit-function-declaration", "-Wno-deprecated-declarations",
             "-I", str(tests / "app-isolation-integration/include"),
             "-I", str(production),
             "-I", str(repo / "BaseBin/libjailbreak/src"),
             "-I", str(repo / "BaseBin/launchdhook/src")]
    if args.sanitizer == "address":
        flags += ["-fno-omit-frame-pointer", "-fsanitize=address,undefined"]

    with tempfile.TemporaryDirectory(prefix="dopamine-isolation-integration-") as temp:
        directory = Path(temp).resolve()
        containers = directory / "containers"
        containers.mkdir()
        jbroot = directory / "jbroot"
        jbroot.mkdir()
        flags += ["-DAPP_PATH_PREFIX=" + json.dumps(str(containers) + "/")]
        units = [production / "_configuration.c", production / "_wantsInject.c",
                 production / "_whitelist.c", production / "blacklist.m",
                 repo / "BaseBin/launchdhook/src/app_isolation_policy.c",
                 tests / "app-isolation-integration.m"]
        objects = []
        for index, unit in enumerate(units):
            obj = directory / (str(index) + ".o")
            language = ["-fobjc-arc"] if unit.suffix == ".m" else ["-std=gnu11"]
            print("Compile " + str(unit.relative_to(repo)), flush=True)
            subprocess.run([*compiler, *flags, *language, "-c", str(unit), "-o", str(obj)],
                           check=True, timeout=90)
            objects.append(str(obj))
        binary = directory / "app-isolation-integration"
        subprocess.run([*compiler, *flags, *objects, "-framework", "Foundation", "-lbsm",
                        "-o", str(binary)], check=True, timeout=90)
        environment = os.environ.copy()
        if args.sanitizer == "address":
            environment.setdefault("ASAN_OPTIONS", "detect_leaks=0:abort_on_error=1")
        subprocess.run([str(binary), str(jbroot)], check=True, env=environment, timeout=45)


if __name__ == "__main__":
    main()

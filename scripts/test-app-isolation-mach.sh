#!/usr/bin/env bash
# Real Mach IPC tests on the macOS CI host; no iOS target or jailbreak primitives.
set -euo pipefail
repo_root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
if [[ "$(uname -s)" != Darwin ]]; then
    echo 'SKIP: real Mach transport tests require macOS'
    exit 0
fi
output="$(mktemp -d "${TMPDIR:-/tmp}/dopamine-isolation-mach.XXXXXX")"
trap 'rm -rf -- "$output"' EXIT
xcrun --sdk macosx clang -std=c11 -Wall -Wextra -Werror -fblocks -g \
    -fno-omit-frame-pointer -fsanitize=address,undefined \
    -I"$repo_root/BaseBin/libroothider/src" \
    "$repo_root/BaseBin/libroothider/src/app_isolation_mach.c" \
    "$repo_root/tests/app-isolation-mach.c" -lbsm -o "$output/app-isolation-mach"
python3 - "$output/app-isolation-mach" <<'PY'
import os
import signal
import subprocess
import sys

# Own a process group, including the intentionally stopped fixture child.
process = subprocess.Popen([sys.argv[1]], start_new_session=True)
try:
    result = process.wait(timeout=30)
except subprocess.TimeoutExpired:
    os.killpg(process.pid, signal.SIGKILL)
    process.wait()
    raise SystemExit("FAIL: Mach tests exceeded 30 seconds; owned process group terminated")
except BaseException:
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
    raise
raise SystemExit(result)
PY
python3 "$repo_root/tests/check-isolation-ipc-wiring.py"

# Host execution alone does not cover the different iOS audit/libproc header surface.
# Compile this standalone production unit for each shipped architecture before the
# full Theos build, using the same checked-in header source as BaseBin/.include.
for arch in arm64 arm64e; do
    xcrun --sdk iphoneos clang -std=c11 -fsyntax-only -arch "$arch" \
        -miphoneos-version-min=15.0 -Werror=implicit-function-declaration \
        -I"$repo_root/BaseBin/_external/include" \
        -I"$repo_root/BaseBin/libroothider/src" \
        "$repo_root/BaseBin/libroothider/src/app_isolation_mach.c"
    printf 'PASS: production Mach transport iOS SDK declarations (%s)\n' "$arch"
done

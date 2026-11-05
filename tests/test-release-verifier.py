#!/usr/bin/env python3
"""Exercise the release verifier with inert ZIP/TAR fixtures, without native code."""
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import plistlib
import runpy
import sys
import tarfile
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True


def fixture(*, tar_duplicate=False, zip_duplicate=False, wrong_id=False, executable=True):
    base = (ROOT / "BaseBin/_external/basebin/.version").read_text().strip()
    revision = (ROOT / "BaseBin/_external/basebin/.version-roothide").read_text().strip()
    content = {
        "basebin/.version": base.encode(), "basebin/.version-roothide": revision.encode(),
        **{"basebin/" + name: b"native fixture never executed" for name in
           ("jbctl", "jailbreakd", "launchdhook.dylib", "systemhook.dylib", "libroothider.dylib", "libjailbreak.dylib")},
    }
    tar_bytes = io.BytesIO()
    with tarfile.open(fileobj=tar_bytes, mode="w") as archive:
        for name, data in content.items():
            member = tarfile.TarInfo(name)
            member.size = len(data)
            archive.addfile(member, io.BytesIO(data))
        if tar_duplicate:
            member = tarfile.TarInfo("./basebin/.version")
            member.size = len(base)
            archive.addfile(member, io.BytesIO(base.encode()))
    info = plistlib.dumps({"CFBundleIdentifier": "other.app" if wrong_id else "com.doimty.dopamine",
                          "CFBundleExecutable": "Dopamine", "CFBundleShortVersionString": base + "-" + revision,
                          "DOBuildTimestamp": 1})
    package_bytes = io.BytesIO()
    with zipfile.ZipFile(package_bytes, "w") as package:
        package.writestr("Payload/Dopamine.app/Info.plist", info)
        if zip_duplicate:
            package.writestr("Payload/Dopamine.app/./Info.plist", info)
        package.writestr("Payload/Dopamine.app/Dopamine.roothide", b"")
        package.writestr("Payload/Dopamine.app/basebin.tar", tar_bytes.getvalue())
        member = zipfile.ZipInfo("Payload/Dopamine.app/Dopamine")
        member.create_system = 3
        member.external_attr = (0o100755 if executable else 0o100644) << 16
        package.writestr(member, b"\xcf\xfa\xed\xfe" + b"inert fixture")
    return package_bytes.getvalue()


def run_case(name, expected, **kwargs):
    with tempfile.TemporaryDirectory(prefix="release-verifier-test-") as directory:
        directory = Path(directory)
        data = fixture(**kwargs)
        ipa, tipa = directory / "package.ipa", directory / "package.tipa"
        ipa.write_bytes(data)
        tipa.write_bytes(data)
        output = directory / "manifest.json"
        previous = sys.argv
        sys.argv = [str(ROOT / "scripts/verify-release-package.py"), "--ipa", str(ipa), "--tipa", str(tipa),
                    "--commit", "a" * 40, "--output", str(output)]
        try:
            try:
                with redirect_stdout(io.StringIO()):
                    runpy.run_path(sys.argv[0], run_name="__main__")
                success = True
            except AssertionError:
                success = False
        finally:
            sys.argv = previous
        assert success == expected, name
        if success:
            manifest = json.loads(output.read_text())
            assert manifest["ipa"]["sha256"] == manifest["tipa"]["sha256"]
            assert len(manifest["basebin_binaries"]) == 6
        print("PASS release verifier:", name)


if __name__ == "__main__":
    run_case("valid artifact structure", True)
    run_case("normalized duplicate TAR name", False, tar_duplicate=True)
    run_case("normalized duplicate ZIP name", False, zip_duplicate=True)
    run_case("foreign bundle identifier", False, wrong_id=True)
    run_case("missing executable permission", False, executable=False)

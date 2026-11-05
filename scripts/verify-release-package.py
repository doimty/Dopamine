#!/usr/bin/env python3
"""Verify the unmodified CI IPA/TIPA, packaged identity, basebin versions and hashes.

Archives are read in memory, never extracted or executed. The manifest describes
build artifacts only; it does not establish the version currently running on a phone.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import plistlib
import re
import tarfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", required=True, type=Path)
    parser.add_argument("--tipa", required=True, type=Path)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--require-official-home", action="store_true")
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-f]{40}", args.commit):
        raise SystemExit("Expected full Git commit SHA")
    expected_base = (ROOT / "BaseBin/_external/basebin/.version").read_text().strip()
    expected_revision = (ROOT / "BaseBin/_external/basebin/.version-roothide").read_text().strip()
    expected_version = expected_base + "-" + expected_revision
    ipa, tipa = args.ipa.read_bytes(), args.tipa.read_bytes()
    assert ipa == tipa, "TIPA must be a byte-identical copy of the signed IPA"
    prefix = "Payload/Dopamine.app/"
    official_home = None
    home_checks = None
    if args.require_official_home:
        import runpy
        home_checks = runpy.run_path(str(ROOT / "scripts/test-official-home.py"))
        official_home = home_checks["static_checks"]()
    with zipfile.ZipFile(io.BytesIO(tipa)) as package:
        names = package.namelist()
        assert len(names) == len(set(names)), "Duplicate ZIP entries"
        normalized_zip_names = set()
        for name in names:
            parts = PurePosixPath(name).parts
            assert not name.startswith("/") and ".." not in parts and "\\" not in name, "Unsafe ZIP member"
            normalized = str(PurePosixPath(name))
            assert normalized not in normalized_zip_names, "Duplicate normalized ZIP member: " + normalized
            normalized_zip_names.add(normalized)
        assert package.testzip() is None, "ZIP CRC failure"
        info = plistlib.loads(package.read(prefix + "Info.plist"))
        assert info["CFBundleIdentifier"] == "com.doimty.dopamine"
        assert info["CFBundleExecutable"] == "Dopamine"
        assert info["CFBundleShortVersionString"] == expected_version
        assert isinstance(info.get("DOBuildTimestamp"), int) and info["DOBuildTimestamp"] > 0
        assert prefix + "Dopamine.roothide" in names
        executable_info = package.getinfo(prefix + "Dopamine")
        mode = (executable_info.external_attr >> 16) & 0o7777
        assert mode & 0o111, "Main executable mode missing in signed archive"
        executable = package.read(executable_info)
        assert executable[:4] in (b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf"), "Not a Mach-O executable"
        basebin_bytes = package.read(prefix + "basebin.tar")
        executable_sha = sha(executable)
        if official_home is not None:
            for key in home_checks["REMOVED_KEYS"]:
                assert key.encode("utf-8") not in executable, "Removed homepage label remains in actual executable: " + key
            packaged_authors = {}
            for language in home_checks["LANGUAGES"]:
                resource = package.read(prefix + language + ".lproj/Localizable.strings")
                if resource.startswith(b"bplist") or resource.lstrip().startswith(b"<?xml"):
                    table = plistlib.loads(resource)
                else:
                    encoding = "utf-16" if resource.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig"
                    table = home_checks["parse_strings"](resource.decode(encoding))
                expected = official_home["localized_authors"][language]
                assert table["Credits_Made_By"] == expected, "Packaged author text differs: " + language
                for key in home_checks["REMOVED_KEYS"]:
                    assert key not in table, "Dead homepage resource reintroduced: " + language
                packaged_authors[language] = table["Credits_Made_By"]
            official_home["packaged_authors"] = packaged_authors
            official_home["extra_home_labels_absent_from_executable"] = True
    binary_names = ("jbctl", "jailbreakd", "launchdhook.dylib", "systemhook.dylib", "libroothider.dylib", "libjailbreak.dylib")
    binary_hashes = {}
    links = []
    with tarfile.open(fileobj=io.BytesIO(basebin_bytes), mode="r:*") as archive:
        members = {}
        for member in archive.getmembers():
            parts = PurePosixPath(member.name).parts
            assert parts and parts[0] == "basebin" and ".." not in parts and "\\" not in member.name, "Unexpected TAR member path"
            normalized = str(PurePosixPath(member.name))
            assert normalized not in members, "Duplicate normalized TAR member: " + normalized
            members[normalized] = member
            if member.issym() or member.islnk():
                links.append({"path": normalized, "target": member.linkname,
                              "type": "symlink" if member.issym() else "hardlink"})
        def data(name: str) -> bytes:
            member = members["basebin/" + name]
            assert member.isfile(), "Expected regular basebin file: " + name
            stream = archive.extractfile(member)
            assert stream is not None
            return stream.read()
        assert data(".version").decode("utf-8").strip() == expected_base
        assert data(".version-roothide").decode("utf-8").strip() == expected_revision
        for name in binary_names:
            contents = data(name)
            assert contents, "Empty basebin executable: " + name
            binary_hashes[name] = {"sha256": sha(contents), "bytes": len(contents)}
    result = {
        "commit": args.commit,
        "bundle_identifier": info["CFBundleIdentifier"],
        "app_version": expected_version,
        "basebin_version": expected_base,
        "roothide_revision": expected_revision,
        "build_timestamp": info["DOBuildTimestamp"],
        "ipa": {"name": args.ipa.name, "sha256": sha(ipa), "bytes": len(ipa)},
        "tipa": {"name": args.tipa.name, "sha256": sha(tipa), "bytes": len(tipa)},
        "main_executable": {"sha256": executable_sha, "unix_mode": oct(mode)},
        "basebin_archive_sha256": sha(basebin_bytes),
        "basebin_binaries": binary_hashes,
        "basebin_links": links,
        "scope": "unmodified build artifacts and selected executable hashes; archive links recorded but not followed; device installation and running state not observed",
    }
    if official_home is not None:
        result["official_home"] = official_home
        print("PASS actual executable lacks extra home labels; packaged localized authors match official-home source")
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("PASS IPA/TIPA byte identity, ZIP CRC, bundle ID, executable mode, basebin pair:", expected_version)
    print("TIPA SHA-256:", result["tipa"]["sha256"])


if __name__ == "__main__":
    main()

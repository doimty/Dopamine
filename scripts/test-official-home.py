#!/usr/bin/env python3
"""Check actual official-home source integration and Chinese format contracts.

--static-only runs on the editing host. Full execution additionally asks macOS
Foundation/NSBundle to load the real .strings resources and format sentinel IDs.
No phone, UIKit application or jailbreak operation is started.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = ("en", "zh-CN", "zh-Hans", "zh-HK", "zh-TW")
REMOVED_KEYS = (
    "System version: %@", "Build version: %@", "Build time: %@",
    "System boot time: %@", "Uptime_Format",
    "If you encounter any issues, please reproduce them using the official version before reporting.",
)
ROOT_HIDE_GUARD = '''        // Keep the RootHide activation guard; it is independent of homepage styling.
        if (otherJailbreakActived(false)) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:DOLocalizedString(@"Error")
                message:DOLocalizedString(@"Other_Jailbreak_Active_Message") preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:DOLocalizedString(@"Button_Close")
                style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
            return;
        }
'''


def sha(data: bytes) -> str:
    return hashlib.sha256(data.replace(b"\r\n", b"\n")).hexdigest()


def parse_strings(text: str) -> dict[str, str]:
    """Strict subset of OpenStep .strings used by the selected source tables."""
    result = {}
    decoder = json.JSONDecoder()
    position = 0
    def skip(index: int) -> int:
        while index < len(text):
            if text[index].isspace():
                index += 1
            elif text.startswith("//", index):
                end = text.find("\n", index)
                index = len(text) if end < 0 else end + 1
            elif text.startswith("/*", index):
                end = text.find("*/", index + 2)
                if end < 0:
                    raise AssertionError("Unterminated strings comment")
                index = end + 2
            else:
                break
        return index
    while (position := skip(position)) < len(text):
        key, position = decoder.raw_decode(text, position)
        assert isinstance(key, str), "Non-string key"
        position = skip(position)
        assert text[position:position + 1] == "=", "Missing strings assignment"
        position = skip(position + 1)
        value, position = decoder.raw_decode(text, position)
        assert isinstance(value, str), "Non-string value"
        position = skip(position)
        assert text[position:position + 1] == ";", "Missing strings terminator"
        assert key not in result, "Duplicate strings key: " + key
        result[key] = value
        position += 1
    return result


FORMAT = re.compile(r"%(?:(\d+)\$)?[-+#0 ]*(?:\d+)?(?:\.\d+)?(hh|h|ll|l|j|z|t|L)?([@diuoxXfFeEgGaAcCsSp])")


def format_contract(value: str) -> dict[int, str]:
    result = {}
    cursor = 0
    argument = 1
    while (at := value.find("%", cursor)) >= 0:
        if value.startswith("%%", at):
            cursor = at + 2
            continue
        match = FORMAT.match(value, at)
        assert match is not None, "Unknown printf placeholder: " + value
        index = int(match.group(1)) if match.group(1) else argument
        if not match.group(1):
            argument += 1
        kind = (match.group(2) or "") + match.group(3)
        assert index not in result or result[index] == kind, "Conflicting placeholder type"
        result[index] = kind
        cursor = match.end()
    return result


def static_checks() -> dict:
    reference = json.loads((ROOT / "tests/official-home-reference.json").read_text())
    source_hashes = {}
    for path, expected in reference["official_sources"].items():
        content = (ROOT / path).read_bytes().replace(b"\r\n", b"\n")
        source_hashes[path] = sha(content)
        if path.endswith("DOMainViewController.m"):
            text = content.decode("utf-8")
            assert text.count(ROOT_HIDE_GUARD) == 1, "RootHide guard missing or changed"
            text = text.replace(ROOT_HIDE_GUARD, "", 1)
            assert text.count("jailbrokenVersionRootHide") == 1
            text = text.replace("jailbrokenVersionRootHide", "jailbrokenVersion", 1)
            localized = 'stringWithFormat:DOLocalizedString(@"Jailbreak_Failed_With_Error"), error'
            assert text.count(localized) == 1
            text = text.replace(localized, 'stringWithFormat:@"Jailbreak failed with error: %@", error', 1)
            content = text.encode("utf-8")
        assert sha(content) == expected, "Home differs from official baseline beyond approved functional/localized exceptions: " + path
    for path, expected in reference["protected_functional_sources"].items():
        assert sha((ROOT / path).read_bytes()) == expected, "Verified functionality unexpectedly edited: " + path
    main = (ROOT / "Application/Dopamine/UI/DOMainViewController.m").read_text(encoding="utf-8")
    for forbidden in (*REMOVED_KEYS, "uptimeTimer", "contentView", "addInformationRow", "systemUptimeDescription"):
        assert forbidden not in main, "Extra homepage content returned: " + forbidden
    assert "if (self.jailbreakBtn.didExpand)" in main
    assert main.index("if (self.jailbreakBtn.didExpand)") < main.index("self.updateButton =")
    assert main.index("otherJailbreakActived(false)") < main.index("[actionView hide]")
    assert "self.jailbreakBtn.topAnchor" in main
    tables = {lang: parse_strings((ROOT / f"Application/Dopamine/{lang}.lproj/Localizable.strings").read_text(encoding="utf-8-sig")) for lang in LANGUAGES}
    english = tables["en"]
    for lang, table in tables.items():
        assert not set(REMOVED_KEYS) & table.keys(), "Dead homepage key in " + lang
        assert english.keys() <= table.keys(), "Missing translated resource keys in " + lang
        assert all(table[key].strip() for key in english), "Empty localized value in " + lang
        for key in english:
            assert format_contract(table[key]) == format_contract(english[key]), (lang, key, "format type/order contract")
        if lang.startswith("zh"):
            assert table["Credits_Made_By"].startswith("作者：")
            assert "插件扩展" not in table["Spinlock_Fix_Warning"] and "外掛擴充" not in table["Spinlock_Fix_Warning"]
    assert tables["zh-CN"] == tables["zh-Hans"], "Simplified Chinese locale variants differ"
    print("PASS official header/menu/full homepage source; only RootHide guard, release source and localized failure log differ")
    print("PASS 20 verified functional source hashes retained")
    print("PASS five locale resources, format contracts and short author line; source completeness scoped to English resource keys")
    return {"reference_commit": reference["official_commit"], "source_sha256": source_hashes,
            "functional_reference": reference["functional_commit"],
            "localized_authors": {lang: tables[lang]["Credits_Made_By"] for lang in LANGUAGES}}


def native_checks() -> None:
    if platform.system() != "Darwin":
        raise SystemExit("Full native localization test requires macOS; choose --static-only for source checks.")
    with tempfile.TemporaryDirectory(prefix="official-home-localization-") as temporary:
        binary = Path(temporary) / "localization-contracts"
        subprocess.run(["xcrun", "--sdk", "macosx", "clang", "-fobjc-arc", "-Wall", "-Wextra", "-Werror",
                        "-g", "-O1", "-fsanitize=address,undefined", "-framework", "Foundation",
                        str(ROOT / "tests/official-home-localization.m"), "-o", str(binary)], check=True, timeout=90)
        environment = dict(os.environ)
        environment["ASAN_OPTIONS"] = "detect_leaks=0:abort_on_error=1"
        subprocess.run([str(binary), str(ROOT)], check=True, timeout=30, env=environment)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--static-only", action="store_true")
    options = parser.parse_args()
    static_checks()
    if options.static_only:
        print("SKIP native NSBundle formatting (--static-only)")
    else:
        native_checks()

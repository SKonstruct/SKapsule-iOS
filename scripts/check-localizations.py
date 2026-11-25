#!/usr/bin/env python3
"""Checks the translated strings (Natives/<language>.lproj/Localizable.strings) against the English ones.

Every language must have exactly the keys of en.lproj, and every value must keep the format placeholders of its key
(%@, %d, %ld, %s, %f and positional forms like %1$@), so a machine translation cannot break a screen. A value equal to
the English text just means "not translated yet". Run by `make test`; exits 1 and says what is wrong.
"""
import re
import sys
from pathlib import Path

NATIVES = Path(__file__).resolve().parent.parent / "Natives"
ENTRY = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', re.M)
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:l{0,2}[dixXuUfeEgGs@]|[0-9.]*l{0,2}[dfs@])")


def read(path: Path) -> dict[str, str]:
    data = path.read_bytes()
    # genstrings writes UTF-16; translators' tools write UTF-8. Both are valid .strings files.
    text = data.decode("utf-16") if data.startswith((b"\xff\xfe", b"\xfe\xff")) else data.decode("utf-8")
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return {m.group(1): m.group(2) for m in ENTRY.finditer(text)}


def placeholders(text: str) -> list[str]:
    # Positional placeholders compare without their position, so a translation may reorder them.
    return sorted(re.sub(r"^%\d+\$", "%", p) for p in PLACEHOLDER.findall(text))


def listed_languages() -> set[str]:
    plist = (NATIVES / "Info.plist").read_text(encoding="utf-8")
    if "CFBundleLocalizations" not in plist:
        return set()
    block = plist.split("<key>CFBundleLocalizations</key>")[-1].split("</array>")[0]
    return set(re.findall(r"<string>([A-Za-z-]+)</string>", block))


def main() -> int:
    english_file = NATIVES / "en.lproj" / "Localizable.strings"
    if not english_file.exists():
        print("Natives/en.lproj/Localizable.strings is missing", file=sys.stderr)
        return 1
    english = read(english_file)
    problems: list[str] = []
    if not english:
        problems.append("en.lproj/Localizable.strings has no entries")
    others = sorted(p for p in NATIVES.glob("*.lproj") if p.name != "en.lproj")
    for folder in others:
        file = folder / "Localizable.strings"
        if not file.exists():
            problems.append(f"{folder.name}: Localizable.strings is missing")
            continue
        strings = read(file)
        for key in sorted(set(english) - set(strings))[:5]:
            problems.append(f"{folder.name}: missing key {key!r}")
        for key in sorted(set(strings) - set(english))[:5]:
            problems.append(f"{folder.name}: unknown key {key!r} (not in en.lproj)")
        for key, value in strings.items():
            if key in english and placeholders(key) != placeholders(value):
                problems.append(
                    f"{folder.name}: placeholders of {key!r} are {placeholders(key)}, "
                    f"the translation {value!r} has {placeholders(value)}"
                )
    # Every language the app lists must have a folder (Info.plist CFBundleLocalizations).
    have = {p.name.removesuffix(".lproj") for p in NATIVES.glob("*.lproj")}
    for lang in sorted(listed_languages() - have):
        problems.append(f"Info.plist lists {lang} but Natives/{lang}.lproj does not exist")
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    print(f"localizations ok: {len(english)} strings, {len(others)} translated languages")
    return 0


if __name__ == "__main__":
    sys.exit(main())

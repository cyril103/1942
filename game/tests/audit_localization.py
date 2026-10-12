"""Validate shipped English catalogues without third-party dependencies.

Run from any directory: python game/tests/audit_localization.py
Checks exact source keys, duplicate translations, formatting contracts and literal
L10N.text calls. Runtime tests cover composed messages and language switching.
"""
import ast
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLACEHOLDER = re.compile(r"%(?:[-+0-9.]*)[sdfi]")
CALL = re.compile(r'L10N\.text\(\s*("(?:\\.|[^"\\])*")')


def main():
    entries = {}
    errors = []
    for path in sorted((ROOT / "data/localization").glob("*.en.json")):
        def unique_pairs(pairs):
            result = {}
            for key, value in pairs:
                if key in result:
                    errors.append(f"{path.name}: duplicate key {key!r}")
                result[key] = value
            return result
        catalog = json.loads(path.read_text(encoding="utf-8-sig"), object_pairs_hook=unique_pairs)
        for source, english in catalog.items():
            if not isinstance(english, str) or not english:
                errors.append(f"{path.name}: empty/non-string translation {source!r}")
                continue
            if source in entries and entries[source] != english:
                errors.append(f"{path.name}: conflicting translation {source!r}")
            entries[source] = english
            if PLACEHOLDER.findall(source) != PLACEHOLDER.findall(english):
                errors.append(f"{path.name}: format mismatch {source!r} -> {english!r}")
    calls = 0
    for path in sorted((ROOT / "scripts").rglob("*.gd")):
        for match in CALL.finditer(path.read_text(encoding="utf-8-sig")):
            source = ast.literal_eval(match.group(1))
            calls += 1
            if source and source not in entries:
                errors.append(f"{path.relative_to(ROOT)}: missing literal translation {source!r}")
    print(f"LOCALIZATION AUDIT: {len(entries)} messages, {calls} literal calls, {len(errors)} errors")
    for error in errors:
        print(error)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())

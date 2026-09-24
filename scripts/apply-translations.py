#!/usr/bin/env python3
"""Writes the Czech translations from translations-cs.py into the String Catalogs."""
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from importlib import import_module
module = import_module("translations-cs")
CS, UNTRANSLATED = module.CS, module.UNTRANSLATED

def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}

for path in ["Sources/Hashline/Resources/Localizable.xcstrings", "Sources/HashlineQuickLook/Localizable.xcstrings"]:
    catalog = json.load(open(path))
    # Strings no longer in the code (xcstringstool marks them stale).
    for key in [k for k, v in catalog["strings"].items() if v.get("extractionState") == "stale"]:
        del catalog["strings"][key]
    missing = []
    for key, entry in catalog["strings"].items():
        if key in UNTRANSLATED:
            entry["shouldTranslate"] = False
            entry.pop("localizations", None)
            continue
        value = CS.get(key)
        if value is None:
            missing.append(key)
            continue
        localizations = entry.setdefault("localizations", {})
        if isinstance(value, dict):
            localizations["cs"] = {"variations": {"plural": {form: unit(text) for form, text in value.items()}}}
            localizations["en"] = {"variations": {"plural": {
                "one": unit(key.replace("%lld ", "%lld ").rstrip("s") if key.endswith("s") else key),
                "other": unit(key)}}}
        else:
            localizations["cs"] = unit(value)
    json.dump(catalog, open(path, "w"), ensure_ascii=False, indent=2, sort_keys=True)
    open(path, "a").write("\n")
    print(path, "missing:", missing)

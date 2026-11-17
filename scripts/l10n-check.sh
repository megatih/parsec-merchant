#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Localization check (A11Y-032…035, PRD §9 M12 "localization completeness").
#   scripts/l10n-check.sh            check the committed string catalogs against the last app build's .stringsdata
#   scripts/l10n-check.sh --fix      sync the committed catalogs in place, then mark mechanical source-language units
#                                    translated (anything else stays `new` for human review)
#   scripts/l10n-check.sh --export   the check, plus `xcodebuild -exportLocalizations` (A11Y-034)
# Reads .stringsdata from build/DD (configuration L10N_CONFIG, default Debug). Writes only under build/l10n/, except
# --fix, which rewrites SpaceTraderMac/Resources/*.xcstrings. Ends with "L10N CHECK PASS" or "L10N CHECK FAIL".
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
MODE="check"
case "${1:-}" in
  --fix) MODE="fix" ;;
  --export) MODE="export" ;;
  "") ;;
  *) echo "usage: $0 [--fix|--export]"; exit 2 ;;
esac
CONFIG="${L10N_CONFIG:-Debug}"
OBJ="build/DD/Build/Intermediates.noindex/SpaceTraderMac.build/$CONFIG/SpaceTraderMac.build/Objects-normal"
OUT="build/l10n"
rm -rf "$OUT/sync"
mkdir -p "$OUT/sync"

/usr/bin/python3 -I - "$MODE" "$OBJ" "$OUT" <<'PY'
import json, os, pathlib, re, subprocess, sys

mode, obj, out = sys.argv[1], pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
RES = pathlib.Path("SpaceTraderMac/Resources")
CATALOGS = [RES / "Localizable.xcstrings", RES / "AppShortcuts.xcstrings"]
ALLOWLIST = pathlib.Path("scripts/l10n-allowlist.txt")
failures = []

def fail(msg):
    failures.append(msg)

# --- Xcode's catalog serialization (2-space indent, " : ", sorted keys, empty objects as "{\n\n}", no final newline).
def dump(o, ind=0):
    pad = "  " * ind
    if isinstance(o, dict):
        if not o:
            return "{\n\n" + pad + "}"
        items = [pad + "  " + json.dumps(k, ensure_ascii=False) + " : " + dump(o[k], ind + 1) for k in sorted(o)]
        return "{\n" + ",\n".join(items) + "\n" + pad + "}"
    if isinstance(o, list):
        if not o:
            return "[\n\n" + pad + "]"
        return "[\n" + ",\n".join(pad + "  " + dump(v, ind + 1) for v in o) + "\n" + pad + "]"
    if isinstance(o, bool):
        return "true" if o else "false"
    return json.dumps(o, ensure_ascii=False)

def load(p):
    return json.loads(p.read_text(encoding="utf-8"))

# --- 1. The app target's .stringsdata whose source still exists (A11Y-033 step 1).
stringsdata = []
if obj.is_dir():
    for f in sorted(obj.glob("*/*.stringsdata")):
        try:
            src = json.loads(f.read_text(encoding="utf-8")).get("source", "")
        except (OSError, ValueError):
            continue
        if src and os.path.exists(src):
            stringsdata.append(str(f))
if not any(s.endswith("ExtractedAppShortcutsMetadata.stringsdata") for s in stringsdata):
    fail(f"no app .stringsdata (with ExtractedAppShortcutsMetadata) under {obj}: build the app first")

def sync(paths):
    r = subprocess.run(["xcrun", "xcstringstool", "sync", *map(str, paths), "--stringsdata", *stringsdata],
                       capture_output=True, text=True)
    if r.returncode != 0:
        fail("xcstringstool sync failed: " + (r.stderr or r.stdout).strip())
    return r.returncode == 0

FORMAT = re.compile(r"%(?:\d+\$)?(?:lld|llu|ld|lu|d|u|@|f|\.\d+f|lf|s|c)")

def mechanical(key):
    """The positional form of a key ("%1$@ %2$@" for "%@ %@"): what a source-language unit holds by default."""
    n = [0]
    def rep(m):
        if "$" in m.group(0):
            return m.group(0)
        n[0] += 1
        return "%" + str(n[0]) + "$" + m.group(0)[1:]
    return FORMAT.sub(rep, key)

def mark_mechanical(cat):
    src = cat.get("sourceLanguage", "en")
    changed = 0
    for key, entry in cat["strings"].items():
        unit = entry.get("localizations", {}).get(src, {})
        su = unit.get("stringUnit")
        if su and su.get("state") == "new" and su.get("value") in (key, mechanical(key)):
            su["state"] = "translated"; changed += 1
        ss = unit.get("stringSet")
        if ss and ss.get("state") == "new" and ss.get("values") == [key]:
            ss["state"] = "translated"; changed += 1
    return changed

# --- --fix: sync in place, then mark mechanical units (A11Y-032).
if mode == "fix" and not failures:
    for c in CATALOGS:
        if not c.exists():
            c.write_text(dump({"sourceLanguage": "en", "strings": {}, "version": "1.0"}), encoding="utf-8")
    if sync(CATALOGS):
        for c in CATALOGS:
            cat = load(c)
            n = mark_mechanical(cat)
            text = dump(cat)
            if text != c.read_text(encoding="utf-8"):
                c.write_text(text, encoding="utf-8")
            print(f"{c}: {len(cat['strings'])} keys, {n} mechanical units marked translated")

# --- 2. A synced copy must equal the committed catalog (A11Y-033 step 2).
if not failures:
    copies = []
    for c in CATALOGS:
        if not c.exists():
            fail(f"{c} is missing")
            continue
        dst = out / "sync" / c.name
        dst.write_bytes(c.read_bytes())
        copies.append((c, dst))
    if copies and sync([d for _, d in copies]):
        for c, d in copies:
            if load(c) != load(d):
                before, after = load(c)["strings"], load(d)["strings"]
                added = sorted(set(after) - set(before))
                gone = sorted(k for k in before if after.get(k) != before[k])
                fail(f"{c.name}: catalog out of date: run scripts/l10n-check.sh --fix and review "
                     f"({len(added)} new, {len(gone)} changed or stale; first: {(added + gone)[:5]})")

# --- Allowlist: one JSON string literal (the key) per line, then a reason (A11Y-033 steps 3-4, A11Y-036).
allow = {}
if ALLOWLIST.exists():
    dec = json.JSONDecoder()
    for i, line in enumerate(ALLOWLIST.read_text(encoding="utf-8").splitlines(), 1):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        try:
            key, end = dec.raw_decode(s)
        except ValueError:
            fail(f"{ALLOWLIST}:{i}: expected a JSON string key, then a reason")
            continue
        reason = s[end:].strip()
        if not isinstance(key, str) or not reason:
            fail(f"{ALLOWLIST}:{i}: every allowlisted key needs a reason")
            continue
        allow[key] = reason

# --- 3 and 4. Content checks on the committed catalogs.
proj = json.loads(re.sub(r",(\s*[}\]])", r"\1", pathlib.Path("SpaceTraderMac.xcodeproj/project.xcproj").read_text()))
dev = proj.get("localizations", {}).get("development", "en")
others = [l for l in proj.get("localizations", {}).get("supported", []) if l not in ("Base", dev)]
COUNT = re.compile(r"%(?:\d+\$)?(?:lld|ld|d)")

def units(node, path):
    """Every stringUnit / stringSet below a localization, including variations and substitutions."""
    if isinstance(node, dict):
        for k, v in node.items():
            if k in ("stringUnit", "stringSet") and isinstance(v, dict):
                yield path + [k], v
            else:
                yield from units(v, path + [k])

def has_plural(node):
    if isinstance(node, dict):
        return "plural" in node or any(has_plural(v) for v in node.values())
    return False

for c in CATALOGS:
    if not c.exists():
        continue
    cat = load(c)
    if cat.get("sourceLanguage") != dev:
        fail(f"{c.name}: sourceLanguage is {cat.get('sourceLanguage')!r}, expected {dev!r}")
    for key, entry in cat["strings"].items():
        where = f"{c.name}: {key!r}"
        if entry.get("extractionState") == "stale":
            fail(f"{where}: stale (no longer in the source): remove it")
        for path, u in units(entry.get("localizations", {}), []):
            if u.get("state") in ("new", "needs_review"):
                fail(f"{where}: {'/'.join(path)} is {u.get('state')}")
        if not key.strip():
            fail(f"{where}: empty or whitespace-only key")
        elif key != key.strip() and key not in allow:
            fail(f"{where}: leading or trailing whitespace")
        if not entry.get("shouldTranslate", True):
            continue
        for lang in others:
            loc = entry.get("localizations", {}).get(lang)
            if not loc or not all(u.get("state") == "translated" for _, u in units(loc, [])):
                fail(f"{where}: not translated into {lang}")
        if c.name == "Localizable.xcstrings" and COUNT.search(key) and key not in allow:
            if not has_plural(entry.get("localizations", {}).get(dev, {})):
                fail(f"{where}: count-bearing key without a plural variation (add one, or allowlist it with a reason)")

for key in allow:
    if not any(key in load(c)["strings"] for c in CATALOGS if c.exists()):
        fail(f"{ALLOWLIST}: {key!r} is not a catalog key (remove the stale allowlist line)")

# --- 5. Bundled help exists for every supported language (A11Y-033 step 5).
topics = re.search(r"enum HelpTopic[^{]*\{\s*case ([^}]*?)\n\n", pathlib.Path("SpaceTraderMac/Views/About/HelpView.swift").read_text())
names = [t.strip() for t in re.sub(r"\s+", " ", topics.group(1)).split(",")] if topics else []
if not names:
    fail("could not read the HelpTopic cases")
for lang in [dev] + others:
    folder = RES / "Help" if lang == dev else RES / f"{lang}.lproj" / "Help"
    for t in names:
        if not (folder / f"{t}.md").is_file():
            fail(f"missing help page {folder / (t + '.md')}")

for f in failures:
    print("FAIL:", f)
summary = ", ".join(f"{c.name} {len(load(c)['strings'])} keys" for c in CATALOGS if c.exists())
print(f"catalogs: {summary}; stringsdata files: {len(stringsdata)}; languages: {[dev] + others}")
sys.exit(1 if failures else 0)
PY
RC=$?

if [ $RC -eq 0 ] && [ "$MODE" = "export" ]; then
  # A11Y-034: export must succeed without warnings and leave the committed catalogs untouched.
  rm -rf "$OUT/export"
  CATS="SpaceTraderMac/Resources/Localizable.xcstrings SpaceTraderMac/Resources/AppShortcuts.xcstrings"
  # shellcheck disable=SC2086
  BEFORE="$(shasum $CATS)"
  xcodebuild -exportLocalizations -project SpaceTraderMac.xcodeproj -localizationPath "$OUT/export" -exportLanguage en \
    -scheme SpaceTraderMac -derivedDataPath build/DD > "$OUT/export.log" 2>&1
  XRC=$?
  if [ $XRC -ne 0 ]; then
    echo "FAIL: xcodebuild -exportLocalizations exited $XRC (see $OUT/export.log)"; tail -20 "$OUT/export.log"; RC=1
  elif /usr/bin/grep -q -E 'warning:' "$OUT/export.log"; then
    echo "FAIL: exportLocalizations warnings:"; /usr/bin/grep -E 'warning:' "$OUT/export.log" | sort -u | head -20; RC=1
  elif [ ! -d "$OUT/export/en.xcloc" ]; then
    echo "FAIL: $OUT/export/en.xcloc is missing"; RC=1
  # shellcheck disable=SC2086
  elif [ "$(shasum $CATS)" != "$BEFORE" ]; then
    echo "FAIL: exportLocalizations rewrote the catalog: catalog out of date: run scripts/l10n-check.sh --fix and review"; RC=1
  else
    echo "export: $OUT/export/en.xcloc"
  fi
fi

if [ $RC -eq 0 ]; then echo "L10N CHECK PASS"; exit 0; else echo "L10N CHECK FAIL"; exit 1; fi

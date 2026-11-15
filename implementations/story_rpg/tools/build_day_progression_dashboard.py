#!/usr/bin/env python3
"""Rebuild standalone dashboard from Markdown; stdlib only.
Usage: python implementations/story_rpg/tools/build_day_progression_dashboard.py [--check]
Edit ACT_DAY_PROGRESSION_MAP.md, then rerun this script and commit HTML together.
The first-six-day commentary is preserved from the existing HTML audit data.
"""
import argparse
import json
import re
import sys
from pathlib import Path

DOCS = Path(__file__).resolve().parents[1] / "docs"
MAP = DOCS / "ACT_DAY_PROGRESSION_MAP.md"
LANG = DOCS / "LANGUAGE_DESIGN.md"
LANGUAGE_MAP = DOCS / "LANGUAGE_MAP.md"
HTML = DOCS / "ACT_DAY_PROGRESSION_DASHBOARD.html"
DATA_SCRIPT = re.compile(r'(<script id="progression-data">const DATA=)(.*?)(;</script>)', re.S)
GROUPS = {
    "P0": "Контакт и понимание", "P1": "Предметы и состояния",
    "P2": "Люди, место, передача", "P3": "Время, выбор, правила",
    "P4": "Документы, сравнение, связи", "P5": "Прошлое и планы",
    "P6": "Интеграция",
}

def cells(line):
    return [x.strip() for x in line.split("|")[1:-1]]

def render(original, source, matrix, language_map):
    match = DATA_SCRIPT.search(original)
    if match is None:
        raise ValueError("Missing embedded DATA in dashboard")
    previous = json.loads(match.group(2))
    names = {}
    for line in matrix.splitlines():
        if re.match(r"^\| M\d\d \|", line):
            c = cells(line)
            names[c[0]] = c[1].replace("**", "").replace(chr(96), "")[:88]
    days, count = [], 0
    for line in source.splitlines():
        found = re.match(r"^\| \*\*D(\d+)\*\* \|", line)
        if not found:
            continue
        c = cells(line)
        ids = re.findall(r"\bM\d\d\b", c[3])
        day = int(found.group(1))
        if day != len(days) + 1:
            raise ValueError("Days must be consecutive, starting with D01")
        count += len(ids)
        days.append({"day": day, "phase": c[1], "title": c[2], "new": ids,
                     "reuse": [], "complexity": 0, "cumulative": count,
                     "existing": "Есть сюжетная основа" in c[4]})
    if not days or count != 55:
        raise ValueError("Exactly 55 M## must be assigned to days")
    ids = [x for d in days for x in d["new"]]
    if len(set(ids)) != 55 or set(ids) != set(names):
        raise ValueError("M## in daily plan differ from LANGUAGE_DESIGN.md")
    section = source.split("## 7. Ожидаемая кривая сложности языка", 1)
    if len(section) != 2:
        raise ValueError("Difficulty section absent from markdown")
    found = re.search(r"line\s*\[([0-9.,\s]+)\]", section[1])
    if not found:
        raise ValueError("Cannot find difficulty series")
    points = [float(v.strip()) for v in found.group(1).split(",")]
    if len(points) != len(days):
        raise ValueError("Difficulty series/day count mismatch")
    for day, difficulty in zip(days, points):
        day["complexity"] = difficulty
    # Canonical skill horizons come from LANGUAGE_MAP.md, not the day label.
    # A day may introduce one early P1 function amid mostly P0 language.
    section_parts = language_map.split("## 2. Карта нарастания по семантическим пачкам", 1)
    if len(section_parts) != 2:
        raise ValueError("Missing language skill map")
    skill_rows = section_parts[1].split("### Микрошаги внутри", 1)[0]
    first = {}
    for line in skill_rows.splitlines():
        if re.match(r"^\| \*\*P[0-5]\*\* \|", line):
            c = cells(line)
            phase = c[0].replace("*", "")
            for name in re.findall(r"\bM\d\d\b", c[-1]):
                if name in first:
                    raise ValueError("Duplicate M## in language map: " + name)
                first[name] = phase
    if set(first) != set(names):
        raise ValueError("Language horizons do not cover all M##")

    rows = [cells(s) for s in source.splitlines() if re.match(r"^\| \*\*P[0-5]\*\* \|", s)]
    if len(rows) != 6:
        raise ValueError("Expected 6 language reuse groups")
    for row in rows:
        group = row[0].replace("*", "")
        if len(row) != len(days) + 1:
            raise ValueError("Reuse matrix column count != days")
        for index, mark in enumerate(row[1:]):
            if mark in ("↻", "◉"):
                days[index]["reuse"].append(group)
            elif mark not in ("●", "·"):
                raise ValueError("Unknown heatmap symbol: " + mark)
    payload = {"days": days, "groups": GROUPS, "skillNames": names,
               "audit": previous.get("audit", []), "first": first}
    encoded = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).replace("<", "\\u003c")
    return original[:match.start(2)] + encoded + original[match.end(2):]

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--check", action="store_true", help="Fail if dashboard needs regeneration")
    args = p.parse_args()
    original = HTML.read_text(encoding="utf-8")
    new = render(original, MAP.read_text(encoding="utf-8"), LANG.read_text(encoding="utf-8"), LANGUAGE_MAP.read_text(encoding="utf-8"))
    if args.check:
        if new != original:
            print("Dashboard out of date — rebuild it and commit with Markdown", file=sys.stderr)
            return 1
        print("Dashboard synchronized")
        return 0
    if new != original:
        HTML.write_text(new, encoding="utf-8")
        print("Dashboard regenerated")
    else:
        print("Dashboard already synchronized")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Rebuild the interactive, standalone HTML from the canonical Markdown plan.

Run from the repository root:
    python implementations/story_rpg/tools/build_day_progression_dashboard.py
    python implementations/story_rpg/tools/build_day_progression_dashboard.py --check

All daily story goals, first M## contacts, R/P contracts, meanings, heatmap
repetitions and the complexity curve come from ACT_DAY_PROGRESSION_MAP.md.
M## names come from LANGUAGE_DESIGN.md and skill categories from LANGUAGE_MAP.md.
Only Python's standard library is needed; no LLM, browser or network.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

DOCS = Path(__file__).resolve().parents[1] / "docs"
DAY_MAP = DOCS / "ACT_DAY_PROGRESSION_MAP.md"
LANGUAGE_DESIGN = DOCS / "LANGUAGE_DESIGN.md"
LANGUAGE_MAP = DOCS / "LANGUAGE_MAP.md"
DASHBOARD = DOCS / "ACT_DAY_PROGRESSION_DASHBOARD.html"

DATA_SCRIPT = re.compile(r'(<script id="progression-data">const DATA=)(.*?)(;</script>)', re.DOTALL)
GROUPS = {
    "P0": "Контакт и понимание", "P1": "Предметы и состояния",
    "P2": "Люди, место, передача", "P3": "Время, выбор, правила",
    "P4": "Документы, сравнение, связи", "P5": "Прошлое и планы",
    "P6": "Интеграция",
}

def cells(row: str) -> list[str]:
    return [value.strip() for value in row.split("|")[1:-1]]

def between(source: str, begin: str, end: str) -> str:
    parts = source.split(begin, 1)
    if len(parts) != 2:
        raise ValueError("Section not found: " + begin)
    end_parts = parts[1].split(end, 1)
    if len(end_parts) != 2:
        raise ValueError("Section boundary not found: " + end)
    return end_parts[0]

def skill_labels(source: str) -> dict[str, str]:
    names = {}
    for row in source.splitlines():
        if re.match(r"^\| M\d\d \|", row):
            values = cells(row)
            names[values[0]] = values[1].replace("**", "").replace(chr(96), "")[:88]
    if len(names) != 55:
        raise ValueError(f"LANGUAGE_DESIGN: expected 55 M##; found {len(names)}")
    return names

def skill_horizons(source: str) -> dict[str, str]:
    body = between(source, "## 2. Карта нарастания по семантическим пачкам",
                   "### Микрошаги внутри")
    first = {}
    for row in body.splitlines():
        if re.match(r"^\| \*\*P[0-5]\*\* \|", row):
            values = cells(row)
            horizon = values[0].replace("*", "")
            for name in re.findall(r"\bM\d\d\b", values[-1]):
                if name in first:
                    raise ValueError("Duplicate M## in LANGUAGE_MAP: " + name)
                first[name] = horizon
    return first

def parse_days(source: str) -> tuple[list[dict], dict[str, dict]]:
    daily_section = between(source, "## 2. Дневная модель — сюжетные исходы",
                            "## 3. Накопление первых доступных коммуникативных функций")
    contract_section = between(source, "## 7. Минимальный диалоговый контракт каждого дня",
                               "## 8. Трассировка всех 13 результатов")
    contracts = {}
    for row in contract_section.splitlines():
        match = re.match(r"^\| \*\*D(\d+)\*\* \|", row)
        if match:
            values = cells(row)
            number = int(match.group(1))
            if number in contracts:
                raise ValueError("Duplicate contract for day " + str(number))
            if len(values) != 4:
                raise ValueError("Contract must contain day, R, P, contrast")
            contracts[number] = {
                "R": values[1],
                "P": values[2],
                "risk": values[3],
            }
    days = []
    cumulative = 0
    for row in daily_section.splitlines():
        match = re.match(r"^\| \*\*D(\d+)\*\* \|", row)
        if not match:
            continue
        values = cells(row)
        number = int(match.group(1))
        if number != len(days) + 1:
            raise ValueError("Daily sequence must start at D01 and be consecutive")
        if len(values) != 6:
            raise ValueError("Daily row must have 6 columns")
        ids = re.findall(r"\bM\d\d\b", values[3])
        cumulative += len(ids)
        days.append({
            "day": number, "phase": values[1], "title": values[2],
            "new": ids, "reuse": [], "complexity": 0, "cumulative": cumulative,
            "existing": False, "effect": values[4],
        })
    if not days or cumulative != 55 or len({id for d in days for id in d["new"]}) != 55:
        raise ValueError("Day plan must assign all 55 unique M## exactly once")
    if set(contracts) != {d["day"] for d in days}:
        raise ValueError("Every day needs exactly one R/P/contrast contract")
    return days, contracts

def parse_curve(source: str, count: int) -> list[float]:
    section = source.split("## 6. Графическое усложнение доступных смыслов", 1)
    if len(section) != 2:
        raise ValueError("Difficulty section missing")
    match = re.search(r"line\s*\[([0-9.,\s]+)\]", section[1])
    if match is None:
        raise ValueError("Difficulty line missing")
    points = [float(value.strip()) for value in match.group(1).split(",")]
    if len(points) != count:
        raise ValueError("Complexity curve length does not match days")
    return points

def apply_reuse(source: str, days: list[dict], first: dict[str, str]) -> None:
    section = between(source, "## 5. Тепловая матрица возвращений",
                      "## 6. Графическое усложнение доступных смыслов")
    rows = [cells(row) for row in section.splitlines()
            if re.match(r"^\| \*\*P[0-5]\*\* \|", row)]
    if len(rows) != 6:
        raise ValueError("Heatmap must have 6 skill groups")
    introduced = set()
    for values in rows:
        group = values[0].replace("*", "")
        if len(values) != len(days) + 1:
            raise ValueError("Heatmap columns do not match day count")
        for day, marker in zip(days, values[1:]):
            is_new = any(first[id] == group for id in day["new"])
            if is_new != (marker in ("●", "◉")):
                raise ValueError(f"Heatmap introduction mismatch {group} D{day['day']:02}")
            if marker in ("↻", "◉"):
                day["reuse"].append(group)
            elif marker != ("●", "·"):
                raise ValueError("Unknown heatmap marker " + marker)
    for day in days:
        for group in day["reuse"]:
            if group not in introduced and not any(first[id] == group for id in day["new"]):
                raise ValueError(f"Reuse of {group} before introduction")
        introduced.update(first[id] for id in day["new"])

def build(html: str, source: str, matrix: str, language: str) -> str:
    embedded = DATA_SCRIPT.search(html)
    if embedded is None:
        raise ValueError("Dashboard DATA script missing")
    names = skill_labels(matrix)
    first = skill_horizons(language)
    days, contracts = parse_days(source)
    if set(first) != set(names):
        raise ValueError("Skill horizons and language design disagree")
    for day, value in zip(days, parse_curve(source, len(days))):
        day["complexity"] = value
    apply_reuse(source, days, first)
    audit = [
        {
            "day": day["day"], "focus": day["title"],
            "P": contracts[day["day"]]["P"], "R": contracts[day["day"]]["R"],
            "reuse": day["effect"], "risk": contracts[day["day"]]["risk"],
        }
        for day in days
    ]
    payload = {
        "days": days, "groups": GROUPS, "skillNames": names,
        "audit": audit, "first": first,
    }
    encoded = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).replace("<", r"\u003c")
    return html[:embedded.start(2)] + encoded + html[embedded.end(2):]

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true",
                        help="Fail if the tracked HTML differs from Markdown")
    args = parser.parse_args()
    old = DASHBOARD.read_text(encoding="utf-8")
    fresh = build(old, DAY_MAP.read_text(encoding="utf-8"),
                  LANGUAGE_DESIGN.read_text(encoding="utf-8"),
                  LANGUAGE_MAP.read_text(encoding="utf-8"))
    if args.check:
        if old != fresh:
            print("Dashboard is stale. Rebuild it and commit HTML with Markdown.", file=sys.stderr)
            return 1
        print("Dashboard matches the Markdown and language references.")
        return 0
    if old != fresh:
        DASHBOARD.write_text(fresh, encoding="utf-8")
        print("Rebuilt " + str(DASHBOARD))
    else:
        print("Dashboard already current.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

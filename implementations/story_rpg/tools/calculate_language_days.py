#!/usr/bin/env python3
"""Воспроизводимый расчёт предварительной длительности из независимых языковых данных.

Числа дней — модель минимальной вместимости, НЕ доказательство усвоения или
готовый календарь игровых эпизодов. Не читает ACT/сюжетные файлы.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
STAGES = ("P0", "P1", "P2a", "P2b", "P2c", "P3a", "P3b", "P3c",
          "P4a", "P4b", "P4c", "P5", "P6")
COLUMNS = ("U", "M", "G", "P", "A", "R", "LO")

# РЕДАКТОРСКИЕ ГИПОТЕЗЫ о допустимом новом фокусе за игровой день.
# Это не научно доказанные пределы и не дневная квота освоенных слов.
PROFILES = {
    "compact": {
        "default": {"U": 3, "M": 3, "G": 2, "P": 2, "A": 8, "R": 12, "LO": 4},
        "P0": {"U": 2, "M": 3, "G": 2, "P": 2, "A": 6, "R": 8},
        "P1": {"U": 3, "M": 2, "G": 2, "P": 2, "A": 7, "R": 10},
    },
    "baseline": {
        "default": {"U": 2, "M": 2, "G": 1, "P": 2, "A": 6, "R": 9, "LO": 3},
        "P0": {"U": 2, "M": 2, "G": 1, "P": 1, "A": 5, "R": 6},
        "P1": {"U": 2, "M": 2, "G": 1, "P": 1, "A": 5, "R": 7},
    },
    "gentle": {
        "default": {"U": 2, "M": 2, "G": 1, "P": 1, "A": 4, "R": 6, "LO": 2},
        "P0": {"U": 1, "M": 2, "G": 1, "P": 1, "A": 3, "R": 5},
    },
}
START = "<!-- LANGUAGE_DAY_MODEL_START -->"
END = "<!-- LANGUAGE_DAY_MODEL_END -->"


def calculate() -> tuple[dict, dict]:
    program = json.loads((DOCS / "LANGUAGE_PRACTICE_UNITS.json").read_text(encoding="utf-8"))
    lexicon = json.loads((DOCS / "LANGUAGE_LEXICAL_CATALOG.json").read_text(encoding="utf-8"))
    counts = {stage: dict.fromkeys(COLUMNS, 0) for stage in STAGES}
    ids = set()

    for unit in program["items"]:
        stage = unit["stage"]
        if stage not in counts or unit["id"] in ids:
            raise ValueError(f"Неизвестный горизонт или повтор ID: {unit['id']} {stage}")
        ids.add(unit["id"])
        row = counts[stage]
        row["U"] += 1
        row["M"] += len(unit["introduce_m"])
        row["G"] += len(unit["introduce_g"])
        row["P"] += len(unit["first_p"])
        # До P6 это кандидаты ранней практики LO, не итоговый экзамен.
        if stage == "P6":
            row["LO"] += len(unit.get("outcome_candidates", []))

    for entry in lexicon["entries"]:
        scope = entry["learning_scope"]
        stage = scope["focus_band"]
        if stage not in counts:
            raise ValueError(f"Неизвестный языковой горизонт лексики: {entry['text']}: {stage}")
        if scope["track"] in ("active_core", "receptive_core"):
            counts[stage]["A" if scope["track"] == "active_core" else "R"] += 1
        elif scope["track"] not in ("productive_choice", "contextual"):
            raise ValueError(f"Неизвестная роль лексики: {entry['text']}: {scope['track']}")

    days = {stage: {} for stage in STAGES}
    for name, profile in PROFILES.items():
        for stage, row in counts.items():
            caps = {**profile["default"], **profile.get(stage, {})}
            if any(caps[k] < 1 for k in COLUMNS):
                raise ValueError("Нулевой бюджет дня")
            days[stage][name] = max(1, *(math.ceil(row[k] / caps[k]) for k in COLUMNS))
    return counts, days


def render(counts: dict, days: dict) -> str:
    lines = [
        "| Языковой горизонт | Единицы U | Первые M / G / P | Фокус A / R | Компактный | Базовый | Бережный |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    for stage in STAGES:
        r, d = counts[stage], days[stage]
        lines.append(f"| {stage} | {r['U']} | {r['M']} / {r['G']} / {r['P']} | "
                     f"{r['A']} / {r['R']} | {d['compact']} | {d['baseline']} | {d['gentle']} |")
    total = {k: sum(counts[s][k] for s in STAGES) for k in COLUMNS}
    td = {p: sum(days[s][p] for s in STAGES) for p in PROFILES}
    lines.append(f"| **Итого** | **{total['U']}** | "
                 f"**{total['M']} / {total['G']} / {total['P']}** | "
                 f"**{total['A']} / {total['R']}** | "
                 f"**{td['compact']}** | **{td['baseline']}** | **{td['gentle']}** |")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="Проверить встроенную таблицу в LANGUAGE_PROGRAM.md")
    mode.add_argument("--write", action="store_true", help="Обновить только вычисляемую таблицу")
    args = parser.parse_args()
    counts, days = calculate()
    table = render(counts, days)
    if not (args.check or args.write):
        print(table)
        return 0
    path = DOCS / "LANGUAGE_PROGRAM.md"
    content = path.read_text(encoding="utf-8")
    if content.count(START) != 1 or content.count(END) != 1:
        raise ValueError("Ожидались ровно два маркера диапазона таблицы")
    before, tail = content.split(START, 1)
    _, after = tail.split(END, 1)
    expected = before + START + "\n" + table + "\n" + END + after
    if args.check:
        if content != expected:
            print("LANGUAGE_PROGRAM.md: таблица длительности устарела; запустите --write")
            return 1
        print("LANGUAGE_PROGRAM.md: расчёт языковых дней согласован с JSON")
        return 0
    path.write_text(expected, encoding="utf-8")
    print("LANGUAGE_PROGRAM.md: таблица длительности пересчитана")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

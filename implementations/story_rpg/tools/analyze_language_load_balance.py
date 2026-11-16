#!/usr/bin/env python3
"""Validate and report the setting-independent language load schedule.

Uses LANGUAGE_* files only. ACT_* (story/scenes) must never be an input.
Usage:
    python implementations/story_rpg/tools/analyze_language_load_balance.py --write
    python implementations/story_rpg/tools/analyze_language_load_balance.py --check
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path


DOCS = Path(__file__).resolve().parent.parent / "docs"
INPUT = DOCS / "LANGUAGE_PRACTICE_UNITS.json"
MAP = DOCS / "LANGUAGE_MAP.md"
PROGRESSION = DOCS / "LANGUAGE_PROGRESSION.md"
OUTPUT = DOCS / "LANGUAGE_LOAD_BALANCE_REPORT.md"
STAGES = ["P0", "P1", "P2a", "P2b", "P2c", "P3a", "P3b", "P3c",
          "P4a", "P4b", "P4c", "P5", "P6"]
FIELDS = ("introduce_m", "introduce_g", "first_p", "revisit_m")


def horizon(stage: str) -> str:
    return stage[:2]


def read_map() -> dict[str, dict[str, str]]:
    result = {}
    for line in MAP.read_text(encoding="utf-8").splitlines():
        if not re.match(r"^\| M\d{2} \|", line):
            continue
        cells = [v.strip().replace("**", "") for v in line.split("|")[1:-1]]
        if len(cells) != 6:
            raise ValueError(f"Bad M row: {line}")
        mid, mode, first_r, first_p, revisit, lo = cells
        result[mid] = {
            "mode": mode, "first_r": first_r, "first_p": first_p,
            "revisit": revisit, "lo": lo,
        }
    return result


def grammar_stages() -> dict[str, str]:
    found = {}
    for line in PROGRESSION.read_text(encoding="utf-8").splitlines():
        cells = [c.strip().replace("**", "") for c in line.split("|")[1:-1]]
        if len(cells) != 3 or not re.fullmatch(r"P[0-6]", cells[0]):
            continue
        for gid in re.findall(r"G\d{2}", cells[2]):
            if gid in found:
                raise ValueError(f"Duplicate grammar {gid}")
            found[gid] = cells[0]
    return found


def revisit_stages(text: str) -> set[str]:
    stages = set()
    for part in text.split(","):
        part = part.strip()
        match = re.fullmatch(r"P(\d)[–-]P(\d)", part)
        if match:
            stages.update(f"P{i}" for i in range(int(match[1]), int(match[2]) + 1))
        elif re.fullmatch(r"P[0-6]", part):
            stages.add(part)
        else:
            raise ValueError(f"Unknown revisit specification {text!r}")
    return stages


def validate(doc: dict, mmap: dict, gmap: dict) -> list[str]:
    errors = []
    actual = {field: defaultdict(list) for field in FIELDS}
    previous = -1
    counters = Counter()

    for item in doc["items"]:
        sid, stage = item["id"], item["stage"]
        if stage not in STAGES:
            errors.append(f"{sid}: invalid stage {stage}")
            continue
        order = STAGES.index(stage)
        if order < previous:
            errors.append(f"{sid}: stage order went backwards")
        previous = order
        counters[stage] += 1
        if sid != f"{stage}-{counters[stage]:02d}":
            errors.append(f"{sid}: unexpected id in stage {stage}")
        if not item.get("goal") or not item.get("contrast") or not item.get("context"):
            errors.append(f"{sid}: incomplete semantic contract")
        for field in FIELDS:
            values = item.get(field)
            if not isinstance(values, list) or len(values) != len(set(values)):
                errors.append(f"{sid}: invalid/duplicated field {field}")
                continue
            for code in values:
                actual[field][code].append(item)

    for field, expected in (("introduce_m", mmap), ("introduce_g", gmap),
                             ("first_p", {m: data for m, data in mmap.items()
                                           if data["first_p"] != "—"}),
                             ("revisit_m", mmap)):
        for code in expected:
            seen = actual[field].get(code, [])
            if not seen:
                errors.append(f"{field}: missing {code}")
            if field != "revisit_m" and len(seen) != 1:
                errors.append(f"{field}: {code} occurs {len(seen)} times")
        for code in actual[field]:
            if code not in expected:
                errors.append(f"{field}: unknown/invalid target {code}")

    for mid, items in actual["introduce_m"].items():
        if mid in mmap:
            for it in items:
                if horizon(it["stage"]) != mmap[mid]["first_r"]:
                    errors.append(f"{it['id']}: {mid} R must start at {mmap[mid]['first_r']}")
    for mid, items in actual["first_p"].items():
        if mid in mmap:
            for it in items:
                if horizon(it["stage"]) != mmap[mid]["first_p"]:
                    errors.append(f"{it['id']}: {mid} P must start at {mmap[mid]['first_p']}")
    for gid, items in actual["introduce_g"].items():
        if gid in gmap:
            for it in items:
                if horizon(it["stage"]) != gmap[gid]:
                    errors.append(f"{it['id']}: {gid} must start at {gmap[gid]}")
    for mid, items in actual["revisit_m"].items():
        if mid in mmap:
            allowed = revisit_stages(mmap[mid]["revisit"])
            for it in items:
                if horizon(it["stage"]) not in allowed:
                    errors.append(f"{it['id']}: {mid} revisit outside {mmap[mid]['revisit']}")
    if any(item["introduce_m"] or item["introduce_g"] or item["first_p"]
           for item in doc["items"] if item["stage"] == "P6"):
        errors.append("P6: new M/G or first P is prohibited")
    if dict(counters) != doc["horizon_units"]:
        errors.append("horizon_units not synchronized with items")

    forbidden = re.compile(r"\bD\d{2}-S\d\b|корабл|Лен[аеуы]|навигатор|снабженец",
                           re.IGNORECASE)
    for it in doc["items"]:
        if forbidden.search(it["goal"] + " " + it["contrast"] + " " + it["context"]):
            errors.append(f"{it['id']}: contains plot-specific assumption")

    return sorted(set(errors))


def table(doc: dict) -> tuple[list[str], list[str]]:
    totals = defaultdict(Counter)
    maximum = 0
    peaks = []
    for it in doc["items"]:
        t = totals[it["stage"]]
        t["units"] += 1
        for field in FIELDS:
            t[field] += len(it[field])
        novelty = sum(len(it[field]) for field in FIELDS[:3])
        maximum = max(maximum, novelty)
        if novelty >= 3:
            peaks.append(f"{it['id']} ({novelty}: M={len(it['introduce_m'])}, "
                         f"G={len(it['introduce_g'])}, P={len(it['first_p'])})")

    rows = ["| Горизонт | Единиц | Первое R (M) | Новая G | Первое P (M) | ↻ | "
            "Макс. новых ID на единицу |",
            "|---|---:|---:|---:|---:|---:|---:|"]
    for stage in STAGES:
        t = totals[stage]
        local_peak = max(
            (sum(len(it[k]) for k in FIELDS[:3])
             for it in doc["items"] if it["stage"] == stage), default=0
        )
        rows.append(f"| {stage} | {t['units']} | {t['introduce_m']} | "
                    f"{t['introduce_g']} | {t['first_p']} | {t['revisit_m']} | "
                    f"{local_peak} |")
    return rows, peaks


def report(doc: dict, mmap: dict, gmap: dict, errors: list[str]) -> str:
    rows, peaks = table(doc)
    counts = {key: sum(len(x[key]) for x in doc["items"]) for key in FIELDS}
    states = "ВАЛИДНЫ" if not errors else "НЕ ВАЛИДНЫ"
    lines = [
        "# LP06/LP07/LP08/LP10 — баланс языковых коммуникативных единиц",
        "",
        "**Источник:** [LANGUAGE_PRACTICE_UNITS.json](LANGUAGE_PRACTICE_UNITS.json), "
        "[LANGUAGE_MAP.md](LANGUAGE_MAP.md), "
        "[LANGUAGE_PROGRESSION.md](LANGUAGE_PROGRESSION.md). "
        "**Ни один сценарный документ не используется.**",
        "",
        "**Статус:** абстрактный проект последовательности, не игровые дни, "
        "не завершённые занятия, не доказательство изучения и не проверка на A0.",
        "",
        f"**Структурный контроль: {states}.** {len(doc['items'])} независимых "
        f"языковых единиц, {len(mmap)} из {len(mmap)} первых R для M, "
        f"{len(gmap)} из {len(gmap)} первых G, {counts['first_p']} "
        "первых P и {0 if errors else len(mmap)} M с кандидатами ↻. "
        "Значимость, доступность и объём слов **не** валидируются этим подсчётом.",
        "",
        "## 1. Вектор нагрузки по горизонтам",
        "",
        *rows,
        "",
        "Числа — **учётные ID-якоря**, не реальные когнитивные веса. "
        "Первое R навыка, новая грамматическая форма и первая самостоятельная P "
        "проверяются раздельно. В одном шаге они могут относиться "
        "к **одному** содержательному различию; простая сумма переоценивает "
        "новизну. Возвраты ↻ — **запланированы**, не подтверждены.",
        "",
        "## 2. Точки концентрации нескольких новых якорей",
        "",
        *[f"- {item}" for item in peaks],
        "",
        "Эти точки требуют **качественного** аудита: насколько вводимая лексика знакома, "
        "не совмещены ли новые адресат/отрицание/время, можно ли разделить "
        "первое R и первое P. Сам факт трёх ID не означает перегруз.",
        "",
        "## 3. Контроль непрерывной практики",
        "",
        "- P0–P1: короткие самостоятельные слова/вопросы с первого контакта; "
        "новые значения показываются через известные опоры.",
        "- P2–P4: микрошаги удерживают роли и жанры отдельно от "
        "сложной одновременной грамматики; знакомое возвращается с новой целью.",
        "- P5: формы прошлого накладываются на знакомые предметы/действия, "
        "а не на новый сюжет или большой словарь.",
        "- P6: не добавляются новые обязательные M/G; только "
        "комбинация известных смыслов и самостоятельный P.",
        "- Никакие меры сложности не калиброваны на реальных игроках; "
        "не определено число игровых дней и реальная длительность каждой единицы.",
        "",
        "## 4. Что остаётся открытым",
        "",
        "1. **Лексическая нагрузка:** связать каждую единицу с переносимым "
        "словарём, первыми обязательными словами и только фоновой рецепцией. "
        "Нельзя использовать уже написанные игровые диалоги как план словаря.",
        "2. **Смысловая проверка:** сделать по каждому критичному контрасту "
        "две замены данных, без подсказанного ответа; пока это дизайн, не тест.",
        "3. **Сглаживание:** качественно оценить группы с несколькими новыми "
        "якорями, отдельно трудность новой R и P, затем перестроить единицы "
        "внутри горизонтов без потери покрытия.",
        "4. **Реальная A0-проверка и отсроченный перенос:** невозможно "
        "доказать из равномерной таблицы, необходимы интерфейс и учащиеся.",
        "",
        "## 5. Проверка воспроизводимости",
        "",
        "Команда: `python implementations/story_rpg/tools/"
        "analyze_language_load_balance.py --check`. "
        "Генерация: та же команда с `--write`.",
        "",
        "Проверка включает: уникальность 55 M/34 G/42 первых P, "
        "этапность R/P по исходной карте, допустимость ↻, "
        "отсутствие новых обязательных ID на P6, непривязанность "
        "шагов к конкретному сюжету и совпадение счётчиков.",
    ]
    if errors:
        lines.extend(["", "### Ошибки", ""])
        lines.extend(f"- {error}" for error in errors)
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--write", action="store_true")
    group.add_argument("--check", action="store_true")
    options = parser.parse_args()
    doc = json.loads(INPUT.read_text(encoding="utf-8"))
    mmap, gmap = read_map(), grammar_stages()
    errors = validate(doc, mmap, gmap)
    if errors:
        print("FAIL: " + "\nFAIL: ".join(errors), file=sys.stderr)
        return 1
    expected = report(doc, mmap, gmap, errors)
    if options.write:
        OUTPUT.write_text(expected, encoding="utf-8")
        print(f"WROTE {OUTPUT.relative_to(DOCS.parent.parent.parent)}")
        return 0
    if not OUTPUT.is_file():
        print(f"FAIL: report not found: {OUTPUT}", file=sys.stderr)
        return 1
    if OUTPUT.read_text(encoding="utf-8") != expected:
        print("FAIL: language load report is outdated; use --write", file=sys.stderr)
        return 1
    print(f"PASS: 55 M, 34 G, 42 first P, {len(doc['items'])} language units")
    return 0


if __name__ == "__main__":
    sys.exit(main())

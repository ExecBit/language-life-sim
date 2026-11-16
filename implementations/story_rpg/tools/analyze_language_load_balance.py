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
LEXICAL = DOCS / "LANGUAGE_LEXICAL_ANCHORS.json"
OUTCOMES = DOCS / "LEARNING_OUTCOMES.md"
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



def lexical_stage_report(doc: dict, glossary: dict) -> tuple[str, list[str]]:
    """Validate all selected lexical anchors against the independent catalogue."""
    errors = []
    expected = {}
    for group in glossary["groups"]:
        for expression in group["minimal_anchor_expressions"]:
            key = (group["id"], expression)
            if key in expected:
                errors.append(f"duplicate catalogue anchor: {key}")
            expected[key] = group["role"]
    actual = defaultdict(list)
    lexical_totals = defaultdict(Counter)
    for item in doc["items"]:
        stage = item["stage"]
        for anchor in item.get("lexical_anchors", []):
            key = (anchor["group"], anchor["expression"])
            actual[key].append(item["id"])
            role = anchor["obligation"]
            if role not in ("functional_candidate", "contextual_optional"):
                errors.append(f"{item['id']}: invalid lexical role {role}")
            if key not in expected:
                errors.append(f"{item['id']}: unknown lexical anchor {key}")
            elif (role == "functional_candidate") != (
                expected[key] == "functional_anchor_candidate"
            ):
                errors.append(f"{item['id']}: mismatched role {key}")
            lexical_totals[stage][role] += 1
    for key in expected:
        if len(actual[key]) != 1:
            errors.append(f"lexical anchor {key} occurs {len(actual[key])} times")
    if len(glossary["groups"]) != 29:
        errors.append("expected 29 independent lexical groups")

    lines = [
        "","## 6. Минимальные лексические опоры (не словарные квоты)","",
        "Источник: [LANGUAGE_LEXICAL_ANCHORS.json](LANGUAGE_LEXICAL_ANCHORS.json), "
        "на основе [LANGUAGE_LEXICON.md](LANGUAGE_LEXICON.md) — **без сценового словаря**.","",
        f"Распределено **{len(expected)}** выражений-кандидатов из **29 тематических групп**. "
        f"Из них **{sum(t['functional_candidate'] for t in lexical_totals.values())}** "
        "функциональных опор и "
        f"**{sum(t['contextual_optional'] for t in lexical_totals.values())}** "
        "контекстных необязательных. **Одна фраза может включать несколько лексем, "
        "а один знакомый корень — несколько форм; это не подсчёт новых слов.**","",
        "| Горизонт | Функциональные выражения-кандидаты | Контекстные, необязательные |",
        "|---|---:|---:|",
    ]
    for stage in STAGES:
        n = lexical_totals[stage]
        lines.append(f"| {stage} | {n['functional_candidate']} | {n['contextual_optional']} |")
    lines.extend([
        "",
        "**Неравномерность тематического каталога не исправляется навязыванием "
        "всех его слов.** Избранные опоры ещё должны быть сверены с задачами и "
        "снижены, если одновременное предъявление нескольких незнакомых слов "
        "делает языковой контраст недоступным A0.",
        "",
        "**Раннее появление отдельных знакомых форм допускается** до основного "
        "горизонта тематической группы: например, ich/du и verstehen нужны "
        "раньше, чем развёрнутые темы «человек» и «учёба». Это уточнение "
        "языковых предпосылок, а не выбор сеттинга.",
        "",
        "**Возможность проверки:** этот реестр покрывает выбранные "
        "минимальные якоря, но не утверждает полный актовый F1, не проверяет "
        "грамматические омонимы и не выдаёт повторение за усвоение.",
        "",
    ])
    return "\n".join(lines)+"\n", sorted(set(errors))



def outcome_stage_report(doc: dict) -> tuple[str, list[str]]:
    """Ensure every independent LO is practised before and after transfer."""
    expected = set(re.findall(r"LO-[RW]\\d{2}", OUTCOMES.read_text(encoding="utf-8")))
    hits = defaultdict(list)
    for item in doc["items"]:
        values = item.get("outcome_candidates", [])
        if len(values) != len(set(values)):
            raise ValueError(f"{item['id']}: duplicate outcome")
        for value in values:
            hits[value].append(item["id"])
    errors = []
    if len(expected) != 13:
        errors.append(f"LO spec contains {len(expected)}, expected 13")
    for code in sorted(expected):
        targets = hits.get(code, [])
        if not any(not x.startswith("P6-") for x in targets):
            errors.append(f"{code}: no earlier learning practice")
        if not any(x.startswith("P6-") for x in targets):
            errors.append(f"{code}: no P6 transfer candidate")
    for code in hits:
        if code not in expected:
            errors.append(f"unknown LO {code}")
    lines = [
        "",
        "## 7. Связь с независимыми результатами (13 LO)",
        "",
        "| LO | Ранее — самостоятельная практика (кандидат) | P6 — перенос (кандидат) |",
        "|---|---|---|",
    ]
    for code in sorted(expected):
        earlier = ", ".join(x for x in hits[code] if not x.startswith("P6-"))
        later = ", ".join(x for x in hits[code] if x.startswith("P6-"))
        lines.append(f"| {code} | {earlier} | {later} |")
    lines.extend([
        "",
        "**В каждом LO предусмотрены два контекста, но это ещё не проведённый "
        "экзамен или эмпирически доказанный перенос.** "
        "Текстовый R требует извлечения необходимого факта; свободный W — "
        "самостоятельной передачи информации без готовой немецкой реплики. "
        "Контрфакт должен менять результат, а не только порядок вариантов.",
        "",
    ])
    return "\n".join(lines) + "\n", sorted(errors)


def main() -> int:
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--write", action="store_true")
    group.add_argument("--check", action="store_true")
    options = parser.parse_args()
    doc = json.loads(INPUT.read_text(encoding="utf-8"))
    mmap, gmap = read_map(), grammar_stages()
    errors = validate(doc, mmap, gmap)
    glossary = json.loads(LEXICAL.read_text(encoding="utf-8"))
    lexical_appendix, lexical_errors = lexical_stage_report(doc, glossary)
    errors.extend(lexical_errors)
    outcome_appendix, outcome_errors = outcome_stage_report(doc)
    errors.extend(outcome_errors)
    if errors:
        print("FAIL: " + "\nFAIL: ".join(errors), file=sys.stderr)
        return 1
    expected = report(doc, mmap, gmap, errors) + lexical_appendix + outcome_appendix
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
    print(f"PASS: 55 M, 34 G, 42 first P, {len(doc['items'])} language units; lexical anchors valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())

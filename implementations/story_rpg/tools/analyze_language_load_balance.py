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
CATALOGUE = DOCS / "LANGUAGE_LEXICON.md"
LEXICAL_CATALOGUE = DOCS / "LANGUAGE_LEXICAL_CATALOG.json"
GRAMMAR_CONTRASTS = DOCS / "LANGUAGE_GRAMMAR_CONTRASTS.json"
F1_SEMANTIC_CASES = DOCS / "LANGUAGE_F1_SEMANTIC_CASES.json"
OUTCOME_FOCUSED_PROBES = DOCS / "LANGUAGE_OUTCOME_FOCUSED_PROBES.json"
REVISIT_SEMANTIC_AUDIT = DOCS / "LANGUAGE_REVISIT_SEMANTIC_AUDIT.json"
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




def grammar_probe_appendix(doc: dict) -> tuple[str, list[str]]:
    """Compare the separate G A/B examples with the main language-unit pairs."""
    grammar = json.loads(GRAMMAR_CONTRASTS.read_text(encoding="utf-8"))
    unit_by_id = {it["id"]: it for it in doc["items"]}
    totals = defaultdict(Counter)
    errors = []
    for it in doc["items"]:
        totals[it["stage"]]["main"] += len(it.get("language_example_checks", []))

    seen = set()
    for probe in grammar.get("items", []):
        gid, unit_id = probe["id"], probe["unit"]
        plan = probe.get("first_r_plan", {})
        required = ("minimal_recognition", "ordered_after", "independent_contact",
                    "productive_followup", "status")
        if any(not isinstance(plan.get(k), str) or not plan[k].strip()
               for k in required):
            errors.append(f"Grammar {gid} lacks explicit first R / prerequisite plan")
        delayed = plan.get("deferred_r_reuse")
        if delayed:
            target = unit_by_id.get(delayed.get("unit"))
            if (target is None or not any(
                q["example_A_de"] == delayed.get("example_A")
                and q["example_B_de"] == delayed.get("example_B")
                for q in target.get("language_example_checks", [])
            )):
                errors.append(f"Grammar {gid} deferred R not anchored to a main pair")
        for extra in probe.get("variant_examples", []):
            if not extra.get("example_A") or not extra.get("example_B") or not extra.get("role"):
                errors.append(f"Grammar {gid} has incomplete retained variant")
        if gid in seen:
            errors.append(f"Grammar probe repeated: {gid}")
        seen.add(gid)
        it = unit_by_id.get(unit_id)
        if it is None or gid not in it["introduce_g"]:
            errors.append(f"Grammar probe {gid} not linked to first G unit {unit_id}")
            continue
        already_main = any(
            pair["example_A_de"] == probe["example_A"]
            and pair["example_B_de"] == probe["example_B"]
            for pair in it.get("language_example_checks", [])
        )
        if not already_main:
            totals[it["stage"]]["extra"] += 1
    expected_g = {gid for it in doc["items"] for gid in it["introduce_g"]}
    if seen != expected_g:
        errors.append(f"Grammar probe IDs differ: {sorted(seen ^ expected_g)}")

    main = sum(totals[s]["main"] for s in STAGES)
    extra = sum(totals[s]["extra"] for s in STAGES)
    matched = len(seen) - extra
    lines = [
        "", "## 8. Грамматические A/B-контрасты вне основных пар: скрытая плотность", "",
        "**Источники:** [LANGUAGE_PRACTICE_UNITS.json](LANGUAGE_PRACTICE_UNITS.json) и [LANGUAGE_GRAMMAR_CONTRASTS.json](LANGUAGE_GRAMMAR_CONTRASTS.json). Это только сопоставление двух независимых наборов проектных примеров, без сценария.",
        "",
        "| Горизонт | Основных A/B-пар | Отдельных G A/B-пар вне основных | Всего кандидатных пар |",
        "|---|---:|---:|---:|",
    ]
    for stage in STAGES:
        a, b = totals[stage]["main"], totals[stage]["extra"]
        lines.append(f"| {stage} | {a} | {b} | {a + b} |")
    lines.extend([
        "",
        f"**Итого:** {main} основных пар и {len(seen)} грамматических G-контраста, из которых {matched} буквально совпадают с основными парами в соответствующих единицах, а {extra} отличаются. Суммарно **{main + extra} кандидатных проверочных пар по (единица, A/B)**, и не являются количеством обязательных игровых контактов.",
        "",
        f"**Планы первого R:** {len(seen)} из {len(seen)} G имеют отдельные условия осмысленного чтения, предпосылки и допустимую продукцию. Это документация, а не проведение тестов.",
        "",
        "**Риск равномерности:** если каждую отличающуюся G-пару позднее предъявлять как самостоятельный обязательный контакт, нагрузка начала программы возрастёт сильнее, чем видно по числу M/G-ID (P0: "
        + str(totals["P0"]["main"] + totals["P0"]["extra"]) + " вместо "
        + str(totals["P0"]["main"]) + " пар; P1: "
        + str(totals["P1"]["main"] + totals["P1"]["extra"]) + " вместо "
        + str(totals["P1"]["main"]) + "). При адаптации нужно объединять совместимые различия или планировать отдельные доступные R-контакты без автоматического добавления задач. Отдельные примеры пока НЕ проверены на A0.",
        "",
        "**Качественные несоответствия:** см. [LANGUAGE_SEMANTIC_ALIGNMENT_AUDIT.md](LANGUAGE_SEMANTIC_ALIGNMENT_AUDIT.md). Число пар отражает ширину проектной проверки, но не измеренную когнитивную нагрузку и не доказательство усвоения.",
        "",
    ])
    return "\n".join(lines) + "\n", sorted(set(errors))


def lexical_stage_report(doc: dict, glossary: dict) -> tuple[str, list[str]]:
    """Validate all selected lexical anchors against the independent catalogue."""
    errors = []
    source_groups = {}
    for line in CATALOGUE.read_text(encoding="utf-8").splitlines():
        cells = [v.strip() for v in line.split("|")[1:-1]]
        if len(cells) != 6 or not cells[0].isdigit():
            continue
        source_groups[int(cells[0])] = {
            "active": re.findall(r"`([^`]+)`", cells[4]),
            "receptive": re.findall(r"`([^`]+)`", cells[5]),
        }
    if len(source_groups) != 29:
        errors.append("LANGUAGE_LEXICON.md must contain 29 groups")
    for group in glossary["groups"]:
        canonical = source_groups.get(group["id"])
        if canonical is None or canonical["active"] != group["active"] or canonical["receptive"] != group["receptive"]:
            errors.append(f"lexical group {group['id']} is out of sync with LANGUAGE_LEXICON.md")

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
    expected = set(re.findall(r"LO-[RW]\d{2}", OUTCOMES.read_text(encoding="utf-8")))
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



def outcome_focused_probe_report(doc: dict) -> tuple[str, list[str]]:
    """Check semantic isolation in independent LO candidates, not test learners."""
    cases = doc.get("independent_outcome_assessments", {}).get("cases", [])
    cases_by_id = {case["lo"]: case for case in cases}
    fixtures = json.loads(OUTCOME_FOCUSED_PROBES.read_text(encoding="utf-8"))
    rows = fixtures.get("items", [])
    errors = []
    focus = defaultdict(list)
    ids = set()
    counts = Counter()
    if len(cases) != 13 or len(cases_by_id) != 13:
        errors.append("Expected 13 unique independent LO candidates")
    for case in cases:
        case_id = case["lo"]
        if not case.get("required_semantic_slots"):
            errors.append(f"{case_id}: missing semantic slots")
        if len(case["required_semantic_slots"]) != len(set(case["required_semantic_slots"])):
            errors.append(f"{case_id}: duplicate semantic slots")
        stim = case["stimulus"]
        if case["kind"] == "reading":
            if stim.get("variant_A_de") == stim.get("variant_B_de"):
                errors.append(f"{case_id}: identical independent reading A/B")
        elif case["kind"] == "free_writing":
            if stim.get("variant_A_facts") == stim.get("variant_B_facts"):
                errors.append(f"{case_id}: identical independent writing A/B")
        else:
            errors.append(f"{case_id}: unexpected assessment kind")
    for probe in rows:
        pid, cid = probe["id"], probe["lo"]
        if pid in ids:
            errors.append(f"Duplicate focused LO probe: {pid}")
        ids.add(pid)
        case = cases_by_id.get(cid)
        if not case or case["kind"] != probe.get("kind"):
            errors.append(f"LO focused probe mismatched case/kind: {pid}")
            continue
        if probe.get("focus_slot") not in case.get("required_semantic_slots", []):
            errors.append(f"LO focused probe unknown critical slot: {pid}")
        if (not probe.get("meaning_A_ru") or not probe.get("meaning_B_ru")
            or probe["meaning_A_ru"] == probe["meaning_B_ru"]):
            errors.append(f"LO focused probe lacks distinct grading meanings: {pid}")
        if probe["kind"] == "reading":
            va, vb = probe.get("variant_A_de"), probe.get("variant_B_de")
        else:
            va, vb = probe.get("variant_A_facts"), probe.get("variant_B_facts")
        if not va or not vb or va == vb:
            errors.append(f"LO focused probe identical/empty A/B: {pid}")
        focus[cid].append(probe["focus_slot"])
        counts[probe["kind"]] += 1
    if (len(rows) != 21 or counts != Counter({"reading": 11, "free_writing": 10})
        or doc["independent_outcome_assessments"].get("focused_probes_count") != len(rows)
        or set(focus) != set(cases_by_id)):
        errors.append("Independent LO focused probe total, type or coverage stale")
    w2, w3, w4, w6 = (cases_by_id.get(k) for k in
                        ("LO-W02", "LO-W03", "LO-W04", "LO-W06"))
    if w2 and (not {"negation_scope", "current_location"} <= set(focus["LO-W02"])):
        errors.append("LO-W02: negation and location are not independently checked")
    if w3 and (w3["stimulus"]["variant_A_facts"].get("time_reference")
               != w3["stimulus"]["variant_B_facts"].get("time_reference")):
        errors.append("LO-W03: modality contrast also changes time")
    if w4 and "preference_intent" not in w4["required_semantic_slots"]:
        errors.append("LO-W04: preference/request intention not explicit")
    if w6 and any("facts" in variant for variant in
                  (w6["stimulus"]["variant_A_facts"],
                   w6["stimulus"]["variant_B_facts"])):
        errors.append("LO-W06: German-form-field values are already prefilled")
    lines = [
        "", "## 9. Независимость смысловых результатов (LP11)", "",
        "Источник: [LANGUAGE_OUTCOME_FOCUSED_PROBES.json]"
        "(LANGUAGE_OUTCOME_FOCUSED_PROBES.json) и "
        "[LANGUAGE_PRACTICE_UNITS.json](LANGUAGE_PRACTICE_UNITS.json). "
        "Проектные варианты языка без использования сюжетных материалов.",
        "",
        f"**13 исходных LO и {len(rows)} дополнительных сфокусированных A/B-контрастов**"
        f" ({counts['reading']} R, {counts['free_writing']} W). "
        "Они дополняют, а не заменяют исходные варианты; "
        "это не количество обязательных экзаменационных задач.",
        "",
        "| LO | Дополнительные пары | Проверяемые изменяемые слоты |",
        "|---|---:|---|",
    ]
    for case in cases:
        cid = case["lo"]
        slots = ", ".join(dict.fromkeys(focus[cid])) or "—"
        lines.append(f"| {cid} | {len(focus[cid])} | {slots} |")
    lines.extend([
        "",
        "**Устранённые проблемы:** отрицание в LO-W02 больше не "
        "выдаётся за проверенное через leer/voll; в LO-W03 отделены "
        "время и область модального отрицания; LO-W06 использует "
        "независимые сведения вместо заранее заполненных немецких полей; "
        "LO-W04 различает предпочтение и текущую просьбу.",
        "",
        "**Граница статической проверки:** валидируются связи, "
        "отличие A/B и форматы данных, но не правильность восприятия "
        "немецкого, не работающий парсер, не попытки учащихся и "
        "не отложенное запоминание. Цену реальной экзаменационной "
        "нагрузки и проходной порог пока не определяем.",
        "",
    ])
    return "\n".join(lines) + "\n", sorted(set(errors))


def revisit_evidence_report(doc: dict) -> tuple[str, list[str]]:
    """Check candidate revisit evidence without equating a linked ID to learning."""
    audit = json.loads(REVISIT_SEMANTIC_AUDIT.read_text(encoding="utf-8"))
    expected = {(it["id"], M) for it in doc["items"] for M in it["revisit_m"]}
    actual = [(entry["unit"], entry["M"]) for entry in audit["entries"]]
    status = Counter(entry.get("status") for entry in audit["entries"])
    errors = []
    if len(actual) != len(expected) or set(actual) != expected:
        errors.append("LP07 evidence audit must match all current revisit pairs")
    if len(set(actual)) != len(actual):
        errors.append("LP07 duplicate evidence record")
    if any(entry["status"] not in (
        "plausible_in_main_AB_candidate_not_user_test",
        "not_demonstrated_by_current_main_AB")
           for entry in audit["entries"]):
        errors.append("LP07 evidence has unrecognised status")
    if any(not entry.get("primary_example_de") or
           not entry.get("evidence_rule_ru") for entry in audit["entries"]):
        errors.append("LP07 evidence missing example or review rule")
    repairs = [entry.get("repair_candidate") for entry in audit["entries"]
               if entry["status"] == "not_demonstrated_by_current_main_AB"]
    if any(not r or not r.get("status") or r.get("obligatory_contact") is not False
           for r in repairs):
        errors.append("LP07 weak revisits must keep non-mandatory repair plan")
    repair_pairs = sum(bool(r and r.get("example_A_de") and r.get("example_B_de"))
                       for r in repairs)
    if (audit["summary"].get("repair_candidates") != len(repairs)
        or audit["summary"].get("repair_pairs") != repair_pairs
        or audit["summary"].get("conditional_or_linked")
            != len(repairs) - repair_pairs):
        errors.append("LP07 candidate repair counts stale")
    catalogue = json.loads(LEXICAL_CATALOGUE.read_text(encoding="utf-8"))
    def tokenize_repair(s: str) -> set[str]:
        return set(re.findall(r"[a-zäöüß]+", s.lower()))
    lemma_forms = {w for entry in catalogue["entries"]
                   for w in tokenize_repair(entry["text"])}
    known_aliases = {a["surface"].lower()
                     for a in catalogue.get("f1_candidate_search", {}).get("aliases", [])}
    used_repair_forms = {w for plan in repairs if plan
                         for key in ("example_A_de", "example_B_de")
                         for w in tokenize_repair(plan.get(key, ""))}
    unresolved_repair_forms = (
        used_repair_forms - lemma_forms - known_aliases
        - {"mia", "tom", "lea", "a", "b"})
    if (audit["summary"].get("repair_proposal_unique_forms")
            != len(used_repair_forms)
        or set(audit["summary"].get("repair_proposal_unlinked_f1_forms", []))
            != unresolved_repair_forms):
        errors.append("LP07 optional repair candidate F1 forms audit stale")
    summary = audit["summary"]
    if (summary.get("all_candidates") != len(actual)
        or summary.get("illustrated_candidates")
            != status["plausible_in_main_AB_candidate_not_user_test"]
        or summary.get("not_demonstrated_by_main_AB")
            != status["not_demonstrated_by_current_main_AB"]):
        errors.append("LP07 evidence summary is stale")
    lines = [
        "", "## 10. Качество возвращений ↻ (LP07)", "",
        "Источник: [LANGUAGE_REVISIT_SEMANTIC_AUDIT.json]"
        "(LANGUAGE_REVISIT_SEMANTIC_AUDIT.json), отдельная от сюжета "
        "содержательная ревизия связей возвращения.",
        "",
        f"**{len(actual)} запланированных связей ↻:** "
        f"{status['plausible_in_main_AB_candidate_not_user_test']} "
        "потенциально иллюстрированы основными A/B, "
        f"{status['not_demonstrated_by_current_main_AB']} "
        "**не демонстрируются** текущими основными A/B. "
        "Ни одна ссылка не доказывает запоминания.",
        "",
        "Поиск связей, не подтверждённых смыслом основной пары, "
        "не равен удалению навыка. Пять ошибочно назначенных связей "
        "перенесены к более подходящим абстрактным единицам; история "
        "переносов сохранена. Оставшиеся случаи требуют самостоятельных "
        "смысловых контрастов, корректного переназначения или "
        "явной пометки факультативного возврата — без выдумывания сюжета.",
        "",
        f"**Для 40 слабых связей** заданы {repair_pairs} необязательных "
        f"языковых A/B-кандидатов и {len(repairs) - repair_pairs} "
        "условных варианта (включая право не переспрашивать при понимании). "
        f"Из {len(used_repair_forms)} форм таких вариантов "
        f"{len(unresolved_repair_forms)} пока без прямой формы/алиаса в F1; "
        "их нельзя объявлять готовыми или прибавлять к обязательной нагрузке.",
        "",
        "**Граница проверки:** статические метки — экспертная гипотеза "
        "по языковым парам, не эксперимент с игроками и не измерение "
        "долговременной памяти. Нельзя выдавать покрытие 55 ID за "
        "55 подтверждённых переносов.",
        "",
    ]
    return "\n".join(lines) + "\n", sorted(set(errors))


def lexical_catalogue_audit(doc: dict) -> list[str]:
    """Validate independent source, candidate RU glosses and F1 references.

    A static check; it does not execute F1 or assess actual language learning.
    """
    errors = []
    source = {}
    for line in CATALOGUE.read_text(encoding="utf-8").splitlines():
        parts = [x.strip() for x in line.split("|")[1:-1]]
        if len(parts) != 6 or not parts[0].isdigit():
            continue
        number = int(parts[0])
        source[number] = {
            "horizon": parts[1].replace("**", ""),
            "domain": parts[2],
            "functions": re.findall(r"M\d{2}", parts[3]),
            "productive": re.findall(r"\x60([^\x60]+)\x60", parts[4]),
            "receptive": re.findall(r"\x60([^\x60]+)\x60", parts[5]),
        }
    data = json.loads(LEXICAL_CATALOGUE.read_text(encoding="utf-8"))
    groups = data.get("groups", [])
    entries = data.get("entries", [])
    indexed = {item.get("text"): item for item in entries}
    expected = defaultdict(list)
    for number, group in source.items():
        for role in ("productive", "receptive"):
            for expression in group[role]:
                expected[expression].append((number, role))
    if len(source) != 29 or len(groups) != 29:
        errors.append("F1 source must contain 29 independent groups")
    for group in groups:
        number = group["group"]
        spec = source.get(number)
        if spec is None or any(group.get(k) != spec[k] for k in (
            "horizon", "domain", "functions", "productive", "receptive"
        )):
            errors.append(f"F1 catalogue group {number} diverges from source")
    if set(indexed) != set(expected) or len(indexed) != len(entries):
        errors.append("F1 catalogue entries mismatch independent source")
    for expression, item in indexed.items():
        refs = [(r["group"], r["role"]) for r in item.get("occurrences", [])]
        if Counter(refs) != Counter(expected.get(expression, [])):
            errors.append(f"F1 occurrence mismatch: {expression}")
        if not item.get("draft_ru_meanings") or not all(
            isinstance(x, str) and x.strip() for x in item["draft_ru_meanings"]
        ):
            errors.append(f"F1 missing Russian gloss: {expression}")
    stats = data.get("validation", {})
    if (stats.get("groups") != len(source)
        or stats.get("unique_strings") != len(expected)
        or stats.get("occurrences") != sum(map(len, expected.values()))):
        errors.append("F1 catalogue summary counts stale")

    def tokenize(value: str) -> list[str]:
        return re.findall(r"[a-zäöüß]+", value.lower())

    vocabulary = {w for entry in entries for w in tokenize(entry["text"])}
    pairs = [pair for item in doc["items"]
             for pair in item.get("language_example_checks", [])]
    used_forms = {w for p in pairs
                  for key in ("example_A_de", "example_B_de")
                  for w in tokenize(p[key])}
    no_exact = used_forms - vocabulary
    aliases = data.get("program_form_alias_candidates", [])
    if {x.get("observed_form") for x in aliases} != no_exact:
        errors.append("F1 form aliases stale versus German A/B corpus")
    if len(pairs) < len(doc["items"]):
        errors.append("Every language unit needs a German A/B contrast")
    audit = data.get("program_german_form_audit", {})
    if (audit.get("unique_example_wordforms") != len(used_forms)
        or audit.get("exact_surface_token_matches") != len(used_forms - no_exact)
        or audit.get("needs_normalization") != len(no_exact)):
        errors.append("F1 German wordform audit stale")

    lookup = data.get("f1_candidate_search", {})
    if not lookup.get("aliases") or not lookup.get("reverse_ru_queries"):
        errors.append("F1 candidate lookup has no morphological/reverse data")
    for item in lookup.get("aliases", []):
        if not item.get("surface") or item.get("lemma") not in indexed:
            errors.append(f"F1 alias target absent: {item}")
    for item in lookup.get("reverse_ru_queries", []):
        if not item.get("query_ru") or not item.get("candidate_de"):
            errors.append(f"F1 empty Russian reverse lookup: {item}")
        for target in item.get("candidate_de", []):
            if target not in indexed:
                errors.append(f"F1 reverse query target absent: {target}")
    for item in lookup.get("ambiguity_groups", []):
        if not item.get("distinction") or not item.get("forms"):
            errors.append(f"F1 incomplete ambiguous meaning group: {item}")
        for target in item.get("forms", []):
            if target not in indexed:
                errors.append(f"F1 ambiguous meaning target absent: {target}")

    # Validate static dictionary meaning contracts independently of UI/parser.
    fixtures = json.loads(F1_SEMANTIC_CASES.read_text(encoding="utf-8"))
    reverse = {q["query_ru"]: q for q in lookup.get("reverse_ru_queries", [])}
    aliases_by_surface = {a["surface"]: a["lemma"] for a in lookup.get("aliases", [])}
    ambiguous = {g["id"]: g for g in lookup.get("ambiguity_groups", [])}
    negative = {q["query_ru"]: q for q in lookup.get("negative_ru_queries", [])}
    for fixture in fixtures["gloss_cases"]:
        meanings = " / ".join(indexed.get(fixture["entry"], {}).get("draft_ru_meanings", [])).lower()
        if any(fragment.lower() not in meanings
               for fragment in fixture["required_ru_fragments"]):
            errors.append(f"F1 gloss semantic check failed: {fixture['id']}")
    for fixture in fixtures["reverse_cases"]:
        query = reverse.get(fixture["query_ru"], {})
        candidates = set(query.get("candidate_de", []))
        if (not set(fixture["required_candidates"]) <= candidates
            or set(fixture.get("forbidden_candidates", [])) & candidates):
            errors.append(f"F1 reverse semantic check failed: {fixture['id']}")
    for fixture in fixtures["alias_cases"]:
        if aliases_by_surface.get(fixture["surface"]) != fixture["lemma"]:
            errors.append(f"F1 morphology semantic check failed: {fixture['id']}")
    for fixture in fixtures["negative_reverse_cases"]:
        query = reverse.get(fixture["query_ru"], {})
        if (set(fixture["forbidden_exact_candidates"])
                & set(query.get("candidate_de", []))
            or fixture["query_ru"] not in negative):
            errors.append(f"F1 negative semantic check failed: {fixture['id']}")
    for fixture in fixtures["ambiguity_cases"]:
        meaning = ambiguous.get(fixture["group_id"], {}).get("distinction", "").lower()
        if any(fragment.lower() not in meaning
               for fragment in fixture["required_distinction_fragments"]):
            errors.append(f"F1 ambiguity semantic check failed: {fixture['id']}")
    counts = lookup.get("validation", {})
    for label, value in (("alias_links", len(aliases_by_surface)),
                         ("reverse_queries", len(reverse)),
                         ("ambiguity_groups", len(ambiguous)),
                         ("negative_ru_queries", len(negative))):
        if counts.get(label) != value:
            errors.append(f"F1 static lookup counts stale: {label}")

    cases = doc.get("independent_outcome_assessments", {}).get("cases", [])
    if (len(cases) != 13
        or sum(x.get("kind") == "reading" for x in cases) != 6
        or sum(x.get("kind") == "free_writing" for x in cases) != 7):
        errors.append("LO cases must include 6 R and 7 independent W")
    reading_forms = {w for case in cases if case.get("kind") == "reading"
                     for key in ("variant_A_de", "variant_B_de")
                     for w in tokenize(case["stimulus"][key])}
    missing_reading = reading_forms - vocabulary
    ra = data.get("independent_assessment_receptive_forms", {})
    if (ra.get("forms") != len(reading_forms)
        or ra.get("unmatched") != len(missing_reading)
        or {x.get("form") for x in ra.get("unmatched_forms", [])}
            != missing_reading):
        errors.append("F1 independent reading wordforms audit stale")
    productive = sum(len(x.get("independent_production_checks", []))
                     for x in doc["items"])
    if productive != 42:
        errors.append(f"Free-writing first P cases: {productive} != 42")

    grammar = json.loads(GRAMMAR_CONTRASTS.read_text(encoding="utf-8"))
    examples = grammar.get("items", [])
    if len(examples) != 34 or len({x.get("id") for x in examples}) != 34:
        errors.append("Expected 34 unique independent grammar examples")
    form_to_lemma = {x["surface"].lower(): x["lemma"]
                     for x in lookup.get("aliases", []) if x.get("surface")}
    grammar_forms = {w for example in examples
                     for key in ("example_A", "example_B")
                     for w in tokenize(example[key])}
    unresolved = grammar_forms - vocabulary - set(form_to_lemma) - {"mia"}
    if unresolved:
        errors.append("Grammar examples contain forms missing from F1: "
                      + ", ".join(sorted(unresolved)))
    form_audit = data.get("grammar_form_audit", {})
    if (form_audit.get("unique_example_wordforms") != len(grammar_forms)
        or form_audit.get("exact_surface_token_matches")
            != len(grammar_forms & vocabulary)
        or form_audit.get("unresolved_forms") != len(unresolved)):
        errors.append("F1 grammar wordform audit stale")
    for example in examples:
        if not any(item["id"] == example.get("unit")
                   and example.get("id") in item.get("introduce_g", [])
                   for item in doc["items"]):
            errors.append(f"Grammar example not aligned with LU: {example.get('id')}")
    return sorted(set(errors))


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
    outcome_focused_appendix, outcome_focused_errors = outcome_focused_probe_report(doc)
    errors.extend(outcome_focused_errors)
    revisit_appendix, revisit_errors = revisit_evidence_report(doc)
    errors.extend(revisit_errors)
    grammar_appendix, grammar_errors = grammar_probe_appendix(doc)
    errors.extend(grammar_errors)
    errors.extend(lexical_catalogue_audit(doc))
    if errors:
        print("FAIL: " + "\nFAIL: ".join(errors), file=sys.stderr)
        return 1
    expected = report(doc, mmap, gmap, errors) + lexical_appendix + outcome_appendix + grammar_appendix + outcome_focused_appendix + revisit_appendix
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
    print(f"PASS: 55 M, 34 G, 42 first P, {len(doc['items'])} language units; lexical anchors, Russian glosses, and F1 candidate references valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())

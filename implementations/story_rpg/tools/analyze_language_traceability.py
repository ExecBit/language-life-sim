#!/usr/bin/env python3
"""Cross-check the manually reviewed M/G/LO map against mandatory scene events.

Manual annotations identify candidate semantic evidence, not language mastery,
parser coverage or gameplay-tested understanding. Never infer coverage merely
from the appearance of a word or from planned calendar day labels.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

from scene_corpus import DOCS, scene_data
from analyze_semantic_contacts import semantic_data

SOURCE = DOCS / "ACT_LANGUAGE_TRACEABILITY.json"
REPORT = DOCS / "ACT_LANGUAGE_TRACEABILITY_REPORT.md"
DESIGN = DOCS / "LANGUAGE_DESIGN.md"
MAP = DOCS / "LANGUAGE_MAP.md"
OUTCOMES = DOCS / "LEARNING_OUTCOMES.md"
KINDS = {"M": 55, "G": 34, "LO": 13}
STATES = ("candidate", "partial", "gap")
STATE_LABELS = {
    "candidate": "Кандидат осмысленной практики",
    "partial": "Частичное покрытие",
    "gap": "Пробел",
}
PREFIX_LABELS = {
    "M": "Коммуникативные функции M01–M55",
    "G": "Грамматические блоки G01–G34",
    "LO": "Результаты обучения LO-R01–R06 / LO-W01–W07",
}


def _labels() -> tuple[dict[str, str], dict[str, str]]:
    titles = {}
    for match in re.finditer(r"^\| (M\d\d|G\d\d) \| ([^|]+) \|", DESIGN.read_text(encoding="utf-8"), re.M):
        titles[match.group(1)] = match.group(2).strip()
    for match in re.finditer(r"^\| \*\*(LO-[RW]\d\d)\*\* \| ([^|]+) \|",
                             OUTCOMES.read_text(encoding="utf-8"), re.M):
        titles[match.group(1)] = match.group(2).strip()
    core = {}
    for match in re.finditer(r"^\| (M\d\d) \| \*\*(R|P)\*\* \|",
                             MAP.read_text(encoding="utf-8"), re.M):
        core[match.group(1)] = match.group(2)
    expected = ({f"M{i:02}" for i in range(1, 56)}
                | {f"G{i:02}" for i in range(1, 35)}
                | {f"LO-R{i:02}" for i in range(1, 7)}
                | {f"LO-W{i:02}" for i in range(1, 8)})
    if set(titles) != expected or set(core) != {f"M{i:02}" for i in range(1, 56)}:
        raise ValueError("M/G/LO source definitions or labels have changed; review mapping")
    return titles, core


def traceability_data() -> dict:
    corpus = scene_data()
    manual = json.loads(SOURCE.read_text(encoding="utf-8"))
    names, core = _labels()
    annotations = semantic_data()
    annotated = {a["event_id"]: a for a in annotations["annotations"]}
    events = {}
    for day in corpus["days"]:
        for scene in day["scenes"]:
            for mode in ("r", "p"):
                for event in scene[mode]:
                    if event["id"] in events:
                        raise ValueError(f"Duplicate scene event {event['id']}")
                    events[event["id"]] = {
                        "day": day["day"], "scene": scene["id"],
                        "required": event["required"] and scene["required"],
                        "mode": mode.upper(), "content": event.get("de", event.get("example", "")),
                    }
    expected = set(names)
    encountered = set()
    enriched = []
    for item in manual["items"]:
        target = item["id"]
        if target not in expected or target in encountered:
            raise ValueError(f"Missing or duplicate language target {target}")
        encountered.add(target)
        if item["title"] != names[target]:
            raise ValueError(f"Outdated title for {target}, compare LANGUAGE_DESIGN/LO")
        kind = "LO" if target.startswith("LO") else target[0]
        if item["status"] not in STATES:
            raise ValueError(f"Bad target status {target}")
        if not item["note"].strip():
            raise ValueError(f"Missing rationale {target}")
        if kind == "M":
            if item.get("core") != core[target]:
                raise ValueError(f"Outdated R/P core of {target}")
            if core[target] == "R" and item["p"]:
                raise ValueError(f"R-only target must not require P: {target}")
        for field, mode in (("r", "R"), ("p", "P"), ("return", None)):
            for eid in item[field]:
                if eid not in events:
                    raise ValueError(f"Unknown {field} evidence {target}: {eid}")
                ref = events[eid]
                if not ref["required"]:
                    raise ValueError(f"Optional event cannot prove guaranteed exposure {target}: {eid}")
                if mode and ref["mode"] != mode:
                    raise ValueError(f"Wrong event mode {target}: {eid}")
        if item["status"] == "gap" and item["p"]:
            raise ValueError(f"Review gap with claimed productive evidence: {target}")
        first = item["r"] + item["p"]
        if item["return"] and first:
            start = min(events[x]["day"] for x in first)
            if any(events[x]["day"] <= start for x in item["return"]):
                raise ValueError(f"Return must occur after an initial event: {target}")
        enriched.append({
            **item, "kind": kind,
            "r_days": sorted({events[eid]["day"] for eid in item["r"]}),
            "p_days": sorted({events[eid]["day"] for eid in item["p"]}),
            "return_days": sorted({events[eid]["day"] for eid in item["return"]}),
            "needed_R_evidence": sum(annotated.get(eid, {}).get("mode") == "needed_R"
                                     for eid in item["r"]),
            "unreviewed_R_evidence": sum(eid not in annotated for eid in item["r"]),
            "P_evidence_reviewed": sum(annotated.get(eid, {}).get("mode") == "needed_P"
                                       for eid in item["p"]),
        })
    if encountered != expected:
        raise ValueError("Every M01–M55, G01–G34 and LO-R/W must have exactly one row")
    tally = {kind: dict(Counter(i["status"] for i in enriched if i["kind"] == kind))
             for kind in KINDS}
    for kind in KINDS:
        tally[kind] = {state: tally[kind].get(state, 0) for state in STATES}
        if sum(tally[kind].values()) != KINDS[kind]:
            raise ValueError("Target count changed")
    return {
        "status": "manual_candidate_crosswalk_not_learner_outcomes",
        "counts": tally,
        "total": len(enriched),
        "items": enriched,
        "notes": manual["method"],
        "gaps": [i["id"] for i in enriched if i["status"] == "gap"],
    }


def render_report(data: dict) -> str:
    lines = [
        "# Сквозная проверка языковой программы M## / G## / LO##",
        "",
        "**Статус: ручной аудит проектного обязательного корпуса.** Это не данные игрока, "
        "не доказательство понимания, не покрытие грамматических форм парсером. "
        "[Редактируемая сверка](ACT_LANGUAGE_TRACEABILITY.json), "
        "[диалоговый корпус](ACT_DIALOGUE_SITUATIONS.json), "
        "[смысловые аннотации](ACT_SEMANTIC_CONTACT_ANNOTATIONS.json), "
        "[план программы](LANGUAGE_PROGRAM_ROADMAP.md).",
        "",
        "## 1. Метод и границы",
        "",
        "- **Кандидат:** найден хотя бы один мотивированный обязательный R/P-контакт, "
        "**не** подтверждённая компетенция или достаточное число повторов.",
        "- **Частично:** есть отдельная встреча или пример, но существенное "
        "различие, жанр, самостоятельность или перенос не подтверждены.",
        "- **Пробел:** гарантированная практика требуемого смысла отсутствует "
        "либо не обнаружена в текущих 37 обязательных сценах.",
        "- **R** — ссылка на обязательную реплику/запись, **P** — на обязательную "
        "возможность самостоятельного ответа; P-пример не whitelist. "
        "Таблицы не засчитывают необязательные эпизоды как гарантированное покрытие.",
        "- **Возврат ↻** — вручную указанная другая сцена, не измерение памяти. "
        "Отсутствие ↻ означает, что явный перенос **не проверен**, "
        "а не что слово/функция больше не встречается.",
        "- **Грамматика G##:** анализируется смысловая доступность, "
        "без требования правильных окончаний и без автоматической "
        "привязки к слову в скрипте.",
        "",
        "## 2. Обзор",
        "",
        "| Ось | Всего | Кандидаты | Частично | Пробелы |",
        "|---|---:|---:|---:|---:|",
    ]
    for kind in KINDS:
        n = data["counts"][kind]
        lines.append(f"| {PREFIX_LABELS[kind]} | {sum(n.values())} | "
                     f"{n['candidate']} | {n['partial']} | {n['gap']} |")
    lines += [
        "",
        "## 3. Полный ручной реестр",
        "",
        "В столбцах приведены ID конкретных событий из обязательных сцен. "
        "Даже после разметки **игровые ветвления, F1, ошибка парсера и понимание "
        "на A0 не проверены**.",
        "",
    ]
    for kind in KINDS:
        lines += [
            f"### {PREFIX_LABELS[kind]}",
            "",
            "| ID | Цель | Ядро | Статус | R-свидетельства | P-свидетельства | Возврат ↻ | Ограничение |",
            "|---|---|---|---|---|---|---|---|",
        ]
        for item in (i for i in data["items"] if i["kind"] == kind):
            form = item.get("core", "—")
            evidence = lambda field: ", ".join(f"\`{x}\`" for x in item[field]) or "—"
            lines.append(
                f"| {item['id']} | {item['title']} | {form} | "
                f"{STATE_LABELS[item['status']]} | "
                f"{evidence('r')} | {evidence('p')} | {evidence('return')} | "
                f"{item['note']} |"
            )
        lines.append("")
    lines += [
        "## 4. Подтверждённые пробелы проектной трассировки",
        "",
        "Пробел означает отсутствие **подходящей обязательной смысловой практики** "
        "в текущем авторском корпусе; не обязует создавать отдельный квест на каждую строку.",
        "",
    ]
    for kind in KINDS:
        lines.append(f"### {PREFIX_LABELS[kind]}")
        lines.append("")
        gaps = [i for i in data["items"] if i["kind"] == kind and i["status"] == "gap"]
        if not gaps:
            lines.append("Отдельных статусов «пробел» нет, но частичное покрытие "
                         "не превращается в успешный результат экзамена.")
        for item in gaps:
            lines.append(f"- **{item['id']} — {item['title']}:** {item['note']}")
        lines.append("")
    lines += [
        "## 5. Прежде чем считать покрытие достаточным",
        "",
        "1. **M05:** обязательный P-контакт \`D15-S2-P2\` существует, "
        "но сценарий принуждает к фразе «Ich verstehe nicht» без реального "
        "непонимания. На D01 просьба повторить стала факультативной. "
        "Следовательно, отсутствие M05 в обязательном корпусе — неверный "
        "вывод, **качество самостоятельной практики M05 остаётся проблемой**.",
        "2. **M08/G02/LO-R01:** не подменять формальное \`Sie\` местоимением "
        "третьего лица \`sie\`. **M55/G33** — отдельные рецептивные "
        "формулы \`hätte gern/könnte ich\`, обычного \`bitte\` недостаточно.",
        "3. **M25, M34, M36, G21, G30:** не считать цели закрытыми "
        "по техническим разговорам или факультативным эпизодам. "
        "Нужны естественные причины понимать/выражать смысл, "
        "не механические упражнения и не новые дни без основания.",
        "4. **G15/G16/G18/G22/G24/G26/G34:** "
        "наличие формы в тексте ещё не означает, что игрок различит "
        "адресата, объект, перемещение, запрет/необязательность, "
        "ответ на отрицание и сопоставление.",
        "5. **LO-R04/LO-R05/LO-W04/LO-W06:** проверить бытовые "
        "тексты, личную информацию, реальные жанры и поля простой формы. "
        "Рабочая форма Sensor/Zeit/Status полезна, но не подтверждает "
        "умение заполнять Name/Adresse.",
        "6. **Повторение и перенос:** где выставлен кандидат, "
        "проверить не только первое R и P, но и независимую задачу "
        "после временного промежутка. Отдельно проверять допустимые "
        "неидеальные немецкие ответы и контрфакты.",
        "",
        "## 6. Следующий шаг",
        "",
        "Сверить приоритеты пробелов с ядром M/G и 13 LO, "
        "исправлять лишь **значимые** недостатки обязательного общения. "
        "Далее — проверить доступность с A0 и работоспособность F1/парсера "
        "на реальных вариантах, затем предложить независимые LO-проверки. "
        "**Количество дней не выводится из числа M/G/LO.**",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--check", action="store_true")
    args = p.parse_args()
    report = render_report(traceability_data())
    if args.check:
        if not REPORT.exists() or REPORT.read_text(encoding="utf-8") != report:
            print("Language traceability report is stale.", file=sys.stderr)
            return 1
        print("Language traceability report is current.")
        return 0
    if not REPORT.exists() or REPORT.read_text(encoding="utf-8") != report:
        REPORT.write_text(report, encoding="utf-8")
    print("Language traceability report generated.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

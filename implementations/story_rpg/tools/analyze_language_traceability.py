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
        if target.startswith("LO-R") and item["p"]:
            raise ValueError(f"Receptive LO must be supported by receptive evidence: {target}")
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
        "**Статус:** ручная трассировка обязательных авторских сцен. "
        "Кандидат не означает усвоение или подтверждённую работу в игре. "
        "[Исходная разметка](ACT_LANGUAGE_TRACEABILITY.json); "
        "[сценовый корпус](ACT_DIALOGUE_SITUATIONS.json); "
        "[семантический аудит](ACT_SEMANTIC_CONTACT_REPORT.md).",
        "",
        "## 1. Сводка",
        "",
        "| Направление | Всего | Кандидаты | Частично | Пробелы |",
        "|---|---:|---:|---:|---:|",
    ]
    for kind in ("M", "G", "LO"):
        c = data["counts"][kind]
        lines.append(f"| {PREFIX_LABELS[kind]} | {sum(c.values())} | "
                     f"{c['candidate']} | {c['partial']} | {c['gap']} |")
    lines += [
        "",
        "## 2. Все 102 проверяемые позиции",
        "",
        "**R/P** — ID обязательных сценовых событий, а не проверка владения. "
        "**↻** — возможная новая ситуация для того же навыка, не доказательство памяти. "
        "Появление слова не гарантирует, что его смысл необходим для действия.",
        "",
    ]
    for kind in ("M", "G", "LO"):
        lines += [
            f"### {PREFIX_LABELS[kind]}",
            "",
            "| ID | Цель | Ядро | Статус | Обязательный R | Обязательный P | Возврат ↻ | Ограничение |",
            "|---|---|---|---|---|---|---|---|",
        ]
        for item in data["items"]:
            if item["kind"] != kind:
                continue
            def evs(field: str) -> str:
                return ", ".join(f"`{eid}`" for eid in item[field]) or "—"
            lines.append(
                f"| {item['id']} | {item['title']} | {item.get('core', '—')} | "
                f"{STATE_LABELS[item['status']]} | {evs('r')} | "
                f"{evs('p')} | {evs('return')} | {item['note']} |"
            )
        lines.append("")
    lines += [
        "## 3. Пробелы обязательной программы",
        "",
        "Пробел означает отсутствие подходящей **обязательной смысловой практики** "
        "в проектных сценах, а не необходимость добавлять отдельный квест.",
        "",
    ]
    for kind in ("M", "G", "LO"):
        lines.append(f"### {PREFIX_LABELS[kind]}")
        lines.append("")
        missing = [x for x in data["items"]
                   if x["kind"] == kind and x["status"] == "gap"]
        if not missing:
            lines.append("Отдельных пробелов не отмечено; частичные позиции всё ещё требуют проверки.")
        for item in missing:
            lines.append(f"- **{item['id']} — {item['title']}:** {item['note']}")
        lines.append("")
    lines += [
        "## 4. Приоритетный следующий проход",
        "",
        "1. **M05:** на D15 есть обязательный `D15-S2-P2` с `Ich verstehe nicht`, "
        "однако непонимание предписано сценарием. На D01 просьба повторить "
        "теперь необязательна. Нужно дать навыку естественную возможность, "
        "не заставляя игрока изображать непонимание.",
        "2. **M08/G02/LO-R01** требуют контраста `du/Sie`, а **M55/G33** — "
        "рецептивной вежливой формулы `hätte gern` / `könnte ich`. "
        "`sie` о третьем лице и обычное `bitte` не заменяют эти цели.",
        "3. **M02/M25/M34/M36, G21/G30:** нет подходящего обязательного "
        "смысла. Возможны естественные разговоры или записи в существующих "
        "ситуациях; не назначать шесть новых учебных дней.",
        "4. **G15/G16/G18/G22/G24/G26/G34:** формы частично присутствуют, "
        "но самостоятельное различение объекта, получателя, направления, "
        "запрета/необязательности и сопоставления не подтверждено.",
        "5. **LO-R04/LO-R05/LO-W04/LO-W06:** дополнительно проверить "
        "бытовые жанры, личные данные и личную коммуникацию; "
        "`Sensor/Zeit/Status` не подтверждает `Name/Adresse`.",
        "6. **Кандидаты:** нужен поздний значимый возврат с другой целью, "
        "проверка альтернативных ответов и возможность ошибиться по смыслу. "
        "Из этих таблиц нельзя вывести, сколько дней требуется для A1.",
        "",
    ]
    return "\n".join(lines) + "\n"


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

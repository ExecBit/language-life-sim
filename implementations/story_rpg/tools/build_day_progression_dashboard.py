#!/usr/bin/env python3
"""Rebuild the interactive, standalone HTML from the canonical Markdown plan.

Run from the repository root:
    python implementations/story_rpg/tools/build_day_progression_dashboard.py
    python implementations/story_rpg/tools/build_day_progression_dashboard.py --check

All daily story goals, first M## contacts, R/P contracts, meanings, heatmap
repetitions and the complexity curve come from ACT_DAY_PROGRESSION_MAP.md.
M## names come from LANGUAGE_DESIGN.md and skill categories from LANGUAGE_MAP.md.
Vocabulary growth and lexical recurrence come from the scene contract corpus,
reviewed normalization and explicit provisional word-role candidate list. D22 exam never contributes to the cumulative vocabulary.
Only Python's standard library is needed; no LLM, browser or network.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

from scene_corpus import scene_data
from analyze_lexical_recurrence import recurrence_data
from analyze_semantic_contacts import semantic_data
from analyze_a0_readiness import a0_readiness_data
from analyze_language_traceability import traceability_data

DOCS = Path(__file__).resolve().parents[1] / "docs"
DAY_MAP = DOCS / "ACT_DAY_PROGRESSION_MAP.md"
LANGUAGE_DESIGN = DOCS / "LANGUAGE_DESIGN.md"
LANGUAGE_MAP = DOCS / "LANGUAGE_MAP.md"
DASHBOARD = DOCS / "ACT_DAY_PROGRESSION_DASHBOARD.html"
CORPUS = DOCS / "ACT_DIALOGUE_SITUATIONS.json"
NORMALIZATION = DOCS / "ACT_VOCAB_NORMALIZATION.json"
LEXICON = DOCS / "LANGUAGE_LEXICON.md"
LANGUAGE_CATALOG = DOCS / "LANGUAGE_LEXICAL_CATALOG.json"
WORD_PATTERN = re.compile(r"[^\W_]+", re.UNICODE)

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
    # JSON-compatible numeric formatting: integer points are serialized as 1,
    # not 1.0. The checked-in HTML also uses JavaScript number formatting.
    return [int(value) if value.is_integer() else value for value in points]

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
            elif marker not in ("●", "·"):
                raise ValueError("Unknown heatmap marker " + marker)
    for day in days:
        for group in day["reuse"]:
            if group not in introduced and not any(first[id] == group for id in day["new"]):
                raise ValueError(f"Reuse of {group} before introduction")
        introduced.update(first[id] for id in day["new"])


def vocab_data() -> dict:
    """Calculate cumulative R vocabulary and the R+P-sample vocabulary by day.

    R = German actually present in authored NPC/document samples.
    P = the author's example wording for required FREE-TEXT responses, not actual
    player input. Forms are normalized against a reviewed, exhaustive mapping.
    Proper names and sensor identifiers are excluded from vocabulary only;
    they still count in raw text volume. D22 is an exam and is not counted.
    """
    corpus = scene_data()
    norm = corpus["normalization"]
    mapping = norm["form_to_lexeme"]
    excluded = set(norm["excluded"])
    seen_r_lexemes: set[str] = set()
    seen_r_forms: set[str] = set()
    seen_all_lexemes: set[str] = set()
    cumulative_r_words = 0
    series: list[dict] = []

    def lexemes(text: str) -> tuple[list[str], list[str], int]:
        forms = [word.lower() for word in WORD_PATTERN.findall(text)]
        unknown = set(forms).difference(mapping, excluded)
        if unknown:
            raise ValueError(
                "Unreviewed German word forms in dialogue corpus; update "
                "ACT_VOCAB_NORMALIZATION.json: " + ", ".join(sorted(unknown))
            )
        useful = [form for form in forms if form not in excluded]
        return useful, [mapping[form] for form in useful], len(forms)

    for day in corpus["days"]:
        number = day["day"]
        if number != len(series) + 1:
            raise ValueError("Corpus days must be consecutive.")
        if number >= corpus["exam_day"]:
            raise ValueError("Exam day must not contribute to practice vocabulary.")
        r_forms: list[str] = []
        r_lemmas: list[str] = []
        r_words = 0
        for event in day["r"]:
            if not event["required"]:
                continue
            forms, lemmas, words = lexemes(event["de"])
            r_forms.extend(forms)
            r_lemmas.extend(lemmas)
            r_words += words

        # Vocabulary 'new today' means first appearance across any earlier day;
        # duplicate uses in the same day count as repeated tokens, not new types.
        cumulative_r_words += r_words
        new_r_lemmas = set(r_lemmas) - seen_r_lexemes
        new_r_forms = set(r_forms) - seen_r_forms
        seen_r_lexemes.update(r_lemmas)
        seen_r_forms.update(r_forms)
        new_all = set(r_lemmas) - seen_all_lexemes
        seen_all_lexemes.update(r_lemmas)
        p_words = 0
        p_lemmas: list[str] = []
        for event in day["p"]:
            if event["required"] and event["kind"] == "dialog":
                _, lemmas, count = lexemes(event["example"])
                p_words += count
                p_lemmas.extend(lemmas)
        p_only_new = set(p_lemmas) - seen_all_lexemes
        seen_all_lexemes.update(p_lemmas)
        series.append({
            "day": number,
            "r_words": r_words,
            "r_cumulative_words": cumulative_r_words,
            "p_example_words": p_words,
            "r_lexical_words": len(r_lemmas),
            "r_repeated_words": len(r_lemmas) - len(new_r_lemmas),
            "r_new_lexemes": len(new_r_lemmas),
            "r_cumulative_lexemes": len(seen_r_lexemes),
            "r_new_forms": len(new_r_forms),
            "r_cumulative_forms": len(seen_r_forms),
            "p_only_new_lexemes": len(p_only_new),
            "sample_cumulative_lexemes": len(seen_all_lexemes),
            "mandatory_scenes": sum(1 for s in day["scenes"] if s["required"]),
            "optional_scenes": sum(1 for s in day["scenes"] if not s["required"]),
        })
    return {
        "status": "expanded_authored_situations_not_player_telemetry",
        "exam_day": corpus["exam_day"],
        "days": series,
        "excluded": sorted(excluded),
    }



def dialogue_load_data() -> dict:
    """Volume of guaranteed scene text and optional additions, by day and topic.

    R counts all displayed German words in guaranteed scenes. Output example
    words are only an author sample; P components are thematic semantic tags,
    not unique utterances or actual user text.
    """
    corpus = scene_data()
    form_to_group = corpus["normalization"]["primary_group_for_form"]
    names: dict[str, str] = {}
    for line in LEXICON.read_text(encoding="utf-8").splitlines():
        match = re.match(r"^\|\s*(\d{1,2})\s*\|", line)
        if match:
            fields = [x.strip() for x in line.split("|")[1:-1]]
            if len(fields) >= 3:
                names[f"{int(match.group(1)):02}"] = fields[2]
    if len(names) != 29:
        raise ValueError("Expected 29 catalog groups")
    topics = {key: {"id": key, "name": name, "r": 0, "p": 0,
                    "r_optional": 0, "p_optional": 0,
                    "by_day": [{"r": 0, "p": 0, "r_optional": 0, "p_optional": 0}
                               for _ in corpus["days"]]}
              for key, name in sorted(names.items())}
    days = []
    for day in corpus["days"]:
        point = {"day": day["day"], "r_words": 0, "r_marked": 0,
                 "r_optional_words": 0, "p_example_words": 0,
                 "p_optional_examples": 0, "p_required": 0, "p_optional": 0,
                 "p_slots": 0}
        for event in day["r"]:
            forms = [word.lower() for word in WORD_PATTERN.findall(event["de"])]
            mode = "r" if event["required"] else "r_optional"
            point["r_words" if event["required"] else "r_optional_words"] += len(forms)
            for form in forms:
                group = form_to_group.get(form)
                if group:
                    topics[group][mode] += 1
                    topics[group]["by_day"][day["day"] - 1][mode] += 1
                    if event["required"]:
                        point["r_marked"] += 1
        for event in day["p"]:
            point["p_required" if event["required"] else "p_optional"] += 1
            if event["kind"] == "dialog":
                point["p_example_words" if event["required"] else "p_optional_examples"] += len(
                    WORD_PATTERN.findall(event["example"])
                )
            for slot in event["slots"]:
                if event["required"]:
                    point["p_slots"] += 1
                mode = "p" if event["required"] else "p_optional"
                topics[slot["group"]][mode] += 1
                topics[slot["group"]]["by_day"][day["day"] - 1][mode] += 1
        days.append(point)
    return {"status": "authored_scene_contracts", "days": days,
            "groups": list(topics.values())}


def language_program_data() -> dict:
    """Independent language-program lexicon, never inferred from ACT scenes.

    P0-P5 are language horizons, not story days. Entries are expressions/forms,
    not a count of learned lemmas; F1 and actual learner performance are untested.
    """
    catalogue = json.loads(LANGUAGE_CATALOG.read_text(encoding="utf-8"))
    source_groups = catalogue["groups"]
    entries = catalogue["entries"]
    band_order = (
        "P0", "P1", "P2a", "P2b", "P2c",
        "P3a", "P3b", "P3c", "P4a", "P4b", "P4c", "P5"
    )
    track_order = (
        "active_core", "receptive_core", "productive_choice", "contextual"
    )
    bands = [
        {
            "band": band,
            "tracks": {
                track: sum(
                    item["learning_scope"]["focus_band"] == band
                    and item["learning_scope"]["track"] == track
                    for item in entries
                )
                for track in track_order
            },
        }
        for band in band_order
    ]
    tracks = {
        track: sum(
            item["learning_scope"]["track"] == track for item in entries
        )
        for track in track_order
    }
    summary = catalogue["curriculum_summary"]
    if len(entries) != summary["entries_total"] or tracks != summary["tracks"]:
        raise ValueError("Independent lexical catalogue totals are inconsistent")
    if not all(
        summary["focus_band_counts"][b["band"]][track] == b["tracks"][track]
        for b in bands for track in ("active_core", "receptive_core")
    ):
        raise ValueError("Independent lexical program focus bands are stale")
    topics = [
        {
            "id": group["group"],
            "name": group["domain"],
            "horizon": group["horizon"],
            "productive": len(group["productive"]),
            "receptive": len(group["receptive"]),
        }
        for group in source_groups
    ]
    vocabulary = [
        {
            "text": item["text"],
            "ru": " / ".join(item["draft_ru_meanings"]),
            "track": item["learning_scope"]["track"],
            "band": item["learning_scope"]["focus_band"],
            "groups": sorted({
                usage["group"] for usage in item["occurrences"]
            }),
        }
        for item in entries
    ]
    contracts = [
        {
            "id": item["id"],
            "goal": item["goal"],
            "horizon": item["horizon"],
            "outcomes": item["learning_outcome_refs"],
            "acceptance": item["semantic_acceptance_rule_ru"],
        }
        for item in catalogue["lexical_competency_contracts"]
    ]
    return {
        "summary": {
            "expressions": len(entries),
            "occurrences": catalogue["validation"]["occurrences"],
            "previous": summary["originals"],
            "added": summary["additions"],
            "groups": len(source_groups),
            "contracts": len(contracts),
            "outcomes": summary["independent_outcomes_lexically_traced"],
            "tracks": tracks,
        },
        "bands": bands,
        "topics": topics,
        "vocabulary": vocabulary,
        "contracts": contracts,
    }


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
            "reuse": ", ".join(day["reuse"]) or "Нет запланированных возвращений",
            "risk": contracts[day["day"]]["risk"],
        }
        for day in days
    ]
    payload = {
        "days": days, "groups": GROUPS, "skillNames": names,
        "audit": audit, "first": first, "vocab": vocab_data(),
        "load": dialogue_load_data(), "recycling": recurrence_data(),
        "semantic": semantic_data(),
        "a0_readiness": a0_readiness_data(),
        "traceability": traceability_data(),
        "language_program": language_program_data(),
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
            diff_at = next(
                (i for i, (a, b) in enumerate(zip(old, fresh)) if a != b),
                min(len(old), len(fresh))
            )
            print(
                "Dashboard is stale; first difference at character "
                + str(diff_at)
                + "; tracked=" + repr(old[max(0, diff_at - 80):diff_at + 170])
                + "; generated=" + repr(fresh[max(0, diff_at - 80):diff_at + 170]),
                file=sys.stderr
            )
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

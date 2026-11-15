#!/usr/bin/env python3
"""Audit *authored* semantic necessity in story dialogue; no learner-memory inference.

Only explicit hand-reviewed event annotations count as semantic candidates.
Unannotated R is unknown (not incidental); P is planned communicative intent,
not an obligation to use a specific lemma from the example reply.
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

from scene_corpus import DOCS, WORD, scene_data

ANNOTATIONS = DOCS / "ACT_SEMANTIC_CONTACT_ANNOTATIONS.json"
REPORT = DOCS / "ACT_SEMANTIC_CONTACT_REPORT.md"
MODES = {"needed_R", "context_R", "needed_P"}
ASSESSMENTS = {"supported", "needs_validation", "needs_revision"}


def semantic_data() -> dict:
    corpus = scene_data()
    source = json.loads(ANNOTATIONS.read_text(encoding="utf-8"))
    norm = corpus["normalization"]
    mapping = norm["form_to_lexeme"]
    excluded = set(norm["excluded"])
    events: dict[str, dict] = {}
    for day in corpus["days"]:
        for event in day["r"]:
            events[event["id"]] = {
                **event, "day": day["day"], "mode": "R",
            }
        for event in day["p"]:
            events[event["id"]] = {
                **event, "day": day["day"], "mode": "P",
            }
    audited_ids: set[str] = set()
    summaries = []
    mode_counts = Counter()
    assessment_counts = Counter()
    concept_contacts = defaultdict(lambda: {
        "needed_R": set(), "context_R": set(), "needed_P": set(),
        "r_scenes": set(), "p_scenes": set(),
    })
    anchored_lexemes = defaultdict(lambda: {
        "needed_R_days": set(), "context_R_days": set(),
        "needed_P_example_days": set(),
        "supported_needed_R_days": set(), "supported_needed_P_example_days": set(),
    })
    by_day = [
        {"day": day["day"], "needed_R": 0, "context_R": 0,
         "needed_P": 0, "supported_R": 0, "supported_P": 0,
         "P_needs_revision": 0, "P_needs_validation": 0}
        for day in corpus["days"]
    ]
    for entry in source["annotations"]:
        event_id = entry["event_id"]
        if event_id in audited_ids or event_id not in events:
            raise ValueError(f"Duplicate or unknown semantic event: {event_id}")
        audited_ids.add(event_id)
        event = events[event_id]
        if not event["required"]:
            raise ValueError(f"Optional event cannot be a guaranteed contact: {event_id}")
        mode = entry["mode"]
        if mode not in MODES or (mode == "needed_P") != (event["mode"] == "P"):
            raise ValueError(f"Semantic mode mismatch at {event_id}")
        if entry["assessment"] not in ASSESSMENTS:
            raise ValueError(f"Unknown semantic assessment at {event_id}")
        if entry["concept"] not in source["concepts"]:
            raise ValueError(f"Unknown semantic concept at {event_id}")
        if not entry["anchors"] or len(set(entry["anchors"])) != len(entry["anchors"]):
            raise ValueError(f"Empty or duplicate anchor at {event_id}")
        if not entry["reason"].strip():
            raise ValueError(f"Empty reason at {event_id}")
        text = event.get("de", event.get("example"))
        lemmas = {mapping[word.lower()] for word in WORD.findall(text)
                  if word.lower() not in excluded}
        if not set(entry["anchors"]) <= lemmas:
            raise ValueError(f"Anchors not present in authored R/P text: {event_id}")
        day = event["day"]
        mode_counts[mode] += 1
        assessment_counts[entry["assessment"]] += 1
        row = {**entry, "day": day, "scene_id": event["scene_id"]}
        summaries.append(row)
        by_day[day - 1][mode] += 1
        if entry["assessment"] == "supported":
            if mode == "needed_R":
                by_day[day - 1]["supported_R"] += 1
            elif mode == "needed_P":
                by_day[day - 1]["supported_P"] += 1
        if mode == "needed_P":
            if entry["assessment"] == "needs_revision":
                by_day[day - 1]["P_needs_revision"] += 1
            elif entry["assessment"] == "needs_validation":
                by_day[day - 1]["P_needs_validation"] += 1
        concept_contacts[entry["concept"]][mode].add(day)
        if mode == "needed_P":
            concept_contacts[entry["concept"]]["p_scenes"].add(event["scene_id"])
        elif mode == "needed_R":
            concept_contacts[entry["concept"]]["r_scenes"].add(event["scene_id"])
        for lemma in entry["anchors"]:
            k = {
                "needed_R": "needed_R_days", "context_R": "context_R_days",
                "needed_P": "needed_P_example_days",
            }[mode]
            anchored_lexemes[lemma][k].add(day)
            if entry["assessment"] == "supported":
                if mode == "needed_R":
                    anchored_lexemes[lemma]["supported_needed_R_days"].add(day)
                elif mode == "needed_P":
                    anchored_lexemes[lemma]["supported_needed_P_example_days"].add(day)

    expected_r = sum(e["required"] for day in corpus["days"] for e in day["r"])
    expected_p = sum(e["required"] for day in corpus["days"] for e in day["p"])
    if sum(mode_counts.values()) > expected_r + expected_p:
        raise ValueError("More annotations than mandatory events.")
    concepts = []
    for id_, title in source["concepts"].items():
        contacts = concept_contacts[id_]
        concepts.append({
            "id": id_, "title": title,
            **{mode + "_days": sorted(contacts[mode])
               for mode in ("needed_R", "context_R", "needed_P")},
            "r_scenes": len(contacts["r_scenes"]),
            "p_scenes": len(contacts["p_scenes"]),
        })
    lexemes = [
        {"lexeme": word,
         **{field: sorted(days) for field, days in fields.items()}}
        for word, fields in sorted(anchored_lexemes.items(),
                                   key=lambda item: (item[0].casefold(), item[0]))
    ]
    summaries.sort(key=lambda a: (a["day"], a["event_id"]))
    return {
        "status": "planned_semantic_requirements_not_player_data",
        "exam_day": corpus["exam_day"],
        "counts": {
            "mandatory_R_events": expected_r,
            "mandatory_P_events": expected_p,
            "audited_R_events": mode_counts["needed_R"] + mode_counts["context_R"],
            "audited_P_events": mode_counts["needed_P"],
            "unassessed_R_events": expected_r - mode_counts["needed_R"] - mode_counts["context_R"],
            "unassessed_P_events": expected_p - mode_counts["needed_P"],
            "modes": dict(mode_counts),
            "assessments": dict(assessment_counts),
        },
        "days": by_day,
        "concepts": concepts,
        "lexemes": lexemes,
        "issues": [entry for entry in summaries if entry["assessment"] == "needs_revision"],
        "annotations": summaries,
    }


def render_report(data: dict) -> str:
    t = data["counts"]
    lines = [
        "# Смысловое использование языка в сценах: аудит R/P",
        "",
        "**Статус: авторская проверка выбранных смысловых контактов, не измерение "
        "фактического понимания и не данные игрока.** "
        "Источник: [ACT_SEMANTIC_CONTACT_ANNOTATIONS.json](ACT_SEMANTIC_CONTACT_ANNOTATIONS.json), "
        "сверка с [ACT_DIALOGUE_SITUATIONS.json](ACT_DIALOGUE_SITUATIONS.json). "
        "Нормализация: [ACT_VOCAB_NORMALIZATION.json](ACT_VOCAB_NORMALIZATION.json). "
        "D22 исключён, необязательные контакты не считаются обязательными.",
        "",
        f"**Из {t['mandatory_R_events']} обязательных R-строк** аннотированы "
        f"{t['audited_R_events']} (из них кандидатов смысловой необходимости "
        f"{t['modes'].get('needed_R', 0)}, контекстных "
        f"{t['modes'].get('context_R', 0)}); **{t['unassessed_R_events']} "
        "ещё не классифицированы** — это не значит, что они не нужны.",
        "",
        f"**Из {t['mandatory_P_events']} обязательных P-возможностей** вручную "
        f"разобраны {t['audited_P_events']}, остаются "
        f"{t['unassessed_P_events']} без оценки. **{t['assessments'].get('needs_revision', 0)} "
        "конкретных контрактов требуют исправления перед признанием "
        "самостоятельной продукцией.** Все P-лексемы указаны **только по "
        "авторскому образцу**, их точное воспроизведение не требуется.",
        "",
        "## 1. Число смысловых событий по дням",
        "",
        "| День | R смысл нужен (кандидат) | R контекст | P самостоятельный смысл (кандидат) | R с явной опорой | P с явной опорой | P требует пересмотра |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    for d in data["days"]:
        lines.append(
            f"| D{d['day']:02} | {d['needed_R']} | {d['context_R']} | "
            f"{d['needed_P']} | {d['supported_R']} | {d['supported_P']} | "
            f"{d['P_needs_revision']} |"
        )
    lines += [
        "",
        "## 2. Возвращение коммуникационных смыслов",
        "",
        "Числа R/P — **дни, где нашлась аннотированная кандидатная необходимость**, "
        "не число появлений слова и не подтверждённая память игрока. "
        "Реплики без аннотаций в этот подсчёт не входят.",
        "",
        "| Смысл | Дни R (необходимо) | Дни P (планируемый смысл) | R-сцен | P-сцен |",
        "|---|---|---|---:|---:|",
    ]
    for concept in data["concepts"]:
        r = ", ".join(f"D{d:02}" for d in concept["needed_R_days"]) or "—"
        p = ", ".join(f"D{d:02}" for d in concept["needed_P_days"]) or "—"
        lines.append(f"| {concept['title']} | {r} | {p} | "
                     f"{concept['r_scenes']} | {concept['p_scenes']} |")
    lines += [
        "",
        "## 3. Дефекты, мешающие считать P самостоятельным выражением",
        "",
        "| Событие | День | Смысл | Проблема |",
        "|---|---|---|---|",
    ]
    for issue in data["issues"]:
        lines.append(
            f"| \`{issue['event_id']}\` | D{issue['day']:02} | "
            f"{next(c['title'] for c in data['concepts'] if c['id'] == issue['concept'])} | "
            f"{issue['reason']} |"
        )
    lines += [
        "",
        "## 4. Кандидаты словарных опор с разметкой смысловой необходимости",
        "",
        "**needed_R** — запланировано извлечение значения из немецкой строки; "
        "**P-пример** — смысл, который игрок намерен сообщить, "
        "но он вправе использовать синоним или другую понятную конструкцию. "
        "Отсутствие слова в этой таблице означает отсутствие аннотации, "
        "а не отсутствие слова в сценах.",
        "",
        "| Словарная опора | Дни needed_R | Дни P-смысловых примеров | Дни R контекста |",
        "|---|---|---|---|",
    ]
    for word in data["lexemes"]:
        r = ", ".join(f"D{d:02}" for d in word["needed_R_days"]) or "—"
        p = ", ".join(f"D{d:02}" for d in word["needed_P_example_days"]) or "—"
        c = ", ".join(f"D{d:02}" for d in word["context_R_days"]) or "—"
        lines.append(f"| \`{word['lexeme']}\` | {r} | {p} | {c} |")
    lines += [
        "",
        "## 5. Ограничения и проверка",
        "",
        "- Доказанная необходимость отдельной лексемы потребовала бы теста "
        "альтернативных путей, визуальных подсказок и возможности догадаться "
        "по контексту; текущие аннотации — **проектные гипотезы**.",
        "- Независимая P-продукция — требование **смысла**, не фиксированного "
        "слова и не точной грамматики; авторский пример не whitelist парсера.",
        "- «С явной опорой» означает внутренне согласованный контракт "
        "сцены, **не результат пользовательского тестирования**.",
        "- Контекстные реплики (например, спор о воде) могут быть важны "
        "для персонажей, хотя не закрывают обязательную языковую задачу.",
        "- Неаннотированные сообщения остаются **не проверены**, не "
        "превращаются автоматически в «бессмысленные» или «необязательные».",
        "- Генератор пересчитывает числа при правке сцены и проверяет, "
        "что используемые лексические опоры действительно есть в строках.",
        "- Следующий шаг — исправить конкретные проблемные информационные "
        "контракты и проверить смысловую необходимость в вариантах диалога, "
        "а затем пересчитать без фиксации 22 дней как нормы.",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    text = render_report(semantic_data())
    if args.check:
        if not REPORT.exists() or REPORT.read_text(encoding="utf-8") != text:
            print("Semantic contacts report is stale.", file=sys.stderr)
            return 1
        print("Semantic contacts report is current.")
        return 0
    if not REPORT.exists() or REPORT.read_text(encoding="utf-8") != text:
        REPORT.write_text(text, encoding="utf-8")
        print("Updated", REPORT)
    else:
        print("Semantic contacts report already current.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

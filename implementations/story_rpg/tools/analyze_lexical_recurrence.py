#!/usr/bin/env python3
"""Audit authored German word recurrence across provisional story-day slots.

Required NPC/document text is the only guaranteed R source. P examples are
tracked separately and are NOT player telemetry or proof of productive recall.
No spaced-repetition schedule or arbitrary "mastered" state is inferred.
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

from scene_corpus import scene_data, WORD

DOCS = Path(__file__).resolve().parents[1] / "docs"
ROLES = DOCS / "ACT_LEXICAL_ROLE_CANDIDATES.json"
REPORT = DOCS / "ACT_LEXICAL_RECURRENCE_REPORT.md"
COHORTS = (
    ("early", "D01–D04", 1, 4),
    ("middle_a", "D05–D10", 5, 10),
    ("middle_b", "D11–D17", 11, 17),
    ("late", "D18–D21", 18, 21),
)
ROLLING_DAYS = 4
REVIEW_GAP = 5  # Story-day slots with no mandatory R contact, NOT an SRS interval.


def recurrence_data() -> dict:
    data = scene_data()
    rules = json.loads(ROLES.read_text(encoding="utf-8"))
    norm = data["normalization"]
    mapping = norm["form_to_lexeme"]
    excluded = set(norm["excluded"])
    candidate_core = rules["candidate_core"]
    candidate_situational = rules["candidate_situational"]
    if len(set(candidate_core)) != len(candidate_core):
        raise ValueError("Repeated core lexeme in role list.")
    if len(set(candidate_situational)) != len(candidate_situational):
        raise ValueError("Repeated situational lexeme in role list.")
    if set(candidate_core) & set(candidate_situational):
        raise ValueError("A lexeme cannot belong to two proposed roles.")
    if not (set(candidate_core) | set(candidate_situational)) <= set(mapping.values()):
        raise ValueError("Lexical-role list refers to an unknown normalized lexeme.")
    roles = {lexeme: "candidate_core" for lexeme in candidate_core}
    roles.update({lexeme: "candidate_situational" for lexeme in candidate_situational})

    per_day: list[dict] = []
    encountered: dict[str, dict] = {}
    r_sets: list[set[str]] = []
    exam_day = data["exam_day"]
    for day in data["days"]:
        d = day["day"]
        r_tokens: list[str] = []
        p_tokens: list[str] = []
        for event in day["r"]:
            if not event["required"]:
                continue
            for word in WORD.findall(event["de"]):
                form = word.lower()
                if form not in excluded:
                    r_tokens.append(mapping[form])
        for event in day["p"]:
            if event["required"] and event["kind"] == "dialog":
                for word in WORD.findall(event["example"]):
                    form = word.lower()
                    if form not in excluded:
                        p_tokens.append(mapping[form])
        seen_r = set(r_tokens)
        seen_p = set(p_tokens)
        for lexeme in seen_r | seen_p:
            item = encountered.setdefault(
                lexeme, {"lexeme": lexeme, "first_r_day": None,
                         "r_days": [], "p_example_days": [], "r_tokens": 0,
                         "role": roles.get(lexeme, "unclassified")}
            )
            if lexeme in seen_r:
                item["r_days"].append(d)
                if item["first_r_day"] is None:
                    item["first_r_day"] = d
            if lexeme in seen_p:
                item["p_example_days"].append(d)
        counts = Counter(r_tokens)
        for lexeme, count in counts.items():
            encountered[lexeme]["r_tokens"] += count

        r_sets.append(seen_r)
        window = set().union(*r_sets[-ROLLING_DAYS:])
        by_cohort = {}
        for key, _label, lower, upper in COHORTS:
            by_cohort[key] = sum(
                lower <= encountered[lexeme]["first_r_day"] <= upper
                for lexeme in seen_r
                if encountered[lexeme]["first_r_day"] is not None
            )
        if sum(by_cohort.values()) != len(seen_r):
            raise ValueError(f"Cohort counts do not reconcile on D{d:02}.")
        old_lexemes = {
            lexeme for lexeme in seen_r
            if encountered[lexeme]["first_r_day"] is not None
            and d - encountered[lexeme]["first_r_day"] >= REVIEW_GAP
        }
        per_day.append({
            "day": d,
            "r_distinct": len(seen_r),
            "r_tokens_without_excluded": len(r_tokens),
            "rolling_4_r_distinct": len(window),
            "old_r_distinct": len(old_lexemes),
            "cohorts": by_cohort,
            "core_r_distinct": len(seen_r & set(candidate_core)),
            "situational_r_distinct": len(seen_r & set(candidate_situational)),
        })
    end = exam_day - 1
    lexemes = []
    for item in encountered.values():
        r_days = item["r_days"]
        if not r_days:
            # P-only example does not count towards guaranteed R vocabulary.
            continue
        first_r = r_days[0]
        longest_interior = max(
            (b - a - 1 for a, b in zip(r_days, r_days[1:])),
            default=0,
        )
        trailing = end - r_days[-1]
        row = {
            **item,
            "last_r_day": r_days[-1],
            "r_distinct_days": len(r_days),
            "max_interior_absent_days": longest_interior,
            "end_absent_days": trailing,
            "review_gap": longest_interior >= REVIEW_GAP or trailing >= REVIEW_GAP,
            "never_revisited_r": len(r_days) == 1,
            "cohort": next(
                key for key, _label, lower, upper in COHORTS
                if lower <= first_r <= upper
            ),
        }
        lexemes.append(row)
    lexemes.sort(key=lambda x: (x["lexeme"].casefold(), x["lexeme"]))
    r_total = len(lexemes)
    if r_total != len(set().union(*r_sets)):
        raise ValueError("Distinct R counts disagree.")
    by_role = {}
    last_window = set().union(*r_sets[-ROLLING_DAYS:])
    for role in ("candidate_core", "candidate_situational", "unclassified"):
        selected = [w for w in lexemes if w["role"] == role]
        by_role[role] = {
            "total": len(selected),
            "seen_in_last_4": sum(w["lexeme"] in last_window for w in selected),
            "end_absent_5_plus": sum(w["end_absent_days"] >= REVIEW_GAP for w in selected),
            "never_revisited_r": sum(w["never_revisited_r"] for w in selected),
        }
    if sum(r["total"] for r in by_role.values()) != r_total:
        raise ValueError("Role totals disagree.")
    early = [w for w in lexemes if w["first_r_day"] <= 4]
    return {
        "status": "authored_mandatory_R_exposure_not_memory",
        "exam_day": exam_day,
        "rolling_days": ROLLING_DAYS,
        "review_gap": REVIEW_GAP,
        "cohorts": [{"id": key, "label": label, "from": lower, "to": upper}
                    for key, label, lower, upper in COHORTS],
        "days": per_day,
        "lexemes": lexemes,
        "by_role": by_role,
        "summary": {
            "total_r_lexemes": r_total,
            "early_d01_d04": len(early),
            "early_seen_d18_d21": sum(
                any(day >= 18 for day in w["r_days"]) for w in early
            ),
            "early_not_seen_d18_d21": sum(
                not any(day >= 18 for day in w["r_days"]) for w in early
            ),
        },
    }


def render_report(report: dict) -> str:
    summaries = report["summary"]
    by_role = report["by_role"]
    lines = [
        "# Возвращение слов в первом акте: сценарный аудит",
        "",
        "**Статус: вычислено из авторских обязательных R-реплик D01–D21; "
        "не тест памяти игрока и не SRS.** Источник: "
        "[ACT_DIALOGUE_SITUATIONS.json](ACT_DIALOGUE_SITUATIONS.json). "
        "Нормализация: [ACT_VOCAB_NORMALIZATION.json](ACT_VOCAB_NORMALIZATION.json). "
        "Роли слов: [ACT_LEXICAL_ROLE_CANDIDATES.json](ACT_LEXICAL_ROLE_CANDIDATES.json) "
        "— **неутверждённые гипотезы**. Дополнительные сцены исключены; "
        "P отражает только авторские примеры, а не ответы игрока.",
        "",
        f"К D21: **{summaries['total_r_lexemes']}** R-лексемы. Из "
        f"**{summaries['early_d01_d04']}** впервые встреченных в D01–D04 "
        f"**{summaries['early_seen_d18_d21']}** повторно появляются в D18–D21, "
        f"**{summaries['early_not_seen_d18_d21']}** — нет.",
        "",
        "## 1. Когорты по первому R-контакту",
        "",
        "Значение в колонке = **разные лексемы, встречающиеся в R данного дня**, "
        "сгруппированные по дню их первого R-контакта. "
        "Не число всех словоупотреблений и не число выученных слов.",
        "",
        "| День | D01–D04 | D05–D10 | D11–D17 | D18–D21 | Разных R-лексем за день | За последние 4 дня (объединение) | Старые, первое R ≥5 слотов назад |",
        "|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for day in report["days"]:
        g = day["cohorts"]
        lines.append(
            f"| D{day['day']:02} | {g['early']} | {g['middle_a']} | "
            f"{g['middle_b']} | {g['late']} | {day['r_distinct']} | "
            f"{day['rolling_4_r_distinct']} | {day['old_r_distinct']} |"
        )
    lines += [
        "",
        "## 2. Предварительные роли слов: не оценки усвоения",
        "",
        "| Роль | Всего разных R-лексем | Встречаются в R за D18–D21 | Нет R пять и более последних слотов | R только в одном дне |",
        "|---|---:|---:|---:|---:|",
    ]
    names = {"candidate_core": "Кандидаты постоянной основы",
             "candidate_situational": "Кандидаты ситуационного запаса",
             "unclassified": "Не классифицированы"}
    for key, title in names.items():
        r = by_role[key]
        lines.append(
            f"| {title} | {r['total']} | {r['seen_in_last_4']} | "
            f"{r['end_absent_5_plus']} | {r['never_revisited_r']} |"
        )
    lines += [
        "",
        "## 3. Список кандидатов постоянной основы",
        "",
        "Отсутствие в конце акта — **повод для авторского разбора**, "
        "не команда вставить слово в диалог; первые R-употребления "
        "не гарантируют понимания. Пробел между R-контактами — число "
        "**пустых сценарных слотов** между двумя днями с обязательным R. "
        "«В конце не встречалось» — количество слотов после последнего R до D21.",
        "",
        "| Лексема | Первый R | Последний R | R-дней | Макс. пустых слотов между R | Пустых слотов после последнего R | Дни P-примеров |",
        "|---|---:|---:|---:|---:|---:|---|",
    ]
    core = sorted((x for x in report["lexemes"] if x["role"] == "candidate_core"),
                  key=lambda x: (-x["end_absent_days"], x["lexeme"].casefold()))
    for w in core:
        p = ", ".join(f"D{n:02}" for n in w["p_example_days"]) or "—"
        lines.append(
            f"| \`{w['lexeme']}\` | D{w['first_r_day']:02} | "
            f"D{w['last_r_day']:02} | {w['r_distinct_days']} | "
            f"{w['max_interior_absent_days']} | {w['end_absent_days']} | {p} |"
        )
    lines += [
        "",
        "## 4. Как интерпретировать отсутствие",
        "",
        "- **Разные R-лексемы в данном дне** = встреченные хотя бы раз в "
        "обязательном немецком тексте, включая фоновые/служебные слова.",
        "- **P-примеры** не добавляются к обязательным R-контактам. "
        "Слово может не использоваться в авторском примере, хотя игрок "
        "выразит нужный смысл синонимом.",
        f"- **{REVIEW_GAP} пустых дневных слотов** — только фильтр для просмотра, "
        "не забывание и не рекомендованный интервал.",
        "- Перерывы в **проектных днях** не соответствуют времени в реальном мире.",
        "- Кандидаты ядра и ситуационной лексики требуют авторского утверждения; "
        "слова без назначенной роли остаются видны и не считаются ненужными.",
        "- Для существенной проверки нужны отдельные **needed_R/needed_P** "
        "контракты и варианты диалогов, чтобы не принимать автоматические "
        "упоминания слов за осмысленную практику.",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true",
                        help="Verify recurrence report matches scene corpus and role list")
    args = parser.parse_args()
    report = render_report(recurrence_data())
    if args.check:
        if not REPORT.exists() or REPORT.read_text(encoding="utf-8") != report:
            print("Lexical recurrence report is stale.", file=sys.stderr)
            return 1
        print("Lexical recurrence report is current.")
        return 0
    if not REPORT.exists() or REPORT.read_text(encoding="utf-8") != report:
        REPORT.write_text(report, encoding="utf-8")
        print(f"Updated {REPORT}")
    else:
        print("Lexical recurrence report already current.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

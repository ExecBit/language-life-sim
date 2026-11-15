#!/usr/bin/env python3
"""Recompute story-language load from the canonical situation contracts.

No counted dialogue is taken from the previous toy pilot. The main-path
minimum excludes optional scenes and optional turns; output example words are
NOT the player's actual typed output. Run from repository root:
  python implementations/story_rpg/tools/analyze_dialogue_load.py
  python implementations/story_rpg/tools/analyze_dialogue_load.py --check
"""
from __future__ import annotations

import argparse
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

from build_day_progression_dashboard import vocab_data
from scene_corpus import scene_data, WORD

DOCS = Path(__file__).resolve().parents[1] / "docs"
LEXICON = DOCS / "LANGUAGE_LEXICON.md"
REPORT = DOCS / "ACT_DIALOGUE_LOAD_REPORT.md"


def names() -> dict[str, str]:
    result = {}
    for line in LEXICON.read_text(encoding="utf-8").splitlines():
        match = re.match(r"^\|\s*(\d{1,2})\s*\|", line)
        if match:
            fields = [x.strip() for x in line.split("|")[1:-1]]
            if len(fields) >= 3:
                result[f"{int(match.group(1)):02}"] = fields[2]
    if len(result) != 29:
        raise ValueError(f"Expected 29 thematic groups; found {len(result)}")
    return result


def analyze(data: dict) -> dict:
    stats = defaultdict(lambda: {"r": 0, "p": 0, "r_days": set(), "p_days": set(),
                                 "r_contexts": set(), "p_contexts": set()})
    day_rows = []
    total = Counter()
    tag_map = data["normalization"]["primary_group_for_form"]
    for day in data["days"]:
        row = Counter({"day": day["day"]})
        row["scenes_required"] = sum(bool(s["required"]) for s in day["scenes"])
        row["scenes_optional"] = len(day["scenes"]) - row["scenes_required"]
        for event in day["r"]:
            tokens = [x.lower() for x in WORD.findall(event["de"])]
            if not event["required"]:
                row["r_optional_events"] += 1
                row["r_optional_words"] += len(tokens)
                continue
            row["r_events"] += 1
            row["r_words"] += len(tokens)
            for token in tokens:
                group = tag_map.get(token)
                if group:
                    row["r_marked"] += 1
                    s = stats[group]
                    s["r"] += 1
                    s["r_days"].add(day["day"])
                    s["r_contexts"].add(event["context"])
        for event in day["p"]:
            count = len(WORD.findall(event["example"]))
            if not event["required"]:
                row["p_optional"] += 1
                row["p_optional_examples"] += count
                continue
            row["p_" + event["kind"]] += 1
            if event["kind"] == "dialog":
                row["p_example_words"] += count
            for slot in event["slots"]:
                group = slot["group"]
                row["p_slots"] += 1
                s = stats[group]
                s["p"] += 1
                s["p_days"].add(day["day"])
                s["p_contexts"].add(event["context"])
        day_rows.append(row)
        total.update({k: v for k, v in row.items() if k != "day"})
    return {"days": day_rows, "totals": total, "groups": stats}


def render(data: dict, a: dict, group_names: dict[str, str], vocabulary: dict) -> str:
    t = a["totals"]
    vocab = vocabulary["days"]
    lines = [
        "# Первый акт: языковая нагрузка связных игровых ситуаций",
        "",
        "**Статус: авторский сценарный корпус v0.2, не реализованные или проверенные игроками диалоги.** "
        "Основной источник: [ACT_DIALOGUE_SITUATIONS.json](ACT_DIALOGUE_SITUATIONS.json). "
        "Прежний [пробный корпус](ACT_DIALOGUE_REFERENCE_CORPUS.json) не участвует в текущих графиках. "
        "D01–D21 — предварительные сценарные контейнеры, **D22 — предполагаемый экзамен и исключён из практики**.",
        "",
        "## 1. Общий объём гарантированного основного пути",
        "",
        f"**Сцены:** {t['scenes_required']} обязательных, {t['scenes_optional']} факультативных. "
        f"**Input (R):** {t['r_events']} обязательных реплик и записей / {t['r_words']} немецких словоупотреблений; "
        f"{t['r_optional_events']} факультативных сообщений / {t['r_optional_words']} слов отдельно. "
        f"**Output (P):** {t['p_dialog']} обязательных случаев свободного ввода, "
        f"{t['p_form']} форма(ы), {t['p_slots']} тематических смысловых компонентов, "
        f"{t['p_example_words']} слов только в авторских образцах ответов; "
        f"{t['p_optional']} факультативных возможностей / {t['p_optional_examples']} слов примеров.",
        "",
        "**Важные ограничения:** подсчитано то, что гарантированно показано в авторских обязательных сценах, "
        "а не количество обязательных для понимания слов, и не реальные слова пользователя. "
        "Короткие реплики возможны в нескольких вариантах, и их фактический объём заранее неизвестен. "
        "Число P-слотов отражает тематическую разметку значимых компонентов и пока не является "
        "независимой грамматической рубрикой; одна реплика может иметь несколько групп.",
        "",
        "## 2. По дням",
        "",
        "| День | Сцены обяз./доп. | R реплик | R слов | R темат. слов | P свободных | P форм | P компонентов | P слов в примерах | R слов доп. |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for d in a["days"]:
        lines.append(
            f"| D{d['day']:02} | {d['scenes_required']}/{d['scenes_optional']} | "
            f"{d['r_events']} | {d['r_words']} | {d['r_marked']} | {d['p_dialog']} | "
            f"{d['p_form']} | {d['p_slots']} | {d['p_example_words']} | "
            f"{d['r_optional_words']} |"
        )
    lines += [
        "",
        "## 3. Тематические группы: доли и возвращения",
        "",
        "R-доля = число **тематически распознанных** входящих словоупотреблений группы / "
        "общее число тематически распознанных R-словоупотреблений. "
        "P-доля = число размеченных P-смысловых компонентов группы / все такие компоненты. "
        "Это **не** доля от словаря конкретной группы, а разные условные показатели. "
        "Они не доказывают закрепление и не заменяют накопительный словарь.",
        "",
        "| № | Тематическая группа | R слов | R-доля | P компонентов | P-доля | Дни обязательного R/P |",
        "|---|---|---:|---:|---:|---:|---|",
    ]
    missing = []
    for group, title in sorted(group_names.items()):
        s = a["groups"].get(group)
        r = s["r"] if s else 0
        p = s["p"] if s else 0
        if r + p == 0:
            missing.append(group)
        days = sorted((s["r_days"] | s["p_days"]) if s else [])
        lines.append(
            f"| {group} | {title} | {r} | "
            f"{(100 * r / t['r_marked'] if t['r_marked'] else 0):.1f}% | "
            f"{p} | {(100 * p / t['p_slots'] if t['p_slots'] else 0):.1f}% | "
            f"{', '.join(f'D{n:02}' for n in days) if days else '—'} |"
        )
    lines += [
        "",
        f"**Группы без обязательных контактов в этом корпусе:** {', '.join(missing) if missing else 'нет'}. "
        "Их статус как обязательного словарного ядра не утверждён. "
        "Нельзя компенсировать пробелы перечислением групп в F1 или добавлением произвольных диалогов.",
        "",
        "## 4. Общий словарь и его рост, без тематических фильтров",
        "",
        "Слова нормализованы по [ACT_VOCAB_NORMALIZATION.json](ACT_VOCAB_NORMALIZATION.json). "
        "Это **наблюдаемый словарь авторских реплик**, не активный запас знаний игрока. "
        "Лексемы, написания и повторные словоупотребления различаются; технические A/B "
        "и имя Lena исключены только из уникального словаря.",
        "",
        "| День | Новые R-лексемы | R повторы | Накоплено R-лексем | Разные R-словоформы | R+P примеры: лексемы |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for item in vocab:
        lines.append(
            f"| D{item['day']:02} | {item['r_new_lexemes']} | {item['r_repeated_words']} | "
            f"{item['r_cumulative_lexemes']} | {item['r_cumulative_forms']} | "
            f"{item['sample_cumulative_lexemes']} |"
        )
    lines += [
        "",
        f"**К D21:** {vocab[-1]['r_cumulative_lexemes']} R-лексем, "
        f"{vocab[-1]['r_cumulative_forms']} разных R-словоформ; "
        f"{vocab[-1]['sample_cumulative_lexemes']} лексем при включении P-образцов. "
        "Эта кривая отражает только написанный авторский материал, а не желаемый норматив.",
        "",
        "## 5. Сами сцены: реплики, самостоятельные смыслы и последствия",
        "",
        "Примеры P — **не whitelist парсера**. Вводить можно иную понятную фразу, "
        "пока сохраняются существенные предмет, состояние, адресат, отрицание и время. "
        "R — текст, который встретится на соответствующем пути, не каждое слово обязано пониматься сразу.",
        "",
    ]
    for day in data["days"]:
        lines.append(f"### D{day['day']:02} · {day['phase']}")
        lines.append("")
        for scene in day["scenes"]:
            marker = "обязательная" if scene["required"] else "факультативная"
            lines += [
                f"**{scene['id']} · {scene['title']} ({marker})**",
                "",
                f"Место: {scene['location']}. Участники: {scene['actors']}. "
                f"Причина: {scene['trigger']}.",
                "",
                f"Игроку доступны данные: {scene['evidence']}",
                "",
            ]
            for idx, event in enumerate(scene["r"], start=1):
                lines.append(f"- **R{idx}, {event['speaker']}:** \`{event['de']}\`")
                for p in scene["p"]:
                    if p["after_r"] == idx:
                        state = "обязательно" if p["required"] else "дополнительно"
                        typ = "заполнение формы" if p["kind"] == "form" else "свободный ввод"
                        lines.append(
                            f"- **P ({typ}, {state}):** {p['goal']}. "
                            f"Пример: \`{p['example']}\`. Контраст: {p['contrast']}."
                        )
            lines += ["", f"**Исход сцены:** {scene['consequence']}", ""]
    lines += [
        "## 6. Проверка качества и открытые ограничения",
        "",
        "- Авторские реплики **не проверены на реальном абсолютном A0**. Некоторые ранние фразы содержат формы из поздних горизонтов, которые могут быть фоновыми, но нельзя требовать их полного понимания при первом контакте.",
        "- **Не смоделированы полные ветви непонимания, перестановки сцен, повторные обращения и все варианты формулировок.** Это сценарные контракты, не финальный сценарный граф и не реализованный парсер.",
        "- В каждом P-контракте нужно подтвердить, что игрок **обладает уникальным фактом**, неизвестным адресату. Иначе реплику можно угадать или выбрать кнопку без немецкого.",
        "- Разделение NPC-полномочий сохраняется: герой не командует снабженцем, навигатором или капитаном; конфликт биолога и снабженца не решается одним ответом героя.",
        "- Отдельные бытовые темы (например, покупки и транспорт) по-прежнему могут отсутствовать на корабле. Надо решить, какие словарные группы действительно обязательны для первого акта, а какие только расширяют содержание F1.",
        "- Экзамен D22 не участвует в расчёте подготовки. **22 дня всё ещё гипотеза**, не следует выводить длительность из общего числа реплик или процентов.",
        "- Для следующего методического прохода: проверить холодный старт A0, разнести обязательность **получения** текста и обязательность **понять** конкретный факт, добавить допустимые ветви диалога и оценить содержательные возвращения поздних групп.",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="Verify the report matches authored scene data.")
    args = parser.parse_args()
    data = scene_data()
    new_report = render(data, analyze(data), names(), vocab_data())
    if args.check:
        if not REPORT.exists() or REPORT.read_text(encoding="utf-8") != new_report:
            print(f"Report out of date: {REPORT}", file=sys.stderr)
            return 1
        print("Scene load report is consistent with the canonical data.")
        return 0
    if not REPORT.exists() or REPORT.read_text(encoding="utf-8") != new_report:
        REPORT.write_text(new_report, encoding="utf-8")
    print("Scene load report generated.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
